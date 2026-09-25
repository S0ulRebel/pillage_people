@tool
extends EditorPlugin
## Run: tests/editor_live_check.sh   (it enables this plugin for one headless editor run)
##
## The one path no other test reaches. Everything else runs the game's side of the terrain;
## this runs inside the editor, where Engine.is_editor_hint() is true, so a stamp's edit has
## to travel the editor's route - the transform notification, the stamp's `changed` signal,
## the terrain's debounce timer - and only the chunks under the stamp may be rebuilt. It was
## written when live preview worked in every headless test and not in the editor.
##
## An EditorPlugin rather than an EditorScript because a headless editor does not run a
## command-line EditorScript, but it does load plugins. Not enabled in project.godot: the
## script enables it through an override.cfg it removes again.

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	var tree := get_tree()
	for i in 3:
		await tree.process_frame
	print("editor hint: %s" % Engine.is_editor_hint())
	check(Engine.is_editor_hint(), "not running as the editor - this proves nothing")

	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://world/terrain.gd"))
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	var stamp: TerrainStamp = load("res://world/terrain_stamp/terrain_stamp.tscn").instantiate()
	stamp.name = "Pad"
	stamp.mode = TerrainStamp.Mode.FLATTEN
	stamp.shape = TerrainStamp.Shape.SOFT_RECT
	stamp.length = 20.0
	stamp.width = 14.0
	stamp.edge_softness = 4.0
	stamp.preview = true
	stamp.position = Vector3(60.0, 0.0, -20.0)
	terrain.add_child(stamp)
	var started := Time.get_ticks_msec()
	tree.root.add_child(terrain)
	await tree.process_frame
	print("opened: %d chunks built in %d ms, %d children watched" % [terrain._chunks.size(),
			Time.get_ticks_msec() - started, terrain._connections.size()])
	check(terrain._chunks.size() > 0, "the editor built no ground")
	check(stamp.changed.get_connections().size() == 1,
			"the stamp's changed signal has %d connections, expected the terrain's one"
			% stamp.changed.get_connections().size())
	var meshes_before: Array = []
	for chunk in terrain._chunks:
		meshes_before.append(chunk.mesh)
	var natural: float = terrain.height_at(60.0, -20.0)

	# The edit: raise the pad's plane 3 m above the natural ground, as a drag on the gizmo would.
	stamp.position.y = natural + 3.0
	await tree.create_timer(1.0).timeout   # the notification, the 0.1 s debounce, the rebuild

	var rebuilt := 0
	for index in terrain._chunks.size():
		if terrain._chunks[index].mesh != meshes_before[index]:
			rebuilt += 1
	var ground: float = terrain.height_at(60.0, -20.0)
	print("after the edit: %d chunks rebuilt (terrain reports %d), ground under the pad %.2f m, plane %.2f m, natural %.2f m"
			% [rebuilt, terrain.last_rebuilt, ground, stamp.position.y, natural])
	check(absf(ground - stamp.position.y) < 0.01, "the heights did not follow the edit")
	check(rebuilt > 0, "no chunk was rebuilt after the edit")
	check(rebuilt <= 9, "%d chunks rebuilt for a 20 m pad - not a partial rebuild" % rebuilt)
	check(rebuilt == terrain.last_rebuilt, "last_rebuilt says %d but %d meshes changed" % [terrain.last_rebuilt, rebuilt])

	# One more nudge, so the second edit is not special.
	for index in terrain._chunks.size():
		meshes_before[index] = terrain._chunks[index].mesh
	stamp.position.x += 6.0
	await tree.create_timer(1.0).timeout
	rebuilt = 0
	for index in terrain._chunks.size():
		if terrain._chunks[index].mesh != meshes_before[index]:
			rebuilt += 1
	print("after a second edit: %d chunks rebuilt" % rebuilt)
	check(rebuilt > 0, "the second edit rebuilt nothing")

	terrain.queue_free()
	await tree.process_frame

	# --- and in main.tscn itself, with everything else that is in it ---
	print("opening main.tscn...")
	started = Time.get_ticks_msec()
	var scene: Node = (load("res://main.tscn") as PackedScene).instantiate()
	tree.root.add_child(scene)
	await tree.process_frame
	var main_terrain: Node = scene.get_node_or_null("Terrain")
	check(main_terrain != null, "main.tscn has no Terrain")
	if main_terrain != null:
		var stamps: Array = []
		for child in main_terrain.get_children():
			if child is TerrainStamp:
				stamps.append(child)
		print("main.tscn: %d chunks built in %d ms; stamps: %s" % [main_terrain._chunks.size(),
				Time.get_ticks_msec() - started, stamps.map(func(node) -> String:
				return "%s (preview %s)" % [node.name, node.preview])])
		check(not stamps.is_empty(), "main.tscn has no TerrainStamp under Terrain")
		if not stamps.is_empty():
			var theirs: TerrainStamp = stamps[0]
			if not theirs.preview:
				theirs.preview = true
				await tree.create_timer(1.0).timeout
			var main_before: Array = []
			for chunk in main_terrain._chunks:
				main_before.append(chunk.mesh)
			var foot := theirs.global_position
			var before_edit: float = main_terrain.height_at(foot.x, foot.z)
			theirs.position.y += 2.0
			await tree.create_timer(1.5).timeout
			rebuilt = 0
			for index in main_terrain._chunks.size():
				if main_terrain._chunks[index].mesh != main_before[index]:
					rebuilt += 1
			var after_edit: float = main_terrain.height_at(foot.x, foot.z)
			print("main.tscn: raised %s 2 m: ground under it %.2f -> %.2f m, %d chunks rebuilt"
					% [theirs.name, before_edit, after_edit, rebuilt])
			check(rebuilt > 0, "in main.tscn the edit rebuilt nothing")
			check(absf(after_edit - before_edit - 2.0) < 0.05 or absf(after_edit - theirs.position.y) < 0.05,
					"in main.tscn the ground did not follow the stamp")
	scene.queue_free()

	print("editor_live_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	tree.quit(1 if failures > 0 else 0)
