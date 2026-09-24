class_name Cannonball
extends MeshInstance3D
## A real projectile. It arcs under gravity and decides its own hit.
##
## This is the OPPOSITE of Ball, deliberately, and it is a separate class for that reason.
## Ball's own docstring says it "does NOT collide with anything" because the pistol is a
## hitscan - the ray decides the hit on the frame of the click and the ball is a tracer drawn
## over an answer already given. That is right for a pistol, where the shot is instant and
## cannot miss differently from how it was aimed.
##
## A cannon is the other thing entirely. The whole point is that the shot ARCS, that you watch
## it, and that it lands where the arc takes it rather than where you pointed. So the hit
## cannot be known at fire time, and this has to find it itself.
##
## SWEPT, not an Area3D, and not a position test. At 40 m/s a ball moves 0.67 m per physics
## tick, so a test at the new position alone steps straight through a grunt. The blade had
## exactly this bug - see the note in sword.gd about a 12 cm hitbox on a hand moving 20 cm a
## step - and an Area3D would reintroduce it. Each step raycasts from where it was to where it
## now is, so nothing can be skipped however fast it flies.

## Where it stopped, what it struck (null for terrain or nothing) and the surface it hit.
signal landed(body: Node, at: Vector3, normal: Vector3)

## Metres per second squared. NOT Godot's default 9.8: this world is small and a real-gravity
## shell hangs in the air for an age and reads as floating. Heavier gravity shortens the arc
## and makes the shot feel like iron. Tune this before touching muzzle speed.
@export var gravity := 26.0
@export var radius := 0.16
## Give up after this long. A shot fired at the sky would otherwise fall for ever, and a ball
## that leaves the island never reports anything and never frees itself.
@export var max_seconds := 12.0
## What it can hit. Set by the firer; both the world and anything damageable, by default.
@export var mask := 0

var _velocity := Vector3.ZERO
var _age := 0.0
var _trail: CPUParticles3D = null


## Puts a ball in the world travelling at `velocity`. The caller works out that vector - see
## Cannon.aim_velocity - because the launch angle is the thing the player is actually choosing
## and it does not belong in here.
static func launch(parent: Node, from: Vector3, velocity: Vector3, hit_mask: int) -> Cannonball:
	var ball := Cannonball.new()
	ball.name = "Cannonball"
	ball._velocity = velocity
	ball.mask = hit_mask
	parent.add_child(ball)
	ball.global_position = from
	ball._build()
	return ball


## Where a shot fired at `velocity` from `from` would be after `seconds`. Exposed so a test can
## check the arc against the same arithmetic the ball flies, and so a future aiming aid could
## draw the path without duplicating it.
static func at_time(from: Vector3, velocity: Vector3, gravity_up: float, seconds: float) -> Vector3:
	return from + velocity * seconds + Vector3.DOWN * (0.5 * gravity_up * seconds * seconds)


func _build() -> void:
	var shot := SphereMesh.new()
	shot.radius = radius
	shot.height = radius * 2.0
	shot.radial_segments = 10
	shot.rings = 6
	mesh = shot
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.11, 0.10, 0.10)
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.metallic = 0.0
	material.roughness = 1.0
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material_override = material
	# Layer 20 is the overhead water-interaction camera; anything visible has to be on it.
	set_layer_mask_value(20, true)
	_build_trail()


## A thread of smoke behind it. This is not decoration: the shot is aimed by eye and corrected
## by watching where the last one went, so the trail IS the aiming aid. Without it a miss over
## a ridge tells you nothing.
func _build_trail() -> void:
	_trail = CPUParticles3D.new()
	_trail.name = "Trail"
	_trail.amount = 28
	_trail.lifetime = 0.9
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = radius * 0.6
	_trail.direction = Vector3.UP
	_trail.spread = 12.0
	_trail.initial_velocity_min = 0.1
	_trail.initial_velocity_max = 0.5
	_trail.gravity = Vector3.UP * 0.6
	_trail.scale_amount_min = radius * 1.4
	_trail.scale_amount_max = radius * 2.6
	var fade := Gradient.new()
	fade.set_color(0, Color(0.85, 0.84, 0.82, 0.55))
	fade.set_color(1, Color(0.78, 0.77, 0.75, 0.0))
	# CPUParticles3D takes the Gradient itself. GPUParticles3D is the one that wants it wrapped
	# in a GradientTexture1D, and mixing the two up is a compile error, not a runtime one.
	_trail.color_ramp = fade
	add_child(_trail)


func velocity() -> Vector3:
	return _velocity


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > max_seconds:
		# Out of the world rather than into something. Say so with a null body at the last
		# known place, so a listener never silently loses a shot.
		landed.emit(null, global_position, Vector3.UP)
		queue_free()
		return

	_velocity += Vector3.DOWN * gravity * delta
	var was := global_position
	var now := was + _velocity * delta

	# Swept. See the note at the top - testing only `now` steps over anything thinner than one
	# tick of travel, which at these speeds is most of a person.
	var query := PhysicsRayQueryParameters3D.create(was, now)
	query.collision_mask = mask
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var at: Vector3 = hit["position"]
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		global_position = at
		landed.emit(hit.get("collider") as Node, at, normal)
		queue_free()
		return

	global_position = now
	# Point the way it is going, so the ball reads as travelling rather than drifting.
	if _velocity.length_squared() > 0.001:
		look_at(now + _velocity, Vector3.UP)
