extends Node3D
## Bird's-eye chase camera: sits high behind the player, follows smoothly, orbits with Q/E,
## zooms with the mouse wheel, and never clips into the terrain (SpringArm3D does that part).

@export var follow_speed := 8.0
@export var orbit_speed := 2.0
@export var zoom_step := 2.0
@export var min_distance := 6.0
@export var max_distance := 40.0
@export var pitch_degrees := -55.0   ## -90 is straight down, -30 is over-the-shoulder

@onready var _arm: SpringArm3D = $SpringArm3D
var _target: Node3D


func _ready() -> void:
	_arm.rotation_degrees.x = pitch_degrees
	_arm.spring_length = 18.0
	_arm.margin = 0.4


func set_target(target: Node3D) -> void:
	_target = target
	if target:
		global_position = target.global_position


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_arm.spring_length = maxf(min_distance, _arm.spring_length - zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_arm.spring_length = minf(max_distance, _arm.spring_length + zoom_step)


func _process(delta: float) -> void:
	if _target:
		global_position = global_position.lerp(_target.global_position, follow_speed * delta)
	var orbit := Input.get_axis("cam_left", "cam_right")
	if absf(orbit) > 0.01:
		rotation.y -= orbit * orbit_speed * delta
