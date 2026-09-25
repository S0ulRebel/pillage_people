@tool
class_name Tunnel
extends Path3D
## A tunnel or cave you place under the Terrain node: draw a curve, pick a cross-section.
##
## The curve decides the kind: two points make a straight cave, points with handles a winding
## one, points without handles a passage with sharp corners. Where the curve is underground the
## section is extruded along it; where it comes up, the tube stops at the surface and the
## terrain is cut to exactly the tube's shape, so the opening always matches, at any slope. An
## end that stays underground is closed off with a rounded cap - a dead end, not a hole into
## nothing. Tunnels that cross open into each other: each one's walls are trimmed where they
## run inside another.
##
## Like a TerrainStamp, it only shows in the editor once Preview is ticked; from then on it
## is live, rebuilt as its curve or settings change. The game builds every tunnel either way.

signal changed

enum Section {
	ROUND,  ## an ellipse, width x height - a bore
	ARCH,   ## flat floor, straight walls, a rounded roof - the natural cave
	SHAFT,  ## flat floor, straight walls, flat roof - a mine
}

## Editor only: whether this tunnel is built, and the terrain cut for it, in the editor. See
## TerrainStamp.preview - same rule, same reason.
@export var preview := false:
	set(value):
		if preview == value:
			return
		preview = value
		if Engine.is_editor_hint() and is_node_ready():
			if not preview:
				clear()
			_draw_guide()
			changed.emit()
@export var section := Section.ARCH:
	set(value):
		section = value
		_edited()
## Metres, wall to wall.
@export_range(1.0, 40.0, 0.1, "suffix:m") var width := 6.0:
	set(value):
		width = value
		_edited()
## Metres, floor to the top of the roof. The curve runs through the middle of the section, so
## the floor is half this below it.
@export_range(1.0, 40.0, 0.1, "suffix:m") var height := 5.0:
	set(value):
		height = value
		_edited()
## Sides on the round parts of the section.
@export_range(6, 48) var ring_segments := 20:
	set(value):
		ring_segments = value
		_edited()
## Distance between sections along the curve.
@export var sample_spacing := 1.5:
	set(value):
		sample_spacing = maxf(value, 0.25)
		_edited()
## How far the tube follows the curve past the surface. It is trimmed to the ground, so this
## only has to be long enough that the cut's end is clear of the terrain.
@export var overshoot := 6.0
## The terrain is cut a little inside the tube wall, so ground and tube overlap rather than
## meeting exactly on the same surface (a seam the player can slip through).
@export var cut_margin := 0.4
@export var light_spacing := 12.0
@export var wall_colour := Color(0.30, 0.27, 0.24)

## Where one tunnel's wall is trimmed against another's, it is kept this far into the other so
## the two overlap instead of meeting on a line that leaves a crack.
const JUNCTION_OVERLAP := 0.05
## Rings in a dead end's rounded cap.
const CAP_RINGS := 4
## A bend sharper than this many degrees at one point of the curve gets a mitred section.
const CORNER_DEGREES := 8.0

## One underground run of the curve, built and cut separately from any other.
class Stretch:
	var centres := PackedVector3Array()
	var forwards := PackedVector3Array()
	## Per centre: the direction a mitred section is stretched along, and by how much. A zero
	## vector where the section is not mitred.
	var bends := PackedVector3Array()
	var stretch := PackedFloat32Array()
	var cap_start := false
	var cap_end := false

var _terrain: Node3D
var _profile := PackedVector2Array()
## Outward edge normals and offsets of the (convex) section: inside where every
## normal.dot(p) - offset is below zero.
var _edge_normals := PackedVector2Array()
var _edge_offsets := PackedFloat32Array()
var _stretches: Array[Stretch] = []
var _others: Array = []
var _bounds := AABB()
## The transform the last edit was reported for. Godot sends a transform-changed notification
## the frame after a node enters the tree, transform and all unchanged; reported as an edit it
## had the terrain rebuild every ticked tunnel a moment after the scene opened.
var _last_transform := Transform3D.IDENTITY
var _guide: MeshInstance3D


func _init() -> void:
	curve_changed.connect(_on_curve_changed)
	# Moving or turning the node moves the tube with it - it is a child - but the terrain only
	# learns of a change through `changed`. Without this, dragging a built tunnel carried the
	# tube off and left the hole where it had been: a slab of ground inside the tube's outline
	# and a hole cut beside it, open to the sky.
	set_notify_transform(true)


func _ready() -> void:
	_on_curve_changed()
	if Engine.is_editor_hint():
		_draw_guide()
	elif not _under_terrain():
		push_error("Tunnel %s is not a child of the Terrain node, so it is never built"
				% get_path())


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()
	if what == NOTIFICATION_ENTER_TREE:
		_last_transform = global_transform
	if what == NOTIFICATION_TRANSFORM_CHANGED and not global_transform.is_equal_approx(_last_transform):
		_last_transform = global_transform
		_edited()


func _get_configuration_warnings() -> PackedStringArray:
	if _under_terrain():
		return PackedStringArray()
	return PackedStringArray(["Not under the Terrain node, so it is never built. Drag it onto Terrain."])


func _under_terrain() -> bool:
	return get_parent() != null and get_parent().is_in_group(&"terrain")


# --- called by the terrain ------------------------------------------------------------------

## First pass: works out where the curve is underground, against the terrain's current
## heights. Every tunnel is prepared before any is built, because building trims each one
## against the others.
func prepare(terrain: Node3D) -> void:
	_terrain = terrain
	clear()
	_profile = _section_profile()
	_edge_normals = PackedVector2Array()
	_edge_offsets = PackedFloat32Array()
	for i in _profile.size():
		var a := _profile[i]
		var b := _profile[(i + 1) % _profile.size()]
		var edge := (b - a).normalized()
		var normal := Vector2(edge.y, -edge.x)   # outward, for a counter-clockwise outline
		_edge_normals.append(normal)
		_edge_offsets.append(normal.dot(a))
	_stretches = _underground_stretches() if curve != null and curve.point_count >= 2 else []
	_bounds = AABB()
	var first := true
	# A mitred section is stretched by up to 3x across the bend, so the box allows for it.
	var reach := 1.5 * Vector2(width, height).length() + cut_margin
	for stretch in _stretches:
		for centre in stretch.centres:
			var box := AABB(centre - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
			_bounds = box if first else _bounds.merge(box)
			first = false
	if _stretches.is_empty():
		push_warning("Tunnel %s never goes underground - nothing to build" % name)


## Second pass: the tube, its collider and its lights. `others` are the other tunnels, already
## prepared, whose insides this one's walls are trimmed out of.
func build(others: Array) -> void:
	_others = others.filter(func(other) -> bool: return other != self and not other.is_empty())
	if _stretches.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for stretch in _stretches:
		_add_stretch(st, stretch)
	st.generate_normals()
	var mesh := st.commit()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TunnelMesh"
	mesh_instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = wall_colour.srgb_to_linear()
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED   # walked on from the inside
	mesh_instance.material_override = material
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "TunnelBody"
	var collider := CollisionShape3D.new()
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	# trimesh shapes ignore back faces by default, and a tube is all back faces from inside
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	add_child(body)

	for stretch in _stretches:
		_add_lights(stretch.centres)
	_draw_guide()


## The ground the tunnel could reach if all of its curve were underground: the curve's extent
## plus the section's reach. The terrain checks this, not bounds(), to decide whether ground
## that moved could change what is built here - bounds() only covers what was underground
## last time, and a curve that ran above a valley floor is buried by a mountain stamped over it.
func curve_footprint() -> Rect2:
	if curve == null or curve.point_count == 0:
		return Rect2()
	var rect := Rect2()
	var first := true
	for point in curve.get_baked_points():
		var world := to_global(point)
		var flat := Vector2(world.x, world.z)
		rect = Rect2(flat, Vector2.ZERO) if first else rect.expand(flat)
		first = false
	return rect.grow(1.5 * Vector2(width, height).length() + cut_margin + overshoot)


## Removes whatever build() made.
func clear() -> void:
	for child in get_children():
		# by name, not by _guide: after a script reload _guide is empty and the old guide is not
		if child.name != &"TunnelGuide":
			remove_child(child)
			child.queue_free()


func is_empty() -> bool:
	return _stretches.is_empty()


## The world-space box the tube can reach, cut margin included. The terrain only asks
## distance_outside() inside it.
func bounds() -> AABB:
	return _bounds


## How far outside the tube a world point is: negative inside. The terrain cuts wherever this
## is below zero, which is the tube's own shape pulled in by cut_margin.
func distance_outside(world_point: Vector3) -> float:
	return _signed_distance(world_point) + cut_margin


# --- the section ----------------------------------------------------------------------------

## The section's outline, counter-clockwise, with the curve at (0, 0): x across, y up.
func _section_profile() -> PackedVector2Array:
	var half_w := width * 0.5
	var half_h := height * 0.5
	var points := PackedVector2Array()
	match section:
		Section.ROUND:
			for s in ring_segments:
				var angle := TAU * s / ring_segments
				points.append(Vector2(cos(angle) * half_w, sin(angle) * half_h))
		Section.SHAFT:
			points = PackedVector2Array([Vector2(-half_w, -half_h), Vector2(half_w, -half_h),
					Vector2(half_w, half_h), Vector2(-half_w, half_h)])
		Section.ARCH:
			# The roof is a half-ellipse as wide as the tunnel, no taller than the whole section;
			# what height is left over becomes straight wall under it.
			var rise := minf(half_w, height)
			var spring := half_h - rise
			points.append(Vector2(-half_w, -half_h))
			points.append(Vector2(half_w, -half_h))
			var steps := maxi(ring_segments / 2, 3)
			for k in steps + 1:
				var angle := PI * k / steps
				var point := Vector2(cos(angle) * half_w, spring + sin(angle) * rise)
				if point.distance_to(points[points.size() - 1]) > 0.001 \
						and point.distance_to(points[0]) > 0.001:
					points.append(point)
	return points


## Signed distance to the section in its own plane: negative inside. Exact inside; outside it
## is the largest edge distance, which can read short near a corner but never has the wrong
## sign - and the sign is all the cut uses.
func _section_distance(p: Vector2) -> float:
	var worst := -1e9
	for i in _edge_normals.size():
		worst = maxf(worst, _edge_normals[i].dot(p) - _edge_offsets[i])
	return worst


## Signed distance to the whole tube: the section swept along each segment of each stretch.
## Each segment is also let run on past its ends by half the section, which fills the wedge on
## the outside of a mitred corner and stands in for a dead end's rounded cap - but not past an
## open end, where there is no tube: a curve starting just above the ground had the terrain cut
## 3 m behind the tube, a hole with nothing under it.
func _signed_distance(world_point: Vector3) -> float:
	var best := 1e9
	var run_on := 0.5 * maxf(width, height)
	for stretch in _stretches:
		var centres := stretch.centres
		var last := centres.size() - 2
		for i in range(centres.size() - 1):
			var a := centres[i]
			var ab := centres[i + 1] - a
			var length := ab.length()
			if length < 0.0001:
				continue
			var forward := ab / length
			var t := (world_point - a).dot(forward)
			var run_back := run_on if i > 0 or stretch.cap_start else 0.0
			var run_ahead := run_on if i < last or stretch.cap_end else 0.0
			var beyond := maxf(-t - run_back, t - length - run_ahead)
			var nearest := a + forward * clampf(t, 0.0, length)
			var frame := _frame(forward)
			var offset := world_point - nearest
			var across := _section_distance(Vector2(offset.dot(frame[0]), offset.dot(frame[1])))
			best = minf(best, maxf(across, beyond))
	return best


## Right and up for a section facing `forward`, taken from world up so the floor stays level
## side to side however the tunnel turns.
func _frame(forward: Vector3) -> Array[Vector3]:
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.95:
		up = Vector3.FORWARD
	var right := forward.cross(up).normalized()
	return [right, right.cross(forward).normalized()]


# --- following the curve --------------------------------------------------------------------

## World positions along the curve, a section every sample_spacing, with every control point
## included exactly - that is what lets a sharp corner be found and mitred rather than having a
## section land a little before it and another a little after.
func _samples() -> Array:
	var offsets: Array[float] = []
	for i in curve.point_count:
		offsets.append(curve.get_closest_offset(curve.get_point_position(i)))
	var samples: Array = []   # of [offset, world position]
	for i in range(offsets.size() - 1):
		var from := offsets[i]
		var to := offsets[i + 1]
		var count := maxi(1, ceili((to - from) / sample_spacing))
		for k in count:
			var offset := lerpf(from, to, float(k) / count)
			samples.append([offset, to_global(curve.sample_baked(offset))])
	samples.append([offsets[-1], to_global(curve.sample_baked(offsets[-1]))])
	return samples


## The curve can dip underground more than once (a tunnel crossing a ridge surfaces in the
## middle). Each underground stretch is built - and cut - separately: joining them would put
## tube over a hilltop and, worse, cut the ground beneath a piece of tube that is up in the air.
func _underground_stretches() -> Array[Stretch]:
	var samples := _samples()
	var length := curve.get_baked_length()
	var runs: Array = []   # each a list of sample indices, plus whether it touches each end
	var current: Array = []
	for i in samples.size():
		var world: Vector3 = samples[i][1]
		# Carry on until the centre reaches the surface: stopping while the whole section is
		# still buried leaves the mouth covered by ground, with no way in.
		if world.y < _terrain.height_at(world.x, world.z):
			current.append(i)
		elif not current.is_empty():
			runs.append(current)
			current = []
	if not current.is_empty():
		runs.append(current)

	var stretches: Array[Stretch] = []
	for run in runs:
		var first: int = run[0]
		var last: int = run[-1]
		var points := PackedVector3Array()
		var stretch := Stretch.new()
		# An end of the curve that is still underground is a dead end and gets a cap. Any other
		# end comes up through the surface: step out past it so the tube starts above ground and
		# overlaps the cut.
		stretch.cap_start = first == 0
		stretch.cap_end = last == samples.size() - 1
		if not stretch.cap_start:
			points.append(to_global(curve.sample_baked(maxf(0.0, samples[first][0] - overshoot))))
		for i in run:
			points.append(samples[i][1])
		if not stretch.cap_end:
			points.append(to_global(curve.sample_baked(minf(length, samples[last][0] + overshoot))))
		_fill_stretch(stretch, _without_repeats(points))
		if stretch.centres.size() >= 2:
			stretches.append(stretch)
	return stretches


func _without_repeats(points: PackedVector3Array) -> PackedVector3Array:
	var kept := PackedVector3Array()
	for point in points:
		if kept.is_empty() or point.distance_to(kept[kept.size() - 1]) > 0.01:
			kept.append(point)
	return kept


## Directions for each section. On a straight run a section faces along it; at a sharp corner
## it faces halfway round and is stretched across the bend - a mitre joint - so the two runs
## meet in one clean seam. Faced along the average of its neighbours instead, the sections
## either side of a corner crossed on the inside of the bend and pinched the wall shut.
func _fill_stretch(stretch: Stretch, centres: PackedVector3Array) -> void:
	stretch.centres = centres
	var count := centres.size()
	for i in count:
		var forward: Vector3
		var bend := Vector3.ZERO
		var factor := 1.0
		if i == 0:
			forward = (centres[1] - centres[0]).normalized()
		elif i == count - 1:
			forward = (centres[i] - centres[i - 1]).normalized()
		else:
			var into := (centres[i] - centres[i - 1]).normalized()
			var out := (centres[i + 1] - centres[i]).normalized()
			forward = (into + out).normalized()
			var angle := into.angle_to(out)
			if angle > deg_to_rad(CORNER_DEGREES):
				bend = (out - into).normalized()
				# 1 / cos(half the bend) keeps the walls parallel through the joint; capped so a
				# near-hairpin does not throw the section out to infinity.
				factor = minf(1.0 / cos(angle * 0.5), 3.0)
		stretch.forwards.append(forward)
		stretch.bends.append(bend)
		stretch.stretch.append(factor)


func _section_at(centre: Vector3, forward: Vector3, bend: Vector3, factor: float,
		scale: float) -> Array[Vector3]:
	var frame := _frame(forward)
	var ring: Array[Vector3] = []
	for point in _profile:
		var offset := (frame[0] * point.x + frame[1] * point.y) * scale
		if bend != Vector3.ZERO:
			offset += bend * offset.dot(bend) * (factor - 1.0)
		ring.append(centre + offset)
	return ring


# --- the mesh -------------------------------------------------------------------------------

func _add_stretch(st: SurfaceTool, stretch: Stretch) -> void:
	var rings: Array = []
	var count := stretch.centres.size()
	if stretch.cap_start:
		rings.append_array(_cap(stretch.centres[0], -stretch.forwards[0], true))
	for i in count:
		rings.append(_section_at(stretch.centres[i], stretch.forwards[i], stretch.bends[i],
				stretch.stretch[i], 1.0))
	if stretch.cap_end:
		rings.append_array(_cap(stretch.centres[count - 1], stretch.forwards[count - 1], false))
	for i in range(rings.size() - 1):
		_join(st, rings[i], rings[i + 1])


## A rounded end: the section shrinks to a point over half the tunnel's width. Returned in the
## order the tube runs, so a cap at the start comes back tip first.
func _cap(centre: Vector3, outward: Vector3, at_start: bool) -> Array:
	var rings: Array = []
	var depth := width * 0.5
	for k in range(1, CAP_RINGS + 1):
		var t := float(k) / CAP_RINGS
		var at := centre + outward * depth * t
		if k == CAP_RINGS:
			rings.append([at] as Array[Vector3])
		else:
			rings.append(_section_at(at, outward if not at_start else -outward, Vector3.ZERO, 1.0,
					sqrt(1.0 - t * t)))
	if at_start:
		rings.reverse()
	return rings


## Faces between two consecutive sections. A single-point ring is a cap's tip, joined as a fan.
func _join(st: SurfaceTool, a: Array, b: Array) -> void:
	if a.size() == 1 or b.size() == 1:
		var tip: Vector3 = a[0] if a.size() == 1 else b[0]
		var ring: Array = b if a.size() == 1 else a
		for s in ring.size():
			_add_clipped(st, [ring[s], tip, ring[(s + 1) % ring.size()]])
		return
	for s in a.size():
		var s2 := (s + 1) % a.size()
		_add_clipped(st, [a[s], b[s], b[s2]])
		_add_clipped(st, [a[s], b[s2], a[s2]])


## Adds a triangle, keeping only the part that is below the terrain and outside every other
## tunnel. Against the ground this shapes the mouth: the tube ends exactly where it meets the
## surface, on the same curve the terrain is cut along. Against another tunnel it opens the
## junction, so two passages that cross become one instead of two walled pipes.
func _add_clipped(st: SurfaceTool, triangle: Array) -> void:
	var polygon: Array[Vector3] = []
	for i in 3:
		var current: Vector3 = triangle[i]
		var next: Vector3 = triangle[(i + 1) % 3]
		var keep_current := _keep(current)
		var keep_next := _keep(next)
		if keep_current >= 0.0:
			polygon.append(current)
		if (keep_current >= 0.0) != (keep_next >= 0.0):
			polygon.append(_crossing(current, next, keep_current))
	if polygon.size() < 3:
		return
	for i in range(1, polygon.size() - 1):
		for p: Vector3 in [polygon[0], polygon[i], polygon[i + 1]]:
			st.add_vertex(to_local(p))


## Positive where the wall is kept: below ground, and outside every other tunnel.
func _keep(world_point: Vector3) -> float:
	var keep: float = _terrain.height_at(world_point.x, world_point.z) - world_point.y
	for other in _others:
		if other.bounds().has_point(world_point):
			keep = minf(keep, other._signed_distance(world_point) + JUNCTION_OVERLAP)
	return keep


## Where a segment crosses from kept to cut. Neither the ground nor another tube is flat, so a
## linear guess is tightened by bisection.
func _crossing(a: Vector3, b: Vector3, keep_a: float) -> Vector3:
	var low := 0.0
	var high := 1.0
	for i in 12:
		var t := (low + high) * 0.5
		if (_keep(a.lerp(b, t)) >= 0.0) == (keep_a >= 0.0):
			low = t
		else:
			high = t
	return a.lerp(b, (low + high) * 0.5)


func _add_lights(centres: PackedVector3Array) -> void:
	var walked := light_spacing
	for i in range(1, centres.size()):
		walked += centres[i].distance_to(centres[i - 1])
		if walked >= light_spacing:
			walked = 0.0
			var light := OmniLight3D.new()
			light.position = to_local(centres[i]) + Vector3.UP * (height * 0.2)
			light.light_color = Color(1.0, 0.86, 0.66)
			light.light_energy = 2.5
			light.omni_range = maxf(width, height) * 2.0
			add_child(light)


# --- editing --------------------------------------------------------------------------------

func _on_curve_changed() -> void:
	if curve != null and not curve.changed.is_connected(_edited):
		curve.changed.connect(_edited)
	_edited()


## Any edit: an unticked tunnel redraws its guide; a ticked one tells the terrain, which
## rebuilds the tube and the ground around where it was and where it is. Ignored until ready,
## as for TerrainStamp: loading the scene assigns every property.
func _edited() -> void:
	if not is_node_ready():
		return
	if not Engine.is_editor_hint() or preview:
		changed.emit()
	else:
		_draw_guide()


## Editor only, never saved: the section drawn every few metres along the whole curve, so an
## unticked tunnel shows its size and path before anything is built. Hidden once ticked, when
## the tube itself is there to see.
func _draw_guide() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _guide == null:
		_guide = get_node_or_null(^"TunnelGuide") as MeshInstance3D
	if _guide == null:
		_guide = MeshInstance3D.new()
		_guide.name = "TunnelGuide"
		_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color(0.95, 0.75, 0.3)
		_guide.material_override = material
		add_child(_guide)
	_guide.visible = not preview
	if preview or curve == null or curve.point_count < 2:
		return
	_profile = _section_profile()
	var samples := _samples()
	var centres := PackedVector3Array()
	for sample in samples:
		centres.append(sample[1])
	var shape := Stretch.new()
	_fill_stretch(shape, _without_repeats(centres))
	# One surface of loose line pairs rather than a strip per ring: a mesh holds at most 256
	# surfaces, and a long tunnel has more rings than that.
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var every := maxi(1, roundi(4.0 / sample_spacing))
	for i in shape.centres.size():
		var mitred := shape.bends[i] != Vector3.ZERO
		if i % every != 0 and i != shape.centres.size() - 1 and not mitred:
			continue
		var ring := _section_at(shape.centres[i], shape.forwards[i], shape.bends[i],
				shape.stretch[i], 1.0)
		for s in ring.size():
			lines.surface_add_vertex(to_local(ring[s]))
			lines.surface_add_vertex(to_local(ring[(s + 1) % ring.size()]))
	lines.surface_end()
	_guide.mesh = lines
