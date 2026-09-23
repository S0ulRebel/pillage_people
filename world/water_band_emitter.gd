@tool
class_name WaterBandEmitter
extends Marker3D
## Marks a character, boat, barrel, or prop for the overhead water-interaction camera.
## The water shader still reads the captured top-down silhouette; this node creates no
## camera-facing or analytic outline of its own.

@export var band_enabled := true


func _ready() -> void:
	# Runtime only. This reaches up and sets a layer bit on its PARENT's meshes, and a @tool
	# script that edits other nodes in the editor has those edits saved into the scene file -
	# so the mask would be baked in by whoever next hit Ctrl+S, silently.
	if Engine.is_editor_hint():
		return
	_apply_capture_layer.call_deferred()


func _apply_capture_layer() -> void:
	if not band_enabled or get_parent() == null:
		return
	var root := get_parent()
	if root is MeshInstance3D:
		root.set_layer_mask_value(20, true)
	for child in root.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).set_layer_mask_value(20, true)
