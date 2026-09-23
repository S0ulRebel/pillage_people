extends SceneTree
## Run: godot --path . --script res://tests/captain_view.gd [-- --spin]
##
## A close look at the captain, for checking how he is holding things.
##
## The cutlass has been wrong twice - once upside down, once rolled a quarter turn in his fist -
## and both times the only way to know was to look at him. A rotation that reads correctly in
## the export panel can still be wrong on the model, because which way a blade's flat faces is
## not recoverable from anything but the mesh.
##
## --spin writes four views a quarter turn apart, for when one angle cannot settle it.
## --aim raises the flintlock first, which is the only way to see whether the aiming stance
## actually points it at anything - the numbers say the hand is 28 cm out and level with the
## hips, and numbers cannot tell you which way the barrel faces.

const SHOTS := "user://captain"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	# Long enough for him to land and for the weapon's deferred fitting to have run.
	for i in 90:
		await process_frame
	var player := scene.get_node("Player") as Node3D
	# A camera of this test's own, made current, rather than borrowing the rig's. The rig
	# follows the player every frame and puts its camera back where it wants it, so anything
	# set on it here is overwritten before the frame is drawn - which produced four identical
	# long shots of the island and no captain in them.
	var camera := Camera3D.new()
	camera.fov = 32.0
	scene.add_child(camera)
	camera.make_current()

	var blade := player.find_children("Sword", "", true, false)
	print("sword nodes: ", blade.size())
	if not blade.is_empty():
		var node := blade[0] as Node3D
		print("  blade rotation ", node.rotation_degrees, " position ", node.position)

	if "--aim" in OS.get_cmdline_user_args():
		player.equip(1)
		# Long enough for the 0.15 s cross-fade into the stance to finish.
		for i in 30:
			await process_frame
		var clips: Clips = player.get_node("Clips")
		print("  aiming, playing '%s'" % clips.current())

	DirAccess.make_dir_recursive_absolute(SHOTS)
	# Chest height, a couple of metres out - close enough that the grip is readable.
	var focus: Vector3 = player.global_position + Vector3.UP * 1.05
	var angles := [0.0]
	if "--spin" in OS.get_cmdline_user_args():
		angles = [0.0, 90.0, 180.0, 270.0]
	for angle in angles:
		var away := Vector3(sin(deg_to_rad(angle)), 0.22, cos(deg_to_rad(angle))) * 2.6
		camera.global_position = focus + away
		camera.look_at(focus, Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var tag := "aim" if "--aim" in OS.get_cmdline_user_args() else "captain"
		get_root().get_texture().get_image().save_png("%s/%s_%03d.png" % [SHOTS, tag, int(angle)])
		print("  view at %d degrees" % int(angle))
	print("captain view: ", ProjectSettings.globalize_path(SHOTS))
	quit()
