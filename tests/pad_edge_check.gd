extends SceneTree
## Run: godot --headless --path . --script res://tests/pad_edge_check.gd
##
## Is a sharp pad's edge drawn where the pad says it is?
##
## The ground mesh has a vertex every 1.2 m. A pad whose fade is narrower than that used to be
## drawn wherever the nearest vertices happened to land: along a rotated edge they sat at
## different heights on the fade, so the crest zigzagged, its shadow zigzagged, and the wall
## was painted triangle by triangle. Now the mesh is cut along the crest and the foot of the
## fade, and the rim collider carries those cells, so a ray dropped anywhere along the outline
## has to land exactly on the plane, at the foot exactly on the natural ground, and halfway
## down the wall exactly on the stamp's own fade - at any angle, for a rectangle and an oval.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")

var failures := 0
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var plain := StaticBody3D.new()
	plain.set_script(TERRAIN)
	plain.raw_path = "res://terrain/island.r16"
	plain.world_size = 620.0
	plain.height_scale = 180.0
	root.add_child(plain)
	await process_frame

	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	root.add_child(terrain)
	await process_frame
	# A rectangle turned 27 degrees with a 0.5 m fade, 6 m up; an oval turned the other way
	# with a 0.75 m fade, 4 m up. Both on land, well apart.
	var rect := _pad(TerrainStamp.Shape.SOFT_RECT, Vector3(60.0, 0.0, -20.0), 12.0, 8.0, 0.5, 6.0, 27.0, plain)
	var oval := _pad(TerrainStamp.Shape.SOFT_CIRCLE, Vector3(-40.0, 0.0, 70.0), 16.0, 10.0, 0.75, 4.0, -40.0, plain)
	terrain.add_child(rect)
	terrain.add_child(oval)
	for i in 2:
		await process_frame
	var started := Time.get_ticks_msec()
	terrain.generate()
	print("built with two sharp pads in %d ms" % (Time.get_ticks_msec() - started))
	for i in 3:
		await physics_frame
	_space = terrain.get_world_3d().direct_space_state

	for pad: TerrainStamp in [rect, oval]:
		_check_pad(pad, terrain, plain)

	# And the switch: with cut_edges off the same pads are drawn from the height field alone -
	# no vertex on either crest, and the crest no longer exactly at the plane.
	terrain.cut_edges = false
	terrain.generate()
	for i in 3:
		await physics_frame
	for pad: TerrainStamp in [rect, oval]:
		var on_crest := 0
		for chunk in terrain._chunks:
			if chunk.mesh == null or chunk.mesh.get_surface_count() == 0:
				continue
			for v in chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				if absf(pad.edge_distance(v.x, v.z)) < 0.002:
					on_crest += 1
		var worst := 0.0
		for p in _along_outline(pad, -0.05, 64):
			var hit := _drop(p)
			if not hit.is_empty():
				worst = maxf(worst, absf(hit.position.y - pad.global_position.y))
		print("%s with cut_edges off: %d vertices on the crest, crest up to %.2f m off the plane" % [pad.name, on_crest, worst])
		check(on_crest == 0, "%s: cut_edges is off but %d vertices still lie on the crest" % [pad.name, on_crest])
		check(worst > 0.1, "%s: cut_edges is off but the crest is still on the plane - the switch does nothing" % pad.name)

	print("pad_edge_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _pad(shape: TerrainStamp.Shape, at: Vector3, length: float, width: float, softness: float,
		lift: float, degrees: float, plain: Node3D) -> TerrainStamp:
	var pad := STAMP.instantiate() as TerrainStamp
	pad.name = "Rect" if shape == TerrainStamp.Shape.SOFT_RECT else "Oval"
	pad.mode = TerrainStamp.Mode.FLATTEN
	pad.shape = shape
	pad.length = length
	pad.width = width
	pad.edge_softness = softness
	pad.position = Vector3(at.x, plain.height_at(at.x, at.z) + lift, at.z)
	pad.rotation.y = deg_to_rad(degrees)
	return pad


## Points along the outline at a given distance out from it, in world space: the rectangle's
## sides or the oval's rim, sampled every half metre or so.
func _along_outline(pad: TerrainStamp, out: float, count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var half_l := pad.length * 0.5
	var half_w := pad.width * 0.5
	for i in count:
		var local: Vector3
		if pad.shape == TerrainStamp.Shape.SOFT_RECT:
			# round the four sides, then push straight out from the side
			var s := float(i) / count * 4.0
			var side := int(s)
			var f := s - side
			match side:
				0: local = Vector3(lerpf(-half_l, half_l, f), 0.0, -half_w - out)
				1: local = Vector3(half_l + out, 0.0, lerpf(-half_w, half_w, f))
				2: local = Vector3(lerpf(half_l, -half_l, f), 0.0, half_w + out)
				3: local = Vector3(-half_l - out, 0.0, lerpf(half_w, -half_w, f))
		else:
			# straight out from the rim, along its normal
			var angle := TAU * i / count
			var rim := Vector2(cos(angle) * half_l, sin(angle) * half_w)
			var normal := Vector2(cos(angle) / half_l, sin(angle) / half_w).normalized()
			var point := rim + normal * out
			local = Vector3(point.x, 0.0, point.y)
		points.append(pad.global_transform * local)
	return points


func _check_pad(pad: TerrainStamp, terrain: Node3D, plain: Node3D) -> void:
	var plane := pad.global_position.y
	# The crest: a hand's width inside the outline, where the pad is at full strength.
	var crest := _along_outline(pad, -0.05, 64)
	var crest_worst := 0.0
	var crest_ground := 0.0
	var crest_missing := 0
	var worst_at := ""
	for i in crest.size():
		var p := crest[i]
		var hit := _drop(p)
		if hit.is_empty():
			crest_missing += 1
			continue
		var off := absf(hit.position.y - plane)
		if off > crest_worst:
			crest_worst = off
			worst_at = "point %d at %s, hit shape %s at y %.2f, height_at %.2f" % [i, p.round(), hit.shape, hit.position.y, terrain.height_at(p.x, p.z)]
		crest_ground = maxf(crest_ground, absf(plain.height_at(p.x, p.z) - plane))
	print("%s crest: %d points, worst %.3f m off the plane (the natural ground is up to %.1f m off it)%s"
			% [pad.name, crest.size(), crest_worst, crest_ground, "" if crest_worst < 0.03 else "
    worst: " + worst_at])
	check(crest_missing == 0, "%s: %d crest points found no collider" % [pad.name, crest_missing])
	check(crest_worst < 0.03, "%s crest is %.3f m off the plane somewhere" % [pad.name, crest_worst])
	check(crest_ground > 1.0, "%s: the natural ground is already at the plane - the check proves nothing" % pad.name)

	# The foot: a hand's width past the end of the fade, back on natural ground.
	var foot := _along_outline(pad, pad.edge_softness + 0.05, 64)
	var foot_worst := 0.0
	var foot_missing := 0
	var foot_at := ""
	for i in foot.size():
		var p := foot[i]
		var hit := _drop(p)
		if hit.is_empty():
			foot_missing += 1
			continue
		var off := absf(hit.position.y - plain.height_at(p.x, p.z))
		if off > foot_worst:
			foot_worst = off
			foot_at = "point %d at %s, d %.3f, hit y %.2f, plain %.2f, height_at %.2f" % [i, p, pad.edge_distance(p.x, p.z), hit.position.y, plain.height_at(p.x, p.z), terrain.height_at(p.x, p.z)]
	# Loosely by ray: the collider there is the mesh, which chords the natural ground between
	# vertices by a few tens of centimetres on rough ground - so the exact check is on the
	# mesh's own foot vertices, below.
	print("%s foot: rays worst %.3f m off the natural ground%s" % [pad.name, foot_worst, "" if foot_worst < 0.45 else "
    worst: " + foot_at])
	check(foot_missing == 0, "%s: %d foot points found no collider" % [pad.name, foot_missing])
	check(foot_worst < 0.45, "%s foot is %.3f m off the natural ground somewhere" % [pad.name, foot_worst])

	# Halfway down the wall: on the stamp's own fade, as near as flat triangles can draw it.
	# The bank is the ground lifted towards the plane, so where the ground climbs along the
	# bank the bank is twisted, and a flat triangle across a twisted patch is off by up to a
	# quarter of the ground's rise across the cell (plus the cell's own twist, which the plain
	# ground's triangles have too). On the steep hillside the rectangle stands on that is a few
	# tenths of a metre at mid-bank; on level ground it is nothing. A curved crest is drawn as
	# chords within a centimetre of the curve, and a centimetre sideways on the bank is a
	# centimetre times the bank's slope in height.
	var wall := _along_outline(pad, pad.edge_softness * 0.5, 64)
	var wall_worst := 0.0
	var wall_over := 0
	var wall_missing := 0
	var wall_at := ""
	for i in wall.size():
		var p := wall[i]
		var hit := _drop(p)
		if hit.is_empty():
			wall_missing += 1
			continue
		var off := absf(hit.position.y - terrain.height_at(p.x, p.z))
		var allowed := 0.03 + _twist_bound(p, plain)
		if pad.shape != TerrainStamp.Shape.SOFT_RECT:
			allowed += 0.01 * absf(plane - plain.height_at(p.x, p.z)) / pad.edge_softness
		if off > allowed:
			wall_over += 1
		if off > wall_worst:
			wall_worst = off
			wall_at = "point %d at %s, d %.3f, hit y %.2f, height_at %.2f, plain %.2f, allowed %.3f" % [i, p.round(),
					pad.edge_distance(p.x, p.z), hit.position.y, terrain.height_at(p.x, p.z), plain.height_at(p.x, p.z), allowed]
	print("%s wall: worst %.3f m off the fade, %d points further off than flat triangles allow%s"
			% [pad.name, wall_worst, wall_over, "" if wall_over == 0 else "\n    worst: " + wall_at])
	check(wall_missing == 0, "%s: %d wall points found no collider" % [pad.name, wall_missing])
	check(wall_over == 0, "%s wall is further off the fade than flat triangles account for at %d points" % [pad.name, wall_over])

	# And the mesh itself: vertices on the crest line, all at the plane; vertices on the foot
	# line, all on the natural ground.
	var on_crest := 0
	var off_plane := 0
	var on_foot := 0
	var off_ground := 0
	for chunk in terrain._chunks:
		if chunk.mesh == null or chunk.mesh.get_surface_count() == 0:
			continue
		for v in chunk.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var d: float = pad.edge_distance(v.x, v.z)
			if absf(d) < 0.002:
				on_crest += 1
				if absf(v.y - plane) > 0.01:
					off_plane += 1
			elif absf(d - pad.edge_softness) < 0.002:
				on_foot += 1
				if absf(v.y - plain.height_at(v.x, v.z)) > 0.01:
					off_ground += 1
					if off_ground <= 4:
						print("    foot vertex off: %s d %.4f, y %.3f, plain %.3f, terrain %.3f" % [v, d, v.y, plain.height_at(v.x, v.z), terrain.height_at(v.x, v.z)])
	print("%s mesh: %d vertices on the crest line (%d off the plane), %d on the foot line (%d off the ground)"
			% [pad.name, on_crest, off_plane, on_foot, off_ground])
	check(on_crest >= 20, "%s: only %d mesh vertices lie on the crest - it was not cut" % [pad.name, on_crest])
	check(off_plane == 0, "%s: %d crest vertices are not at the plane" % [pad.name, off_plane])
	check(on_foot >= 20, "%s: only %d mesh vertices lie on the foot line" % [pad.name, on_foot])
	check(off_ground == 0, "%s: %d foot vertices are not on the natural ground" % [pad.name, off_ground])


## How far a flat triangle in a cut cell may sit from the bank's true surface at p: a quarter
## of the ground's rise across the cell, from the bank's twist (the plane's weight and the
## ground both change across the triangle, and their product is not flat), plus the cell's own
## twist, which the ground's bilinear surface has and no triangle can follow.
func _twist_bound(p: Vector3, plain: Node3D) -> float:
	var step: float = 620.0 / plain._built_resolution
	var half := 310.0
	var i := floorf((p.x + half) / step)
	var j := floorf((p.z + half) / step)
	var h00: float = plain.height_at(i * step - half, j * step - half)
	var h10: float = plain.height_at((i + 1) * step - half, j * step - half)
	var h01: float = plain.height_at(i * step - half, (j + 1) * step - half)
	var h11: float = plain.height_at((i + 1) * step - half, (j + 1) * step - half)
	var rise := maxf(maxf(h00, h10), maxf(h01, h11)) - minf(minf(h00, h10), minf(h01, h11))
	var twist := absf(h00 + h11 - h01 - h10)
	return rise * 0.25 + twist * 0.75


func _drop(p: Vector3) -> Dictionary:
	return _space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 400.0, p.z), Vector3(p.x, -100.0, p.z)))
