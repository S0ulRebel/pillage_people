@tool
extends MeshInstance3D
class_name Ocean
## The sea surface: one big plane at sea level, visible from above and below.
##
## Sea level is not stored here - it comes from the terrain, because the height map was
## generated with a sea level baked into it and the two must agree or the shoreline is wrong.

## How far the water extends past the island, so there is open sea on every horizon.
@export var extent := 4000.0
@export var shallow := Color(0.22, 0.65, 0.72)
@export var deep := Color(0.03, 0.18, 0.34)
## Below 1.0 you can see the seabed through the surface, which is most of the appeal.
@export_range(0.0, 1.0) var opacity := 0.93


func setup(sea_level: float) -> void:
	position.y = sea_level
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	# A few subdivisions so a wave shader has vertices to move later on.
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
	mesh = plane

	var water := StandardMaterial3D.new()
	water.albedo_color = Color(shallow.r, shallow.g, shallow.b, opacity)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Seen from underneath as well, so the surface reads as a ceiling while diving.
	water.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.metallic = 0.3
	water.roughness = 0.08
	water.emission_enabled = true
	water.emission = deep
	water.emission_energy_multiplier = 0.35
	# Past the shore there is no seabed under the water, so a see-through surface there shows
	# sky and the sea appears to stop. The open water has to carry its own colour.
	material_override = water
