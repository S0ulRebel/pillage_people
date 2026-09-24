@tool
class_name Sail
extends Node3D
## Cloth laced along two opposite edges. The course uses the yard and the foot yard; the
## jib uses the mast and the bowsprit. The points are in ship space, so the hull can
## heave and yaw without the sheet being left behind in the world.
##
## Verlet plus distance constraints, not a soft body: the sail only has to hang and belly,
## and a physics soft body would also try to collide with the mast, the deck and the guns.

const COLS := 14
const ROWS := 10
## Half the yard is 4 m. The cloth stops short of the tips.
const HALF_WIDTH := 3.6
## Head yard to foot yard. The foot yard sits high enough to walk under.
const DROP := 2.4
const ITERATIONS := 5

var _pos: PackedVector3Array = PackedVector3Array()
var _prev: PackedVector3Array = PackedVector3Array()
var _rest: PackedFloat32Array = PackedFloat32Array()
var _links: PackedInt32Array = PackedInt32Array()
var _mesh_node: MeshInstance3D
var _arrays := []
## Head edge and foot edge in ship space. Empty until rig_between, in which case the
## course yard is used.
var _head_from := Vector3.ZERO
var _head_to := Vector3.ZERO
var _foot_from := Vector3.ZERO
var _foot_to := Vector3.ZERO
## Added at mid-sheet, zero on the laced edges, so the cloth starts as a curve.
var _belly := Vector3(0.0, 0.0, 0.45)
var _rigged := false
## The course leaves this false: only the head is laced. Topsail and jib lace both edges.
var _pin_foot := true


## Call before the node enters the tree. False hangs the foot free.
func pin_foot(on: bool) -> void:
	_pin_foot = on


## Call before the node enters the tree. Head and foot are the two laced edges.
func rig_between(head_from: Vector3, head_to: Vector3, foot_from: Vector3, foot_to: Vector3, belly: Vector3) -> void:
	_head_from = head_from
	_head_to = head_to
	_foot_from = foot_from
	_foot_to = foot_to
	_belly = belly
	_rigged = true


func _ready() -> void:
	if not _rigged:
		# Weather deck is 5.2; the yard sits 4.6 above that. The foot hangs free of the deck.
		var top_y := 5.2 + 4.6
		var top_z := 9.12
		var drop := 3.0
		_head_from = Vector3(-HALF_WIDTH, top_y, top_z)
		_head_to = Vector3(HALF_WIDTH, top_y, top_z)
		_foot_from = Vector3(-HALF_WIDTH, top_y - drop, top_z)
		_foot_to = Vector3(HALF_WIDTH, top_y - drop, top_z)
		_belly = Vector3(0.0, 0.0, 0.45)
	for row in ROWS:
		var down := float(row) / float(ROWS - 1)
		for col in COLS:
			var across := float(col) / float(COLS - 1)
			var head := _head_from.lerp(_head_to, across)
			var foot := _foot_from.lerp(_foot_to, across)
			var point := head.lerp(foot, down)
			point += _belly * sin(down * PI) * sin(across * PI)
			_pos.append(point)
			_prev.append(point)
	for row in ROWS:
		for col in COLS:
			var here := _index(col, row)
			if col + 1 < COLS:
				_link(here, _index(col + 1, row))
			if row + 1 < ROWS:
				_link(here, _index(col, row + 1))
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "Cloth"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.86, 0.82, 0.70)
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_mesh_node.material_override = material
	_mesh_node.mesh = ArrayMesh.new()
	add_child(_mesh_node)
	_arrays.resize(Mesh.ARRAY_MAX)
	_rebuild()


func _physics_process(delta: float) -> void:
	# The editor shows the sheet at rest. Simulating here would rebuild the mesh every tick
	# while the scene is open.
	if Engine.is_editor_hint():
		return
	var ship := get_parent() as Node3D
	if ship == null:
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var down := ship.global_transform.basis.inverse() * Vector3.DOWN
	var push := Vector3.ZERO
	var wind := get_tree().get_first_node_in_group("wind")
	if wind != null and wind.has_method("blow"):
		push = ship.global_transform.basis.inverse() * wind.blow()
	var accel := down * gravity + push
	var step := minf(delta, 0.05)
	var damp := 0.985
	var count := _pos.size()
	for i in count:
		if _pinned(i):
			continue
		var current := _pos[i]
		var velocity := (current - _prev[i]) * damp
		_prev[i] = current
		_pos[i] = current + velocity + accel * step * step
	for _iteration in ITERATIONS:
		for link in range(0, _links.size(), 2):
			var a := _links[link]
			var b := _links[link + 1]
			var delta_p := _pos[b] - _pos[a]
			var length := delta_p.length()
			if length < 0.0001:
				continue
			var correction := delta_p * ((length - _rest[link >> 1]) / length)
			if _pinned(a) and _pinned(b):
				continue
			if _pinned(a):
				_pos[b] -= correction
			elif _pinned(b):
				_pos[a] += correction
			else:
				_pos[a] += correction * 0.5
				_pos[b] -= correction * 0.5
	_rebuild()


func _pinned(index: int) -> bool:
	var row := index / COLS
	return row == 0 or (_pin_foot and row == ROWS - 1)


func _index(col: int, row: int) -> int:
	return row * COLS + col


func _link(a: int, b: int) -> void:
	_links.append(a)
	_links.append(b)
	_rest.append(_pos[a].distance_to(_pos[b]))


func _rebuild() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.resize(_pos.size())
	normals.resize(_pos.size())
	for i in _pos.size():
		vertices[i] = _pos[i]
	for row in ROWS - 1:
		for col in COLS - 1:
			var a := _index(col, row)
			var b := _index(col + 1, row)
			var c := _index(col, row + 1)
			var d := _index(col + 1, row + 1)
			indices.append_array([a, c, b, b, c, d])
			var normal := (_pos[c] - _pos[a]).cross(_pos[b] - _pos[a])
			if normal.length_squared() > 0.000001:
				normal = normal.normalized()
			normals[a] += normal
			normals[b] += normal
			normals[c] += normal
			normals[d] += normal
	for i in normals.size():
		if normals[i].length_squared() > 0.000001:
			normals[i] = normals[i].normalized()
		else:
			normals[i] = Vector3.FORWARD
	_arrays[Mesh.ARRAY_VERTEX] = vertices
	_arrays[Mesh.ARRAY_NORMAL] = normals
	_arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := _mesh_node.mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
