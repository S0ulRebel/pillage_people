@tool
extends Path3D
class_name Tunnel
## A tunnel you place in the scene: draw a curve, set a radius, done.
##
## The tube is extruded along the curve and stops where it breaks the surface, and the
## terrain is cut to exactly the shape of the tube where it emerges - so the opening always
## matches the tunnel, at any slope, with nothing to line up by hand.

@export var radius := 3.0:
	set(value):
		radius = value
		_rebuild()
@export var ring_segments := 20
@export var sample_spacing := 1.5      ## distance between rings along the curve
@export var overshoot := 1.5           ## how far the tube pokes past the surface, so the
									   ## cut and the tube overlap instead of meeting exactly
## The terrain is cut a little inside the tube wall, so ground and tube overlap rather than
## meeting exactly on the same surface (a seam the player can slip through).
@export var cut_margin := 0.4
@export var light_spacing := 12.0
@export var wall_colour := Color(0.30, 0.27, 0.24)

var _terrain: Node3D
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
## Centres of the rings actually built, in world space. The terrain is cut against these,
## not against the raw curve: the curve also runs above ground, and cutting there would
## open holes with no tube underneath them.
var _stretches: Array[PackedVector3Array] = []


## Called by the terrain once it knows its heights; tunnels cannot be built before that.
func build(terrain: Node3D) -> void:
	_terrain = terrain
	_rebuild()


## How far outside the tube a world point is: negative inside, zero on the wall.
## The terrain uses this to decide what to cut, so the hole is always the tube's own shape.
func distance_outside(world_point: Vector3) -> float:
	var best := 1e9
	for stretch in _stretches:
		# Skip the first and last segment: the distance test rounds off the ends, so cutting
		# against them removes ground just past the mouth where there is no tube to stand on.
		var from: int = 1 if stretch.size() > 3 else 0
		var to: int = stretch.size() - 2 if stretch.size() > 3 else stretch.size() - 1
		for i in range(from, to):
			best = minf(best, _distance_to_segment(world_point, stretch[i], stretch[i + 1]))
	return best - (radius - cut_margin)


func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab: Vector3 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared < 0.0001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _rebuild() -> void:
	if _terrain == null or curve == null or curve.point_count < 2:
		return
	for child in get_children():
		child.queue_free()

	_stretches = _underground_stretches()
	if _stretches.is_empty():
		push_warning("Tunnel %s never goes underground - nothing to build" % name)
		return

	var mesh := _tube_mesh(_stretches)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = wall_colour.srgb_to_linear()
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED   # walked on from the inside
	_mesh_instance.material_override = material
	add_child(_mesh_instance)

	_body = StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	# trimesh shapes ignore back faces by default, and a tube is all back faces from inside
	shape.backface_collision = true
	collider.shape = shape
	_body.add_child(collider)
	add_child(_body)

	for stretch in _stretches:
		_add_lights(stretch)


## The curve can dip underground more than once (a tunnel crossing a ridge surfaces in the
## middle). Each underground stretch is built - and cut - separately: joining them would put
## tube over a hilltop and, worse, cut the ground beneath a piece of tube that is up in the air.
func _underground_stretches() -> Array[PackedVector3Array]:
	var stretches: Array[PackedVector3Array] = []
	var current := PackedVector3Array()
	var length := curve.get_baked_length()
	var distance := 0.0
	var was_under := false
	while distance <= length:
		var world: Vector3 = to_global(curve.sample_baked(distance))
		# Carry on until the centre of the tube reaches the surface: stopping while the whole
		# ring is still buried leaves the mouth covered by ground, with no way in.
		var under: bool = world.y < _terrain.height_at(world.x, world.z)
		if under and not was_under:
			# step back out so the tube starts above ground and overlaps the cut
			current = PackedVector3Array()
			current.append(to_global(curve.sample_baked(maxf(0.0, distance - overshoot))))
		if under:
			current.append(world)
		elif was_under:
			current.append(to_global(curve.sample_baked(minf(length, distance + overshoot))))
			if current.size() >= 2:
				stretches.append(current)
			current = PackedVector3Array()
		was_under = under
		distance += sample_spacing
	if was_under and current.size() >= 2:
		stretches.append(current)
	return stretches


func _tube_mesh(stretches: Array[PackedVector3Array]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for centres in stretches:
		_add_tube(st, centres)
	st.generate_normals()
	return st.commit()


func _add_tube(st: SurfaceTool, centres: PackedVector3Array) -> void:
	var rings: Array[Array] = []
	for i in centres.size():
		var forward: Vector3
		if i == 0:
			forward = (centres[1] - centres[0]).normalized()
		elif i == centres.size() - 1:
			forward = (centres[i] - centres[i - 1]).normalized()
		else:
			forward = (centres[i + 1] - centres[i - 1]).normalized()
		rings.append(_ring(to_local(centres[i]), forward))
	for i in range(rings.size() - 1):
		var current: Array = rings[i]
		var next: Array = rings[i + 1]
		for s in ring_segments:
			var s2 := (s + 1) % ring_segments
			for p: Vector3 in [current[s], next[s], next[s2], current[s], next[s2], current[s2]]:
				st.add_vertex(p)


func _ring(centre: Vector3, forward: Vector3) -> Array:
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.95:
		up = Vector3.FORWARD
	var right := forward.cross(up).normalized()
	var real_up := right.cross(forward).normalized()
	var points: Array[Vector3] = []
	for s in ring_segments:
		var angle := TAU * s / ring_segments
		points.append(centre + (right * cos(angle) + real_up * sin(angle)) * radius)
	return points


func _add_lights(centres: PackedVector3Array) -> void:
	var walked := light_spacing
	for i in range(1, centres.size()):
		walked += centres[i].distance_to(centres[i - 1])
		if walked >= light_spacing:
			walked = 0.0
			var light := OmniLight3D.new()
			light.position = to_local(centres[i]) + Vector3.UP * (radius * 0.4)
			light.light_color = Color(1.0, 0.86, 0.66)
			light.light_energy = 2.5
			light.omni_range = radius * 4.0
			add_child(light)
