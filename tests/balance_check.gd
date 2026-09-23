extends SceneTree
## Run: godot --headless --path . --script res://tests/balance_check.gd
##
## Is a fight a fight? Run twice: the captain against one grunt, and against all five at once.
##
## This exists because a correctness fix wrecked the balance and nothing noticed. Giving his
## swing a reach that works took him from "loses to one grunt" to "kills five in three swings
## without being touched", and both of those are numbers, not opinions - so they belong in a
## test rather than in somebody's memory of how the last playthrough went.
##
## The bands are deliberately wide. This is a physics fight with AI in it and it will never
## repeat exactly; what it can catch is a change that makes one grunt harmless or five of them
## a formality.

## One grunt should go down, and take a few swings doing it.
##
## Note what is NOT asserted: that it costs him health. It does not, and that is fine - a
## captain should beat a single mook, and the threat is meant to come from numbers. The
## simulated player here is also the best case, facing perfectly and swinging the instant the
## cooldown allows; a real one is slower and will get hit.
const SOLO_MIN_SWINGS := 2
const SOLO_MAX_SWINGS := 12
## Five at once should be genuinely dangerous - he must not walk away untouched - but still
## winnable, so the blade has to account for at least one of them.
const SWARM_MAX_HP := 3
const SWARM_MIN_KILLS := 1

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	# A fresh island per fight. Sharing one meant the grunts killed in the first fight were
	# still dead in the second, so "five at once" was really four, and the captain carried his
	# wounds across - revive() does nothing unless he actually died. Two builds is slower and
	# is the only way the second number means anything.
	var solo := await _fight(1)
	print("one grunt : %d swings, %.1fs -> %d of 1 left, captain %d/5"
			% [solo["swings"], solo["seconds"], solo["left"], solo["hp"]])
	check(solo["left"] == 0, "he could not kill a single grunt in %.0f seconds"
			% solo["seconds"])
	check(solo["swings"] >= SOLO_MIN_SWINGS,
			"one grunt went down in %d swings - the blade is hitting too hard"
			% solo["swings"])
	check(solo["swings"] <= SOLO_MAX_SWINGS,
			"one grunt took %d swings - either the blade is missing or it does nothing"
			% solo["swings"])

	var swarm := await _fight(5)
	print("five at once: %d swings, %.1fs -> %d of 5 left, captain %d/5 dead=%s"
			% [swarm["swings"], swarm["seconds"], swarm["left"], swarm["hp"], swarm["dead"]])
	check(swarm["hp"] <= SWARM_MAX_HP or swarm["dead"],
			"five grunts at once left him on %d/5 - a crowd is not a threat" % swarm["hp"])
	check(5 - swarm["left"] >= SWARM_MIN_KILLS,
			"he died to five grunts without taking one of them with him - being surrounded"
			+ " should be dangerous, not hopeless")
	print("balance check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


## Puts `count` grunts around him and lets it play out. He swings whenever he can and always
## faces the nearest - an attentive player, not a perfect one.
func _fight(count: int) -> Dictionary:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await physics_frame
	var captain: CharacterBody3D = scene.get_node("Player")
	var band: Node3D = scene.get_node("Grunts")
	var here: Vector3 = captain.global_position
	var fighting: Array[Node3D] = []
	for i in band.get_child_count():
		var grunt: Node3D = band.get_child(i)
		if i < count and not grunt.is_dead():
			var a := TAU * float(i) / float(maxi(count, 1))
			grunt.global_position = here + Vector3(cos(a), 0.0, sin(a)) * 3.0 + Vector3.UP * 0.3
			fighting.append(grunt)
		else:
			grunt.global_position = here + Vector3(0.0, 0.0, 80.0)
	for i in 40:
		await physics_frame

	var swings := 0
	var frames := 0
	for i in 2400:
		await physics_frame
		frames += 1
		# Stopped before he dies: a dead captain reloads the scene and takes every reference in
		# this file with it. See the note in the README.
		if captain.is_dead() or captain.health() <= 1:
			break
		var nearest: Node3D = null
		var best := 999.0
		var left := 0
		for grunt in fighting:
			if grunt.is_dead():
				continue
			left += 1
			var d: float = captain.global_position.distance_to(grunt.global_position)
			if d < best:
				best = d
				nearest = grunt
		if left == 0:
			break
		var towards: Vector3 = nearest.global_position - captain.global_position
		captain._body.rotation.y = atan2(towards.x, towards.z)
		if not captain.is_attacking():
			captain.attack()
			# Counted only when the swing actually STARTED. Counting the calls counted the
			# cooldown rejections too, and reported forty-five swings in two seconds.
			if captain.is_attacking():
				swings += 1

	var standing := 0
	for grunt in fighting:
		if not grunt.is_dead():
			standing += 1
	var outcome := {"swings": swings, "seconds": frames / 60.0, "left": standing,
			"hp": captain.health(), "dead": captain.is_dead()}
	scene.queue_free()
	await process_frame
	return outcome
