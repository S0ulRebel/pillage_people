extends SceneTree
## Run: godot --headless --path . --script res://tests/outline_probe.gd
##
## Finds what is putting a pale outline around distant props.
##
## Renders the same view several ways - as it ships, then with one suspect turned off at a
## time - and writes each to a PNG for measuring. Whichever change makes the halo go is the
## cause; guessing at it from a description is how you end up fixing the wrong thing.
##
## Not headless in practice: --headless has no renderer, so this opens a window off-screen.

const SHOTS := "user://outline"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 60:
		await process_frame
	var terrain := scene.get_node("Terrain")
	var rig := scene.get_node("CameraRig")
	var camera: Camera3D = rig.find_children("*", "Camera3D", true, false)[0]

	# Standing out in the water looking back at the shore, which is the view the halo was
	# reported from - props a hundred metres off and further, against the green band and the
	# sea, rather than anything close up.
	var sea: float = terrain.sea_level()
	var here := (scene.get_node("Player") as Node3D).global_position
	var inland := Vector3(0.0, sea + 6.0, 0.0)
	var out := (Vector3(here.x, 0.0, here.z) - Vector3(inland.x, 0.0, inland.z)).normalized()
	camera.set_as_top_level(true)
	camera.global_position = Vector3(here.x, sea + 1.2, here.z) + out * 120.0
	camera.look_at(inland, Vector3.UP)
	camera.far = 1200.0

	DirAccess.make_dir_recursive_absolute(SHOTS)
	var world: WorldEnvironment = scene.get_node("WorldEnvironment")
	var env: Environment = world.environment

	await _shot("shipped")

	var was_fog: bool = env.fog_enabled
	env.fog_enabled = false
	await _shot("no_fog")
	env.fog_enabled = was_fog

	var was_msaa := get_root().msaa_3d
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	await _shot("no_msaa")
	get_root().msaa_3d = was_msaa

	# Both at once, in case each alone leaves the other's share of it behind.
	env.fog_enabled = false
	get_root().msaa_3d = Viewport.MSAA_DISABLED
	await _shot("neither")

	print("outline probe: written to ", ProjectSettings.globalize_path(SHOTS))
	quit()


func _shot(tag: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, tag])
	print("  ", tag)
