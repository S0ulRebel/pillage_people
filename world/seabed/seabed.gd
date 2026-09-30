@tool
class_name Seabed
extends Node
## The ground under everything: a seabed with gentle noise in it, that goes on past the island
## and deepens into open sea. Put it under the Terrain; the Terrain lays these heights down
## first and every TerrainStamp after it, in child order - so an island is a stamp on the sea
## floor rather than the sea floor being the ragged edge of an island's height map.
##
## Worked out here, on the CPU, not in a shader. The collider, height_at() - which props,
## swimming and the ship all read - and the water's idea of how deep it is all need the real
## height, and a shader's answer cannot be read back by any of them. Fine detail that only has
## to be seen, not stood on, is the terrain shader's business, as before.
##
## Heights come back in the Terrain's own metres, measured from the sea level it passes in, so
## this node needs to know nothing about the Terrain and could stand under anything that asks.

## Any setting changed. The Terrain listens and rebuilds, in the editor, since every sample of
## the ground starts here.
signal changed

## Metres of water over the seabed round the islands, out to shelf_radius, before any noise.
##
## Deeper than the island's own shelf, by a little: reef.gd grows its beds wherever the water is
## 0.9 to 2.8 m deep, and a bed as shallow as the shelf would have them growing in the open a
## quarter of a kilometre out. At 4 m with a metre of noise it is never shallower than 3.
@export_range(0.0, 200.0, 0.5, "suffix:m") var depth := 4.0:
	set(value):
		depth = value
		changed.emit()
## How far the noise lifts or lowers the bed, in metres each way.
@export_range(0.0, 50.0, 0.1, "suffix:m") var noise_height := 1.0:
	set(value):
		noise_height = value
		changed.emit()
## The pattern of the bumps. Godot's own noise, so the inspector shows a preview and the seed,
## frequency and octaves are all there to turn.
@export var noise: FastNoiseLite:
	set(value):
		if noise != null and noise.changed.is_connected(_on_noise_changed):
			noise.changed.disconnect(_on_noise_changed)
		noise = value
		if noise != null:
			noise.changed.connect(_on_noise_changed)
		changed.emit()
## Metres of water far out, once the bed has finished dropping away.
@export_range(0.0, 1000.0, 1.0, "suffix:m") var far_depth := 60.0:
	set(value):
		far_depth = value
		changed.emit()
## How far from the middle the bed stays at `depth` before it starts to drop away.
##
## Round the middle rather than from the edge of the Terrain's square: an island's own slope is
## round, and a bed that deepened from the square's edges had square contours, which the sea's
## colour drew from above as a lighter square with straight sides round the island.
@export_range(0.0, 5000.0, 1.0, "suffix:m") var shelf_radius := 200.0:
	set(value):
		shelf_radius = maxf(value, 0.0)
		changed.emit()
## How far past shelf_radius the bed takes to drop from `depth` to `far_depth`, easing in and
## out of the slope so it has no crease at either end.
@export_range(1.0, 5000.0, 1.0, "suffix:m") var deepening_distance := 350.0:
	set(value):
		deepening_distance = maxf(value, 1.0)
		changed.emit()


func _on_noise_changed() -> void:
	changed.emit()


## The seabed at a world point, in the asker's metres: `sea_level` is where the water stands,
## and `centre` (world x, z) the middle the bed deepens away from.
func height_at(world_x: float, world_z: float, sea_level: float, centre: Vector2) -> float:
	var bump := noise.get_noise_2d(world_x, world_z) * noise_height if noise != null else 0.0
	return sea_level - _water(Vector2(world_x, world_z).distance_to(centre)) + bump


## Metres of water, before the noise, `from_middle` metres out.
func _water(from_middle: float) -> float:
	var past := from_middle - shelf_radius
	if past <= 0.0:
		return depth
	return lerpf(depth, far_depth, smoothstep(0.0, deepening_distance, past))


## The same heights over a square grid - `size` samples a side, `spacing` apart, the first at
## (first, first), the middle the bed deepens from at the grid's own middle - divided by
## `scale`, row by row. The Terrain's whole grid in one call: a million height_at() calls took
## 0.6 s, most of it the calls themselves.
func fill(size: int, spacing: float, first: float, sea_level: float,
		scale: float) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var middle := first + (size - 1) * spacing * 0.5
	for gz in size:
		var wz := first + gz * spacing
		var row := gz * size
		for gx in size:
			var wx := first + gx * spacing
			var level := sea_level - _water(Vector2(wx - middle, wz - middle).length())
			if noise != null:
				level += noise.get_noise_2d(wx, wz) * noise_height
			heights[row + gx] = level / scale
	return heights
