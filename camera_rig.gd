extends Node3D
## Bird's-eye chase camera: sits high behind the player, follows smoothly, orbits with Q/E,
## zooms with the mouse wheel, and never clips into the terrain (SpringArm3D does that part).
##
## The spring arm casts from this pivot back toward the camera on the physics step. Following
## in _process let the pivot lag a metre behind, so walking back toward the camera stepped
## the captain into that cast. The arm treated him as a wall, collapsed, and the view dropped
## onto the beach with him behind it.

@export var follow_speed := 8.0
@export var orbit_speed := 2.0
@export var zoom_step := 2.0
@export var min_distance := 6.0
@export var max_distance := 40.0
@export var pitch_degrees := -55.0   ## -90 is straight down, -15 is nearly level
@export var min_pitch_degrees := -85.0
@export var max_pitch_degrees := -12.0
@export var pitch_speed := 60.0      ## degrees per second on the keyboard

@onready var _arm: SpringArm3D = $SpringArm3D
var _target: Node3D
## Set by main.gd on touch devices.
var touch_controls: CanvasLayer


func _ready() -> void:
	_apply_pitch()
	_arm.spring_length = 18.0
	_arm.margin = 0.4


## Keeps the tilt inside a range where the camera neither looks up from under the ground nor
## straight down onto the top of the player's head.
func _apply_pitch() -> void:
	pitch_degrees = clampf(pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	_arm.rotation_degrees.x = pitch_degrees


func set_target(target: Node3D) -> void:
	_target = target
	if target == null:
		return
	global_position = target.global_position
	# The cast starts just above his head. Without this exclusion, backing into the camera
	# makes the arm hit his capsule and shorten to nothing.
	if target is CollisionObject3D:
		_arm.clear_excluded_objects()
		_arm.add_excluded_object(target.get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_arm.spring_length = maxf(min_distance, _arm.spring_length - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_arm.spring_length = minf(max_distance, _arm.spring_length + zoom_step)


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# Horizontal lag only. Copying Y keeps the cast origin on the ground he is standing
	# on; a trailed height puts that origin inside the beach and the arm pulls the
	# camera under it. The spring arm casts on this same physics step.
	var weight := 1.0 - exp(-follow_speed * delta)
	var followed := global_position.lerp(_target.global_position, weight)
	followed.y = _target.global_position.y
	global_position = followed


func _process(delta: float) -> void:
	var orbit := Input.get_axis("cam_left", "cam_right")
	if absf(orbit) > 0.01:
		rotation.y -= orbit * orbit_speed * delta
	var tilt := Input.get_axis("cam_down", "cam_up")
	if absf(tilt) > 0.01:
		pitch_degrees += tilt * pitch_speed * delta
		_apply_pitch()
	if touch_controls:
		var gesture: Dictionary = touch_controls.take_camera_input()
		rotation.y -= gesture["orbit"]
		if absf(gesture["pitch"]) > 0.0:
			pitch_degrees += gesture["pitch"]
			_apply_pitch()
		if absf(gesture["zoom"]) > 0.0:
			_arm.spring_length = clampf(_arm.spring_length + gesture["zoom"],
					min_distance, max_distance)
