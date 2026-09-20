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

## Holes punched through the terrain, as Vector3(world_x, world_z, radius).
## Set before generate() - main.gd picks them near the spawn point.
var holes: Array[Vector3] = []

var _heights: PackedFloat32Array
var _size := 0
var _rim_triangles := PackedVector3Array()   ## boundary geometry, for the precise rim collider


func _ready() -> void:
	var source := "raw" if _load_raw() else ("png" if _load_png() else "")
	if source == "":
		push_error("Could not load a height map (%s or %s)" % [raw_path, heightmap_path])


## Builds the mesh and colliders. Call after setting `holes`.
func generate() -> void:
	_build_mesh()
	_build_collision()


## Negative inside a hole, positive outside, zero on the rim: the contour the mesh is cut along.
func hole_field(world_x: float, world_z: float) -> float:
	var best := 1e9
	for h in holes:
		best = minf(best, Vector2(world_x - h.x, world_z - h.y).length() - h.z)
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


## Picks `count` hole positions near the spawn: flat-ish ground, spread apart, and not so
## close to the player that they fall straight in on the first step.
func plan_holes(spawn: Vector3, count: int, hole_radius := 11.6) -> Array[Vector3]:
	# Craters want flat ground; if the terrain has none nearby, accept rougher spots rather
	# than give up (no holes at all would leave the demo without tunnels).
	for tolerance in [3.5, 5.0, 7.5, 12.0]:
		var found := _find_hole_sites(spawn, count, hole_radius, tolerance)
		if found.size() >= count:
			return found
	return []


func _find_hole_sites(spawn: Vector3, count: int, hole_radius: float,
		tolerance: float) -> Array[Vector3]:
	var chosen: Array[Vector3] = []
	var attempts := 0
	while chosen.size() < count and attempts < 20000:
		attempts += 1
		var angle := randf() * TAU
		var distance := randf_range(32.0, 70.0)
		var wx: float = spawn.x + cos(angle) * distance
		var wz: float = spawn.z + sin(angle) * distance
		if absf(wx) > world_size * 0.45 or absf(wz) > world_size * 0.45:
			continue
		var h := height_at(wx, wz)
		# the whole rim has to sit close to the centre height, or the crater becomes a cliff
		# on one side and sticks out of the ground on the other
		var rim_ok := true
		for step in 8:
			var a := TAU * step / 8.0
			if absf(height_at(wx + cos(a) * hole_radius, wz + sin(a) * hole_radius) - h) > tolerance:
				rim_ok = false
				break
		if not rim_ok:
			continue
		# holes at similar heights keep the tunnel between them gentle
		if chosen.size() > 0 and absf(h - height_at(chosen[0].x, chosen[0].y)) > 6.0:
			continue
		var clear := true
		for other in chosen:
			if Vector2(wx - other.x, wz - other.y).length() < 45.0:
				clear = false
		if clear:
			chosen.append(Vector3(wx, wz, hole_radius))
	return chosen


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
				continue                      # entirely inside a hole: no geometry at all
			var polygon: Array[Vector3] = quad if inside == 0 else _clip_to_hole_edge(quad)
			if polygon.size() < 3:
				continue
			# fan-triangulate: quads stay two triangles, clipped shapes become 3-5
			for i in range(1, polygon.size() - 1):
				var tri: Array[Vector3] = [polygon[0], polygon[i], polygon[i + 1]]
				for p: Vector3 in tri:
					st.set_uv(Vector2(p.x / world_size + 0.5, p.z / world_size + 0.5))
					st.set_color(_terrain_colour(p.y / height_scale))
					st.add_vertex(p)
				if inside > 0:                # keep rim geometry for the precise collider
					_rim_triangles.append_array(tri)
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
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
			# Only knock out samples a full cell INSIDE the hole. Going the other way (a
			# margin outside) leaves a ring where the height field is gone but the rim
			# trimesh does not reach - a gap in the world that swallows the player.
			data[z * collision_resolution + x] = NAN if hole_field(wx, wz) < -spacing else height
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
