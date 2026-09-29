extends SceneTree
## Run: godot --path . --script res://tests/foam_view.gd
##
## How the sea's foam is judged (docs/foam-plan.md): from the gameplay camera, on a real beach,
## next to the art. The captain stands on the sand a couple of metres up from the water, the
## camera is where the camera rig puts it in play (18 m arm, 55 degrees down, 60 degree lens),
## looking inland with the sea at the bottom of the frame - the way panels 9 and 10 of
## art/references/terrain-water-and-shore-transitions.jpg are framed - and the water clock is
## held so every run shows the same moment.
##
## Writes to user://foam:
##   gameplay.png        the frame as the game draws it
##   gameplay_close.png  the same at 7 m of arm, where the captain is the panels' size
##   seabed_close.png    the close view with the sea hidden: what the water is drawn over
##   compare.png         panel 9 | the game at 7 m | panel 10, each cropped to the same framing
##   compare_18m.png     the same at play's default 18 m
##   field.png           the shore distance field drawn over the 18 m view (step 1 of the plan)
##   runup_0..3.png      the close view at four moments through one run-up (step 3)
##   runup_debug_0..3    the same with runup_preview: water blue, foam age white, drying orange
##   open_sea.png        open water 70 m out from the gameplay camera, for the whitecaps (step 8)
##   waves_0..2.png      the sea's height from 110 m up over the coast, 2 s apart (step 2)
##   overview.png        the same view as the game draws it
## Not headless - no renderer there.

const SHOTS := "user://foam"
const SHEET := "res://art/references/terrain-water-and-shore-transitions.jpg"
## Panel 9 (wet to dry sand, surf) and panel 10 (shallow water to beach, calm), in the sheet's
## 1280 x 853 pixels, below their titles.
const PANEL_9 := Rect2i(642, 457, 306, 377)
const PANEL_10 := Rect2i(955, 457, 323, 377)
## The camera rig's play settings (ui/camera_rig.gd, main.tscn).
const ARM := 18.0
const PITCH := -55.0
const FOV := 60.0
const TARGET_HEIGHT := 2.1
## The panels are framed closer than play's default: their captain is about 14% of the
## panel's height, ours about 5% at 18 m. At 7 m of arm the two match, so the comparison is
## made there too - the nearest the rig lets the player zoom is 6 m.
const ARM_CLOSE := 7.0
## Seconds on the water clock every capture is taken at.
const MOMENT := 4.0

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("foam views need a renderer")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var terrain := scene.get_node("Terrain")
	var ocean := scene.get_node("Ocean")
	var study := scene.get_node("CoastalStudy")
	var day := scene.get_node_or_null("Day")
	if day != null:
		day.set_process(false)
		day.set_physics_process(false)
	for n in ["HUD", "TouchControls", "Spyglass", "GlassView"]:
		var node := scene.get_node_or_null(n)
		if node != null:
			node.hide()
	for i in 90:
		await physics_frame
	ocean.hold_clock = MOMENT
	terrain.material.set_shader_parameter("preview_time", MOMENT)
	var player := scene.get_node("Player") as Node3D
	player.set_physics_process(false)
	var rig := scene.get_node_or_null("CameraRig") as Node3D
	if rig != null:
		rig.set_process(false)
		rig.set_physics_process(false)

	# The beach: walk seaward from the coastal study until the ground is under the sea.
	var sea: float = terrain.sea_level()
	var inland: Vector3 = study.inland
	var shore: Vector3 = study.anchor
	for step in range(1, 80):
		var p: Vector3 = study.anchor - inland * float(step) * 0.5
		if terrain.height_at(p.x, p.z) <= sea:
			shore = Vector3(p.x, sea, p.z)
			break
	var stand := shore + inland * 2.5
	stand.y = terrain.height_at(stand.x, stand.z)
	player.global_position = stand
	print("beach at %s, captain at %s" % [shore, stand])

	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = FOV
	camera.far = 1000.0
	camera.current = true
	var target := stand + Vector3.UP * TARGET_HEIGHT
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	if sheet == null:
		push_error("could not read %s" % SHEET)
		quit(1)
		return
	sheet.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(SHOTS)

	_aim(camera, target, inland, ARM)
	var game := await _capture("gameplay")
	_compare(sheet, game, camera, target, "compare_18m")
	terrain.material.set_shader_parameter("shore_field_preview", true)
	ocean.material.set_shader_parameter("shore_field_preview", true)
	await _capture("field")
	terrain.material.set_shader_parameter("shore_field_preview", false)
	ocean.material.set_shader_parameter("shore_field_preview", false)
	# Close up, the panels put the waterline across the middle of the frame and the captain in
	# its upper third, so the camera looks at the beach just above the water, not at him.
	var beach := shore + inland * 0.8 + Vector3.UP * 0.3
	_aim(camera, beach, inland, ARM_CLOSE)
	var close := await _capture("gameplay_close")
	_compare(sheet, close, camera, beach, "compare")
	# What the sea is drawn over, from the same place: the seabed and the sand, water hidden.
	ocean.hide()
	await _capture("seabed_close")
	ocean.show()

	# The run-up (step 3) from the close camera, at four moments through one: as drawn, and
	# with runup_preview on, which shows where the water is, the foam's age and the drying.
	var cycle := 2.0 * TAU / sqrt(9.8 * TAU / (ocean.wave_1 as Vector4).w)
	for k in 4:
		ocean.hold_clock = MOMENT + cycle * float(k) / 4.0
		await _capture("runup_%d" % k)
	terrain.material.set_shader_parameter("runup_preview", true)
	ocean.material.set_shader_parameter("runup_preview", true)
	for k in 4:
		ocean.hold_clock = MOMENT + cycle * float(k) / 4.0
		await _capture("runup_debug_%d" % k)
	terrain.material.set_shader_parameter("runup_preview", false)
	ocean.material.set_shader_parameter("runup_preview", false)
	ocean.hold_clock = MOMENT

	# Whitecaps (step 8): open water from the gameplay camera, 70 m out, and the share of it
	# that is white - the references' water-type swatches are about 1% white in calm water,
	# 4% choppy, 6% stormy.
	var open_sea := shore - inland * 70.0
	_aim(camera, open_sea + Vector3.UP * TARGET_HEIGHT, inland, ARM)
	var sea_frame := await _capture("open_sea")
	var white := 0
	var counted := 0
	for y in range(0, sea_frame.get_height(), 3):
		for x in range(0, sea_frame.get_width(), 3):
			var c := sea_frame.get_pixel(x, y)
			counted += 1
			if c.r > 0.8 and c.g > 0.8 and c.b > 0.8:
				white += 1
	print("open sea: %.1f%% whitecap" % (100.0 * float(white) / float(maxi(counted, 1))))

	# The waves, seen from high over the coast: the surface's height drawn in bands, at three
	# moments two seconds apart, so the shore waves can be seen coming in parallel to the beach
	# and wrapping round it. And the same view as the game draws it.
	camera.global_position = shore - inland * 25.0 + Vector3.UP * 110.0
	camera.look_at(shore - inland * 25.0, inland)
	ocean.material.set_shader_parameter("wave_preview", true)
	for k in 3:
		ocean.hold_clock = MOMENT + 2.0 * float(k)
		await _capture("waves_%d" % k)
	ocean.material.set_shader_parameter("wave_preview", false)
	ocean.hold_clock = MOMENT
	await _capture("overview")
	print("foam views: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _aim(camera: Camera3D, target: Vector3, inland: Vector3, arm: float) -> void:
	var pitch := deg_to_rad(PITCH)
	camera.global_position = target - inland * cos(pitch) * arm - Vector3.UP * sin(pitch) * arm
	camera.look_at(target, Vector3.UP)


## Panel 9 | the game | panel 10, each cropped to the panels' portrait framing round the
## captain, at the height of the game's frame.
func _compare(sheet: Image, game: Image, camera: Camera3D, target: Vector3, tag: String) -> void:
	game = game.duplicate()
	game.convert(Image.FORMAT_RGB8)
	var h := game.get_height()
	var w := int(round(float(h) * float(PANEL_9.size.x) / float(PANEL_9.size.y)))
	var centre := camera.unproject_position(target) * float(h) / root.get_visible_rect().size.y
	var x0 := clampi(int(centre.x) - w / 2, 0, game.get_width() - w)
	var framed := game.get_region(Rect2i(x0, 0, w, h))
	var left := sheet.get_region(PANEL_9)
	left.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var right := sheet.get_region(PANEL_10)
	right.resize(int(round(float(h) * float(PANEL_10.size.x) / float(PANEL_10.size.y))), h,
			Image.INTERPOLATE_LANCZOS)
	var gap := 12
	var out := Image.create_empty(left.get_width() + framed.get_width() + right.get_width() + gap * 2,
			h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.09, 0.12))
	out.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
	out.blit_rect(framed, Rect2i(Vector2i.ZERO, framed.get_size()), Vector2i(left.get_width() + gap, 0))
	out.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()),
			Vector2i(left.get_width() + framed.get_width() + gap * 2, 0))
	out.save_png("%s/%s.png" % [SHOTS, tag])
	print("  %s" % tag)


func _capture(tag: String) -> Image:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, tag])
	print("  %s" % tag)
	return image
