extends SceneTree
## Run: godot --headless --path . --script res://tests/terrain_stamp_check.gd
##
## Does a TerrainStamp change the ground by exactly what it says, and nowhere else?
##
## Two terrains are built from the same island, one with stamps under it and one without, and
## compared sample by sample: at a stamp's centre the difference has to be its strength times
## the stamp's own value there, and outside every footprint it has to be zero. A stamp that
## leaked past its border would lift a square of ground around the landform - the failure the
## stamp images are made 0 at the edge to prevent.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _terrain(stamps: Array) -> Node3D:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	for stamp in stamps:
		terrain.add_child(stamp)
	root.add_child(terrain)
	return terrain


func _stamp(path: String, at: Vector3, strength: float, yaw: float) -> TerrainStamp:
	var stamp := STAMP.instantiate() as TerrainStamp
	stamp.stamp_path = path
	stamp.strength = strength
	stamp.length = 150.0
	stamp.width = 90.0
	stamp.position = at
	stamp.rotation.y = yaw
	return stamp


func _run() -> void:
	var plain := _terrain([])
	var mountain := _stamp("res://world/terrain_stamp/stamps/mountain.r16",
			Vector3(-60.0, 0.0, 40.0), 50.0, 0.6)
	var canyon := _stamp("res://world/terrain_stamp/stamps/canyon.r16",
			Vector3(90.0, 0.0, -70.0), -20.0, -0.3)
	var stamped := _terrain([mountain, canyon])
	await process_frame

	# Measured on a sample of the height map, not at the stamp's exact centre: between samples
	# the terrain interpolates, and on a craggy peak that alone moved the answer 0.3 m.
	var spacing := 620.0 / 1023.0
	for stamp: TerrainStamp in [mountain, canyon]:
		var at := stamp.global_position
		at.x = roundf((at.x + 310.0) / spacing) * spacing - 310.0
		at.z = roundf((at.z + 310.0) / spacing) * spacing - 310.0
		var expected := stamp.strength * stamp.value_at(at.x, at.z)
		var got: float = stamped.height_at(at.x, at.z) - plain.height_at(at.x, at.z)
		print("%s centre: moved %.2f m, expected %.2f m" % [stamp.stamp_path.get_file(), got, expected])
		check(absf(got - expected) < 0.05, "%s moved the ground %.3f m at its centre, expected %.3f m"
				% [stamp.stamp_path.get_file(), got, expected])
		check(absf(expected) > 5.0, "%s barely changes its centre (%.2f m) - the test proves nothing"
				% [stamp.stamp_path.get_file(), expected])

	# Everywhere outside both footprints must be untouched.
	var leaked := 0
	var worst := 0.0
	var inside := [mountain.footprint(), canyon.footprint()]
	for gx in 124:
		for gz in 124:
			var x := -305.0 + gx * 5.0
			var z := -305.0 + gz * 5.0
			var covered := false
			for rect: Rect2 in inside:
				covered = covered or rect.grow(1.0).has_point(Vector2(x, z))
			if covered:
				continue
			var moved: float = absf(stamped.height_at(x, z) - plain.height_at(x, z))
			if moved > 0.0001:
				leaked += 1
				worst = maxf(worst, moved)
	print("outside the footprints: %d samples moved, worst %.4f m" % [leaked, worst])
	check(leaked == 0, "%d samples outside every footprint moved (worst %.4f m)" % [leaked, worst])

	# The collider is built from the same stamped heights as the mesh. Compared on a mesh vertex:
	# the mesh and the collider share a 1.2 m grid, both coarser than the 0.6 m height map, so
	# between vertices both chord the stamp's finer crags and differ from height_at - by 1.03 m
	# on this peak - while agreeing with each other.
	stamped.generate()
	await physics_frame
	await physics_frame
	var space := stamped.get_world_3d().direct_space_state
	var step := 620.0 / 512.0
	var top := mountain.global_position
	top.x = roundf((top.x + 310.0) / step) * step - 310.0
	top.z = roundf((top.z + 310.0) / step) * step - 310.0
	var query := PhysicsRayQueryParameters3D.create(Vector3(top.x, 500.0, top.z), Vector3(top.x, -100.0, top.z))
	var hit := space.intersect_ray(query)
	check(not hit.is_empty(), "no collider under the mountain stamp")
	if not hit.is_empty():
		var floor_gap: float = hit.position.y - stamped.height_at(top.x, top.z)
		print("collider vs stamped ground at the mountain: %.3f m" % floor_gap)
		check(absf(floor_gap) < 0.03, "collider %.3f m off the stamped ground" % floor_gap)

	await _check_levelling(plain)
	await _check_small_pad(plain)

	print("terrain_stamp_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


## Flatten, cut down and fill up, each on its own patch of hillside with the plane set to the
## plain ground's height at the centre - so every patch has ground both above and below it.
func _check_levelling(plain: Node3D) -> void:
	var spots := {
		TerrainStamp.Mode.FLATTEN: Vector2(-120.0, -40.0),
		TerrainStamp.Mode.CUT_DOWN: Vector2(40.0, 110.0),
		TerrainStamp.Mode.FILL_UP: Vector2(130.0, 20.0),
	}
	var stamps: Array = []
	for mode in spots:
		var at: Vector2 = spots[mode]
		var stamp := STAMP.instantiate() as TerrainStamp
		stamp.mode = mode
		stamp.shape = TerrainStamp.Shape.SOFT_RECT
		stamp.length = 60.0
		stamp.width = 40.0
		stamp.edge_softness = 8.0
		stamp.position = Vector3(at.x, plain.height_at(at.x, at.y), at.y)
		stamp.rotation.y = 0.4
		stamps.append(stamp)
	var levelled := _terrain(stamps)
	await process_frame

	for stamp: TerrainStamp in stamps:
		var plane := stamp.global_position.y
		var above := 0
		var below := 0
		var wrong := 0
		# the core, where the weight is 1: inside the rectangle by more than the softness
		for i in 20:
			for j in 20:
				var local := Vector3(-20.0 + i * 2.0, 0.0, -10.0 + j * 1.0)
				var world := stamp.global_transform * local
				var before: float = plain.height_at(world.x, world.z)
				var after: float = levelled.height_at(world.x, world.z)
				if before > plane:
					above += 1
				else:
					below += 1
				var expected := before
				match stamp.mode:
					TerrainStamp.Mode.FLATTEN:
						expected = plane
					TerrainStamp.Mode.CUT_DOWN:
						expected = minf(before, plane)
					TerrainStamp.Mode.FILL_UP:
						expected = maxf(before, plane)
				# sampled between map samples, so interpolation next to a crease is allowed a little
				if absf(after - expected) > 0.1:
					wrong += 1
		var name: String = TerrainStamp.Mode.keys()[stamp.mode]
		print("%s: plane %.1f m, %d samples above it and %d below, %d wrong" % [name, plane, above, below, wrong])
		check(above > 20 and below > 20, "%s patch is not on a slope - the check proves nothing" % name)
		check(wrong == 0, "%s: %d core samples are not where the mode puts them" % [name, wrong])


## The first real use: a 6 x 5 m flatten pad under the cannon, with the default 12 m softness.
## While the softness faded inwards the pad's centre got 11% of the effect and the ground under
## the cannon stayed sloped. The whole pad has to be level now.
func _check_small_pad(plain: Node3D) -> void:
	var at := Vector2(91.4, 45.0)
	var pad := STAMP.instantiate() as TerrainStamp
	pad.mode = TerrainStamp.Mode.FLATTEN
	pad.shape = TerrainStamp.Shape.SOFT_RECT
	pad.length = 6.0
	pad.width = 5.0
	pad.position = Vector3(at.x, plain.height_at(at.x, at.y) + 0.5, at.y)
	var levelled := _terrain([pad])
	await process_frame
	var worst := 0.0
	var slope := 0.0
	for i in 7:
		for j in 6:
			var x := at.x - 3.0 + i * 1.0
			var z := at.y - 2.5 + j * 1.0
			worst = maxf(worst, absf(levelled.height_at(x, z) - pad.position.y))
			slope = maxf(slope, absf(plain.height_at(x, z) - pad.position.y))
	print("6 x 5 m pad: ground was up to %.2f m off the plane, now %.3f m" % [slope, worst])
	check(slope > 0.5, "the pad's patch was already level - the check proves nothing")
	check(worst < 0.02, "6 x 5 m pad left the ground %.3f m off its plane" % worst)
