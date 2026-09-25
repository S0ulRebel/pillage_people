@tool
extends Node3D
## One coral head on the seabed. Drag it into a scene to place one by hand, or let corals.gd
## scatter a reef of them.
##
## These are the Tripo corals in art/models/props - about a thousand triangles each, matching
## art/references/nature-kit/03-corals-v1.png, where every coral in the sheet grows out of a
## little grey pebble base. That base is part of the sculpt, not a separate object: it is why
## the model arrives as ONE mesh with ONE material and cannot be split into "the coral" and
## "the rocks" without repainting. Colour variants therefore come from repainting the texture
## and swapping it back in with tools/retexture_model.py, not from tinting at runtime.
##
## The files are named for their SHAPE - fingers, plate - and never for their colour, because a
## repaint is expected and coral_pink.glb would start lying the first time one happened.
##
## Their size is baked into the .glb (tools/reorient_model.py --scale) rather than set on
## import, which is only allowed because neither is rigged - see the note in .gitignore about
## root_scale living in a file a fresh clone never receives.

## Which coral. The enum is the thing scenes and tests refer to; the paths are an implementation
## detail that a repaint or a re-export may change.
enum Kind {FINGERS, PLATE, BRANCH}

const MODELS := {
	Kind.FINGERS: "res://art/models/props/coral_fingers.glb",
	Kind.PLATE: "res://art/models/props/coral_plate.glb",
	Kind.BRANCH: "res://art/models/props/coral_branch.glb",
}

@export var kind: Kind = Kind.FINGERS:
	set(value):
		kind = value
		if is_inside_tree():
			_build()


func _ready() -> void:
	_build()


## Loads the model and dresses it. Rebuilt rather than patched, so changing `kind` in the
## editor swaps the coral instead of leaving the old one behind it.
func _build() -> void:
	var existing := get_node_or_null("Model")
	if existing != null:
		existing.free()
	var path: String = MODELS[kind]
	if not ResourceLoader.exists(path):
		push_warning("coral.gd: no model at %s" % path)
		return
	var model := (load(path) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	# An editor-instanced child with no owner vanishes on the next reload.
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		model.owner = get_tree().edited_scene_root
	dress(model)


## Flat shading, the same pass every prop here applies. A coral that arrives with a specular
## highlight reads as a different game from the one it is sitting in - and these come out of
## Tripo with roughness 0.5 and a metallic slot, which is exactly that.
##
## Static, so corals.gd can dress a model it instantiated itself without going through a Coral
## node. A scattered coral and an authored one are then the same thing.
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
				mesh_node.set_surface_override_material(surface, flat)
		# NO LAYER 20, deliberately, and this is the one place a coral differs from a rock.
		#
		# Layer 20 is not "things in the water" - it is the ocean's overhead band-mask capture,
		# and that camera's far plane sits 0.1 m BELOW the water plane (ocean.gd: camera at
		# sea + 220 with far 220.1) precisely so that fully submerged objects are clipped out
		# of it. A coral on the crater floor is fifteen metres under; it contributes nothing
		# to the foam band whatever this bit says. grass.gd leaves it off for the same kind of
		# reason and says so.
		#
		# What keeps that true is corals.gd refusing any spot where the coral would breach the
		# surface, and coral_check measuring it.
		mesh_node.layers = 1


## The coral's own box in this node's space, measured off the meshes rather than read off the
## node. Tripo origins are arbitrary - see the note in cannon.gd - so nothing here trusts the
## imported transform.
func bounds() -> AABB:
	var box := AABB()
	var first := true
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var here := (global_transform.affine_inverse() * mesh_node.global_transform) \
				* mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


## How tall it stands, in metres. What corals.gd checks the water against.
func height() -> float:
	return bounds().size.y
