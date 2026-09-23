extends SceneTree
## Run: godot --headless --path . --script res://tests/guard_check.gd
##
## Blocking and parrying: does a guard turn a blow aside, does a late guard still work, does a
## guard held the wrong way work (it must not), and does a parry actually cost the attacker
## something?
##
## The last one is the whole reason to parry rather than block. If it only negates damage it
## is a block with better timing, and nobody would take the risk.

## Held down before the blow lands. Anything under the captain's parry_window is a parry.
const PARRY_AT := 0.05
const BLOCK_AT := 0.60

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
	var captain: CharacterBody3D = scene.get_node("Player")
	var grunt: CharacterBody3D = scene.get_node("Grunts").get_child(0)
	var terrain := scene.get_node("Terrain")

	# Park him where he cannot be reached, and swing at the captain by hand instead. Letting
	# the AI do it makes the timing of the blow something this test does not control, and the
	# timing is the entire subject.
	var at: Vector3 = captain.global_position
	grunt.global_position = at + Vector3(0.0, 0.3, 1.0)
	grunt.set_physics_process(false)
	captain._body.rotation.y = 0.0     # facing +Z, at the grunt
	for i in 30:
		await physics_frame

	print("%-22s %6s %8s %9s %s" % ["case", "hp", "blocked", "parried", "shove on attacker"])
	var open := await _blow(captain, grunt, -1.0, true)
	var parry := await _blow(captain, grunt, PARRY_AT, true)
	var block := await _blow(captain, grunt, BLOCK_AT, true)
	var behind := await _blow(captain, grunt, PARRY_AT, false)

	check(open["lost"] > 0, "an unguarded blow took nothing off him")
	check(parry["lost"] == 0, "a parried blow still cost him %d hp" % parry["lost"])
	check(block["lost"] == 0, "a blocked blow still cost him %d hp" % block["lost"])
	check(behind["lost"] > 0,
			"a guard held facing away still turned the blow aside - it is a bubble, not a guard")

	check(parry["parried"] and not parry["blocked"],
			"the early guard reported a block rather than a parry")
	check(block["blocked"] and not block["parried"],
			"the late guard reported a parry - the window is not closing")
	# The point of the whole thing.
	check(parry["knocked"] > 0.1,
			"the parry put no shove on the attacker (%.2f m/s) - it is only a block with"
			% parry["knocked"] + " better timing, and nobody would take the risk")
	check(block["knocked"] <= 0.1,
			"an ordinary block shoved the attacker at %.2f m/s, which is the parry's job"
			% block["knocked"])

	# What he LOOKS like while guarding. There is no block clip yet, so this really asks what
	# the animation falls back to - and the answer was the walk cycle, played on the spot,
	# because the fallback order was shared with every other state. Pressed through the real
	# action rather than poking _guarding, because holding it across frames is the point.
	Input.action_press("guard")
	for i in 20:
		await physics_frame
	var posed: String = captain._clips.current()
	Input.action_release("guard")
	print("%-22s %6s" % ["guard pose clip", posed])
	check(posed == captain.clip_block or posed == captain.clip_idle,
			"guarding on the spot plays '%s' - with no block clip the fallback has to be idle,"
			% posed + " not a walk cycle on the spot")

	print("guard check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


## One blow at the captain. `guard_for` is how long the guard has been up when it lands, or
## -1 for no guard at all. `facing` false turns him away first.
func _blow(captain: CharacterBody3D, grunt: CharacterBody3D, guard_for: float,
		facing: bool) -> Dictionary:
	captain._guarding = false
	captain._guard_time = 0.0
	captain._body.rotation.y = 0.0 if facing else PI
	# Out of any immunity left from the blow before.
	for i in 60:
		await physics_frame

	var caught := {"blocked": false, "parried": false}
	var on_block := func(_a: Node) -> void: caught["blocked"] = true
	var on_parry := func(_a: Node) -> void: caught["parried"] = true
	captain.blocked.connect(on_block)
	captain.parried.connect(on_parry)

	if guard_for >= 0.0:
		captain._guarding = true
		captain._guard_time = guard_for

	var before: int = captain.health()
	# Read off the attacker's Knockback rather than watching him move. He has physics turned
	# off for this test so the shove is applied and never travels - measuring the displacement
	# measured the test's own setup and reported every parry as doing nothing.
	var shove: Knockback = grunt.get_node("Knockback")
	# Wiped first. With his physics off the component never ticks, so a shove from an earlier
	# blow sits there forever and every case after the first parry read 3.60 m/s - the same
	# leftover, reported four times as a result.
	shove.clear()
	captain.take_damage(1, grunt)
	await physics_frame
	var moved: float = shove.shove().length()

	captain.blocked.disconnect(on_block)
	captain.parried.disconnect(on_parry)
	var label := "no guard" if guard_for < 0.0 else (
			"guard %.2fs%s" % [guard_for, "" if facing else ", facing away"])
	print("%-22s %6d %8s %9s %8.2f m/s" % [label, captain.health(), caught["blocked"],
			caught["parried"], moved])
	return {"lost": before - captain.health(), "blocked": caught["blocked"],
			"parried": caught["parried"], "knocked": moved}
