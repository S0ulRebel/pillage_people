extends Node3D
## Drops the player onto the generated terrain, wires the camera to it, and shows the controls.
##
## Run with --screenshot to save a picture after a few frames and quit (used to check the
## project renders without opening the editor).

@onready var _terrain: StaticBody3D = $Terrain
@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: Node3D = $CameraRig


func _ready() -> void:
	# start the player on the ground near the middle, plus a little clearance
	var spawn: Vector3 = _terrain.find_spawn()
	_player.global_position = spawn + Vector3.UP * 2.0
	_player.camera_rig = _camera_rig
	_camera_rig.set_target(_player)
	var touch: CanvasLayer = $TouchControls
	_player.touch_controls = touch
	_camera_rig.touch_controls = touch
	touch.jumped.connect(_player.request_jump)
	touch.released.connect(_player.release_jump)
	if "--jumptest" in OS.get_cmdline_user_args():
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
