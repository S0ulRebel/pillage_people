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
	var crown := origin + Vector3.UP * plant_height * 0.30
	_add_stem(stems, origin, crown, plant_height * 0.035, Color("55602d"))
	var count := rng.randi_range(4, 6)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.18, 0.18)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var petiole_length := plant_height * rng.randf_range(0.26, 0.38)
		var leaf_base := crown + direction * petiole_length * 0.72 \
			+ Vector3.UP * petiole_length * rng.randf_range(0.55, 0.90)
		_add_stem(stems, crown, leaf_base, plant_height * 0.018, Color("617632"))
		var colour := leaf_colour.lightened(rng.randf_range(-0.04, 0.13))
		_leaf(leaves, leaf_base, direction, plant_height * rng.randf_range(0.58, 0.76),
			plant_height * rng.randf_range(0.19, 0.25), plant_height * rng.randf_range(0.08, 0.18), colour)


func _add_fern(stems: SurfaceTool, leaves: SurfaceTool, origin: Vector3,
		plant_height: float, rng: RandomNumberGenerator) -> void:
	var crown := origin + Vector3.UP * plant_height * 0.20
	_add_stem(stems, origin, crown, plant_height * 0.018, Color("53602b"))
	var count := rng.randi_range(6, 8)
	for i in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.16, 0.16)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-direction.z, 0.0, direction.x)
		var length := plant_height * rng.randf_range(0.82, 1.02)
		var previous := crown
		for segment in range(1, 8):
			var t := float(segment) / 7.0
			var centre := crown + direction * length * t + Vector3.UP * (
				sin(t * PI) * plant_height * 0.24 - t * t * plant_height * 0.18)
			Builder.quad(leaves, previous - side * 0.028, centre - side * 0.018,
				centre + side * 0.018, previous + side * 0.028, leaf_colour.darkened(0.16))
			previous = centre
			if segment == 7:
				continue
			var pinna_reach := sin(t * PI) * plant_height * 0.27
			var pinna_width: float = plant_height * lerpf(0.12, 0.055, t)
			for sign_index in 2:
				var sign_value: float = -1.0 if sign_index == 0 else 1.0
				var pinna_tip: Vector3 = centre + side * pinna_reach * sign_value \
					- direction * pinna_width * 0.25 - Vector3.UP * pinna_reach * 0.06
				var pinna_back: Vector3 = centre - direction * pinna_width
				var pinna_front: Vector3 = centre + direction * pinna_width
				var ridge: Vector3 = centre + side * pinna_reach * sign_value * 0.46 \
					+ Vector3.UP * plant_height * 0.045
				var colour := leaf_colour.lightened(rng.randf_range(-0.05, 0.10))
				Builder.triangle(leaves, pinna_back, pinna_tip, ridge, colour.darkened(0.06))
				Builder.triangle(leaves, pinna_tip, pinna_front, ridge, colour)


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
