extends Node3D
## Bird's-eye chase camera: sits high behind the player, follows smoothly, and never clips into
## the terrain (SpringArm3D does that part).
##
## Orbits with Q/E or by holding the middle mouse button and moving sideways; tilts with the
## same middle-button drag up and down; zooms on the wheel.
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

@export_group("Spyglass")
## Held to the captain's eye. The camera goes to his head and the field of view narrows; the
## wheel then magnifies instead of pulling the camera back.
##
## FOV rather than the spring arm, which is what the wheel normally drives. Shortening the arm
## moves the camera CLOSER - it clips through terrain and magnifies nothing. Narrowing the
## angle is what a telescope does, and it costs nothing.
@export var glass_fov := 22.0
@export var glass_zoom_min := 1.0
@export var glass_zoom_max := 5.0
@export var glass_zoom_step := 0.5
## Where his eye is, above the node origin at his feet.
@export var eye_height := 1.6
## How wide the iris sits while glassing. Not shut, or there is nothing to look through.
@export var glass_iris := 0.62
@export var glass_seconds := 0.35
## Tilt limits while glassing. The chase camera cannot go above -12 degrees, which is fine
## looking down at the captain and useless for looking at a horizon - the whole point of the
## glass is the things level with you and slightly above.
@export var glass_min_pitch := -70.0
@export var glass_max_pitch := 25.0
## Flips the mouse tilt while the glass is up, and it is on by default because the two modes
## mean genuinely different things by the same movement.
##
## The chase camera ORBITS him: drag up and it swings up and over, so you end up looking down
## at him. That is what orbiting a subject should do. The glass is first person - you are not
## moving a camera around something, you are turning your head - and there drag up has to look
## up. Same code, opposite convention, which is why it reads as reversed rather than as wrong.
@export var glass_invert_pitch := true

@export_group("Mouse look")
## Hold the middle button and move to swing the camera round and tilt it. The left button is
## deliberately left alone - it belongs to whatever the player is doing in the world. It used
## to orbit the camera, but only by accident: the project had emulate_touch_from_mouse on, so
## every left-drag arrived at the iPad controls as a finger dragging across the screen.
@export var mouse_orbit_speed := 0.006   ## radians per pixel of horizontal movement
@export var mouse_pitch_speed := 0.12    ## degrees per pixel of vertical movement
## Drag up to look down on the player, drag down to look along the ground - the same way round
## as the touch controls. Turn this on to swap it.
@export var invert_mouse_pitch := false

@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D
var _target: Node3D
## The iris drawn while glassing. Separate from the one main.gd uses for openings and deaths:
## that one is opaque and covers everything, this one has to be looked through.
var glass: Spyglass
var _glassing := false
var _magnification := 1.0
var _wide_fov := 75.0
var _rested_length := 18.0
## Set by main.gd on touch devices.
var touch_controls: CanvasLayer
## True while the middle button is held.
var _mouse_looking := false


func _ready() -> void:
	_apply_pitch()
	_arm.spring_length = 18.0
	_arm.margin = 0.4
	if _camera != null:
		_wide_fov = _camera.fov


## Raises or lowers the glass. Returns what it did, so a caller can tell whether anything
## happened without tracking the state itself.
func set_glassing(looking: bool) -> bool:
	if _glassing == looking or _target == null:
		return false
	_glassing = looking
	if looking:
		_rested_length = _arm.spring_length
		_magnification = 1.0
		# Arm to nothing puts the camera on the pivot, and the pivot goes to his head - so the
		# view is from his eye rather than from eighteen metres behind him. Anything else and
		# the iris is drawn over a shot of the back of his own head.
		_arm.spring_length = 0.0
	else:
		_arm.spring_length = _rested_length
	_apply_fov()
	if glass != null:
		if looking:
			glass.to(glass_iris, glass_seconds)
		else:
			# clear(), not close(). Closing takes it to fully black - which is right for a
			# transition and blacks the screen out for a captain simply lowering his glass.
			glass.clear(glass_seconds * 0.6)
	return true


func is_glassing() -> bool:
	return _glassing


func _apply_fov() -> void:
	if _camera == null:
		return
	_camera.fov = (glass_fov / _magnification) if _glassing else _wide_fov


## Keeps the tilt inside a range where the camera neither looks up from under the ground nor
## straight down onto the top of the player's head.
func _apply_pitch() -> void:
	var lowest := glass_min_pitch if _glassing else min_pitch_degrees
	var highest := glass_max_pitch if _glassing else max_pitch_degrees
	pitch_degrees = clampf(pitch_degrees, lowest, highest)
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
	if event.is_action_pressed("spyglass"):
		set_glassing(not _glassing)
		# Coming down from a steep look, the chase camera's own limits apply again and the
		# pitch has to be pulled back inside them or the view stays where the glass left it.
		_apply_pitch()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_set_mouse_looking(event.pressed)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _glassing:
				_magnify(glass_zoom_step)
			else:
				_arm.spring_length = maxf(min_distance, _arm.spring_length - zoom_step)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _glassing:
				_magnify(-glass_zoom_step)
			else:
				_arm.spring_length = minf(max_distance, _arm.spring_length + zoom_step)
	elif event is InputEventMouseMotion and _mouse_looking:
		# screen_relative, not relative. The project stretches canvas items to a 1920x1080 base,
		# and relative arrives already scaled into that space - so the same physical mouse
		# movement turned the camera a different amount depending on the window size, and by
		# different amounts horizontally and vertically once the aspect stopped matching.
		# screen_relative is in real screen pixels and does not move when the window does.
		var motion: Vector2 = event.screen_relative
		# Divided by the magnification. At 4x the same hand movement sweeps four times the
		# view, and a glass that whips past what you are aiming at is unusable - this is the
		# single thing most scoped views get wrong.
		var steady := _look_scale()
		rotation.y -= motion.x * mouse_orbit_speed * steady
		pitch_degrees += motion.y * mouse_pitch_speed * steady * _pitch_sign()
		_apply_pitch()


## Capturing the pointer while the button is held means a long swing keeps going instead of
## stopping when the cursor reaches the edge of the window, and the pointer comes back where
## it was left. Releasing always restores it - including when the window loses focus, because
## a middle-button release that lands on another window never arrives here and would otherwise
## leave the pointer captured with no way to get it back.
func _set_mouse_looking(looking: bool) -> void:
	if _mouse_looking == looking:
		return
	_mouse_looking = looking
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_set_mouse_looking(false)


func _physics_process(delta: float) -> void:
	if _target == null:
		return
	# Horizontal lag only. Copying Y keeps the cast origin on the ground he is standing
	# on; a trailed height puts that origin inside the beach and the arm pulls the
	# camera under it. The spring arm casts on this same physics step.
	var weight := 1.0 - exp(-follow_speed * delta)
	var followed := global_position.lerp(_target.global_position, weight)
	followed.y = _target.global_position.y
	# No lag at the eye. A pivot trailing a metre behind is unnoticeable from eighteen metres
	# back and is the whole picture swimming when the camera IS the pivot.
	if _glassing:
		followed = _target.global_position
		followed.y += eye_height
	global_position = followed


## Which way the mouse tilts the view. See glass_invert_pitch.
func _pitch_sign() -> float:
	var sign_ := -1.0 if invert_mouse_pitch else 1.0
	if _glassing and glass_invert_pitch:
		sign_ = -sign_
	return sign_


## How much to slow the look by, so turning feels the same whatever the glass is doing.
func _look_scale() -> float:
	return 1.0 / _magnification if _glassing else 1.0


func _magnify(by: float) -> void:
	_magnification = clampf(_magnification + by, glass_zoom_min, glass_zoom_max)
	_apply_fov()


func _process(delta: float) -> void:
	var steady := _look_scale()
	var orbit := Input.get_axis("cam_left", "cam_right")
	if absf(orbit) > 0.01:
		rotation.y -= orbit * orbit_speed * delta * steady
	var tilt := Input.get_axis("cam_down", "cam_up")
	if absf(tilt) > 0.01:
		pitch_degrees += tilt * pitch_speed * delta * steady
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
