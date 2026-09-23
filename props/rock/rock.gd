@tool
extends Node3D
## One generated rock, placeable by hand in the editor.
##
## Drag rock.tscn into the scene, pick a variant, and it appears. It is a @tool script that
## rebuilds itself when its exports change, which is how the procedural rock it replaced was
## authored, so placing one feels the same as it always did.
##
## rocks.gd uses this too, so the scatter and a hand-placed rock are the same thing: one place
## decides what a rock is made of, and a rock dropped in by hand cannot drift out of step with
## the forty the island starts with.

enum Kind {BOULDER, CLUSTER, PILE, PILE_TALL, PLATFORM, STONE, STONES}

const PATHS := {
	Kind.BOULDER: "res://art/models/rocks/rock_boulder.glb",
	Kind.CLUSTER: "res://art/models/rocks/rock_cluster.glb",
	Kind.PILE: "res://art/models/rocks/rock_pile.glb",
	Kind.PILE_TALL: "res://art/models/rocks/rock_pile_tall.glb",
	Kind.PLATFORM: "res://art/models/rocks/stone_platform.glb",
	Kind.STONE: "res://art/models/rocks/stone_rock.glb",
	Kind.STONES: "res://art/models/rocks/stone_rocks.glb",
}

## What each model was authored at, in metres. Baked into the files by prepare_game_model.py,
## and repeated here so a placement can ask how tall a rock will be before it exists - the
## shoreline group picks its water depth from exactly that.
const HEIGHTS := {
	Kind.BOULDER: 2.2, Kind.CLUSTER: 2.4, Kind.PILE: 1.2, Kind.PILE_TALL: 2.0,
	Kind.PLATFORM: 0.9, Kind.STONE: 1.3, Kind.STONES: 1.1,
}

@export var kind: Kind = Kind.BOULDER:
	set(value):
		kind = value
		_refresh()
## Multiplies the authored size. The scatter varies this per rock; by hand it is whatever
## suits the spot.
@export_range(0.2, 4.0, 0.01) var size := 1.0:
	set(value):
		size = maxf(value, 0.05)
		_refresh()
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		_refresh()

var _queued := false


## How tall this rock stands once placed, in metres.
func height() -> float:
	return float(HEIGHTS.get(kind, 1.0)) * size


## The size that makes this kind stand a given height.
static func size_for(of_kind: Kind, metres: float) -> float:
	return metres / float(HEIGHTS.get(of_kind, 1.0))


func _ready() -> void:
	rebuild()


func _refresh() -> void:
	if is_inside_tree() and not _queued:
		_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	for child in get_children():
		child.queue_free()
		remove_child(child)
	var path: String = PATHS.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("rock.gd: no model at %s" % path)
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	# Owned by the edited scene, or the editor saves an empty node and the rock vanishes on
	# reload. Only matters in the editor; at runtime there is nothing to save.
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		model.owner = get_tree().edited_scene_root
	model.scale = Vector3.ONE * size
	dress(model, collision_enabled)


## Flat shading, the water camera's layer, and something to walk into.
##
## Static so rocks.gd can call it on its own instances without building one of these nodes for
## every rock it scatters.
static func dress(rock: Node3D, with_collision: bool) -> void:
	for node in _descendants(rock):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		# Layer 20 is sampled by the ocean's overhead silhouette camera. Keeping layer 1 as
		# well means the same mesh is both the visible rock and its water-band mask; a separate
		# proxy mesh would be one more thing to keep in step with the first.
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
		if with_collision:
			# From the mesh rather than a box: these are shapes the player walks around and
			# climbs onto. create_trimesh_collision parents the body to the mesh itself, so
			# whatever scale the rock was given carries through to the shape with it.
			mesh_node.create_trimesh_collision()


static func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
