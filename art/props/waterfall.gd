@tool
extends Path3D
class_name Waterfall
## A waterfall you place in the scene: draw a curve down the rock, set a width, done.
##
## Built the same way tunnel.gd is - a @tool Path3D that rebuilds as you drag the curve - so
## hanging one on a cliff feels like placing a tunnel. Where the tunnel extrudes a tube, this
## extrudes a ribbon, and the curve is what lets a fall bow out from the face, kink over a
## ledge, or drop dead straight.
##
## There is no collision. You walk through it, which is the point: the plan is caves behind.

const SHADER := "res://waterfall.gdshader"

@export var width := 2.4:
	set(value):
		width = maxf(value, 0.05)
		_queue()
## Falls fan out on the way down. 1.0 keeps it parallel-sided.
@export var spread := 1.55:
	set(value):
		spread = maxf(value, 0.05)
		_queue()
## Distance between cross-sections along the curve - tunnel.gd's own name for the same idea.
@export var sample_spacing := 0.7:
	set(value):
		sample_spacing = maxf(value, 0.1)
		_queue()
## Two overlapping sheets scrolling at different rates. One sheet always reads as a decal; the
## second is what gives falling water any depth at all.
@export_range(1, 3) var sheets := 2:
	set(value):
		sheets = clampi(value, 1, 3)
		_queue()
## How far apart the sheets sit, in metres. Enough to separate them, not enough to see a gap.
@export var sheet_gap := 0.18:
	set(value):
		sheet_gap = value
		_queue()

@export_group("Look")
@export var water_colour := Color(0.62, 0.86, 0.90):
	set(value):
		water_colour = value
		_queue()
@export var speed := 1.7:
	set(value):
		speed = value
		_queue()
@export var mist := true:
	set(value):
		mist = value
		_queue()

var _queued := false


func _ready() -> void:
	if curve == null:
		curve = Curve3D.new()
	# A stable frame along the curve. Crossing the tangent with world up is the obvious way to
	# work out which direction is "sideways" for a ribbon, and it collapses to nothing when the
	# curve runs vertically - which for a waterfall is always. Godot's own up vectors do not
	# have that problem, and they let a curve point be tilted to twist the sheet at the lip.
	curve.up_vector_enabled = true
	rebuild()


func _queue() -> void:
	if is_inside_tree() and not _queued:
		_queued = true
		rebuild.call_deferred()


func rebuild() -> void:
	_queued = false
	if not is_inside_tree():
		return
	for child in get_children():
		child.queue_free()
		remove_child(child)
	if curve == null or curve.point_count < 2:
		return
	var length := curve.get_baked_length()
	if length < 0.2:
		return

	var steps := maxi(2, int(ceil(length / sample_spacing)))
	for sheet in sheets:
		var offset := (float(sheet) - float(sheets - 1) * 0.5) * sheet_gap
		var surface := _build_sheet(steps, length, offset)
		var instance := MeshInstance3D.new()
		instance.name = "Sheet%d" % sheet
		instance.mesh = surface
		instance.material_override = _material(sheet)
		# Deliberately NOT on layer 20. The ocean's overhead camera reads that layer to mask
		# its foam band, and a waterfall hanging over the water would stamp a hole in the band
		# the whole length of the fall.
		instance.layers = 1
		add_child(instance)
		if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
			instance.owner = get_tree().edited_scene_root
	if mist:
		_add_mist(curve.sample_baked(length))


## One ribbon along the curve, widening as it falls.
func _build_sheet(steps: int, length: float, push: float) -> ArrayMesh:
	var tool_mesh := SurfaceTool.new()
	tool_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lefts: Array[Vector3] = []
	var rights: Array[Vector3] = []
	for i in steps + 1:
		var along := float(i) / float(steps)
		var distance := along * length
		var point := curve.sample_baked(distance)
		var up := curve.sample_baked_up_vector(distance, true)
		var ahead := curve.sample_baked(minf(distance + 0.1, length))
		var behind := curve.sample_baked(maxf(distance - 0.1, 0.0))
		var tangent := (ahead - behind)
		if tangent.length() < 0.0001:
			tangent = Vector3.DOWN
		tangent = tangent.normalized()
		var side := tangent.cross(up)
		if side.length() < 0.0001:
			side = tangent.cross(Vector3.FORWARD)
		side = side.normalized()
		# Wider toward the bottom, and nudged along the face so the sheets do not coincide.
		var half := width * lerpf(1.0, spread, along) * 0.5
		var shove := up.normalized() * push
		lefts.append(point - side * half + shove)
		rights.append(point + side * half + shove)

	for i in steps:
		var v0 := float(i) / float(steps)
		var v1 := float(i + 1) / float(steps)
		_quad(tool_mesh, lefts[i], rights[i], rights[i + 1], lefts[i + 1], v0, v1)
	tool_mesh.generate_normals()
	return tool_mesh.commit()


func _quad(tool_mesh: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		v0: float, v1: float) -> void:
	tool_mesh.set_uv(Vector2(0.0, v0)); tool_mesh.add_vertex(a)
	tool_mesh.set_uv(Vector2(1.0, v0)); tool_mesh.add_vertex(b)
	tool_mesh.set_uv(Vector2(1.0, v1)); tool_mesh.add_vertex(c)
	tool_mesh.set_uv(Vector2(0.0, v0)); tool_mesh.add_vertex(a)
	tool_mesh.set_uv(Vector2(1.0, v1)); tool_mesh.add_vertex(c)
	tool_mesh.set_uv(Vector2(0.0, v1)); tool_mesh.add_vertex(d)


func _material(sheet: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHADER)
	material.set_shader_parameter("water_colour", water_colour)
	# Each sheet runs at its own rate, or the two move as one object and the second sheet buys
	# nothing but overdraw.
	material.set_shader_parameter("speed", speed * (1.0 + float(sheet) * 0.28))
	material.set_shader_parameter("streaks", 9.0 + float(sheet) * 3.0)
	material.set_shader_parameter("base_alpha", 0.60 if sheet == 0 else 0.34)
	return material


## Spray where it lands. A sheet that simply stops at the water reads as broken - the mist is
## what joins the two.
func _add_mist(at: Vector3) -> void:
	var spray := CPUParticles3D.new()
	spray.name = "Mist"
	add_child(spray)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		spray.owner = get_tree().edited_scene_root
	spray.position = at
	spray.amount = 26
	spray.lifetime = 1.3
	spray.local_coords = false
	spray.direction = Vector3.UP
	spray.spread = 75.0
	spray.initial_velocity_min = 0.6
	spray.initial_velocity_max = 2.2
	spray.gravity = Vector3(0.0, -1.4, 0.0)
	spray.scale_amount_min = 0.10 * width
	spray.scale_amount_max = 0.26 * width
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.35))
	shrink.add_point(Vector2(0.4, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	spray.scale_amount_curve = shrink
	var fade := Gradient.new()
	fade.set_color(0, Color(0.95, 0.99, 1.0, 0.5))
	fade.set_color(1, Color(0.95, 0.99, 1.0, 0.0))
	spray.color_ramp = fade
	var puff := SphereMesh.new()
	puff.radius = 0.5
	puff.height = 1.0
	puff.radial_segments = 6
	puff.rings = 3
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.vertex_color_use_as_albedo = true
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	puff.material = surface
	spray.mesh = puff
	spray.emitting = true
