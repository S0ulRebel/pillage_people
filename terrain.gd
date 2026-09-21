@tool
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
## Fraction of the height range that sits under water. make_heightmap.py bakes the same
## number into the island, so it has to match or the shoreline lands in the wrong place.
@export var sea_fraction := 0.10
## The material, so its colours can be tuned in the inspector instead of only in the shader.
## Only the values that depend on the scene (sea level, sun) are written from here.
@export var material: ShaderMaterial

## Colours, on the node itself rather than only inside the material. Buried under
## Material > Shader Parameters they are there but nobody finds them - and the caustics in
## particular are drawn on the seabed, so their colour lives on the terrain, which is not
## where anyone looks for the colour of something in the water.
@export_group("Colours")
@export var caustic_colour := Color(1.0, 0.88, 0.56):
	set(value):
		caustic_colour = value
		_push_colour("caustic_colour", value)
@export var seabed_colour := Color(0.78, 0.70, 0.50, 1):
	set(value):
		seabed_colour = value
		_push_colour("seabed_colour", value)
@export var deep_seabed_colour := Color(0.18, 0.36, 0.33, 1):
	set(value):
		deep_seabed_colour = value
		_push_colour("deep_seabed_colour", value)
@export var seabed_weed := Color(0.18, 0.40, 0.29, 1):
	set(value):
		seabed_weed = value
		_push_colour("seabed_weed", value)
@export var seabed_rock_colour := Color(0.27, 0.39, 0.39, 1):
	set(value):
		seabed_rock_colour = value
		_push_colour("seabed_rock_colour", value)
@export var dry_sand_colour := Color(0.93, 0.735, 0.43):
	set(value):
		dry_sand_colour = value
		_push_colour("dry_sand_colour", value)
@export var wet_sand_colour := Color(0.60, 0.42, 0.285):
	set(value):
		wet_sand_colour = value
		_push_colour("wet_sand_colour", value)
@export var grass_colour := Color(0.39, 0.555, 0.145):
	set(value):
		grass_colour = value
		_push_colour("grass_colour", value)
@export var jungle_colour := Color(0.155, 0.215, 0.105):
	set(value):
		jungle_colour = value
		_push_colour("jungle_colour", value)
@export var rock_colour := Color(0.45, 0.43, 0.46):
	set(value):
		rock_colour = value
		_push_colour("rock_colour", value)

@export_group("Caustics")
@export_range(0.02, 4.0) var caustic_scale := 0.52:
	set(value):
		caustic_scale = value
		_push_colour("caustic_scale", value)
@export_range(0.01, 0.8) var caustic_width := 0.020:
	set(value):
		caustic_width = value
		_push_colour("caustic_width", value)
@export_range(0.0, 3.0) var caustic_strength := 0.68:
	set(value):
		caustic_strength = value
		_push_colour("caustic_strength", value)
## How far from the camera the web survives. The shader also fades it by pixel
## footprint, so on a wide shot the lagoon loses its caustics unless this is opened up.
@export_range(10.0, 400.0) var caustic_distance_fade := 320.0:
	set(value):
		caustic_distance_fade = value
		_push_colour("caustic_distance_fade", value)
@export_range(0.05, 4.0) var caustic_footprint_fade := 1.2:
	set(value):
		caustic_footprint_fade = value
		_push_colour("caustic_footprint_fade", value)
@export_range(0.0, 2.0) var caustic_speed := 0.30:
	set(value):
		caustic_speed = value
		_push_colour("caustic_speed", value)
@export_range(0.5, 30.0) var caustic_reach := 12.0:
	set(value):
		caustic_reach = value
		_push_colour("caustic_reach", value)


func _push_colour(name: StringName, value: Variant) -> void:
	if material != null:
		material.set_shader_parameter(name, value)
## Quads per side. The height map has 1024 samples per side, so anything below that throws
## detail away: at 256 each quad swallowed sixteen height samples and the island came out
## smooth and faceted no matter what the shading did.
@export var mesh_resolution := 512
@export var collision_resolution := 257  ## samples per side for the collision shape (match mesh_resolution + 1)

## Tunnels that cut through this terrain. Set before generate(); each one is asked where its
## tube is, and the terrain is cut to exactly that shape - so an opening always matches its
## tunnel, whatever the slope, with nothing to line up by hand.
var tunnels: Array = []

var _heights: PackedFloat32Array
var _size := 0
var _rim_triangles := PackedVector3Array()
var _dropped := 0
var _clipped := 0   ## boundary geometry, for the precise rim collider


func _ready() -> void:
	var source := "raw" if _load_raw() else ("png" if _load_png() else "")
	if source == "":
		push_error("Could not load a height map (%s or %s)" % [raw_path, heightmap_path])
		return
	if Engine.is_editor_hint():
		# Preview the landscape in the editor - without it you would be drawing tunnel curves
		# against an empty viewport. Mesh only: collision is a runtime concern.
		_build_mesh()


## Builds the mesh and colliders. Call after setting `holes`.
func generate() -> void:
	_build_mesh()
	_build_collision()


## Negative where the ground is inside a tunnel, positive outside, zero on the opening's edge:
## the contour the terrain mesh is cut along.
func hole_field(world_x: float, world_z: float) -> float:
	if tunnels.is_empty():
		return 1e9
	var point := Vector3(world_x, sample_height(world_x / world_size + 0.5,
			world_z / world_size + 0.5), world_z)
	var best := 1e9
	for tunnel in tunnels:
		best = minf(best, tunnel.distance_outside(point))
	return best


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
## Sea level in metres, the single source of truth for the ocean plane and for swimming.
func sea_level() -> float:
	return height_scale * sea_fraction


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


## Two spots near the spawn, far enough apart to be worth a tunnel between them, on ground
## that is not a cliff.
func plan_tunnel_ends(spawn: Vector3) -> Array[Vector3]:
	var best: Array[Vector3] = []
	var best_score := -1e9
	for attempt in 4000:
		var angle := randf() * TAU
		var a := Vector3(spawn.x + cos(angle) * randf_range(25.0, 45.0), 0.0,
				spawn.z + sin(angle) * randf_range(25.0, 45.0))
		var away := angle + randf_range(2.0, 4.3)
		var b := Vector3(a.x + cos(away) * randf_range(45.0, 70.0), 0.0,
				a.z + sin(away) * randf_range(45.0, 70.0))
		if maxf(absf(b.x), absf(b.z)) > world_size * 0.45:
			continue
		a.y = height_at(a.x, a.z)
		b.y = height_at(b.x, b.z)
		# gentle ground at both ends, and not too much height difference between them
		var score: float = -absf(a.y - b.y) - _roughness(a) * 2.0 - _roughness(b) * 2.0
		if score > best_score:
			best_score = score
			best = [a, b]
	return best


func _roughness(point: Vector3) -> float:
	var h := height_at(point.x, point.z)
	var total := 0.0
	for step in 4:
		var angle := TAU * step / 4.0
		total += absf(height_at(point.x + cos(angle) * 6.0, point.z + sin(angle) * 6.0) - h)
	return total * 0.25


## The height map as a texture, so a shader can read the seabed.
##
## The water needs to know how deep it is at every point - to flatten the swell as it shoals,
## and to colour itself - and reading it from the depth buffer instead ties the colour to the
## displaced surface, which then shimmers as the waves move.
func height_texture() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(_heights.size() * 4)
	for i in _heights.size():
		bytes.encode_float(i * 4, _heights[i])
	var image := Image.create_from_data(_size, _size, false, Image.FORMAT_RF, bytes)
	return ImageTexture.create_from_image(image)


## World-space height under a point, for dropping things onto the ground.
func height_at(world_x: float, world_z: float) -> float:
	return sample_height(world_x / world_size + 0.5, world_z / world_size + 0.5)


func _build_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_rim_triangles = PackedVector3Array()
	var step := world_size / mesh_resolution
	for z in mesh_resolution:
		for x in mesh_resolution:
			var quad: Array[Vector3] = []
			for c: Vector2 in [Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]:
				quad.append(_surface_point(c.x * step - world_size * 0.5, c.y * step - world_size * 0.5))
			var inside := 0
			for p: Vector3 in quad:
				if hole_field(p.x, p.z) < 0.0:
					inside += 1
			if inside == 4:
				_dropped += 1
				continue                      # entirely inside a hole: no geometry at all
			if inside > 0:
				_clipped += 1
			var polygon: Array[Vector3] = quad if inside == 0 else _clip_to_hole_edge(quad)
			if polygon.size() < 3:
				continue
			# fan-triangulate: quads stay two triangles, clipped shapes become 3-5
			for i in range(1, polygon.size() - 1):
				var tri: Array[Vector3] = [polygon[0], polygon[i], polygon[i + 1]]
				for p: Vector3 in tri:
					st.set_uv(Vector2(p.x / world_size + 0.5, p.z / world_size + 0.5))
					st.set_color(_terrain_colour(p.y))
					st.add_vertex(p)
				if inside > 0:                # keep rim geometry for the precise collider
					_rim_triangles.append_array(tri)
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	# Cel shading is where the stylised look comes from; the vertex colours only supply which
	# biome each point is in. See terrain.gdshader.
	if material == null:
		material = load("res://terrain_material.tres")
	material.set_shader_parameter("sea_y", sea_level())
	for entry in [["caustic_colour", caustic_colour], ["seabed_colour", seabed_colour],
			["deep_seabed_colour", deep_seabed_colour], ["seabed_weed", seabed_weed],
			["seabed_rock_colour", seabed_rock_colour], ["dry_sand_colour", dry_sand_colour],
			["wet_sand_colour", wet_sand_colour], ["grass_colour", grass_colour],
			["jungle_colour", jungle_colour], ["rock_colour", rock_colour],
			["caustic_scale", caustic_scale], ["caustic_width", caustic_width],
			["caustic_strength", caustic_strength], ["caustic_reach", caustic_reach],
			["caustic_distance_fade", caustic_distance_fade], ["caustic_speed", caustic_speed],
			["caustic_footprint_fade", caustic_footprint_fade]]:
		material.set_shader_parameter(entry[0], entry[1])
	# The shader does its own shading, so it needs to know where the sun is.
	var sun := get_node_or_null("../Sun") as DirectionalLight3D
	if sun != null:
		material.set_shader_parameter("sun_direction", sun.global_transform.basis.z.normalized())
	mesh_instance.material_override = material
	add_child(mesh_instance)


## Terrain point in world space, height sampled from the map.
func _surface_point(world_x: float, world_z: float) -> Vector3:
	return Vector3(world_x, height_at(world_x, world_z), world_z)


## Clips a quad to the part outside the holes (Sutherland-Hodgman against hole_field = 0).
## This is what keeps hole rims smooth: the cut follows the circle instead of the grid,
## so the outline does not go chunky at low mesh resolution.
func _clip_to_hole_edge(polygon: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var count := polygon.size()
	for i in count:
		var current: Vector3 = polygon[i]
		var next: Vector3 = polygon[(i + 1) % count]
		var f_current := hole_field(current.x, current.z)
		var f_next := hole_field(next.x, next.z)
		if f_current >= 0.0:
			result.append(current)
		if (f_current >= 0.0) != (f_next >= 0.0):
			# crossing the rim: walk to the zero of the field along this edge
			var t: float = f_current / (f_current - f_next)
			var cut: Vector3 = current.lerp(next, clampf(t, 0.0, 1.0))
			result.append(_surface_point(cut.x, cut.z))
	return result


## Seabed -> sand -> jungle -> rock, keyed to sea level rather than to the lowest point.
##
## Keying the bands to the map's minimum painted a snowcap on a tropical island and put the
## beach underwater. Sea level is the landmark that matters here: sand belongs just above it,
## and everything below it is seabed nobody walks on.
## The colours are sampled from the material study in the art reference (sand, leaves, rock),
## toned down a little: those spheres are rendered lit, so using their values raw as albedo
## lights them twice and the beach blows out to orange.
## Vertex colours are used as linear albedo, so the sRGB values have to be converted -
## otherwise everything comes out washed out and pale.
func _terrain_colour(height_m: float) -> Color:
	var seabed := Color(0.55, 0.52, 0.40)
	var sand := Color(0.85, 0.68, 0.45)
	var jungle := Color(0.31, 0.38, 0.24)
	var rock := Color(0.46, 0.40, 0.40)
	# Metres above the waterline, not a fraction of the height range: keyed to the fraction,
	# a beach on a 180 m island covered everything from 11 m to 34 m of elevation and a third
	# of the island came out as sand.
	var above := height_m - sea_level()
	var c: Color = seabed.lerp(sand, smoothstep(-1.5, 0.3, above))
	c = c.lerp(jungle, smoothstep(1.5, 6.0, above))
	c = c.lerp(rock, smoothstep(height_scale * 0.50, height_scale * 0.80, height_m))
	return c.srgb_to_linear()


## Collision is a hybrid: a cheap height field for the bulk of the terrain, with NaN samples
## (holes - Jolt supports these) wherever a hole is, plus a small trimesh built from the cut
## rim quads so the edges line up with what is drawn instead of with the collider's grid.
func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = collision_resolution
	shape.map_depth = collision_resolution
	var spacing := world_size / (collision_resolution - 1)
	var data := PackedFloat32Array()
	data.resize(collision_resolution * collision_resolution)
	for z in collision_resolution:
		for x in collision_resolution:
			var wx := x * spacing - world_size * 0.5
			var wz := z * spacing - world_size * 0.5
			var height := sample_height(float(x) / (collision_resolution - 1),
					float(z) / (collision_resolution - 1))
			# Knock out every sample inside the opening. Keeping a margin of solid samples
			# there left an invisible floor across most of the hole; the cut rim quads (the
			# trimesh below) are what covers the boundary cells.
			data[z * collision_resolution + x] = NAN if hole_field(wx, wz) < 0.0 else height
	shape.map_data = data
	if _rim_triangles.size() > 0:
		var rim := ConcavePolygonShape3D.new()
		rim.set_faces(_rim_triangles)
		var rim_collider := CollisionShape3D.new()
		rim_collider.shape = rim
		add_child(rim_collider)
	var owner_node := CollisionShape3D.new()
	owner_node.shape = shape
	# HeightMapShape3D spans one unit per sample, so scale it out to the world size.
	owner_node.scale = Vector3(world_size / (collision_resolution - 1), 1.0,
			world_size / (collision_resolution - 1))
	add_child(owner_node)
