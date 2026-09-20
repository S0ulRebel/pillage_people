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
	if "--screenshot" in OS.get_cmdline_user_args():
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
