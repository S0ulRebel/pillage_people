class_name Sword
extends Held
## A blade in a hand, with an overlap volume running along it.
##
## Everything about getting it INTO the hand - the bone socket, which way it leaves the fist,
## cancelling the rig's unit scale - is in held.gd, shared with anything else a character
## carries. What is here is the only part that makes it a sword: a box that reports what the
## blade is touching.
##
## Shared by the captain and the grunts, though only the captain's hits are decided by it. A
## grunt's swing sweeps ACROSS its body - the tip travels 0.37 to 0.51 m to its left and barely
## 0.3 m forward - so blade overlap can never reach the person in front of it, and the grunt
## uses a range and facing check instead. The hitbox is still built, because the sword is the
## same sword and the day a grunt gets a clip that thrusts it will already be right.

## The overlap volume around the blade. Whoever owns the sword decides when a hit counts; this
## only reports what the blade is touching.
var hitbox: Area3D


## Builds the blade, hangs it off the bone, and puts a hitbox along it.
func setup(skeleton: Skeleton3D, bone: String, size: Vector3, offset: Vector3,
		rotation_deg: Vector3, colour: Color, model_path := "",
		grip := Vector3.ZERO) -> bool:
	if not mount(skeleton, bone, size, offset, rotation_deg, colour, model_path, grip):
		return false

	hitbox = Area3D.new()
	hitbox.name = "BladeHit"
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	hitbox.add_child(collider)
	# Left monitoring the whole time. Toggling it costs a physics frame before overlaps are
	# reported again, and a strike window is only a dozen frames wide - long enough to lose a
	# hit to that delay. The owner gates whether a hit counts, not whether the area is watching.
	hitbox.monitoring = true
	add_child(hitbox)
	# A modelled blade has its origin at the pommel and runs out along +X, so the hitbox is
	# pushed out to sit over the blade rather than straddling the fist. The box mesh is centred
	# on its own origin, so it needs no such shift.
	if Held.has_model(model_path):
		collider.position = Vector3(size.x * 0.5, 0.0, 0.0)
	return true
