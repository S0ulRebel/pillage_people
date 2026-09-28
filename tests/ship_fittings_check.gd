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
			"Quarterdeck/Stairs", "Quarterdeck/Stairs/Rail"]:
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
	_check_quarterdeck(ship)
	_check_rail(ship)
	await _check_course_clears_cabin(ship)

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


## The stern cabin and its roof, the quarterdeck: inside the bulwarks, level, reached by the
## stairs, and holding the wheel with room for the helmsman behind it.
func _check_quarterdeck(ship: Node3D) -> void:
	var cabin_node := ship.get_node_or_null("Quarterdeck/Cabin") as Node3D
	var stairs_node := ship.get_node_or_null("Quarterdeck/Stairs") as Node3D
	if cabin_node == null or stairs_node == null:
		check(false, "the quarterdeck is missing")
		return
	var space := ship.get_world_3d().direct_space_state
	var cabin := _bounds(ship, cabin_node)

	# Inside the bulwarks: level by level up to the rail, the hull's side is further out than
	# the cabin's. The stern narrows, so this is what decides how far aft the cabin can go.
	var own: Array[RID] = []
	for body in ship.get_node("Quarterdeck").find_children("*", "StaticBody3D", true, false):
		own.append((body as StaticBody3D).get_rid())
	var widest := {}
	var to_ship := ship.global_transform.affine_inverse()
	for m in cabin_node.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := m as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			for v in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = to_ship * mesh_node.global_transform * v
				if p.y < Ship.DECK_Y + 0.8:
					var slot := int(floor(p.z / 0.1))
					widest[slot] = maxf(widest.get(slot, 0.0), absf(p.x))
	for slot in widest:
		var z := (float(slot) + 0.5) * 0.1
		for side in [-1.0, 1.0]:
			var query := PhysicsRayQueryParameters3D.create(ship.to_global(Vector3(0.0, Ship.DECK_Y + 0.3, z)),
					ship.to_global(Vector3(side * 3.5, Ship.DECK_Y + 0.3, z)))
			query.exclude = own
			var hit := space.intersect_ray(query)
			var wall := absf(ship.to_local(hit.position).x) if not hit.is_empty() else INF
			check(wall > widest[slot], "the cabin reaches %.2f out at z %.1f, through the hull's side at %.2f"
					% [widest[slot], z, wall])

	# The roof is level and walkable: every sample inside its rails is at the quarterdeck's
	# height, apart from the fittings standing on it.
	var fittings: Array[AABB] = []
	for path in ["Helm", "DeckFittings/Binnacle", "DeckFittings/CoilQuarterdeck", "DeckFittings/BreastRail"]:
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
	# his body - 0.35 m round, 1.9 m tall - fits all the way, lifted by one step for the stairs.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.9
	var body := PhysicsShapeQueryParameters3D.new()
	body.shape = capsule
	var x := Ship.QUARTERDECK_STAIRS_AT.x
	var last := Ship.DECK_Y
	var z := Ship.QUARTERDECK_STAIRS_AT.z - 1.0
	while z <= Ship.HELM_FEET.z:
		var hit := _ray_down(ship, Vector3(x, Ship.QUARTERDECK_Y + 2.5, z), 5.5)
		var y := ship.to_local(hit.position).y if not hit.is_empty() else -INF
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


## The rail that replaced the bulwark: the wall is gone aft of the bow head, the rail is built
## from the models, every post stands on the hull's edge, and it collides without a gap.
func _check_rail(ship: Node3D) -> void:
	var to_ship := ship.global_transform.affine_inverse()
	var hull_wall := 0
	for m in ship.get_node("Model").find_children("*", "MeshInstance3D", true, false):
		var mesh_node := m as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			for v in mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p: Vector3 = to_ship * mesh_node.global_transform * v
				if p.y > Ship.DECK_Y + 0.01 and p.z > -0.8:
					hull_wall += 1
	check(hull_wall == 0, "%d hull vertices still stand above the deck aft of the bow head" % hull_wall)

	var rail := ship.get_node_or_null("Rail")
	var body := ship.get_node_or_null("Rail/Body") as StaticBody3D
	check(rail != null and body != null, "the rail is missing")
	if rail == null or body == null:
		return
	var posts := rail.get_node_or_null("Posts") as MultiMeshInstance3D
	for part in ["Posts", "Handrails", "Bases", "Balusters"]:
		var node := rail.get_node_or_null(part) as MultiMeshInstance3D
		var material := null if node == null else node.material_override as BaseMaterial3D
		check(node != null and node.multimesh.instance_count > 0 and material != null and material.albedo_texture != null,
				"the rail's %s are missing or built from the placeholder" % part.to_lower())
	if posts == null:
		return

	# Every post on the wall top: over the hull at the deck, and the hull's outer edge within
	# 0.3 m outboard of it (the top is 0.2 m wide along the sides, 0.5 m at the stern's tip). The rays start inside the rail's own collision, which they ignore.
	var space := ship.get_world_3d().direct_space_state
	var placed: Array = posts.get_meta("placed", [])
	var count := placed.size()
	check(count == posts.multimesh.instance_count, "the rail's posts are not all placed")
	var centre := Vector3(0.0, Ship.DECK_Y, 7.0)
	for i in count:
		var at: Transform3D = placed[i]
		var out := at.basis.z
		if out.dot(at.origin - centre) < 0.0:
			out = -out
		# 5 cm along the rail: the posts stand on the hull's panel joins, and a ray exactly on the
		# seam between two triangles can slip through it.
		var foot := at.origin + at.basis.x * 0.05 + Vector3(0.0, 0.02, 0.0)
		var under := _ray_down(ship, foot, 0.3)
		var y := ship.to_local(under.position).y if not under.is_empty() else -INF
		check(absf(y - Ship.DECK_Y) <= 0.03, "rail post %d at (%.2f, %.2f) is not on the hull (met %.2f)" % [i, at.origin.x, at.origin.z, y])
		var beyond := _ray_down(ship, foot + out * 0.3, 0.3)
		check(beyond.is_empty(), "rail post %d at (%.2f, %.2f) stands inboard of the hull's edge" % [i, at.origin.x, at.origin.z])

		# No gap in the collision between this post and the next: a ray across the rail's line
		# meets the rail's own body all the way along.
		if i + 1 < count:
			var next: Vector3 = (placed[i + 1] as Transform3D).origin
			for k in range(1, 10):
				var q := at.origin.lerp(next, k / 10.0) + Vector3(0.0, 0.4, 0.0)
				var query := PhysicsRayQueryParameters3D.create(ship.to_global(q - out * 0.4), ship.to_global(q + out * 0.4))
				var hit := space.intersect_ray(query)
				check(not hit.is_empty() and hit.collider == body,
						"the rail does not collide at (%.2f, %.2f)" % [q.x, q.z])

	# No baluster stands in a cathead's timber.
	var balusters := rail.get_node_or_null("Balusters") as MultiMeshInstance3D
	var shape := balusters.multimesh.mesh.get_aabb()
	for side in ["CatheadStarboard", "CatheadPort"]:
		var cathead := _bounds(ship, ship.get_node_or_null("DeckFittings/" + side))
		for at in balusters.get_meta("placed", []):
			var box := (at as Transform3D) * shape
			check(not box.intersects(cathead), "a baluster at (%.2f, %.2f) stands in %s" % [box.get_center().x, box.get_center().z, side])


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
	var inside := 0
	var reach := -INF
	for p in sail.get("_pos") as PackedVector3Array:
		reach = maxf(reach, p.z)
		if cabin.has_point(p):
			inside += 1
	check(reach > cabin.position.z, "the test wind never swung the course back to the cabin (reached z %.2f)" % reach)
	check(inside == 0, "%d points of the course hang inside the stern cabin" % inside)


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
