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
	var CoralProp := load("res://props/coral/coral.gd")
	for kind in CoralProp.MODELS:
		var path: String = CoralProp.MODELS[kind]
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

	print("reef: %d corals, water %.1f to %.1f m, worst perch %.3f m off the bed, nearest pair %.2f m"
			% [corals.size(), shallowest, deepest, worst_perch, nearest])

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
