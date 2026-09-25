extends SceneTree
## Run: godot --headless --path . --script res://tests/chunk_check.gd
##
## The ground is built in chunks, and an edit rebuilds only the chunks it touches. That is only
## right if what comes out is exactly what building from scratch would give - and the cheap
## ways to get it wrong (a stamp's old ground left behind, a tunnel's hole left where it was,
## a neighbouring chunk not redone though its normals read the moved ground, a crossing tunnel
## still trimmed against where the other one used to be) all show up as a difference. So:
##
##   Terrain A is built, then edited - a mountain and a stamp in the island's far corner are
##   moved, a cave is moved a chunk over, a flatten pad is removed, and a pad is added whose
##   fade ends a hand's width short of a chunk border - and asked to rebuild what changed.
##   Terrain B is built from scratch with everything already where A has it. Every height
##   sample, every chunk's vertices, normals and colours, and every tunnel's tube must match.
##   Two tunnels are never edited: one crossing the cave, one under the moved mountain. Their
##   tubes must change all the same, and match B.
##
##   The chunks A rebuilt are read off the mesh objects it replaced: few of them, and among
##   them the ones over each edit. Neighbouring chunks must share their border vertices. The
##   grass patch under the mountain must stand on the moved ground.
##
##   All of it twice: with the default 32-quad chunks, and with 48-quad ones, which 512 quads
##   do not divide, so the last row and column are ragged.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")
const PATCH := preload("res://props/grass/grass_patch.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	await _scenario(32)
	await _scenario(48)
	print("chunk_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


# --- the pieces --------------------------------------------------------------------------------

func _terrain(chunk_quads: int) -> Node3D:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	terrain.chunk_quads = chunk_quads
	return terrain


func _mountain(at: Vector3) -> TerrainStamp:
	var stamp := STAMP.instantiate() as TerrainStamp
	stamp.name = "Mountain"
	stamp.stamp_path = "res://world/terrain_stamp/stamps/mountain.r16"
	stamp.strength = 45.0
	stamp.length = 110.0
	stamp.width = 90.0
	stamp.position = at
	stamp.rotation.y = 0.7
	return stamp


func _corner_stamp(at: Vector3) -> TerrainStamp:
	var stamp := STAMP.instantiate() as TerrainStamp
	stamp.name = "Corner"
	stamp.stamp_path = "res://world/terrain_stamp/stamps/mesa.r16"
	stamp.strength = 20.0
	stamp.length = 40.0
	stamp.width = 40.0
	stamp.position = at
	return stamp


func _pad(pad_name: String, at: Vector3, length: float, width: float) -> TerrainStamp:
	var stamp := STAMP.instantiate() as TerrainStamp
	stamp.name = pad_name
	stamp.mode = TerrainStamp.Mode.FLATTEN
	stamp.shape = TerrainStamp.Shape.SOFT_RECT
	stamp.length = length
	stamp.width = width
	stamp.edge_softness = 5.0
	stamp.position = at
	return stamp


func _tunnel(tunnel_name: String, points: Array) -> Tunnel:
	var tunnel := Tunnel.new()
	tunnel.name = tunnel_name
	tunnel.section = Tunnel.Section.ARCH
	tunnel.width = 6.0
	tunnel.height = 5.0
	tunnel.curve = Curve3D.new()
	for point: Vector3 in points:
		tunnel.curve.add_point(point)
	return tunnel


func _patch(at: Vector3) -> GrassPatch:
	var patch := PATCH.instantiate() as GrassPatch
	patch.name = "Grass"
	patch.radius = 3.0
	patch.tufts = 20
	patch.position = at
	return patch


# --- the scenario -------------------------------------------------------------------------------

func _scenario(chunk_quads: int) -> void:
	print("--- chunk_quads %d ---" % chunk_quads)
	# The cave is on the hillside tunnel_check uses, on the west side; the mountain is on the
	# east side, so no chunk over the cave is rebuilt for the mountain's sake. The cave moves
	# 40 m, more than a chunk, so its old and new holes are in different chunks. The corner
	# stamp sits in the last chunk row and column, mostly off the island.
	var mountain_before := Vector3(60.0, 0.0, -20.0)
	var mountain_after := Vector3(90.0, 0.0, -5.0)
	var corner_before := Vector3(290.0, 0.0, 290.0)
	var corner_after := Vector3(282.0, 0.0, 296.0)
	var pad_at := Vector3(90.0, 0.0, -70.0)
	var cave_from := Vector3(-110.0, 26.5, -10.0)
	var cave_to := Vector3(-84.0, 25.5, -10.0)
	var cave_shift := Vector3(0.0, 0.0, 40.0)
	# Along z at x = -97, at the cave's depth: it crosses the cave where the cave was and
	# where it goes.
	var crossing_points: Array = [Vector3(-97.0, 26.5, -30.0), Vector3(-97.0, 25.5, 50.0)]
	var patch_at := Vector3(84.0, 0.0, 6.0)   # under the mountain once it has moved

	# --- A: built one way, then edited ---
	var a := _terrain(chunk_quads)
	var mountain := _mountain(mountain_before)
	var corner := _corner_stamp(corner_before)
	var cave := _tunnel("Cave", [cave_from, cave_to])
	var crossing := _tunnel("Crossing", crossing_points)
	var patch := _patch(patch_at)
	for child in [mountain, corner, cave, crossing, patch]:
		a.add_child(child)
	root.add_child(a)
	await process_frame
	# Under the moved mountain. At 23 m it opens out of the hillside at (88, -2), where the old
	# mountain leaves the ground at 22.6 m, and dead-ends uphill; the new mountain lifts the
	# ground there to 55 m, burying it end to end.
	var buried_from := Vector3(88.0, 23.0, -2.0)
	var buried_to := Vector3(64.0, 23.0, 9.0)
	var buried := _tunnel("Buried", [buried_from, buried_to])
	a.add_child(buried)
	# The pad joins after _ready() has laid the heights down, 2 m above natural ground: an edit
	# generate() has to apply before it builds.
	var pad := _pad("Pad", pad_at, 24.0, 18.0)
	pad.position.y = a.height_at(pad_at.x, pad_at.z) + 2.0
	a.add_child(pad)
	patch.position.y = a.height_at(patch_at.x, patch_at.z)
	await _settle()
	var started := Time.get_ticks_msec()
	a.generate()
	print("built A from scratch: %d chunks, %d tunnels, %d ms"
			% [a._chunks.size(), a.tunnels.size(), Time.get_ticks_msec() - started])
	await process_frame
	var chunk_count: int = a._chunks.size()
	check(a.tunnels.size() == 3, "A built %d of 3 tunnels" % a.tunnels.size())
	var pad_height: float = a.height_at(pad_at.x, pad_at.z)
	check(absf(pad_height - pad.position.y) < 0.01,
			"the pad added before generate() was not applied: ground %.2f, plane %.2f" % [pad_height, pad.position.y])
	var crossing_before := _tube(crossing)
	var buried_before := _tube(buried)
	var meshes_before: Array = []
	for index in chunk_count:
		meshes_before.append(a._chunks[index].mesh)

	# --- the edits ---
	mountain.position = mountain_after
	corner.position = corner_after
	cave.position += cave_shift
	a.remove_child(pad)
	# Its fade ends 0.3 m short of the chunk border at x = 38.75 (a border for both grids).
	# The border vertices there read the sample 0.6 m inside, which the pad moves, so the chunk
	# beyond the border has to be rebuilt for its normals though no vertex of it moves.
	var border_pad := _pad("BorderPad", Vector3(38.75 - 0.3 - 15.0, 0.0, 30.0), 20.0, 12.0)
	border_pad.position.y = a.height_at(border_pad.position.x, border_pad.position.z) + 1.5
	a.add_child(border_pad)
	await _settle()
	started = Time.get_ticks_msec()
	a.rebuild_changed()
	var took := Time.get_ticks_msec() - started
	pad.queue_free()

	var rebuilt: Array[int] = []
	for index in chunk_count:
		if a._chunks[index].mesh != meshes_before[index]:
			rebuilt.append(index)
	print("A rebuilt %d of %d chunks in %d ms (it reports %d)" % [rebuilt.size(), chunk_count, took, a.last_rebuilt])
	check(rebuilt.size() == a.last_rebuilt, "last_rebuilt says %d, but %d chunk meshes were replaced" % [a.last_rebuilt, rebuilt.size()])
	check(rebuilt.size() > 0, "the edits rebuilt nothing")
	check(rebuilt.size() < chunk_count / 3, "rebuilt %d of %d chunks - not a partial rebuild" % [rebuilt.size(), chunk_count])
	for spot in [["the cave's old mouth", cave_from], ["the old mountain", mountain_before],
			["the removed pad", pad_at], ["the corner stamp", corner_before],
			["the chunk beyond the border pad", Vector3(39.5, 0.0, 30.0)]]:
		var index := _chunk_at(a, spot[1])
		check(rebuilt.has(index), "the chunk over %s (%d) was not rebuilt" % [spot[0], index])

	# --- B: built from scratch with everything where A has it now ---
	var b := _terrain(chunk_quads)
	var mountain_b := _mountain(mountain_after)
	var corner_b := _corner_stamp(corner_after)
	var cave_b := _tunnel("Cave", [cave_from, cave_to])
	cave_b.position = cave_shift
	var crossing_b := _tunnel("Crossing", crossing_points)
	var patch_b := _patch(patch_at)
	patch_b.position.y = patch.position.y
	var buried_b := _tunnel("Buried", [buried_from, buried_to])
	var border_pad_b := _pad("BorderPad", border_pad.position, 20.0, 12.0)
	for child in [mountain_b, corner_b, cave_b, crossing_b, patch_b, buried_b, border_pad_b]:
		b.add_child(child)
	root.add_child(b)
	await process_frame
	b.generate()
	await process_frame
	check(b.tunnels.size() == 3, "B built %d of 3 tunnels" % b.tunnels.size())

	# --- the same ground ---
	var heights_a: PackedFloat32Array = a._heights
	var heights_b: PackedFloat32Array = b._heights
	var height_diffs := 0
	var where := Rect2()
	var size: int = a._size
	var spacing: float = a.world_size / float(size - 1)
	for i in heights_a.size():
		if heights_a[i] != heights_b[i]:
			var at := Vector2((i % size) * spacing - 310.0, (i / size) * spacing - 310.0)
			where = Rect2(at, Vector2.ZERO) if height_diffs == 0 else where.expand(at)
			height_diffs += 1
	print("height samples that differ: %d of %d%s" % [height_diffs, heights_a.size(),
			"" if height_diffs == 0 else ", within x %.0f..%.0f z %.0f..%.0f"
			% [where.position.x, where.end.x, where.position.y, where.end.y]])
	check(height_diffs == 0, "%d height samples differ from a build from scratch" % height_diffs)

	var chunk_diffs := 0
	var normal_diffs := 0
	var colour_diffs := 0
	var triangles := 0
	for index in chunk_count:
		var surface_a := _surface(a, index)
		var surface_b := _surface(b, index)
		triangles += surface_b[3]
		if surface_a[0] != surface_b[0]:
			chunk_diffs += 1
		if surface_a[1] != surface_b[1]:
			normal_diffs += 1
		if surface_a[2] != surface_b[2]:
			colour_diffs += 1
	print("chunks that differ: %d by vertices, %d by normals, %d by colours, of %d (%d triangles)"
			% [chunk_diffs, normal_diffs, colour_diffs, chunk_count, triangles])
	check(chunk_diffs == 0, "%d chunks' vertices differ from a build from scratch" % chunk_diffs)
	check(normal_diffs == 0, "%d chunks' normals differ from a build from scratch" % normal_diffs)
	check(colour_diffs == 0, "%d chunks' colours differ from a build from scratch" % colour_diffs)

	for pair in [["Cave", cave, cave_b], ["Crossing", crossing, crossing_b], ["Buried", buried, buried_b]]:
		var tube_a := _tube(pair[1])
		var tube_b := _tube(pair[2])
		print("%s: %d triangles in A, %d in B, %s" % [pair[0], tube_a.size() / 3, tube_b.size() / 3,
				"same" if tube_a == tube_b else "DIFFERENT"])
		check(tube_a.size() > 0, "%s has no tube" % pair[0])
		check(tube_a == tube_b, "%s's tube differs from a build from scratch" % pair[0])
	# Never edited, but the ground and the cave they depend on were: their tubes must have
	# changed, or the checks above would pass on a rebuild that left them alone.
	check(_tube(crossing) != crossing_before, "the crossing tunnel's tube did not change when the cave moved - the check proves nothing")
	check(_tube(buried) != buried_before, "the buried tunnel's tube did not change when the mountain moved onto it - the check proves nothing")

	# --- the seams ---
	var per_side: int = b._chunks_per_side
	var seams := 0
	var seam_faults := 0
	for cz in per_side:
		for cx in per_side:
			if cx + 1 < per_side:
				seams += 1
				if not _edges_match(b, cz * per_side + cx, cz * per_side + cx + 1, true):
					seam_faults += 1
			if cz + 1 < per_side:
				seams += 1
				if not _edges_match(b, cz * per_side + cx, (cz + 1) * per_side + cx, false):
					seam_faults += 1
	print("seams: %d checked, %d with a border that does not match" % [seams, seam_faults])
	check(seam_faults == 0, "%d chunk borders do not match their neighbour" % seam_faults)

	# --- the grass ---
	var field := patch.get_node_or_null("Tufts")
	check(field != null, "the grass patch has no tufts")
	if field != null:
		var worst := 0.0
		for placed in field._placed:
			worst = maxf(worst, absf(placed.origin.y - (a.height_at(placed.origin.x, placed.origin.z) - 0.05)))
		var lift: float = a.height_at(patch_at.x, patch_at.z) - patch.position.y
		print("grass: ground under the patch rose %.2f m with the mountain; tufts are %.3f m off it" % [lift, worst])
		check(lift > 1.0, "the mountain did not move the ground under the patch - the check proves nothing")
		check(worst < 0.02, "grass tufts are %.3f m off the moved ground" % worst)

	a.queue_free()
	b.queue_free()
	await process_frame


# --- helpers ------------------------------------------------------------------------------------

## Two frames: a node reports a moved transform on the next frame, not at once, and one await
## can resume before that frame's flush. The editor's rebuild waits a tenth of a second anyway.
func _settle() -> void:
	for i in 2:
		await process_frame


func _chunk_at(terrain: Node3D, at: Vector3) -> int:
	var size: float = terrain._chunk_size()
	var last: int = terrain._chunks_per_side - 1
	var cx := clampi(floori((at.x + 310.0) / size), 0, last)
	var cz := clampi(floori((at.z + 310.0) / size), 0, last)
	return cz * terrain._chunks_per_side + cx


## A chunk's vertices, normals and colours, and its triangle count.
func _surface(terrain: Node3D, index: int) -> Array:
	var instance: MeshInstance3D = terrain._chunks[index]
	if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0:
		return [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), 0]
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	# indexed, so the triangle count is the index count over three, not the vertex count
	return [arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_NORMAL], arrays[Mesh.ARRAY_COLOR],
			arrays[Mesh.ARRAY_INDEX].size() / 3]


func _tube(tunnel: Tunnel) -> PackedVector3Array:
	var mesh := tunnel.get_node_or_null("TunnelMesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
		return PackedVector3Array()
	return mesh.mesh.get_faces()


## Whether two neighbouring chunks agree along their shared border: the set of vertices the
## first has on its far edge is the set the second has on its near edge.
func _edges_match(terrain: Node3D, first: int, second: int, along_x: bool) -> bool:
	var faces_first: PackedVector3Array = _surface(terrain, first)[0]
	var faces_second: PackedVector3Array = _surface(terrain, second)[0]
	if faces_first.is_empty() or faces_second.is_empty():
		return true   # a chunk swallowed by a hole has no border to match
	var edge := -1e9
	for p in faces_first:
		edge = maxf(edge, p.x if along_x else p.z)
	var mine := {}
	for p in faces_first:
		if absf((p.x if along_x else p.z) - edge) < 0.0001:
			mine[p] = true
	var theirs := {}
	for p in faces_second:
		if absf((p.x if along_x else p.z) - edge) < 0.0001:
			theirs[p] = true
	if mine.is_empty() or theirs.is_empty():
		return false
	var only_mine: Array = []
	var only_theirs: Array = []
	for p in mine:
		if not theirs.has(p):
			only_mine.append(p)
	for p in theirs:
		if not mine.has(p):
			only_theirs.append(p)
	if only_mine.is_empty() and only_theirs.is_empty():
		return true
	print("    border between chunks %d and %d (%s): %d only in the first %s, %d only in the second %s"
			% [first, second, "x" if along_x else "z", only_mine.size(), only_mine.slice(0, 2),
			only_theirs.size(), only_theirs.slice(0, 2)])
	return false
