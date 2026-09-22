@tool
extends StaticBody3D
## A palm, placeable by hand or scattered by main.gd.
##
## A StaticBody rather than the MultiMesh the grass uses, because a palm is something you walk
## into and there are a dozen of them rather than seven hundred. The collision is the trunk
## only - the fronds are four metres across and a player who cannot walk under them is a player
## fighting the scenery.

const MODEL := "res://art/models/foliage/palm.glb"

## Multiplies the authored size. The model is installed at 4.5 m, and a stand of palms all the
## same height reads as wallpaper.
@export_range(0.4, 2.5, 0.01) var size := 1.0:
	set(value):
		size = maxf(value, 0.1)
		_queue()
## Leans the trunk, in degrees. Palms do not grow straight and a scatter of upright ones looks
## planted rather than grown.
@export var lean := 0.0:
	set(value):
		lean = value
		_queue()
@export var lean_towards := 0.0:
	set(value):
		lean_towards = value
		_queue()
@export var collision_enabled := true:
	set(value):
		collision_enabled = value
		_queue()

## Authored height, in metres, and how thick the trunk is at the base. The model's own profile
## is 0.19 of its height across at the trunk and 0.86 at the fronds, so the collider is built
## from the first of those and deliberately ignores the second.
const HEIGHT := 4.5
const TRUNK_RADIUS := 0.34
## How far up the trunk the collision reaches. Above this it is fronds, which should not stop
## anybody.
const TRUNK_HEIGHT := 2.6

var _queued := false


func _ready() -> void:
	rebuild()


func _queue() -> void:
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
	if not ResourceLoader.exists(MODEL):
		push_warning("palm.gd: no model at %s" % MODEL)
		return

	var tilt := Basis(Vector3.UP, deg_to_rad(lean_towards)) \
			* Basis(Vector3.FORWARD, deg_to_rad(lean))
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		model.owner = get_tree().edited_scene_root
	model.transform = Transform3D(tilt.scaled(Vector3.ONE * size), Vector3.ZERO)
	for node in _descendants(model):
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			# Layer 20 is the ocean's overhead mask - a palm at the waterline should break the
			# foam band the way the rocks do.
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
					# Fronds are flat and one-sided as exported, so half of the crown vanishes
					# depending on the camera without this.
					flat.cull_mode = BaseMaterial3D.CULL_DISABLED
					mesh_node.set_surface_override_material(surface, flat)

	if not collision_enabled:
		return
	var shape := CollisionShape3D.new()
	shape.name = "Trunk"
	var cylinder := CylinderShape3D.new()
	cylinder.height = TRUNK_HEIGHT * size
	cylinder.radius = TRUNK_RADIUS * size
	shape.shape = cylinder
	add_child(shape)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		shape.owner = get_tree().edited_scene_root
	# Lifted to sit on the ground and leaned with the trunk, so the collision follows the tree
	# rather than standing upright beside it.
	shape.transform = Transform3D(tilt, tilt * Vector3(0.0, TRUNK_HEIGHT * size * 0.5, 0.0))


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
