extends CharacterBody3D
## Something that can be hit, so the captain's cutlass has a reason to exist.
##
## It does not chase, attack or defend itself yet - it stands there, takes damage, and falls
## over. That is deliberate: it makes the damage loop testable on its own, before any of it
## depends on an AI being right.
##
## Everything is built in code, including the collider, so an enemy can be spawned from a
## script without a scene to place. It borrows the captain's own model until the grunt exists;
## swap model_path and the rest carries over, because the clips are Mixamo-named either way.

const HealthBar = preload("res://health_bar.gd")

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

@export_group("Animation")
## Falls back to the walk if there is no idle, because the grunt's first set of animations is
## walk, slash and death with nothing to stand still in. A clip that does not exist leaves the
## model in its bind pose, which for a Mixamo rig is a T-pose - arms out, staring ahead. A
## marching target reads as a placeholder; a T-posed one reads as broken.
@export var clip_idle := "idle"
@export var clip_walk := "walk"
@export var clip_death := "death"
@export var clip_blend := 0.15
## How long the body takes to fall over when the model has no death clip, which is the case
## while the grunt is still unrigged. Without it a killed target goes on standing there and
## there is no way to tell a hit landed - which is the one thing target practice has to show.
@export var topple_time := 0.5

## Matches the player's capsule, so a body of the same build stands the same way on the ground.
const RADIUS := 0.35
const HEIGHT := 1.9

var _health := 0
var _dead := false
var _anim: AnimationPlayer
var _clip := ""
var _body: Node3D
## Seconds into the fall, and how far to raise the body so a model lying on its back rests on
## the ground rather than sinking half into it. Measured from the mesh, not assumed.
var _toppled := -1.0
var _lie_lift := 0.0
var _bar: Sprite3D
var _bar_placed := false


func _ready() -> void:
	_health = max_health
	_build_collider()
	_build_body()
	_play(_standing_clip())


func health() -> int:
	return _health


func is_dead() -> bool:
	return _dead


## Called by anything that hits this - see the blade hitbox in player.gd. Duck-typed on
## purpose: the hitbox asks whether a body has this method rather than what class it is, so
## breakable crates and the player answer the same way without a shared base class.
func take_damage(amount: int, _from: Node = null) -> void:
	if _dead:
		return
	_health = maxi(0, _health - amount)
	if _bar != null:
		_bar.set_fraction(float(_health) / float(maxi(max_health, 1)))
	damaged.emit(amount, _health)
	if _health == 0:
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
	if _anim != null and _anim.has_animation(clip_death):
		_play(clip_death)
	else:
		# No rig, so nothing can be animated - tip the whole model over instead. Starting the
		# clock here rather than setting a flag keeps the fall in one place in _physics_process.
		_toppled = 0.0
	died.emit()


func _physics_process(delta: float) -> void:
	# Falls whether alive or dead, so a body dropped above the ground still lands on it.
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()
	if not _bar_placed:
		_place_bar()
	_fall_over(delta)


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
		if candidate != "" and _anim != null and _anim.has_animation(candidate):
			return candidate
	return ""


func _play(name_: String) -> void:
	if _anim == null or name_ == "" or name_ == _clip or not _anim.has_animation(name_):
		return
	_anim.play(name_, clip_blend)
	_clip = name_


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
		elif node is AnimationPlayer and _anim == null:
			_anim = node as AnimationPlayer
	_flatten_materials(model)
	# glTF carries no loop flag, so a cycle would otherwise stop on its last frame and the body
	# would freeze mid-stride. The death clip is deliberately not in here: it ends on the floor
	# and should stay there.
	for cycle in [clip_idle, clip_walk]:
		if cycle != "" and _anim != null and _anim.has_animation(cycle):
			_anim.get_animation(cycle).loop_mode = Animation.LOOP_LINEAR
	_measure_body.call_deferred()
	_add_bar()


## Hangs the health bar above the body, at a default height for now.
##
## The real height needs the head bone, and the skeleton has not posed yet - see _place_bar,
## which does it on the first physics frame instead.
func _add_bar() -> void:
	_bar = HealthBar.new()
	_bar.name = "HealthBar"
	add_child(_bar)
	_bar.position = Vector3(0.0, 1.8 + bar_clearance, 0.0)
	_bar.set_fraction(float(_health) / float(maxi(max_health, 1)))


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
