extends SceneTree
## Run: godot --headless --path . --script res://tests/step_check.gd
##
## Does the captain walk up a low ledge, and still stop at a wall?
##
## A CharacterBody3D only climbs slopes, so every vertical edge used to be a wall to him. The one
## that found it was the rock arch: its stone floor sits 0.28 m above the ground in front, and he
## stopped at its lip and could not get into the cave.
##
## Built on a platform high above the island, out of reach of everything else, with the grunts
## left out - a walk that ends in a fight measures the fight, not the feet:
##
##   lane 1   a 0.28 m ledge, the arch's, then a second of 0.30 m. Both must be climbed.
##   lane 2   a 0.60 m wall. He must stop at it, on the ground, not be lifted onto it.
##   control  lane 1 again with step_height 0, which must stop at the first ledge.

const PLATFORM_Y := 400.0

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	scene.enemy_count = 0
	root.add_child(scene)
	for i in 30:
		await physics_frame
	var player := scene.get_node("Player") as CharacterBody3D
	var touch := scene.get_node("TouchControls")
	# Stick input is camera-relative; with the rig unturned, the stick's x/y are world x/z.
	(scene.get_node("CameraRig") as Node3D).rotation.y = 0.0

	_box(scene, Vector3(0, PLATFORM_Y - 0.5, 0), Vector3(40, 1, 40))
	# lane 1, along +x at z = 0
	_box(scene, Vector3(6, PLATFORM_Y + 0.14, 0), Vector3(4, 0.28, 3))
	# long enough that 3 s of walking ends on it rather than off its far edge
	_box(scene, Vector3(16, PLATFORM_Y + 0.29, 0), Vector3(16, 0.58, 3))
	# lane 2, along +x at z = 10
	_box(scene, Vector3(6, PLATFORM_Y + 0.30, 10), Vector3(2, 0.60, 3))

	var climbed := await _walk(player, touch, Vector3(0, PLATFORM_Y + 0.1, 0), 3.0)
	print("ledges: ended at x %.2f, feet %.2f m above the platform (two ledges make 0.58)"
			% [climbed.x, climbed.y - PLATFORM_Y])
	check(climbed.x > 10.0, "stopped at x %.2f - a ledge he should have walked up" % climbed.x)
	check(absf(climbed.y - PLATFORM_Y - 0.58) < 0.08,
			"feet %.2f m up, not on the second ledge at 0.58" % (climbed.y - PLATFORM_Y))

	var walled := await _walk(player, touch, Vector3(0, PLATFORM_Y + 0.1, 10), 3.0)
	print("wall: ended at x %.2f, feet %.2f m above the platform (wall face at x 5.0)"
			% [walled.x, walled.y - PLATFORM_Y])
	check(walled.x < 5.0, "went past a 0.6 m wall (x %.2f)" % walled.x)
	check(absf(walled.y - PLATFORM_Y) < 0.08, "lifted %.2f m at a wall he should not climb"
			% (walled.y - PLATFORM_Y))

	# The control: the same lane with stepping off must stop at the first ledge, or this check
	# would pass on a captain who never needed the step-up at all.
	var step: float = player.step_height
	player.step_height = 0.0
	var unaided := await _walk(player, touch, Vector3(0, PLATFORM_Y + 0.1, 0), 3.0)
	player.step_height = step
	print("control, step_height 0: ended at x %.2f (first ledge face at x 4.0)" % unaided.x)
	check(unaided.x < 4.0, "walked up the ledge with stepping off (x %.2f) - the check proves nothing" % unaided.x)

	print("step_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


## Puts him at `start`, lets him settle, then holds the stick towards +x for `seconds`.
func _walk(player: CharacterBody3D, touch: Node, start: Vector3, seconds: float) -> Vector3:
	player.global_position = start
	player.velocity = Vector3.ZERO
	for i in 20:
		await physics_frame
	touch.move = Vector2(1, 0)
	for i in int(seconds * 60.0):
		await physics_frame
	touch.move = Vector2.ZERO
	for i in 20:
		await physics_frame
	return player.global_position


func _box(parent: Node, centre: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = centre
