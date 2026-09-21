@tool
extends Marker3D
class_name WaterBandEmitter
## Reusable waterline footprint for moving characters, boats, barrels, and other props.
## Place this marker at the object's bottom; height reaches to the top of the object.

@export_range(0.05, 20.0) var radius := 0.55
@export_range(0.05, 40.0) var height := 1.9
@export var band_enabled := true


func _enter_tree() -> void:
	add_to_group(&"water_band_emitters")


func _exit_tree() -> void:
	remove_from_group(&"water_band_emitters")
