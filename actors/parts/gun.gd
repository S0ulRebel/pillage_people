class_name Gun
extends Held
## A flintlock: one ball, then a long reload.
##
## Everything about getting it into the hand is in held.gd, shared with the sword and with
## anything else a character carries. What is here is the business end - where the ball goes,
## what it hits, and the fact that there is only ever one of them.
##
## The single shot is the design rather than a limitation. A pistol with a magazine turns the
## cutlass into a backup weapon, because ranged always beats melee when ammunition is free; one
## ball and five seconds of reloading makes every shot a decision - open the fight with it, or
## keep it for whoever gets past your guard. The reload IS the balance.

## Where the ball comes from, along the barrel from the grip. In metres.
@export var muzzle_forward := 0.22
@export var damage := 2
## How far the ball carries. Beyond this it is a miss whatever it was aimed at.
@export var carry := 60.0
@export var reload_seconds := 5.0

## Fired with where the ball went, so something can draw smoke and a crack along it. `hit` is
## null for a clean miss.
signal fired(from: Vector3, to: Vector3, hit: Node)
## Loaded again, for whatever wants to tell the player so.
signal reloaded

var _loaded := true
var _reloading := 0.0


func is_loaded() -> bool:
	return _loaded


func is_reloading() -> bool:
	return _reloading > 0.0


## How far through the reload, 0 to 1. For a bar, or for an animation to follow.
func reload_fraction() -> float:
	if reload_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - _reloading / reload_seconds, 0.0, 1.0)


## Counts the reload down. The owner calls this once a frame.
func tick(delta: float) -> void:
	if _reloading <= 0.0:
		return
	_reloading = maxf(0.0, _reloading - delta)
	if _reloading <= 0.0:
		_loaded = true
		reloaded.emit()


## Where the ball leaves from, in world space.
##
## Along the barrel rather than at the grip, so smoke and the shot line start at the end of the
## pistol instead of inside the captain's fist.
func muzzle() -> Vector3:
	return global_position + global_transform.basis.x.normalized() * muzzle_forward


## Fires at `aim`. Returns what was hit, or null for a miss - and false is returned by
## is_loaded() until the reload finishes.
##
## The ball is traced from the MUZZLE to the aim point, not from the camera. The camera is how
## the player picked the spot; the pistol is what the shot comes out of, and those two are not
## in the same place. Tracing from the camera would let him shoot through the rock he is
## standing behind.
func fire(wielder: Node3D, aim: Vector3) -> Node:
	if not _loaded:
		return null
	_loaded = false
	_reloading = reload_seconds

	var from := muzzle()
	# Fired THROUGH the aim point for the pistol's full carry, not stopped at it.
	#
	# The aim arrives from a camera ray, so it is a point on the SURFACE of whatever is under
	# the cursor. A ray that ends exactly on a surface is a coin flip - it registered when the
	# test aimed at a grunt's centre and ended up inside him, and missed in the game every
	# time, where the cursor puts it on his chest. A ball does not stop in mid-air where you
	# were pointing either.
	var along := aim - from
	if along.length() < 0.001:
		return null
	var to := from + along.normalized() * carry

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	if wielder is CollisionObject3D:
		query.exclude = [(wielder as CollisionObject3D).get_rid()]
	var result := wielder.get_world_3d().direct_space_state.intersect_ray(query)

	var struck: Node = null
	if not result.is_empty():
		to = result["position"]
		var body := result.get("collider") as Node
		if body != null and body.has_method("take_damage"):
			struck = body
			body.take_damage(damage, wielder)
	fired.emit(from, to, struck)
	return struck
