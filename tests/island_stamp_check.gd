extends SceneTree
## Run: godot --headless --path . --script res://tests/island_stamp_check.gd
##
## Is the island the same island now that it is a stamp?
##
## It used to BE the ground: terrain/island.r16, read as the height map. Now the ground starts
## as a Seabed and the island is a Replace stamp on it - terrain/island.stamp, the same numbers
## read with mid-grey as zero, so the stamp's Y and its height are both 180 x 32768 / 65535 m,
## and Y + value x height gives back exactly what the file said. This builds both and compares
## every height sample, height_at() between them, and every vertex of the mesh; and checks
## main.tscn's Island is the stamp built here, so the two cannot drift apart.
##
## It also checks the Seabed on its own, with nothing on it: that the ground it lays down is
## the bed it describes, at the Terrain's sea level.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")
## 180 x 32768 / 65535, to a float's width: the transform that carries the stamp's Y is 32-bit,
## so its height is given the same number and Y + value x height stays H x (1 + value). That
## number is 2e-10 short of the exact one, which tips about one sample in fifty to the next
## 32-bit value over - 0.011 mm. Everything is held to a millimetre.
const ISLAND_HEIGHT := 90.001373291015625
const TOLERANCE := 0.001

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _terrain() -> Node3D:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	return terrain


func _old_island() -> Node3D:
	var terrain := _terrain()
	terrain.raw_path = "res://terrain/island.r16"
	return terrain


func _new_island() -> Node3D:
	var terrain := _terrain()
	var seabed := Seabed.new()
	seabed.noise = FastNoiseLite.new()
	terrain.add_child(seabed)
	var island := STAMP.instantiate() as TerrainStamp
	island.name = "Island"
	island.mode = TerrainStamp.Mode.REPLACE
	island.stamp_path = "res://terrain/island.stamp"
	island.height = ISLAND_HEIGHT
	island.length = 620.0
	island.width = 620.0
	island.position = Vector3(0.0, ISLAND_HEIGHT, 0.0)
	terrain.add_child(island)
	return terrain


func _run() -> void:
	_check_scene()

	var filed := _old_island()
	var started := Time.get_ticks_usec()
	root.add_child(filed)
	var old_time := (Time.get_ticks_usec() - started) / 1e6
	var stamped := _new_island()
	started = Time.get_ticks_usec()
	root.add_child(stamped)
	var new_time := (Time.get_ticks_usec() - started) / 1e6
	print("ready: from the height file %.2f s, from the seabed and the island stamp %.2f s"
			% [old_time, new_time])
	await process_frame

	# --- every height sample ---
	var a: PackedFloat32Array = filed._heights
	var b: PackedFloat32Array = stamped._heights
	check(a.size() == b.size(), "the grids differ: %d samples against %d" % [a.size(), b.size()])
	var differ := 0
	var worst := 0.0
	var worst_at := -1
	for i in mini(a.size(), b.size()):
		var gap := absf(a[i] - b[i]) * 180.0
		if gap > 0.0:
			differ += 1
		if gap > worst:
			worst = gap
			worst_at = i
	print("samples: %d of %d differ, worst %.6f m (sample %d)" % [differ, a.size(), worst, worst_at])
	check(worst < TOLERANCE, "a height sample is %.4f m from the island file - sample %d, row %d"
			% [worst, worst_at, worst_at / 1025])

	# --- between samples ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var between := 0.0
	for i in 20000:
		var x := rng.randf_range(-310.0, 310.0)
		var z := rng.randf_range(-310.0, 310.0)
		between = maxf(between, absf(filed.height_at(x, z) - stamped.height_at(x, z)))
	print("height_at at 20000 points: worst %.6f m" % between)
	check(between < TOLERANCE, "height_at is %.4f m from the island file between samples" % between)

	# --- the mesh ---
	filed.generate()
	stamped.generate()
	var chunks: int = filed._chunks.size()
	check(chunks == stamped._chunks.size(), "%d chunks against %d" % [chunks, stamped._chunks.size()])
	var vertices := 0
	var mesh_worst := 0.0
	for c in mini(chunks, stamped._chunks.size()):
		var va: PackedVector3Array = filed._chunks[c].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var vb: PackedVector3Array = stamped._chunks[c].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		check(va.size() == vb.size(), "chunk %d has %d vertices against %d" % [c, va.size(), vb.size()])
		for v in mini(va.size(), vb.size()):
			mesh_worst = maxf(mesh_worst, va[v].distance_to(vb[v]))
		vertices += va.size()
	print("mesh: %d vertices in %d chunks, worst %.6f m apart" % [vertices, chunks, mesh_worst])
	# Every vertex: 256 chunks of 33 x 33, the chunks being indexed meshes.
	check(vertices > 250000, "only %d vertices compared - the check proves little" % vertices)
	check(mesh_worst < TOLERANCE, "a mesh vertex is %.4f m from where the island file put it"
			% mesh_worst)

	_check_seabed_alone()
	print("island_stamp_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


## main.tscn's Island has to be the stamp built above, and the first stamp under the Terrain,
## after its Seabed - or everything measured here is about a different island.
func _check_scene() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	var terrain := scene.get_node("Terrain")
	var seabed_seen := false
	var first_stamp: TerrainStamp = null
	for child in terrain.get_children():
		if child is Seabed:
			seabed_seen = first_stamp == null
		if child is TerrainStamp and first_stamp == null:
			first_stamp = child
	check(seabed_seen, "main.tscn's Terrain has no Seabed ahead of its stamps")
	check(first_stamp != null and first_stamp.name == "Island",
			"the first stamp under the Terrain is %s, not the Island - a pad before it would be"
			% (first_stamp.name if first_stamp != null else "nothing") + " wiped out by it")
	if first_stamp != null:
		var island := first_stamp
		check(island.mode == TerrainStamp.Mode.REPLACE and island.shape == TerrainStamp.Shape.IMAGE
				and island.stamp_path == "res://terrain/island.stamp" and island.opacity == 1.0
				and island.border_fade == 0.0,
				"main.tscn's Island is not a full Replace of terrain/island.stamp")
		check(island.height == ISLAND_HEIGHT and island.position.y == ISLAND_HEIGHT,
				"main.tscn's Island stands at %.6f m with %.6f m of height, not %.6f m for both"
				% [island.position.y, island.height, ISLAND_HEIGHT])
		check(island.length == 620.0 and island.width == 620.0
				and Vector2(island.position.x, island.position.z) == Vector2.ZERO
				and island.basis.is_equal_approx(Basis.IDENTITY),
				"main.tscn's Island is not 620 m square, unturned, on the Terrain's middle")
	scene.free()


## With nothing on it, the ground is the bed the Seabed describes - at the Terrain's own sea
## level and in its metres.
func _check_seabed_alone() -> void:
	var terrain := _terrain()
	var seabed := Seabed.new()
	seabed.noise = FastNoiseLite.new()
	seabed.depth = 7.0
	seabed.noise_height = 2.0
	terrain.add_child(seabed)
	root.add_child(terrain)
	var sea: float = terrain.sea_level()
	var area := Rect2(-310.0, -310.0, 620.0, 620.0)
	var worst := 0.0
	var spacing := 620.0 / 1024.0
	for i in 200:
		var x := -310.0 + (i * 37 % 1025) * spacing
		var z := -310.0 + (i * 91 % 1025) * spacing
		worst = maxf(worst, absf(terrain.height_at(x, z) - seabed.height_at(x, z, sea, area)))
	print("seabed alone: the ground is at worst %.6f m from the bed it describes" % worst)
	check(worst < TOLERANCE, "with only a Seabed the ground is %.4f m off its bed" % worst)
	terrain.free()
