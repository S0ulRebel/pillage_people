@tool
extends Node3D

const Builder = preload("res://art/procedural/kit_mesh.gd")

@export var shape_seed: int = 13:
	set(value):
		shape_seed = value
		_refresh()
@export var dimensions := Vector3(3.6, 3.0, 2.8):
	set(value):
		dimensions = value.max(Vector3.ONE * 0.1)
		_refresh()
@export var stone_colour := Color("777a80"):
	set(value):
		stone_colour = value
		_refresh()
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		_refresh()
var _queued := false


func _ready() -> void:
	rebuild()


func _refresh() -> void:
	if is_inside_tree() and not _queued:
		_queued = true
		call_deferred("rebuild")


func rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var root := Builder.clear_generated(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var angles := PackedFloat32Array()
	var radii := PackedFloat32Array()
	for i in 8:
		angles.append(TAU * float(i) / 8.0 + rng.randf_range(-0.09, 0.09))
		radii.append(rng.randf_range(0.86, 1.12))
	var levels := [0.0, 0.15, 0.76, 1.0]
	var widths := [0.76, 1.0, 0.91, 0.56]
	var rings: Array[PackedVector3Array] = []
	var lean := Vector3(rng.randf_range(-0.16, 0.16), 0, rng.randf_range(-0.12, 0.12))
	for j in 4:
		var ring := PackedVector3Array()
		for i in 8:
			var t: float = levels[j]
			var p := Vector3(cos(angles[i]) * radii[i] * widths[j] * 0.5,
					t, sin(angles[i]) * radii[i] * widths[j] * 0.5)
			p += lean * t
			if j > 0:
				p.y += rng.randf_range(-0.035, 0.035)
			ring.append(p * dimensions)
		rings.append(ring)
	for j in 3:
		for i in 8:
			var n := (i + 1) % 8
			var colour := stone_colour * rng.randf_range(0.88, 1.10)
			colour.a = 1.0
			Builder.quad(st, rings[j][i], rings[j + 1][i], rings[j + 1][n], rings[j][n], colour)
	var top := Vector3.ZERO
	for p in rings[3]:
		top += p / 8.0
	for i in 8:
		var n := (i + 1) % 8
		Builder.triangle(st, top, rings[3][n], rings[3][i], stone_colour.lightened(0.10))
		Builder.triangle(st, Vector3.ZERO, rings[0][i], rings[0][n], stone_colour)
	var mesh := st.commit()
	var stone := Builder.instance(root, mesh, Builder.material(), "Stone")
	# Layer 20 is sampled by the ocean's overhead silhouette camera. Keeping the normal
	# layer as well means the same faceted mesh supplies both the visible rock and its
	# stable world-space water-band mask, without a second proxy mesh.
	stone.layers = 1 | (1 << 19)
	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "Collision"
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_convex_shape()
		body.add_child(shape)
		root.add_child(body)
