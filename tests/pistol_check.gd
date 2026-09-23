extends SceneTree
## Run: godot --headless --path . --script res://tests/pistol_check.gd
##
## The flintlock: is it in his hand, does it reach, does it fire once, and does the reload
## actually stop him firing again.
##
## That last one is the whole weapon. A pistol with a magazine turns the cutlass into a backup,
## because ranged always beats melee when ammunition is free - so "the second click does
## nothing" is not an edge case here, it IS the design, and it is the first thing that would
## quietly stop working.

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
	var captain := scene.get_node("Player") as CharacterBody3D
	var grunt := scene.get_node("Grunts").get_child(0) as CharacterBody3D

	var gun: Gun = captain.pistol()
	check(gun != null, "the captain has no pistol - it never mounted")
	if gun == null:
		_finish()
		return
	print("pistol: mounted at %s, loaded=%s" % [str(gun.global_position).left(26),
			gun.is_loaded()])

	# Raising it is a stance, and it has to actually latch.
	check(not captain.is_aiming(), "he starts with the pistol already up")
	captain.set_aiming(true)
	check(captain.is_aiming(), "raising the pistol did nothing")

	# Stand a grunt well beyond sword reach - the whole point of carrying one.
	var here := captain.global_position
	var out := Vector3(0.0, 0.0, 1.0)
	grunt.global_position = here + out * 8.0
	grunt.global_position.y = terrain.height_at(grunt.global_position.x,
			grunt.global_position.z) + 0.3
	grunt.set_physics_process(false)
	for i in 20:
		await physics_frame

	var before: int = grunt.health()
	var aim := grunt.global_position + Vector3.UP * 0.9
	var struck: Node = captain.shoot_at(aim)
	await physics_frame
	print("shot at %.1f m: hit %s, grunt %d -> %d hp"
			% [here.distance_to(grunt.global_position),
			struck.name if struck != null else "nothing", before, grunt.health()])
	check(struck == grunt, "the ball did not reach a grunt eight metres away, in the open")
	check(grunt.health() < before, "it connected but took nothing off him")

	# And now the part that matters.
	check(not gun.is_loaded(), "it is still loaded after firing - there is only one ball")
	var after_shot: int = grunt.health()
	captain.shoot_at(aim)
	await physics_frame
	print("second shot straight away: grunt %d -> %d hp, reload %.0f%% done"
			% [after_shot, grunt.health(), gun.reload_fraction() * 100.0])
	check(grunt.health() == after_shot,
			"he fired twice without reloading - the flintlock has become a revolver")

	# Wind the reload through and check it comes back.
	var waited := 0.0
	for i in int(gun.reload_seconds * 60.0) + 40:
		await physics_frame
		waited += 1.0 / 60.0
		if gun.is_loaded():
			break
	print("reloaded after %.1f s (setting is %.1f)" % [waited, gun.reload_seconds])
	check(gun.is_loaded(), "it never reloaded")
	check(absf(waited - gun.reload_seconds) < 0.6,
			"the reload took %.1f s against a setting of %.1f" % [waited, gun.reload_seconds])

	# Lowering it should stop him firing at all.
	captain.set_aiming(false)
	var down: int = grunt.health()
	captain.shoot_at(aim)
	await physics_frame
	check(grunt.health() == down, "he fired with the pistol lowered")
	grunt.set_physics_process(true)
	_finish()


func _finish() -> void:
	print("pistol check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
