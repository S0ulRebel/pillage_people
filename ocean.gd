@tool
extends MeshInstance3D
class_name Ocean
## The sea surface: one big plane at sea level, visible from above and below.
##
## Sea level is not stored here - it comes from the terrain, because the height map was
## generated with a sea level baked into it and the two must agree or the shoreline is wrong.

## How far the water extends past the island, so there is open sea on every horizon.
@export var extent := 4000.0
## Sampled from the "Shallow (sand)" and "Deep ocean" swatches in the water study.
@export var shallow := Color(0.310, 0.621, 0.655)
@export var deep := Color(0.059, 0.336, 0.477)
## Transparency is driven by depth in the shader now - shallows show the sand, open water
## does not - so there is no single opacity to set here.


func setup(sea_level: float) -> void:
	position.y = sea_level
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	plane.subdivide_width = 8
	plane.subdivide_depth = 8
	mesh = plane

	# The look lives in ocean.gdshader: depth drives colour, transparency and the foam line.
	var water := ShaderMaterial.new()
	water.shader = load("res://ocean.gdshader")
	water.set_shader_parameter("shallow_colour", shallow)
	water.set_shader_parameter("deep_colour", deep)
	material_override = water
