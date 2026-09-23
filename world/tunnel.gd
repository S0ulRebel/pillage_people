@tool
class_name Tunnel
extends Path3D
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
## How far the curve is followed past the surface. The tube is trimmed to the ground, so
## this only has to be long enough that the cut's rounded end is clear of the terrain.
@export var overshoot := 6.0
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
## Ring centres per underground stretch, including one sample of overshoot at each end: the
## tube is built from these and then clipped to the ground.
var _stretches: Array[PackedVector3Array] = []
## Strictly-underground centres, kept for reference by tools and tests.
var _cut_stretches: Array[PackedVector3Array] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		# so a tunnel dropped into the scene shows itself straight away
		var found := get_node_or_null("../Terrain")
		if found != null:
			build(found)


## Called by main.gd (or by the editor preview) once the terrain knows its heights.
func build(terrain: Node3D) -> void:
	_terrain = terrain
	_rebuild()


## How far outside the tube a world point is: negative inside, zero on the wall.
## The terrain uses this to decide what to cut, so the hole is always the tube's own shape.
func distance_outside(world_point: Vector3) -> float:
	# Cut against the full tube, overshoot included: the tube is clipped to the ground, so an
	# opening is exactly the surface inside the tube. The overshoot has to be long enough that
	# the polyline's rounded end sits above ground, or the cut wraps past where the tube is.
	var best := 1e9
	for stretch in _stretches:
		for i in range(stretch.size() - 1):
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
		remove_child(child)
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
	_cut_stretches = []
	var current := PackedVector3Array()
	var underground := PackedVector3Array()
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
			underground.append(world)
		elif was_under:
			current.append(to_global(curve.sample_baked(minf(length, distance + overshoot))))
			if current.size() >= 2:
				stretches.append(current)
				_cut_stretches.append(underground)
			current = PackedVector3Array()
			underground = PackedVector3Array()
		was_under = under
		distance += sample_spacing
	if was_under and current.size() >= 2:
		stretches.append(current)
		_cut_stretches.append(underground)
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
		rings.append(_ring(centres[i], forward))
	for i in range(rings.size() - 1):
		var current: Array = rings[i]
		var next: Array = rings[i + 1]
		for s in ring_segments:
			var s2 := (s + 1) % ring_segments
			_add_clipped(st, [current[s], next[s], next[s2]])
			_add_clipped(st, [current[s], next[s2], current[s2]])


## Adds a triangle, keeping only the part that is below the terrain surface. This is what
## shapes the mouth: the tube ends exactly where it meets the ground, on the same curve the
## terrain is cut along, so there is no lip sticking out and no gap to fall through.
func _add_clipped(st: SurfaceTool, triangle: Array) -> void:
	var polygon: Array[Vector3] = []
	for i in 3:
		var current: Vector3 = to_global(triangle[i])
		var next: Vector3 = to_global(triangle[(i + 1) % 3])
		var depth_current: float = _depth(current)
		var depth_next: float = _depth(next)
		if depth_current >= 0.0:
			polygon.append(current)
		if (depth_current >= 0.0) != (depth_next >= 0.0):
			polygon.append(_surface_crossing(current, next, depth_current, depth_next))
	if polygon.size() < 3:
		return
	for i in range(1, polygon.size() - 1):
		for p: Vector3 in [polygon[0], polygon[i], polygon[i + 1]]:
			st.add_vertex(to_local(p))


## How far below the terrain a point is; negative above ground.
func _depth(world_point: Vector3) -> float:
	return _terrain.height_at(world_point.x, world_point.z) - world_point.y


## Where a segment crosses the terrain surface. The first guess is linear; the ground is not,
## so a few bisection steps tighten it.
func _surface_crossing(a: Vector3, b: Vector3, depth_a: float, depth_b: float) -> Vector3:
	var t: float = clampf(depth_a / (depth_a - depth_b), 0.0, 1.0)
	var low := 0.0
	var high := 1.0
	for i in 6:
		var point: Vector3 = a.lerp(b, t)
		if (_depth(point) >= 0.0) == (depth_a >= 0.0):
			low = t
		else:
			high = t
		t = (low + high) * 0.5
	return a.lerp(b, t)


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
