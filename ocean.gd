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

var _camera: Camera3D


func setup(sea_level: float, terrain: Node3D = null) -> void:
	position.y = sea_level
	mesh = _radial_grid()
	var water := ShaderMaterial.new()
	water.shader = load("res://ocean.gdshader")
	water.set_shader_parameter("shallow_colour", shallow)
	water.set_shader_parameter("deep_colour", deep)
	if terrain != null:
		water.set_shader_parameter("terrain_height", terrain.height_texture())
		water.set_shader_parameter("terrain_size", terrain.world_size)
		water.set_shader_parameter("terrain_scale", terrain.height_scale)
		water.set_shader_parameter("sea_y", sea_level)
	var sun := get_node_or_null("../Sun") as DirectionalLight3D
	if sun != null:
		water.set_shader_parameter("sun_direction", -sun.global_transform.basis.z)
	material_override = water
	# The waves move vertices outside their own quad and the grid re-centres every frame, so
	# Godot's computed bounds are wrong constantly. A generous AABB stops it culling the sea
	# whenever the camera looks along the horizon.
	custom_aabb = AABB(Vector3(-extent, -60.0, -extent), Vector3(extent * 2.0, 120.0, extent * 2.0))


func _process(_delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	# Horizontal follow only. The wave field is evaluated in world space in the shader, so the
	# sea itself stays put - only the grid of vertices slides along underneath it.
	var eye := _camera.global_position
	global_position = Vector3(eye.x, global_position.y, eye.z)


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
