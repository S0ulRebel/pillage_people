extends Node3D
## Drops the player onto the generated terrain, wires the camera to it, and shows the controls.
##
## Run with --screenshot to save a picture after a few frames and quit (used to check the
## project renders without opening the editor).

@onready var _terrain: StaticBody3D = $Terrain
@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: Node3D = $CameraRig


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
	# one tunnel near the spawn: a curve dropping underground and coming back up. The terrain
	# is then cut to whatever shape the tube makes where it breaks the surface.
	var ends: Array[Vector3] = _terrain.plan_tunnel_ends(spawn)
	var holes: Array[Vector3] = []
	if ends.size() == 2:
		var tunnel := _make_tunnel(ends[0], ends[1])
		_terrain.tunnels = [tunnel]
		holes = [Vector3(ends[0].x, ends[0].z, tunnel.radius),
				Vector3(ends[1].x, ends[1].z, tunnel.radius)]
	_terrain.generate()
	_player.global_position = spawn + Vector3.UP * 2.0
	print("tunnel between ", ends)
	_player.camera_rig = _camera_rig
	_camera_rig.set_target(_player)
	var touch: CanvasLayer = $TouchControls
	_player.touch_controls = touch
	_camera_rig.touch_controls = touch
	touch.jumped.connect(_player.request_jump)
	touch.released.connect(_player.release_jump)
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
	elif "--touchtest" in OS.get_cmdline_user_args():
		_touch_self_test()
	elif "--screenshot" in OS.get_cmdline_user_args():
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
	# Each end keeps climbing along its ramp until it is clear of the ground, so the tunnel
	# always breaks the surface somewhere and has a mouth you can walk into.
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


## Walks out along `direction` from `from` until the point is clear of the terrain, and then
## a little further, so the tube ends above ground rather than buried in a hillside.
func _surface_exit(from: Vector3, direction: Vector3, clearance: float) -> Vector3:
	var travelled := 0.0
	while travelled < 120.0:
		var point: Vector3 = from + direction * travelled
		if point.y > _terrain.height_at(point.x, point.z) + clearance:
			return point + direction * 4.0
		travelled += 2.0
	return from + direction * 40.0


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
