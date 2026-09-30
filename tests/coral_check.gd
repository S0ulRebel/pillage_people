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
