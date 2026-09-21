extends Node3D
## Drops the player onto the generated terrain, wires the camera to it, and shows the controls.
##
## Run with --screenshot to save a picture after a few frames and quit (used to check the
## project renders without opening the editor).

const CoastalStudy = preload("res://art/procedural/coastal_study.gd")
var _coastal_study: Node3D

@onready var _terrain: StaticBody3D = $Terrain
@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: Node3D = $CameraRig
@onready var _ocean: MeshInstance3D = $Ocean


func _ready() -> void:
	# same layout every run unless --seed N is passed: reproducible problems, but easy to
	# check that the tunnel generator copes with more than one arrangement
	var chosen_seed := 20260920
	for i in OS.get_cmdline_user_args().size():
		if OS.get_cmdline_user_args()[i] == "--seed" and i + 1 < OS.get_cmdline_user_args().size():
			chosen_seed = int(OS.get_cmdline_user_args()[i + 1])
	seed(chosen_seed)
	# start the player on the ground near the middle, plus a little clearance
	var spawn: Vector3 = _terrain.find_spawn()
	# Tunnels placed in the scene win; the generated one is only a fallback so the demo is
	# never empty. Add a Tunnel node, draw its curve, and it is picked up here.
	var authored: Array = []
	if "--noscene" not in OS.get_cmdline_user_args():   # --noscene: generate one instead
		for child in get_children():
			if child is Tunnel:
				authored.append(child)
	var holes: Array[Vector3] = []
	if not authored.is_empty():
		for tunnel in authored:
			tunnel.build(_terrain)
		_terrain.tunnels = authored
		print("using %d tunnel(s) from the scene" % authored.size())
	elif "--tunnel" in OS.get_cmdline_user_args():
		# Only on request now: the island slice is about terrain and water, and a generated
		# tunnel punches a hole through the shoreline that reads as a bug.
		var ends: Array[Vector3] = _terrain.plan_tunnel_ends(spawn)
		if ends.size() == 2:
			var tunnel := _make_tunnel(ends[0], ends[1])
			_terrain.tunnels = [tunnel]
			holes = [Vector3(ends[0].x, ends[0].z, tunnel.radius),
					Vector3(ends[1].x, ends[1].z, tunnel.radius)]
	_terrain.generate()
	# Tunnel scenes and tunnel test arguments retain their original layout and spawn.
	var tunnel_mode := false
	for argument in OS.get_cmdline_user_args():
		if argument in ["--tunnel", "--tunneltest", "--probepath", "--probe", "--holeview", "--holeshot", "--printcurve", "--second"]:
			tunnel_mode = true
	if authored.is_empty() and _terrain.tunnels.is_empty() and not tunnel_mode and "--noassets" not in OS.get_cmdline_user_args():
		_coastal_study = CoastalStudy.new()
		_coastal_study.name = "CoastalStudy"
		add_child(_coastal_study)
		if _coastal_study.setup(_terrain):
			spawn = _coastal_study.spawn
			var towards: Vector3 = _coastal_study.global_position - spawn
			_camera_rig.rotation.y = atan2(-towards.x, -towards.z)
	# Start next to the tunnel mouth, looking at it: the tunnel used to be tens of metres away
	# with nothing pointing at it, so it was easy to miss entirely.
	if _terrain.tunnels.size() > 0:
		var tunnel = _terrain.tunnels[0]
		var mouth: Vector3 = tunnel.to_global(tunnel.curve.sample_baked(0.0))
		var inward: Vector3 = tunnel.to_global(tunnel.curve.sample_baked(10.0)) - mouth
		inward.y = 0.0
		inward = inward.normalized()
		var stand: Vector3 = mouth - inward * 11.0
		spawn = Vector3(stand.x, _terrain.height_at(stand.x, stand.z), stand.z)
		_camera_rig.rotation.y = atan2(-inward.x, -inward.z)   # face the entrance
		if "--printcurve" in OS.get_cmdline_user_args():
			var printed := PackedStringArray()
			for i in tunnel.curve.point_count:
				printed.append(str(tunnel.curve.get_point_position(i)))
			print("curve points: ", ", ".join(printed))
	_player.global_position = spawn + Vector3.UP * 2.0
	_ocean.setup(_terrain.sea_level(), _terrain)
	_player.water_level = _terrain.sea_level()
	_player.camera_rig = _camera_rig
	_camera_rig.set_target(_player)
	var touch: CanvasLayer = $TouchControls
	_player.touch_controls = touch
	_camera_rig.touch_controls = touch
	touch.jumped.connect(_player.request_jump)
	touch.released.connect(_player.release_jump)
	touch.dive_changed.connect(_player.set_diving)
	if "--probepath" in OS.get_cmdline_user_args():
		_probe_path()
	elif "--probe" in OS.get_cmdline_user_args():
		_probe(holes)
	elif "--holeview" in OS.get_cmdline_user_args():
		_hole_view(holes)
	elif "--tunneltest" in OS.get_cmdline_user_args():
		_tunnel_test(holes)
	elif "--holeshot" in OS.get_cmdline_user_args():
		_player.global_position = Vector3(holes[0].x, 0, holes[0].y) 				+ Vector3(9, 0, 9) + Vector3.UP * (_terrain.height_at(holes[0].x + 9, holes[0].y + 9) + 2.0)
		_camera_rig.set_target(_player)
		_screenshot_and_quit()
	elif "--jumptest" in OS.get_cmdline_user_args():
		_jump_test()
	elif "--swimtest" in OS.get_cmdline_user_args():
		_swim_test()
	elif "--touchtest" in OS.get_cmdline_user_args():
		_touch_self_test()
	elif "--shore" in OS.get_cmdline_user_args():
		_shore_view()
	elif "--overview" in OS.get_cmdline_user_args():
		_overview()
	elif "--assetview" in OS.get_cmdline_user_args():
		_asset_view()
	elif "--screenshot" in OS.get_cmdline_user_args():
		_screenshot_and_quit()


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
	add_child(camera)
	camera.fov = 60.0
	camera.far = 6000.0
	camera.global_position = best + outward * 34.0 + Vector3.UP * (sea + 9.0 - best.y)
	camera.look_at(best - outward * 30.0 + Vector3.UP * 6.0, Vector3.UP)
	camera.current = true
	print("shore at ", best, " (error %.2f m)" % best_error)
	_screenshot_and_quit()


## A high, wide shot of the whole island and the sea around it - the view that shows whether
## the shoreline, the scale and the water read correctly, which a ground-level shot cannot.
func _overview() -> void:
	# Its own camera rather than the rigged one: the SpringArm keeps writing to that camera's
	# transform every frame, so moving it has no lasting effect.
	var camera := Camera3D.new()
	add_child(camera)
	camera.fov = 55.0
	camera.far = 6000.0
	camera.global_position = Vector3(0.0, _terrain.height_scale * 3.2, _terrain.world_size * 1.15)
	camera.look_at(Vector3(0.0, _terrain.height_scale * 0.2, 0.0), Vector3.UP)
	camera.current = true
	_screenshot_and_quit()


## Builds a Tunnel node whose curve runs from above ground at `a`, down at `entry_slope`,
## along at depth, and back up to `b`. Everything else (tube, collision, the hole in the
## terrain) follows from the curve and the radius.
func _make_tunnel(a: Vector3, b: Vector3, tunnel_radius := 3.0, depth := 9.0,
		entry_slope_degrees := 25.0) -> Tunnel:
	var tunnel := Tunnel.new()
	tunnel.name = "Tunnel"
	tunnel.radius = tunnel_radius
	var towards := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var run: float = depth / tan(deg_to_rad(entry_slope_degrees))
	var floor_y: float = minf(a.y, b.y) - depth
	var ramp_bottom_a := Vector3(a.x, floor_y, a.z) + towards * (run * 0.65)
	var ramp_bottom_b := Vector3(b.x, floor_y, b.z) - towards * (run * 0.65)
	# Start just above the chosen spot and dive: the tube is trimmed where it crosses the
	# surface, so that crossing becomes the mouth. No need to hunt for daylight.
	var points: Array[Vector3] = [
		Vector3(a.x, a.y + tunnel_radius * 0.8, a.z),
		ramp_bottom_a,
		ramp_bottom_b,
		Vector3(b.x, b.y + tunnel_radius * 0.8, b.z),
	]
	var curve := Curve3D.new()
	for i in points.size():
		# smooth handles: the ramps blend into the level run instead of kinking
		var handle := Vector3.ZERO
		if i > 0 and i < points.size() - 1:
			handle = (points[i + 1] - points[i - 1]).normalized() * 7.0
		curve.add_point(points[i], -handle, handle)
	tunnel.curve = curve
	add_child(tunnel)
	tunnel.build(_terrain)
	return tunnel


func _screenshot_and_quit() -> void:
	# let physics settle first: if the player falls through the terrain, the picture shows it
	for i in 90:
		await get_tree().process_frame
	print("player settled at ", _player.global_position, " ground ",
			_terrain.height_at(_player.global_position.x, _player.global_position.z),
			" on_floor=", _player.is_on_floor())
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
	var touch: CanvasLayer = $TouchControls
	var sea: float = _terrain.sea_level()
	await get_tree().process_frame

	# Drop into open water well off the beach, where the seabed is clear below.
	var deep := Vector3(0.0, sea - 3.0, _terrain.world_size * 0.42)
	_player.global_position = deep
	_player.velocity = Vector3.ZERO
	for i in 6:
		await get_tree().physics_frame
	print("in water: swimming=%s dive button visible=%s" % [_player.is_swimming(), touch.get_node("DiveButton").visible])

	var before: float = _player.global_position.y
	_player.set_diving(true)
	for i in 30:
		await get_tree().physics_frame
	var after_dive: float = _player.global_position.y
	print("dive:    %.2f -> %.2f m (%.2f)" % [before, after_dive, after_dive - before])

	_player.set_diving(false)
	_player.request_jump()
	for i in 30:
		await get_tree().physics_frame
	var after_rise: float = _player.global_position.y
	print("swim up: %.2f -> %.2f m (%.2f)" % [after_dive, after_rise, after_rise - after_dive])

	_player.release_jump()
	for i in 90:
		await get_tree().physics_frame
	print("float:   settled at %.2f m, sea level %.2f m" % [_player.global_position.y, sea])

	# Back on land the button has to go away, and dive must not stay latched on.
	_player.global_position = _terrain.find_spawn() + Vector3.UP * 2.0
	for i in 6:
		await get_tree().physics_frame
	print("on land: swimming=%s dive button visible=%s" % [_player.is_swimming(), touch.get_node("DiveButton").visible])
	get_tree().quit()


func _touch_self_test() -> void:
	var touch: CanvasLayer = $TouchControls
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

	# and R / F on the keyboard
	before_pitch = camera_rig.pitch_degrees
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	Input.parse_input_event(key)
	for i in 20:
		await get_tree().process_frame
	var released := InputEventKey.new()
	released.keycode = KEY_R
	released.pressed = false
	Input.parse_input_event(released)
	print("tilt (R key): pitch %.1f -> %.1f degrees" % [before_pitch, camera_rig.pitch_degrees])

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
	var touch: CanvasLayer = $TouchControls
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
	add_child(camera)
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
	if _coastal_study == null or not _coastal_study.valid:
		push_error("--assetview requires a valid coastal study (no tunnels or --noassets).")
		get_tree().quit(1)
		return
	$HUD.hide()
	$TouchControls.hide()
	_coastal_study.show_camera()
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
