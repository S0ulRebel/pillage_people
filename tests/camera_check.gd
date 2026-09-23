extends SceneTree
## Run: godot --headless --path . --script res://tests/camera_check.gd
##
## Checks the camera's two modes: the chase rig, and the captain's spyglass.
##
## The tilt direction is in here because it escaped once. The two modes mean genuinely
## different things by the same mouse movement - the chase camera ORBITS him, so dragging up
## swings it over and you look down at him, while the glass is first person and dragging up
## has to look up. Sharing one line of code between them made the glass feel reversed, and
## nothing caught it because nothing had ever asked which way either of them went.

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
	for i in 40:
		await physics_frame
	var rig := scene.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("SpringArm3D/Camera3D")
	var arm: SpringArm3D = rig.get_node("SpringArm3D")

	# --- tilt direction, in both modes ---
	print("%-10s %10s %11s   %s" % ["mode", "drag up", "drag down", "meaning"])
	var readings := {}
	for glassing in [false, true]:
		rig.set_glassing(glassing)
		await physics_frame
		var moved: Array[float] = []
		for motion in [-40.0, 40.0]:
			rig.pitch_degrees = -30.0 if glassing else -50.0
			rig._apply_pitch()
			var before: float = rig.pitch_degrees
			var event := InputEventMouseMotion.new()
			event.screen_relative = Vector2(0.0, motion)
			rig._mouse_looking = true
			rig._unhandled_input(event)
			moved.append(rig.pitch_degrees - before)
		readings[glassing] = moved
		print("%-10s %+9.1f %+11.1f   %s" % [
				"glassing" if glassing else "chase", moved[0], moved[1],
				"up -> look up" if moved[0] > 0.0 else "up -> look down"])
	rig._mouse_looking = false
	check(readings[false][0] < 0.0,
			"chase: dragging up should look DOWN at him, the way orbiting a subject does")
	check(readings[true][0] > 0.0,
			"glassing: dragging up should look UP - this is first person, not an orbit")
	check(signf(readings[false][0]) != signf(readings[true][0]),
			"both modes tilt the same way; one of them is reversed for whoever is using it")

	# --- what raising the glass actually does ---
	rig.set_glassing(false)
	await physics_frame
	var wide_fov: float = camera.fov
	var rested: float = arm.spring_length
	rig.set_glassing(true)
	await physics_frame
	var glass_fov: float = camera.fov
	var glass_arm: float = arm.spring_length
	rig._magnify(3.0)
	await physics_frame
	var zoomed_fov: float = camera.fov
	rig.set_glassing(false)
	await physics_frame

	print("fov %.0f -> %.0f raised -> %.1f at %.0fx | arm %.0f -> %.0f -> %.0f"
			% [wide_fov, glass_fov, zoomed_fov, rig._magnification, rested, glass_arm,
			arm.spring_length])
	check(glass_fov < wide_fov, "raising the glass did not narrow the field of view")
	check(zoomed_fov < glass_fov, "the wheel did not magnify while glassing")
	check(glass_arm == 0.0,
			"the arm is %.1f m while glassing - the camera is not at his eye" % glass_arm)
	check(arm.spring_length == rested,
			"lowering the glass left the arm at %.1f instead of %.1f"
			% [arm.spring_length, rested])
	# Looking at a horizon is the whole point, and the chase limits stop at -12 degrees.
	check(rig.glass_max_pitch > 0.0,
			"the glass cannot be raised above level, so it cannot look at a horizon")
	print("camera check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
