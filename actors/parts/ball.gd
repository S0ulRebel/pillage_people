class_name Ball
extends MeshInstance3D
## A fired shot, in flight.
##
## It does NOT collide with anything. The gun's ray has already worked out what the shot meets
## and where - see gun.gd - so the ball only has to travel there and say when it arrives. Doing
## the collision twice would mean a shot could be resolved one way and drawn another, and a
## ball moving 1.17 m per tick would need sweeping to be trusted at all.
##
## What it buys is time. Damage lands when the ball gets there rather than on the frame of the
## click, so a shot across the beach is visibly a shot rather than an instant result.

## Reached its destination. This is the moment the shot actually happens.
signal arrived(at: Vector3)

## Metres per second. Slow enough to read as a streak, fast enough that ten metres takes
## 0.14 s rather than long enough to walk out of.
@export var speed := 70.0
## Half the length of the streak, in metres.
@export var trail := 0.35

var _to := Vector3.ZERO
var _direction := Vector3.FORWARD


## Puts a tracer in the world and sends it to `to`, which the gun's ray already chose.
static func launch(parent: Node, from: Vector3, to: Vector3, speed_override := 0.0) -> Ball:
	var ball := Ball.new()
	ball.name = "Ball"
	if speed_override > 0.0:
		ball.speed = speed_override
	ball._to = to
	var along := to - from
	ball._direction = along.normalized() if along.length() > 0.001 else Vector3.FORWARD
	parent.add_child(ball)
	ball.global_position = from
	ball._build()
	return ball


func _build() -> void:
	var streak := CapsuleMesh.new()
	streak.radius = 0.02
	streak.height = trail * 2.0
	streak.radial_segments = 6
	streak.rings = 1
	mesh = streak
	# The capsule is built along Y, so lay it along the flight path.
	look_at(global_position + _direction, Vector3.UP)
	rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.18, 0.16)
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.metallic = 0.0
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material_override = material
	# Layer 20 is the overhead water-interaction camera; anything visible has to be on it.
	set_layer_mask_value(20, true)


func _physics_process(delta: float) -> void:
	var step := speed * delta
	var left := global_position.distance_to(_to)
	if step >= left:
		global_position = _to
		arrived.emit(_to)
		queue_free()
		return
	global_position += _direction * step
