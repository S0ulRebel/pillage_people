extends SceneTree
## Run: godot --headless --path . --script res://tests/shore_field_check.gd
##
## The shore distance field (world/shore_field.gd) against the ground itself, at points all
## round the island. For each point, whatever the field says:
##   - its sign is which side of the waterline the ground is on (sea +, land -);
##   - the nearest shore point it names is on the waterline, the stated distance away;
##   - nothing on a circle a little smaller than that distance is across the waterline - so no
##     closer shore was missed;
##   - the straight line to that shore point doesn't cross the waterline on the way.
## Points within a sample or two of the waterline, where the ground is only known to the
## height map's spacing, are held to that spacing rather than to centimetres.

const ShoreField = preload("res://world/shore_field.gd")
const POINTS := 600
## Metres of disagreement allowed: about one field texel. The field reads the height map at
## its sample spacing (1.2 m), and height_at() interpolates between samples, so the two agree
## on where the waterline is to about that.
const SLACK := 1.3
## The field is read out to this far from the shore; beyond it only the sign is checked.
const REACH := 60.0

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	_failures += 1
	if _failures <= 12:
		push_error(message)


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var terrain := scene.get_node("Terrain")
	var field: ShoreField = terrain.shore_field()
	if field == null:
		push_error("the terrain made no shore field")
		quit(1)
		return
	var sea: float = terrain.sea_level()
	var half: float = terrain.world_size * 0.5
	print("shore field: %d texels a side, %.2f m apart, %d ms to bake" % [int(field.rect.w),
			field.rect.z, field.bake_msec])
	# Waterline ground: height_at against the sea, and how steep it is there, since on a
	# steep shore a small height error is a small distance error and on a flat one a big one.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var checked := 0
	var near_shore := 0
	var worst := 0.0
	for n in POINTS:
		var p := Vector2(rng.randf_range(-half * 0.9, half * 0.9), rng.randf_range(-half * 0.9, half * 0.9))
		var d := field.distance_at(p.x, p.y)
		var above: float = terrain.height_at(p.x, p.y) - sea
		if absf(d) > SLACK and (d > 0.0) != (above < 0.0):
			_fail("at %s the field says %.2f m but the ground is %.2f m %s the sea" % [p, d,
					absf(above), "above" if above > 0.0 else "below"])
		if absf(d) > REACH:
			continue
		checked += 1
		if absf(d) < 8.0:
			near_shore += 1
		var shore := field.nearest_shore(p.x, p.y)
		# The named shore point is on the waterline.
		var at_shore: float = terrain.height_at(shore.x, shore.y) - sea
		var slope: float = _slope(terrain, shore)
		var off := absf(at_shore) / maxf(slope, 0.02)
		if off > SLACK * 1.5:
			_fail("shore point %s for %s is %.2f m off the waterline (%.2f m of height)" % [
					shore, p, off, at_shore])
		# ... and the stated distance away.
		var gap := absf(p.distance_to(shore) - absf(d))
		worst = maxf(worst, gap)
		if gap > SLACK:
			_fail("at %s the field says %.2f m but its shore point is %.2f m away" % [p, d,
					p.distance_to(shore)])
		# No closer shore: every point on a circle a texel smaller is on this side.
		var r := absf(d) - SLACK
		if r > 0.5:
			for k in 48:
				var a := TAU * float(k) / 48.0
				var q := p + Vector2(cos(a), sin(a)) * r
				var h: float = terrain.height_at(q.x, q.y) - sea
				if (h < 0.0) != (d > 0.0) and absf(h) > 0.05:
					_fail("at %s the field says %.2f m, but %s, %.2f m away, is across the waterline" % [
							p, d, q, r])
					break
	print("checked %d points within %d m of the shore (%d within 8 m); worst distance error %.2f m"
			% [checked, int(REACH), near_shore, worst])
	if checked < POINTS / 10:
		_fail("too few points near the shore to check (%d)" % checked)
	print("shore field check: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _slope(terrain: Node, at: Vector2) -> float:
	var step := 0.6
	var dx: float = terrain.height_at(at.x + step, at.y) - terrain.height_at(at.x - step, at.y)
	var dz: float = terrain.height_at(at.x, at.y + step) - terrain.height_at(at.x, at.y - step)
	return Vector2(dx, dz).length() / (2.0 * step)
