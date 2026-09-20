extends StaticBody3D
## Builds a terrain mesh + collision from a 16-bit height map PNG.
##
## The image is read at runtime with Image.load_from_file, so Godot's texture importer
## cannot quietly convert it to 8-bit or apply sRGB - both of which flatten the heights.

## Raw 16-bit heights (make_heightmap.py writes these). Godot's Image loader converts a
## 16-bit PNG down to 8-bit, which shows up as visible terracing, so the .r16 is preferred
## and the PNG is only a fallback.
@export_file("*.r16") var raw_path := "res://terrain/heightmap.r16"
@export_file("*.png") var heightmap_path := "res://terrain/heightmap.png"
@export var world_size := 400.0   ## metres across
@export var height_scale := 60.0  ## metres from lowest to highest point
@export var mesh_resolution := 256  ## quads per side for the visual mesh
@export var collision_resolution := 257  ## samples per side for the collision shape (match mesh_resolution + 1)

var _heights: PackedFloat32Array
var _size := 0


func _ready() -> void:
	var source := "raw" if _load_raw() else ("png" if _load_png() else "")
	if source == "":
		push_error("Could not load a height map (%s or %s)" % [raw_path, heightmap_path])
		return
	_build_mesh()
	_build_collision()


func _load_raw() -> bool:
	var file := FileAccess.open(raw_path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(file.get_length())
	var count := bytes.size() / 2
	_size = int(sqrt(float(count)))
	if _size * _size != count:
		push_error("%s is not square (%d samples)" % [raw_path, count])
		return false
	_heights = PackedFloat32Array()
	_heights.resize(count)
	for i in count:
		_heights[i] = bytes.decode_u16(i * 2) / 65535.0
	return true


func _load_png() -> bool:
	var image := Image.load_from_file(ProjectSettings.globalize_path(heightmap_path))
	if image == null:
		return false
	_size = image.get_width()
	_heights = PackedFloat32Array()
	_heights.resize(_size * _size)
	for y in _size:
		for x in _size:
			_heights[y * _size + x] = image.get_pixel(x, y).r
	return true


## Bilinear sample of the height map in 0..1 texture space.
func sample_height(u: float, v: float) -> float:
	u = clampf(u, 0.0, 1.0) * (_size - 1)
	v = clampf(v, 0.0, 1.0) * (_size - 1)
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, _size - 1)
	var y1 := mini(y0 + 1, _size - 1)
	var fx := u - x0
	var fy := v - y0
	var h00 := _heights[y0 * _size + x0]
	var h10 := _heights[y0 * _size + x1]
	var h01 := _heights[y1 * _size + x0]
	var h11 := _heights[y1 * _size + x1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fy) * height_scale


## A spawn point on gentle mid-altitude ground, so the view starts somewhere interesting
## rather than on a peak or in a pit.
func find_spawn() -> Vector3:
	var best := Vector3.ZERO
	var best_score := -1.0
	for i in 400:
		var wx := randf_range(-world_size, world_size) * 0.35
		var wz := randf_range(-world_size, world_size) * 0.35
		var h := height_at(wx, wz)
		var t := h / height_scale
		# prefer mid heights, and flat-ish ground (small difference to neighbours)
		var slope: float = absf(height_at(wx + 4.0, wz) - h) + absf(height_at(wx, wz + 4.0) - h)
		var score: float = 1.0 - absf(t - 0.45) * 2.0 - slope * 0.25
		if score > best_score:
			best_score = score
			best = Vector3(wx, h, wz)
	return best


## World-space height under a point, for dropping things onto the ground.
func height_at(world_x: float, world_z: float) -> float:
	return sample_height(world_x / world_size + 0.5, world_z / world_size + 0.5)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := world_size / mesh_resolution
	for z in mesh_resolution:
		for x in mesh_resolution:
			var corners: Array[Vector2] = [Vector2(x, z), Vector2(x + 1, z),
					Vector2(x + 1, z + 1), Vector2(x, z + 1)]
			var positions: Array[Vector3] = []
			for c: Vector2 in corners:
				var wx: float = c.x * step - world_size * 0.5
				var wz: float = c.y * step - world_size * 0.5
				positions.append(Vector3(wx, sample_height(c.x / mesh_resolution, c.y / mesh_resolution), wz))
			var triangles: Array[Array] = [[0, 1, 2], [0, 2, 3]]
			for tri: Array in triangles:
				for i: int in tri:
					var p: Vector3 = positions[i]
					st.set_uv(Vector2(p.x / world_size + 0.5, p.z / world_size + 0.5))
					st.set_color(_terrain_colour(p.y / height_scale))
					st.add_vertex(p)
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	mesh_instance.material_override = material
	add_child(mesh_instance)


## Sand -> grass -> rock -> snow, so the shape reads without any textures.
## Vertex colours are used as linear albedo, so the sRGB values below have to be converted -
## otherwise everything comes out washed out and pale.
func _terrain_colour(t: float) -> Color:
	var sand := Color(0.74, 0.68, 0.50)
	var grass := Color(0.30, 0.42, 0.20)
	var rock := Color(0.44, 0.41, 0.37)
	var snow := Color(0.93, 0.94, 0.97)
	var c: Color
	if t < 0.20:
		c = sand.lerp(grass, smoothstep(0.08, 0.20, t))
	elif t < 0.55:
		c = grass.lerp(rock, smoothstep(0.38, 0.55, t))
	else:
		c = rock.lerp(snow, smoothstep(0.70, 0.86, t))
	return c.srgb_to_linear()


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = collision_resolution
	shape.map_depth = collision_resolution
	var data := PackedFloat32Array()
	data.resize(collision_resolution * collision_resolution)
	for z in collision_resolution:
		for x in collision_resolution:
			data[z * collision_resolution + x] = sample_height(
				float(x) / (collision_resolution - 1), float(z) / (collision_resolution - 1))
	shape.map_data = data
	var owner_node := CollisionShape3D.new()
	owner_node.shape = shape
	# HeightMapShape3D spans one unit per sample, so scale it out to the world size.
	owner_node.scale = Vector3(world_size / (collision_resolution - 1), 1.0,
			world_size / (collision_resolution - 1))
	add_child(owner_node)
