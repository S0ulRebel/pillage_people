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
	for path in ["Helm", "Capstan", "Bowsprit", "Rudder", "Rudder/Hinges",
			"Mast/Lower", "Mast/Topmast", "Mast/Top", "Mast/Yard", "Mast/TopsailYard",
			"Mast/TopsailFoot", "Foremast/Lower", "Foremast/Topmast", "Foremast/Top", "Foremast/Yard",
			"Foremast/TopsailYard", "Foremast/TopsailFoot", "DeckFittings/Binnacle", "DeckFittings/MastCollar",
			"DeckFittings/ForemastCollar", "DeckFittings/SternLantern", "Quarterdeck/Cabin",
			"Quarterdeck/Stairs"]:
		var slot := ship.get_node_or_null(path)
		check(slot != null and slot.get_node_or_null("Model") != null,
				"%s has no model - its .glb is missing and the placeholder was built instead" % path)

	# Fittings stand ON their deck: not hovering, not sunk into the slab. The wheel and the
	# binnacle are up on the quarterdeck, the capstan down on the gun deck.
	var decks := {"Helm": Ship.QUARTERDECK_Y, "Capstan": Ship.GUN_DECK_Y,
			"DeckFittings/Binnacle": Ship.QUARTERDECK_Y, "DeckFittings/MastCollar": Ship.DECK_Y,
			"Quarterdeck/Cabin": Ship.DECK_Y, "Quarterdeck/Stairs": Ship.DECK_Y}
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

	# The masts: the lower mast's head is where the topmast's heel sits, MAIN_LOWER up, and the
	# topmast ends 3 m above that - the lengths ship.gd's sails and ropes are rigged to.
	var lower := _bounds(ship, ship.get_node_or_null("Mast/Lower"))
	var topmast := _bounds(ship, ship.get_node_or_null("Mast/Topmast"))
	check(absf(lower.position.y - Ship.DECK_Y) <= TOLERANCE, "the mainmast does not stand on the deck")
	check(absf(lower.end.y - (Ship.DECK_Y + Ship.MAIN_LOWER)) <= TOLERANCE,
			"the mainmast's head is at %.3f, not %.1f m above the deck" % [lower.end.y, Ship.MAIN_LOWER])
	check(absf(topmast.position.y - lower.end.y) <= TOLERANCE, "the topmast does not sit on the mainmast's head")
	check(absf(topmast.end.y - (Ship.DECK_Y + Ship.MAIN_LOWER + 3.0)) <= TOLERANCE,
			"the topmast ends at %.3f, not %.1f m above the deck" % [topmast.end.y, Ship.MAIN_LOWER + 3.0])
	# The foremast is the main again, smaller: its lower mast and topmast FORE_SCALE of the main's.
	var fore_lower := _bounds(ship, ship.get_node_or_null("Foremast/Lower"))
	var fore_top := _bounds(ship, ship.get_node_or_null("Foremast/Topmast"))
	var fore_height := (Ship.MAIN_LOWER + 3.0) * Ship.FORE_SCALE
	check(absf(fore_lower.position.y - Ship.DECK_Y) <= TOLERANCE and absf(fore_top.end.y - (Ship.DECK_Y + fore_height)) <= TOLERANCE
			and absf(fore_top.position.y - fore_lower.end.y) <= TOLERANCE,
			"the foremast stands %.2f to %.2f, not %.2f m up from the deck, its topmast on its lower mast's head" % [fore_lower.position.y, fore_top.end.y, fore_height])
	var fore := fore_lower.merge(fore_top)
	check(fore.size.y >= 0.75 * (topmast.end.y - Ship.DECK_Y), "the foremast is %.2f m, a stub beside the main's %.2f" % [fore.size.y, topmast.end.y - Ship.DECK_Y])
	var yard := _bounds(ship, ship.get_node_or_null("Mast/Yard"))
	check(absf(yard.size.x - 8.0) <= TOLERANCE and yard.size.z < 0.5,
			"the course yard is %.2f m across and %.2f deep - it should run 8 m athwartships"
			% [yard.size.x, yard.size.z])

	# The mast top wraps the joint: its collar clears the course yard below, and its rim sits
	# between the mast head and the rail ring the lookout's posts carry.
	var top := _bounds(ship, ship.get_node_or_null("Mast/Top"))
	check(top.position.y >= yard.end.y - TOLERANCE,
			"the mast top's collar comes down to %.2f, into the course yard (top at %.2f)" % [top.position.y, yard.end.y])
	check(top.end.y > Ship.DECK_Y + Ship.MAIN_LOWER and top.end.y <= Ship.DECK_Y + 6.6 + Ship.MAIN_LIFT,
			"the mast top's rim is at %.2f, not between the mast head and the rail ring" % top.end.y)

	# The bowsprit reaches forward of its mount and rises, as the jib and bobstay expect.
	var sprit := _bounds(ship, ship.get_node_or_null("Bowsprit"))
	var reach := Ship.BOWSPRIT_LENGTH * cos(deg_to_rad(Ship.BOWSPRIT_RISE))
	check(absf(Ship.BOWSPRIT_AT.z - sprit.position.z - reach) <= 0.1,
			"the bowsprit reaches %.2f m forward of its mount; at %.1f m long it should reach %.2f" % [Ship.BOWSPRIT_AT.z - sprit.position.z, Ship.BOWSPRIT_LENGTH, reach])
	check(sprit.end.y > Ship.BOWSPRIT_AT.y + 0.4, "the bowsprit does not rise toward its tip")
	_check_bowsprit_clears_knightheads(ship)
	_check_jib(ship)
	_check_fore_yards(ship)

	# The rudder blade hangs aft of its hinge; the strip is forward of it.
	var blade := _bounds(ship, ship.get_node_or_null("Rudder/Model"))
	var strip := _bounds(ship, ship.get_node_or_null("Rudder/Hinges"))
	check(blade.position.z >= Ship.RUDDER_AT.z - TOLERANCE, "the rudder blade reaches forward of its hinge")
	check(strip.end.z <= Ship.RUDDER_AT.z + TOLERANCE, "the hinge strip is aft of the hinge")

	# A frame on every port, on the hull's side, and no lid: the reference's ports stand open,
	# and the model's lid swung up stood out over each port like a shelf.
	var frames := ship.get_node_or_null("GunPorts/Frames")
	var ports := 0 if frames == null else frames.get_child_count()
	var wanted: int = (ship as Ship).gun_port_count * 2
	check(ports == wanted, "%d gunport frames for %d ports" % [ports, wanted])
	if frames != null:
		for port in frames.get_children():
			check(port.find_child("lid", true, false) == null, "%s still has its lid" % port.name)
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
	_check_pillars(ship)
	_check_castle_rim(ship)
	_check_rail(ship)
	_check_wale(ship)
	_check_rigging(ship)
	_check_canvas(ship)
	_check_sheets(ship)
	_check_flag_rings(ship)
	await _check_course_clears_stairs(ship)
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


## The foremast is rigged as the main is, at FORE_SCALE: its course yard, topsail yard and topsail
## foot yard each at the main's height and length times FORE_SCALE, athwartships, with a block
## under each arm of the two big yards and its top on its lower mast's head. The fore course is
## laced to the fore yard with its foot above head height over the foredeck, and the fore topsail
## is laced between its topsail yard and topsail foot yard.
func _check_fore_yards(ship: Node3D) -> void:
	var s := Ship.FORE_SCALE
	for pair in [["Yard", "Mast/Yard"], ["TopsailYard", "Mast/TopsailYard"], ["TopsailFoot", "Mast/TopsailFoot"], ["Top", "Mast/Top"]]:
		var fore := _bounds(ship, ship.get_node_or_null("Foremast/" + pair[0]))
		var main := _bounds(ship, ship.get_node_or_null(pair[1]))
		check(absf(fore.size.x - main.size.x * s) <= 0.05 and absf((fore.get_center().y - Ship.DECK_Y) - (main.get_center().y - Ship.DECK_Y) * s) <= 0.05,
				"the foremast's %s is %.2f m across at %.2f; it should be the main's at %.2f scale (%.2f across at %.2f)"
				% [pair[0], fore.size.x, fore.get_center().y, s, main.size.x * s, Ship.DECK_Y + (main.get_center().y - Ship.DECK_Y) * s])
	var blocks := ship.get_node_or_null("Foremast/Blocks")
	check(blocks != null and blocks.get_child_count() == 4
			and blocks.get_children().all(func(b: Node) -> bool: return b.get_node_or_null("Model") != null),
			"there should be a block with its model under each of the foremast's four yard arms")
	var course := ship.get_node_or_null("ForeCourse")
	var topsail := ship.get_node_or_null("ForeTopsail")
	check(course != null and topsail != null, "the foremast's sails are missing")
	if course == null or topsail == null:
		return
	var yard := _bounds(ship, ship.get_node("Foremast/Yard")).get_center().y
	var lowest := INF
	for p in course.get("_pos") as PackedVector3Array:
		lowest = minf(lowest, p.y)
	check(lowest >= Ship.DECK_Y + 1.9, "the fore course hangs down to %.2f, %.2f m over the foredeck: into the heads of anyone there" % [lowest, lowest - Ship.DECK_Y])
	check(absf((course.get("_head_from") as Vector3).y - yard) <= 0.1, "the fore course is not laced to the fore yard")
	var top_yard := _bounds(ship, ship.get_node("Foremast/TopsailYard")).get_center().y
	var top_foot := _bounds(ship, ship.get_node("Foremast/TopsailFoot")).get_center().y
	check(absf((topsail.get("_head_from") as Vector3).y - top_yard) <= 0.1 and absf((topsail.get("_foot_from") as Vector3).y - top_foot) <= 0.1,
			"the fore topsail is not laced between the fore topsail yard and its foot yard")


## The bowsprit passes between the knightheads, the rail's first posts either side of it at the
## bow, without touching them.
func _check_bowsprit_clears_knightheads(ship: Node3D) -> void:
	var post_half := ((ship.get_node("Rail/Posts") as MultiMeshInstance3D).multimesh.mesh.get_aabb().size.x) * 0.5
	var knightheads: Array[Vector3] = []
	for line in ship.get_node("Rail").get_meta("post_lines"):
		for at in line:
			var o := (at as Transform3D).origin
			if o.z < Ship.BOWSPRIT_AT.z and absf(o.y - Ship.DECK_Y) < 0.01:
				knightheads.append(o)
	check(knightheads.size() == 2, "%d knightheads at the bow; there should be one either side of the bowsprit" % knightheads.size())
	var to_ship := ship.global_transform.affine_inverse()
	var widest := 0.0
	var model := ship.get_node("Bowsprit/Model") as Node3D
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := m as MeshInstance3D
		for v in mesh_node.mesh.get_faces():
			var p: Vector3 = to_ship * mesh_node.global_transform * v
			for k in knightheads:
				if absf(p.z - k.z) <= post_half:
					widest = maxf(widest, absf(p.x))
	for k in knightheads:
		check(widest < absf(k.x) - post_half, "the bowsprit is %.3f m out from the centreline between the knightheads, into their posts (%.3f)" % [widest, absf(k.x) - post_half])


## The jib: its head on the forward side of the foremast's head, its foot along the bowsprit,
## short of its tip; and the bobstay holds the bowsprit down from its tip.
func _check_jib(ship: Node3D) -> void:
	var jib := ship.get_node_or_null("Jib")
	var sprit := _bounds(ship, ship.get_node_or_null("Bowsprit"))
	if jib == null:
		check(false, "the jib is missing")
		return
	var head_from: Vector3 = jib.get("_head_from")
	var head_to: Vector3 = jib.get("_head_to")
	var foot_to: Vector3 = jib.get("_foot_to")
	# As in the reference, the jib's head is at the fore yard, not up at the masthead.
	var fore_yard := _bounds(ship, ship.get_node("Foremast/Yard")).get_center().y
	check(absf(head_to.y - fore_yard) <= 0.5 and head_from.y < head_to.y and head_to.z < Ship.FOREMAST_AT.z,
			"the jib's head runs %.2f to %.2f, not on the forward side of the foremast up to its fore yard (%.2f)" % [head_from.y, head_to.y, fore_yard])
	check(foot_to.z > sprit.position.z and foot_to.z < sprit.position.z + 0.6,
			"the jib's foot ends at z %.2f; the bowsprit's tip is at %.2f" % [foot_to.z, sprit.position.z])
	var stay := _bounds(ship, ship.get_node_or_null("Bobstay"))
	check(absf(stay.position.z - sprit.position.z) < 0.3, "the bobstay reaches z %.2f, not the bowsprit's tip at %.2f" % [stay.position.z, sprit.position.z])


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
	check(ship.get_node("GunPorts/Frames").get_child_count() == 6 and ship.get_node("GunPorts/Guns").get_child_count() == 6,
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
			var barrel_node := gun.call("barrel") as Node3D
			var barrel := _bounds(ship, barrel_node)
			check(absf(barrel.get_center().y - Ship.GUN_PORT_Y) <= 0.05,
					"the gun at z %.2f aims at %.2f, not through its port at %.2f" % [z, barrel.get_center().y, Ship.GUN_PORT_Y])
			# Run out, as in the reference: the muzzle through the port and clear of its frame's
			# face, the carriage on the inside of the wall.
			var muzzle := barrel.end.x if side > 0.0 else -barrel.position.x
			var face := Ship.BEAM * 0.5
			for port in ship.get_node("GunPorts/Frames").get_children():
				var frame := _bounds(ship, port.find_child("frame", true, false) as Node3D)
				if frame.size != Vector3.ZERO and absf(frame.get_center().z - z) < 0.3 and signf(frame.get_center().x) == side:
					face = frame.end.x if side > 0.0 else -frame.position.x
			check(muzzle >= face + 0.1,
					"the gun at z %.2f is not run out: its muzzle is at %.2f, the port frame's face at %.2f" % [z, muzzle, face])
			var carriage := AABB()
			var first := true
			for m in gun.find_children("*", "MeshInstance3D", true, false):
				if m != barrel_node:
					carriage = _bounds(ship, m) if first else carriage.merge(_bounds(ship, m))
					first = false
			var front := carriage.end.x if side > 0.0 else -carriage.position.x
			check(front <= Ship.GUN_WALL_INNER_X,
					"the gun carriage at z %.2f reaches %.2f, into the wall at %.2f" % [z, front, Ship.GUN_WALL_INNER_X])
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
	# The quarterdeck's stairs arrive between two posts, and the corner pillars stand under its
	# front corners: the rays past the edge ignore them.
	var stairs: Array[RID] = []
	for below in ["Quarterdeck/Stairs", "Quarterdeck/Pillars"]:
		for stair_body in ship.get_node(below).find_children("*", "StaticBody3D", true, false):
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
	var gaps: Array[float] = []
	var last := Vector3.INF
	for window in windows.get_children():
		var w := window as Node3D
		_check_on_wall(ship, w, Ship.WINDOW_SCALE, (ship as Ship).window_offset)
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
	_check_texture_size(windows.get_child(0), "window")


## Tripo's models came with 4096 px atlases, 64 MB of video memory each, for parts a metre or
## two across: each is shrunk to 1024 px (tools/shrink_glb_texture.py).
func _check_texture_size(node: Node, label: String) -> void:
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := found as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as BaseMaterial3D
			var texture := null if material == null else material.albedo_texture
			check(texture != null and maxi(texture.get_width(), texture.get_height()) <= 1024,
					"the %s's texture is %s; it should be textured and no more than 1024 px" % [label, texture.get_size() if texture != null else "missing"])


## Something flat-backed on the castle's wall, `node` scaled by `scale` and stood off by
## `offset`: with no offset, its back is on the wall panel's middle to 5 mm, and its edges stand
## no more than 4 cm off where the wall bends away past the panel. `edge` is how far out toward
## its sides, as a fraction of its half width, the edges are tried.
func _check_on_wall(ship: Node3D, node: Node3D, scale: float, offset: float, edge := 0.95) -> void:
	var space := ship.get_world_3d().direct_space_state
	var box := _bounds(node, node.get_node_or_null("Model"))
	var out := node.basis.z.normalized()
	var across := node.basis.x.normalized()
	var back := node.position + out * box.position.z * scale + Vector3.UP * box.get_center().y * scale - out * offset
	# Past its own collision, if it has any, to the wall behind.
	var own: Array[RID] = []
	for body in node.find_children("*", "StaticBody3D", true, false):
		own.append((body as StaticBody3D).get_rid())
	for side in [-1.0, 0.0, 1.0]:
		var at: Vector3 = back + across * side * box.size.x * 0.5 * scale * edge
		var ray := PhysicsRayQueryParameters3D.create(ship.to_global(at + out * 0.5), ship.to_global(at - out * 0.5))
		ray.exclude = own
		var hit := space.intersect_ray(ray)
		var gap: float = (at - ship.to_local(hit.position)).dot(out) if not hit.is_empty() else INF
		if side == 0.0:
			check(absf(gap) <= 0.005, "%s's back is %.3f m off the middle of its wall panel" % [node.name, gap])
		else:
			check(gap <= 0.04, "%s's edge stands %.2f m off the wall" % [node.name, gap])


## The castle's carved pillars: one at each corner of the front wall, its outer side just proud
## of the castle's side, and one between each pair of windows round the stern, the two nearest
## the stern window on the panels either side of its own. Each stands on the deck line with its
## back on the wall and its head just under the trim, clear of the windows, the door and the
## stairs' rails. The weather deck's rail stops a little short of each corner pillar, on a post
## of its own, leaving a gap too narrow to slip through, and the corner pillar is solid.
## pillar_offset moves them all.
func _check_pillars(ship: Node3D) -> void:
	var pillars := ship.get_node_or_null("Quarterdeck/Pillars")
	var wanted := 2 + Ship.CASTLE_WINDOW_COUNT - 1
	check(pillars != null and pillars.get_child_count() == wanted
			and pillars.get_children().all(func(p: Node) -> bool: return p.get_node_or_null("Model") != null),
			"the stern castle has not got its %d pillars" % wanted)
	if pillars == null or pillars.get_child_count() != wanted:
		return
	var trim := _bounds(ship, ship.get_node_or_null("Quarterdeck/Trim"))
	var door := _bounds(ship, ship.get_node_or_null("Quarterdeck/Door"))
	var windows := ship.get_node("Quarterdeck/Windows").get_children()
	var window_half := _bounds(windows[0], windows[0].get_node("Model")).size.x * 0.5 * Ship.WINDOW_SCALE
	var wall: Array[Vector3] = (ship as Ship)._castle_wall(ship.get_node("Quarterdeck/Cabin"))
	var corner := absf(wall[0].x)
	for node in pillars.get_children():
		var p := node as Node3D
		var front := absf(p.position.z - (wall[0].z - Ship.PILLAR_BACK * Ship.PILLAR_SCALE)) < 0.01 and p.basis.z.z < -0.99
		# A corner pillar hangs just past the corner, where there is no wall behind its edge.
		_check_on_wall(ship, p, Ship.PILLAR_SCALE, (ship as Ship).pillar_offset, 0.8 if front else 0.95)
		var box := _bounds(ship, p)
		var half := _bounds(p, p.get_node("Model")).size.x * 0.5 * Ship.PILLAR_SCALE
		check(absf(box.position.y - Ship.DECK_Y) <= TOLERANCE, "%s's foot is at %.3f, not on the deck line" % [p.name, box.position.y])
		check(box.end.y <= trim.position.y + 0.005 and box.end.y > trim.position.y - 0.05,
				"%s's head is at %.2f; the trim's underside is at %.2f" % [p.name, box.end.y, trim.position.y])
		var flat := Vector2(p.position.x, p.position.z)
		for window in windows:
			var gap := flat.distance_to(Vector2(window.position.x, window.position.z)) - half - window_half
			check(gap > 0.05, "%s is %.2f m from %s" % [p.name, gap, window.name])
		check(not box.intersects(door), "%s stands in the door" % p.name)
		check(absf(p.position.x - Ship.QUARTERDECK_STAIRS_AT.x) > Ship.STAIR_RAIL_OUT + 0.12 + half or not front,
				"%s stands in the stairs' rails" % p.name)
	for k in 2:
		var p := pillars.get_child(k) as Node3D
		var outer := absf(p.position.x) + _bounds(p, p.get_node("Model")).size.x * 0.5 * Ship.PILLAR_SCALE
		check(absf(outer - corner - Ship.PILLAR_CORNER_PROUD) <= 0.005,
				"%s's outer side is at %.3f; the front wall's corner is at %.3f" % [p.name, outer, corner])

	# The stern window's pillars stand on the panels either side of its own.
	var panel_of := func(at: Vector3) -> int:
		var best := 0
		var nearest := INF
		for i in wall.size() - 1:
			var mid := (wall[i] + wall[i + 1]) * 0.5
			var d := Vector2(at.x, at.z).distance_to(Vector2(mid.x, mid.z))
			if d < nearest:
				best = i
				nearest = d
		return best
	var stern_window: int = panel_of.call(windows[Ship.CASTLE_WINDOW_COUNT / 2].position)
	var flanking: Array[int] = []
	for node in pillars.get_children():
		var panel: int = panel_of.call((node as Node3D).position)
		if absf(panel - stern_window) == 1:
			flanking.append(panel)
	check(flanking.size() == 2, "the stern window (panel %d) is not framed by a pillar either side (%s)" % [stern_window, flanking])

	# The weather deck's rail stops short of the corner pillars: its last post stands
	# RAIL_PILLAR_GAP clear of the pillar's front, no part of the rail reaches into the pillar,
	# and the pillar itself stops a walker.
	var space := ship.get_world_3d().direct_space_state
	var parts: Array = []
	for part in ["Handrails", "Bases"]:
		parts.append_array((ship.get_node("Rail/" + part) as MeshInstance3D).mesh.get_faces())
	for k in 2:
		var p := pillars.get_child(k) as Node3D
		var box := _bounds(ship, p)
		var nearest := INF
		for line in ship.get_node("Rail").get_meta("post_lines"):
			for at in line:
				var o := (at as Transform3D).origin
				if absf(o.y - Ship.DECK_Y) < 0.01 and signf(o.x) == signf(p.position.x):
					nearest = minf(nearest, box.position.z - (o.z + 0.12))
		check(absf(nearest - Ship.RAIL_PILLAR_GAP) <= 0.03,
				"the weather deck's rail ends %.2f m short of %s; it should stop %.2f short" % [nearest, p.name, Ship.RAIL_PILLAR_GAP])
		var inside := 0
		for v in parts:
			inside += 1 if box.has_point(v) else 0
		check(inside == 0, "the weather deck's rail reaches into %s" % p.name)
		var q := Vector3(p.position.x, Ship.DECK_Y + 1.0, box.position.z - 0.5)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(q), ship.to_global(q + Vector3(0.0, 0.0, 0.6))))
		check(not hit.is_empty() and p.is_ancestor_of(hit.collider), "%s does not collide" % p.name)

	_check_texture_size(pillars.get_child(0), "pillar")
	var typed := ship as Ship
	var first := (pillars.get_child(0) as Node3D).position
	var normal := (pillars.get_child(0) as Node3D).basis.z.normalized()
	typed.pillar_offset = 0.05
	var moved := ship.get_node("Quarterdeck/Pillars").get_child(0) as Node3D
	check(absf((moved.position - first).dot(normal) - 0.05) <= 0.001 and ship.get_node("Quarterdeck/Pillars").get_child_count() == wanted,
			"setting pillar_offset does not move the pillars along their normal")
	typed.pillar_offset = 0.0


## The castle's bottom rim: swept from the trim's profile and textured, its foot on the deck
## line, lying on the castle's walls all round the stern, and not across the front wall's walkway:
## in front of the front wall it is only inside the corner pillars' bases.
func _check_castle_rim(ship: Node3D) -> void:
	var rim := ship.get_node_or_null("Quarterdeck/Rim") as MeshInstance3D
	var material := null if rim == null else rim.material_override as BaseMaterial3D
	check(rim != null and rim.mesh != null and material != null and material.albedo_texture != null,
			"the castle's bottom rim is missing or not swept from its profile")
	if rim == null:
		return
	var box := _bounds(ship, rim)
	check(absf(box.position.y - Ship.DECK_Y) <= 0.005, "the rim's foot is at %.3f, not on the deck line" % box.position.y)
	var cabin := _bounds(ship, ship.get_node_or_null("Quarterdeck/Cabin"))
	check(box.end.z > cabin.end.z and box.position.x < cabin.position.x and box.end.x > cabin.end.x,
			"the rim does not run round the whole castle (%s)" % box)
	var wall: Array[Vector3] = (ship as Ship)._castle_wall(ship.get_node("Quarterdeck/Cabin"))
	var pillars := ship.get_node("Quarterdeck/Pillars")
	var corners: Array[AABB] = [_bounds(ship, pillars.get_child(0)), _bounds(ship, pillars.get_child(1))]
	var loose := 0
	for v in rim.mesh.get_faces():
		if v.z < wall[0].z - 0.001 and absf(v.x) < absf(wall[0].x):
			loose += 0 if corners.any(func(c: AABB) -> bool: return c.grow(0.001).has_point(v)) else 1
	check(loose == 0, "%d of the rim's corners stand across the front wall, outside the corner pillars" % loose)
	var space := ship.get_world_3d().direct_space_state
	var y := Ship.DECK_Y + box.size.y * 0.5
	for i in wall.size() - 1:
		var mid := (wall[i] + wall[i + 1]) * 0.5
		var out := (wall[i + 1] - wall[i]).cross(Vector3.UP).normalized()
		if out.dot(mid - cabin.get_center()) < 0.0:
			out = -out
		var at := Vector3(mid.x, y, mid.z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(at + out * 0.5), ship.to_global(at - out * 0.5)))
		var gap: float = (ship.to_local(hit.position) - at).dot(out) if not hit.is_empty() else INF
		check(absf(gap) <= 0.015, "the rim at (%.2f, %.2f) is %.3f m off the castle's wall" % [at.x, at.z, gap])


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


## The small rigging: a block under each yard arm, and the flag above everything on the
## topmast. The shrouds and backstays are _check_shrouds'.
func _check_rigging(ship: Node3D) -> void:
	_check_shrouds(ship)
	var blocks := ship.get_node_or_null("Mast/Blocks")
	check(blocks != null and blocks.get_child_count() == 4
			and blocks.get_children().all(func(b: Node) -> bool: return b.get_node_or_null("Model") != null),
			"there should be a block with its model under each of the four yard arms")
	var yard := _bounds(ship, ship.get_node_or_null("Mast/TopsailYard"))
	var flag := _bounds(ship, ship.get_node_or_null("Mast/Flag"))
	check(ship.get_node_or_null("Mast/Flag/Model") != null and flag.position.y > yard.end.y,
			"the flag is missing or hangs down to %.2f, into the topsail yard (top %.2f)" % [flag.position.y, yard.end.y])


## Every shroud and backstay is made fast at both ends. At the top it leaves the mast from its
## surface (the main's from inside its top's collar). At the foot it is set up with an upper and a
## lower deadeye to a channel standing out from the hull, the channel's inner edge on the hull,
## and a chain plate from the lower deadeye down to the hull's side. Between, the rope passes
## clear of the rail and the hull, and the fore shrouds clear of the catheads and anchors and
## forward of the fore sails.
func _check_shrouds(ship: Node3D) -> void:
	var space := ship.get_world_3d().direct_space_state
	var sets := [["Mast/Shrouds", 6, "Mast/Top"], ["Foremast/Shrouds", 6, "Foremast/Top"],
			["Mast/Backstays", 2, "Mast/Topmast"]]
	var catheads: Array[Vector3] = []
	for name in ["CatheadStarboard", "CatheadPort"]:
		var cathead := ship.get_node("DeckFittings/" + name) as Node3D
		for m in cathead.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := m as MeshInstance3D
			for v in mesh_node.mesh.get_faces():
				catheads.append(ship.global_transform.affine_inverse() * mesh_node.global_transform * v)
	for spec in sets:
		var node := ship.get_node_or_null(spec[0])
		var ropes: Array = [] if node == null else node.get_meta("set_up", [])
		check(ropes.size() == spec[1], "%s: %d ropes set up; there should be %d" % [spec[0], ropes.size(), spec[1]])
		if node == null:
			continue
		for kind in ["Deadeye*", "LowerDeadeye*"]:
			var found: Array = node.find_children(kind, "", false, false)
			check(found.size() == spec[1] and found.all(func(d: Node) -> bool: return d.get_node_or_null("Model") != null),
					"%s: %d %s with models; there should be one on each rope" % [spec[0], found.size(), kind.trim_suffix("*")])
		# The mast part the ropes leave from, and how far out from its axis it reaches.
		var part := ship.get_node(spec[2]) as Node3D
		var axis := ship.to_local(part.global_position)
		var part_verts: Array[Vector3] = []
		for m in part.find_children("*", "MeshInstance3D", true, false) + ([part] if part is MeshInstance3D else []):
			var mesh_node := m as MeshInstance3D
			for v in mesh_node.mesh.get_faces():
				part_verts.append(ship.global_transform.affine_inverse() * mesh_node.global_transform * v)
		var index := {}
		for rope in ropes:
			var top: Vector3 = rope["top"]
			var strop: Vector3 = rope["strop"]
			var foot: Vector3 = rope["foot"]
			var plate_end: Vector3 = rope["plate_end"]
			var out: Vector3 = rope["out"]
			var side := "Starboard" if out.x > 0.0 else "Port"
			var k: int = index.get(side, 0)
			index[side] = k + 1
			var label := "%s rope at (%.2f, %.2f)" % [spec[0], foot.x, foot.z]
			# Its top on the mast: no further from the axis than the mast reaches at that height.
			# A plain spar has vertices only at its ends and bands: look wider until some are found.
			var reach := 0.0
			for band in [0.15, 0.6, 1.2, 2.5]:
				for v in part_verts:
					if absf(v.y - top.y) < band:
						reach = maxf(reach, Vector2(v.x - axis.x, v.z - axis.z).length())
				if reach > 0.0:
					break
			var from_axis := Vector2(top.x - axis.x, top.z - axis.z).length()
			check(reach > 0.0 and from_axis <= reach + 0.03,
					"%s leaves %s %.2f m from its axis, where it reaches %.2f: in the air" % [label, spec[2], from_axis, reach])
			# Its channel's inner edge over the hull's side: the hull's outer face at the deck under it.
			var hull: Vector3 = rope["hull"]
			var deck_at := Vector3(hull.x, (Ship.QUARTERDECK_Y if rope["on_castle"] else Ship.DECK_Y) - 0.05, hull.z)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(deck_at + out * 0.6), ship.to_global(deck_at - out * 0.3)))
			var gap: float = (ship.to_local(hit.position) - deck_at).dot(out) if not hit.is_empty() else INF
			check(absf(gap) <= 0.03, "%s: its channel's inner edge stands %.3f m off the hull below it" % [label, gap])
			var lower := _bounds(ship, node.get_node_or_null("LowerDeadeye%s%d" % [side, k]))
			# A steeply leaning rope tips its deadeyes, and a corner dips a little into the plank.
			check(lower.position.y >= foot.y - 0.12 and lower.position.y <= foot.y + 0.05,
					"%s: its lower deadeye does not stand on the channel (%.2f, channel top %.2f)" % [label, lower.position.y, foot.y])
			var planked := false
			for channel in node.find_children("Channel*", "MeshInstance3D", false, false):
				planked = planked or _bounds(ship, channel as Node3D).grow(0.02).has_point(foot - Vector3(0.0, Ship.CHANNEL_THICK * 0.5, 0.0))
			check(planked, "%s: its foot is not on a channel's plank" % label)
			# Its chain plate down to the hull's side.
			var plate := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(plate_end + out * 0.3), ship.to_global(plate_end - out * 0.3)))
			var plate_gap: float = (plate_end - ship.to_local(plate.position)).dot(out) if not plate.is_empty() else INF
			if rope["on_castle"]:
				# On the castle it is bolted to the trim, which stands 0.2 m off the wall.
				var trim := _bounds(ship, ship.get_node("Quarterdeck/Trim"))
				check(plate_gap >= 0.0 and plate_gap <= 0.2 and absf(plate_end.y - trim.end.y) <= 0.02,
						"%s: its chain plate does not end on the castle's trim (%.3f off the wall at %.2f)" % [label, plate_gap, plate_end.y])
			else:
				check(absf(plate_gap) <= 0.06, "%s: its chain plate ends %.3f m off the hull" % [label, plate_gap])
			check(plate_end.y < foot.y - 0.5, "%s: its chain plate does not reach down the hull" % label)
			# The deadeyes wholly above the rail's top, and the lower one outboard of it.
			var rail_top: float = (Ship.QUARTERDECK_Y if rope["on_castle"] else Ship.DECK_Y) + Ship.RAIL_HEIGHT
			check(lower.position.y > rail_top and (foot - hull).dot(out) >= 0.13,
					"%s: its deadeyes are not clear above and outboard of the rail (%.2f, rail top %.2f)" % [label, lower.position.y, rail_top])
			# The rope itself clear of the rail, the hull and the castle, from its deadeye up.
			var run := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(strop), ship.to_global(strop.lerp(top, 0.85))))
			check(run.is_empty(), "%s runs into %s" % [label, "" if run.is_empty() else str((run.collider as Node).get_path())])
			if spec[0] == "Foremast/Shrouds":
				var nearest := INF
				for j in 21:
					var p := foot.lerp(top, j / 20.0)
					for v in catheads:
						nearest = minf(nearest, p.distance_to(v))
				for j in 11:
					var p := foot.lerp(plate_end, j / 10.0)
					for v in catheads:
						nearest = minf(nearest, p.distance_to(v))
				check(nearest > 0.1, "%s comes within %.2f m of a cathead or its anchor" % [label, nearest])
				check(top.z <= Ship.FOREMAST_AT.z + 0.01 and foot.z < top.z, "%s is not forward of the foremast, clear of its sails" % label)


## Every sail is painted with Tripo's canvas (tools/bake_sail_canvas.py) and has the texture
## coordinates to show it: seams, patches and hem, not plain cloth. And the ship has two masts,
## as the reference has: no mizzen on the quarterdeck.
func _check_canvas(ship: Node3D) -> void:
	for name in ["Sail", "Topsail", "ForeCourse", "ForeTopsail", "Jib"]:
		var cloth := ship.get_node_or_null(name + "/Cloth") as MeshInstance3D
		var material := null if cloth == null else cloth.material_override as BaseMaterial3D
		check(material != null and material.albedo_texture != null, "the %s has no canvas texture" % name)
		if cloth == null or cloth.mesh == null or cloth.mesh.get_surface_count() == 0:
			check(false, "the %s has no cloth" % name)
			continue
		var uvs = cloth.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		check(uvs != null and (uvs as PackedVector2Array).size() == Sail.COLS * Sail.ROWS,
				"the %s's cloth has no texture coordinates for its canvas" % name)
	check(ship.get_node_or_null("Mizzen") == null and ship.get_node_or_null("Spanker") == null,
			"there is a mizzen on the quarterdeck; the reference has two masts")


## The sails' feet are made fast as in the reference. From a block at each course clew a sheet runs
## aft and a tack forward to the rail (the fore tack to its cathead), and from a block at the
## jib's clew a sheet runs to each side's rail. Each rope starts under its block, at a sail's foot
## corner, and ends on what it is belayed to. It passes clear of the hull, the rail and the
## shrouds on its way. The jib's clew, free above the bow, is above the head of anyone there.
func _check_sheets(ship: Node3D) -> void:
	var sheets := ship.get_node_or_null("Sheets")
	var ropes: Array = [] if sheets == null else sheets.get_meta("sheets", [])
	check(ropes.size() == 10, "%d sheets and tacks; there should be a sheet and a tack from each course clew and two jib sheets" % ropes.size())
	if sheets == null:
		return
	var blocks := sheets.find_children("Block*", "", false, false)
	check(blocks.size() == 5 and blocks.all(func(b: Node) -> bool: return b.get_node_or_null("Model") != null),
			"%d clew blocks with models; there should be one at each course clew and the jib's" % blocks.size())
	var corners: Array[Vector3] = []
	for name in ["Sail", "ForeCourse", "Jib"]:
		var sail := ship.get_node(name)
		corners.append_array([sail.get("_foot_from") as Vector3, sail.get("_foot_to") as Vector3])
	var catheads: Array[Vector3] = []
	for name in ["CatheadStarboard", "CatheadPort"]:
		var cathead := ship.get_node("DeckFittings/" + name) as Node3D
		for m in cathead.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := m as MeshInstance3D
			for v in mesh_node.mesh.get_faces():
				catheads.append(ship.global_transform.affine_inverse() * mesh_node.global_transform * v)
	var shrouds: Array = []
	for path in ["Mast/Shrouds", "Foremast/Shrouds", "Mast/Backstays"]:
		shrouds.append_array(ship.get_node(path).get_meta("set_up", []))
	var space := ship.get_world_3d().direct_space_state
	var rail := ship.get_node("Rail/Body")
	for rope in ropes:
		var clew: Vector3 = rope["clew"]
		var from: Vector3 = rope["from"]
		var to: Vector3 = rope["to"]
		var label := "the rope from (%.2f, %.2f, %.2f)" % [clew.x, clew.y, clew.z]
		check(corners.any(func(c: Vector3) -> bool: return c.distance_to(clew) < 0.01), "%s does not start at a sail's foot corner" % label)
		check(absf(from.y - (clew.y - 0.33)) < 0.01 and Vector2(from.x - clew.x, from.z - clew.z).length() < 0.01,
				"%s does not start under its clew's block" % label)
		if rope["onto"] == "rail":
			var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(to + Vector3(0.0, 0.3, 0.0)), ship.to_global(to - Vector3(0.0, 0.3, 0.0))))
			var gap: float = (to - ship.to_local(down.position)).y if not down.is_empty() else INF
			check(not down.is_empty() and down.collider == rail and absf(gap) <= 0.08,
					"%s is not belayed to the rail (it ends %.2f m off it)" % [label, gap])
		else:
			var nearest := INF
			for v in catheads:
				nearest = minf(nearest, v.distance_to(to))
			check(nearest < 0.1, "%s is not made fast to the cathead (%.2f m off it)" % [label, nearest])
		# Clear of the hull, the castle and the rail until it reaches what it is belayed to.
		var end := to + (from - to).normalized() * 0.15
		var run := space.intersect_ray(PhysicsRayQueryParameters3D.create(ship.to_global(from), ship.to_global(end)))
		check(run.is_empty(), "%s runs into %s" % [label, "" if run.is_empty() else str((run.collider as Node).get_path())])
		for shroud in shrouds:
			var pair := Geometry3D.get_closest_points_between_segments(from, to, shroud["strop"], shroud["top"])
			check(pair[0].distance_to(pair[1]) > 0.08, "%s runs into a shroud at (%.2f, %.2f, %.2f)" % [label, pair[0].x, pair[0].y, pair[0].z])
	check(Ship.JIB_CLEW.y >= Ship.DECK_Y + 1.9, "the jib's clew hangs %.2f m over the bow, into the head of anyone there" % (Ship.JIB_CLEW.y - Ship.DECK_Y))


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


## The course is sheeted home at its foot. With the breeze from dead astern and from abeam it
## bellies, but never out over the castle, and wherever it hangs over the quarterdeck's stairs
## it is above the head of anyone climbing them.
func _check_course_clears_stairs(ship: Node3D) -> void:
	var wind := ship.get_tree().get_first_node_in_group("wind")
	var sail := ship.get_node_or_null("Sail")
	if wind == null or sail == null:
		check(false, "no wind or course to test the course against")
		return
	var stairs := Ship.QUARTERDECK_STAIRS_AT
	var run := Ship.CASTLE_FRONT_Z + 0.1 - stairs.z
	for blow in [ship.global_basis.z, ship.global_basis.x]:
		for i in 180:
			wind.set("_angle", atan2(blow.x, blow.z))
			await physics_frame
		var aft := -INF
		var head_room := INF
		for p in sail.get("_pos") as PackedVector3Array:
			aft = maxf(aft, p.z)
			if absf(p.x - stairs.x) < Ship.STAIR_RAIL_OUT and p.z > stairs.z and p.z < stairs.z + run:
				var tread := Ship.DECK_Y + (p.z - stairs.z) / run * (Ship.QUARTERDECK_Y - Ship.DECK_Y)
				head_room = minf(head_room, p.y - tread)
		check(aft < Ship.CASTLE_FRONT_Z, "the course bellies back to z %.2f, over the castle (front at %.2f)" % [aft, Ship.CASTLE_FRONT_Z])
		check(head_room >= 1.9, "the course hangs %.2f m over the quarterdeck's stairs: into the head of anyone on them" % head_room)


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
