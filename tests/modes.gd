extends Node
## Every command-line mode: the ones that render a picture, the ones that walk the captain
## through a manoeuvre and print what happened, and the ones that kill him to check the island
## comes back.
##
## These were 442 of main.gd's 943 lines - nearly half the orchestrator was code that only runs
## when a flag is passed, sitting in the same file as the thing it inspects. They are not
## tests in the tests/ sense: several of them only print or render, and a person reads the
## result. What they have in common is that none of them happens during a normal game.
##
## They are handed the scene rather than reaching into it, so this file never has to know how
## main is laid out beyond the four nodes it asks for by name.

## Survives a scene reload, because the script does and the node does not. Only --deathtest
## uses it.
static var _death_test_runs := 0

var _main: Node3D
var _player: CharacterBody3D
var _terrain: StaticBody3D
var _camera_rig: Node3D


## Runs whichever mode was asked for, or nothing at all. `holes` is where the tunnel probes
## expect to find tunnel mouths - empty unless one was generated.
func begin(main_scene: Node3D, holes: Array[Vector3]) -> void:
	_main = main_scene
	_player = main_scene.get_node("Player")
	_terrain = main_scene.get_node("Terrain")
	_camera_rig = main_scene.get_node("CameraRig")

	var args := OS.get_cmdline_user_args()
	if "--probepath" in args:
		_probe_path()
	elif "--probe" in args:
		_probe(holes)
	elif "--holeview" in args:
		_hole_view(holes)
	elif "--tunneltest" in args:
		_tunnel_test(holes)
	elif "--holeshot" in args and not holes.is_empty():
		_player.global_position = Vector3(holes[0].x, 0, holes[0].y) + Vector3(9, 0, 9) 				+ Vector3.UP * (_terrain.height_at(holes[0].x + 9, holes[0].y + 9) + 2.0)
		_camera_rig.set_target(_player)
		_screenshot_and_quit()
	elif "--deathtest" in args:
		_death_test()
	elif "--jumptest" in args:
		_jump_test()
	elif "--swimtest" in args:
		_swim_test()
	elif "--touchtest" in args:
		_touch_self_test()
	elif "--shore" in args:
		_shore_view()
	elif "--ship" in args:
		_ship_view()
	elif "--boardtest" in args:
		_board_test()
	elif "--overview" in args:
		_overview()
	elif "--assetview" in args:
		_asset_view()
	elif "--screenshot" in args:
		_screenshot_and_quit()




## Kills the captain and checks the island actually comes back.
##
## Run as a real scene rather than through a --script harness, because reload_current_scene
## needs a current scene and a hand-instantiated one has none - which made the first attempt at
## testing this report a failure that was entirely the test's own.
func _death_test() -> void:
	# A static counter, which survives the reload because the script does. The first run kills
	# the captain; the second run only happens if the island really did come back, and reports
	# what it came back as. Without this the test kills him again on every reload and never
	# stops - which it did.
	_death_test_runs += 1
	if _death_test_runs > 1:
		var band := _main.get_node_or_null("Grunts")
		var rocks := _main.get_node_or_null("Rocks")
		print("death test: the island came back - player %d/%d hp, dead=%s, %d grunts, %d rocks"
				% [_player.health(), _player.max_health, _player.is_dead(),
				band.get_child_count() if band != null else 0,
				rocks.get_child_count() if rocks != null else 0])
		get_tree().quit(0)
		return
	for i in 60:
		await get_tree().physics_frame
	print("death test: killing the captain")
	_player.take_damage(999, null)
	print("  dead=", _player.is_dead(), ", waiting ", _main.restart_delay, "s for the restart")
	await get_tree().create_timer(_main.restart_delay + 3.0).timeout
	print("death test: FAILED - no reload happened")
	get_tree().quit(1)




## A low shot along the waterline, which is the only place the water shader can be judged:
## depth colour, transparency over the sand and the foam line all live at the shore.
func _shore_view() -> void:
	var sea: float = _terrain.sea_level()
	var best := Vector3.ZERO
	var best_error := 1e9
	# Walk out from the middle along one bearing until the ground crosses sea level.
	for i in 900:
		var angle := TAU * float(i) / 900.0
		for step in 60:
			var d: float = 40.0 + float(step) * 4.0
			var p := Vector3(cos(angle) * d, 0.0, sin(angle) * d)
			var e: float = absf(_terrain.height_at(p.x, p.z) - sea)
			if e < best_error:
				best_error = e
				best = Vector3(p.x, _terrain.height_at(p.x, p.z), p.z)
	var outward := Vector3(best.x, 0.0, best.z).normalized()
	var camera := Camera3D.new()
	_main.add_child(camera)
	camera.fov = 60.0
	camera.far = 6000.0
	camera.global_position = best + outward * 34.0 + Vector3.UP * (sea + 9.0 - best.y)
	camera.look_at(best - outward * 30.0 + Vector3.UP * 6.0, Vector3.UP)
	camera.current = true
	print("shore at ", best, " (error %.2f m)" % best_error)
	_screenshot_and_quit()




## Three-quarter on the moored hull. The chase camera looks inland at the beach, so this is
## the shot that can actually see the ship.
func _ship_view() -> void:
	var ship := _main.get_node_or_null("Ship") as Node3D
	if ship == null:
		push_error("--ship: no ship in the scene")
		get_tree().quit(1)
		return
	var camera := Camera3D.new()
	_main.add_child(camera)
	camera.fov = 50.0
	camera.far = 6000.0
	# Bow keel is the origin. Step off the starboard bow and look back at the midships deck.
	camera.global_position = ship.global_position + ship.global_basis * Vector3(22.0, 10.0, -6.0)
	camera.look_at(ship.global_position + ship.global_basis * Vector3(0.0, 3.2, 7.0), Vector3.UP)
	camera.current = true
	# Drop the captain on the weather deck, clear of the stair opening around Z=4.
	# The print from the screenshot says whether the hull actually holds him.
	_player.velocity = Vector3.ZERO
	_player.global_position = ship.to_global(Vector3(0.0, 7.0, 10.0))
	print("ship at ", ship.global_position)
	_screenshot_and_quit()


## Puts him beside the hull, climbs, and checks he is standing on the deck.
func _board_test() -> void:
	var ship := _main.get_node_or_null("Ship") as Node3D
	if ship == null:
		push_error("board test: no ship")
		get_tree().quit(1)
		return
	var beside := ship.to_global(Vector3(4.5, 1.2, 7.0))
	_player.global_position = beside
	_player.velocity = Vector3.ZERO
	if not _player.try_board():
		push_error("board test: beside the hull should climb")
		get_tree().quit(1)
		return
	for _i in 40:
		await get_tree().physics_frame
	var local: Vector3 = ship.to_local(_player.global_position)
	print("board test: local ", local, " on_floor=", _player.is_on_floor())
	if local.y < 4.8 or not _player.is_on_floor():
		push_error("board test: he is not standing on the deck")
		get_tree().quit(1)
		return
	if _player.boarding():
		push_error("board test: still offering a climb once he is up")
		get_tree().quit(1)
		return
	_player.global_position = ship.to_global(Vector3(0.0, 5.4, 13.2))
	_player.velocity = Vector3.ZERO
	if not _player.try_helm():
		push_error("board test: at the wheel should take the helm")
		get_tree().quit(1)
		return
	var before: Vector3 = ship.global_position
	for _j in 20:
		ship.drive(0.05, 1.0, 0.0)
	if ship.global_position.distance_to(before) < 1.0:
		push_error("board test: the hull did not move ahead")
		get_tree().quit(1)
		return
	var sea: float = _terrain.sea_level()
	var low := ship.global_position.y
	var high := low
	var sum := 0.0
	for _k in 180:
		await get_tree().physics_frame
		var keel: float = ship.global_position.y
		low = minf(low, keel)
		high = maxf(high, keel)
		sum += keel
	var mean := sum / 180.0
	print("board test: heave %.3f m, mean keel %.2f (flat draft %.2f)" % [high - low, mean, sea - 2.0])
	if high - low < 0.02:
		push_error("board test: the hull did not rise and fall with the water")
		get_tree().quit(1)
		return
	# The long swell stacks to about a metre. More than that, with the mean still on the
	# draft, would be the hull throwing itself.
	if high - low > 1.6:
		push_error("board test: the hull heaved %.2f m" % (high - low))
		get_tree().quit(1)
		return
	if absf(mean - (sea - 2.0)) > 0.45:
		push_error("board test: buoyancy did not settle near the draft")
		get_tree().quit(1)
		return
	if not _player.try_helm():
		push_error("board test: E again should leave the wheel")
		get_tree().quit(1)
		return
	_player.global_position = ship.to_global(Vector3(30.0, 1.2, 7.0))
	if _player.try_board():
		push_error("board test: thirty metres off should not climb")
		get_tree().quit(1)
		return
	print("board test: ok")
	get_tree().quit()




## A high, wide shot of the whole island and the sea around it - the view that shows whether
## the shoreline, the scale and the water read correctly, which a ground-level shot cannot.
func _overview() -> void:
	# Its own camera rather than the rigged one: the SpringArm keeps writing to that camera's
	# transform every frame, so moving it has no lasting effect.
	var camera := Camera3D.new()
	_main.add_child(camera)
	camera.fov = 55.0
	camera.far = 6000.0
	camera.global_position = Vector3(0.0, _terrain.height_scale * 3.2, _terrain.world_size * 1.15)
	camera.look_at(Vector3(0.0, _terrain.height_scale * 0.2, 0.0), Vector3.UP)
	camera.current = true
	_screenshot_and_quit()




func _screenshot_and_quit() -> void:
	# let physics settle first: if the player falls through the terrain, the picture shows it
	for i in 90:
		await get_tree().process_frame
	print("player settled at ", _player.global_position, " ground ",
			_terrain.height_at(_player.global_position.x, _player.global_position.z),
			" on_floor=", _player.is_on_floor())
	# Headless has no renderer, so frame_post_draw never fires and awaiting it waits forever.
	# Every mode that finishes by calling this then hangs instead of quitting - silently, with
	# no error and no window, which is how three --touchtest runs sat in the process list for
	# twenty-two hours holding a log file open. The run still has to END; it just cannot take
	# a picture.
	if DisplayServer.get_name() == "headless":
		print("screenshot: skipped, this run has no renderer")
		get_tree().quit()
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://screenshot.png")
	print("screenshot: ", ProjectSettings.globalize_path("user://screenshot.png"))
	get_tree().quit()




## Feeds synthetic touch events through the same path as a real finger, so the iPad controls
## can be checked from a desktop run: python-free smoke test for stick, orbit and jump.
## Walks the swim states on the iPad controls, because the dive button is the only way down
## on touch and a button that silently does nothing is indistinguishable from deep water.
func _swim_test() -> void:
	var touch: CanvasLayer = _main.get_node("TouchControls")
	var sea: float = _terrain.sea_level()
	await get_tree().process_frame

	var failures := 0
	# Drop into open water well off the beach, where the seabed is clear below, and let the
	# surface take him: a plunge is not a dive.
	var deep := Vector3(0.0, sea - 3.0, _terrain.world_size * 0.42)
	_player.global_position = deep
	_player.velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame
	var surface: float = _player.surface_depth()
	print("in water: swimming=%s diving=%s dive button visible=%s, %.2f m under (floats at %.2f)"
			% [_player.is_swimming(), _player.is_diving(), touch.get_node("DiveButton").visible,
			_player.submersion(), surface])
	if _player.is_diving() or absf(_player.submersion() - surface) > 0.2:
		failures += 1
		push_error("a plunge should float him back to the surface, not leave him %.2f m under"
				% _player.submersion())

	# Dive: down while the key is held - the real key, so the binding is part of what is
	# tested; the touch button's path is exercised further down.
	var before: float = _player.global_position.y
	Input.action_press("dive")
	for i in 30:
		await get_tree().physics_frame
	var after_dive: float = _player.global_position.y
	print("dive:    %.2f -> %.2f m (%.2f), diving=%s" % [before, after_dive, after_dive - before, _player.is_diving()])
	if not _player.is_diving() or after_dive > before - 1.0:
		failures += 1
		push_error("holding dive should take him down and leave him diving")

	# ...and held there once it is let go. This is the rule: no floating back up. Measured
	# after the water has taken his momentum, which is a dozen frames of drift - and with
	# water under him, or the seabed would be doing the holding and the check would prove
	# nothing.
	Input.action_release("dive")
	for i in 15:
		await get_tree().physics_frame
	var rest: float = _player.global_position.y
	for i in 60:
		await get_tree().physics_frame
	var held: float = _player.global_position.y
	var clearance: float = held - _terrain.height_at(_player.global_position.x, _player.global_position.z)
	print("let go:  drifted to %.2f m, then held within %.3f m for a second with %.2f m of water under him, diving=%s"
			% [rest, absf(held - rest), clearance, _player.is_diving()])
	if not _player.is_diving() or absf(held - rest) > 0.05:
		failures += 1
		push_error("letting go of dive should hold his depth; he moved %.2f m" % (held - rest))
	if clearance < 0.3:
		failures += 1
		push_error("he is resting on the seabed (%.2f m clear), so the hold proves nothing" % clearance)

	# Up while jump is held, held again when it is let go short of the surface.
	_player.request_jump()
	for i in 10:
		await get_tree().physics_frame
	_player.release_jump()
	for i in 15:
		await get_tree().physics_frame
	var part_way: float = _player.global_position.y
	for i in 60:
		await get_tree().physics_frame
	var held_again: float = _player.global_position.y
	print("swim up: %.2f -> %.2f m, let go and held within %.3f m, diving=%s"
			% [held, part_way, absf(held_again - part_way), _player.is_diving()])
	if part_way <= held + 0.3 or not _player.is_diving() or absf(held_again - part_way) > 0.05:
		failures += 1
		push_error("jump should raise him, and letting go short of the surface should hold him there, still diving")

	# The touch button sinks him the same way.
	_player.set_diving(true)
	for i in 10:
		await get_tree().physics_frame
	_player.set_diving(false)
	for i in 15:
		await get_tree().physics_frame
	var touched: float = _player.global_position.y
	print("button:  %.2f -> %.2f m (%.2f), diving=%s" % [held_again, touched, touched - held_again, _player.is_diving()])
	if touched >= held_again - 0.3 or not _player.is_diving():
		failures += 1
		push_error("the touch dive button should sink him like the key does")

	# Jump held long enough reaches the surface, and that is what ends the dive.
	_player.request_jump()
	var frames := 0
	while _player.is_diving() and frames < 300:
		await get_tree().physics_frame
		frames += 1
	_player.release_jump()
	for i in 60:
		await get_tree().physics_frame
	print("surface: dive over after %d frames, settled %.2f m under, swimming=%s diving=%s"
			% [frames, _player.submersion(), _player.is_swimming(), _player.is_diving()])
	if _player.is_diving() or not _player.is_swimming() \
			or absf(_player.submersion() - surface) > 0.2:
		failures += 1
		push_error("holding jump to the surface should end the dive and leave him swimming on it")

	# The camera: under the water with him while he dives, back up once he surfaces - and
	# not at all with the follow switched off.
	var rig := _main.get_node("CameraRig")
	var camera: Camera3D = rig.get_node("SpringArm3D/Camera3D")
	var camera_after_surfacing: float = camera.global_position.y
	# Eased, not cut: the biggest move the camera makes in one physics frame, going under and
	# coming back up. Cut, it jumped ten metres along the arm.
	var jump := 0.0
	var last: Vector3 = camera.global_position
	var arm: SpringArm3D = rig.get_node("SpringArm3D")
	var chase_length: float = arm.spring_length
	Input.action_press("dive")
	for i in 45:
		await get_tree().physics_frame
		# A wobble of the mouse mid-ease. It used to cut the camera to the end of the ease.
		if i % 5 == 2:
			rig.tilt(0.5)
		jump = maxf(jump, camera.global_position.distance_to(last))
		last = camera.global_position
	var camera_diving: float = camera.global_position.y
	# No spyglass under water.
	var glass_refused: bool = not rig.set_glassing(true)
	Input.action_release("dive")
	_player.request_jump()
	frames = 0
	while _player.is_diving() and frames < 300:
		await get_tree().physics_frame
		frames += 1
	_player.release_jump()
	for i in 60:
		await get_tree().physics_frame
		if i % 5 == 2:
			rig.tilt(-0.5)
		jump = maxf(jump, camera.global_position.distance_to(last))
		last = camera.global_position
	var camera_back: float = camera.global_position.y
	print("camera:  %.1f m over the sea after surfacing, %.1f m under it while diving, %.1f m over it once back up; biggest move in a frame %.2f m; glass refused under water=%s"
			% [camera_after_surfacing - sea, sea - camera_diving, camera_back - sea, jump, glass_refused])
	if camera_after_surfacing < sea or camera_diving > sea - 0.5 or camera_back < sea:
		failures += 1
		push_error("the camera should be under the water only while he is diving")
	# Cut, the camera moved ten metres in a frame; eased at six per second from seventeen
	# metres up it moves under three. Half a cut is the line.
	if jump > 5.0:
		failures += 1
		push_error("the camera cut %.2f m in one frame - the dive should be eased" % jump)
	if not glass_refused:
		failures += 1
		push_error("the spyglass should refuse while diving")
	# The toggle: off before a dive, the camera never goes under; off during one, it comes up.
	rig.follow_dives = false
	Input.action_press("dive")
	for i in 45:
		await get_tree().physics_frame
	var camera_unfollowed: float = camera.global_position.y
	rig.follow_dives = true
	Input.action_release("dive")
	_player.request_jump()
	frames = 0
	while _player.is_diving() and frames < 300:
		await get_tree().physics_frame
		frames += 1
	_player.release_jump()
	for i in 30:
		await get_tree().physics_frame
	Input.action_press("dive")
	for i in 45:
		await get_tree().physics_frame
	var camera_followed: float = camera.global_position.y
	rig.follow_dives = false
	for i in 60:
		await get_tree().physics_frame
	var camera_recalled: float = camera.global_position.y
	rig.follow_dives = true
	Input.action_release("dive")
	print("camera:  follow off, %.1f m over the sea while diving; on, %.1f m under; switched off mid-dive, %.1f m over"
			% [camera_unfollowed - sea, sea - camera_followed, camera_recalled - sea])
	if camera_unfollowed < sea or camera_followed > sea - 0.5 or camera_recalled < sea:
		failures += 1
		push_error("follow_dives should keep the camera up when off, and bring it up when switched off mid-dive")
	# Bobbing: surface, and dive again before the camera has finished coming back up, three
	# times. The chase distance has to come back whole; it used to ratchet down a tap at a time.
	_player.request_jump()
	frames = 0
	while _player.is_diving() and frames < 300:
		await get_tree().physics_frame
		frames += 1
	_player.release_jump()
	for bob in 3:
		for i in 12:
			await get_tree().physics_frame
		Input.action_press("dive")
		for i in 20:
			await get_tree().physics_frame
		Input.action_release("dive")
		_player.request_jump()
		frames = 0
		while _player.is_diving() and frames < 300:
			await get_tree().physics_frame
			frames += 1
		_player.release_jump()
	for i in 90:
		await get_tree().physics_frame
	print("camera:  chase distance %.1f m after three quick dives, was %.1f m" % [arm.spring_length, chase_length])
	if absf(arm.spring_length - chase_length) > 0.1:
		failures += 1
		push_error("quick dives ratcheted the chase distance from %.1f to %.1f m" % [chase_length, arm.spring_length])

	# Back on land the button has to go away, and dive must not stay latched on.
	_player.global_position = _terrain.find_spawn() + Vector3.UP * 2.0
	for i in 6:
		await get_tree().physics_frame
	print("on land: swimming=%s diving=%s dive button visible=%s"
			% [_player.is_swimming(), _player.is_diving(), touch.get_node("DiveButton").visible])
	if _player.is_diving() or touch.get_node("DiveButton").visible:
		failures += 1
		push_error("on land the dive button should be gone and the dive over")
	print("swim test: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)




func _touch_self_test() -> void:
	var touch: CanvasLayer = _main.get_node("TouchControls")
	var camera_rig: Node3D = _camera_rig
	await get_tree().process_frame

	var start: Vector3 = _player.global_position
	_send_touch(0, Vector2(150, 600), true)
	_send_drag(0, Vector2(150, 600), Vector2(255, 600))
	for i in 45:
		await get_tree().process_frame
	var moved: float = _player.global_position.distance_to(start)
	print("stick: move=%s player moved %.2f m" % [touch.move, moved])
	_send_touch(0, Vector2(255, 600), false)

	var before_yaw: float = camera_rig.rotation.y
	_send_touch(1, Vector2(1000, 300), true)
	_send_drag(1, Vector2(1000, 300), Vector2(1140, 300))
	await get_tree().process_frame
	await get_tree().process_frame
	print("orbit: camera yaw changed by %.3f rad" % [camera_rig.rotation.y - before_yaw])
	_send_touch(1, Vector2(1140, 300), false)

	# drag up/down on the right half tilts the camera
	var before_pitch: float = camera_rig.pitch_degrees
	_send_touch(2, Vector2(1000, 300), true)
	_send_drag(2, Vector2(1000, 300), Vector2(1000, 420))
	await get_tree().process_frame
	await get_tree().process_frame
	print("tilt (drag): pitch %.1f -> %.1f degrees" % [before_pitch, camera_rig.pitch_degrees])
	_send_touch(2, Vector2(1000, 420), false)

	# wait until the player is standing before testing the jump button
	for i in 120:
		if _player.is_on_floor():
			break
		await get_tree().physics_frame
	var grounded: bool = _player.is_on_floor()
	touch.jumped.emit()
	# physics_frame fires before nodes run _physics_process, so wait for the frame after
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("jump: on_floor=%s vertical velocity -> %.2f" % [grounded, _player.velocity.y])
	_screenshot_and_quit()




func _send_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)




func _send_drag(index: int, from: Vector2, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to
	event.relative = to - from
	Input.parse_input_event(event)




## Measures the jump: how high it goes and how long it stays in the air, for a full-hold
## jump and for a tapped (released early) one.
func _jump_test() -> void:
	for i in 180:
		if _player.is_on_floor():
			break
		await get_tree().physics_frame
	for hold in [true, false]:
		while not _player.is_on_floor():
			await get_tree().physics_frame
		var ground: float = _player.global_position.y
		var peak := ground
		var frames := 0
		_player.request_jump()
		await get_tree().physics_frame
		await get_tree().physics_frame
		if not hold:
			_player.release_jump()
		while not _player.is_on_floor() and frames < 400:
			peak = maxf(peak, _player.global_position.y)
			frames += 1
			await get_tree().physics_frame
		print("%s jump: height %.2f m, airtime %.2f s" % [
				"held" if hold else "tapped", peak - ground, frames / 60.0])
	get_tree().quit()




## Walks the player along the tunnel: in at one opening, through, and out at the other.
func _tunnel_test(holes: Array[Vector3]) -> void:
	if _terrain.tunnels.is_empty():
		print("tunnel test: no tunnel")
		get_tree().quit()
		return
	var tunnel = _terrain.tunnels[0]
	var curve: Curve3D = tunnel.curve
	var total: float = curve.get_baked_length()

	# waypoints along the curve, plus a point past the far end to walk out to
	var route: Array[Vector3] = []
	for i in range(1, 11):
		route.append(tunnel.to_global(curve.sample_baked(total * i / 10.0)))
	var last: Vector3 = route[route.size() - 1]
	var second_last: Vector3 = route[route.size() - 2]
	route.append(last + (last - second_last).normalized() * 12.0)

	# start on the surface, just short of the opening
	var first: Vector3 = tunnel.to_global(curve.sample_baked(0.0))
	var into: Vector3 = (tunnel.to_global(curve.sample_baked(6.0)) - first).normalized()
	var start_point: Vector3 = first - into * 6.0
	_player.global_position = Vector3(start_point.x,
			_terrain.height_at(start_point.x, start_point.z) + 2.0, start_point.z)
	_camera_rig.set_target(_player)
	_camera_rig.rotation.y = 0.0   # stick input is camera-relative
	await get_tree().physics_frame

	var deepest := 0.0
	var waypoint := 0
	for step in 60:
		var aim: Vector3 = route[waypoint]
		var here: Vector3 = _player.global_position
		if Vector2(aim.x - here.x, aim.z - here.z).length() < 4.0 and waypoint < route.size() - 1:
			waypoint += 1
			aim = route[waypoint]
		var to_aim: Vector3 = aim - here
		await _drive(Vector2(to_aim.x, to_aim.z).normalized(), 0.4)
		here = _player.global_position
		var depth: float = _terrain.height_at(here.x, here.z) - here.y
		deepest = maxf(deepest, depth)
		if step % 5 == 4:
			print("  t=%4.1fs  depth=%5.1f m  waypoint %d/%d  on_floor=%s" % [
					(step + 1) * 0.4, depth, waypoint, route.size() - 1, _player.is_on_floor()])
	var final_here: Vector3 = _player.global_position
	var final_depth: float = _terrain.height_at(final_here.x, final_here.z) - final_here.y
	var exit_point: Vector3 = tunnel.to_global(curve.sample_baked(total))
	var from_exit: float = Vector2(final_here.x - exit_point.x, final_here.z - exit_point.z).length()
	print("tunnel test: went %.1f m deep, ended %.1f m below the surface, %.1f m from the far opening"
			% [deepest, final_depth, from_exit])
	print("tunnel test: walked through = ", deepest > 4.0 and absf(final_depth) < 2.5 and from_exit < 25.0)
	_screenshot_and_quit()




## Holds a movement direction for `seconds`, as if the stick were pushed that way.
func _drive(direction: Vector2, seconds: float) -> void:
	var touch: CanvasLayer = _main.get_node("TouchControls")
	touch.move = direction
	var frames := int(seconds * 60.0)
	for i in frames:
		await get_tree().physics_frame
	touch.move = Vector2.ZERO




## Looks straight down at the first hole from above - the quickest way to see whether the
## cut, the funnel and the tunnel mouth line up.
func _hole_view(holes: Array[Vector3]) -> void:
	var centre := Vector3(holes[0].x, _terrain.height_at(holes[0].x, holes[0].y), holes[0].y)
	_player.global_position = centre + Vector3(holes[0].z + 3.0, 3.0, 0.0)
	# a separate camera: the spring arm would keep overwriting a borrowed one
	var camera := Camera3D.new()
	_main.add_child(camera)
	camera.global_position = centre + Vector3(0.0, 38.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.fov = 55.0
	camera.current = true
	for i in 60:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://holeview.png")
	print("hole view saved; hole centre ", centre, " player at ", _player.global_position)
	get_tree().quit()




## Casts rays straight down through the hole and prints what they hit: the quickest way to
## see whether the funnel and tunnel actually provide collision where they are drawn.
func _probe(holes: Array[Vector3]) -> void:
	await get_tree().physics_frame
	var index: int = 1 if "--second" in OS.get_cmdline_user_args() else 0
	var centre := Vector3(holes[index].x, _terrain.height_at(holes[index].x, holes[index].y), holes[index].y)
	if _terrain.tunnels.size() > 0:
		# the opening sits where the curve crosses the surface, not at the planned end point
		var curve: Curve3D = _terrain.tunnels[0].curve
		var at: float = 0.0 if index == 0 else curve.get_baked_length()
		var probe_point: Vector3 = _terrain.tunnels[0].to_global(curve.sample_baked(at))
		centre = Vector3(probe_point.x, _terrain.height_at(probe_point.x, probe_point.z), probe_point.z)
	var space := get_viewport().world_3d.direct_space_state
	print("probe at hole %d, surface y = %.1f" % [index + 1, centre.y])
	# also look for ceilings: an overhang is what stops a player climbing out
	# probe outward from the mouth along the tunnel direction, where the exit gap would be
	var outward := Vector3.RIGHT
	if _terrain.tunnels.size() > 0:
		var c: Curve3D = _terrain.tunnels[0].curve
		var total2: float = c.get_baked_length()
		var tip: Vector3 = _terrain.tunnels[0].to_global(c.sample_baked(total2))
		var inner: Vector3 = _terrain.tunnels[0].to_global(c.sample_baked(total2 - 8.0))
		outward = (tip - inner)
		outward.y = 0.0
		outward = outward.normalized()
		if index == 0:
			outward = -outward
	for offset in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0, 12.0]:
		var below: Vector3 = centre + outward * offset + Vector3(0.0, -7.0, 0.0)
		var up_query := PhysicsRayQueryParameters3D.create(below, below + Vector3.UP * 12.0)
		var up_hit := space.intersect_ray(up_query)
		if not up_hit.is_empty():
			print("  r=%4.1f m: CEILING at %.1f m below the surface" % [
					offset, centre.y - up_hit["position"].y])
		var from: Vector3 = centre + outward * offset + Vector3(0.0, 12.0, 0.0)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 80.0)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			print("  r=%4.1f m: nothing (falls through)" % offset)
		else:
			var node: Node = hit["collider"]
			print("  r=%4.1f m: hit %-12s at y=%.1f (%.1f m below surface)" % [
					offset, node.get_parent().name + "/" + node.name, hit["position"].y,
					centre.y - hit["position"].y])
	get_tree().quit()




## Walks along the tunnel centreline and checks there is floor under every step.
func _probe_path() -> void:
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	for tunnel in _terrain.tunnels:
		print("tunnel path:")
		var curve: Curve3D = tunnel.curve
		var total: float = curve.get_baked_length()
		var walked := 0.0
		while walked <= total:
			var i := 0
			var direction := Vector3.ZERO
			var length := 0.0
			var travelled := 0.0
			var point: Vector3 = tunnel.to_global(curve.sample_baked(walked))
			walked += 4.0
			if true:
				var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5,
						point + Vector3.DOWN * 8.0)
				var hit := space.intersect_ray(query)
				var floor_text := "NO FLOOR" if hit.is_empty() else "floor %.1f m below" % (point.y - hit["position"].y)
				print("  +%6.1f m along  y=%7.1f  %s" % [walked - 4.0, point.y, floor_text])
	get_tree().quit()




func _asset_view() -> void:
	var study: Node3D = _main.get_node_or_null("CoastalStudy")
	if study == null or not study.valid:
		push_error("--assetview requires a valid coastal study (no tunnels or --noassets).")
		get_tree().quit(1)
		return
	_main.get_node("HUD").hide()
	_main.get_node("TouchControls").hide()
	# Put the scale figure in the shallows so the generic scene-depth waterline can be
	# judged beside the captured static-rock silhouettes.
	var water_rock := study.get_node_or_null("WaterRock2") as Node3D
	if water_rock != null:
		var seaward: Vector3 = -study.global_basis.z
		var water_position := water_rock.global_position + seaward * 3.2
		_player.set_physics_process(false)
		_player.global_position = Vector3(water_position.x,
			_terrain.sea_level() - _player.swim_depth, water_position.z)
	study.show_camera()
	if DisplayServer.get_name() == "headless":
		push_error("--assetview cannot capture with the headless display driver.")
		get_tree().quit(1)
		return
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png("user://coastal_study.png")
	if error != OK:
		push_error("Asset study screenshot failed: %s" % error_string(error))
		get_tree().quit(1)
		return
	print("asset study screenshot: ", ProjectSettings.globalize_path("user://coastal_study.png"))
	get_tree().quit()
