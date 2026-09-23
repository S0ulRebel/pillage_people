class_name Ship
extends Node3D
## The double-deck hull from the canonical kit, moored off the beach.
##
## The mesh is the construction form, not a finished model: broad faces, no planking pass.
## It is copied into art/models so the scene does not load out of the reference kit, and so a
## later styling pass can replace the file without touching the kit.
##
## Axes and sizes are the kit's, in metres: X starboard, Y up, Z aft, keel at Y=0, bow at Z=0,
## stern at Z=14, beam 6. The gunport sills are at Y=3.4, so the keel sits two metres under
## the still waterline and the ports stay clear of the waves.

const MODEL := "res://art/models/ship/double_deck.glb"
const LENGTH := 14.0
const BEAM := 6.0
## Keel depth below still water. Gun deck is at 2.6, so this leaves it 0.6 m clear.
const DRAFT := 2.0
## Extra water under the keel, so a sloping seabed does not poke through the bilge.
const CLEARANCE := 0.6
## Top of the weather-deck slab. Measured off the mesh: feet land here.
const DECK_Y := 5.2
## How far from the hull a climb still counts. The collision stops him short of the planks.
const BOARD_MARGIN := 3.0
## Where a climb puts his feet: centreline, aft of the stair opening, a metre above the deck
## so he drops onto it instead of spawning in the slab.
const BOARD_SPOT := Vector3(0.0, DECK_Y + 1.0, 10.0)
## Deck contact of the wheel, on the stern weather deck. The real F01_HELM drops in here.
const HELM_AT := Vector3(0.0, DECK_Y, 12.4)
## Where his feet go: aft of the wheel, looking toward the bow.
const HELM_FEET := Vector3(0.0, DECK_Y, 13.25)
const HELM_REACH := 1.6
const AHEAD_SPEED := 7.0
const ASTERN_SPEED := 3.5
const YAW_RATE := 0.45
## Keel to the top of the bulwark. The fraction of this under the surface is the buoyancy.
const HULL_HEIGHT := 6.0
## How hard a difference in submersion heels the hull, in radians per second squared.
const PITCH_RESPONSE := 6.0
const ROLL_RESPONSE := 8.0
const MAX_HEEL := 0.14

## The ocean, so the lift is taken from the waves rather than the flat sea level. Same sampler
## the barrels use. Without it the hull sits on the average.
var ocean: Node3D
## Whoever is standing on deck. The hull moves, and a character body is not carried along by a
## static floor that teleports, so he is moved with it while his feet are over the deck.
var rider: Node3D

var _terrain: Node
var _sea := 0.0
## Bow origin in the horizontal, and which way aft points. Heave and heel are separate so
## steering never flattens the float.
var _planar := Vector3.ZERO
var _heading := 0.0
## Height of the keel at midships, and how fast it is rising.
var _keel_y := 0.0
var _rise := 0.0
var _pitch := 0.0
var _pitch_rate := 0.0
var _roll := 0.0
var _roll_rate := 0.0


func _ready() -> void:
	_build()
	_build_helm()


## Floats broadside to the beach the coastal study picked, close enough to swim to.
## The study's +Z points inland, so seaward is -Z and the beach runs along X.
func moor_off(beach: Node3D, terrain: Node) -> bool:
	var sea: float = terrain.sea_level()
	var inland: Vector3 = beach.global_basis.z
	inland.y = 0.0
	if inland.length_squared() < 0.01:
		return false
	inland = inland.normalized()
	var along := Vector3.UP.cross(inland).normalized()
	# Broadside first: the ports read, and the hull stays clear of the rocks in the shallows.
	# Bow-out is the fallback where the bay is too narrow for fourteen metres of length.
	var headings: Array[Vector3] = [along, -along, inland]
	for aft in headings:
		for distance in range(36, 140, 4):
			for lateral in [0, 16, -16, 32, -32]:
				var centre := beach.global_position - inland * float(distance) + along * float(lateral)
				var origin := centre - aft * (LENGTH * 0.5)
				origin.y = sea - DRAFT
				if _afloat(origin, aft, terrain, sea):
					_planar = origin
					_heading = atan2(aft.x, aft.z)
					_keel_y = sea - DRAFT
					_terrain = terrain
					_sea = sea
					_apply_pose()
					print("ship moored at ", global_position, " draft ", DRAFT)
					return true
	push_warning("ship: no water deep enough off this beach")
	return false


## True when `who` is beside the hull and not already standing on it.
## The deck is the only way up, and there is no ladder, so this is the whole climb.
func can_board(who: Node3D) -> bool:
	var local := to_local(who.global_position)
	if _on_deck(local):
		return false
	return _hull_distance(local) <= BOARD_MARGIN


## True when he is on the weather deck and within reach of the wheel.
func can_helm(who: Node3D) -> bool:
	var local := to_local(who.global_position)
	if not _on_deck(local):
		return false
	return Vector2(local.x - HELM_AT.x, local.z - HELM_AT.z).length() <= HELM_REACH


func helm_feet() -> Vector3:
	return to_global(HELM_FEET)


## Bow, flat. The wheel faces this way.
func helm_facing() -> Vector3:
	var bow := -global_basis.z
	bow.y = 0.0
	return bow.normalized() if bow.length_squared() > 0.0001 else Vector3.FORWARD


## `throttle` is +1 ahead. `yaw` is +1 to starboard. Only the heading and the
## horizontal move: the draft is the buoyancy's, and writing it here pinned the hull to a
## flat sea while the waves went past it.
func drive(delta: float, throttle: float, yaw: float) -> void:
	if _terrain == null:
		return
	throttle = clampf(throttle, -1.0, 1.0)
	yaw = clampf(yaw, -1.0, 1.0)
	if absf(yaw) > 0.01:
		# Positive yaw is starboard, so the bow swings to +X.
		_heading -= yaw * YAW_RATE * delta
	var aft := _aft()
	if absf(throttle) > 0.01:
		var rate := AHEAD_SPEED if throttle > 0.0 else ASTERN_SPEED
		var candidate := _planar - aft * throttle * rate * delta
		candidate.y = _sea - DRAFT
		# A grounded move is refused. Turning still happened, so he can aim back at water.
		if _afloat(candidate, aft, _terrain, _sea):
			_planar.x = candidate.x
			_planar.z = candidate.z
	_apply_pose()


func _physics_process(delta: float) -> void:
	if _terrain == null:
		return
	var before := global_transform
	var held := Vector3.ZERO
	var riding := false
	if rider != null:
		held = before.affine_inverse() * rider.global_position
		riding = _on_deck(held)
	_buoy(delta)
	_apply_pose()
	if riding:
		rider.global_position = global_transform * held


## Lift from how much hull is under the surface, damped so it settles on the draft instead of
## bobbing forever. The same arrangement as a barrel: too deep and the lift beats gravity, too
## shallow and it does not. Pitch and roll are that difference measured along the hull.
func _buoy(delta: float) -> void:
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	# Full submersion pushes this hard, so the balance sits at the designed draft rather than
	# at half the hull. Gunports are above that line; a barrel's half-submerged balance would
	# put them under.
	var lift := gravity * HULL_HEIGHT / DRAFT
	var aft := _aft()
	var starboard := Vector3(aft.z, 0.0, -aft.x)
	var bow := Vector3(_planar.x, 0.0, _planar.z)
	var mid := bow + aft * (LENGTH * 0.5)
	var stern := bow + aft * LENGTH
	var half_len := LENGTH * 0.5
	var half_beam := BEAM * 0.5
	var bow_y := _keel_y + sin(_pitch) * half_len
	var stern_y := _keel_y - sin(_pitch) * half_len
	var port_y := _keel_y - sin(_roll) * half_beam
	var star_y := _keel_y + sin(_roll) * half_beam
	var mid_sub := _submerged(_surface(mid.x, mid.z) - _keel_y)
	var bow_sub := _submerged(_surface(bow.x, bow.z) - bow_y)
	var stern_sub := _submerged(_surface(stern.x, stern.z) - stern_y)
	var port_sub := _submerged(_surface(mid.x - starboard.x * half_beam, mid.z - starboard.z * half_beam) - port_y)
	var star_sub := _submerged(_surface(mid.x + starboard.x * half_beam, mid.z + starboard.z * half_beam) - star_y)
	_rise += (lift * mid_sub - gravity) * delta
	# Critical damping, and not only while submerged. Scaled by the submerged fraction the
	# drag vanished the moment the keel cleared a crest, so the hull fell and then launched
	# itself back out.
	var heave_omega := sqrt(lift / HULL_HEIGHT)
	_rise *= exp(-2.0 * heave_omega * delta)
	_rise = clampf(_rise, -1.2, 1.2)
	_keel_y += _rise * delta
	_pitch_rate += PITCH_RESPONSE * (bow_sub - stern_sub) * delta
	_roll_rate += ROLL_RESPONSE * (star_sub - port_sub) * delta
	var pitch_omega := sqrt(PITCH_RESPONSE * LENGTH / HULL_HEIGHT)
	var roll_omega := sqrt(ROLL_RESPONSE * BEAM / HULL_HEIGHT)
	_pitch_rate *= exp(-2.0 * pitch_omega * delta)
	_roll_rate *= exp(-2.0 * roll_omega * delta)
	_pitch = clampf(_pitch + _pitch_rate * delta, -MAX_HEEL, MAX_HEEL)
	_roll = clampf(_roll + _roll_rate * delta, -MAX_HEEL, MAX_HEEL)
	if absf(_pitch) >= MAX_HEEL - 0.0001:
		_pitch_rate = 0.0
	if absf(_roll) >= MAX_HEEL - 0.0001:
		_roll_rate = 0.0


func _submerged(depth: float) -> float:
	return clampf(depth / HULL_HEIGHT, 0.0, 1.0)


func _surface(x: float, z: float) -> float:
	if ocean != null and ocean.has_method("surface_y"):
		return ocean.surface_y(x, z)
	return _sea


func _aft() -> Vector3:
	return Vector3(sin(_heading), 0.0, cos(_heading))


func _apply_pose() -> void:
	var bow_lift := sin(_pitch) * LENGTH * 0.5
	global_position = Vector3(_planar.x, _keel_y + bow_lift, _planar.z)
	# Yaw, then heel about the ship's own axes. Built rather than read back, so the float
	# cannot accumulate a tilt the way a decomposed basis does.
	global_basis = Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3(0.0, 0.0, 1.0), _roll)


## Drops `who` onto the weather deck. The caller has already checked can_board.
func board(who: Node3D) -> void:
	who.global_position = to_global(BOARD_SPOT)
	if who is CharacterBody3D:
		(who as CharacterBody3D).velocity = Vector3.ZERO


func _on_deck(local: Vector3) -> bool:
	return local.y > DECK_Y - 0.6 and absf(local.x) <= BEAM * 0.5 and local.z >= 0.0 and local.z <= LENGTH


## Metres from the hull's rectangular outline. Zero when he is inside it.
func _hull_distance(local: Vector3) -> float:
	var dx := maxf(absf(local.x) - BEAM * 0.5, 0.0)
	var dz := 0.0
	if local.z < 0.0:
		dz = -local.z
	elif local.z > LENGTH:
		dz = local.z - LENGTH
	return Vector2(dx, dz).length()


func _build() -> void:
	# The mesh lives in the scene so the editor can show the hull. A missing one is filled in
	# here, and either way the surfaces still need the flat toon pass and deck collision.
	var model := get_node_or_null("Model") as Node3D
	if model == null:
		if not ResourceLoader.exists(MODEL):
			push_warning("ship: no model at %s" % MODEL)
			return
		model = (load(MODEL) as PackedScene).instantiate()
		model.name = "Model"
		add_child(model)
	for node in _descendants(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		# Layer 20 is the ocean's overhead silhouette, same as the rocks, so the hull cuts a
		# band in the surface instead of disappearing under a flat sheet of water.
		mesh_node.layers = 1 | (1 << 19)
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
		# The deck and the stairs are part of the mesh. A box would fill the hatch.
		mesh_node.create_trimesh_collision()


## A wheel and a stand, in the kit's helm box, until a real F01_HELM model replaces it.
## The node is named Helm and sits on HELM_AT so the swap is a mesh, not a new place.
func _build_helm() -> void:
	if get_node_or_null("Helm") != null:
		return
	var helm := Node3D.new()
	helm.name = "Helm"
	helm.position = HELM_AT
	add_child(helm)
	var timber := _flat(Color(0.55, 0.36, 0.18))
	var iron := _flat(Color(0.22, 0.22, 0.24))
	var brass := _flat(Color(0.75, 0.58, 0.22))
	_box(helm, Vector3(0.0, 0.06, 0.0), Vector3(0.7, 0.12, 0.36), timber)
	_box(helm, Vector3(-0.16, 0.48, 0.0), Vector3(0.08, 0.84, 0.08), timber)
	_box(helm, Vector3(0.16, 0.48, 0.0), Vector3(0.08, 0.84, 0.08), timber)
	_box(helm, Vector3(0.0, 0.9, 0.0), Vector3(0.4, 0.08, 0.08), iron)
	var wheel := Node3D.new()
	wheel.name = "Wheel"
	wheel.position = Vector3(0.0, 1.15, 0.08)
	helm.add_child(wheel)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var spoke := _box(wheel, Vector3(cos(ang) * 0.24, sin(ang) * 0.24, 0.0), Vector3(0.36, 0.05, 0.05), timber)
		spoke.rotation.z = ang
		var rim := _box(wheel, Vector3(cos(ang) * 0.46, sin(ang) * 0.46, 0.0), Vector3(0.2, 0.07, 0.07), timber)
		rim.rotation.z = ang + PI * 0.5
	_cylinder(wheel, Vector3.ZERO, 0.08, 0.1, brass)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 1.35, 0.28)
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(shape)
	helm.add_child(body)


func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.rotation_degrees.x = 90.0
	node.material_override = material
	parent.add_child(node)


func _flat(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 1.0
	material.metallic = 0.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	return material


## True when every sample under the hull has enough water for the draft.
func _afloat(origin: Vector3, aft: Vector3, terrain: Node, sea: float) -> bool:
	var starboard := Vector3.UP.cross(aft).normalized()
	var needed := DRAFT + CLEARANCE
	var along_hull: Array[float] = [0.4, 3.0, 6.0, 9.0, 12.0, 13.6]
	var across_hull: Array[float] = [-BEAM * 0.42, 0.0, BEAM * 0.42]
	for z in along_hull:
		for x in across_hull:
			var p := origin + aft * z + starboard * x
			if sea - terrain.height_at(p.x, p.z) < needed:
				return false
	return true


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
