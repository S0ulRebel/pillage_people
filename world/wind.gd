class_name Wind
extends Node
## One breeze for the whole scene. The sail reads `blow`, the sea leans toward `direction`, and
## the clouds' shadows drift with it.
##
## It turns slowly rather than gusting. A steady push is enough to belly a sail and shift the
## waves; a new heading every second would just make both of them twitch.

## Horizontal push, metres per second squared, applied to cloth.
const STRENGTH := 7.0
## How far the waves are allowed to swing toward the breeze. They keep their own headings.
const LEAN := 0.35
## Radians per second. A full turn of the wind takes about three minutes.
const TURN := 0.035
## Metres per second the clouds' shadows cross the island. A fair-weather cloud moves at
## ten or so; slower, because the island is only 620 m across and a shadow gone in a minute
## is a shadow nobody sees.
const CLOUD_SPEED := 4.0

var direction := Vector3(0.45, 0.0, 0.89)
var _angle := 0.45
var _ocean: Ocean
## How far the clouds have been blown, metres. Handed to every shader that draws cloud
## shadows, as the global `cloud_drift` (world/cloud_shadow.gdshaderinc).
var _cloud_drift := Vector2.ZERO


func _ready() -> void:
	add_to_group("wind")
	direction = Vector3(sin(_angle), 0.0, cos(_angle))
	_ocean = get_parent().get_node_or_null("Ocean") as Ocean


func _process(delta: float) -> void:
	_angle += TURN * delta
	direction = Vector3(sin(_angle), 0.0, cos(_angle))
	if _ocean != null:
		_ocean.lean_into(direction, LEAN)
	_cloud_drift += Vector2(direction.x, direction.z) * CLOUD_SPEED * delta
	RenderingServer.global_shader_parameter_set("cloud_drift", _cloud_drift)


## Acceleration the cloth should add, in world space.
func blow() -> Vector3:
	return direction * STRENGTH
