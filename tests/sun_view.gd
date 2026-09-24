extends SceneTree
## Run: godot --path . --script res://tests/sun_view.gd
##
## Points the camera at the sun and at the water under it, so the disc, its rings and the
## sun's streak can be looked at; then checks the horizon from the beach and from a height.
## Not headless - no renderer there.

const SHOTS := "user://sun"

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
	# Hold the sun where the scene put it: the day clock would move it between shots.
	var day := scene.get_node_or_null("Day")
	if day != null:
		day.set_process(false)
		day.set_physics_process(false)
	var rig := scene.get_node("CameraRig")
	var sun := scene.get_node("Sun") as DirectionalLight3D
	var to_sun := sun.global_transform.basis.z
	var bearing := atan2(-to_sun.x, -to_sun.z)
	var elevation := rad_to_deg(asin(to_sun.y))
	print("sun: bearing %.0f deg, elevation %.1f deg" % [rad_to_deg(bearing), elevation])
	DirAccess.make_dir_recursive_absolute(SHOTS)

	# Face it, chase camera, as high as the rig now allows.
	rig.rotation.y = bearing
	rig.pitch_degrees = rig.max_pitch_degrees
	rig._apply_pitch()
	for i in 20:
		await process_frame
	await _shot("00_chase_at_sun", rig)

	# And through the glass, which can look higher.
	rig.set_glassing(true)
	rig.rotation.y = bearing
	rig.pitch_degrees = elevation
	rig._apply_pitch()
	for i in 30:
		await process_frame
	await _shot("01_glass_on_disc", rig)
	rig._magnify(1.0)
	for i in 12:
		await process_frame
	await _shot("02_glass_2x", rig)

	# Down onto the water below the sun, where the streak should be.
	#
	# The captain has to be standing somewhere with SEA between him and the sun, which the
	# spawn is not - looking sunward from there is a beach. So walk out from the middle along
	# the sun's own bearing until the ground drops below the waterline, and stand just inside
	# that: whatever is in frame toward the sun is then water.
	rig.set_glassing(false)
	var terrain := scene.get_node("Terrain")
	var player := scene.get_node("Player") as CharacterBody3D
	var sea: float = terrain.sea_level()
	var out := Vector3(to_sun.x, 0.0, to_sun.z).normalized()
	var shore := 0.0
	for step in 120:
		var d := float(step) * 4.0
		if terrain.height_at(out.x * d, out.z * d) < sea:
			shore = d
			break
	var stand := out * maxf(shore - 10.0, 0.0)
	player.global_position = Vector3(stand.x, terrain.height_at(stand.x, stand.z) + 0.5, stand.z)
	player.velocity = Vector3.ZERO
	for i in 60:
		await process_frame
	rig.rotation.y = bearing
	rig.pitch_degrees = -14.0
	rig._apply_pitch()
	for i in 30:
		await process_frame
	await _shot("03_sun_streak", rig)
	# The horizon. The sea used to end in a broken row of sky-coloured dashes there: its mesh
	# stops a hair below the true horizon and, drawn dark blue to the last pixel, the edge
	# rasterised against the pale sky. Now it hazes to the sky's colour with distance and its
	# far rings are sent out to the horizon itself. Measured as the mechanism: with and
	# without the sea, the difference between the two frames has to arrive over many rows
	# coming down from the sky, never in one step - a step is an edge.
	var with_sea := Image.load_from_file(ProjectSettings.globalize_path("%s/03_sun_streak.png" % SHOTS))
	var ocean := scene.get_node("Ocean")
	ocean.hide()
	await _shot("03_no_sea", rig)
	ocean.show()
	var no_sea := Image.load_from_file(ProjectSettings.globalize_path("%s/03_no_sea.png" % SHOTS))
	# And once the sea has arrived, it has to be there in every pixel. The dashes were HOLES:
	# pixels in the middle of the sea that were the sky, unchanged from the frame with no
	# sea at all - the map's edge, where the bed used to drop a thousand metres in a step
	# and the shoreline softening thinned the water to nothing. A row that is mostly sea
	# with pixels in it that are not is what this counts; there were hundreds.
	var biggest_step := 0.0
	var previous := 0.0
	var ramp_rows := 0
	var holes := 0
	for y in range(with_sea.get_height() * 22 / 100, with_sea.get_height() * 60 / 100):
		var total := 0.0
		var count := 0
		var untouched := 0
		for x in range(0, with_sea.get_width(), 4):
			var bare := no_sea.get_pixel(x, y)
			var gap := absf(with_sea.get_pixel(x, y).get_luminance() - bare.get_luminance())
			total += gap
			count += 1
			# Only where the bare frame is sky. The island's own hill and beach sit in the
			# left of these rows and are the same with or without the sea, and are not holes.
			if gap < 0.01 and bare.b > 0.8 and bare.r < 0.75:
				untouched += 1
		var difference := total / float(count)
		biggest_step = maxf(biggest_step, difference - previous)
		if difference > 0.01 and difference < 0.15:
			ramp_rows += 1
		if difference > 0.15:
			holes += untouched
		previous = difference
	print("horizon: the sea arrives over %d rows, biggest step between rows %.3f (an edge stepped 0.1 or more); %d holes in it (the dashes were hundreds)" % [ramp_rows, biggest_step, holes])
	if biggest_step > 0.06:
		push_error("the sea still ends in an edge at the horizon (step %.3f)" % biggest_step)
		_failures += 1
	if holes > 40:
		push_error("the sea has %d holes in it - the dashed line is back" % holes)
		_failures += 1
	# And the opposite bearing, which should have no streak at all.
	rig.rotation.y = bearing + PI
	for i in 20:
		await process_frame
	await _shot("04_away_from_sun", rig)
	# The horizon from a height, where it is hardest: from the beach the sea's far edge is a
	# hundredth of a pixel below the true horizon; from sixty metres up it is where a mesh
	# ending at the far plane left three degrees of the sky's underside showing (two step
	# edges), and where the horizon band's top row was once drawn with a negative haze and
	# came out as one darker row along the whole horizon (a spike). Sea and sky have to meet
	# in one colour, so two things are measured on the mean luminance of each row, taken
	# across the middle third of the frame's width between 10% and 45% of its height: no
	# single row that differs from both its neighbours (a spike), and no step between two
	# rows larger than the haze's own gentle slope (an edge). The sea drawn to the far plane
	# steps 0.05 or more; the one-row line measured 0.03.
	var high := Camera3D.new()
	scene.add_child(high)
	high.fov = 60.0
	high.far = 1000.0
	high.global_position = Vector3(stand.x, sea + 60.0, stand.z)
	# Ten degrees down, which puts the horizon about a third of the way down the frame.
	high.look_at(high.global_position + out * 100.0 + Vector3(0.0, -100.0 * tan(deg_to_rad(10.0)), 0.0), Vector3.UP)
	high.current = true
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/05_high_horizon.png" % SHOTS)
	print("  %-18s pitch %+6.1f (its own camera, 60 m up)" % ["05_high_horizon", -10.0])
	var frame := Image.load_from_file(ProjectSettings.globalize_path("%s/05_high_horizon.png" % SHOTS))
	var rows: Array[float] = []
	for y in range(frame.get_height() * 10 / 100, frame.get_height() * 45 / 100):
		var total := 0.0
		var count := 0
		for x in range(frame.get_width() / 3, frame.get_width() * 2 / 3, 4):
			total += frame.get_pixel(x, y).get_luminance()
			count += 1
		rows.append(total / float(count))
	var worst_line := 0.0
	var worst_step := 0.0
	for i in range(1, rows.size() - 1):
		worst_step = maxf(worst_step, absf(rows[i] - rows[i - 1]))
		var against_neighbours := minf(absf(rows[i] - rows[i - 1]), absf(rows[i] - rows[i + 1]))
		if (rows[i] - rows[i - 1]) * (rows[i] - rows[i + 1]) > 0.0:
			worst_line = maxf(worst_line, against_neighbours)
	print("horizon from 60 m: worst single-row line %.4f, worst step between rows %.4f of luminance" % [worst_line, worst_step])
	if worst_line > 0.01:
		push_error("a line along the horizon from a height: one row differs from both neighbours by %.3f" % worst_line)
		_failures += 1
	if worst_step > 0.02:
		push_error("an edge at the horizon from a height: two rows differ by %.3f" % worst_step)
		_failures += 1
	high.current = false
	print("sun views: ", ProjectSettings.globalize_path(SHOTS))
	print("sun views: ", "PASS" if _failures == 0 else "FAIL")
	quit(0 if _failures == 0 else 1)


func _shot(tag: String, rig: Node) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [SHOTS, tag])
	print("  %-18s pitch %+6.1f" % [tag, rig.pitch_degrees])
