@tool
class_name Ocean
extends MeshInstance3D
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
@export var rings := 128
@export var segments := 256
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
@export_range(1.0, 60.0) var depth_fade := 26.0:
	set(value):
		depth_fade = value
		_push("depth_fade", value)
@export_range(0.0, 3.0) var wave_height := 0.32:
	set(value):
		wave_height = value
		_push("wave_height", value)
## The four Gerstner waves the surface is built from: direction x and y, steepness, then
## wavelength in metres.
##
## Held here and pushed to the shader, the way the colours are - not left to the shader's own
## declared defaults. Anything that floats has to work the surface out on the CPU, and a
## uniform that is never assigned reads back as null from the material AND from
## shader_get_parameter_default, so the defaults in the shader are unreachable from here. The
## buoyancy silently summed four skipped waves and put every barrel at the mean sea level.
@export var wave_1 := Vector4(1.0, 0.25, 0.72, 21.0):
	set(value):
		wave_1 = value
		_push("wave_1", value)
@export var wave_2 := Vector4(-0.5, 0.9, 0.55, 12.5):
	set(value):
		wave_2 = value
		_push("wave_2", value)
@export var wave_3 := Vector4(0.75, -0.7, 0.42, 7.0):
	set(value):
		wave_3 = value
		_push("wave_3", value)
@export var wave_4 := Vector4(-0.85, -0.3, 0.30, 3.6):
	set(value):
		wave_4 = value
		_push("wave_4", value)
## How far the waves move the water sideways, as a share of the full Gerstner displacement.
## Held here for the same reason as the waves: surface_y has to know it, and the shader's
## own default is unreachable from the CPU.
@export_range(0.0, 1.0) var choppiness := 0.85:
	set(value):
		choppiness = value
		_push("choppiness", value)
## Direction TO the sun. Seeded at setup from the scene's DirectionalLight, and from then on
## set every frame by world/day.gd as the sun moves, so the water and everything standing on
## the beach agree about where the light comes from.
@export var sun_direction := Vector3(-0.53, 0.37, 0.76):
	set(value):
		sun_direction = value
		_push("sun_direction", value)
@export_range(0.1, 40.0) var wave_speed := 1.0:
	set(value):
		wave_speed = value
		_push("wave_speed", value)
## How deep the water has to be before waves reach full height. They flatten as the seabed
## rises, which is why cargo in the shallows bobs less than cargo offshore.
@export_range(0.5, 40.0) var shoal_depth := 2.5:
	set(value):
		shoal_depth = value
		_push("shoal_depth", value)

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
var _terrain: Node3D
## The water clock, advanced here and pushed to the shader, rather than the shader reading its
## own TIME.
##
## Anything that floats has to know where the surface IS, and the surface is computed in the
## vertex shader. Working it out again on the CPU means using the same clock, and "roughly the
## same seconds since startup" is not the same clock: a fixed offset leaves a barrel bobbing at
## the right rate at the wrong moment, sitting in the trough while the crest goes past it. One
## number, set here and read by both, cannot drift.
var _clock := 0.0


func setup(sea_level: float, terrain: Node3D = null, band_focus := Vector3.ZERO) -> void:
	_sea_level = sea_level
	_terrain = terrain
	position.y = sea_level
	mesh = _radial_grid()
	if material == null:
		material = load("res://world/ocean_material.tres")
	var water := material
	for entry in [["shallow_colour", shallow_colour], ["lagoon_colour", lagoon_colour],
			["deep_colour", deep_colour],
			["foam_colour", foam_colour], ["wave_height", wave_height],
			["wave_1", wave_1], ["wave_2", wave_2], ["wave_3", wave_3], ["wave_4", wave_4],
			["choppiness", choppiness],
			["wave_speed", wave_speed], ["shoal_depth", shoal_depth],
			["sun_direction", sun_direction],
			["depth_fade", depth_fade], ["absorption", absorption],
			["absorption_strength", absorption_strength],
			["scattering_strength", scattering_strength],
			["refraction_strength", refraction_strength]]:
		water.set_shader_parameter(entry[0], entry[1])
	# The vertex shader fades displacement when an exponential ring becomes too coarse for
	# a wavelength. Passing the actual mesh layout keeps that filter correct after tuning.
	water.set_shader_parameter("radial_growth", pow(extent / near, 1.0 / float(rings)))
	water.set_shader_parameter("horizon", extent)
	water.set_shader_parameter("radial_segments", float(segments))
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


## Builds the sea in the editor, so it can be seen without pressing play.
##
## The wave preview in _process was already written to run in the editor, but nothing ever
## called setup(), which is what builds the mesh and attaches the material - main.gd calls it
## at runtime and nowhere else. So the Ocean node sat in the editor as an empty transform,
## under a comment claiming the sea could be judged without running the game. It could not, and
## anything that belongs in the water - a school of fish, a moored ship, a rock in the shallows
## - had to be placed against a bare heightmap and guessed at.
var _preview_mesh: Mesh = null


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	# Terrain is the sibling above this one in main.tscn, so its own _ready has already loaded
	# the height map by the time this runs. The sea level is its, not ours - two answers to
	# where the waterline is would drift apart the first time either was tuned.
	var terrain := get_node_or_null("../Terrain")
	if terrain == null or not terrain.has_method("sea_level"):
		return
	setup(terrain.sea_level(), terrain as Node3D)


## Keep the generated preview OUT of the saved scene file.
##
## The editor preview above builds a radial grid - about 1 MB of ArrayMesh - and assigns it to
## this node's `mesh`. Godot serialises whatever is on an exported property when the scene is
## saved, so that mesh was being written into main.tscn as text-encoded binary, and the editor
## warned that the scene had grown to 2.2 MiB. It is generated from `extent`, `rings` and
## `segments` in a fraction of a second, so storing it is pure waste.
##
## PRE_SAVE / POST_SAVE is the documented hook for this: drop the mesh, let the save happen
## without it, then put it straight back so the preview does not blink out.
func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_preview_mesh = mesh
		mesh = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		mesh = _preview_mesh
		_preview_mesh = null


func _process(delta: float) -> void:
	_clock += delta
	_push("preview_time", _clock)
	# The wave preview above runs in the editor too - that is what @tool is for here, and it
	# is how the sea is judged without pressing play. The overhead band camera below is not:
	# it is a SubViewport rendering the whole shore every frame to feed a runtime shader mask,
	# and nothing in the editor reads it.
	if Engine.is_editor_hint():
		return
	if _camera != get_viewport().get_camera_3d():
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
		# Where this camera stops drawing the sea. Its far plane, at a thousand metres, is
		# nearer than the mesh's edge, and it is where the water has to have faded out by.
		_push("horizon", minf(extent, _camera.far))
	# Horizontal follow only. The wave field is evaluated in world space in the shader, so the
	# sea itself stays put - only the grid of vertices slides along underneath it.
	var eye := _camera.global_position
	global_position = Vector3(eye.x, global_position.y, eye.z)
	_position_band_camera(eye)


## The height of the water surface at a world point - the same Gerstner sum the vertex shader
## adds to the flat sea, evaluated on the CPU so that things can float on it. The shader's copy
## is surface_height in waves.gdshaderinc; the two have to agree, and this is the one that
## cannot be included.
##
## One term of the shader's version is deliberately left out: the camera-distance fade. The
## shader flattens waves far from the eye because the mesh out there cannot resolve them, and a
## barrel that rose and fell as you walked towards it would be far worse than one that is
## slightly wrong at a distance where nothing can tell.
##
## The horizontal part of the Gerstner displacement is NOT left out, any more. A Gerstner wave
## moves water sideways as well as up - by up to 0.65 m with these waves - so the surface above
## a point is the sample taken from somewhere else. This used to read the sample at the point
## and call the error centimetres; measured against the drawn mesh by tests/underwater_view.gd,
## it was 102 mm at one spot in the shallows, a barrel floating a hand's width above the water.
## So the sample point is solved for: start at the point, ask where the water there came from,
## ask again from there. Each step only shrinks the error by the slope of the sideways
## displacement, about a half here, so eight steps; the shader does the same eight.
##
## The shoal is taken at the moving sample point every step, not once at the query point. A
## vertex of the mesh flattens by the depth under where it STARTED, not under where the wave
## carries it, and those are up to 0.65 m apart - nothing in open water, centimetres on a bed
## rising inside shoal_depth, which is where he wades.
##
## This runs about twenty-five times a physics tick (every piece of cargo, five points on the
## hull, the shark, the underwater pass's gate) and nine wave sums each, so the per-wave
## constants are prepared once per call and the four waves are summed in one function with no
## per-call allocation - see _prepare_waves.
func surface_y(x: float, z: float) -> float:
	if wave_height <= 0.0:
		return _sea_level
	_prepare_waves()
	var total_steepness := maxf(wave_1.z, 0.0) + maxf(wave_2.z, 0.0) \
			+ maxf(wave_3.z, 0.0) + maxf(wave_4.z, 0.0)
	var q := choppiness / maxf(1.0, total_steepness * wave_height)
	var at := Vector2(x, z)
	var source := at
	var offset := Vector3.ZERO
	for i in 8:
		offset = _displacement(source, _shoal_at(source) * wave_height, q)
		source = at - Vector2(offset.x, offset.z)
	offset = _displacement(source, _shoal_at(source) * wave_height, q)
	return _sea_level + offset.y


## Waves flatten as the seabed rises. This one is real rather than a rendering concession,
## so it stays: without it cargo in the shallows bobs as hard as cargo in open water.
func _shoal_at(p: Vector2) -> float:
	if _terrain == null:
		return 1.0
	return smoothstep(0.0, maxf(shoal_depth, 0.001), _sea_level - _terrain.height_at(p.x, p.y))


## Per-wave constants for _displacement: direction, wave number, steepness over wave number
## (zero for a wave that is switched off) and the time term of the phase. Packed arrays sized
## once, written in place, because this is called from a hot path and an Array built per call
## would be an allocation per call (CONVENTIONS, Part 4).
var _wave_dir := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _wave_k := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _wave_amp := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _wave_time := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])


func _prepare_waves() -> void:
	_prepare_wave(0, wave_1)
	_prepare_wave(1, wave_2)
	_prepare_wave(2, wave_3)
	_prepare_wave(3, wave_4)


func _prepare_wave(i: int, wave: Vector4) -> void:
	var direction := Vector2(wave.x, wave.y)
	var reach := direction.length()
	if reach < 0.0001 or wave.z <= 0.0:
		_wave_amp[i] = 0.0
		return
	var k: float = TAU / maxf(wave.w, 0.01)
	_wave_dir[i] = direction / reach
	_wave_k[i] = k
	_wave_amp[i] = wave.z / k
	_wave_time[i] = sqrt(9.8 * k) * _clock * wave_speed


## Where the four waves move the water that starts at `p`: x and z sideways, y up. The same
## sum as gerstner() in waves.gdshaderinc, on the same clock.
func _displacement(p: Vector2, scale: float, q: float) -> Vector3:
	var moved := Vector3.ZERO
	for i in 4:
		var a: float = _wave_amp[i] * scale
		if a == 0.0:
			continue
		var d: Vector2 = _wave_dir[i]
		var phase: float = _wave_k[i] * d.dot(p) - _wave_time[i]
		var sideways: float = a * q * cos(phase)
		moved += Vector3(sideways * d.x, a * sin(phase), sideways * d.y)
	return moved


func _setup_band_camera(water: ShaderMaterial, focus: Vector3) -> void:
	if Engine.is_editor_hint():
		# Not in the editor. This is a SubViewport rendering the whole shore every frame to
		# feed the shore-foam mask, and the preview only has to show where the water IS - so
		# the editor gets the sea without the foam band rather than a permanent second render.
		return
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
