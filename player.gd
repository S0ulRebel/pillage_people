extends CharacterBody3D
## Bird's-eye third-person controller: WASD moves relative to the camera, Space jumps,
## Q/E orbit, mouse wheel zooms. The body is built from primitives so the project needs no
## imported model.

@export var speed := 9.0
@export var acceleration := 12.0
@export var turn_speed := 12.0

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

@onready var _body: Node3D = $Body

var _walk_time := 0.0
var _coyote := 0.0
var _buffered := 0.0
var _holding_jump := false
## Set by the touch dive button; the keyboard uses the "dive" action directly.
var _holding_dive := false


## Take-off speed for the requested height: v = sqrt(2 * g * h).
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
	# Shallow water drags: wading out to the drop-off should feel different from running.
	var walk_speed := speed * (wade_slowdown if submersion() > 0.0 else 1.0)
	var target := direction * walk_speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta * speed)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta * speed)
	move_and_slide()

	if direction.length() > 0.05:
		var yaw := atan2(direction.x, direction.z)
		_body.rotation.y = lerp_angle(_body.rotation.y, yaw, turn_speed * delta)
		_walk_time += delta * velocity.length()
		_animate_walk()
	else:
		_walk_time = 0.0
		_animate_walk(true)


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


## Primitive "blocky person": capsule torso, sphere head, box limbs that swing while walking.
func _build_body() -> void:
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.68, 0.55)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.20, 0.38, 0.62)
	var trousers := StandardMaterial3D.new()
	trousers.albedo_color = Color(0.22, 0.24, 0.30)

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


func _animate_walk(rest := false) -> void:
	var swing := 0.0 if rest else sin(_walk_time * 1.6) * 0.5
	for child in _body.get_children():
		if child.has_meta("swing_side"):
			child.rotation.x = swing * child.get_meta("swing_side")
