class_name Bubbles
extends CPUParticles3D
## Breath, let go a little at a time while he is under: a thin stream of bubbles from his head
## that rise, spread and pop at the surface. The one thing that says "under water" that no
## colour can.
##
## CPUParticles3D, like the hit spark and the waterfall's mist: a few dozen particles, no
## process material, no shader compile on the first dive, and it can be watched in a headless
## test. Built in code like everything else here. The bubble itself is a quad with a shader
## that faces the camera, fogs itself, and pops itself short of the surface - see
## bubble.gdshader.
##
## Not hung off the head bone, though that is where they come from: it FOLLOWS the head,
## copying its position each frame. A BoneAttachment3D carries the rig's own units - 0.01 on
## these skeletons, which held.gd measured and has to cancel - and a particle system with
## local_coords off runs its launch, its spread and its own bounds through that scale. Under
## the bone the bubbles left the skull at a centimetre a second from a point, and were culled
## whenever the head left the frame.

const SHADER := preload("res://actors/captain/bubble.gdshader")

var _material: ShaderMaterial
var _follow: Node3D


func _ready() -> void:
	name = "Bubbles"
	amount = 36
	lifetime = 2.6
	local_coords = false
	emitting = false
	# From a small volume around the mouth, not a point: a point reads as a hose.
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.12
	direction = Vector3.UP
	spread = 28.0
	initial_velocity_min = 0.3
	initial_velocity_max = 0.9
	lifetime_randomness = 0.35
	# Buoyancy: they speed up as they rise, the damping keeps that from running away.
	gravity = Vector3(0.0, 0.9, 0.0)
	damping_min = 0.5
	damping_max = 0.7
	# A sideways push each way, so they wander up rather than file up, and no clock on the
	# emission. Without both they rose in one column from his head, one bubble every 72 ms,
	# which read as a chain of beads.
	tangential_accel_min = -1.6
	tangential_accel_max = 1.6
	randomness = 0.7
	scale_amount_min = 0.05
	scale_amount_max = 0.11
	# Small when they leave him and growing on the way up, the way a bubble does as the
	# pressure comes off it.
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.55))
	grow.add_point(Vector2(0.5, 1.0))
	grow.add_point(Vector2(1.0, 1.0))
	scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.6))
	color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# After the underwater pass (100) and the sea. Why is on the shader.
	_material.render_priority = 101
	quad.material = _material
	mesh = quad


## The point the bubbles leave from - his head. Followed, not parented; see above.
func follow(target: Node3D) -> void:
	_follow = target


func _process(_delta: float) -> void:
	if _follow != null:
		global_position = _follow.global_position


## Where the surface is, so a bubble can pop short of it. Flat sea level; the shader pops
## them the swell's height under it, so none ever comes up in air over a trough.
func set_water_level(level: float) -> void:
	_material.set_shader_parameter("water_level", level)


## On while he is under, off once he surfaces. The bubbles already loose finish rising.
func breathe(under: bool) -> void:
	emitting = under
