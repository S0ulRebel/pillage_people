extends SceneTree
## Run: D:\Godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/dive_hole_view.gd [-- --nopictures]
##
## Every stamp under Terrain that digs - a crater to dive into - checked four ways and
## pictured twice. It has to lie under water at all, or it is a pit on the beach; the ground
## has to be as deep as the stamp says; the water over it has to be deep enough to dive in;
## and the collider has to agree with the height map, because he stands on the collider and
## the water reads the map. Then a shot from above, where the deeper water should read
## darker, and one from inside, looking at the wall.
##
## Not headless - no renderer there. Pass -- --nopictures to run the numbers alone, headless.

const SHOTS := "user://dive_holes"
## Metres of water a crater has to end up with. He swims from 1.3 m down (captain.gd
## swim_depth); a hole that is not several times that is a dip in the sand, not a dive.
const DIVE_DEPTH := 8.0

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	var pictures := "--nopictures" not in OS.get_cmdline_user_args()
	if pictures and DisplayServer.get_name() == "headless":
		push_error("dive hole pictures need a renderer; pass --nopictures for the numbers alone")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
	var terrain := scene.get_node("Terrain")
	var sea: float = terrain.sea_level()
	scene.get_node("Player").set_physics_process(false)

	# The island without any stamp, to say how much each hole dug. Built the way
	# terrain_stamp_check builds its plain terrain.
	var plain := StaticBody3D.new()
	plain.set_script(load("res://world/terrain.gd"))
	plain.raw_path = terrain.raw_path
	plain.world_size = terrain.world_size
	plain.height_scale = terrain.height_scale
	root.add_child(plain)
	await process_frame

	var holes: Array[TerrainStamp] = []
	for child in terrain.get_children():
		var stamp := child as TerrainStamp
		if stamp == null or stamp.mode != TerrainStamp.Mode.ADD or stamp.strength >= 0.0:
			continue
		var at := stamp.global_position
		if plain.height_at(at.x, at.z) < sea:
			holes.append(stamp)
		else:
			_check(false, "%s digs into dry ground at (%.0f, %.0f) - a pit on the beach, not a crater"
					% [stamp.name, at.x, at.z])
	print("dive holes: %d" % holes.size())
	_check(holes.size() > 0, "no stamp digs below the sea - nothing to dive into")

	if pictures:
		scene.get_node("HUD").hide()
		scene.get_node("TouchControls").hide()
		scene.get_node("Spyglass").hide()
		scene.get_node("GlassView").hide()
		DirAccess.make_dir_recursive_absolute(SHOTS)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 60.0
	camera.far = 1000.0
	camera.current = true

	for stamp in holes:
		var at := stamp.global_position
		var before: float = sea - plain.height_at(at.x, at.z)
		var after: float = sea - terrain.height_at(at.x, at.z)
		var expected: float = -stamp.strength * stamp.value_at(at.x, at.z)
		print("%s at (%.0f, %.0f): %.1f m of water before, %.1f m after (dug %.1f m, stamp says %.1f m)"
				% [stamp.name, at.x, at.z, before, after, after - before, expected])
		_check(absf((after - before) - expected) < 0.05,
				"%s dug %.2f m, its stamp says %.2f m" % [stamp.name, after - before, expected])
		_check(after >= DIVE_DEPTH, "%s leaves %.1f m of water - not enough to dive in (want %.0f m)"
				% [stamp.name, after, DIVE_DEPTH])
		# What he lands on: a ray straight down through the water, at the collider vertex
		# nearest the centre. Between vertices the collider is a chord of the bed and the height
		# map is not, and terrain_stamp_check measured that alone at a metre on rough ground.
		var grid: float = terrain.world_size / float(terrain.collision_resolution - 1)
		var half: float = terrain.world_size * 0.5
		var vertex := Vector3(roundf((at.x + half) / grid) * grid - half, 0.0,
				roundf((at.z + half) / grid) * grid - half)
		var query := PhysicsRayQueryParameters3D.create(Vector3(vertex.x, sea + 50.0, vertex.z),
				Vector3(vertex.x, sea - 200.0, vertex.z))
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "%s: nothing to stand on under the crater" % stamp.name)
		if not hit.is_empty():
			var floor_y: float = (hit["position"] as Vector3).y
			var mapped: float = terrain.height_at(vertex.x, vertex.z)
			print("   collider floor at %.2f m, height map says %.2f m" % [floor_y, mapped])
			_check(absf(floor_y - mapped) < 0.05,
					"%s: the collider (%.2f m) does not follow the stamped map (%.2f m)"
					% [stamp.name, floor_y, mapped])
		if not pictures:
			continue
		# From above, off to one side, so the hole and the flat bed around it are both in frame.
		camera.global_position = at + Vector3(-45.0, 50.0, 30.0)
		camera.look_at(Vector3(at.x, sea, at.z), Vector3.UP)
		await _shot("%s_above" % stamp.name.to_lower(), camera)
		# From inside, two thirds of the way down, looking across at the far wall.
		var floor_here: float = terrain.height_at(at.x, at.z)
		camera.global_position = Vector3(at.x - stamp.length * 0.25, lerpf(sea, floor_here, 0.66), at.z)
		camera.look_at(Vector3(at.x + stamp.length * 0.5, lerpf(sea, floor_here, 0.8), at.z), Vector3.UP)
		await _shot("%s_inside" % stamp.name.to_lower(), camera)

	print("dive holes: ", "PASS" if _failures == 0 else "FAIL")
	quit(0 if _failures == 0 else 1)


func _shot(label: String, camera: Camera3D) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := SHOTS + "/" + label + ".png"
	if image.save_png(path) != OK:
		_failures += 1
		push_error("could not save " + label)
	print("shot: ", ProjectSettings.globalize_path(path), " from ", camera.global_position)
