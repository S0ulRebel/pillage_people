extends SceneTree
## Run: godot --headless --path . --script res://tests/clips_check.gd
##
## Checks that both characters are actually animating.
##
## Nothing measured this before, which was a gap: the clip logic could break completely and
## every other test would still pass, because they count grunts and measure distances. A
## character frozen in its rest pose walks and fights exactly as well as one that is animating.
##
## So this drives each of them through states and reads back which clip is playing.

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
	for i in 40:
		await physics_frame
	var terrain := scene.get_node("Terrain")
	var captain := scene.get_node("Player") as CharacterBody3D
	var grunt := scene.get_node("Grunts").get_child(0) as CharacterBody3D

	for who in [["captain", captain], ["grunt", grunt]]:
		var clips: Clips = (who[1] as Node).get_node_or_null("Clips")
		check(clips != null, "%s has no Clips component" % who[0])
		check(clips != null and clips.ready(),
				"%s never found an AnimationPlayer - it will stand in its rest pose" % who[0])

	var clips: Clips = captain.get_node("Clips")
	var touch := scene.get_node("TouchControls")
	var at := Vector3(40.0, 0.0, 40.0)
	captain.global_position = Vector3(at.x, terrain.height_at(at.x, at.z) + 0.2, at.z)
	captain.velocity = Vector3.ZERO
	# Wait until he is actually on the ground. Dropped in and measured straight away he is
	# still falling, and "moving" reads back as the fall clip - which differs from idle, so
	# the check below passed without ever testing walking.
	for i in 120:
		await physics_frame
		if captain.is_on_floor():
			break
	for i in 20:
		await physics_frame
	var standing := clips.current()

	# Sampled on a frame where he is both moving and ON THE GROUND. Walking away from here
	# takes him over ground that drops, and a single reading after N frames caught him
	# mid-air playing the fall clip - which is not wrong, it is just not what is being tested.
	touch.move = Vector2(0.0, -1.0)
	var walking := ""
	for i in 90:
		await physics_frame
		if captain.is_on_floor() and Vector2(captain.velocity.x, captain.velocity.z).length() > 1.0:
			walking = clips.current()
			break

	touch.move = Vector2.ZERO
	captain.attack()
	for i in 10:
		await physics_frame
	var swinging := clips.current()
	for i in 60:
		await physics_frame

	# The flintlock up, standing still. Two things can go wrong here and neither shows up
	# anywhere else: the stance can fall back to the WALK cycle and play it on the spot, and
	# a 4.03 s held clip that does not loop freezes into its last frame - which looks like
	# nothing at all until you hold the pistol up for four seconds.
	captain.equip(1)
	for i in 30:
		await physics_frame
	var aiming := clips.current()
	var aim_loops := false
	var aim_clip := clips.animation(captain.flintlock.clip_idle)
	if aim_clip != null:
		aim_loops = aim_clip.loop_mode == Animation.LOOP_LINEAR
	captain.equip(0)
	for i in 30:
		await physics_frame

	print("captain clips: standing=%s  moving=%s  swinging=%s  aiming=%s (loops=%s)"
			% [standing, walking, swinging, aiming, aim_loops])
	check(aiming == captain.flintlock.clip_idle,
			"the flintlock plays '%s', expected '%s' - a stance that falls back to the walk"
			% [aiming, captain.flintlock.clip_idle] + " cycle runs it on the spot")
	check(aim_loops,
			"the aim clip does not loop - he freezes into its last frame after %.2fs of"
			% (aim_clip.length if aim_clip != null else 0.0) + " holding the pistol up")
	check(standing != "", "the captain plays nothing at all while standing")
	check(walking != standing,
			"the captain plays '%s' whether standing or running - the clip never changes"
			% standing)
	check(walking in [captain.clip_walk, captain.clip_run],
			"moving plays '%s', expected the walk or run clip" % walking)
	check(swinging == captain.clip_attack,
			"swinging plays '%s', expected '%s'" % [swinging, captain.clip_attack])

	# And the grunt, whose set is smaller but must still change.
	var gclips: Clips = grunt.get_node("Clips")
	print("grunt clips:   %s" % gclips.current())
	check(gclips.current() != "", "the grunt plays nothing at all")
	print("clips check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
