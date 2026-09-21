extends Node3D
## Deterministic layout in shoreline coordinates: +Z inland, +X along the beach.
const Rock = preload("res://art/procedural/coastal_rock.tscn")
const Palm = preload("res://art/procedural/coastal_palm.tscn")
const Foliage = preload("res://art/procedural/coastal_foliage.tscn")
const OFFSETS := [Vector2(-4.5, 2.5), Vector2(-6.5, 0.5), Vector2(-3.0, -0.8),
	Vector2(5.0, 2.0), Vector2(-1.8, -2.2), Vector2(5.8, 0.3)]
const SIZES := [Vector3(4.5, 3.8, 3.4), Vector3(2.8, 2.2, 2.3), Vector3(2.6, 0.9, 2.0),
	Vector3(2.0, 1.6, 1.8), Vector3(0.8, 0.55, 0.65), Vector3(0.65, 0.5, 0.8)]
const PALM_OFFSET := Vector2(3.5, 4.0)
const SPAWN_OFFSET := Vector2(0.0, -5.5)

var spawn := Vector3.ZERO
var anchor := Vector3.ZERO
var inland := Vector3.FORWARD
var valid := false
var _terrain: Node3D


func setup(terrain: Node3D) -> bool:
	_terrain = terrain
	valid = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var sea: float = terrain.sea_level()
	var extent: float = terrain.world_size * 0.46
	var best_score := INF
	var best_position := Vector3.ZERO
	var best_yaw := 0.0
	# Fixed grid and tie order; does not consume the global RNG used by existing tests.
	for x in range(int(-extent), int(extent), 5):
		for z in range(int(-extent), int(extent), 5):
			var h: float = terrain.height_at(x, z)
			if h < sea + 1.3 or h > sea + 5.0:
				continue
			var gradient := Vector2(terrain.height_at(x + 2, z) - terrain.height_at(x - 2, z),
					terrain.height_at(x, z + 2) - terrain.height_at(x, z - 2)) / 4.0
			if gradient.length() < 0.015 or gradient.length() > 0.28:
				continue
			var inland := gradient.normalized()
			var yaw := atan2(inland.x, inland.y)
			var basis_y := Basis(Vector3.UP, yaw)
			var centre := Vector3(x, h, z)
			var shore_distance := INF
			for distance in range(6, 37, 2):
				var shore := Vector2(x, z) - inland * float(distance)
				if terrain.height_at(shore.x, shore.y) <= sea + 0.1:
					shore_distance = float(distance)
					break
			if is_inf(shore_distance):
				continue
			var score := _patch_score(centre, basis_y, sea)
			if is_inf(score):
				continue
			score += shore_distance * 0.04 + absf(h - sea - 2.4) * 0.3
			if score < best_score:
				best_score = score
				best_position = centre
				best_yaw = yaw
	if is_inf(best_score):
		push_warning("Coastal study: no dry, gentle shoreline patch; retaining original spawn.")
		return false
	global_position = best_position
	anchor = best_position
	global_rotation.y = best_yaw
	inland = global_basis.z
	for i in OFFSETS.size():
		var rock := Rock.instantiate()
		rock.name = ["LargeOutcrop", "MediumRockA", "FlatSlab", "MediumRockB", "LooseStoneA", "LooseStoneB"][i]
		rock.shape_seed = [13, 27, 8, 36, 9, 18][i]
		rock.dimensions = SIZES[i]
		rock.rotation.y = float(i) * 1.71
		add_child(rock)
		rock.global_position = _ground(OFFSETS[i]) - Vector3.UP * 0.16
	var palm := Palm.instantiate()
	palm.name = "Palm"
	palm.shape_seed = 41
	palm.rotation.y = 0.4
	add_child(palm)
	palm.global_position = _ground(PALM_OFFSET) - Vector3.UP * 0.08
	_place_foliage("BroadLeaves", Vector2(5.8, 5.0), 0, 67, 2.1, 1.0, 5, Color("4f9230"))
	_place_foliage("FernPatch", Vector2(-5.6, 4.0), 1, 83, 1.5, 1.2, 6, Color("397a30"))
	_place_foliage("BeachGrass", Vector2(-0.8, 3.2), 2, 101, 1.0, 1.6, 10, Color("78a63b"))
	spawn = _ground(SPAWN_OFFSET)
	valid = true
	print("coastal study: 6 rocks + palm + 3 foliage groups at ", global_position, " spawn ", spawn)
	return true


func _place_foliage(label: String, offset: Vector2, style: int, foliage_seed: int,
		foliage_height: float, foliage_spread: float, count: int, colour: Color) -> void:
	var foliage := Foliage.instantiate()
	foliage.name = label
	foliage.style = style
	foliage.shape_seed = foliage_seed
	foliage.height = foliage_height
	foliage.spread = foliage_spread
	foliage.plant_count = count
	foliage.leaf_colour = colour
	foliage.rotation.y = float(foliage_seed) * 0.37
	add_child(foliage)
	foliage.global_position = _ground(offset) - Vector3.UP * 0.04


func _patch_score(centre: Vector3, orientation: Basis, sea: float) -> float:
	var worst_slope := 0.0
	# Cover the complete group and spawn, including the largest rock's footprint.
	for x in range(-10, 11, 2):
		for z in range(-7, 8, 2):
			var p := centre + orientation * Vector3(x, 0, z)
			var h: float = _terrain.height_at(p.x, p.z)
			if h < sea + 0.75 or absf(h - centre.y) > 2.2:
				return INF
			var dx: float = (_terrain.height_at(p.x + 1, p.z) - _terrain.height_at(p.x - 1, p.z)) * 0.5
			var dz: float = (_terrain.height_at(p.x, p.z + 1) - _terrain.height_at(p.x, p.z - 1)) * 0.5
			var slope := Vector2(dx, dz).length()
			if slope > 0.32:
				return INF
			worst_slope = maxf(worst_slope, slope)
	return worst_slope * 5.0


func _ground(offset: Vector2) -> Vector3:
	var p := to_global(Vector3(offset.x, 0, offset.y))
	p.y = _terrain.height_at(p.x, p.z)
	return p


func show_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "AssetStudyCamera"
	add_child(camera)
	camera.position = Vector3(17, 15, -24)
	camera.fov = 52.0
	camera.far = 1500.0
	camera.look_at(to_global(Vector3(0, 3.0, 0)))
	camera.make_current()
	return camera
