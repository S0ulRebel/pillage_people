class_name Underwater
extends MeshInstance3D
## The view from under the sea. A quad pinned to the screen, whose shader fogs the frame blue
## below the waterline and leaves it alone above.
##
## The sea's own numbers - the waves, the seabed, the clock, the sun - are not stored here.
## They are read off the ocean's material every frame and handed to this shader unchanged, so
## the waterline this draws is the surface the ocean draws, at the same moment. Two answers to
## where the surface is would drift apart the first time either was tuned, and this one would
## then split the screen a hand's width off the waves.

## The sea this is the underside of. Handed in by whoever builds the scene.
@export var ocean: Ocean

@export_group("Colours")
@export var water_colour := Color(0.09, 0.68, 0.72):
	set(value):
		water_colour = value
		_push("water_colour", value)
@export var glow_colour := Color(0.10, 0.76, 0.95):
	set(value):
		glow_colour = value
		_push("glow_colour", value)
@export var level_colour := Color(0.02, 0.46, 0.75):
	set(value):
		level_colour = value
		_push("level_colour", value)
@export var floor_colour := Color(0.01, 0.31, 0.52):
	set(value):
		floor_colour = value
		_push("floor_colour", value)
@export var abyss_colour := Color(0.05, 0.33, 0.47):
	set(value):
		abyss_colour = value
		_push("abyss_colour", value)

@export_group("Fog")
@export_range(1.0, 100.0) var fog_distance := 14.0:
	set(value):
		fog_distance = value
		_push("fog_distance", value)
@export_range(0.0, 0.8) var haze := 0.5:
	set(value):
		haze = value
		_push("haze", value)
@export_range(0.0, 1.0) var band_strength := 0.35:
	set(value):
		band_strength = value
		_push("band_strength", value)
@export_range(1.0, 40.0) var deep_fade := 12.0:
	set(value):
		deep_fade = value
		_push("deep_fade", value)
@export_range(0.0, 1.0) var shaft_strength := 0.35:
	set(value):
		shaft_strength = value
		_push("shaft_strength", value)

## How far above the surface the camera can be and still get the pass. The near plane spans a
## few centimetres of world, so this is the margin for the wave crest between two frames.
@export var margin := 0.5

## Everything the shader shares with the ocean's, by the ocean's names. The sampler and the
## terrain numbers are the seabed, which the waves shoal over.
const MIRRORED: Array[StringName] = [
	&"terrain_height", &"terrain_size", &"terrain_scale", &"terrain_center", &"terrain_base_y",
	&"sea_y", &"preview_time", &"wave_1", &"wave_2", &"wave_3", &"wave_4", &"wave_height",
	&"wave_speed", &"shoal_depth", &"choppiness", &"sun_direction",
]

var material: ShaderMaterial
var _complained := false


func setup(sea: Ocean) -> void:
	ocean = sea
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	mesh = quad
	material = ShaderMaterial.new()
	material.shader = load("res://world/underwater.gdshader")
	# After every other transparent thing - the sea from below, the waterfall - or the fog
	# would be drawn first and they would sit on top of it, unfogged.
	material.render_priority = 100
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader pins the quad to the screen and ignores where the node is, so Godot's bounds
	# for it are meaningless. A box the size of the sea stops it being culled.
	custom_aabb = AABB(Vector3(-4000.0, -4000.0, -4000.0), Vector3(8000.0, 8000.0, 8000.0))
	for entry in [["water_colour", water_colour], ["glow_colour", glow_colour],
			["level_colour", level_colour],
			["floor_colour", floor_colour], ["abyss_colour", abyss_colour],
			["fog_distance", fog_distance], ["haze", haze], ["band_strength", band_strength],
			["deep_fade", deep_fade], ["shaft_strength", shaft_strength]]:
		material.set_shader_parameter(entry[0], entry[1])
	_mirror()


func _push(name: StringName, value: Variant) -> void:
	if material != null:
		material.set_shader_parameter(name, value)


func _mirror() -> void:
	var source := ocean.material
	for name in MIRRORED:
		var value: Variant = source.get_shader_parameter(name)
		# A uniform the ocean never assigned reads back as null, not as the shader's default
		# (see ocean.gd on the waves). Passing that null on would not leave the default alone
		# here, it would clear it - so it is skipped, and both shaders keep the declared value.
		if value != null:
			material.set_shader_parameter(name, value)


func _process(_delta: float) -> void:
	if ocean == null or ocean.material == null or material == null:
		if not _complained:
			_complained = true
			push_error("Underwater has no ocean to be under - call setup() with one")
		visible = false
		return
	_mirror()
	# A full-screen pass costs the same whether it draws anything or not, so it is switched
	# off entirely while the camera is clear of the water. The per-pixel split in the shader
	# handles the crossing itself; this only has to be generous enough not to cut it off.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		visible = false
		return
	var eye := camera.global_position
	visible = eye.y < ocean.surface_y(eye.x, eye.z) + margin
