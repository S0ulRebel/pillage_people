extends SceneTree
## Run: godot --path . --script res://tests/sun_view.gd
##
## Points the camera at the sun and at the water under it, so the disc, its rings and the
## glitter path can be looked at. Not headless - no renderer there.

const SHOTS := "user://sun"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
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

	# Down onto the water below the sun, where the glitter should be.
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
	await _shot("03_glitter_path", rig)
	# And the opposite bearing, which should have no glitter at all.
	rig.rotation.y = bearing + PI
	for i in 20:
		await process_frame
	await _shot("04_away_from_sun", rig)
	print("sun views: ", ProjectSettings.globalize_path(SHOTS))
	quit(0)


func _shot(tag: String, rig: Node) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [SHOTS, tag])
	print("  %-18s pitch %+6.1f" % [tag, rig.pitch_degrees])
