extends CanvasLayer
## Touch controls for iPad: a virtual stick on the left, a jump button on the right,
## drag anywhere on the right half to orbit the camera, pinch with two fingers to zoom.
##
## Everything is drawn in code, so there are no image assets to import. On a desktop the
## controls hide themselves unless the project is run with "--touch".

signal jumped
signal released
signal dive_changed(pressed: bool)

const STICK_RADIUS := 110.0
const DEAD_ZONE := 0.12

## -1..1 on both axes, same shape as Input.get_vector()
var move := Vector2.ZERO
## radians to orbit this frame, consumed by the camera rig
var orbit_delta := 0.0
## degrees to tilt this frame: drag up to look up, down to look along the ground
var pitch_delta := 0.0
## +1 zoom out / -1 zoom in, consumed by the camera rig
var zoom_delta := 0.0

var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_position := Vector2.ZERO
var _look_touch := -1
var _look_last := Vector2.ZERO
var _pinch := {}          ## touch index -> position, for two-finger zoom
var _pinch_distance := 0.0

@onready var _stick_layer: Control = $StickLayer
@onready var _jump_button: TouchScreenButton = $JumpButton
@onready var _dive_button: TouchScreenButton = $DiveButton


func _ready() -> void:
	# Only a real mobile build gets these, plus a desktop run that asks for them by name.
	#
	# DisplayServer.is_touchscreen_available() used to be part of this check and had to go. It
	# does not report whether a touchscreen exists: on desktop it reports whether Godot is
	# emulating touch from the mouse, which this project had switched on in its settings. So it
	# came back true on a PC with no touchscreen, the stick and the drag region appeared over
	# the screen, and every mouse movement was delivered to them as a finger - which meant
	# playing on the keyboard fought a virtual stick that should never have been there.
	var args := OS.get_cmdline_user_args()
	var testing := "--touch" in args or "--touchtest" in args
	if not OS.has_feature("mobile") and not testing:
		hide()
		set_process_input(false)
		return
	if testing:
		# Desktop testing only. The mouse produces no touch events by itself, so without this
		# the stick cannot be dragged. It is deliberately set here rather than in the project
		# settings, where it applied to every run - including ordinary keyboard ones.
		Input.set_emulate_touch_from_mouse(true)
	_stick_layer.draw.connect(_draw_stick)
	_build_jump_button()
	_place_jump_button()
	get_viewport().size_changed.connect(_place_jump_button)
	_dive_button.visible = false


func _build_jump_button() -> void:
	var size := 96.0
	var image := Image.create(int(size), int(size), false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# simple filled circle with a soft edge
	var centre := Vector2(size, size) * 0.5
	for y in int(size):
		for x in int(size):
			var d := Vector2(x, y).distance_to(centre)
			if d <= size * 0.5:
				var edge: float = clampf((size * 0.5 - d) / 6.0, 0.0, 1.0)
				image.set_pixel(x, y, Color(1, 1, 1, 0.22 * edge + 0.06))
	var texture := ImageTexture.create_from_image(image)
	_jump_button.texture_normal = texture
	_jump_button.texture_pressed = texture
	_jump_button.modulate = Color(1, 1, 1, 1)
	_jump_button.pressed.connect(func(): jumped.emit())
	_jump_button.released.connect(func(): released.emit())
	_dive_button.texture_normal = texture
	_dive_button.texture_pressed = texture
	_dive_button.pressed.connect(func(): dive_changed.emit(true))
	_dive_button.released.connect(func(): dive_changed.emit(false))


## Anchor the jump button to the bottom-right corner, whatever the screen size is
## (TouchScreenButton is a Node2D, so it has no anchors of its own).
## Shown only while swimming: on land there is nothing to dive into, and a dead button that
## does nothing most of the time is worse than no button.
func show_dive(swimming: bool) -> void:
	if _dive_button.visible != swimming:
		_dive_button.visible = swimming
		if not swimming:
			dive_changed.emit(false)   # never leave dive stuck on when leaving the water


func _place_jump_button() -> void:
	var view := get_viewport().get_visible_rect().size
	_jump_button.position = Vector2(view.x - 190.0, view.y - 190.0)
	# Left of jump rather than below it: below would sit under the thumb that is already
	# resting there, and a mis-tap that surfaces you mid-dive is maddening.
	_dive_button.position = Vector2(view.x - 330.0, view.y - 150.0)


func _draw_stick() -> void:
	if _stick_touch == -1:
		# resting hint in the bottom-left corner
		var rest := Vector2(STICK_RADIUS + 40.0, _stick_layer.size.y - STICK_RADIUS - 40.0)
		_stick_layer.draw_circle(rest, STICK_RADIUS, Color(1, 1, 1, 0.07))
		_stick_layer.draw_arc(rest, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 2.0, true)
		_stick_layer.draw_circle(rest, STICK_RADIUS * 0.38, Color(1, 1, 1, 0.12))
		return
	_stick_layer.draw_circle(_stick_origin, STICK_RADIUS, Color(1, 1, 1, 0.10))
	_stick_layer.draw_arc(_stick_origin, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.25), 2.0, true)
	_stick_layer.draw_circle(_stick_position, STICK_RADIUS * 0.38, Color(1, 1, 1, 0.30))


func _input(event: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < half and _stick_touch == -1:
				_stick_touch = event.index
				_stick_origin = event.position
				_stick_position = event.position
			elif event.position.x >= half:
				if _look_touch == -1:
					_look_touch = event.index
					_look_last = event.position
				_pinch[event.index] = event.position
				if _pinch.size() == 2:
					_pinch_distance = _pinch_span()
		else:
			if event.index == _stick_touch:
				_stick_touch = -1
				move = Vector2.ZERO
			if event.index == _look_touch:
				_look_touch = -1
			_pinch.erase(event.index)
		_stick_layer.queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _stick_touch:
			var offset: Vector2 = event.position - _stick_origin
			if offset.length() > STICK_RADIUS:
				offset = offset.normalized() * STICK_RADIUS
			_stick_position = _stick_origin + offset
			var raw: Vector2 = offset / STICK_RADIUS
			move = Vector2.ZERO if raw.length() < DEAD_ZONE else raw
			_stick_layer.queue_redraw()
		elif _pinch.has(event.index):
			_pinch[event.index] = event.position
			if _pinch.size() == 2:
				var span := _pinch_span()
				zoom_delta += (_pinch_distance - span) * 0.02
				_pinch_distance = span
			elif event.index == _look_touch:
				orbit_delta += (event.position.x - _look_last.x) * 0.005
				# (last - now), so dragging UP is POSITIVE. Screen Y grows downward, and the order of
				# this subtraction is the whole sign - it used to be the other way and was the reason a
				# drag up looked down on touch. `pitch` leaving here means DEGREES UP, nothing else.
				pitch_delta += (_look_last.y - event.position.y) * 0.12
				_look_last = event.position


func _pinch_span() -> float:
	var points := _pinch.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


## The camera rig calls this once per frame and gets the accumulated gestures.
func take_camera_input() -> Dictionary:
	var result := {"orbit": orbit_delta, "pitch": pitch_delta, "zoom": zoom_delta}
	orbit_delta = 0.0
	pitch_delta = 0.0
	zoom_delta = 0.0
	return result
