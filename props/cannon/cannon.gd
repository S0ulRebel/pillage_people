@tool
class_name Cannon
extends Node3D
## A gun carriage that sits on the ground and that you cannot walk through.
##
## STATIC, not a RigidBody. A cannon is heavy and stays where it is put; give it a rigid body
## and it tumbles down the first slope it is placed on, which is worse than no physics at all.
## The rocks and cargo in this game are static for the same reason.
##
## Everything here is measured off the mesh rather than written down, because the model's own
## node carries an arbitrary offset - the imported FBX has its mesh sitting some distance from
## the node you actually grab in the editor - so a collision box built from assumed numbers
## would sit in the wrong place. The union of the child mesh AABBs, expressed in this node's
## space, is the only thing that is reliably true.
##
## The collision body is built at runtime and deliberately has NO owner, so it is never written
## into the scene file. That matters: the ocean's editor preview was serialising a megabyte of
## generated ArrayMesh into main.tscn until it was stopped, and this would do the same.

## --- Firing ----------------------------------------------------------------------------
## Every number the control scheme rests on is here rather than buried, because the scheme is
## expected to change. Swapping "drag for elevation" for "cursor picks the landing point" is
## then a different aim_velocity(), not a rewrite.

## Metres per second at the muzzle. FIXED - the player controls the angle, not the power, so
## the same drag always gives the same arc and the arc can be learned. Raising this flattens
## every shot and lengthens every range at once.
@export var muzzle_speed := 34.0
## Metres per second squared on the ball. Must match Cannonball.gravity or the preview arc and
## the real one disagree.
@export var shot_gravity := 26.0
@export var min_elevation := 2.0
## 45 DEGREES, NOT MORE, and this is a design rule rather than a tuning number.
##
## Range is v^2 * sin(2A) / g, which peaks at 45 and comes back DOWN after it - at 55 degrees a
## shot lands shorter than at 35. Allow the gun past 45 and every range has two answers, so
## pulling further back sometimes lengthens the shot and sometimes shortens it. The arc stops
## being learnable, which is the one thing this whole control scheme exists to make possible.
@export var max_elevation := 45.0
## Degrees of elevation per pixel of upward drag. At 0.12 a 300 px pull covers the whole range,
## which is a comfortable wrist movement rather than a whole-arm one.
@export var elevation_per_pixel := 0.12
## Elevation the gun returns to when it is let go of.
@export var rest_elevation := 12.0
## THE CONTROL SCHEME SWITCH. True: pressing locks the bearing and only vertical movement
## counts until release, so the drag cannot spin the gun while you set the angle. False: the
## cursor keeps steering the bearing all the way through, which is looser and worth trying.
@export var lock_bearing_on_press := true

@export_group("Shot")
@export var damage := 3
## Anything within this of the impact takes `damage`. Without it, aiming by eye is a needle to
## thread and every near miss feels like the game cheated.
@export var blast_radius := 3.6
@export var reload_seconds := 2.0
## How far in front of the carriage the ball appears, and how high. Taken along the FIRING
## direction rather than off the model's own axis, because this mesh arrives from Tripo with an
## arbitrary rotation baked into its node and no reliable forward.
@export var muzzle_reach := 1.1
@export var muzzle_height := 0.55
## The moving part. Left empty it is found by measurement: of the child meshes, the barrel is
## the one with the longest single dimension - 2.0 m against the carriage's 1.2. Naming it
## explicitly wins if the model ever stops being obvious.
@export var barrel_name := ""
## Turn off for a model that is one piece. The gun still fires; only the visible lift is lost.
@export var elevate_barrel := true

## Fired. `from` is the muzzle, `velocity` is the launch vector.
signal fired(from: Vector3, velocity: Vector3)
## A shot landed. `body` is null when it hit ground or nothing.
signal impact(body: Node, at: Vector3)
signal manned_changed(manned: bool)

## Drop onto the terrain on ready. Turn off to keep a hand-placed height - a cannon on a deck,
## say, where the ground underneath is not the island.
@export var sit_on_ground := true:
	set(value):
		sit_on_ground = value
		if is_inside_tree():
			_settle()

## Tilt to match the slope. A carriage sitting dead level on a hillside has one wheel in the
## air; matching the ground normal puts all four down. Off by default because on flat ground it
## is invisible and on a steep slope a cannon leaning over can look wrong rather than right.
@export var follow_slope := false:
	set(value):
		follow_slope = value
		if is_inside_tree():
			_settle()

## How much of the slope to take. 1.0 lies flat on the hill, 0.0 stays upright.
@export_range(0.0, 1.0) var slope_weight := 0.8

@export var collide := true

## Shrinks the collision box off the mesh bounds. The model's widest point is the wheel hubs;
## a box on the full width feels like an invisible wall a hand wider than the cannon looks.
@export_range(0.5, 1.0) var collision_fit := 0.92

var _body: StaticBody3D = null
var _rider: Node3D = null
var _elevation := 12.0
var _bearing := Vector3.FORWARD
var _charging := false
var _drag_from := 0.0
var _elevation_at_press := 0.0
var _cooldown := 0.0
var _barrel: Node3D = null
var _barrel_rest := Basis.IDENTITY


func _ready() -> void:
	_settle()
	# Sit at the resting elevation from the start. Without this the barrel shows whatever angle
	# the model was authored at until somebody mans the gun, and then snaps to `rest_elevation`
	# on the first press. This model is 2 degrees nose-down at rest, which reads as a cannon
	# that is drooping.
	_elevation = rest_elevation
	_swing_barrel()
	if not Engine.is_editor_hint():
		# Joined at runtime rather than ticked in the scene file, so a cannon dropped anywhere
		# is found without anyone remembering to set a group on it.
		add_to_group("cannons")


## The union of every child mesh's bounds, in THIS node's space. Returns an empty AABB when
## there is no mesh yet, which happens in the editor for a frame or two after instancing.
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		# The mesh's own AABB, carried up through however many transforms sit between that
		# node and this one. get_aabb() is in the mesh's space, not ours.
		var local := global_transform.affine_inverse() * mesh_node.global_transform
		var here := local * mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


func _settle() -> void:
	var box := bounds()
	if box.size == Vector3.ZERO:
		return
	if collide:
		_build_body(box)
	if sit_on_ground:
		_drop_to_ground(box)


func _build_body(box: AABB) -> void:
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = Layers.bit(Layers.WORLD)
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size * collision_fit
	shape.shape = box_shape
	shape.position = box.position + box.size * 0.5
	_body.add_child(shape)
	add_child(_body)
	# No owner on purpose - see the note at the top. A node with an owner is saved into the
	# scene; this one is rebuilt from the mesh every time and has no business being in the file.


func _drop_to_ground(box: AABB) -> void:
	var terrain := _find_terrain()
	if terrain == null:
		return
	var at := global_position
	var ground: float = terrain.height_at(at.x, at.z)
	# box.position.y is the BOTTOM of the mesh relative to this node, and it is not zero - the
	# imported model's node sits away from its own geometry. Subtracting it is what puts the
	# wheels on the ground rather than the node origin.
	global_position = Vector3(at.x, ground - box.position.y, at.z)

	if not follow_slope:
		return
	var up: Vector3 = terrain.call("_surface_normal", at.x, at.z) if \
			terrain.has_method("_surface_normal") else Vector3.UP
	if up.length() < 0.01:
		return
	up = Vector3.UP.slerp(up.normalized(), slope_weight)
	# Keep the way it is pointing, change only which way is up.
	var facing := -global_transform.basis.z
	var side := up.cross(facing)
	if side.length() < 0.001:
		return
	side = side.normalized()
	global_transform.basis = Basis(side, up, side.cross(up)).orthonormalized()


func _find_terrain() -> Node:
	var node := get_parent()
	while node != null:
		var found := node.get_node_or_null("Terrain")
		if found != null and found.has_method("height_at"):
			return found
		node = node.get_parent()
	return null


# --- Manning and aiming -------------------------------------------------------------------
#
# The control scheme, in one place:
#   the cursor gives a BEARING - which way the gun is pointed, from a world point under it
#   press and drag gives an ELEVATION - how high it is angled, and so how far it throws
#   release fires
#
# Pressing LOCKS the bearing by default. Without that lock the two fight each other: dragging
# upward to raise the angle also moves the cursor, which re-aims the gun, so you cannot set an
# angle without spoiling the direction you set it for. `lock_bearing_on_press` turns that off
# for anyone who wants to try the looser version.


func is_manned() -> bool:
	return _rider != null and is_instance_valid(_rider)


func rider() -> Node3D:
	return _rider


## How close the player has to be to take hold of it. Measured from the mesh, so a bigger
## cannon is grabbable from further away without a second number to keep in step.
func reach() -> float:
	var box := bounds()
	return maxf(box.size.x, box.size.z) * 0.5 + 1.8


func man(who: Node3D) -> bool:
	if is_manned() or who == null:
		return false
	_rider = who
	_elevation = rest_elevation
	_swing_barrel()
	_charging = false
	manned_changed.emit(true)
	return true


func leave() -> void:
	if not is_manned():
		return
	_rider = null
	_charging = false
	manned_changed.emit(false)


func elevation() -> float:
	return _elevation


## The barrel, if this model has one. Found by measurement rather than by name, because the
## imported part names are Tripo GUIDs and identical for both pieces.
func barrel() -> Node3D:
	if _barrel != null and is_instance_valid(_barrel):
		return _barrel
	var best: MeshInstance3D = null
	var longest := 0.0
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		if barrel_name != "" and mesh_node.name == barrel_name:
			best = mesh_node
			break
		var size: Vector3 = mesh_node.mesh.get_aabb().size
		var span: float = maxf(size.x, maxf(size.y, size.z))
		if span > longest:
			longest = span
			best = mesh_node
	if best != null:
		_barrel = best
		_barrel_rest = best.transform.basis
	return _barrel


## Swing the barrel to the current elevation.
##
## Composed from a STORED REST basis rather than added to whatever the barrel is currently at.
## Reading a rotation back out and adding to it accumulates error every frame and drifts - the
## shark's spine had exactly this problem before it was rebuilt from a stored quaternion.
##
## Rotating about local X lifts a -Z muzzle upward. That works here only because the barrel's
## origin sits on its trunnion, put there in Blender: rotate about any other point and the
## barrel swings out of the carriage instead of pivoting in it.
func _swing_barrel() -> void:
	if not elevate_barrel:
		return
	var arm := barrel()
	if arm == null:
		return
	arm.transform.basis = _barrel_rest.rotated(Vector3.RIGHT, deg_to_rad(_elevation))


func is_charging() -> bool:
	return _charging


func can_fire() -> bool:
	return is_manned() and _cooldown <= 0.0


## 0 while it is being reloaded, 1 when it is ready. Same shape as Gun.reload_fraction, so the
## crosshair can show a cannon's reload with the ring it already draws for the pistol.
func reload_fraction() -> float:
	if reload_seconds <= 0.0:
		return 1.0
	return clampf(1.0 - _cooldown / reload_seconds, 0.0, 1.0)


## Point the gun at a world position. Only the horizontal part is taken - the height of the
## point says nothing about the angle, which is what the drag is for.
func aim_towards(point: Vector3) -> void:
	if _charging and lock_bearing_on_press:
		return
	var along := point - global_position
	along.y = 0.0
	if along.length() > 0.001:
		_bearing = along.normalized()


func press(screen_y: float) -> void:
	if not can_fire():
		return
	_charging = true
	_drag_from = screen_y
	_elevation_at_press = _elevation


## Screen pixels upward raise the angle. Y grows downward on screen, so the subtraction is that
## way round on purpose.
func drag(screen_y: float) -> void:
	if not _charging:
		return
	_elevation = clampf(_elevation_at_press + (_drag_from - screen_y) * elevation_per_pixel,
			min_elevation, max_elevation)
	_swing_barrel()


func release() -> Node:
	if not _charging:
		return null
	_charging = false
	var shot := fire()
	_elevation = rest_elevation
	_swing_barrel()
	return shot


## The launch vector the current bearing and elevation describe. Separated out because this is
## the single thing a different control scheme would replace - solving for the angle that lands
## on a chosen point, say - and everything else here would stay as it is.
func aim_velocity() -> Vector3:
	var side := _bearing.cross(Vector3.UP).normalized()
	if side.length() < 0.001:
		side = Vector3.RIGHT
	# Positive, not negative. `side` is bearing x UP, which for a bearing of -Z comes out as
	# +X, and a positive turn about +X lifts -Z upward. The other sign fires into the dirt at
	# the gun's own feet, which looks like a range problem rather than a sign one.
	var up_tilt := _bearing.rotated(side, deg_to_rad(_elevation))
	return up_tilt.normalized() * muzzle_speed


## Where the ball appears. Taken along the FIRING direction rather than off the model's own
## axis: this mesh comes from Tripo with a rotation and a 60 m offset baked into its node, so
## it has no forward that can be trusted.
func muzzle() -> Vector3:
	var box := bounds()
	# The mesh's own centre in world space, not the node origin - on this model those are
	# sixty metres apart, so a muzzle measured from the node would be out at sea.
	var middle := to_global(box.position + box.size * 0.5)
	return middle + _bearing * muzzle_reach + Vector3.UP * muzzle_height


func fire() -> Node:
	if not can_fire():
		return null
	_cooldown = reload_seconds
	var from := muzzle()
	var velocity := aim_velocity()

	var mask := Layers.bit(Layers.WORLD) | Layers.bit(Layers.DAMAGEABLE)
	var shot := Cannonball.launch(get_parent(), from, velocity, mask)
	shot.gravity = shot_gravity
	shot.landed.connect(_on_landed)

	MuzzleFlash.burst(get_parent(), from, velocity.normalized())
	fired.emit(from, velocity)
	return shot


func _on_landed(body: Node, at: Vector3, normal: Vector3) -> void:
	# Something always shows, whatever it hit. The pistol's listener returns early when a shot
	# meets terrain, so a pistol ball into the sand produces nothing at all; a cannon landing
	# short with no puff of dirt would leave you unable to correct your next shot.
	HitSpark.burst(get_parent(), at, normal, Color(0.62, 0.53, 0.38), 2.2)
	MuzzleFlash.burst(get_parent(), at, normal)
	_hurt_around(at)
	impact.emit(body, at)


## Splash. Masked to DAMAGEABLE and nothing else.
##
## The sword learned this the expensive way: its query went out unmasked, and when the terrain
## collider's resolution doubled, its triangles filled the 16-result cap on their own - 16 of
## 16 results were terrain and the grunt standing in front of the blade was at index 17. A cap
## on an unmasked query is not a limit, it is a lottery.
##
## The cap here is generous rather than tight for the same reason: a blast in the middle of a
## crowd should not silently drop the people at the back.
func _hurt_around(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var ball := SphereShape3D.new()
	ball.radius = blast_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = ball
	query.transform = Transform3D(Basis.IDENTITY, at)
	query.collision_mask = Layers.bit(Layers.DAMAGEABLE)
	query.collide_with_bodies = true
	var seen := {}
	for touch in space.intersect_shape(query, 48):
		var body := touch.get("collider") as Node
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true
		if body.has_method("take_damage"):
			body.take_damage(damage, self)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	# Walking away lets go. The gun owns this rule rather than the captain, so there is one
	# place that decides who is holding it; the captain asks rider() rather than keeping a
	# second opinion that can go stale. A little past `reach` so standing on the edge of it
	# does not flicker between held and let go.
	if is_manned() and _rider.global_position.distance_to(global_position) > reach() * 1.6:
		leave()
