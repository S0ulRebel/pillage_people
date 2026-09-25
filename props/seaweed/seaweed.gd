@tool
extends Node3D
## One plant on the seabed. Drag it in, or let the reef scatter a bed of them.
##
## The same shape as coral.gd next door, and deliberately a separate thing: a coral is a
## mineral and a weed is a plant, they get different sizes and different spacing, and folding
## them into one enum would mean every caller that wants "a coral" has to say which half of the
## list it means.
##
## TWO-SIDED, which is where it differs. These are leaves, and three of the five are barely a
## handspan deep - the fan is 0.18 m - so a frond seen from behind is a frond seen through the
## back of its own faces. Godot culls those by default and the plant half disappears as you
## swim round it. palm.gd and grass.gd already turn culling off for exactly this, and say so.
##
## Named for SHAPE, never colour. Two of these are the same plant in green and gold, so the
## names do some work: leafy and arching are the tell, not the hue, and a repaint cannot make
## them wrong.

enum Kind {LEAFY, FAN, BLADES, FLESHY, ARCHING}

const MODELS := {
	Kind.LEAFY: "res://art/models/props/seaweed_leafy.glb",
	Kind.FAN: "res://art/models/props/seaweed_fan.glb",
	Kind.BLADES: "res://art/models/props/seaweed_blades.glb",
	Kind.FLESHY: "res://art/models/props/seaweed_fleshy.glb",
	Kind.ARCHING: "res://art/models/props/seaweed_arching.glb",
}

@export var kind: Kind = Kind.LEAFY:
	set(value):
		kind = value
		if is_inside_tree():
			_build()
## Drops onto the seabed under it, and stays there while you drag it about in the editor.
@export var sit_on_ground := true:
	set(value):
		sit_on_ground = value
		_settle()
## How far into the bed it sinks, so one on a slope does not stand on the edge of its base.
@export var sink := 0.05:
	set(value):
		sink = value
		_settle()

var _settling := false


func _ready() -> void:
	_build()
	_settle()
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and not _settling:
		_settle()


func _settle() -> void:
	if not is_inside_tree() or not sit_on_ground or _settling:
		return
	_settling = true
	Ground.sit(self, null, sink)
	_settling = false


func _build() -> void:
	var existing := get_node_or_null("Model")
	if existing != null:
		existing.free()
	var path: String = MODELS[kind]
	if not ResourceLoader.exists(path):
		push_warning("seaweed.gd: no model at %s" % path)
		return
	var model := (load(path) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		model.owner = get_tree().edited_scene_root
	dress(model)


## Flat shading and no back-face culling, the same pass every prop here applies plus the one
## line the leafy ones need.
##
## Static, so the reef can dress a model it instantiated itself without going through a Seaweed
## node - a scattered plant and an authored one are then the same thing.
static func dress(model: Node) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material is StandardMaterial3D:
				var flat := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				flat.metallic = 0.0
				flat.roughness = 1.0
				flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				# Leaves, seen from both sides. Without this a frond vanishes as you pass it.
				flat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mesh_node.set_surface_override_material(surface, flat)
		# Not layer 20. See the long note in coral.gd: that layer is the ocean's foam band
		# capture, its camera stops 0.1 m under the water, and a plant on the seabed is outside
		# its frustum. What keeps that true is the reef refusing to plant anything that would
		# break the surface.
		mesh_node.layers = 1


func bounds() -> AABB:
	return Ground.mesh_box(self)


## How tall it stands, in metres. What the reef checks the water against.
func height() -> float:
	return bounds().size.y
