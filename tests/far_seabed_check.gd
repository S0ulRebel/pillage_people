extends SceneTree
## Run: godot --headless --path . --script res://tests/far_seabed_check.gd
##
## The ground past the Terrain's square: the far ring the Terrain builds from its Seabed, out to
## far_extent. Checked where it could go wrong without being seen in a still picture:
##
## - the stitch. Every vertex the chunks have on the square's edge is a vertex of the ring too,
##   at the same height, and the ring has nothing inside the square - so there is no crack at the
##   edge, and no second skin over the chunks.
## - the collider. Standing just inside the edge, just outside it and anywhere on the ring, a ray
##   down finds ground, at height_at()'s height - there is no gap to fall through at the join.
## - the water. The texture the sea reads its depth from out there is the same ground.
## - a stamp that reaches past the edge still shapes the ground there - a crater dug at the
##   island's edge carries on into the ring rather than stopping at a wall.
## - far out, the bed is at the Seabed's far depth.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")
const ISLAND_HEIGHT := 90.001373291015625

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	var seabed := Seabed.new()
	seabed.noise = FastNoiseLite.new()
	terrain.add_child(seabed)
	var island := STAMP.instantiate() as TerrainStamp
	island.mode = TerrainStamp.Mode.REPLACE
	island.stamp_path = "res://terrain/island.stamp"
	island.height = ISLAND_HEIGHT
	island.length = 620.0
	island.width = 620.0
	island.border_fade = 90.0
	island.position = Vector3(0.0, ISLAND_HEIGHT, 0.0)
	terrain.add_child(island)
	# A hole dug at the island's edge, its fade reaching sixteen metres past it.
	var dig := STAMP.instantiate() as TerrainStamp
	dig.shape = TerrainStamp.Shape.SOFT_CIRCLE
	dig.height = -4.0
	dig.length = 24.0
	dig.width = 24.0
	dig.edge_softness = 8.0
	dig.position = Vector3(305.0, 0.0, -100.0)
	terrain.add_child(dig)
	root.add_child(terrain)
	var started := Time.get_ticks_msec()
	terrain.generate()
	print("generated with the far ring in %d ms" % (Time.get_ticks_msec() - started))
	await physics_frame
	await physics_frame

	var half := 310.0
	var ring := terrain.get_node_or_null("FarSeabed") as MeshInstance3D
	check(ring != null and ring.mesh != null, "the Terrain built no far ring")
	if ring == null or ring.mesh == null:
		_finish()
		return
	print("far ring: %.0f m across, cells %.3f m" % [terrain.far_size(), terrain._far_step])
	check(terrain.far_size() >= 2.0 * terrain.far_extent - terrain._far_step,
			"the far ring spans %.0f m, short of far_extent %.0f m each way"
			% [terrain.far_size(), terrain.far_extent])

	# --- the stitch ---
	# On the square's edge itself - not on the lines it runs along, out past its corners.
	var edge_of := func(p: Vector3) -> bool:
		var on_x := absf(absf(p.x) - half) < 0.0001 and absf(p.z) <= half + 0.0001
		var on_z := absf(absf(p.z) - half) < 0.0001 and absf(p.x) <= half + 0.0001
		return on_x or on_z
	var chunk_edge := {}
	for chunk in terrain._chunks:
		for p: Vector3 in chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if edge_of.call(p):
				chunk_edge[Vector2i(roundi(p.x * 1000.0), roundi(p.z * 1000.0))] = p.y
	var ring_edge := {}
	var inside := 0
	for p: Vector3 in ring.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if edge_of.call(p):
			ring_edge[Vector2i(roundi(p.x * 1000.0), roundi(p.z * 1000.0))] = p.y
		elif absf(p.x) < half and absf(p.z) < half:
			inside += 1
	var missing := 0
	var misplaced := 0
	var worst := 0.0
	for key in chunk_edge:
		if not ring_edge.has(key):
			missing += 1
			continue
		worst = maxf(worst, absf(chunk_edge[key] - ring_edge[key]))
	for key in ring_edge:
		if not chunk_edge.has(key):
			misplaced += 1
	print("stitch: %d chunk vertices on the edge, %d missing from the ring, %d ring vertices on"
			% [chunk_edge.size(), missing, misplaced] + " it the chunks do not have, worst %.6f m"
			% worst + " apart; %d ring vertices inside the square" % inside)
	check(chunk_edge.size() >= 4 * 512, "only %d chunk vertices found on the edge" % chunk_edge.size())
	check(missing == 0, "%d of the chunks' edge vertices have no ring vertex - a crack" % missing)
	check(misplaced == 0, "%d ring vertices on the edge are not the chunks' - a T-junction" % misplaced)
	check(worst < 0.0001, "the ring and the chunks are %.4f m apart on the edge" % worst)
	check(inside == 0, "%d ring vertices are inside the square, over the chunks' ground" % inside)
	# And the ring's own cells split the way _drawn() says, and the collider does.
	var arrays := ring.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var wrong_way := 0
	for t in range(0, indices.size(), 3):
		for e in 3:
			var p: Vector3 = vertices[indices[t + e]]
			var q: Vector3 = vertices[indices[t + (e + 1) % 3]]
			var dx := q.x - p.x
			var dz := q.z - p.z
			var diagonal := absf(absf(dx) - terrain._far_step) < 0.001 \
					and absf(absf(dz) - terrain._far_step) < 0.001
			if diagonal and dx * dz > 0.0:
				wrong_way += 1
	check(wrong_way == 0, "%d of the far ring's cells are split the other way from the collider's"
			% wrong_way)

	# --- the collider ---
	var space := terrain.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var points: Array[Vector2] = []
	for i in 200:
		var along := rng.randf_range(-half, half)
		for across in [half - 0.3, half + 0.3]:
			points.append(Vector2(across, along))
			points.append(Vector2(-along, -across))
	for i in 400:
		var angle := rng.randf() * TAU
		var out := rng.randf_range(half * 1.45, terrain.far_extent - 20.0)
		points.append(Vector2(cos(angle), sin(angle)) * out)
	# Over the dig a far cell - ten metres - cannot follow a hole twenty-four across, so there the
	# rays only have to find ground.
	var dug_rect := dig.footprint().grow(terrain._far_step)
	var misses := 0
	var off := 0.0
	var worst_at := Vector2.ZERO
	var drawn_off := 0.0
	for p in points:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 300.0, p.y), Vector3(p.x, -300.0, p.y)))
		if hit.is_empty():
			misses += 1
			continue
		var apart := absf(hit.position.y - terrain.height_at(p.x, p.y))
		if apart > off and not dug_rect.has_point(p):
			off = apart
			worst_at = p
		if absf(p.x) > half + terrain._far_step or absf(p.y) > half + terrain._far_step:
			drawn_off = maxf(drawn_off, absf(hit.position.y - _drawn(terrain, p)))
	print("collider: %d rays at and past the edge, %d found nothing, worst %.3f m off height_at"
			% [points.size(), misses, off] + " at (%.1f, %.1f), %.4f m off the drawn ring"
			% [worst_at.x, worst_at.y, drawn_off])
	check(misses == 0, "%d rays at or past the square's edge fell through - a gap in the ground"
			% misses)
	# What is walked on is what is drawn: the collider is the ring's own samples, split into
	# triangles the same way.
	check(drawn_off < 0.001, "the collider is %.4f m off the far ring as drawn" % drawn_off)
	# A far cell is ten metres and height_at() the bed itself, so the two part a little between
	# the ring's samples: the bed's finest bumps are some twenty metres across, and that is not
	# far from straight over half of one. Forty metres under, nobody sees it.
	check(off < 0.25, "the collider is %.3f m off the ground height_at() reports" % off)

	# --- the water ---
	var image: Image = terrain.far_texture().get_image()
	var count: int = terrain._far_count
	var water_off := 0.0
	for i in 500:
		var gx := rng.randi_range(0, count - 1)
		var gz := rng.randi_range(0, count - 1)
		var cells := (count - 1) / 2
		var truth: float = terrain.height_at((gx - cells) * terrain._far_step, (gz - cells) * terrain._far_step)
		water_off = maxf(water_off, absf(image.get_pixel(gx, gz).r - truth))
	var floor_wanted: float = terrain.sea_level() - seabed.far_depth
	print("water: the far texture is at worst %.6f m from height_at; past it the bed is %.2f m"
			% [water_off, terrain.far_floor()])
	check(water_off < 0.001, "the water's far texture is %.4f m off the ground" % water_off)
	check(absf(terrain.far_floor() - floor_wanted) < 0.001,
			"past the far texture the water puts the bed at %.2f m, not %.2f m"
			% [terrain.far_floor(), floor_wanted])

	# --- a stamp past the edge ---
	var outside := Vector2(314.0, -100.0)
	var bare: float = seabed.height_at(outside.x, outside.y, terrain.sea_level(), Vector2.ZERO)
	var dug: float = terrain.height_at(outside.x, outside.y) - bare
	var wanted: float = dig.height * dig.value_at(outside.x, outside.y)
	print("past the edge the dig takes the ground %.2f m down; the stamp says %.2f m" % [-dug, -wanted])
	check(absf(wanted) > 0.5, "the dig barely reaches past the edge - the check proves nothing")
	check(absf(dug - wanted) < 0.01, "past the edge the ground is %.2f m off what the dig says"
			% absf(dug - wanted))

	# --- far out ---
	var deep := 0.0
	for i in 50:
		var angle := rng.randf() * TAU
		var at := Vector2(cos(angle), sin(angle)) * rng.randf_range(1000.0, 1150.0)
		deep = maxf(deep, absf(terrain.height_at(at.x, at.y) - floor_wanted))
	print("far out the bed is at worst %.2f m from the far depth" % deep)
	check(deep <= seabed.noise_height + 0.01, "far out the bed is %.2f m off the far depth" % deep)
	_finish()


## The far ring's height at a point, as its triangles draw it: the cell's four samples, split
## from (i + 1, j) to (i, j + 1) - the way Jolt splits a height field's cells, which the ring
## follows so that its collider is its drawn ground.
func _drawn(terrain: Node, p: Vector2) -> float:
	var cells: int = (terrain._far_count - 1) / 2
	var step: float = terrain._far_step
	var i := floori(p.x / step) + cells
	var j := floori(p.y / step) + cells
	var u := p.x / step + cells - i
	var v := p.y / step + cells - j
	var at := func(di: int, dj: int) -> float:
		return terrain._far_heights[(j + dj) * terrain._far_count + i + di]
	var a: float = at.call(0, 0)
	var b: float = at.call(1, 0)
	var c: float = at.call(1, 1)
	var d: float = at.call(0, 1)
	if u + v <= 1.0:
		return a + u * (b - a) + v * (d - a)
	return c + (1.0 - u) * (d - c) + (1.0 - v) * (b - c)


func _finish() -> void:
	print("far_seabed_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
