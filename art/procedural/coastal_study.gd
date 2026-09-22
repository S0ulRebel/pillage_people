extends Node3D
## Deterministic layout in shoreline coordinates: +Z inland, +X along the beach.
const Rock = preload("res://art/props/rock.tscn")
const RockKind = preload("res://art/props/rock.gd")
const Palm = preload("res://art/procedural/coastal_palm.tscn")
const Grass = preload("res://art/props/grass.gd")
const OFFSETS := [Vector2(-4.5, 2.5), Vector2(-6.5, 0.5), Vector2(-3.0, -0.8),
	Vector2(5.0, 2.0), Vector2(-1.8, -2.2), Vector2(5.8, 0.3)]
## Which generated model stands at each offset, and how tall it should be. Heights carry over
## from the procedural rocks that used to be here, so the group keeps the silhouette it was
## composed with - a big outcrop, two mid rocks, a flat slab to stand on and two loose stones.
const KINDS := [RockKind.Kind.CLUSTER, RockKind.Kind.BOULDER, RockKind.Kind.PLATFORM,
	RockKind.Kind.STONE, RockKind.Kind.STONES, RockKind.Kind.PILE]
const HEIGHTS := [3.8, 2.2, 0.9, 1.6, 0.55, 0.5]
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
		rock.kind = KINDS[i]
		rock.size = RockKind.size_for(KINDS[i], HEIGHTS[i])
		rock.rotation.y = float(i) * 1.71
		add_child(rock)
		# Sunk slightly, so a modelled base does not sit proud of a sloping beach.
		rock.global_position = _ground(OFFSETS[i]) - Vector3.UP * 0.16
	var water_rock_count := _place_water_rocks(sea)
	var palm := Palm.instantiate()
	palm.name = "Palm"
	palm.shape_seed = 41
	palm.rotation.y = 0.4
	add_child(palm)
	palm.global_position = _ground(PALM_OFFSET) - Vector3.UP * 0.08
	_plant_grass()
	spawn = _ground(SPAWN_OFFSET)
	valid = true
	print("coastal study: 6 shore rocks + %d water rocks + palm + grass at " % water_rock_count,
		global_position, " spawn ", spawn)
	return true


func _place_water_rocks(sea: float) -> int:
	var lateral_offsets := [-5.0, 0.5, 5.5]
	# Heights kept from the rocks that used to stand here: the depth search below picks its
	# seabed from them, so changing one without the other leaves a rock fully submerged and
	# the ocean's water band with nothing to draw against.
	var kinds := [RockKind.Kind.CLUSTER, RockKind.Kind.BOULDER, RockKind.Kind.PILE_TALL]
	var heights := [3.4, 2.4, 1.7]
	var placed := 0
	for i in lateral_offsets.size():
		var chosen := Vector3.ZERO
		var found := false
		# Local -Z points seaward. Pick shallow seabed so every rock crosses sea level.
		for distance in range(6, 32):
			var p := to_global(Vector3(lateral_offsets[i], 0.0, -float(distance)))
			var bed: float = _terrain.height_at(p.x, p.z)
			var depth: float = sea - bed
			if depth >= 0.45 and depth <= heights[i] * 0.68:
				chosen = Vector3(p.x, bed - 0.12, p.z)
				found = true
				break
		if not found:
			continue
		var rock := Rock.instantiate()
		rock.name = "WaterRock%d" % (i + 1)
		rock.kind = kinds[i]
		rock.size = RockKind.size_for(kinds[i], heights[i])
		rock.rotation.y = 0.65 + float(i) * 1.37
		add_child(rock)
		rock.global_position = chosen
		placed += 1
	return placed


## Three clumps of grass where the procedural foliage used to stand.
##
## The same three spots, composed rather than scattered: the group was laid out by hand and a
## random scatter would not put anything where the broad leaves and the ferns were. It gets its
## own Grass node because the island's scatter runs later and knows nothing about this group's
## local space.
func _plant_grass() -> void:
	var grass: MultiMeshInstance3D = Grass.new()
	grass.name = "Grass"
	# Composed planting, so the green band test the island scatter uses does not apply - these
	# sit where the study decided, close to the water.
	grass.lowest = -2.0
	grass.highest = 40.0
	grass.patch_radius = Vector2(0.9, 1.9)
	grass.per_patch = Vector2i(9, 18)
	add_child(grass)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6701
	var spots: Array[Vector3] = [_ground(Vector2(5.8, 5.0)), _ground(Vector2(-5.6, 4.0)),
			_ground(Vector2(-0.8, 3.2))]
	grass.plant(_terrain, spots, rng)


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
	camera.position = Vector3(18, 18, -28)
	camera.fov = 55.0
	camera.far = 1500.0
	camera.look_at(to_global(Vector3(0, 2.5, -4.5)))
	camera.make_current()
	return camera
