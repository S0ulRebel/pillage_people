extends SceneTree
## Run: godot --path . --script res://tests/glass_view.gd
##
## The captain's own spyglass, at each magnification, next to the same view without it.
## Not headless - there is no renderer there and every frame comes back blank.

const SHOTS := "user://glass"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
	var rig := scene.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("SpringArm3D/Camera3D")
	DirAccess.make_dir_recursive_absolute(SHOTS)

	# Level and out to sea, which is what the glass is for.
	rig.pitch_degrees = -4.0
	# Out to sea, which is what the glass is for - inland at this zoom is a wall of sand.
	rig.rotation.y = -0.6
	rig._apply_pitch()
	for i in 10:
		await process_frame
	await _shot("00_naked", camera, rig)

	rig.set_glassing(true)
	rig.pitch_degrees = -4.0
	rig._apply_pitch()
	for i in 40:
		await process_frame
	await _shot("01_raised", camera, rig)

	for step in 3:
		rig._magnify(1.0)
		for i in 12:
			await process_frame
		await _shot("%02d_zoom" % (step + 2), camera, rig)

	rig.set_glassing(false)
	for i in 40:
		await process_frame
	await _shot("05_lowered", camera, rig)
	print("glass views: ", ProjectSettings.globalize_path(SHOTS))
	quit(0)


func _shot(tag: String, camera: Camera3D, rig: Node) -> void:
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [SHOTS, tag])
	print("  %-12s fov %5.1f  mag %.1fx  pitch %.0f  arm %.1f"
			% [tag, camera.fov, rig._magnification, rig.pitch_degrees,
			rig.get_node("SpringArm3D").spring_length])
