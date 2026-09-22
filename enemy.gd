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

signal damaged(amount: int, remaining: int)
signal died

@export var model_path := "res://art/models/captain.glb"
@export var max_health := 3
## Movement rotates nothing yet, but a model authored facing the other way still needs turning.
@export var model_yaw := 0.0
@export var gravity := 30.0

@export_group("Animation")
@export var clip_idle := "idle"
@export var clip_death := "death"
@export var clip_blend := 0.15

## Matches the player's capsule, so a body of the same build stands the same way on the ground.
const RADIUS := 0.35
const HEIGHT := 1.9

var _health := 0
var _dead := false
var _anim: AnimationPlayer
var _clip := ""
var _body: Node3D


func _ready() -> void:
	_health = max_health
	_build_collider()
	_build_body()
	_play(clip_idle)


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
	damaged.emit(amount, _health)
	if _health == 0:
		_die()


func _die() -> void:
	_dead = true
	# Stop colliding with anything, or the corpse keeps blocking the path and the player walks
	# into an invisible wall where it fell. Deferred because this is reached from inside a
	# physics query - the blade's overlap check - and changing collision state mid-query is
	# what makes Godot complain about flushing queries.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	_play(clip_death)
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
	if _anim and _anim.has_animation(clip_idle):
		# glTF carries no loop flag, so an idle would otherwise stop on its last frame.
		_anim.get_animation(clip_idle).loop_mode = Animation.LOOP_LINEAR


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
