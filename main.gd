extends Node3D
## Drops the player onto the generated terrain, wires the camera to it, and shows the controls.
##
## Run with --screenshot to save a picture after a few frames and quit (used to check the
## project renders without opening the editor).

@onready var _terrain: StaticBody3D = $Terrain
@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: Node3D = $CameraRig


func _ready() -> void:
	seed(20260920)   # same terrain, same holes every run - makes problems reproducible
	# start the player on the ground near the middle, plus a little clearance
	var spawn: Vector3 = _terrain.find_spawn()
	# two holes near the spawn, joined underground by a walkable tunnel
	var holes: Array[Vector3] = _terrain.plan_holes(spawn, 2)
	# only cut holes that a tunnel will actually connect - an unpaired hole is a bottomless pit
	if holes.size() % 2 == 1:
		holes.remove_at(holes.size() - 1)
	_terrain.holes = holes
	_terrain.generate()
	$Tunnels.build(_terrain, holes)
	_player.global_position = spawn + Vector3.UP * 2.0
	print("holes at ", holes)
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


## Walks the player into the first hole and on towards the second, reporting whether they
## actually end up underground and standing on the tunnel floor.
func _tunnel_test(holes: Array[Vector3]) -> void:
	if holes.size() < 2:
		print("tunnel test: no holes")
		get_tree().quit()
		return
	var entry := Vector3(holes[0].x, 0.0, holes[0].y)
	var target := Vector3(holes[1].x, 0.0, holes[1].y)
	# start on the crater's near rim: starting further out can put a cliff in the way, which
	# says nothing about whether the tunnel works
	var start_side := (entry - target).normalized() * (holes[0].z * 0.9)
	_player.global_position = entry + start_side + Vector3.UP * (_terrain.height_at(entry.x + start_side.x, entry.z + start_side.z) + 2.0)
	_camera_rig.set_target(_player)
	# stick input is camera-relative; facing the camera north makes x/z map straight through
	_camera_rig.rotation.y = 0.0
	await get_tree().physics_frame

	var surface: float = _terrain.height_at(entry.x, entry.z)
	print("tunnel test: surface at hole 1 = %.1f m" % surface)
	var deepest: float = _player.global_position.y
	# waypoints: down into crater 1, into the tunnel mouth, along it, then out at crater 2
	var route: Array[Vector3] = []
	if $Tunnels.paths.size() > 0:
		var tunnel: Array = $Tunnels.paths[0]
		route = [tunnel[1], tunnel[2], tunnel[tunnel.size() - 3], target]
	else:
		route = [target]
	# phase 1: head for the far hole; phase 2: keep going past it, out onto the surface
	# climb out sideways: straight along the tunnel axis the tube's own roof forms a lip
	var sideways: Vector3 = (target - entry).normalized().cross(Vector3.UP).normalized()
	var beyond: Vector3 = target + sideways * 20.0
	var reached_far_hole := false
	var waypoint := 0
	for step in 40:
		var aim: Vector3 = beyond
		if not reached_far_hole:
			aim = route[waypoint]
			if Vector2(aim.x - _player.global_position.x, aim.z - _player.global_position.z).length() < 5.0 					and waypoint < route.size() - 1:
				waypoint += 1
		var to_aim: Vector3 = aim - _player.global_position
		await _drive(Vector2(to_aim.x, to_aim.z).normalized(), 0.5)
		var here: Vector3 = _player.global_position
		deepest = minf(deepest, here.y)
		var from_far: float = Vector2(here.x - target.x, here.z - target.z).length()
		if not reached_far_hole and from_far < 6.0:
			reached_far_hole = true
			print("  reached hole 2 at t=%.1fs, %.1f m below the surface" % [
					(step + 1) * 0.5, _terrain.height_at(here.x, here.z) - here.y])
		if step % 2 == 1:
			print("  t=%.1fs  y=%.1f  depth=%.1f  %.1f m from hole 1, %.1f m from hole 2  speed=%.1f  aim=%s" % [
					(step + 1) * 0.5, here.y, _terrain.height_at(here.x, here.z) - here.y,
					Vector2(here.x - entry.x, here.z - entry.z).length(), from_far,
					Vector2(_player.velocity.x, _player.velocity.z).length(),
					"hole2" if not reached_far_hole else "beyond"])
	# what is in front of the player, if anything
	var space := get_viewport().world_3d.direct_space_state
	var eye: Vector3 = _player.global_position + Vector3.UP * 1.0
	var aim_dir: Vector3 = (beyond if reached_far_hole else target) - _player.global_position
	aim_dir.y = 0.0
	var forward_query := PhysicsRayQueryParameters3D.create(eye, eye + aim_dir.normalized() * 6.0)
	forward_query.exclude = [_player.get_rid()]
	var blocker := space.intersect_ray(forward_query)
	if blocker.is_empty():
		print("  nothing blocking within 6 m ahead")
	else:
		var node: Node = blocker["collider"]
		print("  blocked by %s at %.2f m ahead, normal %s" % [
				node.get_parent().name + "/" + node.name,
				eye.distance_to(blocker["position"]), blocker["normal"]])
	var final_depth: float = _terrain.height_at(_player.global_position.x, _player.global_position.z) - _player.global_position.y
	print("tunnel test: deepest %.1f m below the surface; ended %.1f m below surface, standing: %s" % [
			surface - deepest, final_depth, _player.is_on_floor()])
	print("tunnel test: walked out = ", absf(final_depth) < 2.0 and _player.is_on_floor())
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
	var space := get_viewport().world_3d.direct_space_state
	print("probe at hole %d, surface y = %.1f" % [index + 1, centre.y])
	# also look for ceilings: an overhang is what stops a player climbing out
	for offset in [8.0, 10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 25.0]:
		var below := centre + Vector3(offset, -7.0, 0.0)
		var up_query := PhysicsRayQueryParameters3D.create(below, below + Vector3.UP * 12.0)
		var up_hit := space.intersect_ray(up_query)
		if not up_hit.is_empty():
			print("  r=%4.1f m: CEILING at %.1f m below the surface" % [
					offset, centre.y - up_hit["position"].y])
		var from := centre + Vector3(offset, 12.0, 0.0)
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
	for path: Array in $Tunnels.paths:
		print("tunnel path:")
		for i in range(path.size() - 1):
			var length: float = (path[i + 1] - path[i]).length()
			var direction: Vector3 = (path[i + 1] - path[i]).normalized()
			var travelled := 0.0
			while travelled < length:
				var point: Vector3 = path[i] + direction * travelled
				var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5,
						point + Vector3.DOWN * 8.0)
				var hit := space.intersect_ray(query)
				var floor_text := "NO FLOOR" if hit.is_empty() else "floor %.1f m below" % (point.y - hit["position"].y)
				print("  seg %d  +%5.1f m  y=%7.1f  %s" % [i, travelled, point.y, floor_text])
				travelled += 4.0
	get_tree().quit()
