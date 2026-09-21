@tool
extends Node3D
## Reusable low-poly coastal foliage. One node can produce broad leaves, ferns or grass.

const Builder = preload("res://art/procedural/kit_mesh.gd")

enum Style { BROAD_LEAF, FERN, GRASS }

@export var style: Style = Style.BROAD_LEAF:
	set(value):
		style = value
		_refresh()
@export var shape_seed := 71:
	set(value):
		shape_seed = value
		_refresh()
@export_range(1, 12) var plant_count := 5:
	set(value):
		plant_count = value
		_refresh()
@export_range(0.4, 4.0) var height := 1.5:
	set(value):
		height = value
		_refresh()
@export_range(0.1, 4.0) var spread := 1.2:
	set(value):
		spread = value
		_refresh()
@export var leaf_colour := Color("4f8f2f"):
	set(value):
		leaf_colour = value
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
	var root := Builder.clear_generated(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plant in plant_count:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * spread
		var origin := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var plant_height := height * rng.randf_range(0.76, 1.12)
		match style:
			Style.BROAD_LEAF:
				_add_broad_plant(stems, leaves, origin, plant_height, rng)
			Style.FERN:
				_add_fern(stems, leaves, origin, plant_height, rng)
			Style.GRASS:
				_add_grass(leaves, origin, plant_height, rng)
	if style != Style.GRASS:
		Builder.instance(root, stems.commit(), Builder.material(), "Stems")
	Builder.instance(root, leaves.commit(), Builder.material(true), "Leaves")


func _add_stem(st: SurfaceTool, base: Vector3, top: Vector3, radius: float, colour: Color) -> void:
	var x := Vector3.RIGHT * radius
	var z := Vector3.FORWARD * radius
	Builder.quad(st, base - x - z, top - x - z, top + x - z, base + x - z, colour)
	Builder.quad(st, base + x - z, top + x - z, top + x + z, base + x + z, colour)
	Builder.quad(st, base + x + z, top + x + z, top - x + z, base - x + z, colour.darkened(0.08))
	Builder.quad(st, base - x + z, top - x + z, top - x - z, base - x - z, colour.darkened(0.08))


func _leaf(st: SurfaceTool, base: Vector3, direction: Vector3, length: float,
		width: float, lift: float, colour: Color) -> void:
	var side := Vector3(-direction.z, 0.0, direction.x)
	var middle := base + direction * length * 0.48 + Vector3.UP * lift
	var tip := base + direction * length + Vector3.UP * (lift * 0.18)
	var left := middle - side * width
	var right := middle + side * width
	var ridge := middle + Vector3.UP * width * 0.22
	Builder.triangle(st, base, left, ridge, colour.darkened(0.08))
	Builder.triangle(st, left, tip, ridge, colour)
	Builder.triangle(st, tip, right, ridge, colour.lightened(0.08))
	Builder.triangle(st, right, base, ridge, colour)


func _add_broad_plant(stems: SurfaceTool, leaves: SurfaceTool, origin: Vector3,
		plant_height: float, rng: RandomNumberGenerator) -> void:
	var crown := origin + Vector3.UP * plant_height * 0.38
	_add_stem(stems, origin, crown, plant_height * 0.035, Color("55602d"))
	var count := rng.randi_range(5, 7)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.18, 0.18)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var colour := leaf_colour.lightened(rng.randf_range(-0.04, 0.13))
		_leaf(leaves, crown, direction, plant_height * rng.randf_range(0.78, 0.98),
			plant_height * rng.randf_range(0.22, 0.30), plant_height * rng.randf_range(0.14, 0.28), colour)


func _add_fern(stems: SurfaceTool, leaves: SurfaceTool, origin: Vector3,
		plant_height: float, rng: RandomNumberGenerator) -> void:
	var crown := origin + Vector3.UP * plant_height * 0.16
	_add_stem(stems, origin, crown, plant_height * 0.018, Color("53602b"))
	var count := rng.randi_range(7, 9)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.16, 0.16)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var length := plant_height * rng.randf_range(0.90, 1.18)
		var tip := crown + direction * length + Vector3.UP * plant_height * rng.randf_range(0.05, 0.20)
		Builder.quad(leaves, crown - side * 0.025, tip - side * 0.012,
			tip + side * 0.012, crown + side * 0.025, leaf_colour.darkened(0.16))
		for segment in range(1, 6):
			var t := float(segment) / 6.0
			var centre := crown.lerp(tip, t)
			var pinna_width := sin(t * PI) * plant_height * 0.34
			var pinna_length: float = plant_height * lerpf(0.25, 0.10, t)
			for sign_index in 2:
				var sign_value: float = -1.0 if sign_index == 0 else 1.0
				var pinna_tip: Vector3 = centre + side * pinna_width * sign_value - direction * pinna_length * 0.18
				var pinna_base: Vector3 = centre - direction * pinna_length * 0.45
				var fold: Vector3 = (centre + pinna_tip + pinna_base) / 3.0 + Vector3.UP * plant_height * 0.025
				Builder.triangle(leaves, pinna_base, pinna_tip, fold,
					leaf_colour.lightened(rng.randf_range(-0.05, 0.10)))


func _add_grass(leaves: SurfaceTool, origin: Vector3, plant_height: float,
		rng: RandomNumberGenerator) -> void:
	var count := rng.randi_range(7, 11)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.22, 0.22)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var blade_height := plant_height * rng.randf_range(0.55, 1.05)
		var width := plant_height * rng.randf_range(0.10, 0.15)
		var base := origin + direction * rng.randf_range(0.0, spread * 0.18)
		var middle := base + direction * blade_height * 0.18 + Vector3.UP * blade_height * 0.58
		var tip := base + direction * blade_height * 0.42 + Vector3.UP * blade_height
		var colour := leaf_colour.lightened(rng.randf_range(-0.06, 0.14))
		Builder.triangle(leaves, base - side * width, middle, base + side * width, colour.darkened(0.08))
		Builder.triangle(leaves, middle, tip, base + side * width, colour)
