extends Node3D
## Builds walkable tunnels between two holes in the terrain.
##
## Each tunnel is a tube: a ramp down from the first hole, a level run underground, then a
## ramp back up to the second hole. The ramps are shallow enough to walk (CharacterBody3D
## refuses anything steeper than floor_max_angle, 45 degrees by default).

@export var radius := 3.0
## Crater wall angle - shallow enough to walk down and back up (floor_max_angle is 45).
@export var entry_slope_degrees := 35.0
## How far the crater rim tucks under the terrain, so the two surfaces overlap instead of
## meeting edge to edge (a seam a capsule can slip through).
@export var rim_overlap := 1.2
@export var depth := 6.0        ## how far below the lower hole the level run sits
@export var ring_segments := 16
@export var light_spacing := 14.0

var paths: Array[Array] = []   ## centreline of each tunnel, for debugging probes
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.30, 0.27, 0.24).srgb_to_linear()
	_material.roughness = 1.0
	# seen from inside, so draw both sides
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED


## `holes` are Vector3(world_x, world_z, radius) as used by terrain.gd.
func build(terrain: Node3D, holes: Array[Vector3]) -> void:
	for i in range(0, holes.size() - 1, 2):
		_build_tunnel(terrain, holes[i], holes[i + 1])


func _build_tunnel(terrain: Node3D, from_hole: Vector3, to_hole: Vector3) -> void:
	var a := Vector3(from_hole.x, terrain.height_at(from_hole.x, from_hole.y), from_hole.y)
	var b := Vector3(to_hole.x, terrain.height_at(to_hole.x, to_hole.y), to_hole.y)
	var towards := (Vector3(b.x - a.x, 0.0, b.z - a.z)).normalized()

	# The crater IS the ramp: a cone at `entry_slope` from the rim down to the tunnel floor.
	# Its size is fixed by the hole cut in the terrain, and the depth follows from it - doing
	# it the other way round let the crater and the hole disagree, leaving a gap to fall
	# through on one layout and a dome to walk over on another.
	var mouth_a: float = from_hole.z + rim_overlap
	var mouth_b: float = to_hole.z + rim_overlap
	var drop_a: float = (mouth_a - radius) * tan(deg_to_rad(entry_slope_degrees))
	var drop_b: float = (mouth_b - radius) * tan(deg_to_rad(entry_slope_degrees))
	var floor_a: float = a.y - drop_a
	var floor_b: float = b.y - drop_b
	var lead_in: float = radius * 1.5

	var path: Array[Vector3] = [
		Vector3(a.x, a.y + 0.3, a.z),                                   # rim
		Vector3(a.x, floor_a, a.z),                                     # bottom of the crater
		Vector3(a.x, floor_a + radius, a.z) + towards * lead_in,        # into the tube
		Vector3(b.x, floor_b + radius, b.z) - towards * lead_in,        # out of the tube
		Vector3(b.x, floor_b, b.z),
		Vector3(b.x, b.y + 0.3, b.z),
	]
	var radii: Array[float] = [mouth_a, radius, radius, radius, radius, mouth_b]
	# Sharp corners are walls: rounding them keeps every slope inside the walkable range.
	var smoothed := _round_corners(path, radii)
	path = smoothed[0]
	radii = smoothed[1]
	paths.append(path)

	var mesh := _tube_mesh(path, radii, terrain)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _material
	add_child(instance)

	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	# A tube is seen (and walked on) from the inside. Trimesh shapes ignore back faces by
	# default, so without this the player falls straight through the tunnel floor.
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

	_add_lights(path)


## Replaces each interior corner with a short quadratic Bezier, so direction changes happen
## over a few metres instead of instantly. Returns [path, radii].
func _round_corners(path: Array[Vector3], radii: Array[float], blend := 5.0, steps := 4) -> Array:
	var out_path: Array[Vector3] = [path[0]]
	var out_radii: Array[float] = [radii[0]]
	for i in range(1, path.size() - 1):
		# Only round bends within the tube itself. Rounding the cone-to-tube junction pulled
		# the crater's lower wall in to tube width, turning it into an unclimbable shaft.
		if not (is_equal_approx(radii[i - 1], radii[i]) and is_equal_approx(radii[i], radii[i + 1])):
			out_path.append(path[i])
			out_radii.append(radii[i])
			continue
		var previous: Vector3 = path[i - 1]
		var corner: Vector3 = path[i]
		var next: Vector3 = path[i + 1]
		var in_length: float = minf(blend, previous.distance_to(corner) * 0.45)
		var out_length: float = minf(blend, corner.distance_to(next) * 0.45)
		var start: Vector3 = corner + (previous - corner).normalized() * in_length
		var end: Vector3 = corner + (next - corner).normalized() * out_length
		for s in range(steps + 1):
			var t := float(s) / steps
			# quadratic Bezier start -> corner -> end
			var point: Vector3 = start.lerp(corner, t).lerp(corner.lerp(end, t), t)
			out_path.append(point)
			# the radius belongs to the corner, not to the neighbours: interpolating it here
			# put a mouth-sized disc underground and sealed the tunnel off
			out_radii.append(radii[i])
	out_path.append(path[path.size() - 1])
	out_radii.append(radii[radii.size() - 1])
	return [out_path, out_radii]


## A tube of `ring_segments` sides following the path, with rings aligned to the average
## direction at each corner so the joints do not pinch.
func _tube_mesh(path: Array[Vector3], radii: Array[float], terrain: Node3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[Array] = []
	for i in path.size():
		var forward: Vector3
		if i == 0:
			forward = (path[1] - path[0]).normalized()
		elif i == path.size() - 1:
			forward = (path[i] - path[i - 1]).normalized()
		else:
			forward = ((path[i] - path[i - 1]).normalized() + (path[i + 1] - path[i]).normalized()).normalized()
		var ring := _ring(path[i], forward, radii[i])
		if i == 0 or i == path.size() - 1:
			# the mouth ring follows the ground around the rim, otherwise it sticks up as a
			# wall on the uphill side - and a CharacterBody3D cannot step over a lip
			for k in ring.size():
				var p: Vector3 = ring[k]
				ring[k] = Vector3(p.x, terrain.height_at(p.x, p.z) - 0.15, p.z)
		rings.append(ring)

	for i in range(rings.size() - 1):
		var current: Array = rings[i]
		var next: Array = rings[i + 1]
		for s in ring_segments:
			var s2 := (s + 1) % ring_segments
			# wound so the faces point inwards, towards whoever is walking through
			for p: Vector3 in [current[s], next[s], next[s2], current[s], next[s2], current[s2]]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


func _ring(centre: Vector3, forward: Vector3, ring_radius: float) -> Array:
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.95:
		up = Vector3.FORWARD
	var right := forward.cross(up).normalized()
	var real_up := right.cross(forward).normalized()
	var points: Array[Vector3] = []
	for s in ring_segments:
		var angle := TAU * s / ring_segments
		points.append(centre + (right * cos(angle) + real_up * sin(angle)) * ring_radius)
	return points


## A few dim lights so the tunnel is not pitch black.
func _add_lights(path: Array[Vector3]) -> void:
	var walked := 0.0
	for i in range(path.size() - 1):
		var segment := path[i + 1] - path[i]
		var length := segment.length()
		var travelled := 0.0
		while travelled < length:
			if walked >= light_spacing:
				var light := OmniLight3D.new()
				light.position = path[i] + segment.normalized() * travelled + Vector3.UP * (radius * 0.5)
				light.light_color = Color(1.0, 0.86, 0.66)
				light.light_energy = 2.5
				light.omni_range = radius * 4.0
				add_child(light)
				walked = 0.0
			var stepped: float = minf(2.0, length - travelled)
			travelled += stepped
			walked += stepped
