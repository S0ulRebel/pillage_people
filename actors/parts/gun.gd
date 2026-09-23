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

## Override for how far along the barrel the ball leaves, in metres. Zero measures it from the
## model instead, which is almost always what you want - see muzzle().
@export var muzzle_forward := 0.0
@export var damage := 2
## How far the ball carries. Beyond this it is a miss whatever it was aimed at.
@export var carry := 60.0
## Metres per second. The ball is a real object with travel time, so a shot at a moving grunt
## has to lead him - which is the point of firing one rather than a hitscan.
@export var ball_speed := 70.0
@export var reload_seconds := 5.0

## How far off its resting line the barrel may be swung to follow a target, in degrees.
##
## Not unlimited. The body turns towards the cursor too, but on a lerp, so for a moment after a
## fast flick the gun is asked for an angle the arm could never hold - and a pistol pointing
## back over his own shoulder reads as a broken rig rather than as aiming.
@export_range(0.0, 90.0) var aim_limit_degrees := 45.0

@export_group("Recoil")
## How far the gun kicks straight back along its own barrel, in metres.
##
## The gun moves, not the hand: the hand is skinned to a bone and there is no firing clip to
## drive it. The eye follows the pistol, so the kick reads as the arm doing it - and when a
## real firing animation lands this can go to zero and the clip takes over.
@export var recoil_kick := 0.075
## How long the kick and the return take together.
@export var recoil_seconds := 0.16

## The shot leaving the barrel. `to` is where it is aimed, not where it lands - the ball is in
## flight now and nobody knows yet. Kept for the crack and the smoke, which happen at once.
signal fired(from: Vector3, to: Vector3, hit: Node)
## The ball arriving, however long later. `body` is whatever the ray found, which may be
## terrain, or null for a shot into open sky.
signal struck(body: Node, at: Vector3, direction: Vector3)
## Loaded again, for whatever wants to tell the player so.
signal reloaded

var _loaded := true
var _reloading := 0.0
## Seconds left of the kick. Counts down, so 1 is the instant of firing and 0 is at rest.
var _kick := 0.0
## The barrel, in the held node's own space, worked out once from the model. See muzzle().
var _barrel := Vector3.ZERO
var _barrel_length := 0.0


func is_loaded() -> bool:
	return _loaded


func is_reloading() -> bool:
	return _reloading > 0.0


## How far through the reload, 0 to 1. For a bar, or for an animation to follow.
func reload_fraction() -> float:
	if reload_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - _reloading / reload_seconds, 0.0, 1.0)


## Counts the reload down, and settles the recoil. The owner calls this once a frame.
func tick(delta: float) -> void:
	_settle(delta)
	if _reloading <= 0.0:
		return
	_reloading = maxf(0.0, _reloading - delta)
	if _reloading <= 0.0:
		_loaded = true
		reloaded.emit()


## Points the barrel at `target`, on both axes.
##
## The captain's body only turns on its yaw - he stays upright, because a pirate who leans back
## to shoot a gull is a pirate who has fallen over. So anything above or below him has to come
## from the gun itself, and this is the part that makes the shot look like it is going where
## the cursor is.
##
## Rebuilt from the socket every frame rather than nudged, so it cannot drift: the rotation
## asked for is always relative to where the hand bone currently is, not to wherever the gun
## ended up last frame.
func aim_along(target: Vector3) -> void:
	if _barrel_length <= 0.0:
		_measure_barrel()
	var socket := get_parent() as Node3D
	if _barrel_length <= 0.0 or socket == null:
		return
	var want := target - global_position
	if want.length() < 0.05:
		return
	# The direction wanted, expressed in the socket's space, because that is the space this
	# node's own basis lives in.
	var wanted := (socket.global_transform.basis.inverse() * want.normalized()).normalized()
	var barrel := _barrel.normalized()
	var swing := barrel.angle_to(wanted)
	var turn := Quaternion(barrel, wanted)
	var limit := deg_to_rad(aim_limit_degrees)
	if swing > limit and swing > 0.0001:
		turn = Quaternion.IDENTITY.slerp(turn, limit / swing)
	transform.basis = Basis(turn).scaled(rest_scale)


## Eases the gun back to rest after a shot.
##
## Straight back along the barrel, which is +Y in the held node's space - the same axis the
## item's `grip` slides along to put the handle in the fist. Squared, so it leaves at full kick
## on the firing frame and most of the recovery is over quickly: a linear return reads as the
## gun being pushed back rather than as it being fired.
func _settle(delta: float) -> void:
	if _kick <= 0.0:
		return
	_kick = maxf(0.0, _kick - delta)
	var model := get_node_or_null("Model")
	if model == null or item == null:
		return
	var t := _kick / maxf(recoil_seconds, 0.0001)
	(model as Node3D).position = item.grip - Vector3(0.0, recoil_kick * t * t, 0.0)


## Where the ball leaves from, in world space: the end of the barrel.
##
## The direction is MEASURED from the model - the furthest vertex from the grip is the muzzle -
## rather than assumed to be an axis. It used to take the held node's +X and a hand-tuned
## 0.22 m, and both were wrong: measured against this model, +X dots the real barrel at -0.457,
## so it pointed backwards, and the point it produced sat 0.528 m from the actual tip. Nothing
## noticed while the shot was a hitscan, because the ray still ran from there to the aim point
## and hit the right thing. Putting a visible flare at the muzzle is what exposed it.
##
## Measuring also means this survives the gun being resized. `model_scale` going from 1.0 to
## 1.35 moved the real muzzle and would have silently left any fixed number behind.
func muzzle() -> Vector3:
	if _barrel_length <= 0.0:
		_measure_barrel()
	if _barrel_length <= 0.0:
		return global_position + global_transform.basis.x.normalized() * muzzle_forward
	var reach := muzzle_forward if muzzle_forward > 0.0 else _barrel_length
	return global_position + (global_transform.basis * _barrel).normalized() * reach


## The furthest point of the model from the grip, in the held node's own space. Cached: the
## model does not change shape, and this walks every mesh in it.
func _measure_barrel() -> void:
	var model := get_node_or_null("Model")
	if model == null:
		return
	# The whole model, merged, in this node's own space.
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for node in (model as Node3D).find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box: AABB = mesh_node.mesh.get_aabb()
		for corner in 8:
			var at: Vector3 = to_local(mesh_node.global_transform * box.get_endpoint(corner))
			lo = lo.min(at)
			hi = hi.max(at)
	if lo.x > hi.x:
		return

	# The CENTRELINE of the far end, not the furthest corner.
	#
	# A corner was the first attempt and it aimed low every single time, by the same amount
	# wherever the cursor was. The furthest point of a flintlock from its grip is the top edge
	# of the muzzle - the lock and the hammer stand proud - so pointing that at a target tips
	# the bore underneath it. The bore is what the shot and the eye both follow, so take the
	# middle of the far face: longest axis for the length, dead centre on the other two.
	var middle := (lo + hi) * 0.5
	var size := hi - lo
	var axis := 0
	if size.y > size[axis]:
		axis = 1
	if size.z > size[axis]:
		axis = 2
	var tip := middle
	tip[axis] = hi[axis] if absf(hi[axis]) > absf(lo[axis]) else lo[axis]
	if tip.length() < 0.0001:
		return
	_barrel = tip.normalized()
	# Length in WORLD metres. Taking it from local space was wrong once already: this node
	# carries the rig's cancelled unit scale, so a local length is out by a factor of the
	# scale - measured, 0.288 against a real 0.389 m.
	_barrel_length = global_position.distance_to(to_global(tip))


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

	# The ray decides what is hit, here and now. It is the same ray the pistol always used.
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_bodies = true
	if wielder is CollisionObject3D:
		query.exclude = [(wielder as CollisionObject3D).get_rid()]
	var result := wielder.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Node = null
	if not result.is_empty():
		to = result["position"]
		target = result.get("collider") as Node

	# The ball is a tracer over that answer, not a second opinion. It carries the time - damage
	# lands when it arrives rather than on the frame of the click. Spawned on the SCENE rather
	# than on the gun, so it does not ride the hand that fired it and outlives the captain
	# reloading, dying or putting the pistol away.
	var heading := along.normalized()
	var ball := Ball.launch(wielder.get_parent(), from, to, ball_speed)
	ball.arrived.connect(func(at: Vector3) -> void:
		if target != null and is_instance_valid(target) and target.has_method("take_damage"):
			target.take_damage(damage, wielder)
		struck.emit(target, at, heading))
	# The flare and the powder cloud, at the pan, now. On the SCENE rather than on the gun so
	# the cloud stays where it was made instead of riding his hand as he turns away.
	MuzzleFlash.burst(wielder.get_parent(), from, heading)
	_kick = recoil_seconds
	# Reported at the muzzle, for the crack. Nothing has landed yet.
	fired.emit(from, to, null)
	return ball
