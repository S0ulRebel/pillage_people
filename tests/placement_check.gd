extends SceneTree
## Run: godot --headless --path . --script res://tests/placement_check.gd
##
## Checks world/ground.gd - the one place that puts a thing on the island.
##
## Written because the lift that created it went unproven. The cannon's ground-drop was moved
## into Ground and cannon_check still passed, which looked like evidence and was not: it also
## passed with Ground.sit replaced by `return false`. The cannon test never measured whether the
## cannon reaches the ground, so it could not have noticed either way.
##
## The case that matters is the one an origin-at-the-model would hide. An imported model's node
## sits wherever the exporter left it - sixty metres away, for the cannon - so putting the NODE
## on terrain.height_at leaves the visible thing somewhere else entirely. Everything here is
## measured on the mesh, never on the node.

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 30:
		await process_frame
	var terrain := scene.get_node("Terrain")
	var spawn: Vector3 = terrain.find_spawn()

	# --- finding the island from anywhere ---
	var deep := Node3D.new()
	scene.add_child(deep)
	var deeper := Node3D.new()
	deep.add_child(deeper)
	check(Ground.find(deeper) == terrain,
			"Ground.find could not reach the Terrain from two levels down, so a prop dragged"
			+ " into a group would never sit on anything")
	var orphan := Node3D.new()
	check(Ground.find(orphan) == null,
			"Ground.find returned a terrain for a node that is not in any scene")
	orphan.free()

	# --- sitting a model whose origin is NOT at its base ---
	#
	# The whole point. A one metre cube hung two metres above its own node: putting the node on
	# the ground would leave the cube floating 1.5 m clear, and only measuring the mesh catches
	# that. This is the cannon's case, reproduced without the cannon.
	var thing := Node3D.new()
	scene.add_child(thing)
	var block := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	block.mesh = cube
	thing.add_child(block)
	block.position.y = 2.0
	thing.global_position = Vector3(spawn.x, 400.0, spawn.z)
	await process_frame

	var box := Ground.mesh_box(thing)
	print("model box: bottom %.3f, top %.3f (a 1 m cube hung 2 m up)"
			% [box.position.y, box.position.y + box.size.y])
	check(absf(box.position.y - 1.5) < 0.001,
			"Ground.mesh_box put the bottom at %.3f, not 1.5 - it is measuring the node, not"
			% box.position.y + " the mesh")

	check(Ground.sit(thing, terrain), "Ground.sit refused a node standing over the island")
	await process_frame
	var ground: float = terrain.height_at(thing.global_position.x, thing.global_position.z)
	var bottom: float = thing.global_position.y + Ground.mesh_box(thing).position.y
	print("sat from 400 m: node y %.3f, mesh bottom %.3f, ground %.3f"
			% [thing.global_position.y, bottom, ground])
	check(absf(bottom - ground) < 0.01,
			"the model's bottom is %.3f against ground %.3f. Sitting it put the NODE on the"
			% [bottom, ground] + " ground and left the model in the air")

	# --- sink ---
	Ground.sit(thing, terrain, 0.25)
	await process_frame
	var sunk: float = thing.global_position.y + Ground.mesh_box(thing).position.y
	print("sunk 0.25: mesh bottom %.3f, ground %.3f" % [sunk, ground])
	check(absf((ground - sunk) - 0.25) < 0.01,
			"a sink of 0.25 moved the model %.3f m" % (ground - sunk))

	# --- depth, one signed number for both sides of the waterline ---
	var sea: float = terrain.sea_level()
	var dry := Ground.depth(terrain, spawn.x, spawn.z)
	var crater := _crater(terrain)
	var wet := Ground.depth(terrain, crater.x, crater.z)
	print("depth: %.2f m at the spawn, %.2f m at the crater (sea %.1f)" % [dry, wet, sea])
	check(dry < 0.0, "the spawn beach reports %.2f m of water over it" % dry)
	check(wet > 8.0, "the dive crater reports only %.2f m of water" % wet)
	check(absf(wet - (sea - terrain.height_at(crater.x, crater.z))) < 0.001,
			"Ground.depth disagrees with sea_level minus height_at, which is its definition")

	# --- leaning to the slope ---
	#
	# On the private _surface_normal, which is what cannon.gd already used. terrain.gd is being
	# rewritten, so this asks whether the method is there before believing anything about it.
	if terrain.has_method("_surface_normal"):
		var slope := _slope_near(terrain, spawn, 22.0)
		thing.global_position = Vector3(slope.x, 400.0, slope.z)
		await process_frame
		Ground.sit(thing, terrain)
		thing.rotation = Vector3(0.0, 0.7, 0.0)
		var facing_before := (-thing.global_transform.basis.z).normalized()
		var leaned := Ground.lean(thing, terrain, 1.0)
		var up := thing.global_transform.basis.y.normalized()
		var facing_after := (-thing.global_transform.basis.z).normalized()
		var tilt := rad_to_deg(Vector3.UP.angle_to(up))
		var swung := rad_to_deg(Vector2(facing_before.x, facing_before.z).angle_to(
				Vector2(facing_after.x, facing_after.z)))
		print("lean on a %.0f degree slope: tilted %.1f degrees, yaw moved %.1f"
				% [_slope_degrees(terrain, slope), tilt, absf(swung)])
		check(leaned, "Ground.lean refused on the steepest ground on the island")
		check(tilt > 2.0,
				"leaning tilted the node %.1f degrees on a slope - it is not following the" % tilt
				+ " ground at all")
		check(absf(swung) < 5.0,
				"leaning swung the node %.1f degrees round its own axis. It is supposed to"
				% absf(swung) + " change which way is up and leave the facing alone")

	# --- and the thing that started it: does the real cannon reach the ground ---
	var landed := 0
	var floating: Array[String] = []
	for node in scene.get_tree().get_nodes_in_group("cannons"):
		var gun := node as Node3D
		if not gun.get("sit_on_ground"):
			continue
		var at: Vector3 = gun.global_position
		var under: float = terrain.height_at(at.x, at.z)
		var base: float = at.y + (gun.call("bounds") as AABB).position.y
		# Only the guns standing on the island. A ship's gun sits on a deck.
		if absf(base - under) > 8.0:
			continue
		landed += 1
		if absf(base - under) > 0.2:
			floating.append("%s %.2f m off" % [gun.name, base - under])
	print("cannons on the ground: %d, adrift: %s" % [landed, "none" if floating.is_empty() else ", ".join(floating)])
	check(landed > 0, "no cannon stands on the island, so this proves nothing about the drop")
	check(floating.is_empty(), "a cannon is not on the ground: %s" % ", ".join(floating))

	await _check_patch(scene, terrain, spawn, crater)

	print("placement check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


## ScatterPatch, asked to do two jobs that are opposites.
##
## This is the whole claim of the node: that a reef on a crater floor and a rock field on a
## hillside are the same code with a different band. If one patch can do both without a line of
## its own, the abstraction is real; if it needs a special case, it is corals with extra steps.
## So both are measured here, against the same node, in the same run.
func _check_patch(scene: Node3D, terrain: Node, spawn: Vector3, crater: Vector3) -> void:
	var sea: float = terrain.sea_level()

	# --- under water: a reef on the crater floor ---
	var reef := ScatterPatch.new()
	scene.add_child(reef)
	reef.global_position = crater
	reef.scenes = [load("res://props/coral/coral.tscn")]
	reef.count = 20
	# WIDE ENOUGH TO REACH OUT OF ITS OWN BAND. At 18 m every sample was already on the crater
	# floor, so the band had nothing to refuse and the check passed with the filter disabled.
	# The crater is 25 m of full-depth floor and the ground ramps back up over the next ten, so
	# 45 m puts most of the circle in water too shallow to plant in.
	reef.radius = 45.0
	reef.spacing = 2.5
	reef.water_band = Vector2(4.0, 1000.0)
	reef.stay_submerged = true
	reef.surface_clearance = 1.5
	reef.sink = 0.06
	await process_frame

	var wet := reef.placements()
	check(wet.size() >= 12, "the reef patch placed only %d of 20 - too few to measure" % wet.size())
	var shallowest := 1e9
	var closest := 1e9
	var proud := 0
	for spot in wet:
		var at: Vector3 = spot["at"]
		shallowest = minf(shallowest, Ground.depth(terrain, at.x, at.z))
		if at.y + ScatterPatch._height_of(reef.scenes[0]) * spot["basis"].get_scale().y 				+ reef.surface_clearance > sea:
			proud += 1
		for other in wet:
			if other == spot:
				continue
			var there: Vector3 = other["at"]
			closest = minf(closest, Vector2(there.x - at.x, there.z - at.z).length())
	print("patch under water: %d placed, shallowest %.1f m, nearest pair %.2f m"
			% [wet.size(), shallowest, closest])
	check(shallowest >= reef.water_band.x,
			"the reef patch placed in %.1f m of water against a %.1f m band" % [shallowest, reef.water_band.x])
	check(proud == 0, "%d of the reef patch's placements would stick out of the sea" % proud)
	check(closest >= reef.spacing - 0.01,
			"the reef patch put two %.2f m apart against a %.2f m spacing" % [closest, reef.spacing])
	check(reef.get_child_count() == wet.size(),
			"the patch planted %d children for %d placements - the emitter and the decision"
			% [reef.get_child_count(), wet.size()] + " disagree")

	# --- above water: rocks up the beach, same node, band reversed ---
	var field := ScatterPatch.new()
	scene.add_child(field)
	field.global_position = spawn
	field.scenes = [load("res://props/rock/rock.tscn")]
	field.count = 12
	# Same reason: wide enough from the spawn to reach well past the shoreline into the sea,
	# so refusing the water is work rather than a coincidence of where the circle fell.
	field.radius = 95.0
	field.inner_radius = 8.0
	field.spacing = 3.0
	field.water_band = Vector2(-1000.0, -0.6)
	field.max_slope = 0.5
	await process_frame

	var dry := field.placements()
	check(dry.size() >= 6, "the rock patch placed only %d of 12" % dry.size())
	var lowest := 1e9
	var steepest := 0.0
	var inside := 0
	var outside := 0
	for spot in dry:
		var at: Vector3 = spot["at"]
		lowest = minf(lowest, -Ground.depth(terrain, at.x, at.z))
		steepest = maxf(steepest, Ground.slope(terrain, at.x, at.z))
		var away: float = Vector2(at.x - spawn.x, at.z - spawn.z).length()
		if away < field.inner_radius - 0.01:
			inside += 1
		if away > field.radius + 0.01:
			outside += 1
	print("patch above water: %d placed, lowest %.1f m over the sea, steepest slope %.2f"
			% [dry.size(), lowest, steepest])
	check(lowest >= 0.6,
			"the rock patch placed %.2f m above the sea against a 0.6 m band - the same node"
			% lowest + " that just refused to leave the water will not stay out of it")
	check(steepest <= field.max_slope + 0.001,
			"the rock patch used ground at slope %.2f against a %.2f limit" % [steepest, field.max_slope])
	check(inside == 0, "%d rocks landed inside the %.0f m hole in the middle" % [inside, field.inner_radius])
	check(outside == 0, "%d rocks landed outside the %.0f m radius" % [outside, field.radius])

	# --- the same seed gives the same patch ---
	var again := field.placements()
	var same := again.size() == dry.size()
	if same:
		for i in dry.size():
			if (dry[i]["at"] as Vector3).distance_to(again[i]["at"]) > 0.001:
				same = false
				break
	check(same, "two calls with the same seed gave different answers - the patch is not"
			+ " reproducible, so a scene cannot be trusted to come back the way it was left")

	reef.free()
	field.free()


## The middle of the dive crater, found the way main.gd finds it.
func _crater(terrain: Node) -> Vector3:
	for child in terrain.get_children():
		var stamp := child as TerrainStamp
		if stamp == null or stamp.mode != TerrainStamp.Mode.ADD or stamp.strength >= 0.0:
			continue
		var at := stamp.global_position
		if terrain.height_at(at.x, at.z) < terrain.sea_level():
			return at
	return Vector3.ZERO


## Dry ground near the spawn at about `wanted` degrees.
##
## Not the STEEPEST ground, which is what this asked for first and which made the yaw
## measurement meaningless: at 78 degrees the node's forward is nearly vertical, so its
## horizontal heading is a projection of almost nothing and swings wildly for a fraction of a
## degree of tilt. No algorithm preserves a compass bearing there, and nothing is ever planted
## there either - palms refuse above a slope of 0.5 and grass above 0.55, both about 28
## degrees. So this asks about ground a prop would really stand on.
func _slope_near(terrain: Node, near: Vector3, wanted: float) -> Vector3:
	var best := near
	var closest := 1e9
	for i in 600:
		var at := near + Vector3(randf_range(-140.0, 140.0), 0.0, randf_range(-140.0, 140.0))
		if terrain.height_at(at.x, at.z) < terrain.sea_level() + 2.0:
			continue
		var off: float = absf(_slope_degrees(terrain, at) - wanted)
		if off < closest:
			closest = off
			best = at
	return best


func _slope_degrees(terrain: Node, at: Vector3) -> float:
	var dx: float = terrain.height_at(at.x + 1.0, at.z) - terrain.height_at(at.x - 1.0, at.z)
	var dz: float = terrain.height_at(at.x, at.z + 1.0) - terrain.height_at(at.x, at.z - 1.0)
	return rad_to_deg(atan(Vector2(dx, dz).length() * 0.5))
