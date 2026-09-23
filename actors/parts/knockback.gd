class_name Knockback
extends Node
## The shove a hit gives, and the moment of lost control that follows it.
##
## Holds the shove as a velocity that bleeds off, and a countdown while the owner should not be
## steering. The owner asks for both each frame and decides what to do with them - which is the
## whole reason this works for two characters who move completely differently. The captain adds
## the shove to his own velocity and stops reading the controls; a grunt adds it on top of
## walking toward its target and stops walking. Neither had to change how it moves.
##
## Why it is a component at all: these were two implementations of one idea, and they drifted.
## The captain once added his shove to velocity EVERY FRAME, which fed the previous frame's
## push back into move_toward's starting point and compounded - he travelled 2.31 m from a hit
## a grunt took for 0.43. The fix was a single impulse, and it was applied to one of them.

## Metres per second of shove. Tune per character: the captain is shoved harder than a grunt.
@export var strength := 4.0
## Seconds of lost control afterwards. The captain's is deliberately SHORTER than a grunt's -
## losing control of your own character is far more irritating than watching someone else lose
## theirs, and a long stun turns two grunts into a death sentence.
@export var recovery := 0.25
## How fast the shove bleeds off, in metres per second squared. Low on purpose: a character's
## normal deceleration is over a hundred, which would kill the shove inside three frames and
## make a hit look like nothing happened.
@export var damping := 9.0

var _shove := Vector3.ZERO
var _left := 0.0


## Shoves `here` directly away from `attacker`, and starts the recovery.
##
## Applied once, as an impulse. Call it again and it replaces the shove rather than adding to
## it, so being hit twice does not launch anyone.
func hit_from(here: Vector3, attacker: Node) -> void:
	_left = recovery
	if not attacker is Node3D:
		# No direction to be shoved in - a fall, or a hit from nothing in particular. The
		# stagger still counts; only the push is skipped.
		return
	var away: Vector3 = here - (attacker as Node3D).global_position
	away.y = 0.0
	if away.length() > 0.01:
		_shove = away.normalized() * strength


## Bleeds the shove off and counts the recovery down. The owner calls this once a frame.
func tick(delta: float) -> void:
	_left = maxf(0.0, _left - delta)
	_shove = _shove.move_toward(Vector3.ZERO, damping * delta)


## The shove still in effect, in metres per second. Flat: knockback never lifts anyone.
func shove() -> Vector3:
	return _shove


## Whether the owner should be ignoring its controls or its AI right now.
func staggered() -> bool:
	return _left > 0.0


## Drops the shove and the stagger. For a respawn, not for a fight.
func clear() -> void:
	_shove = Vector3.ZERO
	_left = 0.0
