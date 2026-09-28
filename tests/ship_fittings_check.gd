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
			"DeckFittings/ForemastCollar", "DeckFittings/SternLantern"]:
		var slot := ship.get_node_or_null(path)
		check(slot != null and slot.get_node_or_null("Model") != null,
				"%s has no model - its .glb is missing and the placeholder was built instead" % path)

	# Deck fittings stand ON the weather deck: not hovering, not sunk into the slab.
	for path in ["Helm", "Capstan", "DeckFittings/Binnacle", "DeckFittings/MastCollar"]:
		var box := _bounds(ship, ship.get_node_or_null(path))
		check(absf(box.position.y - Ship.DECK_Y) <= TOLERANCE,
				"%s's foot is at %.3f, the deck is at %.2f" % [path, box.position.y, Ship.DECK_Y])

	# The helmsman stands aft of the wheel: the whole helm must be forward of his feet, and
	# the binnacle forward of the helm and clear of the capstan's bars.
	var helm := _bounds(ship, ship.get_node_or_null("Helm"))
	check(helm.end.z < Ship.HELM_FEET.z, "the helm reaches %.2f, past the helmsman's feet at %.2f"
			% [helm.end.z, Ship.HELM_FEET.z])
	var binnacle := _bounds(ship, ship.get_node_or_null("DeckFittings/Binnacle"))
	var capstan := _bounds(ship, ship.get_node_or_null("Capstan"))
	check(not binnacle.intersects(helm) and not binnacle.intersects(capstan),
			"the binnacle overlaps the helm or the capstan's bars")

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
	var lids := ship.get_node_or_null("DeckFittings/GunportLids")
	var ports := 0 if lids == null else lids.get_child_count()
	check(ports == Ship.GUN_PORT_Z.size() * 2, "%d gunport frames for %d ports" % [ports, Ship.GUN_PORT_Z.size() * 2])
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

	_check_deck_props(ship)
	_check_catheads(ship)
	_check_beams(ship)

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


## Everything standing on the weather deck: on it, on solid planks, and out of each other's way.
func _check_deck_props(ship: Node3D) -> void:
	var standing := {}
	for entry in Ship.DECK_PROPS:
		var path: String = "DeckFittings/" + entry[0]
		var node := ship.get_node_or_null(path) as Node3D
		check(node != null and node.get_node_or_null("Model") != null, "%s has no model" % path)
		if node == null:
			continue
		var box := _bounds(ship, node.get_node_or_null("Model"))
		check(absf(box.position.y - Ship.DECK_Y) <= TOLERANCE,
				"%s's foot is at %.3f, the deck is at %.2f" % [path, box.position.y, Ship.DECK_Y])
		standing[path] = box
	for path in ["Helm", "Capstan", "DeckFittings/Binnacle", "DeckFittings/MastCollar", "DeckFittings/ForemastCollar"]:
		standing[path] = _bounds(ship, ship.get_node_or_null(path))

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
	# deck at DECK_Y. Over the stair shaft it would fall to the stairs, and outboard of the
	# bulwark it would meet nothing - or the bulwark - instead.
	var space := ship.get_world_3d().direct_space_state
	for entry in Ship.DECK_PROPS:
		var path: String = "DeckFittings/" + entry[0]
		if not standing.has(path):
			continue
		var box: AABB = standing[path]
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var x := lerpf(box.position.x + 0.05, box.end.x - 0.05, corner.x)
			var z := lerpf(box.position.z + 0.05, box.end.z - 0.05, corner.y)
			var from := ship.to_global(Vector3(x, Ship.DECK_Y + 0.03, z))
			var to := ship.to_global(Vector3(x, Ship.DECK_Y - 0.3, z))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
			var y := ship.to_local(hit.position).y if not hit.is_empty() else -INF
			check(absf(y - Ship.DECK_Y) <= 0.05,
					"%s's corner at (%.2f, %.2f) is not over the deck (ray met %.2f)" % [path, x, z, y])


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
