extends SceneTree
## Run: godot --headless --path . --script res://tests/ship_fittings_check.gd
##
## Are the real fittings on the ship, and are they where the placeholders stood?
##
## ship.gd loads each model into the node its placeholder used to fill, and falls back to the
## placeholder when a file is missing. That fallback is the danger: a renamed or deleted .glb
## puts the grey boxes back without a single error, and the ship still sails. So this asks for
## the model in every slot, by name.
##
## Placement is measured on the meshes, in ship space, never on the nodes - an imported
## model's node can sit anywhere its exporter left it (see placement_check.gd). What a
## wrong origin or scale would show is a helm hovering over the deck, a mast whose head is not
## where the topmast starts, or a bowsprit pointing into the hull.

const Ship := preload("res://props/ship/ship.gd")
## Metres a part may sit off its mark. Seats and heads are exact in the models; this is float
## room and the import's own rounding, not slack for a misplaced part.
const TOLERANCE := 0.03

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 10:
		await process_frame
	var ship := scene.get_node_or_null("Ship") as Node3D
	check(ship != null, "no ship in the scene")
	if ship == null:
		_finish()
		return

	# Every slot holds its model, not the placeholder built when the file was missing.
	for path in ["Helm", "Capstan", "Foremast", "Bowsprit", "Rudder", "Rudder/Hinges",
			"Mast/Lower", "Mast/Topmast", "Mast/Top", "Mast/Yard", "Mast/TopsailYard",
			"Mast/TopsailFoot", "DeckFittings/Binnacle", "DeckFittings/MastCollar",
			"DeckFittings/ForemastCollar", "DeckFittings/SternLantern", "Quarterdeck/Cabin",
			"Quarterdeck/Stairs", "Mizzen", "Mizzen/Boom", "Mizzen/Gaff", "DeckFittings/MizzenCollar"]:
		var slot := ship.get_node_or_null(path)
		check(slot != null and slot.get_node_or_null("Model") != null,
				"%s has no model - its .glb is missing and the placeholder was built instead" % path)

	# Fittings stand ON their deck: not hovering, not sunk into the slab. The wheel and the
	# binnacle are up on the quarterdeck, the capstan down on the gun deck.
	var decks := {"Helm": Ship.QUARTERDECK_Y, "Capstan": Ship.GUN_DECK_Y,
			"DeckFittings/Binnacle": Ship.QUARTERDECK_Y, "DeckFittings/MastCollar": Ship.DECK_Y,
			"Quarterdeck/Cabin": Ship.DECK_Y, "Quarterdeck/Stairs": Ship.DECK_Y,
			"Mizzen": Ship.QUARTERDECK_Y, "DeckFittings/MizzenCollar": Ship.QUARTERDECK_Y}
	for path in decks:
		var box := _bounds(ship, ship.get_node_or_null(path))
		check(absf(box.position.y - decks[path]) <= TOLERANCE,
				"%s's foot is at %.3f, its deck is at %.2f" % [path, box.position.y, decks[path]])

	# The helmsman stands aft of the wheel: the whole helm must be forward of his feet, and
	# the binnacle forward of the helm.
	var helm := _bounds(ship, ship.get_node_or_null("Helm"))
	check(helm.end.z < Ship.HELM_FEET.z, "the helm reaches %.2f, past the helmsman's feet at %.2f"
			% [helm.end.z, Ship.HELM_FEET.z])
	var binnacle := _bounds(ship, ship.get_node_or_null("DeckFittings/Binnacle"))
	check(not binnacle.intersects(helm), "the binnacle overlaps the helm")

	# The masts: the lower mast's head is where the topmast's heel sits, 5.5 m up, and the
	# topmast ends 3 m above that - the lengths ship.gd's sails and ropes are rigged to.
	var lower := _bounds(ship, ship.get_node_or_null("Mast/Lower"))
	var topmast := _bounds(ship, ship.get_node_or_null("Mast/Topmast"))
	check(absf(lower.position.y - Ship.DECK_Y) <= TOLERANCE, "the mainmast does not stand on the deck")
	check(absf(lower.end.y - (Ship.DECK_Y + 5.5)) <= TOLERANCE,
			"the mainmast's head is at %.3f, not 5.5 m above the deck" % lower.end.y)
	check(absf(topmast.position.y - lower.end.y) <= TOLERANCE, "the topmast does not sit on the mainmast's head")
	check(absf(topmast.end.y - (Ship.DECK_Y + 8.5)) <= TOLERANCE,
			"the topmast ends at %.3f, not 8.5 m above the deck" % topmast.end.y)
	var fore := _bounds(ship, ship.get_node_or_null("Foremast"))
	check(absf(fore.size.y - 4.2) <= TOLERANCE, "the foremast is %.2f m, not 4.2" % fore.size.y)
	var yard := _bounds(ship, ship.get_node_or_null("Mast/Yard"))
	check(absf(yard.size.x - 8.0) <= TOLERANCE and yard.size.z < 0.5,
			"the course yard is %.2f m across and %.2f deep - it should run 8 m athwartships"
			% [yard.size.x, yard.size.z])

	# The mast top wraps the joint: its collar clears the course yard below, and its rim sits
	# between the mast head and the rail ring the lookout's posts carry (6.6 m up).
	var top := _bounds(ship, ship.get_node_or_null("Mast/Top"))
	check(top.position.y >= yard.end.y - TOLERANCE,
			"the mast top's collar comes down to %.2f, into the course yard (top at %.2f)" % [top.position.y, yard.end.y])
	check(top.end.y > Ship.DECK_Y + 5.5 and top.end.y <= Ship.DECK_Y + 6.6,
			"the mast top's rim is at %.2f, not between the mast head and the rail ring" % top.end.y)

	# The bowsprit reaches forward of its mount and rises, as the jib and bobstay expect.
	var sprit := _bounds(ship, ship.get_node_or_null("Bowsprit"))
	check(sprit.position.z < Ship.BOWSPRIT_AT.z - 2.5, "the bowsprit does not reach forward of its mount")
	check(sprit.end.y > Ship.BOWSPRIT_AT.y + 0.4, "the bowsprit does not rise toward its tip")

	# The rudder blade hangs aft of its hinge; the strip is forward of it.
	var blade := _bounds(ship, ship.get_node_or_null("Rudder/Model"))
	var strip := _bounds(ship, ship.get_node_or_null("Rudder/Hinges"))
	check(blade.position.z >= Ship.RUDDER_AT.z - TOLERANCE, "the rudder blade reaches forward of its hinge")
	check(strip.end.z <= Ship.RUDDER_AT.z + TOLERANCE, "the hinge strip is aft of the hinge")

	# A frame on every port, on the hull's side, and every lid standing open above its port.
	var lids := ship.get_node_or_null("GunPorts/Lids")
	var ports := 0 if lids == null else lids.get_child_count()
	var wanted: int = (ship as Ship).gun_port_count * 2
	check(ports == wanted, "%d gunport frames for %d ports" % [ports, wanted])
	if lids != null:
		for port in lids.get_children():
			var lid := port.find_child("lid", true, false) as Node3D
			check(lid != null, "%s has no lid node" % port.name)
			if lid == null:
				continue
			var shut := _bounds(ship, lid)
			check(shut.position.y >= Ship.GUN_PORT_Y + 0.25,
					"%s's lid comes down to %.2f, into its port (centre %.2f)" % [port.name, shut.position.y, Ship.GUN_PORT_Y])
			var frame := _bounds(ship, port.find_child("frame", true, false) as Node3D)
			check(absf(absf(frame.position.x + frame.size.x * 0.5) - Ship.BEAM * 0.5) <= 0.3,
					"%s's frame is not on the hull's side" % port.name)

	_check_gun_ports(ship)
	_check_deck_props(ship)
	_check_catheads(ship)
	_check_beams(ship)
	_check_quarterdeck(ship)
	_check_windows(ship)
	_check_castle_trim(ship)
	_check_rail(ship)
	_check_wale(ship)
	_check_rigging(ship)
	_check_flag_rings(ship)
	await _check_mizzen(ship)
	await _check_course_clears_cabin(ship)
	await _check_flag_flies_downwind(ship)

	# The hull carries the plank texture: its wood material has a texture, not a flat colour.
	var textured := false
	for node in ship.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.albedo_texture != null:
				textured = true
	check(textured, "the hull has no plank texture")
	_finish()


## The gunports: a hole in the gun deck's wall at every port, open through, solid wall between
## them, the wall planked like the hull, and a gun behind every hole. Changing the count moves
## the holes, frames and guns together.
func _check_gun_ports(ship: Node3D) -> void:
	var typed := ship as Ship
	for wall in ["GunPorts/WallStarboard", "GunPorts/WallPort"]:
		var node := ship.get_node_or_null(wall) as MeshInstance3D
		var material := null if node == null else node.material_override as BaseMaterial3D
		check(node != null and material != null and material.albedo_texture != null,
				"%s is missing or not planked like the hull" % wall)
	_check_port_holes(ship, typed.gun_port_z())
	var before := typed.gun_port_count
	typed.gun_port_count = 3
	check(ship.get_node("GunPorts/Lids").get_child_count() == 6 and ship.get_node("GunPorts/Guns").get_child_count() == 6,
			"with 3 ports a side there should be 6 frames and 6 guns")
	_check_port_holes(ship, typed.gun_port_z())
	typed.gun_port_count = before


func _check_port_holes(ship: Node3D, spots: Array[float]) -> void:
	var space := ship.get_world_3d().direct_space_state
	var guns := ship.get_node("GunPorts/Guns")
	for side in [1.0, -1.0]:
		for z in spots:
			# Through the hole, clear of the barrel: nothing between the gun deck and the sea.
			var through := Vector3(0.0, Ship.GUN_PORT_Y + 0.25, z + 0.35)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
					ship.to_global(through + Vector3(side * 2.5, 0.0, 0.0)), ship.to_global(through + Vector3(side * 3.6, 0.0, 0.0))))
			check(hit.is_empty(), "the port at z %.2f on the %s side is not open" % [z, "starboard" if side > 0.0 else "port"])
			var gun: Node3D = null
			for g in guns.get_children():
				if absf((g as Node3D).position.z - z) < 0.01 and signf((g as Node3D).position.x) == side:
					gun = g as Node3D
			check(gun != null, "no gun behind the port at z %.2f" % z)
			if gun == null:
				continue
			# On the deck, on its wheels, with its barrel level with the opening.
			var box := _bounds(ship, gun)
			check(absf(box.position.y - Ship.GUN_DECK_Y) <= TOLERANCE,
					"the gun at z %.2f stands at %.2f, not on the gun deck at %.2f" % [z, box.position.y, Ship.GUN_DECK_Y])
			var barrel := _bounds(ship, gun.call("barrel") as Node3D)
			check(absf(barrel.get_center().y - Ship.GUN_PORT_Y) <= 0.05,
					"the gun at z %.2f aims at %.2f, not through its port at %.2f" % [z, barrel.get_center().y, Ship.GUN_PORT_Y])
		# Between ports, and past the ends: solid wall.
		var solid: Array[float] = [Ship.GUN_WALL_FORE_Z + 0.2, Ship.GUN_WALL_AFT_Z - 0.2]
		for i in spots.size() - 1:
			solid.append((spots[i] + spots[i + 1]) * 0.5)
		for z in solid:
			var at := Vector3(side * 2.5, Ship.GUN_PORT_Y, z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(at), ship.to_global(at + Vector3(side * 1.1, 0.0, 0.0))))
			var wall := absf(ship.to_local(hit.position).x) if not hit.is_empty() else INF
			check(absf(wall - Ship.GUN_WALL_INNER_X) <= 0.01, "the gun deck wall is open at z %.2f (met %.2f)" % [z, wall])


## Everything standing on a deck: on it, on solid planks, and out of each other's way.
func _check_deck_props(ship: Node3D) -> void:
	var standing := {}
	for entry in Ship.DECK_PROPS:
		var path: String = "DeckFittings/" + entry[0]
		var node := ship.get_node_or_null(path) as Node3D
		check(node != null and node.get_node_or_null("Model") != null, "%s has no model" % path)
		if node == null:
			continue
		var box := _bounds(ship, node.get_node_or_null("Model"))
		var deck: float = (entry[2] as Vector3).y
		check(absf(box.position.y - deck) <= TOLERANCE,
				"%s's foot is at %.3f, its deck is at %.2f" % [path, box.position.y, deck])
		standing[path] = box
	for path in ["Helm", "Capstan", "DeckFittings/Binnacle", "DeckFittings/MastCollar",
			"DeckFittings/ForemastCollar", "Quarterdeck/Stairs"]:
		standing[path] = _bounds(ship, ship.get_node_or_null(path))
	# Nothing on the weather deck stands in the cabin; the stairs land in its front on purpose.
	var cabin := _bounds(ship, ship.get_node_or_null("Quarterdeck/Cabin"))
	for path in standing:
		var box: AABB = standing[path]
		if path != "Quarterdeck/Stairs" and box.position.y < Ship.DECK_Y + 0.5:
			check(not box.intersects(cabin), "%s stands in the stern cabin" % path)

	var hatch := ship.get_node_or_null("DeckFittings/Hatch") as Node3D
	if hatch != null:
		var coaming := _bounds(ship, hatch.get_node_or_null("Model"))
		var grating := _bounds(ship, hatch.get_node_or_null("Grating"))
		check(absf(grating.position.y - coaming.end.y) <= TOLERANCE,
				"the hatch grating is at %.3f, not resting on the coaming's top at %.3f" % [grating.position.y, coaming.end.y])

	# Nothing overlaps anything else, or the stair opening the captain climbs out of.
	var shaft := AABB(Vector3(-0.55, Ship.DECK_Y, 4.0), Vector3(1.1, 2.0, 3.25))
	var names := standing.keys()
	for i in names.size():
		var a: AABB = standing[names[i]]
		check(not a.intersects(shaft), "%s stands in the stair opening" % names[i])
		for j in range(i + 1, names.size()):
			check(not a.intersects(standing[names[j]]), "%s and %s overlap" % [names[i], names[j]])

	# On solid planks: a short ray down just inside each corner of the footprint must meet the
	# deck the fitting stands on. Over the stair shaft it would fall to the stairs, outboard of
	# the bulwark it would meet nothing - or the bulwark - and off the quarterdeck's edge it
	# would drop to the weather deck.
	var space := ship.get_world_3d().direct_space_state
	var footing := {}
	for entry in Ship.DECK_PROPS:
		footing["DeckFittings/" + entry[0]] = (entry[2] as Vector3).y
	footing["Helm"] = Ship.QUARTERDECK_Y
	footing["DeckFittings/Binnacle"] = Ship.QUARTERDECK_Y
	footing["Capstan"] = Ship.GUN_DECK_Y
	for path in footing:
		if not standing.has(path):
			continue
		var box: AABB = standing[path]
		var deck: float = footing[path]
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var x := lerpf(box.position.x + 0.05, box.end.x - 0.05, corner.x)
			var z := lerpf(box.position.z + 0.05, box.end.z - 0.05, corner.y)
			var hit := _ray_down(ship, Vector3(x, deck + 0.03, z), 0.33)
			var y := ship.to_local(hit.position).y if not hit.is_empty() else -INF
			check(absf(y - deck) <= 0.05,
					"%s's corner at (%.2f, %.2f) is not over its deck (ray met %.2f)" % [path, x, z, y])


## A cathead on each bow with its anchor hanging clear: outboard of the hull, above the water.
func _check_catheads(ship: Node3D) -> void:
	var space := ship.get_world_3d().direct_space_state
	for side in ["CatheadStarboard", "CatheadPort"]:
		var path: String = "DeckFittings/" + side
		var cathead := ship.get_node_or_null(path) as Node3D
		check(cathead != null and cathead.get_node_or_null("Model") != null, "%s has no model" % path)
		var anchor: Node3D = null if cathead == null else cathead.get_node_or_null("Anchor") as Node3D
		check(anchor != null and anchor.get_node_or_null("Model") != null, "%s has no anchor" % path)
		if anchor == null:
			continue
		var box := _bounds(ship, anchor)
		check(box.position.y > Ship.DRAFT + 0.3,
				"%s's anchor hangs down to %.2f, into the sea (waterline %.1f)" % [path, box.position.y, Ship.DRAFT])
		# Outboard of the hull: from the anchor's centre, straight out, there is no more hull.
		var centre := box.get_center()
		var out := signf(centre.x)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				ship.to_global(centre), ship.to_global(centre + Vector3(out * 3.0, 0.0, 0.0))))
		check(hit.is_empty(), "%s's anchor hangs inside the hull" % path)


## Beams under the weather deck: against the slab, with headroom under them, none over the stairs.
func _check_beams(ship: Node3D) -> void:
	var beams := ship.get_node_or_null("DeckFittings/DeckBeams")
	check(beams != null and beams.get_child_count() == Ship.DECK_BEAM_Z.size(), "the deck beams are missing")
	if beams == null:
		return
	var to_ship := ship.global_transform.affine_inverse()
	for beam in beams.get_children():
		var box := _bounds(ship, beam as Node3D)
		check(absf(box.end.y - (Ship.DECK_Y - 0.18)) <= TOLERANCE,
				"%s's top is at %.3f, not under the slab at %.2f" % [beam.name, box.end.y, Ship.DECK_Y - 0.18])
		check(box.end.z < 4.0 - 0.3 or box.position.z > 7.25 + 0.3, "%s crosses the stair shaft" % beam.name)
		# Headroom across the middle, where the captain walks: the knees may come lower by the hull.
		var lowest := INF
		for m in (beam as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mesh_node := m as MeshInstance3D
			for surface in mesh_node.mesh.get_surface_count():
				for v in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var p: Vector3 = to_ship * mesh_node.global_transform * v
					if absf(p.x) < 1.2:
						lowest = minf(lowest, p.y)
		check(lowest >= Ship.GUN_DECK_Y + 1.95,
				"%s comes down to %.2f over the gun deck's middle; the captain is 1.9 m tall" % [beam.name, lowest])


## The stern castle and its roof, the quarterdeck: the hull's own sides carried up, level,
## reached by the stairs, and holding the wheel with room for the helmsman behind it.
func _check_quarterdeck(ship: Node3D) -> void:
	var cabin_node := ship.get_node_or_null("Quarterdeck/Cabin") as Node3D
	var stairs_node := ship.get_node_or_null("Quarterdeck/Stairs") as Node3D
	if cabin_node == null or stairs_node == null:
		check(false, "the quarterdeck is missing")
		return
	var space := ship.get_world_3d().direct_space_state
	var cabin := _bounds(ship, cabin_node)

	# The castle is the hull carried up: at every station along it, its side starts where the
	# hull's side ends at the deck, to 2 cm, on both sides and round the stern. (Round the stern
	# the hull flares out as it rises; the castle's walls go straight up from the deck line.)
	var station := Ship.CASTLE_FRONT_Z + 0.05
	while station < cabin.end.z - 0.05:
		for side in [-1.0, 1.0]:
			var faces: Array[float] = []
			for y in [Ship.DECK_Y - 0.03, Ship.DECK_Y + 0.03]:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
						ship.to_global(Vector3(side * 4.0, y, station)), ship.to_global(Vector3(0.0, y, station))))
				faces.append(absf(ship.to_local(hit.position).x) if not hit.is_empty() else -1.0)
			check(faces[0] > 0.0 and absf(faces[0] - faces[1]) <= 0.02,
					"at z %.1f the castle's side is at %.2f, the hull's at %.2f" % [station, faces[1], faces[0]])
		station += 0.25
	check(absf(cabin.position.z - Ship.CASTLE_FRONT_Z) <= TOLERANCE,
			"the castle's front is at %.2f, not CASTLE_FRONT_Z %.2f" % [cabin.position.z, Ship.CASTLE_FRONT_Z])
	check(absf(cabin.end.y - Ship.QUARTERDECK_Y) <= TOLERANCE, "the castle's roof is at %.2f" % cabin.end.y)

	# The roof is level and walkable: every sample inside its rails is at the quarterdeck's
	# height, apart from the fittings standing on it.
	var fittings: Array[AABB] = []
	for path in ["Helm", "DeckFittings/Binnacle", "DeckFittings/CoilQuarterdeck", "DeckFittings/CleatStarboardAft",
			"DeckFittings/CleatPortAft"]:
		fittings.append(_bounds(ship, ship.get_node_or_null(path)))
	for i in 9:
		for j in 14:
			var at := Vector3(-1.2 + 0.3 * i, Ship.QUARTERDECK_Y + 1.5, 10.8 + 0.28 * j)
			var covered := false
			for box in fittings:
				covered = covered or (at.x > box.position.x - 0.05 and at.x < box.end.x + 0.05
						and at.z > box.position.z - 0.05 and at.z < box.end.z + 0.05)
			if covered:
				continue
			var hit := _ray_down(ship, at, 2.5)
			var y := ship.to_local(hit.position).y if not hit.is_empty() else -INF
			check(absf(y - Ship.QUARTERDECK_Y) <= 0.06,
					"the quarterdeck at (%.1f, %.1f) is at %.2f, not %.2f" % [at.x, at.z, y, Ship.QUARTERDECK_Y])

	# Up the stairs and aft to the wheel's side: no step higher than the captain's step, and
	# his body - 0.35 m round, 1.9 m tall - fits all the way with 2 cm to spare, lifted by one
	# step for the stairs. Between the stair rails, too.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.37
	capsule.height = 1.9
	var body := PhysicsShapeQueryParameters3D.new()
	body.shape = capsule
	var x := Ship.QUARTERDECK_STAIRS_AT.x
	var last := Ship.DECK_Y
	var z := Ship.QUARTERDECK_STAIRS_AT.z - 1.0
	while z <= Ship.HELM_FEET.z:
		# The treads have open risers, and a foot is wider than the gap: the highest of three
		# rays across 20 cm is what he stands on, not a single ray that slips between two.
		var y := -INF
		for step in [-0.1, 0.0, 0.1]:
			var hit := _ray_down(ship, Vector3(x, Ship.QUARTERDECK_Y + 2.5, z + step), 5.5)
			if not hit.is_empty():
				y = maxf(y, ship.to_local(hit.position).y)
		check(y - last <= 0.35 and y - last >= -0.35,
				"the way up to the quarterdeck jumps from %.2f to %.2f at z %.2f" % [last, y, z])
		body.transform = Transform3D(ship.global_basis, ship.to_global(Vector3(x, y + 0.35 + 0.95, z)))
		var blocked := space.intersect_shape(body, 1)
		check(blocked.is_empty(), "the captain does not fit on the way up at z %.2f (height %.2f)" % [z, y])
		last = y
		z += 0.05
	check(absf(last - Ship.QUARTERDECK_Y) <= 0.06, "the stairs do not reach the quarterdeck (%.2f)" % last)

	# The helmsman's spot: on the roof, and room for him between the wheel and the stern rail.
	var feet := _ray_down(ship, Ship.HELM_FEET + Vector3(0.0, 0.5, 0.0), 1.0)
	check(not feet.is_empty() and absf(ship.to_local(feet.position).y - Ship.QUARTERDECK_Y) <= 0.06,
			"the helmsman's feet are not on the quarterdeck")
	body.transform = Transform3D(ship.global_basis, ship.to_global(Ship.HELM_FEET + Vector3(0.0, 0.05 + 0.95, 0.0)))
	check(space.intersect_shape(body, 1).is_empty(), "the helmsman does not fit behind the wheel")
	check(Ship.HELM_AT.x > cabin.position.x and Ship.HELM_AT.x < cabin.end.x
			and Ship.HELM_AT.z > cabin.position.z and Ship.HELM_AT.z < cabin.end.z, "the wheel is not over the cabin")

	# The wheel answers from the quarterdeck only, not from the weather deck under it.
	var probe := Node3D.new()
	ship.add_child(probe)
	probe.position = Ship.HELM_FEET + Vector3(0.0, 0.1, 0.0)
	check(ship.can_helm(probe), "the helmsman's spot is out of the wheel's reach")
	probe.position = Vector3(Ship.HELM_AT.x, Ship.DECK_Y + 0.1, Ship.HELM_AT.z)
	check(not ship.can_helm(probe), "the wheel answers from the deck under the quarterdeck")
	probe.free()


## The rail that replaced the bulwark: the wall is gone, the rail is built from the models,
## its posts are evenly spaced and each stands on the hull's edge, and it collides without a gap.
func _check_rail(ship: Node3D) -> void:
	var to_ship := ship.global_transform.affine_inverse()
	var hull_wall := 0
	for m in ship.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh_node := m as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			for v in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = to_ship * mesh_node.global_transform * v
				if p.y > Ship.DECK_Y + 0.01:
					hull_wall += 1
	check(hull_wall == 0, "%d hull vertices still stand above the weather deck" % hull_wall)

	var rail := ship.get_node_or_null("Rail")
	var body := ship.get_node_or_null("Rail/Body") as StaticBody3D
	check(rail != null and body != null, "the rail is missing")
	if rail == null or body == null:
		return
	var posts := rail.get_node_or_null("Posts") as MultiMeshInstance3D
	for part in ["Posts", "Balusters"]:
		var node := rail.get_node_or_null(part) as MultiMeshInstance3D
		var material := null if node == null else node.material_override as BaseMaterial3D
		check(node != null and node.multimesh.instance_count > 0 and material != null and material.albedo_texture != null,
				"the rail's %s are missing or built from the placeholder" % part.to_lower())
	# The handrail and base are one swept mesh each, textured, reaching every post.
	for part in ["Handrails", "Bases"]:
		var node := rail.get_node_or_null(part) as MeshInstance3D
		var material := null if node == null else node.material_override as BaseMaterial3D
		check(node != null and node.mesh != null and node.mesh.get_surface_count() == 1 and material != null
				and material.albedo_texture != null, "the rail's %s are missing or not swept from the profile" % part.to_lower())
		if node == null or node.mesh == null:
			continue
		check(node.mesh.get_faces().size() > 0, "the rail's %s have no faces" % part.to_lower())
		var sweep := node.mesh.get_aabb()
		var span := AABB()
		var first := true
		for line in rail.get_meta("post_lines", []):
			for at in line:
				var here := (at as Transform3D).origin
				span = AABB(here, Vector3.ZERO) if first else span.expand(here)
				first = false
		check(sweep.position.x <= span.position.x + 0.05 and sweep.end.x >= span.end.x - 0.05
				and sweep.position.z <= span.position.z + 0.05 and sweep.end.z >= span.end.z - 0.05,
				"the rail's %s do not reach every post" % part.to_lower())
	if posts == null:
		return

	# Every post on a wall top: over the hull or the castle at its own height, and the edge
	# within 0.3 m outboard of it (the top is 0.2 m wide along the sides, 0.5 m at the stern's
	# tip). A post's local +Z faces out. The rays start inside the rail's own collision, which
	# they ignore.
	var space := ship.get_world_3d().direct_space_state
	# The quarterdeck's stairs arrive between two posts: the rays past the edge ignore them.
	var stairs: Array[RID] = []
	for stair_body in ship.get_node("Quarterdeck/Stairs").find_children("*", "StaticBody3D", true, false):
		stairs.append((stair_body as StaticBody3D).get_rid())
	var lines: Array = rail.get_meta("post_lines", [])
	# Legs meeting at a corner both list its post; it stands once.
	var unique: Array[Vector3] = []
	for line in lines:
		for at in line:
			var here := (at as Transform3D).origin
			if unique.all(func(p: Vector3) -> bool: return p.distance_to(here) >= 0.001):
				unique.append(here)
	check(lines.size() >= 3 and unique.size() == posts.multimesh.instance_count,
			"%d rail posts placed for %d places; some stand twice or are missing" % [posts.multimesh.instance_count, unique.size()])
	var gaps: Array[float] = []
	var stair_posts: Array[Vector3] = []
	for line in lines:
		for i in (line as Array).size():
			var at: Transform3D = line[i]
			var out := at.basis.z
			var stair := Ship.QUARTERDECK_STAIRS_AT
			if at.origin.z < Ship.CASTLE_FRONT_Z + 0.2 and at.origin.z > stair.z and absf(at.origin.x - stair.x) < 0.8:
				# Up the stairs, to the pair at their head: either side of them, 0.1 m outside the
				# treads, rising with them.
				var spot := at.origin
				if stair_posts.all(func(p: Vector3) -> bool: return p.distance_to(spot) >= 0.001):
					stair_posts.append(spot)
				var rise := (at.origin.z - stair.z - 0.16) / (Ship.CASTLE_FRONT_Z + 0.1 - stair.z - 0.16)
				check(absf(absf(at.origin.x - stair.x) - Ship.STAIR_RAIL_OUT) <= 0.01
						and absf(at.origin.y - lerpf(Ship.DECK_Y, Ship.QUARTERDECK_Y, rise)) <= 0.01,
						"stair rail post at (%.2f, %.2f, %.2f) is off the stairs' rail line" % [at.origin.x, at.origin.y, at.origin.z])
			# 5 cm along the rail: posts stand on the hull's panel joins, and a ray exactly on
			# the seam between two triangles can slip through it.
			else:
				var foot := at.origin + at.basis.x * 0.05 + Vector3(0.0, 0.02, 0.0)
				var under := _ray_down(ship, foot, 0.3)
				var y := ship.to_local(under.position).y if not under.is_empty() else -INF
				check(absf(y - at.origin.y) <= 0.03, "rail post at (%.2f, %.2f) is not on the hull (met %.2f)" % [at.origin.x, at.origin.z, y])
				var past := foot + out * 0.3
				var down := PhysicsRayQueryParameters3D.create(ship.to_global(past), ship.to_global(past - Vector3(0.0, 0.3, 0.0)))
				down.exclude = stairs
				var beyond := space.intersect_ray(down)
				check(beyond.is_empty(), "rail post at (%.2f, %.2f) stands inboard of the edge" % [at.origin.x, at.origin.z])
			if i + 1 == (line as Array).size():
				continue
			var next: Vector3 = (line[i + 1] as Transform3D).origin
			# Level legs only: a stair rail's one bay runs the whole flight.
			if absf(next.y - at.origin.y) < 0.01:
				gaps.append(at.origin.distance_to(next))
			# No gap in the collision between this post and the next: a ray across the rail's
			# line meets the rail's own body all the way along.
			for k in range(1, 10):
				var q := at.origin.lerp(next, k / 10.0) + Vector3(0.0, 0.4, 0.0)
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(q - out * 0.4), ship.to_global(q + out * 0.4)))
				check(not hit.is_empty() and hit.collider == body, "the rail does not collide at (%.2f, %.2f)" % [q.x, q.z])
	check(stair_posts.size() == 4, "%d posts on the stair rails; there should be one at each foot and each head" % stair_posts.size())
	# Posts spaced alike everywhere, stern as bow: no stretch of the rail crowded with them.
	if not gaps.is_empty():
		check(gaps.min() >= 1.0 and gaps.max() <= Ship.RAIL_SPAN + 0.01,
				"the rail's posts are %.2f to %.2f m apart; they should be 1 to %.1f" % [gaps.min(), gaps.max(), Ship.RAIL_SPAN])

	# No baluster stands in a cathead's timber.
	var balusters := rail.get_node_or_null("Balusters") as MultiMeshInstance3D
	var shape := balusters.multimesh.mesh.get_aabb()
	for side in ["CatheadStarboard", "CatheadPort"]:
		var cathead := _bounds(ship, ship.get_node_or_null("DeckFittings/" + side))
		for at in balusters.get_meta("placed", []):
			var box := (at as Transform3D) * shape
			check(not box.intersects(cathead), "a baluster at (%.2f, %.2f) stands in %s" % [box.get_center().x, box.get_center().z, side])


## The castle's windows: as many as asked, each with its model, spaced evenly along the wall,
## and each with its back on the middle of its wall panel (before the editor's window_offset).
func _check_windows(ship: Node3D) -> void:
	var windows := ship.get_node_or_null("Quarterdeck/Windows")
	check(windows != null and windows.get_child_count() == Ship.CASTLE_WINDOW_COUNT
			and windows.get_children().all(func(w: Node) -> bool: return w.get_node_or_null("Model") != null),
			"the stern castle has not got its %d windows" % Ship.CASTLE_WINDOW_COUNT)
	if windows == null:
		return
	var space := ship.get_world_3d().direct_space_state
	var gaps: Array[float] = []
	var last := Vector3.INF
	for window in windows.get_children():
		var w := window as Node3D
		var box := _bounds(w, w.get_node_or_null("Model"))
		var out := w.basis.z.normalized()
		var across := w.basis.x.normalized()
		# Where its back would be with no offset: the offset is the editor's to tune.
		var back := w.position + out * box.position.z * Ship.WINDOW_SCALE + Vector3.UP * box.get_center().y * Ship.WINDOW_SCALE \
				- out * (ship as Ship).window_offset
		for side in [-1.0, 0.0, 1.0]:
			var at: Vector3 = back + across * side * box.size.x * 0.5 * Ship.WINDOW_SCALE * 0.95
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(at + out * 0.5), ship.to_global(at - out * 0.5)))
			var gap: float = (at - ship.to_local(hit.position)).dot(out) if not hit.is_empty() else INF
			if side == 0.0:
				check(absf(gap) <= 0.005, "%s's back is %.3f m off the middle of its wall panel" % [w.name, gap])
			else:
				# The wall bends away past its panel: a window whose edges stand well off it is
				# not on the panel it belongs to.
				check(gap <= 0.04, "%s's edge stands %.2f m off the wall" % [w.name, gap])
		if last != Vector3.INF:
			gaps.append(Vector2(w.position.x, w.position.z).distance_to(Vector2(last.x, last.z)))
		last = w.position
	# Changing the offset moves every window along its normal, as tuning it in the editor would.
	var typed := ship as Ship
	var before := typed.window_offset
	var first := (windows.get_child(0) as Node3D).position
	var normal := (windows.get_child(0) as Node3D).basis.z.normalized()
	typed.window_offset = before + 0.05
	var moved := ship.get_node("Quarterdeck/Windows").get_child(0) as Node3D
	check(absf((moved.position - first).dot(normal) - 0.05) <= 0.001 and ship.get_node("Quarterdeck/Windows").get_child_count() == Ship.CASTLE_WINDOW_COUNT,
			"setting window_offset does not move the windows along their normal")
	typed.window_offset = before
	if not gaps.is_empty():
		# Each is centred on its wall panel, so the spacing varies by up to a panel's length.
		var mean := 0.0
		for g in gaps:
			mean += g / gaps.size()
		check(gaps.max() - gaps.min() < 0.25 * mean, "the windows are %.2f to %.2f m apart; they should be even" % [gaps.min(), gaps.max()])
	# Its texture is shrunk to what a 1.1 m window needs (tools/shrink_glb_texture.py): Tripo's
	# 4096 px atlas was 64 MB of video memory, five times over.
	for node in windows.get_child(0).find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as BaseMaterial3D
			var texture := null if material == null else material.albedo_texture
			check(texture != null and maxi(texture.get_width(), texture.get_height()) <= 1024,
					"the window's texture is %s; it should be textured and no more than 1024 px" % (texture.get_size() if texture != null else "missing"))


## The trim round the castle's top: swept from the wale's profile and textured, its top just
## under the quarterdeck's edge, lying on the castle's walls all round and across the front,
## above the windows and the door, and clear of the stairs and their rails.
func _check_castle_trim(ship: Node3D) -> void:
	var trim := ship.get_node_or_null("Quarterdeck/Trim") as MeshInstance3D
	var material := null if trim == null else trim.material_override as BaseMaterial3D
	check(trim != null and trim.mesh != null and material != null and material.albedo_texture != null,
			"the castle's trim is missing or not swept from its profile")
	if trim == null:
		return
	var box := _bounds(ship, trim)
	check(box.end.y <= Ship.QUARTERDECK_Y + 0.001 and box.end.y > Ship.QUARTERDECK_Y - 0.03,
			"the trim's top is at %.3f, not just under the quarterdeck's edge (%.2f)" % [box.end.y, Ship.QUARTERDECK_Y])
	for path in ["Quarterdeck/Windows", "Quarterdeck/Door"]:
		var under := _bounds(ship, ship.get_node_or_null(path))
		check(under.end.y < box.position.y, "%s reaches %.2f, up into the trim (from %.2f)" % [path, under.end.y, box.position.y])
	var cabin := _bounds(ship, ship.get_node_or_null("Quarterdeck/Cabin"))
	check(box.end.z > cabin.end.z and box.position.x < cabin.position.x and box.end.x > cabin.end.x,
			"the trim does not run round the whole castle (%s)" % box)
	var landing := Ship.QUARTERDECK_STAIRS_AT.x
	var near := INF
	for v in trim.mesh.get_faces():
		if v.z < Ship.CASTLE_FRONT_Z + 0.5:
			near = minf(near, absf(v.x - landing))
	check(near > Ship.STAIR_RAIL_OUT + 0.12, "the trim comes to %.2f m from the stairs' centre line, into the stair rails' posts" % near)

	# On the wall: at every panel's middle round the castle, and across the front either side of
	# the stairs, the wall is within 1.5 cm of the trim's inner face.
	var space := ship.get_world_3d().direct_space_state
	var wall: Array[Vector3] = (ship as Ship)._castle_wall(ship.get_node("Quarterdeck/Cabin"))
	var spots: Array = []
	for i in wall.size() - 1:
		var mid := (wall[i] + wall[i + 1]) * 0.5
		var out := (wall[i + 1] - wall[i]).cross(Vector3.UP).normalized()
		if out.dot(mid - cabin.get_center()) < 0.0:
			out = -out
		spots.append([mid, out])
	for x in [-2.5, -2.1, 0.4, 1.5, 2.5]:
		spots.append([Vector3(x, 0.0, wall[0].z), Vector3.FORWARD])
	for spot in spots:
		var at := Vector3(spot[0].x, Ship.CASTLE_TRIM_Y, spot[0].z)
		var dir: Vector3 = spot[1]
		var wall_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(at + dir * 0.5), ship.to_global(at - dir * 0.5)))
		var gap: float = (ship.to_local(wall_hit.position) - at).dot(dir) if not wall_hit.is_empty() else INF
		check(absf(gap) <= 0.015, "the trim at (%.2f, %.2f) is %.3f m off the castle's wall" % [at.x, at.z, gap])


## The wale: swept from its profile and textured, closed round the hull, and lying on the hull's
## face all the way - at every panel's middle the hull is within 1.5 cm of the path it follows.
func _check_wale(ship: Node3D) -> void:
	var wale := ship.get_node_or_null("Wale") as MeshInstance3D
	var material := null if wale == null else wale.material_override as BaseMaterial3D
	check(wale != null and wale.mesh != null and material != null and material.albedo_texture != null,
			"the wale is missing or not swept from its profile")
	if wale == null:
		return
	var box := _bounds(ship, wale)
	check(box.position.z < -2.2 and box.end.z > 16.0 and box.position.x < -2.9 and box.end.x > 2.9,
			"the wale does not run round the whole hull (%s)" % box)
	var space := ship.get_world_3d().direct_space_state
	for outline in [Ship.WALE_STARBOARD, Ship.WALE_PORT]:
		for i in outline.size() - 1:
			var a: Vector2 = outline[i]
			var b: Vector2 = outline[i + 1]
			var mid := (a + b) * 0.5
			var out := Vector2(b.y - a.y, a.x - b.x).normalized()
			if out.dot(mid - Vector2(0.0, 7.0)) < 0.0:
				out = -out
			var at := Vector3(mid.x, Ship.WALE_Y, mid.y)
			var dir := Vector3(out.x, 0.0, out.y)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(at + dir * 0.5), ship.to_global(at - dir * 0.5)))
			var gap: float = (ship.to_local(hit.position) - at).dot(dir) if not hit.is_empty() else INF
			check(absf(gap) <= 0.015, "the wale at (%.2f, %.2f) is %.3f m off the hull" % [mid.x, mid.y, gap])


## The small rigging: a deadeye on every shroud's foot, hung on the rope just above the rail, a
## block under each yard arm, and the flag above everything on the topmast.
func _check_rigging(ship: Node3D) -> void:
	var shrouds := ship.get_node_or_null("Mast/Shrouds")
	var deadeyes: Array = [] if shrouds == null else shrouds.find_children("Deadeye*", "", false, false)
	check(deadeyes.size() == 6 and deadeyes.all(func(d: Node) -> bool: return d.get_node_or_null("Model") != null),
			"%d deadeyes with models; there should be one on each of the six shrouds" % deadeyes.size())
	for node in deadeyes:
		var d := node as Node3D
		var box := _bounds(ship, d)
		# Above the handrail's top (5.95), and no higher than a hand's reach up the shroud.
		check(box.position.y > Ship.DECK_Y + 0.74 and box.position.y < Ship.DECK_Y + 1.1,
				"%s hangs from %.2f to %.2f, not just above the rail" % [d.name, box.position.y, box.end.y])
	var blocks := ship.get_node_or_null("Mast/Blocks")
	check(blocks != null and blocks.get_child_count() == 4
			and blocks.get_children().all(func(b: Node) -> bool: return b.get_node_or_null("Model") != null),
			"there should be a block with its model under each of the four yard arms")
	var yard := _bounds(ship, ship.get_node_or_null("Mast/TopsailYard"))
	var flag := _bounds(ship, ship.get_node_or_null("Mast/Flag"))
	check(ship.get_node_or_null("Mast/Flag/Model") != null and flag.position.y > yard.end.y,
			"the flag is missing or hangs down to %.2f, into the topsail yard (top %.2f)" % [flag.position.y, yard.end.y])


## The flag hangs on its staff by its three rings: the staff's axis passes through each ring's
## hole, clear of the ring and of the cloth.
func _check_flag_rings(ship: Node3D) -> void:
	var flag := ship.get_node_or_null("Mast/Flag") as Node3D
	var model := null if flag == null else flag.get_node_or_null("Model") as Node3D
	if model == null:
		check(false, "no flag model to hang by its rings")
		return
	var to_flag := flag.global_transform.affine_inverse()
	var near := INF
	# Per 5 cm of height: which sides of the staff's axis the flag reaches round, within 8 cm.
	# A ring the staff passes through reaches round all four.
	var sides := {}
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := m as MeshInstance3D
		for v in mesh_node.mesh.get_faces():
			var p: Vector3 = to_flag * mesh_node.global_transform * v
			var round := Vector2(p.x, p.z)
			near = minf(near, round.length())
			if round.length() < 0.08:
				var band := int(floor(-p.y / 0.05))
				var quadrant := (1 if round.x >= 0.0 else 0) + (2 if round.y >= 0.0 else 0)
				if not sides.has(band):
					sides[band] = {}
				sides[band][quadrant] = true
	var wrapped: Array[int] = []
	for band in sides:
		if sides[band].size() == 4 and not wrapped.has(band - 1):
			wrapped.append(band)
	check(near > Ship.FLAGSTAFF_RADIUS, "the flag reaches %.3f m from the staff's axis, into the %.3f m staff" % [near, Ship.FLAGSTAFF_RADIUS])
	check(wrapped.size() >= 3, "the staff passes through the flag at %d heights; it should through all three rings" % wrapped.size())


## The flag streams downwind: with the breeze from abeam, its fly points the way it blows.
func _check_flag_flies_downwind(ship: Node3D) -> void:
	var wind := ship.get_tree().get_first_node_in_group("wind")
	var flag := ship.get_node_or_null("Mast/Flag") as Node3D
	if wind == null or flag == null:
		check(false, "no wind or no flag to test the flag against")
		return
	var abeam := ship.global_basis.x
	for i in 5:
		wind.set("_angle", atan2(abeam.x, abeam.z))
		await physics_frame
	var fly := _bounds(ship, flag.get_node("Model")).get_center() - ship.to_local(flag.global_position)
	var blows := ship.global_basis.inverse() * (wind.get("direction") as Vector3)
	check(Vector2(fly.x, fly.z).normalized().dot(Vector2(blows.x, blows.z).normalized()) > 0.9,
			"the flag flies toward %s with the wind blowing toward %s" % [fly, blows])


## The mizzen stands on the quarterdeck clear of everything there; its boom and gaff reach aft
## from it over the binnacle and the wheel, the boom well above the helmsman's head; its
## shrouds are set up with deadeyes just above the rail; and the spanker, blown abeam, stays
## laced along its luff and foot and never comes down onto the deck.
func _check_mizzen(ship: Node3D) -> void:
	var mizzen := ship.get_node_or_null("Mizzen") as Node3D
	var spanker := ship.get_node_or_null("Spanker")
	if mizzen == null or spanker == null:
		check(false, "the mizzen or its spanker is missing")
		return
	var mast := _bounds(ship, mizzen.get_node_or_null("Model"))
	check(absf(mast.size.y - Ship.MIZZEN_HEIGHT) <= TOLERANCE, "the mizzen is %.2f m, not %.1f" % [mast.size.y, Ship.MIZZEN_HEIGHT])
	check(mast.position.z > Ship.CASTLE_FRONT_Z + 0.4, "the mizzen stands at the quarterdeck's front edge, in the rail")
	for path in ["Helm", "DeckFittings/Binnacle", "DeckFittings/CoilQuarterdeck", "Quarterdeck/Stairs"]:
		check(not mast.intersects(_bounds(ship, ship.get_node_or_null(path))), "the mizzen stands in %s" % path)
	var helm := _bounds(ship, ship.get_node_or_null("Helm"))
	var boom := _bounds(ship, mizzen.get_node_or_null("Boom"))
	var gaff := _bounds(ship, mizzen.get_node_or_null("Gaff"))
	check(boom.position.y > Ship.HELM_FEET.y + 2.2 and boom.position.y > helm.end.y + 0.5,
			"the boom comes down to %.2f, into the helmsman's head room" % boom.position.y)
	check(boom.end.z > Ship.HELM_FEET.z and gaff.end.z > Ship.HELM_AT.z,
			"the boom and gaff do not reach aft over the wheel (to %.2f and %.2f)" % [boom.end.z, gaff.end.z])
	check(boom.position.z < mast.end.z + 0.1 and gaff.position.z < mast.end.z + 0.1,
			"the boom or gaff does not start at the mast")
	check(gaff.position.y > boom.end.y + 1.0, "the gaff is not above the boom")
	var deadeyes: Array = mizzen.find_children("Deadeye*", "", true, false)
	check(deadeyes.size() == 4 and deadeyes.all(func(d: Node) -> bool: return d.get_node_or_null("Model") != null),
			"%d deadeyes with models on the mizzen's shrouds; there should be four" % deadeyes.size())
	for node in deadeyes:
		var d := _bounds(ship, node as Node3D)
		check(d.position.y > Ship.QUARTERDECK_Y + 0.74 and d.position.y < Ship.QUARTERDECK_Y + 1.1,
				"%s hangs from %.2f, not just above the quarterdeck's rail" % [node.name, d.position.y])

	var wind := ship.get_tree().get_first_node_in_group("wind")
	if wind == null:
		check(false, "no wind to blow the spanker")
		return
	# From either beam in turn: the spanker is a fore-and-aft sail and fills on either tack.
	for side in [1.0, -1.0]:
		var abeam: Vector3 = ship.global_basis.x * side
		for i in 120:
			wind.set("_angle", atan2(abeam.x, abeam.z))
			await physics_frame
		var blows := ship.global_basis.inverse() * (wind.get("direction") as Vector3)
		var points := spanker.get("_pos") as PackedVector3Array
		var lowest := INF
		var off_luff := 0.0
		var belly := 0.0
		for i in points.size():
			lowest = minf(lowest, points[i].y)
			if absf(points[i].x) > absf(belly):
				belly = points[i].x
			if i % Sail.COLS == 0:
				off_luff = maxf(off_luff, absf(points[i].x))
		check(lowest >= boom.position.y, "the spanker comes down to %.2f, under the boom (%.2f)" % [lowest, boom.position.y])
		check(off_luff < 0.01, "the spanker's luff has blown %.2f m off the mast" % off_luff)
		check(absf(belly) > 0.2 and signf(belly) == signf(blows.x),
				"with the wind blowing toward x %.1f the spanker bellies %.2f m across" % [blows.x, belly])


## The course's foot hangs free. With the breeze from dead astern it swings back over the
## quarterdeck; the cloth must drape on the cabin, never hang inside it.
func _check_course_clears_cabin(ship: Node3D) -> void:
	var wind := ship.get_tree().get_first_node_in_group("wind")
	var sail := ship.get_node_or_null("Sail")
	var cabin_node := ship.get_node_or_null("Quarterdeck/Cabin") as Node3D
	if wind == null or sail == null or cabin_node == null:
		check(false, "no wind, course or cabin to test the course against")
		return
	var aft := ship.global_basis.z
	for i in 240:
		wind.set("_angle", atan2(aft.x, aft.z))
		await physics_frame
	var cabin := _bounds(ship, cabin_node).grow(-0.01)
	var mizzen := _bounds(ship, ship.get_node_or_null("Mizzen/Model")).grow(-0.01)
	var in_mizzen := 0
	var inside := 0
	var reach := -INF
	for p in sail.get("_pos") as PackedVector3Array:
		reach = maxf(reach, p.z)
		if cabin.has_point(p):
			inside += 1
		if mizzen.has_point(p):
			in_mizzen += 1
	check(reach > cabin.position.z, "the test wind never swung the course back to the cabin (reached z %.2f)" % reach)
	check(inside == 0, "%d points of the course hang inside the stern cabin" % inside)
	check(in_mizzen == 0, "%d points of the course hang through the mizzen" % in_mizzen)


## A ray straight down in ship space from `from`, `length` long.
func _ray_down(ship: Node3D, from: Vector3, length: float) -> Dictionary:
	var space := ship.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(from),
			ship.to_global(from - Vector3(0.0, length, 0.0))))


## Axis-aligned bounds, in ship space, of every mesh under `node`.
func _bounds(ship: Node3D, node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	if node == null:
		return box
	var to_ship := ship.global_transform.affine_inverse()
	var meshes: Array = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for m in meshes:
		var mesh_node := m as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var here: AABB = to_ship * mesh_node.global_transform * mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


func _finish() -> void:
	print("ship fittings check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
