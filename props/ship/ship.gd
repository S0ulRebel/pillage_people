@tool
class_name Ship
extends Node3D
## The double-deck hull from the canonical kit, moored off the beach.
##
## The mesh is the construction form with the kit's plank texture laid on it, not yet a
## finished model: no bevels, trim or ironwork. It is copied into art/models so the scene does
## not load out of the reference kit, and so a later styling pass can replace the file without
## touching the kit.
##
## The fittings are models cut from the Tripo sheets (art/models/ship/fittings, rigging),
## each placed in the node its placeholder used to fill. Where a model file is missing, the
## placeholder is built instead, so the ship never loses a part it needs.
##
## Axes and sizes are the kit's, in metres: X starboard, Y up, Z aft, keel at Y=0, bow at Z=0,
## stern at Z=14, beam 6. The gunport sills are at Y=3.4, so the keel sits two metres under
## the still waterline and the ports stay clear of the waves.
##
## This script runs in the editor so the mast, sail, guns and the other fittings — which are
## built in code, not saved into the scene — are visible on the hull while it is open.

const MODEL := "res://art/models/ship/double_deck.glb"
const LENGTH := 14.0
## The bulged stern's aftmost point. The hull, and the quarterdeck over it, reach past LENGTH,
## so standing on board is measured to here.
const STERN_Z := 16.7
const BEAM := 6.0
## Keel depth below still water. Gun deck is at 2.6, so this leaves it 0.6 m clear.
const DRAFT := 2.0
## Extra water under the keel, so a sloping seabed does not poke through the bilge.
const CLEARANCE := 0.6
## Top of the weather-deck slab. Measured off the mesh: feet land here.
const DECK_Y := 5.2
## How far from the hull a climb still counts. The collision stops him short of the planks.
const BOARD_MARGIN := 3.0
## Where a climb puts his feet: centreline, between the stair opening and the mainmast, a metre
## above the deck so he drops onto it instead of spawning in the slab. On the centreline he is
## out of reach of the guns below, which measure their reach straight through the deck.
const BOARD_SPOT := Vector3(0.0, DECK_Y + 1.0, 7.9)
## The stern cabin's floor centre. Its door faces the bow and its roof is the quarterdeck. As
## far aft as the narrowing stern allows: its walls stay 4 cm inside the bulwarks.
const CABIN_AT := Vector3(0.0, DECK_Y, 12.75)
## The quarterdeck's walking surface, the cabin roof: one kit tier (2.6 m) above the weather
## deck, which is exactly where STAIRS_260 lands.
const QUARTERDECK_Y := DECK_Y + 2.6
## Foot of the quarterdeck stairs, the kit's STAIRS_260: 1 m wide, rising aft over 3.25 m.
## Port of the centreline and starting just aft of the stair opening, so whoever comes up from
## the gun deck walks straight on; the top lands on the roof clear of the cabin's corner post.
const QUARTERDECK_STAIRS_AT := Vector3(-1.0, DECK_Y, 7.26)
## Deck contact of the wheel, on the quarterdeck. The real F01_HELM drops in here.
const HELM_AT := Vector3(0.0, QUARTERDECK_Y, 13.2)
## Where his feet go: aft of the wheel, looking toward the bow.
const HELM_FEET := Vector3(0.0, QUARTERDECK_Y, 14.05)
const HELM_REACH := 1.6
## Deck contact of the mainmast, aft of the stair hatch and forward of the wheel.
const MAST_AT := Vector3(0.0, DECK_Y, 9.0)
## Deck contact of the foremast, on the bow deck forward of the hatch. Shorter than the main.
const FOREMAST_AT := Vector3(0.0, DECK_Y, 1.5)
## Base of the bowsprit, seated in the raked stem just under the rail. The spar's own
## length runs forward from here. A real F03_BOWSPRIT drops in on this node.
const BOWSPRIT_AT := Vector3(0.0, 5.65, -2.66)
## Hinge of the rudder, on the stern under the counter. The blade hangs aft of this
## point. A real F04_RUDDER drops in on this node.
const RUDDER_AT := Vector3(0.0, 1.8, 14.9)
## Gun deck the ports look out of. One opening per side in each centre bay, centred a metre
## aft of the bay's forward station. The carriage sits high enough for this model's barrel to
## meet that opening: the sill is 0.8 m off the deck and the barrel axis is only 0.62 m up.
const GUN_DECK_Y := 2.6
const GUN_PORT_Z := [5.0, 7.0, 9.0, 11.0]
## Centre of each port's opening: the kit's sill is 0.8 m off the gun deck, the opening 0.8 m tall.
const GUN_PORT_Y := GUN_DECK_Y + 1.2
## Deck contact of the capstan, on the gun deck under the cabin: the weather deck there is
## the cabin's floor now. Clear of the guns and under the beams; a real F02_CAPSTAN drops in
## on this node.
const CAPSTAN_AT := Vector3(0.0, GUN_DECK_Y, 10.8)
## Ahead of the wheel on the quarterdeck, where the helmsman can read it.
const BINNACLE_AT := Vector3(0.0, QUARTERDECK_Y, 12.15)
## Top of the stern rail, on the centreline, where the bulged stern reaches aft furthest.
const LANTERN_AT := Vector3(0.0, 6.0, 16.68)
## How far the gunport lids stand open, so the guns can run out under them.
const LID_OPEN_DEGREES := 100.0
## Where the bow's catheads sit: the origin is the top of the timber's inboard end, 25 degrees
## forward of square. That lands the supporter's foot, 1.0 m out and 1.35 m down in the model,
## on the hull side at z=1.0, and passes the timber through the bulwark at rail height.
const CATHEAD_AT := Vector3(1.33, 6.0, 1.4)
const CATHEAD_YAW := 25.0
## The end of the cathead's fall, in its own space, where the anchor's ring hangs.
const CATHEAD_FALL := Vector3(1.44, -1.22, 0.0)
## Under the weather deck, between the gun ports, spanning the 5.6 m inside the hull. None
## over the stair shaft (z 4 to 7.25): a beam there would meet the head of anyone on the stairs.
const DECK_BEAM_Z := [8.0, 10.0, 12.0]
## Deck fittings with no role in play: [node, model, position, yaw, collides]. The position's
## Y is the deck it stands on. Laid out clear of the masts, the cabin and its stairs, the helm,
## the binnacle, the boarding spot and the stair opening (x -0.55 to 0.55, z 4 to 7.25). Cleats
## and racks sit against the bulwark's inner face, 2.8 m out; the bow narrows, so its fittings
## stay near the centreline. The breast rail closes the quarterdeck's forward edge from the
## stairs' landing to the cabin's starboard corner post.
const DECK_PROPS := [
	["Bitts", "fittings/bollard.glb", Vector3(0.0, DECK_Y, 2.8), 0.0, true],
	["AnchorCable", "fittings/anchor_cable.glb", Vector3(1.55, DECK_Y, 3.15), 0.0, true],
	["BowCoil", "rigging/rope_coil.glb", Vector3(-1.55, DECK_Y, 3.15), 0.0, true],
	["Hatch", "deck/hatch_coaming.glb", Vector3(1.55, DECK_Y, 5.4), 0.0, true],
	["CleatStarboardFore", "fittings/cleat.glb", Vector3(2.68, DECK_Y, 6.5), 90.0, false],
	["CleatPortFore", "fittings/cleat.glb", Vector3(-2.68, DECK_Y, 6.5), 90.0, false],
	["RackStarboard", "fittings/belaying_rack.glb", Vector3(2.68, DECK_Y, 9.0), 90.0, false],
	["RackPort", "fittings/belaying_rack.glb", Vector3(-2.68, DECK_Y, 9.0), 90.0, false],
	["CoilStarboard", "rigging/rope_coil.glb", Vector3(1.55, DECK_Y, 9.7), 0.0, true],
	["CoilQuarterdeck", "rigging/rope_coil.glb", Vector3(0.9, QUARTERDECK_Y, 11.1), 0.0, true],
	["BreastRail", "deck/rail_straight.glb", Vector3(0.35, QUARTERDECK_Y, 10.64), 0.0, true],
	["CleatStarboardAft", "fittings/cleat.glb", Vector3(2.68, DECK_Y, 11.6), 90.0, false],
	["CleatPortAft", "fittings/cleat.glb", Vector3(-2.68, DECK_Y, 11.6), 90.0, false],
]
## The mast top's platform floor stands 1.06 m above the model's lowest point; this puts that
## floor just above the placeholder's, and the model's collar clear of the course yard at 4.6.
const MAST_TOP_Y := 4.72

const FITTINGS := "res://art/models/ship/fittings/"
const RIGGING := "res://art/models/ship/rigging/"
const HULL_PARTS := "res://art/models/ship/hull/"
const DECK_PARTS := "res://art/models/ship/deck/"
const CABIN_PARTS := "res://art/models/ship/cabin/"
const CannonScene := preload("res://props/cannon/cannon.tscn")
const SailScript := preload("res://props/ship/sail.gd")
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
	_build_quarterdeck()
	_build_helm()
	_build_mast()
	_build_top_rail()
	_build_shrouds()
	_build_foremast()
	_build_bowsprit()
	_build_bobstay()
	_build_rudder()
	_build_capstan()
	_build_guns()
	_build_sail()
	_build_topsail()
	_build_backstays()
	_build_deck_fittings()


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


## True when he is up on the quarterdeck and within reach of the wheel. The height matters:
## the cabin under the wheel is closed, but the gangway beside it is on the weather deck.
func can_helm(who: Node3D) -> bool:
	var local := to_local(who.global_position)
	if not _on_deck(local) or local.y < HELM_AT.y - 0.6:
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
	# The fittings are built in the editor so the mast and guns are visible there. The float
	# is not: running it would walk the saved pose off the mooring.
	if Engine.is_editor_hint() or _terrain == null:
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
	return local.y > DECK_Y - 0.6 and absf(local.x) <= BEAM * 0.5 and local.z >= 0.0 and local.z <= STERN_Z


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
		_toon(mesh_node)
	# The deck and the stairs are part of the mesh. A box would fill the hatch.
	_walkable(model)


## Collision that follows the meshes under `node` exactly, for anything walked on or up: a box
## would fill the hatch, the stairs' steps and the rail around the quarterdeck. Skips a mesh
## that already has one: a tool script's _ready runs again on reload, and a second body would
## stack on the first.
func _walkable(node: Node3D) -> void:
	for child in _descendants(node):
		if not (child is MeshInstance3D) or (child as MeshInstance3D).mesh == null:
			continue
		var mesh_node := child as MeshInstance3D
		var blocked := false
		for grandchild in mesh_node.get_children():
			if grandchild is StaticBody3D:
				blocked = true
				break
		if not blocked:
			mesh_node.create_trimesh_collision()


## The stern cabin and the stairs up to its roof, the quarterdeck. The cabin is Tripo's whole
## cabin (art/models/ship/cabin/cabin_house.glb): the separate wall parts have no common bay
## and do not close a room. Its door is part of the mesh and stays shut; the roof, its rails
## and the stairs collide exactly, so the captain can walk up and round the wheel. Where a
## model is missing, a plain block and a ramp of the same size stand in.
func _build_quarterdeck() -> void:
	if get_node_or_null("Quarterdeck") != null:
		return
	var quarterdeck := Node3D.new()
	quarterdeck.name = "Quarterdeck"
	add_child(quarterdeck)
	var timber := _flat(Color(0.55, 0.36, 0.18))

	var cabin := Node3D.new()
	cabin.name = "Cabin"
	cabin.position = CABIN_AT
	quarterdeck.add_child(cabin)
	if _fit_model(cabin, CABIN_PARTS + "cabin_house.glb"):
		_walkable(cabin)
	else:
		_box(cabin, Vector3(0.0, 1.3, 0.0), Vector3(3.6, 2.6, 5.2), timber)
		_solid(cabin)

	# The model's origin is its foot on the centreline; it climbs 2.6 m toward +Z.
	var stairs := Node3D.new()
	stairs.name = "Stairs"
	stairs.position = QUARTERDECK_STAIRS_AT
	quarterdeck.add_child(stairs)
	if _fit_model(stairs, DECK_PARTS + "stairs_260.glb"):
		_walkable(stairs)
		# On the outboard edge, rising with the treads to the cabin's corner post. It does not
		# collide: half of it stands over the treads, and the 1 m stair is only just wide
		# enough for the captain as it is.
		var rail := Node3D.new()
		rail.name = "Rail"
		rail.position = Vector3(-0.5, 0.0, 0.0)
		stairs.add_child(rail)
		_fit_model(rail, DECK_PARTS + "rail_stair.glb")
	else:
		var run := Vector2(3.25, 2.6)
		var ramp := _box(stairs, Vector3(0.0, run.y * 0.5, run.x * 0.5), Vector3(1.0, 0.1, run.length()), timber)
		ramp.rotation.x = -atan2(run.y, run.x)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(1.0, 0.1, run.length())
		shape.shape = slab
		shape.transform = ramp.transform
		body.add_child(shape)
		stairs.add_child(body)


## The flat toon pass the whole ship shares: no specular, no metal, full roughness. Each
## surface gets its own copy, so the imported material is never edited in place.
func _toon(mesh_node: MeshInstance3D) -> void:
	for surface in mesh_node.mesh.get_surface_count():
		var material := mesh_node.mesh.surface_get_material(surface)
		if material is BaseMaterial3D:
			var flat: BaseMaterial3D = material.duplicate()
			flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			flat.metallic = 0.0
			flat.roughness = 1.0
			flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			mesh_node.set_surface_override_material(surface, flat)


## Puts the model at `path` under `parent` as a child named Model, toon-shaded like the hull.
## False when the file is not there, so the caller can build its placeholder instead. Each
## model's origin is already its attachment point (see art/references/ship-kit/tripo), so a
## part lands by its node's position, never by an offset measured off the mesh.
func _fit_model(parent: Node3D, path: String, at := Vector3.ZERO, degrees := Vector3.ZERO) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.name = "Model"
	model.position = at
	model.rotation_degrees = degrees
	parent.add_child(model)
	for node in _descendants(model):
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			_toon(node as MeshInstance3D)
	return true


## The F03 helm model, or a wheel and a stand in the kit's helm box when it is missing.
## The node is named Helm and sits on HELM_AT so the swap is a mesh, not a new place. The
## model's wheel is on its aft side, toward HELM_FEET.
func _build_helm() -> void:
	var helm := get_node_or_null("Helm") as Node3D
	if helm != null:
		helm.position = HELM_AT
		return
	helm = Node3D.new()
	helm.name = "Helm"
	helm.position = HELM_AT
	add_child(helm)
	_helm_body(helm)
	if _fit_model(helm, FITTINGS + "helm.glb"):
		return
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


## The stand collides and the wheel does not: the helmsman stands 0.4 m aft of its rim.
func _helm_body(helm: Node3D) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 1.35, 0.28)
	shape.shape = box
	shape.position = Vector3(0.0, 0.7, 0.0)
	body.add_child(shape)
	helm.add_child(body)


## Lower mast, topmast and a lookout: the M02/M03/M04 models, or spars in the kit's sizes
## when they are missing. The node is named Mast and sits on MAST_AT so the swap is a mesh,
## not a new place.
func _build_mast() -> void:
	var existing := get_node_or_null("Mast") as Node3D
	if existing != null:
		var old_foot := existing.get_node_or_null("FootYard")
		if old_foot != null:
			old_foot.free()
		return
	var mast := Node3D.new()
	mast.name = "Mast"
	mast.position = MAST_AT
	add_child(mast)
	var timber := _flat(Color(0.55, 0.36, 0.18))
	var iron := _flat(Color(0.22, 0.22, 0.24))
	# M01: 5.5 m, radius 0.25 at the deck narrowing to 0.18 at the head. The model is the same
	# 5.5 m from its deck contact, with the topmast's heel seated on its head.
	var lower := Node3D.new()
	lower.name = "Lower"
	mast.add_child(lower)
	if not _fit_model(lower, RIGGING + "mainmast.glb"):
		_spar(lower, 2.75, 0.25, 0.18, 5.5, timber)
		_spar(lower, 1.4, 0.3, 0.3, 0.08, iron)
		_spar(lower, 3.6, 0.24, 0.24, 0.08, iron)
		_spar(lower, 5.42, 0.22, 0.22, 0.1, iron)
	var upper := Node3D.new()
	upper.name = "Topmast"
	upper.position = Vector3(0.0, 5.5, 0.0)
	mast.add_child(upper)
	if not _fit_model(upper, RIGGING + "topmast.glb"):
		# M02 sits on that head and runs another 3 m, down to a 0.08 m tip.
		_spar(upper, 1.5, 0.18, 0.08, 3.0, timber)
	# M03 wraps the joint: a platform and a rail, not a socket in the spar. The model's hole
	# was sized to clear the 0.18 m head; the posts and ring are still the placeholder's,
	# because Tripo's platform has no rail and the lookout needs one.
	var top := Node3D.new()
	top.name = "Top"
	mast.add_child(top)
	if not _fit_model(top, RIGGING + "mast_top.glb", Vector3(0.0, MAST_TOP_Y, 0.0)):
		_spar(top, 5.5, 1.05, 1.05, 0.18, timber)
	for i in 8:
		var ang := TAU * float(i) / 8.0
		_box(mast, Vector3(cos(ang) * 0.95, 6.05, sin(ang) * 0.95), Vector3(0.08, 1.1, 0.08), timber)
	# One course yard under the top. The kit never sized one; this is the crosspiece that
	# makes the pole read as a mast. Eight metres, so it clears the six-metre beam.
	var yard := Node3D.new()
	yard.name = "Yard"
	yard.position = Vector3(0.0, 4.6, 0.0)
	mast.add_child(yard)
	# The model already runs athwartships along X, from its sling at the origin.
	if not _fit_model(yard, RIGGING + "lower_yard.glb"):
		# Local up lies along starboard, so the spar runs athwartships and tapers to both tips.
		yard.rotation_degrees.z = -90.0
		_spar(yard, -2.0, 0.06, 0.12, 4.0, timber)
		_spar(yard, 2.0, 0.12, 0.06, 4.0, timber)
		_spar(yard, 0.0, 0.2, 0.2, 0.12, iron)
	var old_foot := mast.get_node_or_null("FootYard")
	if old_foot != null:
		old_foot.free()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.28
	col.height = 5.5
	shape.shape = col
	shape.position = Vector3(0.0, 2.75, 0.0)
	body.add_child(shape)
	mast.add_child(body)


## A ring on the post tops. The floor was already there; this is the fence around it.
func _build_top_rail() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	if mast == null or mast.get_node_or_null("TopRail") != null:
		return
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.86
	mesh.outer_radius = 1.04
	mesh.rings = 24
	mesh.ring_segments = 6
	var rail := MeshInstance3D.new()
	rail.name = "TopRail"
	rail.mesh = mesh
	rail.position = Vector3(0.0, 6.6, 0.0)
	rail.material_override = _flat(Color(0.55, 0.36, 0.18))
	mast.add_child(rail)


## A shorter mast on the bow, forward of the hatch. The jib stays to this, not to the main.
func _build_foremast() -> void:
	if get_node_or_null("Foremast") != null:
		return
	var mast := Node3D.new()
	mast.name = "Foremast"
	mast.position = FOREMAST_AT
	add_child(mast)
	# The M01 model is the same 4.2 m from its deck contact.
	if not _fit_model(mast, RIGGING + "foremast.glb"):
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		_spar(mast, 2.1, 0.2, 0.12, 4.2, timber)
		_spar(mast, 1.1, 0.24, 0.24, 0.08, iron)
		_spar(mast, 3.3, 0.16, 0.16, 0.08, iron)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.22
	col.height = 4.2
	shape.shape = col
	shape.position = Vector3(0.0, 2.1, 0.0)
	body.add_child(shape)
	mast.add_child(body)


## A 3 m spar out of the stem, rising a little as it goes forward, until a real bowsprit replaces it.
## The node is named Bowsprit and its origin is the mount, so the swap keeps this place.
func _build_bowsprit() -> void:
	if get_node_or_null("Bowsprit") != null:
		return
	var sprit := Node3D.new()
	sprit.name = "Bowsprit"
	sprit.position = BOWSPRIT_AT
	# Local up is turned to point forward (-Z) and a little above the horizontal.
	sprit.rotation_degrees.x = -77.0
	add_child(sprit)
	# The M07 model reaches along its own -Z from the heel at its origin; turning it 90 degrees
	# about X lays that along this node's +Y, the direction the placeholder spar runs.
	if not _fit_model(sprit, RIGGING + "bowsprit.glb", Vector3.ZERO, Vector3(90.0, 0.0, 0.0)):
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		_spar(sprit, 1.5, 0.15, 0.08, 3.0, timber)
		_spar(sprit, 0.35, 0.2, 0.2, 0.12, iron)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.16
	col.height = 3.0
	shape.shape = col
	shape.position = Vector3(0.0, 1.5, 0.0)
	body.add_child(shape)
	sprit.add_child(body)


## From the bowsprit tip down to the stem, so the jib cannot lift the spar.
func _build_bobstay() -> void:
	if get_node_or_null("Bobstay") != null or get_node_or_null("Bowsprit") == null:
		return
	var stay := Node3D.new()
	stay.name = "Bobstay"
	add_child(stay)
	var sprit := Basis(Vector3.RIGHT, deg_to_rad(-77.0))
	var tip: Vector3 = BOWSPRIT_AT + sprit * Vector3(0.0, 2.9, 0.0)
	_rope(stay, tip, Vector3(0.0, 2.6, -0.6), 0.02, _flat(Color(0.45, 0.34, 0.22)))


## The F06 blade and its sternpost hinge strip, or a placeholder blade on an iron post.
## The node is named Rudder and its origin is the hinge, so the swap keeps this place. Both
## models share that origin: the blade reaches aft of it, the strip sits just forward.
func _build_rudder() -> void:
	if get_node_or_null("Rudder") != null:
		return
	var rudder := Node3D.new()
	rudder.name = "Rudder"
	rudder.position = RUDDER_AT
	add_child(rudder)
	var blade := FITTINGS + "rudder.glb"
	var strip := FITTINGS + "rudder_hinges.glb"
	# Both or neither: a model blade on the placeholder's iron post would hang off nothing.
	if ResourceLoader.exists(blade) and ResourceLoader.exists(strip):
		_fit_model(rudder, blade)
		var hinges := Node3D.new()
		hinges.name = "Hinges"
		rudder.add_child(hinges)
		_fit_model(hinges, strip)
	else:
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		# The hinge post. The blade's forward edge is this axis.
		_spar(rudder, -0.5, 0.08, 0.08, 2.0, iron)
		# Wider at the foot, shorter under the counter, still inside the kit's box.
		for i in 6:
			var t := float(i) / 5.0
			var y := -1.35 + t * 1.7
			var length := lerpf(0.95, 0.55, t)
			_box(rudder, Vector3(0.0, y, 0.08 + length * 0.5), Vector3(0.16, 0.26, length), timber)
		_box(rudder, Vector3(0.0, -0.5, 0.35), Vector3(0.2, 1.7, 0.06), iron)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.24, 2.0, 1.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.5)
	body.add_child(shape)
	rudder.add_child(body)


## The F05 capstan model, or a drum and two bars inside the kit's capstan box.
## The node is named Capstan and sits on CAPSTAN_AT so the swap is a mesh, not a new place.
## Only the drum collides. The bars are the working radius, and a solid box that wide would
## close the gun deck's walk between the guns.
func _build_capstan() -> void:
	if get_node_or_null("Capstan") != null:
		return
	var capstan := Node3D.new()
	capstan.name = "Capstan"
	capstan.position = CAPSTAN_AT
	add_child(capstan)
	if not _fit_model(capstan, FITTINGS + "capstan.glb"):
		var timber := _flat(Color(0.55, 0.36, 0.18))
		var iron := _flat(Color(0.22, 0.22, 0.24))
		_spar(capstan, 0.08, 0.55, 0.55, 0.16, timber)
		_spar(capstan, 0.52, 0.34, 0.28, 0.72, timber)
		_spar(capstan, 0.7, 0.36, 0.36, 0.06, iron)
		_spar(capstan, 0.98, 0.42, 0.5, 0.2, timber)
		# Two bars through the head, out to the 1.4 m bound on each axis.
		_box(capstan, Vector3(0.0, 0.88, 0.0), Vector3(2.8, 0.08, 0.08), timber)
		_box(capstan, Vector3(0.0, 0.88, 0.0), Vector3(0.08, 0.08, 2.8), timber)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var col := CylinderShape3D.new()
	col.radius = 0.5
	col.height = 1.1
	shape.shape = col
	shape.position = Vector3(0.0, 0.55, 0.0)
	body.add_child(shape)
	capstan.add_child(body)


## The fittings with no placeholder to replace: a binnacle ahead of the wheel, a collar where
## each mast meets the deck, the lantern on the stern rail, and a frame and lid on every
## gunport. Each is placed only if its model is there - none of them is something the ship
## needs in order to work.
func _build_deck_fittings() -> void:
	if get_node_or_null("DeckFittings") != null:
		return
	var fittings := Node3D.new()
	fittings.name = "DeckFittings"
	add_child(fittings)

	var binnacle := Node3D.new()
	binnacle.name = "Binnacle"
	binnacle.position = BINNACLE_AT
	fittings.add_child(binnacle)
	if _fit_model(binnacle, FITTINGS + "binnacle.glb"):
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var col := CylinderShape3D.new()
		col.radius = 0.3
		col.height = 1.1
		shape.shape = col
		shape.position = Vector3(0.0, 0.55, 0.0)
		body.add_child(shape)
		binnacle.add_child(body)

	# The collar's hole is 0.52 m across, for the mainmast's 0.5 m foot; the foremast is thinner.
	for spot in [["MastCollar", MAST_AT], ["ForemastCollar", FOREMAST_AT]]:
		var collar := Node3D.new()
		collar.name = spot[0]
		collar.position = spot[1]
		fittings.add_child(collar)
		_fit_model(collar, DECK_PARTS + "mast_collar.glb")

	# The model's origin is the top of its wall plate, and the lantern hangs aft of it (+Z).
	var lantern := Node3D.new()
	lantern.name = "SternLantern"
	lantern.position = LANTERN_AT
	fittings.add_child(lantern)
	_fit_model(lantern, FITTINGS + "stern_lantern.glb")

	# The frame faces +X with its back on the hull, centred on its opening; turned half round
	# it serves the port side. The lid is its own node hung on its hinge: +Z swings it out.
	var lids := Node3D.new()
	lids.name = "GunportLids"
	fittings.add_child(lids)
	for z in GUN_PORT_Z:
		for side in [1.0, -1.0]:
			var port := Node3D.new()
			port.name = "Port%s%d" % ["Starboard" if side > 0.0 else "Port", int(z)]
			port.position = Vector3(side * BEAM * 0.5, GUN_PORT_Y, z)
			port.rotation_degrees.y = 0.0 if side > 0.0 else 180.0
			lids.add_child(port)
			if _fit_model(port, HULL_PARTS + "gunport_lid.glb"):
				var lid := port.find_child("lid", true, false) as Node3D
				if lid != null:
					lid.rotation_degrees.z = LID_OPEN_DEGREES

	for entry in DECK_PROPS:
		var prop := Node3D.new()
		prop.name = entry[0]
		prop.position = entry[2]
		prop.rotation_degrees.y = entry[3]
		fittings.add_child(prop)
		if not _fit_model(prop, "res://art/models/ship/" + entry[1]):
			continue
		if prop.name == "Hatch":
			# The grating rests on the coaming and covers its opening.
			var top := _mesh_bounds(prop).end.y
			var grating := Node3D.new()
			grating.name = "Grating"
			grating.position = Vector3(0.0, top, 0.0)
			prop.add_child(grating)
			_fit_model(grating, FITTINGS + "hatch_grating.glb")
		if entry[4]:
			_solid(prop)

	# One cathead on each bow, the anchor hanging from its fall. The port one is the same model
	# turned the other way rather than mirrored, so its texture and winding stay right.
	for side in [1.0, -1.0]:
		var cathead := Node3D.new()
		cathead.name = "CatheadStarboard" if side > 0.0 else "CatheadPort"
		cathead.position = Vector3(side * CATHEAD_AT.x, CATHEAD_AT.y, CATHEAD_AT.z)
		cathead.rotation_degrees.y = CATHEAD_YAW if side > 0.0 else 180.0 - CATHEAD_YAW
		fittings.add_child(cathead)
		if _fit_model(cathead, FITTINGS + "cathead.glb"):
			var anchor := Node3D.new()
			anchor.name = "Anchor"
			anchor.position = CATHEAD_FALL
			# Flukes fore and aft, along the bow, rather than across it into the planking.
			anchor.rotation_degrees.y = 90.0
			cathead.add_child(anchor)
			_fit_model(anchor, FITTINGS + "anchor.glb")

	# Beams under the weather deck, seen from the gun deck. The model's origin is its top
	# centre, so it hangs from the underside of the 0.18 m slab.
	var beams := Node3D.new()
	beams.name = "DeckBeams"
	fittings.add_child(beams)
	for z in DECK_BEAM_Z:
		var beam := Node3D.new()
		beam.name = "Beam%d" % int(z)
		beam.position = Vector3(0.0, DECK_Y - 0.18, z)
		beams.add_child(beam)
		_fit_model(beam, DECK_PARTS + "deck_beam.glb")


## Bounds of every mesh under `node`, in `node`'s own space.
func _mesh_bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_local := node.global_transform.affine_inverse()
	for child in _descendants(node):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			var mesh_node := child as MeshInstance3D
			var here: AABB = to_local * mesh_node.global_transform * mesh_node.mesh.get_aabb()
			box = here if first else box.merge(here)
			first = false
	return box


## A box collider the size of the model, so a coil or a hatch cannot be walked through. Taken
## from the meshes rather than typed in, so it follows the model if the model changes.
func _solid(node: Node3D) -> void:
	var box := _mesh_bounds(node)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = box.size
	shape.shape = cube
	shape.position = box.get_center()
	body.add_child(shape)
	node.add_child(body)


## The course hangs from its yard. The jib runs from the foremast to the bowsprit.
func _build_sail() -> void:
	if get_node_or_null("Mast") == null:
		return
	var old_sail := get_node_or_null("Sail")
	if old_sail != null:
		old_sail.free()
	var sail := SailScript.new() as Node3D
	sail.name = "Sail"
	sail.call("pin_foot", false)
	# The foot hangs free, and a breeze from astern swings it back over the quarterdeck's
	# forward edge. The cloth drapes on the cabin instead of hanging through it.
	var cabin := get_node_or_null("Quarterdeck/Cabin") as Node3D
	if cabin != null:
		var box := _mesh_bounds(cabin)
		box.position += cabin.position
		sail.call("keep_out", box.grow(0.05))
	add_child(sail)
	if get_node_or_null("Foremast") == null or get_node_or_null("Bowsprit") == null:
		return
	var old_jib := get_node_or_null("Jib")
	if old_jib != null:
		old_jib.free()
	var sprit := Basis(Vector3.RIGHT, deg_to_rad(-77.0))
	var foot_from: Vector3 = BOWSPRIT_AT + sprit * Vector3(0.0, 0.4, 0.0)
	var foot_to: Vector3 = BOWSPRIT_AT + sprit * Vector3(0.0, 2.85, 0.0)
	# A short span on the forward side of the foremast head.
	var head_from := FOREMAST_AT + Vector3(0.0, 3.5, -0.22)
	var head_to := FOREMAST_AT + Vector3(0.0, 4.15, -0.22)
	var jib := SailScript.new() as Node3D
	jib.name = "Jib"
	jib.call("rig_between", head_from, head_to, foot_from, foot_to, Vector3(0.35, 0.0, 0.0))
	add_child(jib)


## A shorter course above the lookout. The topmast was a bare pole past the platform.
func _build_topsail() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	if mast == null:
		return
	var timber := _flat(Color(0.55, 0.36, 0.18))
	var iron := _flat(Color(0.22, 0.22, 0.24))
	# Just under the tip, and just clear of the lookout rails. Shorter than the course yard.
	_crossyard(mast, "TopsailYard", 8.15, 2.6, 0.09, timber, iron)
	_crossyard(mast, "TopsailFoot", 6.9, 2.6, 0.07, timber, iron)
	if get_node_or_null("Topsail") != null:
		return
	var head_y := MAST_AT.y + 8.15
	var foot_y := MAST_AT.y + 6.9
	var z := MAST_AT.z + 0.12
	var half := 2.3
	var sail := SailScript.new() as Node3D
	sail.name = "Topsail"
	sail.call("rig_between", Vector3(-half, head_y, z), Vector3(half, head_y, z), Vector3(-half, foot_y, z), Vector3(half, foot_y, z), Vector3(0.0, 0.0, 0.3))
	add_child(sail)


func _crossyard(mast: Node3D, yard_name: String, y: float, half: float, thick: float, timber: Material, iron: Material) -> void:
	if mast.get_node_or_null(yard_name) != null:
		return
	var yard := Node3D.new()
	yard.name = yard_name
	yard.position = Vector3(0.0, y, 0.12)
	mast.add_child(yard)
	# The M06 model is 5.2 m, the same as 2 * half, and already runs along X from its sling.
	if _fit_model(yard, RIGGING + "topsail_yard.glb"):
		return
	yard.rotation_degrees.z = -90.0
	_spar(yard, -half * 0.5, thick * 0.55, thick, half, timber)
	_spar(yard, half * 0.5, thick, thick * 0.55, half, timber)
	_spar(yard, 0.0, thick + 0.04, thick + 0.04, 0.1, iron)


## One rope a side from the topmast head down to the stern quarters. The shrouds hold the
## mast sideways; these hold it aft. No collision, same as the shrouds.
func _build_backstays() -> void:
	if get_node_or_null("Mast") == null or get_node_or_null("Backstays") != null:
		return
	var stays := Node3D.new()
	stays.name = "Backstays"
	add_child(stays)
	var rope := _flat(Color(0.45, 0.34, 0.22))
	# Just above the topsail yard and a little aft of it, so the rope clears the cloth.
	var head_y := MAST_AT.y + 8.4
	var head_z := MAST_AT.z + 0.35
	for side in [-1.0, 1.0]:
		var head := Vector3(side * 0.22, head_y, head_z)
		var foot := Vector3(side * 2.3, 6.0, 15.2)
		_rope(stays, head, foot, 0.02, rope)


## Three ropes a side, from just under the lookout to the rail, and the ratlines across them.
## No collision: a solid cage here would close the deck. A real rope mesh can replace this node.
func _build_shrouds() -> void:
	var mast := get_node_or_null("Mast") as Node3D
	if mast == null:
		return
	var old := mast.get_node_or_null("Shrouds")
	if old != null:
		old.free()
	var shrouds := Node3D.new()
	shrouds.name = "Shrouds"
	mast.add_child(shrouds)
	var rope := _flat(Color(0.45, 0.34, 0.22))
	# Mast-local, and all of them forward of the sail. Port stays on the port side, starboard
	# on the starboard side, so a rope never crosses the spar or the cloth.
	var upper_z: Array[float] = [-0.55, -0.4, -0.25]
	var lower_z: Array[float] = [-1.15, -0.55, -0.2]
	for side in [-1.0, 1.0]:
		var tops: Array[Vector3] = []
		var feet: Array[Vector3] = []
		for i in 3:
			var top := Vector3(side * 0.42, 5.25, upper_z[i])
			var foot := Vector3(side * 2.95, 0.8, lower_z[i])
			tops.append(top)
			feet.append(foot)
			_rope(shrouds, top, foot, 0.02, rope)
		var steps := int(tops[0].distance_to(feet[0]) / 0.42)
		for s in range(1, steps):
			var t := float(s) / float(steps)
			for i in 2:
				_rope(shrouds, tops[i].lerp(feet[i], t), tops[i + 1].lerp(feet[i + 1], t), 0.012, rope)


func _rope(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> void:
	var span := b - a
	var length := span.length()
	if length < 0.001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	var y := span / length
	var x := y.cross(Vector3.UP)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = (a + b) * 0.5
	node.basis = Basis(x, y, x.cross(y))
	node.material_override = material
	parent.add_child(node)


## One of the cannon prefabs behind each gunport, barrel out through the opening.
func _build_guns() -> void:
	if get_node_or_null("Guns") != null:
		return
	var guns := Node3D.new()
	guns.name = "Guns"
	add_child(guns)
	for z in GUN_PORT_Z:
		# Muzzle is 1 m along local -Z and 0.62 m up. -90° yaw sends -Z to starboard.
		_gun(guns, Vector3(2.15, GUN_DECK_Y + 0.58, z), -PI * 0.5, "Starboard")
		_gun(guns, Vector3(-2.15, GUN_DECK_Y + 0.58, z), PI * 0.5, "Port")


func _gun(parent: Node3D, at: Vector3, yaw: float, side: String) -> void:
	var gun := CannonScene.instantiate() as Node3D
	gun.name = "Cannon%s%d" % [side, int(at.z)]
	gun.position = at
	gun.rotation.y = yaw
	gun.set("sit_on_ground", false)
	# A gun in a hull is a different weapon from the one on the hill, and these four numbers
	# are the whole difference. It swings inside its port rather than anywhere, it cannot be
	# lobbed, and it looks out through the opening instead of over the player's shoulder - so
	# a broadside is aimed by turning the ship and fired on timing, not by judging an arc.
	gun.set("traverse_limit", 22.0)
	gun.set("min_elevation", 0.0)
	gun.set("max_elevation", 14.0)
	gun.set("rest_elevation", 3.0)
	gun.set("first_person", true)
	parent.add_child(gun)


func _spar(parent: Node3D, y: float, bottom: float, top: float, height: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3(0.0, y, 0.0)
	node.material_override = material
	parent.add_child(node)


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
