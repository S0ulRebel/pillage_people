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
##   open_sea_low.png    open water from 8 m up, 30 degrees down, framed like the swatches
##   compare_water.png   the calm, small-waves and choppy swatches | open_sea_low
##   waves_0..2.png      the sea's height from 110 m up over the coast, 2 s apart (step 2)
##   overview.png        the same view as the game draws it
## Not headless - no renderer there.

const SHOTS := "user://foam"
const SHEET := "res://art/references/terrain-water-and-shore-transitions.jpg"
## Panel 9 (wet to dry sand, surf) and panel 10 (shallow water to beach, calm), in the sheet's
## 1280 x 853 pixels, below their titles.
const PANEL_9 := Rect2i(642, 457, 306, 377)
const PANEL_10 := Rect2i(955, 457, 323, 377)
## The "Water types" row of the water studies sheet (1280 x 853): calm, small waves, choppy.
const WATER_SHEET := "res://art/references/water-rock-wood-plant-studies.jpg"
const WATER_SWATCHES: Array[Rect2i] = [Rect2i(10, 313, 61, 112), Rect2i(74, 313, 61, 112),
		Rect2i(137, 313, 61, 112)]
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

	# FOAM_SEA_ONLY=1 skips to the open-sea views, for tuning the whitecaps quickly.
	var sea_only := OS.get_environment("FOAM_SEA_ONLY") == "1"
	_aim(camera, target, inland, ARM)
	var game := await _capture("gameplay")
	if not sea_only:
		await _shore_views(sheet, game, camera, target, terrain, ocean, shore, inland)
	await _sea_views(camera, ocean, shore, inland)
	if not sea_only:
		await _wave_views(camera, ocean, shore, inland)
	print("foam views: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else 1)


func _shore_views(sheet: Image, game: Image, camera: Camera3D, target: Vector3, terrain: Node,
		ocean: Node, shore: Vector3, inland: Vector3) -> void:
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


func _sea_views(camera: Camera3D, ocean: Node, shore: Vector3, inland: Vector3) -> void:
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

	# And framed like the references' water-type swatches: from 8 m up, 30 degrees down, over
	# open water - next to the "small waves" and "choppy" swatches.
	# Looking into the swell, the way the swatches are painted: the waves come toward the eye
	# and their crests run across the frame.
	var swell: Vector4 = ocean.wave_1
	var into := -Vector3(swell.x, 0.0, swell.y).normalized()
	camera.global_position = open_sea + Vector3.UP * 8.0 - into * 12.0
	camera.look_at(camera.global_position + into * cos(deg_to_rad(30.0)) - Vector3.UP * sin(deg_to_rad(30.0)), Vector3.UP)
	var low := await _capture("open_sea_low")
	_swatches(low)
	if OS.get_environment("FOAM_DEBUG") == "1":
		ocean.material.set_shader_parameter("whitecap_debug", 1)
		await _capture("debug_low")
		ocean.material.set_shader_parameter("whitecap_debug", 0)
	if OS.get_environment("FOAM_STYLES") == "1":
		await _style_views(camera, ocean, open_sea, inland, low)


## PROTOTYPE comparison (docs/foam-plan.md, 8k): each whitecap_style from the swatch framing
## and from the gameplay camera, next to the "choppy" swatch, and style 2's events over time.
##   styles_low.png       choppy swatch | net | painted lattice | events | lattice + events
##   styles_gameplay.png  the same four styles from the gameplay camera
##   events_time.png      lattice + events at four moments 1.2 s apart
func _style_views(camera: Camera3D, ocean: Node, open_sea: Vector3, inland: Vector3,
		low: Image) -> void:
	var low_xf := camera.global_transform
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(WATER_SHEET))
	sheet.convert(Image.FORMAT_RGB8)
	var h := low.get_height()
	var swatch := sheet.get_region(WATER_SWATCHES[2])
	swatch.resize(int(round(float(h) * float(WATER_SWATCHES[2].size.x) / float(WATER_SWATCHES[2].size.y))), h,
			Image.INTERPOLATE_LANCZOS)
	var lows: Array[Image] = [swatch]
	var tops: Array[Image] = []
	for style in 4:
		ocean.material.set_shader_parameter("whitecap_style", style)
		camera.global_transform = low_xf
		lows.append(_middle(await _capture("style_%d_low" % style), 0.9))
		_aim(camera, open_sea + Vector3.UP * TARGET_HEIGHT, inland, ARM)
		tops.append(_middle(await _capture("style_%d_gameplay" % style), 0.9))
	_strip(lows, "styles_low")
	_strip(tops, "styles_gameplay")
	ocean.material.set_shader_parameter("whitecap_style", 3)
	camera.global_transform = low_xf
	var times: Array[Image] = []
	for k in 4:
		ocean.hold_clock = MOMENT + 1.2 * float(k)
		times.append(_middle(await _capture("events_%d" % k), 0.9))
	ocean.hold_clock = MOMENT
	_strip(times, "events_time")
	ocean.material.set_shader_parameter("whitecap_style", 3)


func _middle(image: Image, aspect: float) -> Image:
	var img := image.duplicate() as Image
	img.convert(Image.FORMAT_RGB8)
	var h := img.get_height()
	var w := int(round(float(h) * aspect))
	return img.get_region(Rect2i((img.get_width() - w) / 2, 0, w, h))


func _strip(parts: Array[Image], tag: String) -> void:
	var h := parts[0].get_height()
	var total := 0
	for part in parts:
		total += part.get_width() + 12
	var out := Image.create_empty(total, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.09, 0.12))
	var x := 0
	for part in parts:
		out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(x, 0))
		x += part.get_width() + 12
	out.save_png("%s/%s.png" % [SHOTS, tag])
	print("  %s" % tag)


func _wave_views(camera: Camera3D, ocean: Node, shore: Vector3, inland: Vector3) -> void:
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


## The swatches of water-rock-wood-plant-studies.jpg's "Water types" row - calm, small waves,
## choppy - beside the low open-sea view, all at the frame's height.
func _swatches(game: Image) -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(WATER_SHEET))
	if sheet == null:
		return
	sheet.convert(Image.FORMAT_RGB8)
	game = game.duplicate()
	game.convert(Image.FORMAT_RGB8)
	var h := game.get_height()
	var parts: Array[Image] = []
	for rect in WATER_SWATCHES:
		var swatch := sheet.get_region(rect)
		swatch.resize(int(round(float(h) * float(rect.size.x) / float(rect.size.y))), h,
				Image.INTERPOLATE_LANCZOS)
		parts.append(swatch)
	var w := int(round(float(h) * 0.9))
	parts.append(game.get_region(Rect2i((game.get_width() - w) / 2, 0, w, h)))
	var total := 0
	for part in parts:
		total += part.get_width() + 12
	var out := Image.create_empty(total, h, false, Image.FORMAT_RGB8)
	out.fill(Color(0.08, 0.09, 0.12))
	var x := 0
	for part in parts:
		out.blit_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), Vector2i(x, 0))
		x += part.get_width() + 12
	out.save_png("%s/compare_water.png" % SHOTS)
	print("  compare_water")


func _capture(tag: String) -> Image:
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, tag])
	print("  %s" % tag)
	return image
