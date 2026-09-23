extends SceneTree
## Run: godot --path . --script res://tests/fish_view.gd
##
## A look at the fish, because tests/fish_check.gd cannot see them.
##
## That check can tell you the school holds together, keeps its distance, points one way and
## scatters when a shark arrives. It cannot tell you whether a fish LOOKS like a fish, and the
## swim is four rotations stacked in a vertex shader - which is exactly the kind of thing that
## produces a perfectly well-behaved school of folded paper. The shark went through three wrong
## orientations that every number agreed with.
##
## Writes a close-up, a view of the whole school, and two frames half a tail-beat apart so the
## bend can be compared against itself.

const SHOTS := "user://fish"
## Half a tail beat at the calm rate, in frames at 60 Hz.
const HALF_BEAT := 27


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 120:
		await process_frame

	var school: Node3D = scene.get_node_or_null("FishSchool0")
	if school == null:
		print("no school in the scene")
		quit(1)
		return

	# The rig's camera follows the player and puts itself back every frame, so anything set on
	# it here is overwritten before the frame is drawn - see the same note in captain_view.gd.
	var camera := Camera3D.new()
	camera.fov = 40.0
	scene.add_child(camera)
	camera.make_current()
	DirAccess.make_dir_recursive_absolute(SHOTS)

	# Close enough that one fish fills a good part of the frame. Looked at from the side, which
	# is the only angle that shows the bend travelling down the body.
	await _shot(camera, school, 1.1, 0.12, "close")
	# The shape of the school.
	await _shot(camera, school, 9.0, 0.35, "school")
	# The same close view half a beat later. If the two are identical the shader is not running;
	# if the fish is bent the same way in both, the wave is not travelling.
	for i in HALF_BEAT:
		await process_frame
	await _shot(camera, school, 1.1, 0.12, "close_half_beat")

	print("fish view: ", ProjectSettings.globalize_path(SHOTS))
	quit()


## Frames the school from `back` metres away, looking at it side-on to its heading.
func _shot(camera: Camera3D, school: Node3D, back: float, lift: float, tag: String) -> void:
	var middle: Vector3 = school.centre()
	var heading: Vector3 = school._dir[0]
	# Across the way they are swimming, so the body is seen in profile rather than end-on.
	var side := heading.cross(Vector3.UP).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	var focus: Vector3 = middle
	if tag.begins_with("close"):
		# One particular fish rather than the middle of the shoal, so the close-ups are of an
		# animal and not of the gap between four of them.
		focus = school._pos[0]
	camera.global_position = focus + side * back + Vector3.UP * back * lift
	camera.look_at(focus, Vector3.UP)
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("%s/%s.png" % [SHOTS, tag])
	print("  %s: fish at %s, camera %.1f m off" % [tag, str(focus.round()), back])
