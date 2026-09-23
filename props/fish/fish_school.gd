class_name FishSchool
extends MultiMeshInstance3D
## A school of fish that swims as a school, in one draw call.
##
## Three parts, and they are separable:
##
##   - the LOOK is props/fish/fish.gdshader, four stacked motions in the vertex shader
##   - the BEHAVIOUR is here: boids, after Reynolds 1986 - separation, alignment, cohesion
##   - the COST is kept down by a spatial hash, below
##
## Why a MultiMesh and a vertex shader rather than a node and an AnimationPlayer per fish: a
## hundred fish as a hundred nodes is a hundred things to cull, a hundred draw calls and a
## hundred poses a frame, and it buys nothing, because nobody ever looks at a single fish in a
## school. This way the whole school is one node and one draw call, and the fish are numbers in
## a handful of packed arrays.
##
## THE SPATIAL HASH. The naive loop is every fish against every other fish, which is n squared:
## at 200 fish that is 40,000 distance checks a frame, and GDScript will not do that at 60 Hz.
## But a fish does not care about a fish forty metres away, only about its neighbours. So the
## water is cut into cells one perception-radius across, each fish is dropped into a cell, and
## it only ever looks at its own cell and the 26 around it. The cost stops growing with the size
## of the school and starts growing with how tightly packed it is, which separation bounds.
##
## The buckets are a linked list over two packed arrays rather than a dictionary of arrays:
## `_head` maps a cell to the first fish in it and `_next` chains to the rest. An array per cell
## would allocate hundreds of small arrays every frame, and that shows up as stutter long before
## the arithmetic does.
##
## WHAT DRIVES THE ANIMATION. Not speed - acceleration. A fish moving fast and steadily is
## gliding and barely moves its tail; a fish changing direction is working hard even if it is
## slow. Driving the swim from velocity gives a school that looks busiest while cruising in a
## straight line, which is exactly backwards. Angular effort counts too, and it feeds back into
## forward speed, because a fish that throws its tail sideways to turn also shoves itself along.

const MODEL := "res://art/models/fish_blue.glb"
const SHADER := "res://props/fish/fish.gdshader"

@export var count := 140

@export_group("Shape of the school")
## How far a fish looks for its neighbours, in metres. This is also the hash cell size, so
## raising it costs more than it looks - the cells grow with it and each one holds more fish.
@export var perception := 3.2
## Inside this, a fish actively pushes away. Above about half of `perception` the school cannot
## hold together at all, because every neighbour it can see is also one it is fleeing.
@export var personal_space := 0.85
@export var weight_separation := 1.7
@export var weight_alignment := 0.85
@export var weight_cohesion := 0.55
## Pull toward the school's wandering target.
@export var weight_target := 0.5

@export_group("Swimming")
@export var cruise := 2.4
@export var speed_max := 5.5
## Radians per second the fish can turn at most.
@export var turn_max := 3.0
## How much of the effort of turning also drives the fish forward. This is the fix for a fish
## that turns while looking limp: when it whips its tail over to change direction, that push has
## to go somewhere.
@export_range(0.0, 1.0) var turn_drives_speed := 0.45
## Tail beats per second, gliding and working flat out.
@export var beat_calm := 1.1
@export var beat_hard := 4.2

@export_group("Where it lives")
## Radius of the water the school stays inside, around the point handed to setup().
@export var home_radius := 26.0
## Metres of clearance kept under the surface and over the seabed.
@export var below_surface := 1.2
@export var above_bed := 0.7
## A fish this close to a predator drops everything and leaves.
@export var flee_range := 9.0
@export var weight_flee := 4.0

## How often a fish re-checks the seabed under itself, in frames. Sampling the terrain for every
## fish every frame is by a wide margin the most expensive thing in here, and the seabed does
## not move, so the checks are spread out and staggered by index.
const BED_EVERY := 12

## How often a fish looks around it, in frames - so at 60 Hz, twenty times a second.
##
## Finding the neighbours is the whole cost of a school, and it is wasted work at 60 Hz: a fish
## can only turn `turn_max` radians a second, so a new heading takes a good fraction of a second
## to carry out and re-deciding it every 16 ms changes nothing anyone can see. The fish are
## staggered by index, so a third of them look around on any given frame and the cost is flat
## rather than spiking every third one.
const THINK_EVERY := 3

var _pos := PackedVector3Array()
var _dir := PackedVector3Array()
var _speed := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _lit := PackedFloat32Array()
var _bed := PackedFloat32Array()
## The heading each fish is currently turning toward, and how frightened it was when it last
## looked. Both are set on a fish's think frame and used on every frame in between.
var _want := PackedVector3Array()
var _scare := PackedFloat32Array()

var _head := {}
var _next := PackedInt32Array()

var _home := Vector3.ZERO
var _target := Vector3.ZERO
var _centre := Vector3.ZERO
var _sea := 0.0
var _body_half := 0.175
var _frame := 0
var _rng := RandomNumberGenerator.new()

## Set by main.gd. Anything with a global_position that the fish should run from.
var predators: Array[Node3D] = []
var terrain: Node3D = null


## `around` is the middle of the water the school will live in. Returns false if the model or
## the shader would not load, so the caller can drop the node rather than keep an empty one.
func setup(around: Vector3, sea_level: float, seed_value: int = 0) -> bool:
	_home = around
	_target = around
	_centre = around
	_sea = sea_level
	_rng.seed = seed_value if seed_value != 0 else hash(around)
	if not _build_mesh():
		return false
	_populate()
	return true


func fish_count() -> int:
	return _pos.size()


## The measured half-length of the model, in metres. The shader needs it to know where the tail
## is; the test uses it to check the model is the size the game thinks it is.
func body_half() -> float:
	return _body_half


## Where the school is, for whatever wants to point a camera or a shark at it.
func centre() -> Vector3:
	return _centre


func _build_mesh() -> bool:
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_warning("fish school: cannot load %s" % MODEL)
		return false
	var root := packed.instantiate()
	var found: MeshInstance3D = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		found = node as MeshInstance3D
		break
	if found == null or found.mesh == null:
		root.queue_free()
		push_warning("fish school: no mesh in %s" % MODEL)
		return false

	# Measured off the asset, not written down. The model carries its own length, because
	# tools/reorient_model.py bakes the scale into the .glb - so re-baking it at another size
	# moves the bend with it instead of leaving the tail in the wrong place.
	var box: AABB = found.mesh.get_aabb()
	_body_half = maxf(box.size.z * 0.5, 0.001)

	var shader := load(SHADER) as Shader
	if shader == null:
		root.queue_free()
		return false
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("body_half", _body_half)
	# The model's own texture, carried across so the fish is not flat grey. The imported
	# material is a StandardMaterial3D and all that is wanted off it is the albedo map.
	var source := found.mesh.surface_get_material(0) as BaseMaterial3D
	if source != null and source.albedo_texture != null:
		material.set_shader_parameter("albedo_texture", source.albedo_texture)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = found.mesh
	mm.instance_count = count
	multimesh = mm
	material_override = material

	# The instance transforms written below are world-space, so this node must not add one of
	# its own on top.
	top_level = true
	global_transform = Transform3D.IDENTITY

	# Godot sizes a MultiMesh's bounds from the instance transforms, and it does not recompute
	# them as the fish swim. Without a box big enough to hold the whole beat, the school gets
	# culled the moment its starting position leaves the frustum.
	var reach := home_radius + 8.0
	custom_aabb = AABB(_home - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)

	root.queue_free()
	return true


## Fish start as a ball, evenly spread, rather than scattered at random across the whole area.
## Random placement means the first several seconds are spent gathering up, and the school only
## begins to look like one once that is over - which is the first thing anybody sees.
##
## The spread is a golden-angle spiral: turning by the same irrational fraction of a circle each
## time is the one rule that never lets the points fall into spokes.
func _populate() -> void:
	var n := count
	_pos.resize(n)
	_dir.resize(n)
	_speed.resize(n)
	_phase.resize(n)
	_lit.resize(n)
	_bed.resize(n)
	_next.resize(n)
	_want.resize(n)
	_scare.resize(n)
	var golden := PI * (3.0 - sqrt(5.0))
	var ball := maxf(home_radius * 0.3, 2.0)
	var heading := Vector3(_rng.randf_range(-1.0, 1.0), 0.0,
			_rng.randf_range(-1.0, 1.0))
	heading = heading.normalized() if heading.length() > 0.1 else Vector3.FORWARD
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		# Cube root, so the points fill the ball evenly instead of crowding into the middle.
		var radius: float = ball * pow(t, 1.0 / 3.0)
		var y: float = 1.0 - 2.0 * t
		var ring: float = sqrt(maxf(1.0 - y * y, 0.0))
		var a: float = golden * float(i)
		var on_ball := Vector3(cos(a) * ring, y, sin(a) * ring)
		# Flattened, because a school is a lens rather than a beach ball.
		on_ball.y *= 0.45
		_pos[i] = _home + on_ball * radius
		_dir[i] = heading
		_speed[i] = cruise
		_phase[i] = _rng.randf()
		_lit[i] = 0.35
		_want[i] = heading
		_scare[i] = 0.0
		# Below anything, so the first bed sample cannot push a fish up through the surface
		# before it has been taken.
		_bed[i] = -1000.0


func _process(delta: float) -> void:
	if _pos.is_empty() or multimesh == null:
		return
	# A long frame - a load, an alt-tab - would otherwise step every fish metres forward at once
	# and burst the school apart.
	delta = minf(delta, 0.1)
	_wander()
	_hash()
	_steer(delta)
	_publish()


## The whole school drifts toward a point and picks a new one when it arrives. Without this the
## boid rules alone give a school that mills about in one place: they describe how fish relate
## to each other, not where any of them is going.
func _wander() -> void:
	if _centre.distance_to(_target) < 6.0 or _frame % 600 == 0:
		var a := _rng.randf() * TAU
		var r: float = _rng.randf_range(0.35, 0.9) * home_radius
		var depth: float = _rng.randf_range(below_surface + 0.5, below_surface + 4.5)
		_target = Vector3(_home.x + cos(a) * r, _sea - depth, _home.z + sin(a) * r)
	_target.y = minf(_target.y, _sea - below_surface)


## Drops every fish into a cell. `_head[cell]` is the first fish in it and `_next[i]` chains on,
## so a cell's contents can be walked without allocating anything.
func _hash() -> void:
	_head.clear()
	var inv := 1.0 / perception
	for i in _pos.size():
		var p := _pos[i]
		var key := _cell(int(floor(p.x * inv)), int(floor(p.y * inv)), int(floor(p.z * inv)))
		_next[i] = _head.get(key, -1)
		_head[key] = i


static func _cell(x: int, y: int, z: int) -> int:
	# Each axis is multiplied by a large odd number before mixing, so that neighbouring cells do
	# not land in neighbouring buckets and a school swimming straight does not pile into one.
	return (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)


## One frame for every fish: turn toward the heading it last chose, move, and work out how hard
## it is working. Only the fish whose turn it is look around them - see THINK_EVERY.
func _steer(delta: float) -> void:
	# Counted here rather than in _process because the staggers below are the only thing that
	# uses it: a caller that drives _steer directly and leaves the frame number standing would
	# have the same third of the school thinking every time and the other two thirds never
	# looking around at all - which is drifting fish, fish in the seabed, and nothing obviously
	# wrong with the code.
	_frame += 1
	var n := _pos.size()
	var beat_span := beat_hard - beat_calm

	# Predators are read once rather than per fish. There are single figures of them against
	# hundreds of fish, and global_position on a node is not free.
	var danger := PackedVector3Array()
	for node in predators:
		if is_instance_valid(node):
			danger.append(node.global_position)

	var sum := Vector3.ZERO
	for i in n:
		if (i + _frame) % THINK_EVERY == 0:
			_decide(i, danger)

		var facing := _dir[i]
		var want := _want[i]

		# How hard this fish is working to turn. This is the number the swim is built on: the
		# angle it still has to close, not the speed it is already carrying. It is measured
		# every frame, not only on think frames, so the effort falls away as the turn completes
		# instead of holding flat until the fish looks again.
		var angle := facing.angle_to(want)
		var turn: float = minf(angle, turn_max * delta)
		var axis := facing.cross(want)
		if axis.length_squared() > 0.000001 and turn > 0.00001:
			facing = facing.rotated(axis.normalized(), turn).normalized()
		var effort_turn: float = clampf(angle / maxf(turn_max * delta, 0.0001), 0.0, 1.0)

		# The turn shoves the fish along as well as around.
		var scared := _scare[i]
		var wanted: float = cruise * (1.0 + turn_drives_speed * effort_turn) + speed_max * scared
		wanted = minf(wanted, speed_max)
		var gain: float = wanted - _speed[i]
		_speed[i] = clampf(_speed[i] + clampf(gain, -1.0, 1.0) * 6.0 * delta, 0.4, speed_max)
		var effort_drive: float = clampf(absf(gain) / maxf(cruise, 0.001), 0.0, 1.0)

		# The louder of the two, which is what stops a hard turn at a constant speed from
		# reading as a glide.
		var lit: float = maxf(maxf(effort_drive, effort_turn), scared)
		# Eased rather than snapped, so one frame of hard steering does not flash.
		_lit[i] = _lit[i] + (clampf(lit, 0.18, 1.0) - _lit[i]) * minf(delta * 6.0, 1.0)

		_dir[i] = facing
		var here: Vector3 = _pos[i] + facing * _speed[i] * delta
		_pos[i] = here
		sum += here
		# Phase is carried, never recomputed from the clock, because the beat changes with the
		# fish - see the note in fish.gdshader.
		_phase[i] = fposmod(_phase[i] + (beat_calm + beat_span * _lit[i]) * delta, 1.0)

	_centre = sum / float(n)


## One fish looks around it and picks a heading. This is the expensive half and the reason for
## the hash: everything above runs on every fish every frame, this runs on a third of them.
func _decide(i: int, danger: PackedVector3Array) -> void:
	var here := _pos[i]
	var facing := _dir[i]
	var inv := 1.0 / perception
	var see_sq := perception * perception
	var near_sq := personal_space * personal_space

	var push := Vector3.ZERO
	var line := Vector3.ZERO
	var middle := Vector3.ZERO
	var seen := 0

	var cx := int(floor(here.x * inv))
	var cy := int(floor(here.y * inv))
	var cz := int(floor(here.z * inv))
	for ox in range(-1, 2):
		for oy in range(-1, 2):
			for oz in range(-1, 2):
				var j: int = _head.get(_cell(cx + ox, cy + oy, cz + oz), -1)
				while j != -1:
					if j != i:
						var away := here - _pos[j]
						var d2 := away.length_squared()
						if d2 < see_sq and d2 > 0.000001:
							middle += _pos[j]
							line += _dir[j]
							seen += 1
							if d2 < near_sq:
								# Divided by the distance, so a fish about to be collided with
								# counts for far more than one merely close.
								push += away / d2
					j = _next[j]

	var want := facing
	if seen > 0:
		if push.length_squared() > 0.000001:
			want += push.normalized() * weight_separation
		if line.length_squared() > 0.000001:
			want += line.normalized() * weight_alignment
		var to_middle := middle / float(seen) - here
		if to_middle.length_squared() > 0.000001:
			want += to_middle.normalized() * weight_cohesion

	var to_target := _target - here
	if to_target.length_squared() > 0.01:
		want += to_target.normalized() * weight_target

	# Predators override everything else. A fish that politely keeps formation while a shark
	# arrives is not a fish.
	var scared := 0.0
	var flee_sq := flee_range * flee_range
	for at in danger:
		var away := here - at
		var d2 := away.length_squared()
		if d2 < flee_sq and d2 > 0.000001:
			var urgency: float = 1.0 - sqrt(d2) / flee_range
			want += away.normalized() * weight_flee * urgency
			scared = maxf(scared, urgency)
	_scare[i] = scared

	# Walls. The surface and the seabed are hard limits - a fish through either one is the whole
	# illusion gone - so they push rather than merely suggest.
	if (i + _frame) % BED_EVERY == 0 and terrain != null:
		_bed[i] = terrain.height_at(here.x, here.z)
	var ceiling := _sea - below_surface
	var floor_y: float = _bed[i] + above_bed
	if here.y > ceiling:
		want += Vector3.DOWN * (1.0 + (here.y - ceiling))
	elif here.y < floor_y:
		want += Vector3.UP * (1.0 + (floor_y - here.y))
	var out := Vector3(here.x - _home.x, 0.0, here.z - _home.z)
	var far := out.length()
	if far > home_radius:
		want -= out / far * (1.0 + (far - home_radius) * 0.2)

	if want.length_squared() < 0.000001:
		want = facing
	_want[i] = want.normalized()


func _publish() -> void:
	var mm := multimesh
	for i in _pos.size():
		mm.set_instance_transform(i,
				Transform3D(Basis.looking_at(_dir[i], Vector3.UP), _pos[i]))
		mm.set_instance_custom_data(i, Color(_phase[i], _lit[i], 0.0, 0.0))
