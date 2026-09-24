@tool
class_name GrassPatch
extends Node3D
## One clump of grass you place by hand. Put it under the Terrain node and move it.
##
## The island's own grass is scattered by main.gd; this is for the spots you want grass that
## the scatter did not choose - against a rock you placed, at a tunnel mouth, round the arch.
## It grows with the same GrassField code as the scatter, so a hand-placed clump and a
## scattered one cannot be told apart: tufts crowded toward the middle, ragged at the edge.
##
## The terrain plants it, after the stamps and the tunnel entrances have shaped the ground, so
## the tufts stand on the finished surface rather than on the island as it was loaded. Moving
## it in the editor replants it where it now is.

## How far the clump spreads, in metres.
@export_range(0.3, 12.0, 0.1, "suffix:m") var radius := 2.2:
	set(value):
		radius = value
		_replant()
## How many tufts in the clump.
@export_range(1, 200) var tufts := 14:
	set(value):
		tufts = value
		_replant()
## Finished tuft heights, in metres.
@export var size_min := 0.30:
	set(value):
		size_min = value
		_replant()
@export var size_max := 0.70:
	set(value):
		size_max = value
		_replant()
## Which clump - change it for a different arrangement of the same size.
@export var variation := 0:
	set(value):
		variation = value
		_replant()

var _terrain: Node3D
var _field: GrassField


func _init() -> void:
	set_notify_transform(true)


func _ready() -> void:
	if not Engine.is_editor_hint() and not _under_terrain():
		push_error("GrassPatch %s is not a child of the Terrain node, so it is never planted"
				% get_path())


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_replant()
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if _under_terrain():
		return PackedStringArray()
	return PackedStringArray(["Not under the Terrain node, so it is never planted. Drag it onto Terrain."])


func _under_terrain() -> bool:
	return get_parent() != null and get_parent().is_in_group(&"terrain")


## Called by the terrain once its ground is final. The terrain is what it asks for heights.
func plant(terrain: Node3D) -> void:
	_terrain = terrain
	_replant()


func _replant() -> void:
	if _terrain == null or not is_inside_tree():
		return
	if _field != null:
		# Out of the tree at once, not just queued: the new field takes the old one's name, and
		# while the old one lingered the new one was renamed round it.
		remove_child(_field)
		_field.queue_free()
	# Its own child, made here and never saved: the tufts are rebuilt from these settings every
	# time, so the scene only ever stores the settings.
	_field = GrassField.new()
	_field.name = "Tufts"
	# One clump exactly this size: the field's ranges pinned to single values.
	_field.patch_radius = Vector2(radius, radius)
	_field.per_patch = Vector2i(tufts, tufts)
	_field.size_min = size_min
	_field.size_max = size_max
	add_child(_field)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(variation)
	_field.plant(_terrain, [global_position] as Array[Vector3], rng)
