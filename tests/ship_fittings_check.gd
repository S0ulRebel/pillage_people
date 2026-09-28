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
