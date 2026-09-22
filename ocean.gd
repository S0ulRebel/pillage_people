@tool
extends MeshInstance3D
class_name Ocean
## The sea: a displaced surface, not a coloured plane.
##
## Sea level is not stored here - it comes from the terrain, because the height map was
## generated with a sea level baked into it and the two must agree or the shoreline is wrong.
##
## The mesh is a radial grid centred on the camera: small quads underfoot growing to hundreds
## of metres at the horizon. Waves need real vertices to displace, and a uniform grid cannot
## do both - fine enough to carry a wave near the player would be millions of triangles by the
## time it reached the horizon - so the grid follows the viewer instead.

## Where the visible sea ends. Beyond this there is only sky.
@export var extent := 4000.0
## Radius of the innermost ring, so roughly the size of the first quads.
@export var near := 0.6
@export var rings := 72
@export var segments := 128
## Sampled from the "Shallow (sand)" and "Deep ocean" swatches in the art reference.
@export var shallow := Color(0.310, 0.621, 0.655)
@export var deep := Color(0.059, 0.336, 0.477)
## The material, so the water colours can be tuned in the inspector.
@export var material: ShaderMaterial

## On the node as well as in the material, so they are found without digging.
## Note the caustics are not here - they are drawn on the seabed, so their colour is on Terrain.
@export_group("Colours")
@export var shallow_colour := Color(0.08, 0.64, 0.68):
	set(value):
		shallow_colour = value
		_push("shallow_colour", value)
@export var lagoon_colour := Color(0.025, 0.48, 0.60):
	set(value):
		lagoon_colour = value
		_push("lagoon_colour", value)
@export var deep_colour := Color(0.059, 0.336, 0.477):
	set(value):
		deep_colour = value
		_push("deep_colour", value)
@export var foam_colour := Color(0.95, 0.98, 1.0):
	set(value):
		foam_colour = value
		_push("foam_colour", value)
@export_range(0.0, 1.0) var shallow_alpha := 0.58:
	set(value):
		shallow_alpha = value
		_push("shallow_alpha", value)
@export_range(0.0, 1.0) var deep_alpha := 0.94:
	set(value):
		deep_alpha = value
		_push("deep_alpha", value)
@export_range(1.0, 60.0) var depth_fade := 26.0:
	set(value):
		depth_fade = value
		_push("depth_fade", value)
@export_range(0.0, 3.0) var wave_height := 0.32:
	set(value):
		wave_height = value
		_push("wave_height", value)

@export_group("Optics")
## Per-metre RGB absorption. Warm light is removed first to create turquoise shallows.
@export var absorption := Vector3(0.24, 0.075, 0.028):
	set(value):
		absorption = value.max(Vector3.ZERO)
		_push("absorption", absorption)
@export_range(0.0, 3.0) var absorption_strength := 0.78:
	set(value):
		absorption_strength = value
		_push("absorption_strength", value)
@export_range(0.0, 1.5) var scattering_strength := 0.68:
	set(value):
		scattering_strength = value
		_push("scattering_strength", value)
@export_range(0.0, 0.05, 0.001) var refraction_strength := 0.008:
	set(value):
		refraction_strength = value
		_push("refraction_strength", value)

@export_group("Object Bands")
## Width of the square area captured by the overhead water-band camera.
@export_range(48.0, 256.0) var band_capture_size := 144.0
@export_range(128, 1024) var band_texture_size := 512


func _push(name: StringName, value: Variant) -> void:
	if material != null:
		material.set_shader_parameter(name, value)

var _camera: Camera3D
var _band_viewport: SubViewport
var _band_camera: Camera3D
var _sea_level := 0.0


func setup(sea_level: float, terrain: Node3D = null, band_focus := Vector3.ZERO) -> void:
	_sea_level = sea_level
	position.y = sea_level
	mesh = _radial_grid()
	if material == null:
		material = load("res://ocean_material.tres")
	var water := material
	for entry in [["shallow_colour", shallow_colour], ["lagoon_colour", lagoon_colour],
			["deep_colour", deep_colour],
			["foam_colour", foam_colour], ["shallow_alpha", shallow_alpha],
			["deep_alpha", deep_alpha], ["wave_height", wave_height],
			["depth_fade", depth_fade], ["absorption", absorption],
			["absorption_strength", absorption_strength],
			["scattering_strength", scattering_strength],
			["refraction_strength", refraction_strength]]:
		water.set_shader_parameter(entry[0], entry[1])
	if terrain != null:
		water.set_shader_parameter("terrain_height", terrain.height_texture())
		water.set_shader_parameter("terrain_size", terrain.world_size)
		water.set_shader_parameter("terrain_scale", terrain.height_scale)
		water.set_shader_parameter("sea_y", sea_level)
		water.set_shader_parameter("terrain_center", Vector2(terrain.global_position.x, terrain.global_position.z))
		water.set_shader_parameter("terrain_base_y", terrain.global_position.y)
	var sun := get_node_or_null("../Sun") as DirectionalLight3D
	if sun != null:
		water.set_shader_parameter("sun_direction", sun.global_transform.basis.z.normalized())
	material_override = water
	_setup_band_camera(water, band_focus)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The waves move vertices outside their own quad and the grid re-centres every frame, so
	# Godot's computed bounds are wrong constantly. A generous AABB stops it culling the sea
	# whenever the camera looks along the horizon.
	custom_aabb = AABB(Vector3(-extent, -60.0, -extent), Vector3(extent * 2.0, 120.0, extent * 2.0))


func _process(_delta: float) -> void:
	if _camera != get_viewport().get_camera_3d():
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	# Horizontal follow only. The wave field is evaluated in world space in the shader, so the
	# sea itself stays put - only the grid of vertices slides along underneath it.
	var eye := _camera.global_position
	global_position = Vector3(eye.x, global_position.y, eye.z)
	_position_band_camera(eye)


func _setup_band_camera(water: ShaderMaterial, focus: Vector3) -> void:
	if _band_viewport != null:
		_band_viewport.queue_free()
	_band_viewport = SubViewport.new()
	_band_viewport.name = "WaterBandViewport"
	_band_viewport.size = Vector2i(band_texture_size, band_texture_size)
	_band_viewport.transparent_bg = true
	_band_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_band_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_band_viewport.world_3d = get_world_3d()
	add_child(_band_viewport)
	_band_camera = Camera3D.new()
	_band_camera.name = "WaterBandCamera"
	_band_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_band_camera.size = band_capture_size
	_band_camera.near = 0.1
	# End the capture at the water plane. Fully submerged objects are clipped, while
	# geometry crossing the surface leaves an overhead silhouette.
	_band_camera.far = 220.1
	_band_camera.cull_mask = 0
	_band_camera.set_cull_mask_value(20, true)
	# Looking straight down maps world +X/+Z to texture +X/+Y.
	_band_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_band_viewport.add_child(_band_camera)
	_band_camera.current = true
	water.set_shader_parameter("band_mask", _band_viewport.get_texture())
	water.set_shader_parameter("band_mask_texel",
		Vector2.ONE / float(maxi(band_texture_size, 1)))
	water.set_shader_parameter("band_mask_size", band_capture_size)
	water.set_shader_parameter("band_mask_ready", true)
	_position_band_camera(focus)


func _position_band_camera(focus: Vector3) -> void:
	if _band_camera == null:
		return
	var texel := band_capture_size / float(maxi(band_texture_size, 1))
	var centre := Vector2(snappedf(focus.x, texel), snappedf(focus.z, texel))
	_band_camera.global_position = Vector3(centre.x, global_position.y + 220.0, centre.y)
	material.set_shader_parameter("band_mask_center", centre)


## Rings of vertices at exponentially growing radius: dense at the centre, coarse at the
## horizon, and no seams, because every ring has the same number of segments.
func _radial_grid() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	var growth: float = pow(extent / near, 1.0 / float(rings))
	var radius := near
	for ring in rings:
		for s in segments:
			var angle := TAU * float(s) / float(segments)
			vertices.append(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))
		radius *= growth

	for s in segments:                      # centre fan
		indices.append(0)
		indices.append(1 + s)
		indices.append(1 + (s + 1) % segments)
	for ring in range(rings - 1):
		var inner := 1 + ring * segments
		var outer := inner + segments
		for s in segments:
			var s2 := (s + 1) % segments
			indices.append(inner + s)
			indices.append(outer + s)
			indices.append(outer + s2)
			indices.append(inner + s)
			indices.append(outer + s2)
			indices.append(inner + s2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return array_mesh
