extends SceneTree
## Run: godot --path . --script res://tests/spyglass_view.gd
##
## Renders the iris at a spread of openness values, so the effect can be looked at rather than
## reasoned about. Not headless: there is no renderer under --headless and every frame would
## come back blank.

const SHOTS := "user://spyglass"
const STAGES := [0.0, 0.15, 0.35, 0.7, 1.2, 1.7, 2.29]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 60:
		await process_frame
	var glass: Spyglass = scene.get_node_or_null("Spyglass")
	if glass == null:
		print("no Spyglass in the scene")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(SHOTS)
	for stage in STAGES:
		glass.snap(true)
		glass._set_openness(stage)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var image := get_root().get_texture().get_image()
		image.save_png("%s/iris_%03d.png" % [SHOTS, int(stage * 100.0)])
		print("  openness %.2f" % stage)
	print("spyglass views: ", ProjectSettings.globalize_path(SHOTS))
	quit(0)
