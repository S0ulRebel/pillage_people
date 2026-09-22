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

## Set by main.gd - movement is relative to whichever way the camera is facing.
var camera_rig: Node3D
## Set by main.gd on touch devices; its stick overrides the keyboard when in use.
var touch_controls: CanvasLayer

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


## Take-off speed for the requested height: v = sqrt(2 * g * h).
## Emitted the moment die() is called, before the clip starts, so whatever is listening can
## fade the screen or start a respawn timer against the same frame.
signal died
signal revived


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

	# --- jump feel: coyote time, buffered presses, short hops, heavier fall ---
	if Input.is_action_just_pressed("jump"):
		_buffered = jump_buffer
		_holding_jump = true
	if Input.is_action_just_released("jump"):
		_holding_jump = false
	_buffered = maxf(0.0, _buffered - delta)
	_coyote = coyote_time if is_on_floor() else maxf(0.0, _coyote - delta)

	var swimming := is_swimming()
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
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta * sprint_speed)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta * sprint_speed)
	move_and_slide()

	if direction.length() > 0.05:
		var yaw := atan2(direction.x, direction.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)
		_walk_time += delta * velocity.length()
		_animate_walk()
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
		_model_loaded = true
		return
	_build_primitive_body()


## Takes the shine off the imported material so the captain sits in the same world as the
## terrain, which is unshaded flat colour.
##
## A generated texture already has its lighting painted into it, and the generator also hands
## over a PBR material with specular and a roughness value. Lighting that again on top is what
## makes the character look like moulded plastic next to flat ground. Toon diffuse and no
## specular is what the primitive stand-in used, so this is the project's existing treatment
## rather than a new one.
##
## Better still is to export from Tripo with texture_delight on, which strips the baked
## lighting out of the texture itself. This only stops it being lit twice.
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
				_clip = candidate
			return
