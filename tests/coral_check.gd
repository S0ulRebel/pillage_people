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
	var reef := scene.get_node_or_null("Reef")
	check(reef != null, "there is no Reef node - no corals were grown at all")
	if reef == null:
		_finish()
		return

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
		# then compared it against sea level - so `top` was about 1.2 and `sea` was 18.0 and no
		# coral could ever breach. It passed with every coral lifted fourteen metres to the
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
	# Which family planted each one, by the name the reef gave it.
	#
	# The reef picks from two families and asks the one it picked to dress what it planted. If
	# that dispatch collapsed to a single family - one wrong index, one preload dropped - the
	# reef would still be full, still be on the bed, and would still pass every measurement
	# above while quietly being one thing.
	#
	# This read the MATERIAL first, on the grounds that seaweed turns back-face culling off and
	# coral does not. That measured the asset, not the code: coral_fingers and coral_branch
	# arrive from Tripo doubleSided and coral_plate and coral_tubes do not, so breaking the
	# dispatch to plant nothing but coral_fingers reported 26 seaweed and passed. The name is
	# written from the same pick the model comes from, so it cannot disagree with it.
	var counted := {}
	for coral in corals:
		var family: String = String(coral.name).trim_suffix(
				String(coral.name).lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"))
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
	check(shallowest >= reef.min_depth,
			"a coral grew in %.1f m of water against a %.1f m minimum - the reef is reaching"
			% [shallowest, reef.min_depth] + " into the shallows at the crater's edge")
	check(nearest >= reef.spacing - 0.01,
			"two corals are %.2f m apart against a %.2f m spacing - they will read as one"
			% [nearest, reef.spacing] + " broken coral")
	_check_shallows(scene, terrain)
	_finish()


## The beds along the coast. The same plants and the same planting as the crater, in a tenth of
## the water - which is what makes this a different check rather than the one above again. Down
## there the swell is a rounding error; here its troughs are most of the water there is, and a
## growth that clears the still level by a hand stands in the air every few seconds.
func _check_shallows(scene: Node3D, terrain: Node) -> void:
	var shallows := scene.get_node_or_null("Shallows")
	check(shallows != null, "there is no Shallows node - nothing grew along the coast")
	if shallows == null:
		return
	var ocean := scene.get_node("Ocean") as Ocean
	var sea: float = terrain.sea_level()
	var growths: Array[Node3D] = []
	for child in shallows.get_children():
		if child is Node3D:
			growths.append(child)
	check(growths.size() >= 150,
			"only %d growths along the whole coast - under the beds that were asked for, so"
			% growths.size() + " the band or the fit is refusing nearly everywhere")
	if growths.is_empty():
		return

	# --- under the swell, sampled rather than taken on trust ---
	#
	# The reef keeps each growth under sea - Ocean.deepest_trough(depth). Checking tops against
	# that same function would pass whatever it returned, zero included. So the sea is READ, at
	# every growth, over three quarters of a minute: surface_y is what floats the cargo and the
	# hull, and the ocean shader draws the same sum. Each sample is also held to the bound, which
	# is what says deepest_trough is a floor and not a guess.
	#
	# The clock is set by hand because the sea's time is its own - surface_motion does the same.
	var clock: float = ocean._clock
	var lowest: Array[float] = []
	lowest.resize(growths.size())
	lowest.fill(1e9)
	for step in 150:
		ocean._clock = float(step) * 0.29
		for i in growths.size():
			var at := growths[i].global_position
			lowest[i] = minf(lowest[i], ocean.surface_y(at.x, at.z))
	ocean._clock = clock
	var awash := 0
	var tightest := 1e9
	var under_bound := 0
	var worst_perch := 0.0
	var out_of_band := 0
	var corals_wading := 0
	var lit := 0
	var glossy := 0
	var undrawn := 0
	var near_start := 0
	var under_hull := 0
	var nearest := 1e9
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
		var top: float = _world_bounds(node).end.y
		tightest = minf(tightest, lowest[i] - top)
		if top >= lowest[i]:
			awash += 1
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
		for j in range(i + 1, growths.size()):
			var there := growths[j].global_position
			nearest = minf(nearest, Vector2(there.x - at.x, there.z - at.z).length())
	print("shallows: %d growths %s, %d within %.0f m of the start, %d of 12 twelfths of the coast"
			% [growths.size(), str(counted), near_start, scene.shallows_reach, sectors.size()])
	print("shallows: tightest %.3f m under the lowest sampled trough, worst perch %.3f m,"
			% [tightest, worst_perch] + " nearest pair %.2f m" % nearest)

	check(awash == 0,
			"%d growth(s) in the shallows come out of the water when the swell goes by. They"
			% awash + " carry no layer 20, so they punch no foam ring - see coral.gd")
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
	check(nearest >= shallows.spacing - 0.01,
			"two growths in the shallows are %.2f m apart against a %.2f m spacing"
			% [nearest, shallows.spacing])


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
