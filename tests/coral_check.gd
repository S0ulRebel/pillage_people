extends SceneTree
## Run: godot --headless --path . --script res://tests/coral_check.gd
##
## Checks the reef: that it grew, that it grew on the seabed, and that none of it breaks the
## surface.
##
## That last one is not decoration. A coral carries `layers = 1` and NOT the ocean's layer 20,
## unlike every other prop in this world - see coral.gd - and the reason it can is that a coral
## is always fully submerged, where the band camera's frustum cannot reach it anyway. If a
## coral ever did stand out of the sea it would be the one thing in the water that punches no
## foam ring, and nothing else in the project would notice. So the two are checked together:
## the layer bit, and the submersion that makes it correct.

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
	for i in 60:
		await process_frame

	var terrain := scene.get_node("Terrain")
	var sea: float = terrain.sea_level()
	var reef := scene.find_child("Reef", true, false) as ScatterPatch
	check(reef != null, "there is no Reef ScatterPatch in the scene - no corals were grown at all")
	if reef == null:
		_finish()
		return
	# Under the crater it fills, so moving the crater in the editor takes the reef with it. It
	# used to be grown by main.gd, which found the crater by guessing: any stamp that dug below
	# the waterline.
	check(reef.get_parent() is TerrainStamp,
			"the Reef is under %s, not under a stamp - it will not follow the crater it fills"
			% reef.get_parent().name)

	# --- the models, before anything placed is believed ---
	#
	# Their size has to live in the .glb. `*.import` is gitignored, so a scale set on import is
	# a scale a fresh clone never receives - the same trap that gave the captain 53% height. A
	# coral that arrives one unit tall has had its bake lost.
	var families := [load("res://props/coral/coral.gd"), load("res://props/seaweed/seaweed.gd")]
	var paths: Array[String] = []
	for family in families:
		for kind in family.MODELS:
			paths.append(family.MODELS[kind])
	check(paths.size() >= 6, "only %d models between the families - the reef has nothing to"
			% paths.size() + " vary and everything below measures one shape")
	for path in paths:
		check(ResourceLoader.exists(path), "no coral model at %s" % path)
		if not ResourceLoader.exists(path):
			continue
		var probe := (load(path) as PackedScene).instantiate()
		scene.add_child(probe)
		var box := _mesh_bounds(probe)
		print("%-22s %.2f x %.2f x %.2f m, base y %.3f"
				% [path.get_file(), box.size.x, box.size.y, box.size.z, box.position.y])
		check(box.size.y > 0.4 and box.size.y < 3.0,
				"%s stands %.2f m. Either the scale was never baked into the .glb or it has been"
				% [path.get_file(), box.size.y] + " lost to a gitignored .import")
		check(absf(box.position.y) < 0.05,
				"%s does not start at y=0 (its base is at %.3f), so planting it at the seabed"
				% [path.get_file(), box.position.y] + " height would bury or float it")
		probe.free()

	# --- what actually grew ---
	var corals: Array[Node] = []
	for child in reef.get_children():
		if child is Node3D:
			corals.append(child)
	check(corals.size() >= 8,
			"only %d corals grew. Below a handful every measurement under here is one lucky"
			% corals.size() + " placement and the check proves nothing")
	if corals.is_empty():
		_finish()
		return

	var deepest := 0.0
	var shallowest := 1e9
	var worst_perch := 0.0
	var breached := 0
	var lit := 0
	var glossy := 0
	var nearest := 1e9
	for coral in corals:
		var node := coral as Node3D
		var at: Vector3 = node.global_position
		var ground: float = terrain.height_at(at.x, at.z)
		# IN WORLD METRES. This read _mesh_bounds, which answers in the node's own space, and
		# then compared it against sea level - so `top` was about 1.2 and `sea`, then at 18 m,
		# 18.0, and no coral could ever breach. It passed with every coral lifted fourteen metres to the
		# surface, which is exactly the thing it exists to catch.
		var top: float = _world_bounds(node).end.y
		# On the seabed, not hovering over it and not sunk into it. Measured against the height
		# map the scatterer itself read, so this catches a placement written in the wrong space
		# rather than re-deriving the same mistake.
		worst_perch = maxf(worst_perch, absf(at.y - ground))
		var water := sea - ground
		deepest = maxf(deepest, water)
		shallowest = minf(shallowest, water)
		if top >= sea:
			breached += 1
		for node2 in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node2 as MeshInstance3D
			if mesh_node.get_layer_mask_value(20):
				lit += 1
			var material := mesh_node.get_surface_override_material(0) as StandardMaterial3D
			if material == null or material.specular_mode != BaseMaterial3D.SPECULAR_DISABLED \
					or material.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON:
				glossy += 1
		for other in corals:
			if other == coral:
				continue
			var there: Vector3 = (other as Node3D).global_position
			nearest = minf(nearest, Vector2(there.x - at.x, there.z - at.z).length())

	print("reef: %d growths, water %.1f to %.1f m, worst perch %.3f m off the bed, nearest pair %.2f m"
			% [corals.size(), shallowest, deepest, worst_perch, nearest])
	# Which family each one came from, by the script it carries.
	#
	# The reef picks from nine scenes across two families. If that pick collapsed to a single
	# family - one wrong index, one scene dropped from the list - the reef would still be full,
	# still be on the bed, and would still pass every measurement above while quietly being one
	# thing.
	#
	# This read the MATERIAL first, on the grounds that seaweed turns back-face culling off and
	# coral does not. That measured the asset, not the code: coral_fingers and coral_branch
	# arrive from Tripo doubleSided and coral_plate and coral_tubes do not, so breaking the
	# dispatch to plant nothing but coral_fingers reported 26 seaweed and passed. The script
	# comes with the scene that was picked, so it cannot disagree with the pick.
	var counted := {}
	for coral in corals:
		var family: String = (coral.get_script() as Script).resource_path.get_file().get_basename()
		counted[family] = int(counted.get(family, 0)) + 1
	print("reef: %s" % str(counted))
	check(counted.size() >= 2,
			"everything in the reef came from one family (%s) - the pick is not reaching both"
			% str(counted))

	check(breached == 0,
			"%d coral(s) break the surface. A coral is the one prop here that carries no layer"
			% breached + " 20, and that is only correct while every one of them is under water")
	check(lit == 0,
			"%d coral mesh(es) are on layer 20. The ocean's band camera stops 0.1 m under the"
			% lit + " water, so a submerged coral on that layer costs a draw and buys nothing")
	check(glossy == 0,
			"%d coral mesh(es) kept their imported material. Tripo hands these back with a"
			% glossy + " specular highlight, which reads as a different game from this one")
	check(worst_perch < 0.25,
			"a coral sits %.2f m off the seabed. They are planted at terrain.height_at, so this"
			% worst_perch + " is a placement written in the wrong space")
	check(shallowest >= reef.water_band.x,
			"a coral grew in %.1f m of water against a %.1f m minimum - the reef is reaching"
			% [shallowest, reef.water_band.x] + " into the shallows at the crater's edge")
	check(nearest >= reef.spacing - 0.01,
			"two corals are %.2f m apart against a %.2f m spacing - they will read as one"
			% [nearest, reef.spacing] + " broken coral")
	# Before the crater moves: the rebuild reshapes ground the beds may stand on.
	_check_shallows(scene, terrain)

	# --- the crater carries its reef ---
	#
	# Moved and rebuilt, the way an edit in the editor rebuilds it, the reef has to replant on
	# the new floor. The first time this was tried it crashed the engine: the patch freed its
	# corals inside the move notification, while Godot was still handing that move to them.
	var crater := reef.get_parent() as Node3D
	crater.global_position += Vector3(-60.0, 0.0, 0.0)
	await process_frame
	await process_frame
	terrain.rebuild_changed()
	var middle := Vector2(crater.global_position.x, crater.global_position.z)
	var moved_shallowest := 1e9
	var moved_farthest := 0.0
	for child in reef.get_children():
		var at := (child as Node3D).global_position
		moved_shallowest = minf(moved_shallowest, sea - terrain.height_at(at.x, at.z))
		moved_farthest = maxf(moved_farthest, Vector2(at.x, at.z).distance_to(middle))
	print("reef after moving the crater 60 m: %d growths, shallowest %.1f m, farthest %.1f m out"
			% [reef.planted, moved_shallowest, moved_farthest])
	check(reef.planted >= 8, "only %d corals replanted after the crater moved" % reef.planted)
	check(moved_farthest <= reef.radius + 0.01,
			"a coral stands %.1f m from the moved crater's middle against a %.1f m radius - the"
			% [moved_farthest, reef.radius] + " reef stayed where the crater was")
	check(moved_shallowest >= reef.water_band.x,
			"after the crater moved a coral grew in %.1f m of water - the reef read the ground"
			% moved_shallowest + " from before the rebuild")
	_finish()


## The beds along the coast. The same plants and the same planting as the crater, in a tenth of
## the water - which is what makes this a different check rather than the one above again. Down
## there the swell is a rounding error; here its troughs are most of the water there is, and a
## growth that clears the still level by a hand stands in the air every few seconds.
##
## They are allowed to, a little: the shallows plant under half the deepest trough, so that the
## plants by the beach are not specks (reef.gd, trough_share). So this does not ask that none
## ever shows. It asks that none crosses the still level, which is the line layer 20 needs, and
## it measures how long the tallest of them actually spends with its tip out.
func _check_shallows(scene: Node3D, terrain: Node) -> void:
	var shallows := scene.get_node_or_null("Shallows")
	check(shallows != null, "there is no Shallows node - nothing grew along the coast")
	if shallows == null:
		return
	# How loose a bed may be: its growths' average distance to their nearest neighbour, in
	# multiples of the family's BED_SPACING. Measured, the loosest reef averages 0.76 m (of
	# 1.13 allowed) and the loosest weed patch 0.63 m (of 0.75). Spread over 3.5 m the way grass
	# clumps - most of a bed in its middle metre, the rest standing alone round it - a weed patch
	# averaged 0.95 m, which is the look a bed is for avoiding.
	const LOOSEST := 2.5
	var ocean := scene.get_node("Ocean") as Ocean
	var sea: float = terrain.sea_level()
	# Beds, then what grew in each. A bed is named for its family - CoralBed3, SeaweedBed7 - and
	# each growth for the family that planted it, from the same pick; the two must agree.
	var growths: Array[Node3D] = []
	var bed_sizes: Array[int] = []
	var bed_kinds := {}
	var mixed := 0
	var loosest := {}
	var spacing_of := {}
	var crowded := 0
	for bed in shallows.get_children():
		var kind := String(bed.name).get_slice("Bed", 0)
		var family := load("res://props/%s/%s.gd" % [kind.to_lower(), kind.to_lower()]) as Script
		bed_kinds[kind] = int(bed_kinds.get(kind, 0)) + 1
		spacing_of[kind] = family.BED_SPACING
		var members: Array[Node3D] = []
		for child in bed.get_children():
			members.append(child as Node3D)
			if String(child.name).rstrip("0123456789") != kind:
				mixed += 1
		bed_sizes.append(members.size())
		growths.append_array(members)
		# How far the average growth in this bed is from its nearest neighbour. A patch is
		# plants touching; a metre and more between them is plants dotted about.
		var gaps := 0.0
		for a in members:
			var closest := 1e9
			for b in members:
				if a != b:
					closest = minf(closest, Vector2(a.global_position.x - b.global_position.x,
							a.global_position.z - b.global_position.z).length())
			gaps += closest
			if closest < family.BED_SPACING - 0.01:
				crowded += 1
		if members.size() > 1:
			loosest[kind] = maxf(float(loosest.get(kind, 0.0)), gaps / members.size())
	bed_sizes.sort()
	print("shallows: %d beds %s, %d to %d growths each (median %d), loosest bed by family %s m"
			% [bed_sizes.size(), str(bed_kinds), bed_sizes[0], bed_sizes[-1],
			bed_sizes[bed_sizes.size() / 2], str(loosest)] + " between neighbours on average")
	check(mixed == 0,
			"%d growth(s) are in a bed of the other family. A bed is a coral reef or a patch of"
			% mixed + " weed, never both")
	check(bed_kinds.size() >= 2,
			"the shallows are all one kind of bed (%s) - no reefs, or no weed" % str(bed_kinds))
	check(bed_sizes[bed_sizes.size() / 2] >= 12,
			"the median bed holds %d growths. Under a dozen it reads as a few plants, not a patch"
			% bed_sizes[bed_sizes.size() / 2])
	for kind in loosest:
		check(loosest[kind] <= LOOSEST * spacing_of[kind],
				"a %s bed's growths average %.2f m from their nearest neighbour - dotted about,"
				% [kind, loosest[kind]] + " not a patch")
	check(crowded == 0,
			"%d growth(s) stand closer to another in their bed than their family's BED_SPACING"
			% crowded)
	check(growths.size() >= 150,
			"only %d growths along the whole coast - under the beds that were asked for, so"
			% growths.size() + " the band or the fit is refusing nearly everywhere")
	if growths.is_empty():
		return

	# --- under the swell, sampled rather than taken on trust ---
	#
	# The reef keeps each growth under part of Ocean.deepest_trough(depth). Checking tops against
	# that same function would pass whatever it returned, zero included. So the sea is READ, at
	# every growth, over three quarters of a minute: surface_y is what floats the cargo and the
	# hull, and the ocean shader draws the same sum. Each sample is also held to the bound, which
	# is what says deepest_trough is a floor and not a guess.
	#
	# The clock is set by hand because the sea's time is its own - surface_motion does the same.
	const SAMPLES := 150
	var tops: Array[float] = []
	for node in growths:
		tops.append(_world_bounds(node).end.y)
	var clock: float = ocean._clock
	var lowest: Array[float] = []
	lowest.resize(growths.size())
	lowest.fill(1e9)
	var showing: Array[int] = []
	showing.resize(growths.size())
	showing.fill(0)
	for step in SAMPLES:
		ocean._clock = float(step) * 0.29
		for i in growths.size():
			var at := growths[i].global_position
			var surface: float = ocean.surface_y(at.x, at.z)
			lowest[i] = minf(lowest[i], surface)
			if surface < tops[i]:
				showing[i] += 1
	ocean._clock = clock
	var breached := 0
	var ever_showing := 0
	var longest_showing := 0
	var under_bound := 0
	var worst_perch := 0.0
	var out_of_band := 0
	var corals_wading := 0
	var lit := 0
	var glossy := 0
	var undrawn := 0
	var near_start := 0
	var under_hull := 0
	var counted := {}
	var sectors := {}
	var start: Vector3 = (scene.get_node("Player") as Node3D).global_position
	var ship := scene.get_node_or_null("Ship") as Node3D
	var hull := AABB()
	if ship != null:
		hull = _world_bounds(ship)
	for i in growths.size():
		var node := growths[i]
		var at := node.global_position
		var ground: float = terrain.height_at(at.x, at.z)
		var depth := sea - ground
		# The band camera's far plane is 0.1 m under the still level - see coral.gd.
		if tops[i] >= sea - 0.1:
			breached += 1
		if showing[i] > 0:
			ever_showing += 1
		longest_showing = maxi(longest_showing, showing[i])
		# 5 mm for the one thing the bound leaves out: the surface over a point is the water
		# from up to 0.65 m away, flattened by the depth THERE (see Ocean.surface_y).
		if lowest[i] < sea - ocean.deepest_trough(depth) - 0.005:
			under_bound += 1
		worst_perch = maxf(worst_perch, absf(at.y - ground))
		if depth < shallows.min_depth or depth > shallows.max_depth:
			out_of_band += 1
		var family: String = String(node.name).rstrip("0123456789")
		counted[family] = int(counted.get(family, 0)) + 1
		if family == "Coral" and depth < (load("res://props/coral/coral.gd") as Script).SHALLOWEST:
			corals_wading += 1
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := mesh as MeshInstance3D
			if mesh_node.get_layer_mask_value(20):
				lit += 1
			var material := mesh_node.get_surface_override_material(0) as StandardMaterial3D
			if material == null or material.diffuse_mode != BaseMaterial3D.DIFFUSE_TOON:
				glossy += 1
			if mesh_node.visibility_range_end != shallows.visible_within:
				undrawn += 1
		if Vector2(at.x - start.x, at.z - start.z).length() < scene.shallows_reach:
			near_start += 1
		if ship != null and Rect2(hull.position.x, hull.position.z, hull.size.x, hull.size.z) \
				.has_point(Vector2(at.x, at.z)):
			under_hull += 1
		# Which twelfth of the way round the island. The map is centred on the origin.
		var sector := int(floorf((atan2(at.z, at.x) + PI) / TAU * 12.0)) % 12
		sectors[sector] = int(sectors.get(sector, 0)) + 1
	print("shallows: %d growths %s, %d within %.0f m of the start, %d of 12 twelfths of the coast"
			% [growths.size(), str(counted), near_start, scene.shallows_reach, sectors.size()])
	var longest := float(longest_showing) / SAMPLES
	print("shallows: %d of %d show a tip in some trough, the most exposed %.0f%% of the time;"
			% [ever_showing, growths.size(), longest * 100.0] + " worst perch %.3f m" % worst_perch)

	check(breached == 0,
			"%d growth(s) in the shallows reach within 0.1 m of the still level. They carry no"
			% breached + " layer 20, so they punch no foam ring - see coral.gd")
	# An eighth. Measured, the most exposed shows 9% of the time under half the trough; ignoring
	# the trough altogether it was 33%, the tallest standing in the air every third second.
	check(longest <= 0.125,
			"a growth in the shallows has its tip out of the water %.0f%% of the time. Half the"
			% (longest * 100.0) + " trough lets the tallest show at the bottom of the biggest"
			+ " swells, not stand in the air")
	check(under_bound == 0,
			"the sea went lower than Ocean.deepest_trough allows at %d growth(s). The reef"
			% under_bound + " plants against that number, so it is under-reading the swell")
	check(worst_perch < 0.25,
			"a growth in the shallows sits %.2f m off the seabed" % worst_perch)
	check(out_of_band == 0,
			"%d growth(s) are outside the shallows' %.1f to %.1f m of water"
			% [out_of_band, shallows.min_depth, shallows.max_depth])
	check(corals_wading == 0,
			"%d coral(s) grew where he wades. A coral has no collider, so he walks through it"
			% corals_wading)
	check(counted.size() >= 2,
			"everything along the coast came from one family (%s)" % str(counted))
	check(lit == 0, "%d shallows mesh(es) are on layer 20" % lit)
	check(glossy == 0, "%d shallows mesh(es) kept their imported material" % glossy)
	check(undrawn == 0,
			"%d shallows mesh(es) have no draw distance. There are hundreds round the coast,"
			% undrawn + " and every one would be drawn from anywhere on the island")
	check(near_start >= 80,
			"only %d growths within %.0f m of where he starts - the beach he sees first is bare"
			% [near_start, scene.shallows_reach])
	check(sectors.size() >= 8,
			"the shallows reach only %d of 12 twelfths of the way round the island" % sectors.size())
	check(under_hull == 0,
			"%d growth(s) are under the moored hull, whose keel sits in the water they grow in"
			% under_hull)



## Every mesh under a node, merged, in that node's own space. The imported origin is arbitrary -
## Tripo puts it wherever it likes - so nothing here reads the node transform.
func _world_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var here := mesh_node.global_transform * mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


## Every mesh under a node, merged, in that node's own space - its size, with its placement
## taken out. For measuring a MODEL. Anything compared against the world (the sea, the seabed)
## has to use _world_bounds instead.
func _mesh_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var here := (node.global_transform.affine_inverse() * mesh_node.global_transform) \
				* mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


func _finish() -> void:
	print("coral check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
