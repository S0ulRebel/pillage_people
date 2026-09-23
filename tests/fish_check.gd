extends SceneTree
## Run: godot --headless --path . --script res://tests/fish_check.gd
##
## Are the fish fish, and are they a school?
##
## Everything about them fails quietly. There is no animation clip to go missing and no
## collision to bump into: the swim is a vertex shader, so a broken one still renders a fish,
## just a rigid one; and the boids are arithmetic, so a wrong weight gives a school that is
## merely wrong rather than one that errors. From the beach, forty metres off, a school that
## has silently collapsed into a single point and a school that is working look much alike.
##
## So this asks for numbers. What it will not do is ask the fish to confirm their own
## arithmetic. The shark taught that lesson twice: a check that compares a node's forward with
## its course passes while the animal swims broadside, because look_at set both. The questions
## here are either about the ASSET, which cannot agree with itself, or about an outcome that no
## single line of the simulation sets directly.

## Seconds of simulation before anything is measured, so the school has settled out of its
## starting ball.
const SETTLE := 3.0
## Frames per second the checks pretend to run at.
const STEP := 1.0 / 60.0
## Milliseconds a school of `fish_per_school` may cost per frame. The whole frame budget at
## 60 Hz is 16.7, and fish are scenery.
const BUDGET_MS := 2.5

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 60:
		await process_frame

	var terrain := scene.get_node("Terrain")
	var schools: Array[Node] = []
	for node in scene.get_children():
		if node.get_script() != null and node is MultiMeshInstance3D \
				and node.has_method("fish_count"):
			schools.append(node)
	check(not schools.is_empty(), "no fish schools in the scene at all")
	if schools.is_empty():
		_finish()
		return
	var school: MultiMeshInstance3D = schools[0]
	print("%d schools, %d fish in the first" % [schools.size(), school.fish_count()])
	check(school.fish_count() > 0, "the first school has no fish in it")

	# From here the schools do not step themselves: every measurement below is taken after a
	# known number of fixed 1/60 steps from a known seed, so the numbers are the same on any
	# machine under any load.
	#
	# They were not before. The sixty frames awaited above run each school's own _process with
	# REAL frame deltas, so on a loaded machine the school had lived several times longer by the
	# time it was measured than it had on an idle one - and this check failed once inside a full
	# suite run while passing five times on its own, which is the worst way for a test to
	# behave. Thresholds tuned against a number that moves are not thresholds.
	for node in schools:
		node.set_process(false)
	school.setup(school.global_position, terrain.sea_level(), 1)

	_check_model(school)
	if school.fish_count() == 0:
		_finish()
		return

	# Settle.
	for i in int(SETTLE / STEP):
		school._wander()
		school._hash()
		school._steer(STEP)

	_check_placement(school)
	_check_school(school)
	_check_water(school, terrain)
	_check_swim(school)
	await _check_flight(school)
	_check_cost(school)
	_finish()


## Everything here is a fact about the file on disk, which is the one thing in the system that
## cannot be talked into agreeing with the code that reads it.
func _check_model(school: MultiMeshInstance3D) -> void:
	var mesh: Mesh = school.multimesh.mesh
	check(mesh != null, "the school has no mesh")
	if mesh == null:
		return
	var box: AABB = mesh.get_aabb()
	print("model aabb pos=(%.3f %.3f %.3f) size=(%.3f %.3f %.3f)"
			% [box.position.x, box.position.y, box.position.z,
				box.size.x, box.size.y, box.size.z])

	var longest := 0
	if box.size.y > box.size[longest]:
		longest = 1
	if box.size.z > box.size[longest]:
		longest = 2
	check(longest == 2,
			"the fish model is longest along %s, so it is not authored nose-along-Z."
			% ["X", "Y", "Z"][longest]
			+ " Godot points a node's -Z forward, so a school of them will swim sideways the way"
			+ " the shark did. Re-bake with tools/reorient_model.py rather than turning the"
			+ " instances to compensate")

	# The origin has to be the body's MIDDLE. Tripo puts it at the belly, and the shader rolls
	# the fish about its own spine - about the origin - so a belly pivot swings the whole body
	# sideways instead of rolling it. This is also what put the shark 1.80 m above the sea.
	var off_y: float = absf(box.position.y + box.size.y * 0.5)
	var off_z: float = absf(box.position.z + box.size.z * 0.5)
	check(off_y < box.size.y * 0.1 and off_z < box.size.z * 0.1,
			"the model's origin is %.3f m off its middle in Y and %.3f m in Z. The roll in"
			% [off_y, off_z]
			+ " fish.gdshader is about the origin, so an off-centre one swings the body instead"
			+ " of rolling it. Re-bake with reorient_model.py --centre")

	# The size has to be in the .glb, not in a gitignored .import. A fresh clone that silently
	# got 1 m fish would still pass every other check in this file.
	check(box.size.z > 0.2 and box.size.z < 0.6,
			"the fish is %.2f m long. It should be about 0.35 - if it is 1.0 the scale has"
			% box.size.z + " moved back into the .import file, which .gitignore drops")

	# Which end is the head. The tail is a flat blade: almost no width, full height. If the head
	# is at +Z the fish swims backwards, and nothing else here would notice.
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var wide := [0.0, 0.0]
	var seen := [0, 0]
	for v in verts:
		var end := -1
		if v.z < box.position.z + box.size.z * 0.2:
			end = 0
		elif v.z > box.position.z + box.size.z * 0.8:
			end = 1
		if end != -1:
			wide[end] += absf(v.x)
			seen[end] += 1
	var nose: float = wide[0] / maxf(seen[0], 1)
	var tail: float = wide[1] / maxf(seen[1], 1)
	print("ends: -Z mean |x| %.4f over %d verts, +Z %.4f over %d" % [nose, seen[0], tail, seen[1]])
	check(nose > tail * 2.0,
			"the -Z end is %.4f m wide and the +Z end %.4f - the thin end is the tail fin, so"
			% [nose, tail] + " this model has its head at +Z and will swim backwards")


## The node's own transform has to be what says where the school is, because that is the only
## thing anybody can drag in the editor. The instances are therefore written RELATIVE to it.
##
## This fails the obvious regression: writing world-space transforms instead. The school would
## still look perfectly correct in the running game - the node sits at the origin of the scene,
## so world and local agree there - and would render a hundred and eighty metres from the node
## in the editor, and jump there the moment anyone moved it.
##
## It asks FishSchool.placement rather than the MultiMesh, because MultiMesh.get_instance_
## transform returns a zero transform for every instance under the headless display server
## whatever was written into it. The first version of this check read the MultiMesh, measured
## "0.0 m" and passed both with the code right and with it deliberately broken.
func _check_placement(school: MultiMeshInstance3D) -> void:
	var at: Vector3 = school.global_position
	check(at.length() > 10.0,
			"this school is at the scene origin, so local and world space cannot be told apart"
			+ " and the check below proves nothing")
	var into_local: Transform3D = school.global_transform.affine_inverse()
	var furthest := 0.0
	for i in school.fish_count():
		furthest = maxf(furthest, school.placement(i, into_local).origin.length())
	print("node at %s, furthest instance %.1f m from it" % [str(at.round()), furthest])
	check(furthest < school.home_radius + 8.0,
			"the furthest fish is %.1f m from the node it belongs to, which is at %s - the"
			% [furthest, str(at.round())]
			+ " instances are being written in world space, so the school ignores the node and"
			+ " moving it in the editor will not move the fish")


## Is it a school, or a swarm, or a single point? None of these is set anywhere in the
## simulation - they are what the three boid rules add up to.
func _check_school(school: MultiMeshInstance3D) -> void:
	var pos: PackedVector3Array = school._pos
	var dir: PackedVector3Array = school._dir
	var n := pos.size()

	var nearest := 0.0
	var loneliest := 0.0
	for i in n:
		var best := 1e9
		for j in n:
			if i != j:
				best = minf(best, pos[i].distance_squared_to(pos[j]))
		best = sqrt(best)
		nearest += best
		loneliest = maxf(loneliest, best)
	nearest /= float(n)
	print("nearest neighbour: %.2f m on average, %.2f m at worst (personal space %.2f)"
			% [nearest, loneliest, school.personal_space])

	# Separation is the only thing holding them apart. If it stops working they converge to a
	# point, which from any distance looks like one large fish.
	check(nearest > school.personal_space * 0.4,
			"the average fish is %.2f m from its nearest neighbour against a personal space of"
			% nearest + " %.2f - separation has stopped working and the school is collapsing"
			% school.personal_space)
	# And cohesion is the only thing holding them together.
	check(nearest < school.perception,
			"the average fish is %.2f m from its nearest neighbour, further than it can even see"
			% nearest + " (%.2f) - cohesion has stopped working and the school has dispersed"
			% school.perception)

	# Alignment and cohesion have to be asked WITHOUT the school's target, and this is the whole
	# reason the section exists. With it, every fish is being pulled toward the same point, so
	# they all end up pointing the same way and staying together no matter what the boid rules
	# do - the first version of this check passed with alignment and cohesion both set to zero.
	# Take the target away and the only things left holding the school together are the rules
	# under test.
	var target_was: float = school.weight_target
	school.weight_target = 0.0
	# Long enough for a school with nothing holding it together to actually come apart. Four
	# seconds was not: alignment alone keeps them parallel, so they drift apart slowly and a
	# cohesion-less school still measured a respectable 4 m across.
	for i in 900:
		school._hash()
		school._steer(STEP)

	var mean := Vector3.ZERO
	for d in school._dir:
		mean += d
	mean /= float(n)
	var agreement := mean.length()
	var spread := _spread(school)
	print("with no target to follow: agreement %.2f, spread %.2f m" % [agreement, spread])
	school.weight_target = target_was

	check(agreement > 0.80,
			"with nothing to swim toward, the fish agree on a heading to only %.2f out of 1.0 -"
			% agreement + " they are milling rather than schooling, which is what dropping the"
			+ " alignment term looks like")
	# 3.0 sits between two measured numbers rather than being a round figure that sounded safe:
	# with cohesion this settles at 2.3 to 2.6 m, and with weight_cohesion set to zero it settles
	# at 3.6 to 3.7. The school's RNG is seeded, so both are repeatable to the centimetre.
	#
	# The mean is what separates them. The WORST straggler does not - 8.1 m either way - because
	# a fish that drifts past `perception` can no longer see the school at all and nothing local
	# can pull it back. That is boids working as designed, not a fault, and it is why the school
	# also has a target: the shared target is what fetches the strays home.
	check(spread < 3.0,
			"with nothing to swim toward, the school settled at %.2f m across against 2.3 to 2.6"
			% spread + " when cohesion is working - they are drifting apart")


func _check_water(school: MultiMeshInstance3D, terrain: Node) -> void:
	var pos: PackedVector3Array = school._pos
	var sea: float = terrain.sea_level()
	var highest := -1e9
	var deepest := 1e9
	var above := 0
	var buried := 0
	for p in pos:
		highest = maxf(highest, p.y)
		deepest = minf(deepest, p.y)
		if p.y > sea:
			above += 1
		if p.y < terrain.height_at(p.x, p.z):
			buried += 1
	print("fish depth: from %.2f m to %.2f m, sea level %.2f" % [deepest, highest, sea])
	check(above == 0,
			"%d fish are out of the water - a fish above the surface is the whole thing gone"
			% above)
	check(buried == 0, "%d fish are inside the seabed" % buried)


func _check_swim(school: MultiMeshInstance3D) -> void:
	# The shader is handed a phase and an intensity per fish and nothing else. If the phase
	# stops advancing every fish freezes mid-beat; if the intensity is pinned they all beat
	# identically, which reads as one object rather than as a hundred animals.
	var before: PackedFloat32Array = school._phase.duplicate()
	for i in 12:
		school._hash()
		school._steer(STEP)
	var moved := 0
	for i in before.size():
		if absf(school._phase[i] - before[i]) > 0.0001:
			moved += 1
	check(moved == before.size(),
			"%d of %d fish did not advance their tail beat - a frozen phase is a rigid fish"
			% [before.size() - moved, before.size()])

	var lo := 1e9
	var hi := -1e9
	for v in school._phase:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var dim := 1e9
	var bright := -1e9
	for v in school._lit:
		dim = minf(dim, v)
		bright = maxf(bright, v)
	print("tail phase spread %.2f to %.2f, intensity %.2f to %.2f" % [lo, hi, dim, bright])
	check(hi - lo > 0.3,
			"every fish is at the same point in its tail beat (spread %.2f) - they will flap in"
			% (hi - lo) + " lockstep, which reads as one object")


## The one behaviour worth more than all the others: does the school break when a shark arrives?
## Nothing sets this. It falls out of the flee term beating the cohesion term.
func _check_flight(school: MultiMeshInstance3D) -> void:
	var shark := Node3D.new()
	current_scene.add_child(shark)
	shark.global_position = school.centre()
	school.predators = [shark] as Array[Node3D]

	# Count the fish that are actually close to it, rather than measuring the school's spread or
	# where its centre drifted to. The first version of this check asked for a wider spread OR a
	# centre further off, and the second half of that was true whatever the fish did - a school
	# swimming normally leaves a stationary point behind it within a second. It passed with the
	# flee term set to zero.
	# The shark KEEPS UP with the school rather than being dropped in and left. A stationary one
	# proves nothing: the school swims off about its business and the count near it falls to
	# almost nothing whether the fish noticed it or not. Pinned to the school's centre, the only
	# thing that can clear the water around it is the fish actively getting out of the way.
	var ring: float = school.flee_range * 0.5
	var before := _within(school, shark.global_position, ring)
	for i in 90:
		shark.global_position = school.centre()
		school._hash()
		school._steer(STEP)
	var after := _within(school, shark.global_position, ring)
	print("shark dropped in: %d fish within %.1f m of it, %d after a second and a half"
			% [before, ring, after])
	check(before > 0, "the shark was not dropped anywhere near the school, so this proved nothing")
	check(after * 4 < before,
			"%d of the %d fish that were within %.1f m of the shark are still there - they are"
			% [after, before, ring] + " ignoring it")
	shark.queue_free()
	school.predators = [] as Array[Node3D]


func _within(school: MultiMeshInstance3D, at: Vector3, radius: float) -> int:
	var n := 0
	for p in school._pos:
		if p.distance_to(at) < radius:
			n += 1
	return n


func _spread(school: MultiMeshInstance3D) -> float:
	var middle: Vector3 = school.centre()
	var total := 0.0
	for p in school._pos:
		total += middle.distance_to(p)
	return total / maxf(school._pos.size(), 1)


## What the school costs, measured rather than assumed. The whole point of the hash and the
## MultiMesh is that this stays small; a change that quietly made it n squared again would look
## fine in every other check here.
func _check_cost(school: MultiMeshInstance3D) -> void:
	var runs := 60
	var hashing := 0
	var steering := 0
	var writing := 0
	for i in runs:
		school._wander()
		var a := Time.get_ticks_usec()
		school._hash()
		var b := Time.get_ticks_usec()
		school._steer(STEP)
		var c := Time.get_ticks_usec()
		school._publish()
		var d := Time.get_ticks_usec()
		hashing += b - a
		steering += c - b
		writing += d - c
	var each := float(hashing + steering + writing) / float(runs) / 1000.0
	print("%d fish cost %.2f ms per frame (hash %.2f, steer %.2f, write %.2f; budget %.2f)"
			% [school.fish_count(), each, float(hashing) / float(runs) / 1000.0,
				float(steering) / float(runs) / 1000.0, float(writing) / float(runs) / 1000.0,
				BUDGET_MS])
	check(each < BUDGET_MS,
			"a school of %d costs %.2f ms a frame against a budget of %.2f. At 60 Hz the whole"
			% [school.fish_count(), each, BUDGET_MS]
			+ " frame is 16.7 ms and these are scenery")


func _finish() -> void:
	print("fish check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
