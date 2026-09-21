@tool
extends Node3D

const Builder = preload("res://art/procedural/kit_mesh.gd")

@export_range(3.0, 14.0) var height: float = 7.5:
	set(value):
		height = clampf(value, 3.0, 14.0)
		_refresh()
@export var bend := Vector2(1.4, 0.3):
	set(value):
		bend = value
		_refresh()
@export var shape_seed: int = 41:
	set(value):
		shape_seed = value
		_refresh()
@export_range(6, 14) var frond_count: int = 10:
	set(value):
		frond_count = clampi(value, 6, 14)
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


func _centre(t: float) -> Vector3:
	return Vector3(bend.x * t * t, height * t, bend.y * t * t)


func rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var root := Builder.clear_generated(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in 20:
		var t0 := float(j) / 20.0
		var t1 := float(j + 1) / 20.0
		var r0 := lerpf(0.36, 0.17, t0)
		var r1 := lerpf(0.36, 0.17, t1)
		var colour := Color("a37a49").lightened(0.10 if j % 3 == 0 else 0.0)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var b := TAU * float(i + 1) / 8.0
			var d0 := Vector3(cos(a), 0, sin(a))
			var d1 := Vector3(cos(b), 0, sin(b))
			Builder.quad(trunk, _centre(t0) + d0 * r0 * 0.91, _centre(t1) + d0 * r1,
					_centre(t1) + d1 * r1, _centre(t0) + d1 * r0 * 0.91, colour)
			# Close the narrow growth-ring ledge between successive segments.
			if j < 19:
				Builder.quad(trunk, _centre(t1) + d0 * r1, _centre(t1) + d0 * r1 * 0.91,
						_centre(t1) + d1 * r1 * 0.91, _centre(t1) + d1 * r1, colour.darkened(0.12))
			if j == 0:
				Builder.triangle(trunk, _centre(0), _centre(0) + d0 * r0 * 0.91, _centre(0) + d1 * r0 * 0.91, colour)
			if j == 19:
				Builder.triangle(trunk, _centre(1), _centre(1) + d1 * r1, _centre(1) + d0 * r1, colour)
	var trunk_mesh := trunk.commit()
	Builder.instance(root, trunk_mesh, Builder.material(), "Trunk")
	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "TrunkCollision"
		var shape := CollisionShape3D.new()
		shape.shape = trunk_mesh.create_trimesh_shape()
		body.add_child(shape)
		root.add_child(body)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in frond_count:
		var angle := TAU * float(i) / float(frond_count) + rng.randf_range(-0.12, 0.12)
		var direction := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-sin(angle), 0, cos(angle))
		var length := rng.randf_range(3.1, 4.1) * height / 7.5
		var lift := rng.randf_range(1.0, 1.8)
		var droop := rng.randf_range(1.0, 2.1)
		var base := _centre(1.0) + Vector3.UP * (0.12 if i % 2 == 0 else -0.08)
		var colour := Color("568b31").lerp(Color("91aa38"), rng.randf())
		for j in 12:
			var t0 := float(j) / 12.0
			var t1 := float(j + 1) / 12.0
			var c0 := base + direction * length * t0 + Vector3.UP * (sin(t0 * PI) * lift - t0 * t0 * droop)
			var c1 := base + direction * length * t1 + Vector3.UP * (sin(t1 * PI) * lift - t1 * t1 * droop)
			Builder.quad(leaves, c0 - side * 0.055, c1 - side * 0.025,
					c1 + side * 0.025, c0 + side * 0.055, colour.lightened(0.12))
			var width := sin(pow(t1, 0.7) * PI) * length * 0.24
			for sign_value in [-1.0, 1.0]:
				var tip: Vector3 = c1 + side * width * sign_value + direction * length * 0.11 - Vector3.UP * width * 0.32
				var ridge: Vector3 = (c0 + c1 + tip) / 3.0 + Vector3.UP * 0.09
				Builder.triangle(leaves, c0, c1, ridge, colour)
				Builder.triangle(leaves, c1, tip, ridge, colour.lightened(0.06))
				Builder.triangle(leaves, tip, c0, ridge, colour.darkened(0.12))
	Builder.instance(root, leaves.commit(), Builder.material(true), "Fronds")
