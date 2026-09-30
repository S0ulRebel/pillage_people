extends SceneTree
## Run: godot --headless --path . --script res://tests/island_stamp_check.gd
##
## Is the island the same island now that it is a stamp?
##
## It used to BE the ground: terrain/island.r16, read as the height map. Now the ground starts
## as a Seabed and the island is a Replace stamp on it - terrain/island.stamp, the same numbers
## read with mid-grey as zero, so the stamp's height is 180 x 32768 / 65535 m and its Y the
## same less the 18 m the file puts its sea at, and Y + value x height gives back exactly what
## the file said, measured from the sea. This builds both and compares
## every height sample, height_at() between them, and every vertex of the mesh; and checks
## main.tscn's Island is the stamp built here, so the two cannot drift apart.
##
## main.tscn's Island also fades into the Seabed over its outer ISLAND_FADE metres, the plain
## slope round the shelf, so the square's edge is seabed and the far ring carries on from it
## with no step. That is checked on its own: inside the fade the island is the file's to the
## same millimetre, at the edge the ground is the Seabed's, and nowhere does the ground jump as
## it crosses the edge.
##
## It also checks the Seabed on its own, with nothing on it: that the ground it lays down is
## the bed it describes, at the Terrain's sea level.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")
## 180 x 32768 / 65535, to a float's width: the transform that carries the stamp's Y is 32-bit,
## and this and the Y below are both exact in it, so Y + value x height is H x (1 + value) less
## 18 m to the last bit of a double. The heights are stored 32-bit, and about one sample in
## fifty lands a step or two away from the file's - 0.015 mm. Everything is held to a millimetre.
const ISLAND_HEIGHT := 90.001373291015625
## Where it stands: its lowest value, the file's 0, is 18 m under the sea - the file's sea is a
## tenth of the way up its 180 m.
const ISLAND_Y := ISLAND_HEIGHT - 18.0
## main.tscn's Island's border_fade: metres inside its border over which it gives way to the bed.
const ISLAND_FADE := 90.0
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
	terrain.file_height = 180.0
	return terrain


func _old_island() -> Node3D:
	var terrain := _terrain()
	terrain.raw_path = "res://terrain/island.r16"
	return terrain


func _new_island(fade := 0.0) -> Node3D:
	var terrain := _seabed_only()
	var island := STAMP.instantiate() as TerrainStamp
	island.name = "Island"
	island.mode = TerrainStamp.Mode.REPLACE
	island.stamp_path = "res://terrain/island.stamp"
	island.height = ISLAND_HEIGHT
	island.length = 620.0
	island.width = 620.0
	island.border_fade = fade
	island.position = Vector3(0.0, ISLAND_Y, 0.0)
	terrain.add_child(island)
	return terrain


## A Terrain with a Seabed and nothing on it - the same bed under every island built here.
func _seabed_only() -> Node3D:
	var terrain := _terrain()
	var seabed := Seabed.new()
	seabed.noise = FastNoiseLite.new()
	terrain.add_child(seabed)
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
		var gap := absf(a[i] - b[i])
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

	await _check_fade(filed)
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
				and island.border_fade == ISLAND_FADE,
				"main.tscn's Island is not a full Replace of terrain/island.stamp, faded over %.0f m"
				% ISLAND_FADE)
		check(island.height == ISLAND_HEIGHT and island.position.y == ISLAND_Y,
				"main.tscn's Island stands at %.6f m with %.6f m of height, not %.6f m with %.6f m"
				% [island.position.y, island.height, ISLAND_Y, ISLAND_HEIGHT])
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
	var worst := 0.0
	var spacing := 620.0 / 1024.0
	for i in 200:
		var x := -310.0 + (i * 37 % 1025) * spacing
		var z := -310.0 + (i * 91 % 1025) * spacing
		worst = maxf(worst, absf(terrain.height_at(x, z) - seabed.height_at(x, z) - sea))
	print("seabed alone: the ground is at worst %.6f m from the bed it describes" % worst)
	check(worst < TOLERANCE, "with only a Seabed the ground is %.4f m off its bed" % worst)
	terrain.free()


## The island as main.tscn has it, faded over its outer ISLAND_FADE metres into the Seabed.
func _check_fade(filed: Node3D) -> void:
	var faded := _new_island(ISLAND_FADE)
	root.add_child(faded)
	var bed := _seabed_only()
	root.add_child(bed)
	await process_frame
	var a: PackedFloat32Array = filed._heights
	var b: PackedFloat32Array = faded._heights
	var c: PackedFloat32Array = bed._heights
	var size: int = faded._size
	var spacing := 620.0 / float(size - 1)
	var core := 0.0
	var edge := 0.0
	var faded_samples := 0
	for gz in size:
		for gx in size:
			var i := gz * size + gx
			var inside := minf(minf(gx, size - 1 - gx), minf(gz, size - 1 - gz)) * spacing
			if inside >= ISLAND_FADE:
				core = maxf(core, absf(a[i] - b[i]))
			elif inside == 0.0:
				edge = maxf(edge, absf(b[i] - c[i]))
			else:
				faded_samples += 1
	# ON the edge, the same point read both ways: as the chunks read it, from the baked samples,
	# and as the far ring does, from the Seabed and the stamps at the point itself. A step there
	# is a step between the two grounds. (Compared a few centimetres apart instead, the answer
	# was mostly the bed's own slope - it drops up to a quarter of a metre a metre out there.)
	#
	# On the edge's own samples - where the mesh and both colliders have their vertices - the two
	# have to be the same. Halfway between them the chunks' ground is a straight line from one
	# sample to the next and the far ring's the bed's own curve, and they part by a millimetre
	# or two; that is only what height_at() says there, and nothing is built from it.
	var jump := 0.0
	var between := 0.0
	for k in size - 1:
		for half_step in [0.0, 0.5]:
			var along: float = -310.0 + (k + half_step) * spacing
			for side in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var on: Vector2 = side * 310.0 + Vector2(side.y, side.x) * along
				var gap := absf(faded.height_at(on.x, on.y) - faded._far_height(on.x, on.y))
				if half_step == 0.0:
					jump = maxf(jump, gap)
				else:
					between = maxf(between, gap)
	print("faded island: core %.6f m from the file, edge %.6f m from the bed alone, %d samples"
			% [core, edge, faded_samples] + " in the fade; on the edge the two grounds differ at worst"
			+ " %.6f m on its samples, %.4f m between them" % [jump, between])
	check(core < TOLERANCE, "inside its fade the island is %.4f m from the file" % core)
	check(edge < TOLERANCE, "at the square's edge the ground is %.4f m off the bed - the island's"
			% edge + " fade does not reach zero there")
	check(jump < TOLERANCE, "on the square's edge the chunks' ground and the far ring's are %.4f m"
			% jump + " apart - a step where one takes over from the other")
	check(between < 0.01, "between the edge's samples the two grounds part by %.3f m" % between)
	faded.free()
	bed.free()
