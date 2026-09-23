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


func _ready() -> void:
	_build()


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
					global_position = origin
					global_basis = Basis(Vector3.UP.cross(aft).normalized(), Vector3.UP, aft)
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
	if get_node_or_null("Model") != null:
		return
	if not ResourceLoader.exists(MODEL):
		push_warning("ship: no model at %s" % MODEL)
		return
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
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
