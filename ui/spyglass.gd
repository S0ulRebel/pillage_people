class_name Spyglass
extends CanvasLayer
## A spyglass iris over the whole screen, for openings, deaths, and moving between scenes.
##
## It knows nothing about what is underneath it or what happens next. `close()` shuts the iris
## and `open()` opens it, both awaitable, so a transition is written where the transition
## belongs:
##
##     await glass.close(0.8)
##     get_tree().change_scene_to_file(somewhere)
##     glass.open(1.2)
##
## That is the whole design. It does not swap scenes itself, because the thing that knows a
## scene should change is never this - and a fader that also decides where you are going
## cannot be reused by anything that wants to go somewhere else.
##
## It does NOT survive a scene change. It does not need to: a scene that starts with the iris
## shut and opens it looks exactly like one continuous shot, with no node persisting across the
## swap and no autoload to arrange it. When there is a Game scene above the swapped one, move
## this into it and the same two calls span the change instead.

const SHADER := "res://ui/spyglass.gdshader"

## Fully shut. Anything at or below this leaves no pinhole.
const SHUT := 0.0
## Fully open is worked out from the window rather than fixed, because a constant cannot be
## right for two shapes of screen. The shader measures distance from the middle with x
## stretched by the aspect and then divided by the half-height, so the corner sits at
## sqrt(aspect^2 + 1) - which is 1.41 on a square screen, 2.04 at 16:9 and 2.66 at 21:9.
##
## The first version of this was a flat 1.35, chosen by halfway remembering the square case.
## It looked correct at every stage of the animation except the last, where the iris stopped
## with the scene framed and black still in the corners.
var _wide := 2.1

## Seconds for a close and for an open when none is given. The open is slower on purpose - a
## scene arriving wants to be unhurried, and a scene leaving wants to be done.
@export var close_seconds := 0.9
@export var open_seconds := 1.4
@export var surround := Color(0.0, 0.0, 0.0, 1.0)
## The rim feather and the darkening inside it. See the shader.
@export_range(0.001, 0.6) var softness := 0.12
@export_range(0.0, 1.0) var falloff := 0.35
@export_range(0.0, 1.0) var falloff_strength := 0.55

## Emitted when an open or a close finishes. Not used for sequencing - await the call instead -
## but useful for anything that wants to know without driving it.
signal opened
signal closed

var _rect: ColorRect
var _material: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	# Above the HUD, which is layer 0. The health bar should be behind the iris, not floating
	# over a black screen after the captain is dead.
	layer = 100
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER)
	_rect = ColorRect.new()
	_rect.name = "Iris"
	_rect.material = _material
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# It covers the screen and must never eat a click meant for the game underneath.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_material.set_shader_parameter("surround", surround)
	_material.set_shader_parameter("softness", softness)
	_material.set_shader_parameter("falloff", falloff)
	_material.set_shader_parameter("falloff_strength", falloff_strength)
	_set_openness(SHUT)
	_match_aspect()
	get_viewport().size_changed.connect(_match_aspect)


## Opens the iris. Awaitable: `await glass.open()` returns when the scene is fully revealed.
func open(seconds := -1.0) -> void:
	await _to(_wide, seconds if seconds >= 0.0 else open_seconds)
	opened.emit()


## Shuts the iris. Awaitable, which is what makes it usable as a transition - close, swap,
## open, in the order they are written.
func close(seconds := -1.0) -> void:
	await _to(SHUT, seconds if seconds >= 0.0 else close_seconds)
	closed.emit()


## Straight to a state with no animation, for starting a scene already shut.
func snap(is_open: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_set_openness(_wide if is_open else SHUT)


func is_shut() -> bool:
	return _openness <= SHUT + 0.0001


var _openness := 0.0


func _to(target: float, seconds: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if seconds <= 0.0:
		_set_openness(target)
		return
	_tween = create_tween()
	# Eased rather than linear. A linear iris appears to hesitate at the end, because the area
	# it reveals grows with the square of the radius while the radius moves at a constant rate.
	_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_method(_set_openness, _openness, target, seconds)
	await _tween.finished


func _set_openness(value: float) -> void:
	_openness = value
	if _material != null:
		_material.set_shader_parameter("openness", value)


## The iris is a circle on screen, not in UV space, so the shader needs to know the shape of
## the window - and needs telling again whenever it changes.
func _match_aspect() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	var aspect := size.x / size.y
	# Plus the feather, or the soft edge is still washing the corners when the iris stops.
	_wide = sqrt(aspect * aspect + 1.0) * (1.0 + softness)
	if _material != null:
		_material.set_shader_parameter("aspect", aspect)
