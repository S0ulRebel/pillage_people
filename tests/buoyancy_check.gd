extends SceneTree
## Run: godot --headless --path . --script res://tests/buoyancy_check.gd
##
## Does floating cargo ride the waves, or just sit at the average?
##
## It used to sit at the average. The buoyancy measured depth against a flat plane at sea level
## while the ocean's vertex shader lifted the water into waves around it, so a barrel held one
## height while the surface visibly rose and fell past it - which reads as the barrel being
## pinned in place rather than as it floating.
##
## Proving the fix needs two numbers, not one. That the barrel moves is not enough: it would
## also move if it were slowly sinking. What matters is whether its height follows the surface
## underneath it, so this correlates the two over several seconds of waves.

## Below this the barrel is not really following the water.
const MIN_CORRELATION := 0.5
## And below this it is barely moving at all, whatever it is correlated with.
const MIN_TRAVEL := 0.02

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
	var ocean := scene.get_node("Ocean")
	var field := scene.get_node_or_null("Cargo")
	check(field != null, "no Cargo container")
	if field == null:
		_finish()
		return

	# Long enough for the pieces to stop plunging and settle at their floating depth.
	for i in 150:
		await physics_frame

	var afloat: RigidBody3D = null
	for piece in field.get_children():
		var body := piece as RigidBody3D
		if body.ocean != null and body.global_position.y < ocean.surface_y(
				body.global_position.x, body.global_position.z) + 0.5:
			afloat = body
			break
	check(afloat != null, "no cargo ended up in the water to measure")
	if afloat == null:
		_finish()
		return

	# First: does the water itself move? If the sampler is stuck the rest means nothing.
	var at := afloat.global_position
	var first: float = ocean.surface_y(at.x, at.z)
	var lowest := first
	var highest := first
	for i in 120:
		await physics_frame
		var now: float = ocean.surface_y(at.x, at.z)
		lowest = minf(lowest, now)
		highest = maxf(highest, now)
	print("surface at the barrel moves through %.3f m" % (highest - lowest))
	check(highest - lowest > MIN_TRAVEL,
			"the wave sampler is not moving (%.3f m) - the clock or the wave settings are wrong"
			% (highest - lowest))

	# Then: does the barrel follow it?
	var water: Array[float] = []
	var barrel: Array[float] = []
	for i in 240:
		await physics_frame
		var here := afloat.global_position
		water.append(ocean.surface_y(here.x, here.z))
		barrel.append(here.y)
	var swing: float = barrel.max() - barrel.min()
	var r := _correlation(water, barrel)
	print("barrel rises and falls through %.3f m" % swing)
	print("barrel vs surface correlation r = %.2f (want > %.1f)" % [r, MIN_CORRELATION])
	check(swing > MIN_TRAVEL, "the barrel barely moves (%.3f m) - it is still pinned" % swing)
	check(r > MIN_CORRELATION,
			"the barrel moves but not with the water (r = %.2f) - it is bobbing on its own"
			% r)

	# The buoyancy is a spring, and a spring driven near its own frequency builds. Overshooting
	# the wave is fine and reads as liveliness; overshooting MORE as time goes on is a barrel
	# that will eventually launch itself, so the two halves are compared rather than the total.
	var half := barrel.size() / 2
	var early: Array[float] = barrel.slice(0, half)
	var late: Array[float] = barrel.slice(half)
	var early_swing: float = early.max() - early.min()
	var late_swing: float = late.max() - late.min()
	var growth: float = late_swing / maxf(early_swing, 0.001)
	print("swing first half %.3f m, second half %.3f m (growth %.2fx)"
			% [early_swing, late_swing, growth])
	check(growth < 1.8, "the bobbing is building rather than settling (%.2fx) - the buoyancy"
			% growth + " is resonating with the waves and needs more drag")
	_finish()


func _correlation(a: Array[float], b: Array[float]) -> float:
	var n := float(a.size())
	var mean_a := 0.0
	var mean_b := 0.0
	for i in a.size():
		mean_a += a[i]
		mean_b += b[i]
	mean_a /= n
	mean_b /= n
	var cov := 0.0
	var var_a := 0.0
	var var_b := 0.0
	for i in a.size():
		var da: float = a[i] - mean_a
		var db: float = b[i] - mean_b
		cov += da * db
		var_a += da * da
		var_b += db * db
	return cov / maxf(sqrt(var_a * var_b), 0.000001)


func _finish() -> void:
	print("buoyancy check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
