extends CharacterBody3D
## A grunt: stands about until the player comes near, walks over, and swings at him.
##
## Three states and no more - idle, close the gap, swing - chosen so the shape of a fight can be
## felt before any of it depends on pathfinding or perception being right. He walks straight at
## you and bumps into whatever is between; steering around it is a separate problem.
##
## Everything is built in code, including the collider and the weapon, so a grunt can be spawned
## from a script with no scene to place and no prefab to keep in step.

const HealthBar = preload("res://ui/health_bar.gd")

signal damaged(amount: int, remaining: int)
signal died

@export var model_path := "res://art/models/grunt.glb"
## NOTE: the grunt's size is NOT set here, and cannot be. He is rigged now, so the scale has to
## go in nodes/root_scale in art/models/grunt.glb.import, currently 1.794 - which puts him at
## 90% of the captain's height, measured toe bone to head bone. .import files are gitignored,
## so a fresh clone gets root_scale 1.0 back and a grunt the size of a mouse.
##
## The static version of this model had its scale baked into the file instead, which is better
## because it survives a clone. That stopped being possible the moment he was rigged: a scale
## on the root of a skinned mesh leaves its inverse-bind matrices behind and tears it apart.
@export var max_health := 3
## Movement rotates nothing yet, but a model authored facing the other way still needs turning.
@export var model_yaw := 0.0
@export var gravity := 30.0
## Which bone the health bar is measured from, and how far above it the bar sits.
@export var head_bone := "mixamorig_Head"
@export var bar_clearance := 0.35

@export_group("Combat")
## Who to chase. main.gd sets this to the player; left empty the grunt just stands there, which
## is what the target-practice version did and is still useful for testing damage on its own.
var target: Node3D
## Starts following inside this, stops and swings inside attack_range. The gap between them is
## where the walk happens, so a grunt that is already in reach never takes a step.
@export var aggro_range := 16.0
## Measured against the blade, not picked. During the hit window the tip reaches 1.00 m from
## the grunt's centre, and the player's capsule adds 0.35, so contact is possible out to 1.35 m
## between origins. The two capsules touch at 0.70 m. Anything above 1.35 and the grunt stops
## short and swings at air, which was the first version of this: he closed, swung, played the
## whole animation and never once connected.
@export var attack_range := 1.00
## Deliberately below the player's 4.8 walk, so running away works. A grunt that matches your
## speed can never be escaped, only killed.
@export var speed := 2.6
@export var turn_speed := 7.0
@export var damage := 1
## Rest between swings. Without it a grunt in range attacks every frame the cooldown allows and
## reads as a blender rather than a pirate.
@export var attack_cooldown := 1.4
@export var clip_attack := "slash"
## Same numbers as the captain, and not by assumption - the grunt's own slash was measured and
## its hand speed peaks at 1.23s with the half-peak band running 1.13s to 1.37s, against the
## captain's 1.17 to 1.37. It is the same Mixamo clip on a different rig.
@export var attack_start := 0.95
@export var attack_length := 0.75
@export var hit_from := 0.20
@export var hit_to := 0.42
## How far a landed hit carries. A little beyond attack_range so someone backing away as the
## swing comes down still gets clipped - the alternative is that walking backwards makes you
## invulnerable.
##
## Kept close to the captain's own reach on purpose. The player's blade stops connecting past
## about 1.0 m head-on, measured by swinging at a grunt from a series of distances, so a grunt
## who struck from 1.7 m could hit from outside anywhere the player could answer from. Whatever
## these numbers become, they want to stay in step with that.
@export var hit_reach := 1.35
## Sparks where the grunt's blade lands. Red, against the captain's gold, so taking a hit and
## landing one never look like the same event.
@export var hit_colour := Color(0.95, 0.30, 0.22)
## How hard a hit shoves this body back, in metres per second, and how long it is unable to act
## afterwards. The shove is what makes a blow land rather than merely register; the pause is
## what stops a grunt walking back into you the same frame he was cut, which reads as him not
## having noticed.
@export var knockback := 3.6
@export var stagger := 0.35
## How fast the shove bleeds off. Higher stops it sooner.
@export var knock_damping := 14.0

@export_group("Weapon")
@export var show_weapon := true
@export var weapon_bone := "mixamorig_RightHand"
## Shorter and plainer than the captain's, so the two read apart at a glance.
@export var sword_size := Vector3(0.62, 0.05, 0.016)
## Y runs towards the fingertips. The grunt's middle knuckle measures 9.6 cm along it, against
## the captain's 5.2 - different rig, bigger hands - so his grip sits further out than 0.07.
@export var sword_offset := Vector3(0.25, 0.12, 0.0)
@export var sword_rotation := Vector3.ZERO
@export var sword_colour := Color(0.58, 0.56, 0.54)

@export_group("Animation")
## The idle exists now, but the fallback to the walk stays. A clip that is missing leaves the
## model in its bind pose, which for a Mixamo rig is a T-pose - arms out, staring ahead - and
## the next enemy type will arrive with an incomplete set the same way this one did. Marching
## on the spot reads as a placeholder; a T-pose reads as broken.
@export var clip_idle := "idle"
@export var clip_walk := "walk"
@export var clip_death := "death"
@export var clip_blend := 0.15
## How long the body takes to fall over when the model has no death clip. Unused now that the
## grunt has one, and kept for the next model that arrives unrigged: without it a killed body
## goes on standing, and there is no way to tell a hit landed.
@export var topple_time := 0.5

## Matches the player's capsule, so a body of the same build stands the same way on the ground.
const RADIUS := 0.35
const HEIGHT := 1.9

## Health and knockback are components - see actors/parts, shared with the captain. Two
## separate implementations of these is how they drifted apart the first time.
var _hp: Health
var _knock: Knockback
var _dead := false
## The model's clips - see actors/parts/clips.gd, shared with the captain.
var _clips: Clips
var _body: Node3D
## Seconds into the fall, and how far to raise the body so a model lying on its back rests on
## the ground rather than sinking half into it. Measured from the mesh, not assumed.
var _toppled := -1.0
var _lie_lift := 0.0
var _bar: Sprite3D
var _bar_placed := false
## Seconds left in the current swing, and until the next one is allowed.
var _attack := 0.0
var _cooldown := 0.0
## The cutlass - see actors/parts/sword.gd. Typed, so its hitbox is reachable by name.
var _sword: Sword
var _blade: Area3D
## Everything hit by the current swing, so one swing cannot land twice on the same body.
var _struck: Array[Node] = []


func _ready() -> void:
	_hp = Health.new()
	_hp.name = "Health"
	_hp.maximum = max_health
	add_child(_hp)
	# The bar follows the number rather than being told separately at every call site. That is
	# most of what a component buys here: nothing has to remember to update it.
	_hp.changed.connect(func(_current: int, _maximum: int) -> void:
		if _bar != null:
			_bar.set_fraction(_hp.fraction()))
	_knock = Knockback.new()
	_knock.name = "Knockback"
	_knock.strength = knockback
	_knock.recovery = stagger
	_knock.damping = knock_damping
	add_child(_knock)
	_clips = Clips.new()
	_clips.name = "Clips"
	_clips.blend = clip_blend
	add_child(_clips)
	_build_collider()
	_build_body()
	_play(_standing_clip())


func health() -> int:
	return _hp.current()


## Whether this one has had its AI taken away because it was just hit.
func is_staggered() -> bool:
	return _knock.staggered()


func is_dead() -> bool:
	return _dead


## Called by anything that hits this - see the blade hitbox in captain.gd. Duck-typed on
## purpose: the hitbox asks whether a body has this method rather than what class it is, so
## breakable crates and the player answer the same way without a shared base class.
func take_damage(amount: int, _from: Node = null) -> void:
	if _dead:
		return
	# Shoved directly away from whoever swung, so the push reads as coming from the blow.
	_knock.hit_from(global_position, _from)
	var finished := _hp.take(amount)
	damaged.emit(amount, _hp.current())
	if finished:
		_die()


func _die() -> void:
	_dead = true
	# Clear the layer so nothing can hit or be blocked by the corpse - otherwise the player
	# walks into an invisible wall where it fell, and the blade keeps finding a dead body.
	#
	# The MASK stays. Clearing that too was the first version of this, and it stopped the body
	# colliding with the ground as well: the corpse fell straight through the terrain and kept
	# going, forty metres down within three seconds. Layer is what others see; mask is what this
	# body runs into. Only the first one should go.
	#
	# Deferred because this is reached from inside a physics query - the blade's overlap check -
	# and changing collision state mid-query is what makes Godot complain about flushing.
	set_deferred("collision_layer", 0)
	if _bar != null:
		_bar.hide()
	if _clips.has(clip_death):
		_play(clip_death)
	else:
		# No rig, so nothing can be animated - tip the whole model over instead. Starting the
		# clock here rather than setting a flag keeps the fall in one place in _physics_process.
		_toppled = 0.0
	died.emit()


## Idle until the player is worth noticing, walk to close the gap, swing when in reach.
##
## There is no pathfinding and no line of sight: a grunt walks straight at you and bumps into
## whatever is between. That is honest for a first pass - the shape of the fight is what wants
## testing, and steering around a rock is a separate problem with its own failure modes.
func _physics_process(delta: float) -> void:
	# Falls whether alive or dead, so a body dropped above the ground still lands on it.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_attack = maxf(0.0, _attack - delta)
	_cooldown = maxf(0.0, _cooldown - delta)
	_knock.tick(delta)

	var wants := Vector3.ZERO
	# Staggered: no chasing, no swinging, and a swing already under way is dropped. Being hit
	# has to interrupt something or there is no reason to hit first.
	if _knock.staggered():
		_attack = 0.0
	elif not _dead:
		var towards := _towards_target()
		var distance := towards.length()
		if _attack > 0.0:
			# Planted mid-swing. Walking through your own strike reads as a shove, not a cut,
			# and it lets a grunt push the player out of the blade he is currently swinging.
			_face(towards, delta)
			_strike()
		elif distance > 0.0 and distance <= attack_range and _cooldown <= 0.0:
			_face(towards, delta)
			_swing()
		elif distance > attack_range and distance <= aggro_range:
			wants = towards / distance
			_face(towards, delta)

	var shove: Vector3 = _knock.shove()
	velocity.x = wants.x * speed + shove.x
	velocity.z = wants.z * speed + shove.z
	move_and_slide()
	if not _bar_placed:
		_place_bar()
	_fall_over(delta)
	_update_animation(wants.length() > 0.01)


## Horizontal vector to the target, or zero when there is nothing to chase or it is already
## dead. Height is dropped so a grunt on a slope does not try to walk into the hillside.
func _towards_target() -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if target.has_method("is_dead") and target.is_dead():
		return Vector3.ZERO
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	return to


func _face(towards: Vector3, delta: float) -> void:
	if _body == null or towards.length() < 0.01:
		return
	var yaw := atan2(towards.x, towards.z)
	_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)


func _swing() -> void:
	if not _clips.has(clip_attack):
		return
	_attack = attack_length
	_cooldown = attack_length + attack_cooldown
	_struck.clear()


## Lands the hit, if the target is still in front and in reach when the strike peaks.
##
## This is a range and facing test, not an overlap of the blade - and that is deliberate, after
## the overlap version never connected once. The clip is Mixamo's "Stable Sword Inward Slash",
## a cut that sweeps across the body: through the whole strike window its tip sits 0.37 to
## 0.51 m out to the grunt's LEFT and between -0.15 and +0.14 m forward. It never reaches out
## in front of him at all, so a blade volume only ever touched the grunt's own capsule.
##
## The player keeps the overlap version because he aims his own swing and wants the blade to be
## the truth. An AI that closes to a fixed distance does not need that, and a hit that depends
## on an animation's reach matching a number somewhere else is a hit that silently stops
## working when the animation is replaced.
func _strike() -> void:
	var elapsed := attack_length - _attack
	if elapsed < hit_from or elapsed > hit_to or not _struck.is_empty():
		return
	var towards := _towards_target()
	var distance := towards.length()
	if distance <= 0.0 or distance > hit_reach:
		return
	# Has to be roughly in front. Without this a grunt lands hits on someone who has already
	# walked past him, because the swing is still running while he turns.
	if _body != null:
		var facing := Vector3(sin(_body.rotation.y), 0.0, cos(_body.rotation.y))
		if facing.dot(towards / distance) < 0.35:
			return
	if target.has_method("take_damage"):
		_struck.append(target)
		target.take_damage(damage, self)
		var contact: Vector3 = target.global_position + Vector3.UP * 1.0 				- (towards / distance) * 0.35
		HitSpark.burst(get_parent(), contact, towards, hit_colour)


## Picks the clip for what this grunt is doing. The fallback chain matters while the animation
## set is incomplete: no idle yet means the walk stands in, and a missing clip would otherwise
## leave a Mixamo rig in its T-pose.
func _update_animation(moving: bool) -> void:
	if _dead:
		return
	var wanted := ""
	if _attack > 0.0:
		wanted = clip_attack
	elif moving:
		wanted = clip_walk
	else:
		wanted = _standing_clip()
	var was := _clips.current()
	if _clips.play(wanted) == clip_attack and _clips.current() != was:
		# The swing is entered part-way in: the clip spends its first second winding up, and
		# starting at zero means the grunt stands still for a beat before anything happens.
		_clips.seek(attack_start)


## Tips a body with no death clip onto its back.
##
## The pivot is the node's origin, which is at the feet, so this rotates the way a felled tree
## does rather than spinning about the middle. Rotating a standing figure a quarter turn swaps
## its height for its depth, so the part that was in front of the origin ends up below the
## ground - hence the lift, taken from the model's own bounds rather than picked.
func _fall_over(delta: float) -> void:
	if _toppled < 0.0 or _toppled >= topple_time or _body == null:
		return
	_toppled = minf(topple_time, _toppled + delta)
	var through := _toppled / topple_time
	# Fast at first and settling at the end, which is how something heavy goes over. A constant
	# rate reads as a door swinging shut.
	var eased := 1.0 - pow(1.0 - through, 3.0)
	_body.rotation.x = deg_to_rad(-90.0 * eased)
	_body.position.y = _lie_lift * eased


## Whatever this body should be doing while it waits: the idle if there is one, else the walk.
func _standing_clip() -> String:
	for candidate in [clip_idle, clip_walk]:
		if _clips.has(candidate):
			return candidate
	return ""


func _play(name_: String) -> void:
	_clips.play(name_)


func _build_collider() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Collider"
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	# The node's origin sits at the feet, same as the player, so spawning at a terrain height
	# puts it on the ground rather than half buried.
	shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	add_child(shape)


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	if not ResourceLoader.exists(model_path):
		push_warning("enemy.gd: no model at %s, this one is invisible." % model_path)
		return
	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	model.name = "Model"
	model.rotation.y = deg_to_rad(model_yaw)
	_body.add_child(model)
	for node in _descendants(model):
		# Layer 20 is the overhead water-interaction camera; anything visible has to be on it
		# or the water loses this body's footprint. Same rule as the player.
		if node is VisualInstance3D:
			(node as VisualInstance3D).set_layer_mask_value(20, true)
		elif node is AnimationPlayer and not _clips.ready():
			_clips.use(node as AnimationPlayer)
	_flatten_materials(model)
	# glTF carries no loop flag, so a cycle would otherwise stop on its last frame and the body
	# would freeze mid-stride. The death clip is deliberately not in here: it ends on the floor
	# and should stay there.
	for cycle in [clip_idle, clip_walk]:
		if _clips.has(cycle):
			_clips.animation(cycle).loop_mode = Animation.LOOP_LINEAR
	_measure_body.call_deferred()
	_add_bar()
	_attach_weapon(model)


## Gives the grunt the same kind of placeholder blade the captain carries, so he can swing back.
func _attach_weapon(model: Node3D) -> void:
	if not show_weapon:
		return
	var skeleton: Skeleton3D = null
	for node in _descendants(model):
		if node is Skeleton3D:
			skeleton = node as Skeleton3D
			break
	var blade := Sword.new()
	blade.name = "Sword"
	if not blade.setup(skeleton, weapon_bone, sword_size, sword_offset, sword_rotation,
			sword_colour):
		blade.free()
		return
	_sword = blade
	_blade = blade.hitbox


## Hangs the health bar above the body, at a default height for now.
##
## The real height needs the head bone, and the skeleton has not posed yet - see _place_bar,
## which does it on the first physics frame instead.
func _add_bar() -> void:
	_bar = HealthBar.new()
	_bar.name = "HealthBar"
	add_child(_bar)
	_bar.position = Vector3(0.0, 1.8 + bar_clearance, 0.0)
	_bar.set_fraction(_hp.fraction())


## Moves the bar to sit just above the head, once there is a posed skeleton to ask.
##
## The height comes from the head bone. The obvious route - the mesh's AABB - does not work on
## a rigged body: that box is in the skin's own space while the render is driven by the
## skeleton, so it reports this grunt as two centimetres tall.
##
## This runs on the first physics frame rather than deferred from _ready, which was the first
## attempt and put the bar around knee height. Deferring is not long enough: the skeleton had
## not posed, so the bone reported the body's own origin and the measurement came out as zero.
##
## Once placed the bar stays at a fixed height rather than following the head, so it does not
## bob through the walk cycle or ride the body down as it dies.
func _place_bar() -> void:
	_bar_placed = true
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton: Skeleton3D = skeletons[0]
	var bone := skeleton.find_bone(head_bone)
	if bone == -1:
		return
	# get_bone_global_pose, not get_bone_global_rest. The two are in different conventions on
	# this rig: the pose comes back with up on -Z, which is what the skeleton's own transform
	# expects, while the rest comes back with up on +Y. Feeding the rest through that transform
	# put the bar at the grunt's feet, because its height landed on an axis the rotation then
	# pointed sideways.
	#
	# The cost is that this reads the head mid-stride, and it bobs about 10 cm through a walk
	# cycle. Every enemy is placed on the same frame so they agree with each other, and 10 cm
	# above a floating bar is not something anyone will see.
	var head: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
	var top := head.y - global_position.y
	# A head that measures at or below the feet means the pose still is not ready; the default
	# set in _add_bar is a better answer than a bar around the ankles.
	if top > 0.2:
		_bar.position = Vector3(0.0, top + bar_clearance, 0.0)


## Works out how far a felled body has to rise to lie on the ground, from the model's own
## bounds. Deferred because a node's global transform is not settled the moment it is added,
## and the model's scale is part of what is being measured.
func _measure_body() -> void:
	if _body == null:
		return
	var bounds := AABB()
	var started := false
	var into_body := _body.global_transform.affine_inverse()
	for node in _descendants(_body):
		if node is VisualInstance3D:
			var visual := node as VisualInstance3D
			var box: AABB = (into_body * visual.global_transform) * visual.get_aabb()
			bounds = box if not started else bounds.merge(box)
			started = true
	if not started:
		return
	# A quarter turn about X maps the model's depth onto the vertical, so whatever sat furthest
	# in front of the origin is what ends up furthest below the ground.
	_lie_lift = maxf(bounds.end.z, 0.0)


## The same flattening the captain gets, so an enemy does not turn up in a different world.
##
## This model arrives as a full PBR set - base colour, metallic/roughness and a normal map -
## while the captain carries base colour alone. Left as exported it would be the shinier, more
## detailed of the two, standing next to a hero rendered flat, which reads as the enemy being
## from a different game rather than the same one.
##
## It only goes so far. This texture still has its lighting baked in, unlike the captain's, so
## it is being lit twice no matter what the material says. The fix for that is upstream: export
## it from Tripo with the lighting removed.
func _flatten_materials(model: Node3D) -> void:
	for node in _descendants(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				var flat: BaseMaterial3D = material.duplicate()
				flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				flat.metallic = 0.0
				flat.roughness = 1.0
				flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				mesh_node.set_surface_override_material(surface, flat)


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
