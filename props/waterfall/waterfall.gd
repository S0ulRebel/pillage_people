@tool
class_name Waterfall
extends Path3D
## A waterfall you place in the scene: draw a curve down the rock, set a width, done.
##
## Built the same way tunnel.gd is - a @tool Path3D that rebuilds as you drag the curve - so
## hanging one on a cliff feels like placing a tunnel. Where the tunnel extrudes a tube, this
## extrudes a sheet, and the curve is what lets a fall bow out from the face, kink over a
## ledge, or drop dead straight.
##
## **End the curve on the water.** Its last point is where the splash, the mist and the foam
## ring go, so it wants to sit on the pool's surface - not on the bed under it, where the foam
## would be drawn under the water, and not above it, where it would float.
##
## What it builds, in the layers stylised games use for this (Zelda, RiME, A Short Hike):
##
##   Body      the column itself: a sheet bowed out into a shallow half-pipe so it has volume
##             from the side, with toon streaks running down it (waterfall.gdshader).
##   Veil      a second, wider sheet just in front, drawing only the brightest streaks. It
##             moves faster than the body, and the two sliding past each other is what makes
##             it read as water falling rather than a picture of water.
##   Splash    chunky white puffs thrown up where it lands (splash.gdshader), plus a few at the
##             lip where it breaks over.
##   Mist      a handful of big soft puffs hanging round the foot, in front of the lower fall.
##   Foam      rings spreading out across the pool from where the water lands
##             (pool_foam.gdshader).
##
## There is no collision. You walk through it, which is the point: the plan is caves behind.

const SHEET_SHADER := "res://props/waterfall/waterfall.gdshader"
const SPLASH_SHADER := "res://props/waterfall/splash.gdshader"
const FOAM_SHADER := "res://props/waterfall/pool_foam.gdshader"

@export var width := 2.4:
	set(value):
		width = maxf(value, 0.05)
		_queue()
## Falls fan out on the way down. 1.0 keeps it parallel-sided.
@export var spread := 1.55:
	set(value):
		spread = maxf(value, 0.05)
		_queue()
## Distance between cross-sections along the curve - world/tunnel.gd's own name for the same idea.
@export var sample_spacing := 0.7:
	set(value):
		sample_spacing = maxf(value, 0.1)
		_queue()
## How far the sheet bows out from the rock, as a fraction of its half-width. A flat ribbon
## vanishes side on; a quarter of the half-width is enough to keep a column there.
@export_range(0.0, 1.0) var bulge := 0.28:
	set(value):
		bulge = value
		_queue()
## The body alone, or the body with the veil in front of it. The veil costs one more sheet of
## overdraw and is most of why it moves like water.
@export_range(1, 2) var sheets := 2:
	set(value):
		sheets = clampi(value, 1, 2)
		_queue()
## How far in front of the body the veil sits, in metres.
@export var sheet_gap := 0.18:
	set(value):
		sheet_gap = value
		_queue()

@export_group("Look")
## The mid tone of the streaks. The shader derives the darker and lighter bands from it. It
## is lit, so this is darker than it looks on screen: by day it comes out near the art's
## (0.46, 0.67, 0.85).
@export var water_colour := Color(0.26, 0.42, 0.60):
	set(value):
		water_colour = value
		_queue()
## Metres per second. Real falling water is faster than this; it is tuned to read rather than
## to be right.
@export var speed := 7.0:
	set(value):
		speed = value
		_queue()

@export_group("Where it lands")
## White puffs thrown up at the foot, and a few spitting off the lip.
@export var splash := true:
	set(value):
		splash = value
		_queue()
@export var mist := true:
	set(value):
		mist = value
		_queue()
## Rings of foam spreading across the pool. Off for a fall that lands on rock.
@export var pool_foam := true:
	set(value):
		pool_foam = value
		_queue()
## How far the foam reaches across the pool, as a multiple of the width where the water lands.
@export_range(0.5, 4.0) var foam_reach := 1.6:
	set(value):
		foam_reach = value
		_queue()

var _queued := false
## The curve's baked length, handed to the shader so streaks come out the same size on a five
## metre fall and a fifty metre one.
var _length := 10.0


func _ready() -> void:
	if curve == null:
		curve = Curve3D.new()
	# A stable frame along the curve. Crossing the tangent with world up is the obvious way to
	# work out which direction is "sideways" for a ribbon, and it collapses to nothing when the
	# curve runs vertically - which for a waterfall is always. Godot's own up vectors do not
	# have that problem, and they let a curve point be tilted to twist the sheet at the lip.
	# Only assigned when it is actually wrong - see _watch_curve for why that matters.
	if not curve.up_vector_enabled:
		curve.up_vector_enabled = true
	# Dragging a curve point changes a resource, which goes nowhere near the setters above. So
	# the first version rebuilt for every export and stayed put for the one edit anybody
	# actually makes. Path3D re-emits the curve's own changed signal as curve_changed; both are
	# watched, because replacing the whole curve fires only the first and editing a point in
	# older builds fires only the second.
	if not curve_changed.is_connected(_on_curve_changed):
		curve_changed.connect(_on_curve_changed)
	_watch_curve()
	rebuild()


func _on_curve_changed() -> void:
	# The resource itself may have been swapped, so the watch is re-established before queuing.
	_watch_curve()
	_queue()


func _watch_curve() -> void:
	if curve == null:
		return
	# Guarded, and it has to be. Assigning this mutates the curve even when the value is
	# already what it was, the curve emits changed, Path3D re-emits curve_changed, and this
	# runs again - a stack overflow reached through three signals and one harmless-looking
	# assignment.
	if not curve.up_vector_enabled:
		curve.up_vector_enabled = true
	if not curve.changed.is_connected(_queue):
		curve.changed.connect(_queue)


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

	var steps := maxi(2, int(ceilf(length / sample_spacing)))
	_length = length
	var out := _outward()
	for sheet in sheets:
		# The veil is pushed out in front and made a little wider, so its ragged edges stand
		# proud of the body's instead of lining up with them.
		var push := float(sheet) * sheet_gap
		var surface := _build_sheet(steps, length, push, 1.0 + float(sheet) * 0.10, out)
		var instance := MeshInstance3D.new()
		instance.name = "Body" if sheet == 0 else "Veil"
		instance.mesh = surface
		instance.material_override = _sheet_material(sheet)
		# A transparent sheet casts a solid shadow in Godot - a dark slab on the rock the whole
		# height of the fall.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Deliberately NOT on layer 20. The ocean's overhead camera reads that layer to mask
		# its foam band, and a waterfall hanging over the water would stamp a hole in the band
		# the whole length of the fall.
		instance.layers = 1
		_adopt(instance)

	var foot := curve.sample_baked(length)
	var landing := _frame_at(length, out)
	var foot_width := width * spread
	if pool_foam:
		_add_foam(foot, landing, foot_width)
	if splash:
		_add_splash(foot, landing, foot_width)
		_add_lip_spray(_frame_at(0.0, out))
	if mist:
		_add_mist(foot, landing, foot_width)


## Which way is "out from the rock". The curve's own up vector points to one face of the sheet
## or the other depending on how it was drawn, and the bulge, the veil and the splash all have
## to go the way the water is leaving the cliff. A fall that leaps out has a horizontal run
## from lip to foot, and that run IS the answer; a dead-straight drop has none, and then the
## up vector is all there is.
func _outward() -> Vector3:
	var lip := curve.sample_baked(0.0)
	var foot := curve.sample_baked(curve.get_baked_length())
	var run := Vector3(foot.x - lip.x, 0.0, foot.z - lip.z)
	if run.length() > 0.5:
		return run.normalized()
	return Vector3.ZERO


## Tangent, sideways and outward at a distance along the curve, as a Basis: x sideways, y the
## way the water is going, z out from the rock.
func _frame_at(distance: float, out: Vector3) -> Basis:
	var length := curve.get_baked_length()
	var up := curve.sample_baked_up_vector(distance, true)
	var ahead := curve.sample_baked(minf(distance + 0.1, length))
	var behind := curve.sample_baked(maxf(distance - 0.1, 0.0))
	var tangent := ahead - behind
	if tangent.length() < 0.0001:
		tangent = Vector3.DOWN
	tangent = tangent.normalized()
	var side := tangent.cross(up)
	if side.length() < 0.0001:
		side = tangent.cross(Vector3.FORWARD)
	side = side.normalized()
	var face := side.cross(tangent).normalized()
	if out != Vector3.ZERO and face.dot(out) < 0.0:
		face = -face
		side = -side
	return Basis(side, tangent, face)


## One sheet along the curve, widening as it falls and bowed out into a shallow half-pipe.
##
## UV runs 0..1 across and 0..1 down. UV2 carries the two lengths the shader needs in metres,
## because it cannot recover them: x is the distance to the nearer edge, which is what the
## ragged sides are eaten back from, and y is the distance down from the lip.
func _build_sheet(steps: int, length: float, push: float, widen: float, out: Vector3) -> ArrayMesh:
	var across := 8
	var tool_mesh := SurfaceTool.new()
	tool_mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[PackedVector3Array] = []
	var edges := PackedFloat32Array()
	for i in steps + 1:
		var along := float(i) / float(steps)
		var distance := along * length
		var point := curve.sample_baked(distance)
		var frame := _frame_at(distance, out)
		var half := width * lerpf(1.0, spread, along) * 0.5 * widen
		var row := PackedVector3Array()
		for j in across + 1:
			var x := float(j) / float(across) * 2.0 - 1.0
			var bow := (1.0 - x * x) * bulge * half
			row.append(point + frame.x * (x * half) + frame.z * (bow + push))
		rows.append(row)
		edges.append(half * 2.0)

	for i in steps:
		var v0 := float(i) / float(steps)
		var v1 := float(i + 1) / float(steps)
		for j in across:
			var u0 := float(j) / float(across)
			var u1 := float(j + 1) / float(across)
			var corners := [
				[rows[i][j], u0, v0, edges[i]], [rows[i][j + 1], u1, v0, edges[i]],
				[rows[i + 1][j + 1], u1, v1, edges[i + 1]], [rows[i + 1][j], u0, v1, edges[i + 1]],
			]
			# Clockwise seen from outside, which is Godot's front face, so the normals point
			# out of the rock and toward whoever is looking at the fall.
			for k in [0, 2, 1, 0, 3, 2]:
				var c: Array = corners[k]
				var u: float = c[1]
				var v: float = c[2]
				tool_mesh.set_uv(Vector2(u, v))
				tool_mesh.set_uv2(Vector2((0.5 - absf(u - 0.5)) * float(c[3]), v * length))
				tool_mesh.add_vertex(c[0])
	tool_mesh.generate_normals()
	return tool_mesh.commit()


func _sheet_material(sheet: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SHEET_SHADER)
	material.set_shader_parameter("water_colour", water_colour)
	material.set_shader_parameter("fall_length", _length)
	# Each sheet runs at its own rate, or the two move as one object and the second sheet buys
	# nothing but overdraw.
	material.set_shader_parameter("speed", speed * (1.0 + float(sheet) * 0.35))
	# The veil's streaks finer than the body's, so the two do not beat against each other.
	material.set_shader_parameter("streaks", 10.0 if sheet == 0 else 15.0)
	material.set_shader_parameter("veil", float(sheet))
	# A different stretch of the noise on each, so the veil's streaks are not the body's.
	material.set_shader_parameter("seed", float(sheet) * 17.3)
	return material


## The flat foam disc on the pool, stretched along the line the water lands on.
func _add_foam(foot: Vector3, landing: Basis, foot_width: float) -> void:
	var reach := foot_width * foam_reach
	var plane := PlaneMesh.new()
	plane.size = Vector2(foot_width + reach * 2.0, reach * 2.0)
	var disc := MeshInstance3D.new()
	disc.name = "Foam"
	disc.mesh = plane
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Level, whatever angle the water arrives at, and turned so its long side runs along the
	# width of the fall. A hair above the surface, or the waves' troughs would have it flicker.
	disc.basis = _level(landing)
	disc.position = foot + Vector3.UP * 0.04
	var material := ShaderMaterial.new()
	material.shader = load(FOAM_SHADER)
	material.set_shader_parameter("half_width", foot_width * 0.5)
	material.set_shader_parameter("reach", reach)
	material.set_shader_parameter("size", plane.size)
	# After the sea, which is also transparent and would otherwise sort in front of it.
	material.render_priority = 1
	disc.material_override = material
	_adopt(disc)


## Chunky white puffs thrown up where the water hits: the crown every reference sheet draws
## at the foot of a fall.
func _add_splash(foot: Vector3, landing: Basis, foot_width: float) -> void:
	var size := clampf(foot_width / 5.0, 0.4, 3.0)
	var burst := _emitter("Splash", 56, 1.1, _puff_material(1.0, 0.0))
	burst.basis = _level(landing)
	burst.position = foot
	var process := burst.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(foot_width * 0.42, 0.1, 0.5 * size)
	process.direction = Vector3(0.0, 1.0, 0.25)
	process.spread = 32.0
	process.initial_velocity_min = 2.5 * size
	process.initial_velocity_max = 6.5 * size
	process.gravity = Vector3(0.0, -9.8, 0.0)
	process.scale_min = 0.8 * size
	process.scale_max = 1.9 * size
	process.scale_curve = _swell(0.5, 0.25)
	burst.visibility_aabb = AABB(Vector3(-foot_width, -1.0, -foot_width),
			Vector3(foot_width * 2.0, 6.0 * size + 2.0, foot_width * 2.0))


## A few small puffs where the water breaks over the lip, dropping with it.
func _add_lip_spray(lip: Basis) -> void:
	var spray := _emitter("LipSpray", 14, 1.4, _puff_material(1.0, 0.0))
	spray.basis = _level(lip)
	spray.position = curve.sample_baked(0.0)
	var process := spray.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(width * 0.45, 0.1, 0.1)
	process.direction = Vector3(0.0, -0.3, 1.0)
	process.spread = 20.0
	process.initial_velocity_min = 1.0
	process.initial_velocity_max = 2.5
	process.gravity = Vector3(0.0, -6.0, 0.0)
	process.scale_min = 0.12 * width / 2.4
	process.scale_max = 0.30 * width / 2.4
	process.scale_curve = _swell(0.3, 0.0)
	spray.visibility_aabb = AABB(Vector3(-width, -8.0, -2.0), Vector3(width * 2.0, 9.0, 6.0))


## Big soft puffs round the foot, drifting up and out. Few and large: every one is a
## screen-sized sheet of blending when the captain walks into it.
func _add_mist(foot: Vector3, landing: Basis, foot_width: float) -> void:
	var cloud := _emitter("Mist", 12, 4.0, _puff_material(0.35, 1.2, 0.35))
	cloud.basis = _level(landing)
	cloud.position = foot + Vector3.UP * 1.5
	var process := cloud.process_material as ParticleProcessMaterial
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(foot_width * 0.5, 1.2, 1.0)
	process.direction = Vector3(0.0, 0.6, 1.0)
	process.spread = 40.0
	process.initial_velocity_min = 0.4
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0.0, 0.15, 0.0)
	process.damping_min = 0.2
	process.damping_max = 0.4
	process.scale_min = foot_width * 0.55
	process.scale_max = foot_width * 0.95
	process.scale_curve = _swell(0.35, 0.6)
	cloud.visibility_aabb = AABB(Vector3(-foot_width * 1.5, -3.0, -foot_width),
			Vector3(foot_width * 3.0, foot_width * 2.0 + 4.0, foot_width * 3.0))


func _emitter(named: String, amount: int, lifetime: float, material: ShaderMaterial) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = named
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.5
	particles.local_coords = false
	# Nearest last, so the puffs in front are the ones that show.
	particles.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Already running when the scene opens, not starting from nothing in front of the player.
	particles.preprocess = lifetime
	var process := ParticleProcessMaterial.new()
	# The shader reads the particle's spin as its seed, so every puff is a different shape.
	process.angle_min = 0.0
	process.angle_max = 360.0
	particles.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = material
	particles.draw_pass_1 = quad
	_adopt(particles)
	return particles


func _puff_material(opacity: float, soft_contact: float, softness := 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(SPLASH_SHADER)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("soft_contact", soft_contact)
	material.set_shader_parameter("softness", softness)
	return material


## Grows fast, holds, then shrinks away to `end` of its size.
func _swell(peak_at: float, end: float) -> CurveTexture:
	var shape := Curve.new()
	shape.add_point(Vector2(0.0, 0.3))
	shape.add_point(Vector2(peak_at, 1.0))
	shape.add_point(Vector2(1.0, end))
	var texture := CurveTexture.new()
	texture.curve = shape
	return texture


## The same frame with its sideways axis laid level and "up" pointing up, for the emitters:
## particles thrown upward from a fall that lands at an angle still go up.
func _level(frame: Basis) -> Basis:
	var out := Vector3(frame.z.x, 0.0, frame.z.z)
	if out.length() < 0.001:
		out = Vector3.BACK
	out = out.normalized()
	return Basis(Vector3.UP.cross(out), Vector3.UP, out)


func _adopt(node: Node) -> void:
	add_child(node)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		node.owner = get_tree().edited_scene_root
