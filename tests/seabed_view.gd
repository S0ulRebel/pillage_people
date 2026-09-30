extends SceneTree
## Run: D:\Godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/seabed_view.gd
##
## Photographs the edge of the detailed ground - the Terrain's 620 m square, where the island
## stamp fades into the Seabed and the far seabed takes over - from everywhere it could show:
## from high above, over the square's corner, from the ship's deck, from the beach, and under
## water across the edge and at a corner. A seam there is a line in the sea's colour from above
## and a step or a gap in the bed from below; both are things to look at, so this takes the
## pictures and says where it put them. Not headless - no renderer there.

const SHOTS := "user://seabed"

## Where each picture is taken from and what it looks at, world metres, and what their heights
## are measured from: the sea level, or for the dives the ground under each point, so the camera
## swims a couple of metres over the bed whatever the bed does.
const VIEWS := [
	["above", Vector3(0.0, 420.0, 720.0), Vector3(0.0, 0.0, 120.0), "sea"],
	["corner", Vector3(390.0, 110.0, 390.0), Vector3(300.0, -10.0, 300.0), "sea"],
	["ship", Vector3(176.0, 5.0, -128.0), Vector3(700.0, 0.0, -420.0), "sea"],
	["beach", Vector3(140.0, 3.0, -95.0), Vector3(640.0, 0.0, -300.0), "sea"],
	["dive_edge", Vector3(282.0, 2.5, 40.0), Vector3(360.0, 0.5, 44.0), "ground"],
	["dive_corner", Vector3(286.0, 2.5, 286.0), Vector3(370.0, 0.5, 370.0), "ground"],
	["dive_far", Vector3(420.0, 3.0, 20.0), Vector3(520.0, 0.0, 30.0), "ground"],
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("seabed views need a renderer")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
	for hud in ["HUD", "TouchControls", "Spyglass", "GlassView"]:
		var node := scene.get_node_or_null(hud)
		if node != null:
			node.hide()
	scene.get_node("Player").set_physics_process(false)
	# Everything that moves between placing the camera and reading the picture back is held:
	# the swell, the wind that leans it, and the day clock that turns the sun.
	var ocean := scene.get_node("Ocean") as Ocean
	ocean.wave_speed = 0.0
	for still in ["Day", "Wind"]:
		var node := scene.get_node_or_null(still)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
	var terrain := scene.get_node("Terrain")
	var sea: float = terrain.sea_level()
	DirAccess.make_dir_recursive_absolute(SHOTS)

	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 60.0
	camera.far = 1000.0
	camera.current = true
	for view in VIEWS:
		var from: Vector3 = view[1]
		var to: Vector3 = view[2]
		if view[3] == "ground":
			from.y += terrain.height_at(from.x, from.z)
			to.y += terrain.height_at(to.x, to.z)
		else:
			from.y += sea
			to.y += sea
		camera.global_position = from
		camera.look_at(to, Vector3.UP)
		for i in 12:
			await process_frame
		var path: String = SHOTS + "/" + view[0] + ".png"
		root.get_texture().get_image().save_png(path)
		print("seabed view %s: %s" % [view[0], ProjectSettings.globalize_path(path)])
	quit(0)
