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


## Waits for the dive camera to stop moving. BOTH of its eases have to land, and they land at
## different times: the arm is still coming in long after the tilt has met the floor it was
## aiming at, so a wait on the tilt alone reads the camera mid-dolly and measures a number that
## was on its way somewhere else.
func settled(arm: SpringArm3D) -> void:
	var last_length := -999.0
	var last_view := -999.0
	var still := 0
	for tick in 300:
		await physics_frame
		if absf(arm.spring_length - last_length) < 0.005 				and absf(arm.rotation_degrees.x - last_view) < 0.02:
			still += 1
			if still >= 3:
				return
		else:
			still = 0
		last_length = arm.spring_length
		last_view = arm.rotation_degrees.x


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
	# UP MEANS UP, IN BOTH MODES. These three checks used to say the opposite, and the third one
	# actively REQUIRED the two modes to disagree - "both modes tilt the same way" was the
	# failure message. That was a defensible reading: a chase camera orbits a subject, so
	# dragging up swings it up and over and you end up looking down at him.
	#
	# It is not what the project does now. Two modes that mean opposite things by the same
	# gesture cannot be learned, because nothing on screen tells you which one is in force - and
	# touch ignored the flags entirely, so the glass already disagreed with itself between an
	# iPad and a mouse. One rule, everywhere: see CameraRig.tilt.
	check(readings[false][0] > 0.0,
			"chase: dragging up must look UP. Up means up - see camera_rig.gd tilt()")
	check(readings[true][0] > 0.0,
			"glassing: dragging up must look UP")
	check(signf(readings[false][0]) == signf(readings[true][0]),
			"the two modes tilt opposite ways. They must agree - that disagreement is the whole"
			+ " thing this convention exists to remove")

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
	# --- looking up and down under water ---
	#
	# A dive used to hold the tilt itself. The camera has to stay in the sea, so the pitch was
	# forced up until it did - and near the surface that left the player none of it: two metres
	# down the view sat five degrees off level whatever the mouse did. The rig pulls the ARM in
	# now and gives the look back, so these are the two things to measure. The view has to
	# answer the mouse at a shallow depth, and the camera still must not break the surface.
	rig.set_glassing(false)
	var under := Node3D.new()
	scene.add_child(under)
	# The dive crater, which holds 14.8 m of water. Sea level here is not zero - main.gd sets it
	# from the terrain - so every depth below is measured DOWN FROM rig.water_level. Written as
	# a plain -8 the first time, this put him twenty-six metres under and measured nothing: the
	# camera had all the room in the world and never came near the surface it is meant to duck.
	under.global_position = Vector3(225.0, rig.water_level - 8.0, -140.0)
	var chase_target: Node3D = rig._target
	rig.set_target(under)
	rig.set_diving(true)
	for tick in 200:
		await physics_frame
		if not rig._settling_length:
			break
	check(rig.dive_max_pitch > rig.max_pitch_degrees,
			"a dive cannot look higher than the chase camera does, so the surface above him is"
			+ " out of reach")
	# Up means up in the third mode as in the other two.
	rig.pitch_degrees = -20.0
	rig._apply_pitch()
	var dive_before: float = rig.pitch_degrees
	var dive_drag := InputEventMouseMotion.new()
	dive_drag.screen_relative = Vector2(0.0, -40.0)
	rig._mouse_looking = true
	rig._unhandled_input(dive_drag)
	rig._mouse_looking = false
	check(rig.pitch_degrees > dive_before, "diving: dragging up must look UP")
	print("%6s %8s %9s %7s %10s" % ["depth", "asked", "view", "arm", "cam under"])
	var lowest_view := {}
	for depth in [2.0, 4.0, 8.0]:
		under.global_position.y = rig.water_level - depth
		for asked in [-80.0, -55.0, 0.0, 55.0]:
			rig.pitch_degrees = asked
			rig._apply_pitch()
			await settled(arm)
			var view: float = arm.rotation_degrees.x
			print("%6.1f %8.0f %9.1f %7.2f %10.2f"
					% [depth, asked, view, arm.spring_length,
					rig.water_level - camera.global_position.y])
			check(camera.global_position.y <= rig.water_level,
					"diving %.0f m down and looking %.0f: the camera is %.2f m ABOVE the water"
					% [depth, asked, camera.global_position.y - rig.water_level])
			check(arm.spring_length <= rig.dive_distance + 0.01,
					"the arm is %.2f m under water, longer than the %.1f a dive asks for"
					% [arm.spring_length, rig.dive_distance])
			if asked < -70.0:
				lowest_view[depth] = view
			if asked > 0.0:
				check(view > 40.0,
						"diving %.0f m down: asked for %.0f up and got %.1f - looking up is"
						% [depth, asked, view] + " being taken away")
	# Two metres is where the old rule bit hardest: pinned near level, with no look down at the
	# thing he had just dived into.
	check(lowest_view[2.0] < -30.0,
			"two metres down, looking down reaches %.1f degrees - the mouse is not being heard"
			% lowest_view[2.0])
	check(lowest_view[8.0] < -70.0,
			"eight metres down, with nothing in the way, looking down reaches only %.1f degrees"
			% lowest_view[8.0])
	# The control has to come BACK. Held against the surface, the tilt used to be refused and
	# left wherever it had already sunk to - so every drag up was refused as well, and the view
	# was dead until one event crossed the whole gap. Two metres down, drag hard into the floor
	# and then ask to look up: the view has to answer the first drag.
	under.global_position.y = rig.water_level - 2.0
	await settled(arm)
	# The pitch a dive INHERITS, not one built up by dragging. This is the whole case: the chase
	# camera hands the dive its own steep look down, the surface holds the view well above it,
	# and the ask is under the floor before the player has touched anything. Refusing the tilt
	# from there refused every tilt.
	rig.pitch_degrees = -55.0
	rig._mouse_looking = true
	var into_floor := InputEventMouseMotion.new()
	into_floor.screen_relative = Vector2(0.0, 400.0)   # and a long drag DOWN on top of it
	rig._unhandled_input(into_floor)
	await settled(arm)
	var pinned: float = arm.rotation_degrees.x
	var small_up := InputEventMouseMotion.new()
	small_up.screen_relative = Vector2(0.0, -25.0)     # three degrees of drag UP
	rig._unhandled_input(small_up)
	rig._mouse_looking = false
	await settled(arm)
	var answered: float = arm.rotation_degrees.x - pinned
	print("pinned at %.1f, a 3 degree drag up moved the view %+.1f" % [pinned, answered])
	check(answered > 0.5,
			"held against the surface, a drag up moved the view %+.1f degrees - the control is"
			% answered + " stuck under the floor")

	rig.set_diving(false)
	rig.set_target(chase_target)
	under.queue_free()
	await physics_frame

	print("camera check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
