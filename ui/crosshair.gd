class_name Crosshair
extends CanvasLayer
## Where the flintlock is pointed, drawn at the mouse.
##
## A cursor rather than a fixed reticle in the middle of the screen, and that is a choice the
## camera makes for us: this is a bird's-eye chase view, so a centre crosshair would mean
## swinging the whole camera round to shoot at a grunt standing beside you. A cursor lets the
## captain shoot where you point without the view moving at all.
##
## It also shows the reload, because a flintlock spends most of its life empty and a player who
## cannot see that is a player clicking a dead trigger.

## Radius of the ring, and how long each of the four ticks is.
@export var radius := 13.0
@export var tick := 7.0
@export var thickness := 2.0
@export var loaded_colour := Color(1.0, 0.96, 0.88, 0.95)
## While reloading. Deliberately far from the loaded colour - this is the one thing about the
## pistol the player has to be able to read at a glance.
@export var empty_colour := Color(0.85, 0.35, 0.25, 0.8)

var _at := Vector2.ZERO
var _fraction := 1.0
var _draw: Control


func _ready() -> void:
	# Above the HUD, below the spyglass and the scene iris.
	layer = 50
	_draw = Control.new()
	_draw.name = "Ring"
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_paint)
	add_child(_draw)
	hide()


## Puts it under the pointer and tells it how the reload is going.
func track(at: Vector2, reload_fraction: float) -> void:
	_at = at
	_fraction = reload_fraction
	if _draw != null:
		_draw.queue_redraw()


func _paint() -> void:
	var colour := loaded_colour if _fraction >= 1.0 else empty_colour
	# Four ticks rather than a full circle: a solid ring hides the thing being aimed at, which
	# on a top-down view is a grunt about the size of the ring.
	for step in 4:
		var angle := TAU * float(step) / 4.0
		var out := Vector2(cos(angle), sin(angle))
		_draw.draw_line(_at + out * radius, _at + out * (radius + tick), colour, thickness)
	# The reload, as an arc closing back to a full ring. Drawn as short segments because
	# draw_arc with a point count this low is visibly a polygon.
	if _fraction < 1.0:
		var filled := int(maxf(_fraction * 32.0, 1.0))
		for step in filled:
			var a := TAU * float(step) / 32.0 - PI * 0.5
			var b := TAU * float(step + 1) / 32.0 - PI * 0.5
			_draw.draw_line(_at + Vector2(cos(a), sin(a)) * radius,
					_at + Vector2(cos(b), sin(b)) * radius, empty_colour, thickness)
