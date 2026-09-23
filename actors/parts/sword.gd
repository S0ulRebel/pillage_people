class_name Sword
extends Held
## A blade in a hand, and who a swing of it reaches.
##
## Everything about getting it INTO the hand - the bone socket, which way it leaves the fist,
## cancelling the rig's unit scale - is in held.gd, shared with anything else a character
## carries. What is here is the part that makes it a sword: the question "who does this swing
## hit", answered once for everybody holding one.
##
## That question used to be answered by an Area3D running along the blade, and it never
## really worked. See targets().

## How far a swing reaches, and how wide a cone in front of the swinger counts.
##
## Measured off the clip rather than chosen. Through the strike window the blade travels
## forward to 0.61 m and then sweeps left to 0.85 m, with its own length beyond that - so 1.35
## covers the arc, and is the number the grunt had already arrived at separately. The cone is
## wide because the sweep genuinely crosses the front: it starts straight ahead and finishes
## ninety degrees to the left.
@export var reach := 1.35
@export_range(0.0, 1.0) var facing_dot := 0.35


## Builds the blade and hangs it off the bone. Nothing else - a sword is a held thing that
## knows its own reach.
func setup(skeleton: Skeleton3D, bone: String, size: Vector3, offset: Vector3,
		rotation_deg: Vector3, colour: Color, model_path := "",
		grip := Vector3.ZERO) -> bool:
	return mount(skeleton, bone, size, offset, rotation_deg, colour, model_path, grip)


## Everybody this swing can hit, from `wielder` facing `facing`, ignoring anyone in `skip`.
##
## A range and cone test, not the blade's own overlap - and that is a fix, not a shortcut.
##
## The hitbox was 12 cm thick and the hand carrying it moves up to 20 cm in one physics step,
## so the blade TELEPORTED PAST people between frames. It only connected when something was
## close enough to still be inside the box on the frame the engine happened to look: measured,
## that was 0.40 m, and 0.55 m and beyond were swept through and took nothing. A grunt stands
## off at 1.00 m and waits there, so the captain could not reach one that was behaving
## normally. His hits landed when the two were jostling close enough to touch, which is why it
## worked often enough to look like bad luck rather than a bug.
##
## The grunt had already worked around the same clip the same way. This is that, in one place.
func targets(wielder: Node3D, facing: Vector3, skip: Array[Node]) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var space := wielder.get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis(), wielder.global_position)
	query.collide_with_bodies = true
	if wielder is CollisionObject3D:
		query.exclude = [(wielder as CollisionObject3D).get_rid()]
	for hit in space.intersect_shape(query, 16):
		var body := hit.get("collider") as Node3D
		if body == null or body == wielder or skip.has(body):
			continue
		if not body.has_method("take_damage"):
			continue
		var towards: Vector3 = body.global_position - wielder.global_position
		towards.y = 0.0
		var distance := towards.length()
		if distance <= 0.001:
			continue
		# Roughly in front. Without this a swing lands on somebody who has already walked past,
		# because the animation is still running while the body turns.
		if facing.dot(towards / distance) < facing_dot:
			continue
		found.append(body)
	return found
