extends SceneTree
## Run: godot --headless --path . --script res://tests/combat_check.gd
##
## Measures what being hit actually does, for the captain and for a grunt.
##
## This is the test that was missing. The captain and the grunt grew their own knockback
## separately and disagreed by five times - he flew 2.31 m from a hit a grunt took for 0.43 -
## and nothing caught it, because nothing measured it. Counting grunts and checking that the
## island reloads says nothing about how far a hit throws you.
##
## So: hit each of them from a known direction on flat ground, and report how far they went and
## how long they could not steer. The numbers are printed whatever happens, because the point is
## to be able to SEE the two side by side; the checks only fail when they disagree by more than
## a stated factor, or when a hit does nothing at all.

## How far apart the two are allowed to be before it counts as drift again. Not 1.0: they are
## deliberately different - the captain is shoved harder and recovers faster, because losing
## control of your own character is more irritating than watching someone else lose theirs.
const DRIFT_LIMIT := 2.5

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
	for i in 30:
		await physics_frame
	var terrain := scene.get_node("Terrain")
	var captain := scene.get_node("Player") as CharacterBody3D
	var band := scene.get_node_or_null("Grunts")
	check(band != null and band.get_child_count() > 0, "no grunts to measure")
	if band == null or band.get_child_count() == 0:
		_finish()
		return
	var grunt := band.get_child(0) as CharacterBody3D

	print("%-9s %8s %8s %9s %8s" % ["who", "hp", "shoved", "settled", "stunned"])
	var cap := await _hit(captain, terrain, Vector3(40.0, 0.0, 40.0))
	var gru := await _hit(grunt, terrain, Vector3(-40.0, 0.0, 40.0))

	for who in [cap, gru]:
		check(who["shoved"] > 0.15,
				"%s barely moves when hit (%.2f m) - the knockback is doing nothing"
				% [who["who"], who["shoved"]])
		check(who["stunned"] > 0.05,
				"%s is never stunned - being hit takes no control away" % who["who"])

	# The drift check: the same idea implemented twice is how this went wrong before.
	var ratio: float = maxf(cap["shoved"], gru["shoved"]) / maxf(minf(cap["shoved"],
			gru["shoved"]), 0.001)
	print("knockback ratio captain:grunt = %.2f (limit %.1f)" % [ratio, DRIFT_LIMIT])
	check(ratio <= DRIFT_LIMIT,
			"captain and grunt knockback have drifted apart by %.1fx - they were two"
			% ratio + " implementations of one idea once before")
	_finish()


## Puts `body` on flat ground, hits it from a fixed bearing, and follows it until it stops.
func _hit(body: CharacterBody3D, terrain: Node, at: Vector3) -> Dictionary:
	var ground: float = terrain.height_at(at.x, at.z)
	body.global_position = Vector3(at.x, ground + 0.2, at.z)
	body.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame

	# The attacker stands a metre away, so the shove has an unambiguous direction.
	var attacker := Node3D.new()
	current_scene.add_child(attacker)
	attacker.global_position = body.global_position + Vector3(1.0, 0.0, 0.0)

	var before := body.global_position
	var health_before: int = body.health()
	body.take_damage(1, attacker)

	var furthest := 0.0
	var stunned := 0.0
	# Two seconds is long after either of them has come to rest.
	for i in 120:
		await physics_frame
		var flat := body.global_position - before
		flat.y = 0.0
		furthest = maxf(furthest, flat.length())
		if _staggered(body):
			stunned += 1.0 / float(Engine.physics_ticks_per_second)
	var settled := body.global_position - before
	settled.y = 0.0
	attacker.queue_free()

	var who := "captain" if body.get_parent() == current_scene else "grunt"
	print("%-9s %3d->%-4d %7.2fm %8.2fm %7.2fs"
			% [who, health_before, body.health(), furthest, settled.length(), stunned])
	return {"who": who, "shoved": furthest, "settled": settled.length(), "stunned": stunned}


## Whether this one has had the controls taken away. Asked through whatever the body exposes,
## so it keeps working when the state moves into a component.
func _staggered(body: Node) -> bool:
	if body.has_method("is_staggered"):
		return body.is_staggered()
	return body.get("_stagger") != null and float(body.get("_stagger")) > 0.0


func _finish() -> void:
	print("combat check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
