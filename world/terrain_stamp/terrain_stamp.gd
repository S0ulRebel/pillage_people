@tool
class_name TerrainStamp
extends Node3D
## Reshapes the island under it: adds a landform, or sets the ground to a shape or a plane.
##
## Put it under the Terrain node, move it with the gizmo and turn it about Y. The terrain reads
## every stamp among its children, top to bottom, before it builds the mesh, the collider and
## the seabed the water sees, so all three follow. The island file itself is never changed -
## delete the stamp and the ground is back.
##
## ONE RULE FOR EVERY STAMP. At each point the shape gives a height, -1 to 1 of `height` metres,
## and a mask, 0 to 1. Add puts ground + shape x height; the other three aim for the stamp's own
## Y + shape x height and take it, cut down to it or fill up to it. Then the mask decides how
## much of that lands: result = mix(ground, blended, mask x opacity). Mask 0 changes nothing,
## which is what makes a pad blend into the hillside instead of ending in a step.
##
## An image (.stamp, see tools/make_stamp.py) carries both: mid-grey is zero height, and its
## second channel is the mask. A soft rectangle or oval is full height everywhere and its mask
## is the fade round its edge - so a Replace pad sits at Y + height, and height 0 puts it at the
## gizmo. It is also cut into the ground mesh along its outline and along the foot of its bank
## (cut_lines), so its edge is drawn where it is and not where the nearest mesh vertices fall.

signal changed

## In the order Flatten, Cut down and Fill up had, which Replace, Min and Max are - a scene
## saves the number, so a pad saved as Cut down loads as Min with nothing to edit.
enum Mode {
	ADD,      ## ground + shape x height: a mountain, or a canyon when the height is negative
	REPLACE,  ## the ground becomes Y + shape x height
	MIN,      ## ground above Y + shape x height is cut down to it; ground below is left alone
	MAX,      ## ground below Y + shape x height is filled up to it; ground above is left alone
}
enum Shape {
	IMAGE,        ## the .stamp in stamp_path
	SOFT_RECT,    ## the whole length x width at full effect, fading out over edge_softness around it
	SOFT_CIRCLE,  ## an ellipse filling length x width at full effect, fading out around it
}

## Editor only: whether the terrain in the editor shows this stamp. Off while you rough it in -
## only the outline and sheet move, and nothing rebuilds - then tick it to see the result. Once
## ticked it stays live: move it or change a setting and the ground follows, since the terrain
## only rebuilds the chunks the stamp touches. Untick a big one if dragging it feels slow. The
## game applies every stamp either way.
@export var preview := false:
	set(value):
		if preview == value:
			return
		preview = value
		if Engine.is_editor_hint():
			_draw_helpers_if_ready()
			changed.emit()
## Replace, Min and Max work to the stamp's own Y plus the shape times `height`: raise or lower
## the node with the gizmo to move that.
@export var mode := Mode.ADD:
	set(value):
		mode = value
		_changed()
@export var shape := Shape.IMAGE:
	set(value):
		shape = value
		_changed()
## For Shape.IMAGE: a .stamp, height and mask per sample - see tools/make_stamp.py, which makes
## one from the "Terrain - Stamp" ComfyUI workflow's output in D:\code\gan. Raw 16-bit for the
## same reason the island is: Godot's image loader cuts a 16-bit PNG down to 8-bit, and on a
## 60 m mountain 256 steps are 23 cm terraces.
@export_file("*.stamp") var stamp_path := "res://world/terrain_stamp/stamps/mountain.stamp":
	set(value):
		stamp_path = value
		_load()
		_changed()
## Metres at full height: what the brightest part of an image adds in Add mode, or how far above
## the stamp's own Y it sits in the other three. Negative digs, or sits below. A soft shape is
## full height all over, so a Replace, Min or Max pad sits this far above the gizmo - 0 for a
## pad at the gizmo's own height; the see-through sheet in the editor shows where it lands.
@export_range(-200.0, 200.0, 0.5, "suffix:m") var height := 40.0:
	set(value):
		height = value
		_changed()
## How much of the stamp lands at all, over the whole of it: 1 is the stamp as drawn, 0 is no
## stamp. Multiplies the image's own mask and the soft shapes' fade.
@export_range(0.0, 1.0, 0.01) var opacity := 1.0:
	set(value):
		opacity = value
		_changed()
## Metres along the stamp's own X.
@export_range(5.0, 600.0, 1.0, "or_greater", "suffix:m") var length := 120.0:
	set(value):
		length = value
		_changed()
## Metres along the stamp's own Z.
@export_range(5.0, 600.0, 1.0, "or_greater", "suffix:m") var width := 120.0:
	set(value):
		width = value
		_changed()
## For the soft shapes: how far OUTSIDE length x width the effect takes to fade to nothing.
## Outside, not inside: faded inwards, a 6 x 5 m pad under a cannon with the default 12 m of
## softness reached 11% at its very centre and flattened nothing.
## The fade is a straight bank from the outline down to the ground, this wide. As sharp as you
## like: the terrain cuts its mesh along the outline and along the foot of the bank
## (Terrain._build_chunk), so a 0.25 m edge is drawn as a real edge rather than wherever the
## nearest mesh vertices land. Straight rather than an S-curve so that the bank the mesh draws
## between those two lines IS the fade, and height_at(), the collider and the picture agree.
@export_range(0.25, 100.0, 0.25, "suffix:m") var edge_softness := 12.0:
	set(value):
		edge_softness = maxf(value, 0.25)
		_changed()
## For Shape.IMAGE: how far INSIDE its own border an image fades out, on top of its mask. 0 is
## off - the image as drawn, which is right when its mask already reaches 0 at the border. For
## one that does not, this is what stops its edge being a step in the ground.
@export_range(0.0, 100.0, 0.25, "suffix:m") var border_fade := 0.0:
	set(value):
		border_fade = maxf(value, 0.0)
		_changed()

const _COLOURS := {
	Mode.ADD: Color(1.0, 0.55, 0.1),
	Mode.REPLACE: Color(0.3, 0.9, 0.35),
	Mode.MIN: Color(1.0, 0.3, 0.25),
	Mode.MAX: Color(0.25, 0.55, 1.0),
}
## An ADD stamp that digs is drawn in the fill colour's blue, so a canyon reads as one before
## the terrain has rebuilt.
const _DIG_COLOUR := Color(0.2, 0.6, 1.0)

## The image, from stamp_path: its height (-1 to 1) and its mask (0 to 1) per sample, row by
## row, `_columns` along the stamp's X and `_rows` along its Z.
var _heights := PackedFloat32Array()
var _masks := PackedFloat32Array()
var _columns := 0
var _rows := 0
var _outline: MeshInstance3D
var _sheet: MeshInstance3D
## World to stamp space, kept rather than inverted per sample: the terrain asks tens of
## thousands of times per stamp.
var _to_local := Transform3D.IDENTITY
## The transform the last edit was reported for. Godot sends a transform-changed notification
## the frame after a node enters the tree, transform and all unchanged; reported as an edit it
## had the terrain redo every ticked stamp's ground a moment after the scene opened.
var _last_transform := Transform3D.IDENTITY


func _init() -> void:
	# Notified so that moving the stamp - including up and down, which moves the plane -
	# rebuilds the ground under it.
	set_notify_transform(true)


func _ready() -> void:
	if _heights.is_empty() and shape == Shape.IMAGE:
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
	if what == NOTIFICATION_ENTER_TREE:
		_last_transform = global_transform
	if what == NOTIFICATION_TRANSFORM_CHANGED and not global_transform.is_equal_approx(_last_transform):
		_last_transform = global_transform
		_changed()
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()


func _get_configuration_warnings() -> PackedStringArray:
	if _under_terrain():
		return PackedStringArray()
	return PackedStringArray(["Not under the Terrain node, so it reshapes nothing. Drag it onto Terrain."])


func _under_terrain() -> bool:
	return get_parent() != null and get_parent().is_in_group(Groups.TERRAIN)


## The ground height at a world point once this stamp has been applied, both in world metres.
func reshape(ground: float, world_x: float, world_z: float) -> float:
	var rise := height
	var weight := opacity
	if shape == Shape.IMAGE:
		var here := _image_at(world_x, world_z)
		rise *= here.x
		weight *= here.y
	else:
		weight *= _fade_at(world_x, world_z)
	return _blend(ground, rise, weight)


## The mode, applied: `rise` is the shape's height in metres here and `weight` how much of it
## lands, mask times opacity.
func _blend(ground: float, rise: float, weight: float) -> float:
	if weight <= 0.0:
		return ground
	if mode == Mode.ADD:
		return ground + weight * rise
	var level := global_position.y + rise
	match mode:
		Mode.REPLACE:
			return lerpf(ground, level, weight)
		Mode.MIN:
			return lerpf(ground, level, weight) if ground > level else ground
		Mode.MAX:
			return lerpf(ground, level, weight) if ground < level else ground
	return ground


## What grid_offset() answers for an image that does not land sample on sample.
const OFF_GRID := Vector2i(-2147483648, -2147483648)


## For a ground grid of samples `spacing` apart with its first at (first, first), which of its
## samples this image's first sample lands on - or OFF_GRID when it lands between them, or is
## turned, scaled or sampled at another spacing. On the grid, each ground sample IS one image
## sample, and reshape_grid() reads it straight.
func grid_offset(spacing: float, first: float) -> Vector2i:
	if shape != Shape.IMAGE or _columns < 2 or _rows < 2 \
			or not global_transform.basis.is_equal_approx(Basis.IDENTITY):
		return OFF_GRID
	if absf(length / (_columns - 1) - spacing) > spacing * 0.000001 \
			or absf(width / (_rows - 1) - spacing) > spacing * 0.000001:
		return OFF_GRID
	var fx := (global_position.x - length * 0.5 - first) / spacing
	var fz := (global_position.z - width * 0.5 - first) / spacing
	if absf(fx - roundf(fx)) > 0.001 or absf(fz - roundf(fz)) > 0.001:
		return OFF_GRID
	return Vector2i(roundi(fx), roundi(fz))


## The image's samples along its X and its Z.
func image_size() -> Vector2i:
	return Vector2i(_columns, _rows)


## reshape() over a block of a ground grid this image lands on sample for sample - see
## grid_offset(), which gives `offset`, the grid sample under the image's first. `heights` is
## the grid, `size` samples a row, each a fraction of `scale` metres above `base`; samples
## gx0..gx1 by gz0..gz1 are reshaped and the grid handed back.
##
## Read straight from the image, with no transform and nothing read between samples, so it is
## exact rather than right to a float's width. And the rule is _blend()'s written out in the
## loop: the island is a million samples, and through reshape() - a transform, a read between
## four samples and two calls each - it took 1.55 s; a call per sample was still 0.68 s.
func reshape_grid(heights: PackedFloat32Array, size: int, offset: Vector2i, gx0: int, gx1: int,
		gz0: int, gz1: int, scale: float, base: float) -> PackedFloat32Array:
	var y := global_position.y
	var step_l := length / (_columns - 1)
	var step_w := width / (_rows - 1)
	var half_l := length * 0.5
	var half_w := width * 0.5
	for gz in range(gz0, gz1 + 1):
		var row := gz * size
		var image_row := (gz - offset.y) * _columns
		var z := (gz - offset.y) * step_w - half_w
		for gx in range(gx0, gx1 + 1):
			var column := gx - offset.x
			var weight := opacity * _masks[image_row + column]
			if border_fade > 0.0:
				var x := column * step_l - half_l
				weight *= clampf(minf(half_l - absf(x), half_w - absf(z)) / border_fade, 0.0, 1.0)
			if weight <= 0.0:
				continue
			var ground := heights[row + gx] * scale + base
			var rise := height * _heights[image_row + column]
			var shaped := ground
			if mode == Mode.ADD:
				shaped = ground + weight * rise
			else:
				var level := y + rise
				if mode == Mode.REPLACE or (mode == Mode.MIN and ground > level) \
						or (mode == Mode.MAX and ground < level):
					shaped = lerpf(ground, level, weight)
			if shaped != ground:
				heights[row + gx] = (shaped - base) / scale
	return heights


## How much of `height` Add would put on a world point: the shape's height times its mask and
## the opacity. 0 outside the footprint.
func value_at(world_x: float, world_z: float) -> float:
	if shape != Shape.IMAGE:
		return _fade_at(world_x, world_z) * opacity
	var here := _image_at(world_x, world_z)
	return here.x * here.y * opacity


## A soft shape's mask: 1 inside its outline, falling to 0 across edge_softness outside it. Its
## height is 1 everywhere, so this is all there is to it. Kept apart from the image's Vector2 -
## whose parts are 32-bit - so that a pad lands exactly where it did before images had masks.
func _fade_at(world_x: float, world_z: float) -> float:
	return 1.0 - clampf(edge_distance(world_x, world_z) / edge_softness, 0.0, 1.0)


## The image at a world point: x is its height, -1 to 1 of `height`, and y its mask, 0 to 1,
## faded inside its border by border_fade. Zero outside it.
func _image_at(world_x: float, world_z: float) -> Vector2:
	var local := _to_local * Vector3(world_x, global_position.y, world_z)
	var half_l := length * 0.5
	var half_w := width * 0.5
	# The edge samples are the image's own: an island as big as the ground has its outermost
	# ring of samples exactly on its border, and left out, the seabed showed through there. A
	# hair's slack, because the point comes through a 32-bit transform.
	if absf(local.x) > half_l + 0.001 or absf(local.z) > half_w + 0.001:
		return Vector2.ZERO
	var here := _sample(local.x / length + 0.5, local.z / width + 0.5)
	if border_fade > 0.0:
		var inside := minf(half_l - absf(local.x), half_w - absf(local.z))
		here.y *= clampf(inside / border_fade, 0.0, 1.0)
	return here


## Whether the shape has an outline the terrain can cut its mesh along. An image has none.
func has_outline() -> bool:
	return shape != Shape.IMAGE


## The kinds of line in cut_lines(), as bits the terrain marks its cells with.
const CUT_CREST := 1
const CUT_FOOT := 2
const CUT_RIDGE := 4


## The lines the terrain cuts its mesh along for this stamp, in the order to cut them, each a
## Dictionary:
## - `bit`: which kind of line. CUT_CREST is the outline, where the flat top meets the bank;
##   CUT_FOOT the foot of the bank, where it meets the ground; CUT_RIDGE a rectangle's corner
##   mitres, where the bank's two facets meet on the corner's diagonal - a triangle laid
##   across that would sag.
## - `field`: a signed function of world x, z, at or below 0 on the near side of the line and
##   above it beyond. The crest and the foot are each ONE line that turns the corners, not four
##   straight sides: a straight side cut wherever it crossed a cell ran on past the corner, and
##   the chunk across a border there, which the pad never reaches, had not cut it.
## - `straight`: whether it is made of straight pieces (a rectangle) or curved (an oval).
## - `probe`: for the straight edge a-b, the fractions along it to look at for the line dipping
##   in and out between two ends both outside it: a rectangle's corner poking into an edge is
##   deepest where the edge crosses the corner's diagonal; an oval is looked at along the
##   edge's length.
## - `corner`: for two points on the line, the corner between them (world x, z) when they lie
##   on two sides of a rectangle that meet, else null. The cut joins a cell's two crossings with
##   a straight edge, and round a corner that edge would chop the corner off.
## An image has no lines. A pad narrower than a mesh cell (1.2 m) is not catered for: its two
## sides can pass through a cell without either touching a corner.
func cut_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if shape == Shape.IMAGE:
		return lines
	var foot := edge_softness
	var straight := shape == Shape.SOFT_RECT
	var probe: Callable = _rect_probe if straight else func(_a: Vector3, _b: Vector3) -> PackedFloat32Array:
		return PackedFloat32Array([0.25, 0.5, 0.75])
	var nothing := func(_p: Vector3, _q: Vector3) -> Variant: return null
	lines.append({"bit": CUT_CREST, "field": edge_distance, "straight": straight, "probe": probe,
			"corner": (func(p: Vector3, q: Vector3) -> Variant: return _rect_corner(p, q, 0.0)) if straight else nothing})
	lines.append({"bit": CUT_FOOT, "field": func(x: float, z: float) -> float: return edge_distance(x, z) - foot,
			"straight": straight, "probe": probe,
			"corner": (func(p: Vector3, q: Vector3) -> Variant: return _rect_corner(p, q, foot)) if straight else nothing})
	if straight:
		var half_l := length * 0.5
		var half_w := width * 0.5
		var y := global_position.y
		lines.append({"bit": CUT_RIDGE, "field": func(x: float, z: float) -> float:
				var local := _to_local * Vector3(x, y, z)
				return (absf(local.x) - half_l) - (absf(local.z) - half_w),
			"straight": true, "probe": func(_a: Vector3, _b: Vector3) -> PackedFloat32Array: return PackedFloat32Array(),
			"corner": nothing})
	return lines


## The same lines' fields, in the same order, at many points at once - the terrain asks for
## the corners of a whole chunk.
func cut_line_values(points: PackedVector2Array) -> Array[PackedFloat32Array]:
	var values: Array[PackedFloat32Array] = []
	if shape == Shape.IMAGE:
		return values
	var crest := PackedFloat32Array()
	var foot := PackedFloat32Array()
	crest.resize(points.size())
	foot.resize(points.size())
	for k in points.size():
		var d := edge_distance(points[k].x, points[k].y)
		crest[k] = d
		foot[k] = d - edge_softness
	values.append(crest)
	values.append(foot)
	if shape == Shape.SOFT_RECT:
		var ridge := PackedFloat32Array()
		ridge.resize(points.size())
		var half_l := length * 0.5
		var half_w := width * 0.5
		var y := global_position.y
		for k in points.size():
			var local := _to_local * Vector3(points[k].x, y, points[k].y)
			ridge[k] = (absf(local.x) - half_l) - (absf(local.z) - half_w)
		values.append(ridge)
	return values


## Which side of the rectangle a point is nearest to, as the direction out through it.
func _rect_side(p: Vector3) -> Vector2i:
	var local := _to_local * Vector3(p.x, global_position.y, p.z)
	var half_l := length * 0.5
	var half_w := width * 0.5
	var sides := [[local.x - half_l, Vector2i(1, 0)], [-local.x - half_l, Vector2i(-1, 0)],
			[local.z - half_w, Vector2i(0, 1)], [-local.z - half_w, Vector2i(0, -1)]]
	var best: Array = sides[0]
	for side in sides:
		if side[0] > best[0]:
			best = side
	return best[1]


## The corner of the outline `iso` out from the rectangle's sides that lies between two points
## on that outline, when they are on two sides that meet; null when they are on the same side
## (the edge between them runs along it) or on opposite sides.
func _rect_corner(p: Vector3, q: Vector3, iso: float) -> Variant:
	var signs := _rect_side(p) + _rect_side(q)
	if signs.x == 0 or signs.y == 0:
		return null
	var world := global_transform * Vector3(signs.x * (length * 0.5 + iso), 0.0, signs.y * (width * 0.5 + iso))
	return Vector2(world.x, world.z)


## Where the straight edge a-b crosses a corner's diagonal, as fractions along it: the deepest
## point of a corner poking into the edge, where the edge passes from one side's reach into
## the other's.
func _rect_probe(a: Vector3, b: Vector3) -> PackedFloat32Array:
	var params := PackedFloat32Array()
	var y := global_position.y
	var la := _to_local * Vector3(a.x, y, a.z)
	var lb := _to_local * Vector3(b.x, y, b.z)
	var half_l := length * 0.5
	var half_w := width * 0.5
	for signs: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var ga: float = (signs.x * la.x - half_l) - (signs.y * la.z - half_w)
		var gb: float = (signs.x * lb.x - half_l) - (signs.y * lb.z - half_w)
		if (ga < 0.0) != (gb < 0.0):
			params.append(ga / (ga - gb))
	return params


## Metres from the shape's outline: negative inside, 0 on it, positive outside. The fade runs
## from 0 to edge_softness of it. The terrain cuts its mesh where this is 0 (the crest of a
## pad) and where it is edge_softness (the foot of the fade), so both are real mesh edges.
func edge_distance(world_x: float, world_z: float) -> float:
	var local := _to_local * Vector3(world_x, global_position.y, world_z)
	var half_l := length * 0.5
	var half_w := width * 0.5
	match shape:
		Shape.SOFT_RECT:
			# How far past the nearest side, so the fade's foot is a larger rectangle and the
			# bank turns each corner as a mitre - straight lines the mesh can be cut along
			# exactly. Rounding the corners instead put a 0.5 m arc across 1.2 m cells, which the
			# cut could not follow, and the corners came out 0.7 m off.
			return maxf(absf(local.x) - half_l, absf(local.z) - half_w)
		Shape.SOFT_CIRCLE:
			# The distance to the ellipse, to first order: (r - 1) over the gradient of r. Exact
			# on a circle, within a few percent on an oval, and measured straight out from the
			# rim rather than along the scaled radius, which ran the fade further along the long
			# axis and put the bank's slope wrong there.
			var scaled := Vector2(local.x / half_l, local.z / half_w)
			var r := scaled.length()
			if r < 0.000001:
				return -minf(half_l, half_w)
			var gradient := Vector2(local.x / (half_l * half_l), local.z / (half_w * half_w)).length() / r
			return (r - 1.0) / maxf(gradient, 0.000001)
	return INF


## The world-space rectangle the stamp can touch, for the terrain to limit its loop to.
func footprint() -> Rect2:
	var basis := global_transform.basis
	# Not normalised: a scaled node samples a scaled stamp, so the footprint grows with it.
	var reach := _fade_reach()
	var half_x := Vector2(basis.x.x, basis.x.z) * (length * 0.5 + reach.x)
	var half_z := Vector2(basis.z.x, basis.z.z) * (width * 0.5 + reach.y)
	var centre := Vector2(global_position.x, global_position.z)
	var rect := Rect2(centre, Vector2.ZERO)
	for corner in [half_x + half_z, half_x - half_z, -half_x + half_z, -half_x - half_z]:
		rect = rect.expand(centre + corner)
	return rect


## How far past length x width the fade reaches, along the stamp's X and Z. The terrain visits
## no sample outside the footprint, so this has to cover the whole fade: it once stopped short
## along an oval's long axis and the last tenth of a dig was never applied, ending the crater
## in a metre-high step. The oval's distance is a first-order estimate, so it gets a margin.
func _fade_reach() -> Vector2:
	match shape:
		Shape.SOFT_RECT:
			return Vector2(edge_softness, edge_softness)
		Shape.SOFT_CIRCLE:
			return Vector2(edge_softness * 1.1 + 0.5, edge_softness * 1.1 + 0.5)
	return Vector2.ZERO


## The image's height and mask at u, v (0 to 1 across it), each read between the four nearest
## samples. Sample 0 is on the image's near edge and the last on its far edge, the way the
## terrain lays out its own height map, so an image the terrain's size lands sample on sample.
func _sample(u: float, v: float) -> Vector2:
	if _columns == 0 or _rows == 0:
		return Vector2.ZERO
	u *= _columns - 1
	v *= _rows - 1
	var x0 := int(u)
	var y0 := int(v)
	var x1 := mini(x0 + 1, _columns - 1)
	var y1 := mini(y0 + 1, _rows - 1)
	var fx := u - x0
	var fy := v - y0
	var a := y0 * _columns
	var b := y1 * _columns
	return Vector2(
			lerpf(lerpf(_heights[a + x0], _heights[a + x1], fx),
					lerpf(_heights[b + x0], _heights[b + x1], fx), fy),
			lerpf(lerpf(_masks[a + x0], _masks[a + x1], fx),
					lerpf(_masks[b + x0], _masks[b + x1], fx), fy))


## Reads stamp_path: a 16-byte header - "STMP", version, columns, rows - then per sample a
## uint16 height, 32768 for zero, and a uint16 mask. tools/make_stamp.py writes it and says why.
func _load() -> void:
	_heights = PackedFloat32Array()
	_masks = PackedFloat32Array()
	_columns = 0
	_rows = 0
	var file := FileAccess.open(stamp_path, FileAccess.READ)
	if file == null:
		push_error("TerrainStamp %s: cannot open %s" % [name, stamp_path])
		return
	var bytes := file.get_buffer(file.get_length())
	if bytes.size() < 16 or bytes.slice(0, 4).get_string_from_ascii() != "STMP":
		push_error("TerrainStamp %s: %s is not a .stamp - an old .r16 converts with"
				% [name, stamp_path] + " tools/make_stamp.py r16")
		return
	var version := bytes.decode_u32(4)
	var columns := bytes.decode_u32(8)
	var rows := bytes.decode_u32(12)
	var count := columns * rows
	if version != 1 or columns < 2 or rows < 2 or bytes.size() < 16 + count * 4:
		push_error("TerrainStamp %s: %s is version %d, %d x %d, %d bytes - not a stamp this reads"
				% [name, stamp_path, version, columns, rows, bytes.size()])
		return
	_heights.resize(count)
	_masks.resize(count)
	for i in count:
		_heights[i] = (bytes.decode_u16(16 + i * 4) - 32768) / 32768.0
		_masks[i] = bytes.decode_u16(18 + i * 4) / 65535.0
	_columns = columns
	_rows = rows


## Any edit: the outline follows at once, and a ticked stamp tells the terrain, which redoes
## the ground it covered and the ground it covers now. Ignored until the node is ready:
## loading the scene assigns every property and transform, and each saved stamp would
## otherwise report an edit on open.
func _changed() -> void:
	if not is_node_ready():
		return
	if Engine.is_editor_hint():
		_draw_helpers()
	if preview or not Engine.is_editor_hint():
		changed.emit()


func _draw_helpers_if_ready() -> void:
	if is_node_ready():
		_draw_helpers()


## Editor-only helpers, never saved into the scene: the footprint as an outline, and for the
## levelling modes the plane itself as a see-through sheet at the height the ground goes to.
## Ground poking through the sheet is what gets cut; gaps under it are what gets filled.
func _draw_helpers() -> void:
	var colour: Color = _DIG_COLOUR if mode == Mode.ADD and height < 0.0 else _COLOURS[mode]
	if _outline == null:
		_outline = _helper(&"StampOutline", true)
		_sheet = _helper(&"StampSheet", false)
	(_outline.material_override as StandardMaterial3D).albedo_color = colour
	(_sheet.material_override as StandardMaterial3D).albedo_color = Color(colour, 0.28)

	var rim := _rim(Vector2.ZERO)
	var lines := ImmediateMesh.new()
	# The soft shapes get a second outline where their blend into the ground runs out.
	var loops: Array[PackedVector3Array] = [rim]
	if shape != Shape.IMAGE:
		loops.append(_rim(_fade_reach()))
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
	# At the level a soft shape takes the ground to, Y + height - not at the gizmo, or a pad
	# with the default 40 m of height would show its sheet 40 m below where it puts the ground.
	# An image's level varies across it; its sheet marks the zero, the stamp's own Y.
	var lift := Vector3.ZERO
	if shape != Shape.IMAGE:
		lift = _to_local * (global_position + Vector3.UP * height)
	var fill := ImmediateMesh.new()
	fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rim.size():
		fill.surface_add_vertex(Vector3(0.0, lift.y, 0.0))
		fill.surface_add_vertex(rim[i] + Vector3(0.0, lift.y, 0.0))
		fill.surface_add_vertex(rim[(i + 1) % rim.size()] + Vector3(0.0, lift.y, 0.0))
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


## The edge of the footprint in the stamp's own space, pushed out by `margin` metres along X
## and Z: the rectangle, or the ellipse for Shape.SOFT_CIRCLE.
func _rim(margin: Vector2) -> PackedVector3Array:
	var points := PackedVector3Array()
	var half_l := length * 0.5 + margin.x
	var half_w := width * 0.5 + margin.y
	if shape == Shape.SOFT_CIRCLE:
		for i in 48:
			var angle := TAU * i / 48.0
			points.append(Vector3(cos(angle) * half_l, 0.0, sin(angle) * half_w))
		return points
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		points.append(Vector3(corner.x * half_l, 0.0, corner.y * half_w))
	return points
