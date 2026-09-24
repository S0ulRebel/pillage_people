@tool
class_name TerrainStamp
extends Node3D
## Reshapes the island under it: adds a landform, or levels the ground to a plane.
##
## Put it under the Terrain node, move it with the gizmo and turn it about Y. The terrain reads
## every stamp among its children, top to bottom, before it builds the mesh, the collider and
## the seabed the water sees, so all three follow. The island file itself is never changed -
## delete the stamp and the ground is back.
##
## The shape says how much, 0 to 1: black leaves the ground alone, white gets the full effect,
## grey part of it. That is what makes a flattened pad blend into the hillside instead of
## ending in a step.

signal changed

enum Mode {
	ADD,       ## strength metres where the shape is white - a mountain, or a canyon when negative
	FLATTEN,   ## the ground becomes the plane
	CUT_DOWN,  ## ground above the plane is cut down to it; ground below is left alone
	FILL_UP,   ## ground below the plane is raised to it; ground above is left alone
}
enum Shape {
	IMAGE,        ## the .r16 in stamp_path
	SOFT_RECT,    ## the whole length x width at full effect, fading out over edge_softness around it
	SOFT_CIRCLE,  ## an ellipse filling length x width at full effect, fading out around it
}

## Editor only: whether the terrain in the editor shows this stamp. Off while you place it -
## only the outline and sheet move, and nothing rebuilds - then tick it to see the result. It
## stays in until ticked off, and editing a ticked stamp unticks it, so the terrain never shows
## a stamp where it used to be. The game applies every stamp either way.
@export var preview := false:
	set(value):
		if preview == value:
			return
		preview = value
		if Engine.is_editor_hint():
			_draw_helpers_if_ready()
			changed.emit()
## The plane the three levelling modes work to is the stamp's own height: raise or lower the
## node with the gizmo to move it.
@export var mode := Mode.ADD:
	set(value):
		mode = value
		_changed()
@export var shape := Shape.IMAGE:
	set(value):
		shape = value
		_changed()
## For Shape.IMAGE. Any square .r16 of 16-bit values, 0 at its border. The images come from
## the "Terrain - Stamp" ComfyUI workflow in D:\code\gan and are raw 16-bit for the same
## reason the island is: Godot's image loader cuts a 16-bit PNG down to 8-bit, and on a 60 m
## mountain 256 steps are 23 cm terraces.
@export_file("*.r16") var stamp_path := "res://world/terrain_stamp/stamps/mountain.r16":
	set(value):
		stamp_path = value
		_load()
		_changed()
## Mode.ADD only: metres added where the shape is white. Negative digs.
@export_range(-200.0, 200.0, 0.5, "suffix:m") var strength := 40.0:
	set(value):
		strength = value
		_changed()
## Metres along the stamp's own X.
@export_range(5.0, 600.0, 1.0, "suffix:m") var length := 120.0:
	set(value):
		length = value
		_changed()
## Metres along the stamp's own Z.
@export_range(5.0, 600.0, 1.0, "suffix:m") var width := 120.0:
	set(value):
		width = value
		_changed()
## For the soft shapes: how far OUTSIDE length x width the effect takes to fade to nothing.
## Outside, not inside: faded inwards, a 6 x 5 m pad under a cannon with the default 12 m of
## softness reached 11% at its very centre and flattened nothing.
@export_range(0.5, 100.0, 0.5, "suffix:m") var edge_softness := 12.0:
	set(value):
		edge_softness = value
		_changed()

const _COLOURS := {
	Mode.ADD: Color(1.0, 0.55, 0.1),
	Mode.FLATTEN: Color(0.3, 0.9, 0.35),
	Mode.CUT_DOWN: Color(1.0, 0.3, 0.25),
	Mode.FILL_UP: Color(0.25, 0.55, 1.0),
}
## An ADD stamp that digs is drawn in the fill colour's blue, so a canyon reads as one before
## the terrain has rebuilt.
const _DIG_COLOUR := Color(0.2, 0.6, 1.0)

var _values := PackedFloat32Array()
var _size := 0
var _outline: MeshInstance3D
var _sheet: MeshInstance3D
## World to stamp space, kept rather than inverted per sample: the terrain asks tens of
## thousands of times per stamp.
var _to_local := Transform3D.IDENTITY


func _init() -> void:
	# Notified so that moving the stamp - including up and down, which moves the plane -
	# rebuilds the ground under it.
	set_notify_transform(true)


func _ready() -> void:
	if _values.is_empty() and shape == Shape.IMAGE:
		_load()
	if Engine.is_editor_hint():
		_draw_helpers()
	elif not _under_terrain():
		# The terrain only reads its own children. One placed beside it instead - which is how
		# the first flatten pad went in, under the scene root - does nothing, and looks fine.
		push_error("TerrainStamp %s is not a child of the Terrain node, so it reshapes nothing"
				% get_path())


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_TRANSFORM_CHANGED:
		_to_local = global_transform.affine_inverse()
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if _under_terrain():
		return PackedStringArray()
	return PackedStringArray(["Not under the Terrain node, so it reshapes nothing. Drag it onto Terrain."])


func _under_terrain() -> bool:
	return get_parent() != null and get_parent().is_in_group(&"terrain")


## The ground height at a world point once this stamp has been applied, both in world metres.
func reshape(height: float, world_x: float, world_z: float) -> float:
	var weight := value_at(world_x, world_z)
	if weight <= 0.0:
		return height
	var plane := global_position.y
	match mode:
		Mode.ADD:
			return height + weight * strength
		Mode.FLATTEN:
			return lerpf(height, plane, weight)
		Mode.CUT_DOWN:
			return lerpf(height, plane, weight) if height > plane else height
		Mode.FILL_UP:
			return lerpf(height, plane, weight) if height < plane else height
	return height


## How much of the effect lands on a world point, 0 outside the footprint.
func value_at(world_x: float, world_z: float) -> float:
	var local := _to_local * Vector3(world_x, global_position.y, world_z)
	var half_l := length * 0.5
	var half_w := width * 0.5
	match shape:
		Shape.SOFT_RECT:
			# metres outside the rectangle, 0 inside it
			var outside := Vector2(maxf(absf(local.x) - half_l, 0.0), maxf(absf(local.z) - half_w, 0.0))
			return 1.0 - smoothstep(0.0, edge_softness, outside.length())
		Shape.SOFT_CIRCLE:
			var r := Vector2(local.x / half_l, local.z / half_w).length()
			# (r - 1) of the shorter radius is metres out past the rim - exact on a circle,
			# close enough on an ellipse
			return 1.0 - smoothstep(0.0, edge_softness, maxf(r - 1.0, 0.0) * minf(half_l, half_w))
	if absf(local.x) >= half_l or absf(local.z) >= half_w:
		return 0.0
	return _sample(local.x / length + 0.5, local.z / width + 0.5)


## The world-space rectangle the stamp can touch, for the terrain to limit its loop to.
func footprint() -> Rect2:
	var basis := global_transform.basis
	# Not normalised: a scaled node samples a scaled stamp, so the footprint grows with it.
	var reach := edge_softness if shape != Shape.IMAGE else 0.0
	var half_x := Vector2(basis.x.x, basis.x.z) * (length * 0.5 + reach)
	var half_z := Vector2(basis.z.x, basis.z.z) * (width * 0.5 + reach)
	var centre := Vector2(global_position.x, global_position.z)
	var rect := Rect2(centre, Vector2.ZERO)
	for corner in [half_x + half_z, half_x - half_z, -half_x + half_z, -half_x - half_z]:
		rect = rect.expand(centre + corner)
	return rect


func _sample(u: float, v: float) -> float:
	if _size == 0:
		return 0.0
	u *= _size - 1
	v *= _size - 1
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, _size - 1)
	var y1 := mini(y0 + 1, _size - 1)
	var fx := u - x0
	var fy := v - y0
	return lerpf(lerpf(_values[y0 * _size + x0], _values[y0 * _size + x1], fx),
			lerpf(_values[y1 * _size + x0], _values[y1 * _size + x1], fx), fy)


func _load() -> void:
	_values = PackedFloat32Array()
	_size = 0
	var file := FileAccess.open(stamp_path, FileAccess.READ)
	if file == null:
		push_error("TerrainStamp %s: cannot open %s" % [name, stamp_path])
		return
	var bytes := file.get_buffer(file.get_length())
	var count := bytes.size() / 2
	var size := int(sqrt(float(count)))
	if size * size != count:
		push_error("TerrainStamp %s: %s is not square (%d samples)" % [name, stamp_path, count])
		return
	_values.resize(count)
	for i in count:
		_values[i] = bytes.decode_u16(i * 2) / 65535.0
	_size = size


## Any edit: the outline follows at once, and a ticked stamp is unticked - which is what
## rebuilds the terrain, taking the stamp out until it is ticked again. Ignored until the node
## is ready: loading the scene assigns every property and transform, and without that guard
## each saved, ticked stamp unticked itself on open.
func _changed() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	_draw_helpers()
	if preview:
		preview = false


func _draw_helpers_if_ready() -> void:
	if is_node_ready():
		_draw_helpers()


## Editor-only helpers, never saved into the scene: the footprint as an outline, and for the
## levelling modes the plane itself as a see-through sheet at the height the ground goes to.
## Ground poking through the sheet is what gets cut; gaps under it are what gets filled.
func _draw_helpers() -> void:
	var colour: Color = _DIG_COLOUR if mode == Mode.ADD and strength < 0.0 else _COLOURS[mode]
	if _outline == null:
		_outline = _helper(&"StampOutline", true)
		_sheet = _helper(&"StampSheet", false)
	(_outline.material_override as StandardMaterial3D).albedo_color = colour
	(_sheet.material_override as StandardMaterial3D).albedo_color = Color(colour, 0.28)

	var rim := _rim(0.0)
	var lines := ImmediateMesh.new()
	# The soft shapes get a second outline where their blend into the ground runs out.
	var loops: Array[PackedVector3Array] = [rim]
	if shape != Shape.IMAGE:
		loops.append(_rim(edge_softness))
	for loop in loops:
		lines.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in loop:
			lines.surface_add_vertex(point)
		lines.surface_add_vertex(loop[0])
		lines.surface_end()
	_outline.mesh = lines

	# Once ticked, the ground itself shows the plane, and a sheet lying in it would only flicker
	# against it.
	_sheet.visible = mode != Mode.ADD and not preview
	var fill := ImmediateMesh.new()
	fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rim.size():
		fill.surface_add_vertex(Vector3.ZERO)
		fill.surface_add_vertex(rim[i])
		fill.surface_add_vertex(rim[(i + 1) % rim.size()])
	fill.surface_end()
	_sheet.mesh = fill


## Found by name before one is made. Saving a script reloads it in the editor and forgets
## _outline, and a fresh outline was then drawn beside the old one - which stayed on screen,
## frozen in whatever colour and size it had, as an orange rectangle round a green pad.
func _helper(helper_name: StringName, on_top: bool) -> MeshInstance3D:
	var existing := get_node_or_null(NodePath(helper_name)) as MeshInstance3D
	if existing != null:
		return existing
	var instance := MeshInstance3D.new()
	instance.name = helper_name
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The outline draws over the terrain so it is never lost; the sheet does not, so that the
	# ground that pokes through it is visible as ground.
	material.no_depth_test = on_top
	if not on_top:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	add_child(instance)
	return instance


## The edge of the footprint in the stamp's own space, pushed out by `margin` metres: the
## rectangle, or the ellipse for Shape.SOFT_CIRCLE.
func _rim(margin: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var half_l := length * 0.5 + margin
	var half_w := width * 0.5 + margin
	if shape == Shape.SOFT_CIRCLE:
		for i in 48:
			var angle := TAU * i / 48.0
			points.append(Vector3(cos(angle) * half_l, 0.0, sin(angle) * half_w))
		return points
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(Vector3(corner.x * half_l, 0.0, corner.y * half_w))
	return points
