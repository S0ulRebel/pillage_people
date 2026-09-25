extends SceneTree
## Run: godot --headless --path . --script res://tests/tunnel_check.gd
##
## Tunnels by what a player would notice, measured with rays against the built colliders:
##
##   a dead-end cave   two points into a hillside. The mouth has to be open from above, the floor
##                     flat and half the section below the curve, and the far end closed - a ray
##                     fired at it must hit rock, not run on into nothing.
##   a sharp corner    three points, 90 degrees. The passage must stay clear round the corner
##                     and the walls stand at the mitre's width, not pinch shut on the inside.
##   a crossing        two tunnels in an X. Each must be clear along its whole length: the
##                     other's walls, which would otherwise wall the junction off, are trimmed.

const TERRAIN := preload("res://world/terrain.gd")

var failures := 0
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	root.add_child(terrain)
	await process_frame

	var slope := _find_hillside(terrain, [])
	check(not slope.is_empty(), "no hillside steep enough for a cave on this island")
	if slope.is_empty():
		_finish()
		return
	var foot: Vector3 = slope[0]
	var uphill: Vector3 = slope[1]
	print("hillside at %s, rising %.2f m per m" % [foot.round(), slope[2]])

	# A dead-end cave: from just above the ground at the foot of the slope, level into the hill.
	var cave := _tunnel("Cave", Tunnel.Section.ARCH, 6.0, 5.0,
			[foot + Vector3.UP * 0.5, foot + uphill * 32.0 + Vector3.UP * -0.5])

	# The corridor and the crossing are buried well away from the cave, under high ground.
	var deep := _find_high_ground(terrain, foot)
	var depth := 16.0
	var corner_at := Vector3(deep.x, deep.y - depth, deep.z)
	var corridor := _tunnel("Corridor", Tunnel.Section.SHAFT, 4.0, 4.0,
			[corner_at + Vector3(-14, 0, 0), corner_at, corner_at + Vector3(0, 0, 14)])
	var cross_at := corner_at + Vector3(0, 0, -30)
	var along_x := _tunnel("AlongX", Tunnel.Section.ARCH, 5.0, 4.5,
			[cross_at + Vector3(-12, 0, 0), cross_at + Vector3(12, 0, 0)])
	var along_z := _tunnel("AlongZ", Tunnel.Section.ARCH, 5.0, 4.5,
			[cross_at + Vector3(0, 0, -12), cross_at + Vector3(0, 0, 12)])
	for tunnel in [cave, corridor, along_x, along_z]:
		terrain.add_child(tunnel)

	var started := Time.get_ticks_msec()
	terrain.generate()
	print("generate() with four tunnels: %d ms" % (Time.get_ticks_msec() - started))
	for i in 3:
		await physics_frame
	_space = terrain.get_world_3d().direct_space_state
	check(terrain.tunnels.size() == 4, "%d of 4 tunnels were built" % terrain.tunnels.size())

	_check_cave(terrain, cave, foot, uphill)
	_check_corner(corner_at)
	_check_crossing(cross_at)
	_finish()


func _finish() -> void:
	print("tunnel_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check_cave(terrain: Node3D, cave: Tunnel, foot: Vector3, uphill: Vector3) -> void:
	var start := cave.to_global(cave.curve.get_point_position(0))
	var end := cave.to_global(cave.curve.get_point_position(1))
	var forward := (end - start).normalized()

	# The mouth: the first point along the curve with the centre half a metre under the ground.
	# The roof there is 2 m above the surface, so the tube and the terrain are both cut, and a
	# ray from the sky lands on the tunnel's floor. Not right at the edge of the opening: there
	# the ground is kept for the last cut_margin (0.4 m) inside the roof on purpose, so ground and
	# tube overlap - a probe 0.23 m under the roof landed on that overlap.
	var mouth := Vector3.INF
	for i in 120:
		var point := start.lerp(end, i / 120.0)
		if terrain.height_at(point.x, point.z) - point.y > 0.5:
			mouth = point
			break
	check(mouth != Vector3.INF, "the cave never goes underground")
	if mouth != Vector3.INF:
		var hit := _ray(mouth + Vector3.UP * 30.0, mouth + Vector3.DOWN * 10.0)
		var landed := "nothing" if hit.is_empty() else "%s at %.2f" % [hit.collider.name, hit.position.y]
		print("cave mouth: a ray from above lands on %s (floor expected at %.2f)"
				% [landed, mouth.y - 2.5])
		check(_is_tunnel(hit) and absf(hit.position.y - (mouth.y - 2.5)) < 0.3,
				"the cave mouth is not open from above - landed on %s" % landed)

	# The floor: flat, and half the section below the curve, all the way in.
	var worst_level := 0.0
	var worst_tilt := 0.0
	var probes := 0
	for i in range(8, 26, 3):
		var point := start + forward * float(i)
		var hit := _ray(point, point + Vector3.DOWN * 6.0)
		if not _is_tunnel(hit):
			check(false, "no cave floor %d m in" % i)
			continue
		probes += 1
		worst_level = maxf(worst_level, absf(hit.position.y - (point.y - 2.5)))
		worst_tilt = maxf(worst_tilt, rad_to_deg(hit.normal.angle_to(Vector3.UP)))
	print("cave floor: %d probes, worst %.3f m off level, worst tilt %.1f deg" % [probes, worst_level, worst_tilt])
	check(worst_level < 0.1, "cave floor is %.3f m off where the section puts it" % worst_level)
	# The curve drops a metre over 32, about 1.8 degrees - that is all the tilt there should be.
	check(worst_tilt < 3.0, "cave floor tilts %.1f degrees - not flat" % worst_tilt)

	# The dead end: fired straight at it from 4 m short, a ray hits rock at the rounded cap -
	# 4 m plus the cap's half-width at most - instead of carrying on into the hill.
	var inside := end - forward * 4.0
	var hit := _ray(inside, inside + forward * 20.0)
	var reach := -1.0 if hit.is_empty() else inside.distance_to(hit.position)
	print("cave end: closed %.2f m ahead of a point 4 m short of it" % reach)
	check(_is_tunnel(hit) and reach < 4.0 + 3.0 + 0.3, "the cave's dead end is open (ray went %.1f m)" % reach)


func _check_corner(corner: Vector3) -> void:
	var into := Vector3(1, 0, 0)
	var out := Vector3(0, 0, 1)
	# Clear round the corner: nothing between 5 m before it and the corner, or the corner and
	# 5 m after.
	var blocked := [_ray(corner - into * 5.0, corner), _ray(corner, corner + out * 5.0)]
	for hit in blocked:
		check(hit.is_empty(), "the corridor is blocked at the corner by %s" % hit)
	# The mitre: across the bend the section is stretched by 1/cos(45), so the outer and inner
	# corners of the walls sit 2 m * sqrt(2) from the centre.
	var bisector := (out - into).normalized()
	var outward := _ray(corner, corner + bisector * 10.0)
	var inward := _ray(corner, corner - bisector * 10.0)
	var expected := 2.0 * sqrt(2.0)
	var out_reach := -1.0 if outward.is_empty() else corner.distance_to(outward.position)
	var in_reach := -1.0 if inward.is_empty() else corner.distance_to(inward.position)
	print("corner: walls %.2f m out and %.2f m in from the centre (mitre expects %.2f)"
			% [out_reach, in_reach, expected])
	check(absf(out_reach - expected) < 0.15, "outer wall at the corner is %.2f m out, not %.2f" % [out_reach, expected])
	check(absf(in_reach - expected) < 0.15, "inner wall at the corner is %.2f m in, not %.2f" % [in_reach, expected])
	var floor := _ray(corner, corner + Vector3.DOWN * 5.0)
	check(_is_tunnel(floor) and absf(floor.position.y - (corner.y - 2.0)) < 0.1,
			"no level floor under the corner")


func _check_crossing(centre: Vector3) -> void:
	# Along each tunnel, through the junction, from 3 m in at one end to 3 m in at the other.
	for axis: Vector3 in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var hit := _ray(centre - axis * 9.0, centre + axis * 9.0)
		print("crossing along %s: %s" % [axis, "clear" if hit.is_empty() else "blocked at %s" % hit.position])
		check(hit.is_empty(), "the junction is walled off along %s" % axis)
	var floor := _ray(centre, centre + Vector3.DOWN * 5.0)
	check(_is_tunnel(floor) and absf(floor.position.y - (centre.y - 2.25)) < 0.1,
			"no floor in the middle of the crossing")


# --- helpers --------------------------------------------------------------------------------

func _tunnel(tunnel_name: String, section: Tunnel.Section, width: float, height: float,
		points: Array) -> Tunnel:
	var tunnel := Tunnel.new()
	tunnel.name = tunnel_name
	tunnel.section = section
	tunnel.width = width
	tunnel.height = height
	tunnel.curve = Curve3D.new()
	for point: Vector3 in points:
		tunnel.curve.add_point(point)
	return tunnel


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))


func _is_tunnel(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit.collider.get_parent() is Tunnel


## A spot on land whose ground rises steadily for 35 m - steep enough to bury a 5 m cave
## within 30 m of its mouth, not so steep it is a cliff.
func _find_hillside(terrain: Node3D, avoid: Array) -> Array:
	var sea: float = terrain.sea_level()
	for gx in range(-24, 25):
		for gz in range(-24, 25):
			var at := Vector3(gx * 10.0, 0.0, gz * 10.0)
			at.y = terrain.height_at(at.x, at.z)
			if at.y < sea + 4.0:
				continue
			var too_close := false
			for other: Vector3 in avoid:
				too_close = too_close or Vector2(at.x - other.x, at.z - other.z).length() < 70.0
			if too_close:
				continue
			var gradient := Vector3(terrain.height_at(at.x + 5.0, at.z) - terrain.height_at(at.x - 5.0, at.z),
					0.0, terrain.height_at(at.x, at.z + 5.0) - terrain.height_at(at.x, at.z - 5.0)) / 10.0
			var rise := gradient.length()
			if rise < 0.35 or rise > 0.9:
				continue
			var uphill := gradient / rise
			# steadily: every 5 m up the line is higher than the last
			var steady := true
			var last := at.y
			for step in range(1, 8):
				var p := at + uphill * step * 5.0
				var h: float = terrain.height_at(p.x, p.z)
				if h < last + 1.0:
					steady = false
					break
				last = h
			if steady:
				return [at, uphill, rise]
	return []


## The highest ground on a coarse grid, for tunnels buried where nothing else is.
func _find_high_ground(terrain: Node3D, avoid: Vector3) -> Vector3:
	var best := Vector3(0, -1e9, 0)
	for gx in range(-20, 21):
		for gz in range(-20, 21):
			var at := Vector3(gx * 12.0, 0.0, gz * 12.0)
			if Vector2(at.x - avoid.x, at.z - avoid.z).length() < 80.0:
				continue
			# the lowest point over the patch the corridor and crossing cover
			var lowest := 1e9
			for dx in range(-20, 21, 10):
				for dz in range(-50, 21, 10):
					lowest = minf(lowest, terrain.height_at(at.x + dx, at.z + dz))
			if lowest > best.y:
				best = Vector3(at.x, lowest, at.z)
	return best
