extends CharacterBody3D
## Bird's-eye third-person controller: WASD moves relative to the camera, Space jumps,
## Q/E orbit, mouse wheel zooms. The body is the captain model when it is present, and a
## blocky stand-in built from primitives when it is not.

## Normal movement. The walk clip plays below run_above, so this sits under it.
@export var speed := 4.8
## Held-Shift movement. Shift is also the dive key, but the two never apply at once - dive
## only means anything while swimming, and this only applies on land.
@export var sprint_speed := 9.0
@export var acceleration := 12.0
@export var turn_speed := 12.0
## Turns the model on the spot, in degrees, without touching which way the body steers.
## Movement rotates the body so its +Z faces the way you are going; a model authored facing
## the other way walks backwards. Set this to 180 if the captain moonwalks.
@export var model_yaw := 0.0
## Ignore scene lighting on the character and show the texture as painted. Worth trying when
## the texture already has its lighting baked in, which generated ones do. The cost is that he
## no longer darkens under a tree or at dusk.
@export var unshaded_model := false
## NOTE: the model's size is NOT set here. It is nodes/root_scale in art/models/captain.glb
## .import, currently 1.9 to match the collider.
##
## Two settings in that .import file have to be right, and .import files are gitignored, so a
## fresh clone gets the defaults back and both have to be set again:
##   nodes/root_scale=1.9                     without it the captain is one metre tall
##   animation/remove_immutable_tracks=false  the jump clip's hips are pinned to a constant,
##                                            and that stripper drops constant tracks, which
##                                            would snap the hips to the bone rest mid-jump
##
## Scaling it in code shatters it. A generator normalises to a unit cube, so the character
## arrives 1.0 units tall and the obvious fix is to scale the node on load - but that node
## has a Skeleton3D under it, and scaling above a skeleton breaks Godot's skinning: the mesh
## tears apart into stretched fragments. The importer rescales the bone rest poses along with
## the mesh, which is why it is the only place this belongs.

@export_group("Animation")
## Clip names as they appear in the model's AnimationPlayer. Mixamo names its downloads after
## the animation ("mixamo.com" for a single clip, or the pack's own names), so these are
## exports rather than constants - set them to whatever actually arrives.
@export var clip_idle := "idle"
@export var clip_walk := "walk"
@export var clip_run := "run"
@export var clip_jump := "jump"
@export var clip_fall := "fall"
@export var clip_swim := "swim"
## Plays once and holds its last frame - the captain staggers back and ends up flat on his
## back. Unlike the others this clip keeps its root motion, because falling over is supposed
## to move him: he travels about two thirds of his own height backwards on the way down. The
## collider stays where it was, so the body comes to rest beside it rather than inside it.
@export var clip_death := "death"
## Above this ground speed the run clip is used instead of the walk. Walking at run speed
## looks like the feet are skating, which is the usual giveaway that the blend is wrong.
@export var run_above := 5.5
## Seconds to cross-fade between clips. Too short snaps, too long makes turns feel sluggish.
@export var clip_blend := 0.15

@export_group("Weapon")
## A stand-in cutlass, built from a box so the sword clips have something to swing. Turn it
## off, or swap the mesh, once a real one is modelled.
@export var show_weapon := true
@export var weapon_bone := "mixamorig_RightHand"
## The cutlass. Leave empty and a plain box stands in, which is what this was before the model
## existed - useful for a character whose weapon is not modelled yet.
@export_file("*.glb") var sword_model := "res://art/models/weapons/cutlass.glb"
## Metres, along the hand bone's axes. Once a model is set this is the HITBOX only - nothing
## here is drawn - so it is deliberately fatter than the blade looks. Matched to the steel at
## 0.075 x 0.030 the captain hit once in three swings at a metre: the strike sweeps sideways
## and a three-centimetre plate slips straight past. Widening it costs nothing visually and is
## the difference between a sword that connects and one that does not.
@export var sword_size := Vector3(0.80, 0.12, 0.12)
## Metres, along the hand bone's own axes. X slides the box along the blade so a short length
## sits inside the hand as a grip. Y runs towards the fingertips, which is downwards while the
## arm hangs, and 0 puts the blade through the wrist joint rather than in the fist - the middle
## knuckle measures 5.2 cm along it and the joint past that 8.3 cm, so the hilt belongs between.
## With a model the origin is the pommel, not the middle of a box, so X sits near zero - a
## little back, to bury the pommel in the fist rather than float it at the fingertips.
@export var sword_offset := Vector3(-0.05, 0.07, 0.0)
## The cutlass is modelled tip-down: the point sits at the origin and the guard is three
## quarters of the way up, which the mesh's own cross-sections give away - 16.75 units wide at
## the guard against 2.3 along the blade. A quarter turn about Z lays it along the hand bone's
## +X with the pommel pointing backwards, and sword_grip then slides it forward so the hand
## holds the grip rather than the point.
##
## The X turn then rolls it about its own length. Laying the blade along +X gets it pointing
## the right way but says nothing about which way its flat faces, and it was authored facing
## the wrong one - so the captain carried a cutlass turned a quarter of a turn in his fist.
## Godot applies these in Y, X, Z order, so by the time X runs the blade is already on +X and
## this spins it in place rather than swinging it somewhere else.
@export var sword_rotation := Vector3(90.0, 0.0, 90.0)
## How far to slide the model along the blade so its grip meets the fist - the blade's length,
## for a sword whose origin is its tip.
@export var sword_grip := Vector3(0.80, 0.0, 0.0)
@export var sword_colour := Color(0.72, 0.74, 0.78)

@export_group("Combat")
@export var clip_attack := "slash"
## Where the swing starts inside the clip. Mixamo's "Stable Sword Inward Slash" runs 2.23s and
## spends its first second winding up; the strike itself peaks at 1.23s. Measured from how fast
## the right hand moves through the clip - the peak is 2.4x anything before it. Playing from
## zero means pressing attack does nothing visible for a second.
@export var attack_start := 0.95
## How long the swing owns the animation before walking and idling take it back. The strike and
## its follow-through fit in this; the clip's remaining recovery is not worth waiting through.
@export var attack_length := 0.75
## Seconds into the swing where the blade actually connects. Not guessed: the right hand's
## speed through the clip peaks at 1.23s, which is 0.28s after attack_start, and stays above
## half that peak from 1.17s to 1.37s. Those are the edges below. Outside them the blade is
## travelling to or from the strike and should pass through people harmlessly, or every swing
## lands the moment the button goes down and range stops meaning anything.
@export var hit_from := 0.20
@export var hit_to := 0.42
@export var damage := 1
@export var max_health := 5
## Sparks where the blade lands. Near-white, because the sand is warm and a gold spark measured
## only 33 luminance above it - invisible in practice. This one manages 59, at three and a half
## times the colour distance, and reads as steel besides.
@export var hit_colour := Color(0.93, 0.97, 1.0)
## Being hit shoves the captain back and takes the controls away for a moment. Deliberately
## shorter than the grunt's: losing control of your own character is far more irritating than
## watching someone else lose theirs, and a long stun turns two grunts into a death sentence.
@export var knockback := 4.2
@export var stagger := 0.22
## How fast the shove bleeds off while staggered, in metres per second squared.
@export var knock_damping := 9.0

@export_group("Jump feel")
## How high a full jump goes, in metres. The take-off speed is derived from it.
@export var jump_height := 1.6
## Gravity while rising. Real-world 9.8 feels like the moon in a game; this is ~2.5x that.
@export var rise_gravity := 26.0
## Gravity while falling. Heavier than the rise makes the arc snappy instead of floaty.
@export var fall_gravity := 38.0
## Releasing the button early cuts the jump short (this fraction of the rising speed is kept).
@export var short_hop_cut := 0.58
## Still allowed to jump this long after walking off an edge.
@export var coyote_time := 0.12
## A jump pressed this long before landing still fires on touchdown.
@export var jump_buffer := 0.15
@export var terminal_velocity := 45.0

@export_group("Swimming")
## Sea level in metres, set by main.gd from the terrain so the two cannot disagree.
@export var water_level := 0.0
## Wading turns into swimming once the water is this deep - about chest height.
@export var swim_depth := 1.3
@export var swim_speed := 5.5
## How hard the water pushes you back to the surface when you stop diving.
@export var buoyancy := 7.0
## Water resists: momentum from running does not carry far once you are in it.
@export var water_drag := 3.0
@export var wade_slowdown := 0.55
## Metres between footfalls. Shorter than a real stride on purpose - the walk clip lands two
## feet per cycle and one sound per cycle reads as limping.
@export var stride_length := 1.5

## Set by main.gd - movement is relative to whichever way the camera is facing.
var camera_rig: Node3D
## Set by main.gd on touch devices; its stick overrides the keyboard when in use.
var touch_controls: CanvasLayer

const Weapon = preload("res://actors/parts/weapon.gd")
const HitSpark = preload("res://actors/parts/hit_spark.gd")
const MODEL_PATH := "res://art/models/captain.glb"

@onready var _body: Node3D = $Body

## False when the model is missing and the blocky stand-in is standing in for it.
var _model_loaded := false
## The model's own AnimationPlayer, or null until it has clips on it.
var _anim: AnimationPlayer
## What is playing, so a clip is not restarted from the top every frame.
var _clip := ""
var _walk_time := 0.0
var _coyote := 0.0
var _buffered := 0.0
var _holding_jump := false
## Set by the touch dive button; the keyboard uses the "dive" action directly.
var _holding_dive := false
## True between die() and revive(). Checked before anything else each frame.
var _dead := false
## Seconds left in the current swing; zero when not attacking.
var _attack := 0.0
## The placeholder blade, so it can be swapped or hidden without rebuilding the body.
var _weapon: MeshInstance3D
## Overlap volume around the blade. Always monitoring; what changes is whether hits count.
var _blade: Area3D
## Everything already struck by the current swing, so one swing cannot hit the same body twice.
var _struck: Array[Node] = []
var _health := 0
var _stagger := 0.0
var _stride := 0.0
var _was_wet := false


## Take-off speed for the requested height: v = sqrt(2 * g * h).
## Emitted the moment die() is called, before the clip starts, so whatever is listening can
## fade the screen or start a respawn timer against the same frame.
signal died
signal revived
## Emitted when a swing starts, not when it connects. Whatever deals damage should wait for
## the blade to be somewhere useful rather than firing on the keypress.
signal attacked
## The blade reached something. Carries what was hit, so scoring or effects can hang off it.
signal hit(target: Node)
signal damaged(amount: int, remaining: int)
## A footfall. Emitted by distance covered rather than on a timer, so it keeps pace with a
## sprint without anything having to know how fast he is going.
signal stepped
## Crossing into water, either way. True going in.
signal splashed(entering: bool)


func is_attacking() -> bool:
	return _attack > 0.0


func health() -> int:
	return _health


## Duck-typed to match enemy.gd, so whatever ends up swinging at the captain does not need to
## know what he is either.
func take_damage(amount: int, _from: Node = null) -> void:
	if _dead:
		return
	_health = maxi(0, _health - amount)
	_stagger = stagger
	# Set as a single impulse on the velocity rather than added every frame. Adding it each
	# frame fed the previous frame's push back into move_toward's starting point, so the shove
	# compounded: the captain travelled 2.31 m where a grunt hit the same way travelled 0.43.
	if _from is Node3D:
		var away: Vector3 = global_position - (_from as Node3D).global_position
		away.y = 0.0
		if away.length() > 0.01:
			away = away.normalized() * knockback
			velocity.x = away.x
			velocity.z = away.z
	damaged.emit(amount, _health)
	if _health == 0:
		die()


## Applies the blade to anything inside it, once per swing per body.
##
## Overlaps are read every frame rather than waiting for body_entered, because a body can
## already be inside the blade when the window opens - standing close enough that the sword
## starts the strike overlapping them - and an entered signal that fired before the window
## never comes again.
func _strike() -> void:
	if _blade == null:
		return
	var elapsed := attack_length - _attack
	if _attack <= 0.0 or elapsed < hit_from or elapsed > hit_to:
		return
	for body in _blade.get_overlapping_bodies():
		if body == self or _struck.has(body):
			continue
		if body.has_method("take_damage"):
			_struck.append(body)
			body.take_damage(damage, self)
			# On the target, at chest height, thrown back the way the blow travelled. Spawned
			# on the scene rather than on either fighter so it does not ride the follow-through
			# or vanish when a body is freed.
			var towards: Vector3 = body.global_position - global_position
			towards.y = 0.0
			var contact: Vector3 = body.global_position + Vector3.UP * 1.0 					- towards.normalized() * 0.35
			HitSpark.burst(get_parent(), contact, towards, hit_colour)
			hit.emit(body)


## Starts a swing, if one is not already running. Movement is deliberately left alone - you can
## walk while swinging, and the clip simply owns the animation until it runs out.
func attack() -> void:
	if _dead or _attack > 0.0:
		return
	_attack = attack_length
	_struck.clear()
	attacked.emit()


func is_dead() -> bool:
	return _dead


## Stops the captain taking input and plays the death clip. Nothing in the game calls this
## yet - there is no health anywhere - so it is here for whatever does the hurting to call.
func die() -> void:
	if _dead:
		return
	_dead = true
	_buffered = 0.0
	_holding_jump = false
	died.emit()


func revive() -> void:
	if not _dead:
		return
	_dead = false
	_health = max_health
	_stagger = 0.0
	# Clearing this makes _update_animation treat the next clip as a change and play it. Without
	# it the captain stands back up still holding the last frame of his own death.
	_clip = ""
	revived.emit()


func _jump_velocity() -> float:
	return sqrt(2.0 * rise_gravity * jump_height)


## Connected to the touch jump button by main.gd (press and release).
func request_jump() -> void:
	_buffered = jump_buffer
	_holding_jump = true


func release_jump() -> void:
	_holding_jump = false


## Connected to the touch dive button by main.gd.
func set_diving(pressed: bool) -> void:
	_holding_dive = pressed


func _ready() -> void:
	# Tunnel ramps run at about 40 degrees, and faceted walls push some normals past Godot's
	# 45 degree default, which reads as "wall" and stops the player dead halfway out.
	floor_max_angle = deg_to_rad(55.0)
	_health = max_health
	_build_body()


## How deep the feet are below the surface; negative when clear of the water.
func submersion() -> float:
	return water_level - global_position.y


func is_swimming() -> bool:
	return submersion() > swim_depth


func _physics_process(delta: float) -> void:
	if _dead:
		# Gravity still applies and momentum still bleeds off, so a captain killed in mid-air
		# falls and comes to rest instead of dying where he was hit and hanging there. Input
		# is not read at all - not even to buffer it - or he would jump on respawn.
		if not is_on_floor():
			velocity.y -= fall_gravity * delta
			velocity.y = maxf(velocity.y, -terminal_velocity)
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta * sprint_speed)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta * sprint_speed)
		move_and_slide()
		_update_animation()
		return

	# Ticked before the swimming branch returns, or a swing started on land would never end.
	_attack = maxf(0.0, _attack - delta)
	_stagger = maxf(0.0, _stagger - delta)
	# The captain's swing SURVIVES being hit. A grunt's does not, and that asymmetry is the
	# point: a grunt out-reaches the captain and swings every 2.15 s, so cancelling on contact
	# meant every swing died before its strike window opened. Measured, that is a captain who
	# lands one blow in six and dies - not a fight, a formality. He is still shoved and still
	# loses control for 0.22 s; he just gets to finish what he started.
	if Input.is_action_just_pressed("attack"):
		attack()
	_strike()

	# --- jump feel: coyote time, buffered presses, short hops, heavier fall ---
	if Input.is_action_just_pressed("jump"):
		_buffered = jump_buffer
		_holding_jump = true
	if Input.is_action_just_released("jump"):
		_holding_jump = false
	_buffered = maxf(0.0, _buffered - delta)
	_coyote = coyote_time if is_on_floor() else maxf(0.0, _coyote - delta)

	var swimming := is_swimming()
	# Only on the crossing, not every frame spent wet.
	var wet := submersion() > 0.25
	if wet != _was_wet:
		_was_wet = wet
		splashed.emit(wet)
	if touch_controls:
		touch_controls.show_dive(swimming)
	if swimming:
		_swim(delta)
		return

	if _buffered > 0.0 and _coyote > 0.0:
		velocity.y = _jump_velocity()
		_buffered = 0.0
		_coyote = 0.0
	elif not is_on_floor():
		var rising := velocity.y > 0.0
		if rising and not _holding_jump:            # let go early -> short hop
			velocity.y *= short_hop_cut
			rising = velocity.y > 0.0
		velocity.y -= (rise_gravity if rising else fall_gravity) * delta
		velocity.y = maxf(velocity.y, -terminal_velocity)

	var direction := _move_direction()
	var wanted := sprint_speed if Input.is_action_pressed("sprint") else speed
	# Shallow water drags: wading out to the drop-off should feel different from running.
	var walk_speed := wanted * (wade_slowdown if submersion() > 0.0 else 1.0)
	var target := direction * walk_speed
	if _stagger > 0.0:
		# Coasting to a stop rather than being steered. The normal deceleration is 108 m/s^2,
		# which would kill the shove inside three frames and make a hit look like nothing.
		velocity.x = move_toward(velocity.x, 0.0, knock_damping * delta)
		velocity.z = move_toward(velocity.z, 0.0, knock_damping * delta)
	else:
		velocity.x = move_toward(velocity.x, target.x, acceleration * delta * sprint_speed)
		velocity.z = move_toward(velocity.z, target.z, acceleration * delta * sprint_speed)
	move_and_slide()

	if direction.length() > 0.05:
		var yaw := atan2(direction.x, direction.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)
		_walk_time += delta * velocity.length()
		_animate_walk()
		# A footfall every stride_length of ground covered, and only with feet on it.
		if is_on_floor():
			_stride += Vector2(velocity.x, velocity.z).length() * delta
			if _stride >= stride_length:
				_stride = 0.0
				stepped.emit()
	else:
		_walk_time = 0.0
		_animate_walk(true)
	_update_animation()


## Swimming: no jump arc and no gravity, just buoyancy, drag and free vertical control.
##
## Holding jump swims up, holding dive swims down, and letting go floats back to the surface.
## Without that float the player sinks quietly to the seabed whenever they stop steering.
func _swim(delta: float) -> void:
	var direction := _move_direction()
	var target := direction * swim_speed
	velocity.x = move_toward(velocity.x, target.x, water_drag * delta * swim_speed)
	velocity.z = move_toward(velocity.z, target.z, water_drag * delta * swim_speed)

	var vertical := 0.0
	if _holding_jump or Input.is_action_pressed("jump"):
		vertical = swim_speed
	elif _holding_dive or Input.is_action_pressed("dive"):
		vertical = -swim_speed
	else:
		# Float up, but stop at the surface rather than launching out of the water.
		var above_swimming_depth: float = submersion() - swim_depth
		vertical = clampf(above_swimming_depth * buoyancy, -swim_speed, swim_speed)
	velocity.y = move_toward(velocity.y, vertical, water_drag * delta * swim_speed * 2.0)
	move_and_slide()

	if direction.length() > 0.05:
		var yaw := atan2(direction.x, direction.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)
		_walk_time += delta * velocity.length()
	_animate_walk()
	_update_animation()


## Camera-relative movement input, shared by walking and swimming.
func _move_direction() -> Vector3:
	# Nothing steers while staggered. Applied here rather than at each call site so it covers
	# swimming and walking together.
	if _stagger > 0.0:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_controls and touch_controls.move.length() > 0.0:
		input = touch_controls.move
	var basis := camera_rig.global_transform.basis if camera_rig else global_transform.basis
	var forward := -Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var direction := (right * input.x + forward * -input.y)
	return direction.normalized() if direction.length() > 1.0 else direction


## The captain, or a blocky stand-in if the model is not there.
##
## The model comes out of the pipeline in D:\code\gan: a silhouette becomes a rendered
## character, four turnaround views come off that, and a multi-view service builds the rigged
## mesh. Generators normalise to a unit cube, so it arrives 1.0 units tall and is scaled here.
##
## Scaling belongs here and not in the file. Writing a scale onto the glTF root node looks
## like it works - the bounds come out right and it loads fine - but a skinned mesh carries
## inverse-bind matrices that do not scale with it, so the character arrives visibly
## distorted. Scaling the instantiated node scales the skeleton and the skin together.
func _build_body() -> void:
	var scene: PackedScene = load(MODEL_PATH) if ResourceLoader.exists(MODEL_PATH) else null
	if scene:
		var model := scene.instantiate()
		model.name = "Model"
		model.rotation.y = deg_to_rad(model_yaw)
		_body.add_child(model)
		# Layer 20 is the overhead water-interaction camera. Every visible surface has to be
		# on it or the water loses the player's footprint - see _add_part.
		for node in _all_descendants(model):
			if node is VisualInstance3D:
				node.set_layer_mask_value(20, true)
		_flatten_materials(model)
		for node in _all_descendants(model):
			if node is AnimationPlayer:
				_anim = node as AnimationPlayer
				break
		_set_looping()
		_attach_weapon(model)
		_model_loaded = true
		return
	_build_primitive_body()


## Hangs the placeholder blade off the right hand. The awkward parts - which way a blade leaves
## a fist, and cancelling the rig's unit scale - live in actors/parts/weapon.gd, shared with the grunts.
func _attach_weapon(model: Node3D) -> void:
	if not show_weapon:
		return
	var skeleton: Skeleton3D = null
	for node in _all_descendants(model):
		if node is Skeleton3D:
			skeleton = node as Skeleton3D
			break
	var blade := Weapon.new()
	blade.name = "Weapon"
	if not blade.setup(skeleton, weapon_bone, sword_size, sword_offset, sword_rotation,
			sword_colour, sword_model, sword_grip):
		blade.free()
		return
	_weapon = blade
	_blade = blade.hitbox


func _flatten_materials(model: Node3D) -> void:
	for node in _all_descendants(model):
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
				if unshaded_model:
					# The texture is already lit, so ignoring the scene lights entirely can
					# read better - at the cost of the character not darkening in shadow.
					flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_node.set_surface_override_material(surface, flat)


func _all_descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_all_descendants(child))
	return found


## The original stand-in, kept so the project still runs with no imported assets.
func _build_primitive_body() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.20, 0.38, 0.62)
	var trousers := StandardMaterial3D.new()
	trousers.albedo_color = Color(0.22, 0.24, 0.30)
	for material in [skin, cloth, trousers]:
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.roughness = 1.0

	_add_part("Torso", CapsuleMesh.new(), Vector3(0, 0.95, 0), cloth, func(m):
		m.radius = 0.28
		m.height = 0.9)
	_add_part("Head", SphereMesh.new(), Vector3(0, 1.62, 0), skin, func(m):
		m.radius = 0.22
		m.height = 0.44)
	for side in [-1.0, 1.0]:
		var arm := _add_part("Arm%s" % ("L" if side < 0 else "R"), BoxMesh.new(),
				Vector3(side * 0.42, 1.05, 0), cloth, func(m): m.size = Vector3(0.16, 0.62, 0.16))
		arm.set_meta("swing_side", side)
		var leg := _add_part("Leg%s" % ("L" if side < 0 else "R"), BoxMesh.new(),
				Vector3(side * 0.16, 0.35, 0), trousers, func(m): m.size = Vector3(0.20, 0.7, 0.20))
		leg.set_meta("swing_side", -side)


func _add_part(name_: String, mesh: PrimitiveMesh, pos: Vector3, material: Material,
		configure: Callable) -> MeshInstance3D:
	configure.call(mesh)
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = name_
	node.mesh = mesh
	node.position = pos
	# Layer 20 is read only by the overhead water-interaction camera. It gives the water
	# the player's true top-down footprint without outlining the gameplay-camera silhouette.
	node.set_layer_mask_value(20, true)
	_body.add_child(node)
	return node


## Swings the stand-in's limbs. The captain is driven by _update_animation instead.
func _animate_walk(rest := false) -> void:
	if _model_loaded:
		return
	var swing := 0.0 if rest else sin(_walk_time * 1.6) * 0.5
	for child in _body.get_children():
		if child.has_meta("swing_side"):
			child.rotation.x = swing * child.get_meta("swing_side")


## Marks the cyclic clips as looping.
##
## glTF carries no loop flag, so Godot imports every animation as play-once. A walk cycle then
## takes a few steps, stops on its last frame, and the character glides along in that pose -
## which reads as the animation being broken rather than merely finished.
##
## Jump is deliberately left alone. It is Mixamo's "Jumping Up" cut down to its launch - the
## legs drive down and then tuck - and it runs 0.34s against the 0.35s the rise actually takes,
## so it lands on the tuck and holds there. Looping it would restart the take-off mid-air.
##
## Fall does loop. It is "Falling Idle", which is built as a cycle, and a drop from any height
## worth having outlasts its 0.73s - without the loop the character freezes into its last frame
## on the way down.
func _set_looping() -> void:
	if _anim == null:
		return
	for name_ in [clip_idle, clip_walk, clip_run, clip_swim, clip_fall]:
		if name_ == "" or not _anim.has_animation(name_):
			continue
		var clip := _anim.get_animation(name_)
		if clip.loop_mode != Animation.LOOP_LINEAR:
			clip.loop_mode = Animation.LOOP_LINEAR


## Picks the clip that matches what the player is doing.
##
## Nothing here assumes the clips exist. A model with a skeleton and no animations - which is
## what a generator gives you - simply stands in its rest pose, and each clip starts working
## the moment it is added. That way the states can be got right before the animations arrive.
func _update_animation() -> void:
	if _anim == null:
		return
	var wanted := ""
	if _dead:
		wanted = clip_death
	elif _attack > 0.0:
		wanted = clip_attack
	elif is_swimming():
		wanted = clip_swim
	elif not is_on_floor():
		wanted = clip_jump if velocity.y > 0.0 else clip_fall
	else:
		var ground_speed := Vector2(velocity.x, velocity.z).length()
		if ground_speed < 0.2:
			wanted = clip_idle
		else:
			wanted = clip_run if ground_speed > run_above else clip_walk

	# Fall back through to something that does exist, so a half-finished set still animates
	# rather than freezing: no run clip yet means walking, no fall clip means the jump.
	for candidate in [wanted, clip_walk, clip_idle]:
		if candidate != "" and _anim.has_animation(candidate):
			if candidate != _clip:
				_anim.play(candidate, clip_blend)
				# The swing is entered part-way in. See attack_start: the clip's first second
				# is a wind-up, and starting at zero makes the button feel like it is not wired.
				if candidate == clip_attack and _attack > 0.0:
					_anim.seek(attack_start, true)
				_clip = candidate
			return
