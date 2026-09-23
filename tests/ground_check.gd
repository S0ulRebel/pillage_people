extends SceneTree
## Run: godot --headless --path . --script res://tests/ground_check.gd
##
## Does the floor he stands on match the ground you can see?
##
## It did not, and the way it failed is worth remembering: the collision shape was built at
## half the mesh's resolution, so its triangles chorded across the real surface. On CONVEX
## ground the chord cuts below the peak and he stands lower than the grass; on CONCAVE ground
## it cuts above and he floats. Flat ground was exact, which is why nothing noticed - every
## test measured distances on open terrain, and the captain's boots only disappeared into the
## turf on hilltops.
##
## Measured before the fix, against the 400 m map:
##
##   hilltop   mean -0.207 m   worst -1.646 m
##   flat      mean +0.004 m
##   bowl      mean +0.175 m
##
## So this samples by curvature rather than at random. An average over the whole island hides
## it completely: the peaks and the hollows cancel, and the mean across everything was about
## a centimetre while he was knee-deep on the skyline.

## How far the collision floor may sit below the visible ground on a hilltop.
##
## Not zero. The mesh chords the height map too, at the same spacing, so a few centimetres is
## the surface being made of triangles rather than a defect. It is set a little above the
## measured -0.061 m to leave room for the map changing, and far below the -0.207 m that was
## visible from the clifftop.
const SINK_ALLOWED := 0.12
## Flat ground has no excuse at all.
const FLAT_ALLOWED := 0.03

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
		await physics_frame
	var terrain := scene.get_node("Terrain")
	var space := scene.get_world_3d().direct_space_state

	var rows := {"hilltop": [], "flat": [], "bowl": []}
	var step := 1.2
	for gx in 90:
		for gz in 90:
			var x := -180.0 + float(gx) * 4.0
			var z := -180.0 + float(gz) * 4.0
			var h: float = terrain.height_at(x, z)
			# Dry land only. The seabed is not somewhere anybody stands.
			if h < terrain.sea_level() + 3.0:
				continue
			# Curvature from the four neighbours: above their average is a peak, below is a
			# hollow. Crude, and enough - the two populations separate cleanly.
			var around := 0.0
			for o in [Vector2(step, 0), Vector2(-step, 0), Vector2(0, step), Vector2(0, -step)]:
				around += terrain.height_at(x + o.x, z + o.y)
			var curve := h - around / 4.0
			var query := PhysicsRayQueryParameters3D.create(
					Vector3(x, h + 8.0, z), Vector3(x, h - 8.0, z))
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var drop: float = hit["position"].y - h
			if curve > 0.04:
				rows["hilltop"].append(drop)
			elif curve < -0.04:
				rows["bowl"].append(drop)
			else:
				rows["flat"].append(drop)

	print("%-10s %7s %9s %9s" % ["where", "count", "mean", "worst low"])
	var means := {}
	for key in ["hilltop", "flat", "bowl"]:
		var all: Array = rows[key]
		check(all.size() > 50, "only %d %s samples - the island changed shape" % [all.size(), key])
		if all.is_empty():
			continue
		var total := 0.0
		var lo := 99.0
		for v in all:
			total += v
			lo = minf(lo, v)
		means[key] = total / all.size()
		print("%-10s %7d %8.3fm %8.3fm" % [key, all.size(), means[key], lo])

	check(means.get("hilltop", -99.0) > -SINK_ALLOWED,
			"the collision floor is %.3f m below the visible ground on hilltops - his boots"
			% means.get("hilltop", 0.0)
			+ " sink into the grass on the skyline. Check collision_resolution still matches"
			+ " mesh_resolution + 1 in world/terrain.gd")
	check(absf(means.get("flat", 99.0)) < FLAT_ALLOWED,
			"flat ground is out by %.3f m, which is not a chord error - something has moved"
			% means.get("flat", 0.0))
	print("ground check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
