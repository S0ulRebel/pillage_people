extends SceneTree
## Run: godot --headless --path . --script res://tests/island_stamp_check.gd
##
## Is main.tscn's Island the island?
##
## It used to BE the ground: terrain/island.r16, read as the height map. Now the ground starts
## as a Seabed and the island is a Replace stamp on it - terrain/island.stamp, the same numbers
## read with mid-grey as zero. That was shown to give the same ground as the file, to 0.015 mm
## at every sample, before the file and its loader went; tests/island_terrain.gd builds it for
## the tests that were written against the file.
##
## What is left to hold: that main.tscn's Island is that stamp, first under the Terrain after
## its Seabed; that it fades into the Seabed over its outer ISLAND_FADE metres, the plain slope
## round the shelf, so the square's edge is seabed and the far ring carries on from it with no
## step - inside the fade the island is the stamp's to the same millimetre, at the edge the
## ground is the Seabed's, and nowhere does the ground jump as it crosses the edge; and that the
## Seabed on its own lays down the bed it describes, at the Terrain's sea level.

const ISLAND := preload("res://tests/island_terrain.gd")
const TERRAIN := preload("res://world/terrain.gd")
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
	terrain.world_size = ISLAND.SIZE
	return terrain


func _new_island(fade := 0.0) -> Node3D:
	var terrain := _seabed_only()
	terrain.add_child(ISLAND.island(fade))
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
	var whole := _new_island()
	var started := Time.get_ticks_usec()
	root.add_child(whole)
	print("ready: the seabed and the island stamp in %.2f s" % ((Time.get_ticks_usec() - started) / 1e6))
	await process_frame
	await _check_fade(whole)
	_check_seabed_alone()
	whole.free()
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
		check(island.height == ISLAND.HEIGHT and island.position.y == ISLAND.Y,
				"main.tscn's Island stands at %.6f m with %.6f m of height, not %.6f m with %.6f m"
				% [island.position.y, island.height, ISLAND.Y, ISLAND.HEIGHT])
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


## The island as main.tscn has it, faded over its outer ISLAND_FADE metres into the Seabed, against
## `whole`, the same island unfaded on the same bed.
func _check_fade(whole: Node3D) -> void:
	var faded := _new_island(ISLAND_FADE)
	root.add_child(faded)
	var bed := _seabed_only()
	root.add_child(bed)
	await process_frame
	var a: PackedFloat32Array = whole._heights
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
	print("faded island: core %.6f m from the whole stamp, edge %.6f m from the bed alone, %d samples"
			% [core, edge, faded_samples] + " in the fade; on the edge the two grounds differ at worst"
			+ " %.6f m on its samples, %.4f m between them" % [jump, between])
	check(core < TOLERANCE, "inside its fade the island is %.4f m from the whole stamp" % core)
	check(edge < TOLERANCE, "at the square's edge the ground is %.4f m off the bed - the island's"
			% edge + " fade does not reach zero there")
	check(jump < TOLERANCE, "on the square's edge the chunks' ground and the far ring's are %.4f m"
			% jump + " apart - a step where one takes over from the other")
	check(between < 0.01, "between the edge's samples the two grounds part by %.3f m" % between)
	faded.free()
	bed.free()
