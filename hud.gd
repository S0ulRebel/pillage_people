extends Control
## The player's health, bottom-left. Placeholder: drawn in code, no art to import.
##
## Bottom-left rather than bottom-right, which is where it was first suggested, because the
## touch build already owns that corner - the jump button sits 190px in from the bottom-right
## and the dive button beside it. Top-left is taken too, by the controls text. On a touch device
## the floating stick can be drawn over this, but the stick appears under a thumb that is
## already looking at the screen edge, and this is a placeholder besides.

const WIDTH := 220.0
const HEIGHT := 18.0
const MARGIN := 24.0

@export var full := Color(0.38, 0.72, 0.30)
@export var low := Color(0.80, 0.22, 0.18)
@export var backing := Color(0.09, 0.08, 0.10, 0.80)
@export var edge := Color(0.02, 0.02, 0.03, 0.9)

var _fraction := 1.0
var _current := 0
var _max := 0


func _ready() -> void:
	# Anchored to the bottom-left corner so it stays put when the window is resized, which the
	# camera's zoom controls make easy to do by accident on desktop.
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	offset_left = MARGIN
	offset_top = -(MARGIN + HEIGHT)
	offset_right = MARGIN + WIDTH
	offset_bottom = -MARGIN
	custom_minimum_size = Vector2(WIDTH, HEIGHT)


func show_health(current: int, maximum: int) -> void:
	_current = current
	_max = maximum
	_fraction = 0.0 if maximum <= 0 else clampf(float(current) / float(maximum), 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, Vector2(WIDTH, HEIGHT))
	draw_rect(box, backing)
	if _fraction > 0.0:
		var inner := Rect2(Vector2(2, 2), Vector2((WIDTH - 4) * _fraction, HEIGHT - 4))
		draw_rect(inner, low.lerp(full, _fraction))
	draw_rect(box, edge, false, 2.0)
	# Notches at each whole point, so three hits read as three rather than as a bar that moved.
	if _max > 1 and _max <= 20:
		for i in range(1, _max):
			var x: float = 2.0 + (WIDTH - 4.0) * (float(i) / float(_max))
			draw_line(Vector2(x, 2), Vector2(x, HEIGHT - 2), edge, 1.0)
