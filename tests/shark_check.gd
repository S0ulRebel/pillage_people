extends SceneTree
## Run: godot --headless --path . --script res://tests/shark_check.gd
##
## Is the shark swimming, and is it swimming in water?
##
## It has no animation clip - the swim is a travelling sine wave written down the spine every
## frame, see props/shark/shark.gd. That fails quietly in a way a clip does not: the model
## loads, the skeleton is found, it moves along its circle, and it is simply RIGID. A shark
## that does not bend is a very expensive rock, and from the beach at forty metres nobody would
## be able to say what was wrong with it.
##
## So this asks the bones, not the eye: does the tail pose actually change over time?
##
## The other half is where the circle goes. It is placed by bearing and radius from the spawn
## point, and nothing in that arithmetic knows where the coastline is - so the far side of the
## circle can sit on dry land, and a shark swimming up the beach is worse than no shark.

## How many spine bones the wave is written to. Five: Spine_0 through Tail_1.
const SPINE_BONES := 5
## Metres the tail must travel sideways across a second. Measured at 0.07 with the shipped
## settings, so this floor leaves room to tune the look without becoming a tripwire.
const TAIL_MUST_MOVE := 0.02
## Metres of water under the shark, all the way round. Below this it is in the shallows.
const WATER_WANTED := 2.0

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
	var shark: Node3D = scene.get_node_or_null("Shark")
	check(shark != null, "no shark in the scene at all")
	if shark == null:
		_finish()
		return

	check(shark.bones_found() == SPINE_BONES,
			"the wave is being written to %d bones, expected %d - the rig's names changed, and"
			% [shark.bones_found(), SPINE_BONES]
			+ " Godot rewrites them on import (tripo::Spine_0 becomes tripo__Spine_0)")

	# Watch the last bone in the chain for a second. Read from the skeleton rather than from
	# the shark's own maths, so this measures what the model is actually doing.
	var skeleton: Skeleton3D = null
	for node in shark.find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	check(skeleton != null, "the shark has no skeleton")
	if skeleton == null:
		_finish()
		return
	var tail := skeleton.find_bone("tripo__Tail_1")
	check(tail != -1, "no tail bone called tripo__Tail_1")
	# Where the tail actually GOES, in the shark's own space, rather than a Euler angle off its
	# pose. The angle version measured the Y component, which stopped meaning anything the
	# moment the swing moved onto the model's own up axis - and it would have kept reporting a
	# healthy 27 degrees while the fish went stiff.
	#
	# Sideways against vertical is also the bug that shipped: the tail was flapping up and down
	# like a dolphin, 1 cm of it, and the old check could not tell the difference.
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	if tail != -1:
		for i in 60:
			await process_frame
			var at: Vector3 = shark.to_local(
					skeleton.to_global(skeleton.get_bone_global_pose(tail).origin))
			lo = lo.min(at)
			hi = hi.max(at)
	var span := hi - lo
	print("tail travels sideways %.3f m, vertically %.3f m" % [span.x, span.y])
	check(span.x >= TAIL_MUST_MOVE,
			"the tail moved %.3f m sideways in a second - the shark is rigid, which from the"
			% span.x + " beach looks like a rock rather than like a bug")
	check(span.x > span.y * 2.0,
			"the tail moves %.3f m vertically against %.3f m sideways - a shark yaws, it does"
			% [span.y, span.x] + " not porpoise. The swing is on the wrong axis")

	# Is it pointing where it is going?
	#
	# Asked of the MODEL FILE, not of the bones and not of the node.
	#
	# Two wrong versions before this one. The first compared the node's forward with the course,
	# which is the same assumption twice - look_at aims -Z along the course, so it read 0.0
	# degrees while the fish went broadside. The second asked the skeleton where its own head
	# was, and on this model the skeleton's rest pose and the mesh DISAGREE: the bones said
	# 5.6 degrees while the thing on screen was square across its own wake.
	#
	# So the question is really about the asset: is the mesh authored nose-along-Z, which is
	# what Godot's forward expects and what tools/reorient_model.py bakes in? That is a fact
	# about the file, it cannot agree with itself, and if it is true then look_at is correct by
	# construction.
	var mesh_node: MeshInstance3D = null
	for node in shark.find_children("*", "MeshInstance3D", true, false):
		mesh_node = node as MeshInstance3D
		break
	check(mesh_node != null and mesh_node.mesh != null, "the shark has no mesh")
	if mesh_node != null and mesh_node.mesh != null:
		var box: AABB = mesh_node.mesh.get_aabb()
		var longest := 0
		if box.size.y > box.size[longest]:
			longest = 1
		if box.size.z > box.size[longest]:
			longest = 2
		print("model is longest along %s (%.2f x %.2f x %.2f)"
				% [["X", "Y", "Z"][longest], box.size.x, box.size.y, box.size.z])
		check(longest == 2,
				"the shark model is longest along %s, so it is not authored nose-along-Z."
				% ["X", "Y", "Z"][longest]
				+ " Godot points a node's -Z forward, so it will swim sideways. Re-bake it with"
				+ " tools/reorient_model.py rather than turning the node to compensate")

	var before: Vector3 = shark.global_position
	for i in 20:
		await process_frame
	var travelled: Vector3 = shark.global_position - before
	travelled.y = 0.0
	check(travelled.length() > 0.05, "the shark is not moving at all")

	# The beat, end to end. The shore curves, so the far ends are where it will run aground.
	var sea: float = terrain.sea_level()
	var centre: Vector3 = shark.global_position
	var along: Vector3 = shark._along
	var shallowest := 999.0
	var driest := Vector3.ZERO
	for step in 21:
		var t: float = (float(step) / 10.0 - 1.0) * float(shark.patrol)
		var at: Vector3 = centre + along * t
		var bed: float = terrain.height_at(at.x, at.z)
		if sea - bed < shallowest:
			shallowest = sea - bed
			driest = at
	print("shallowest point of the beat: %.1f m of water at (%.0f, %.0f)"
			% [shallowest, driest.x, driest.z])
	check(shallowest >= WATER_WANTED,
			"the beat passes through %.1f m of water at (%.0f, %.0f) - an end of its run is"
			% [shallowest, driest.x, driest.z] + " up the beach")
	_finish()


func _finish() -> void:
	print("shark check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
