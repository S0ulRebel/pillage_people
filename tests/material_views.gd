extends SceneTree
## Render fixed-time coastal/shoreline views and prove shadows and caustics affect pixels.
## godot --path . --script res://tests/material_views.gd
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _capture(label: String) -> Image:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	var error := result.save_png("user://" + label + ".png")
	if error != OK:
		failures += 1
		push_error("Could not save " + label)
	print("capture: ", ProjectSettings.globalize_path("user://" + label + ".png"))
	return result

func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 1
	return count

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Material views require a rendering display.")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	var terrain := scene.get_node("Terrain")
	var ocean := scene.get_node("Ocean")
	var sun := scene.get_node("Sun") as DirectionalLight3D
	var study := scene.get_node("CoastalStudy")
	# Hold the sun where the scene put it: these captures are compared with each other and
	# with earlier runs, and the day clock would move the light between them.
	var day := scene.get_node_or_null("Day")
	if day != null:
		day.set_process(false)
		day.set_physics_process(false)
	scene.get_node("HUD").hide()
	scene.get_node("TouchControls").hide()
	terrain.material.set_shader_parameter("preview_time", 4.0)
	ocean.material.set_shader_parameter("preview_time", 4.0)
	for i in 120:
		await physics_frame
	scene.get_node("Player").set_physics_process(false)
	var camera: Camera3D = study.show_camera()
	terrain.material.set_shader_parameter("palette_preview", true)
	ocean.hide()
	await _capture("ground_palette")
	terrain.material.set_shader_parameter("palette_preview", false)
	ocean.show()
	var lit := await _capture("coastal_lighting")
	sun.shadow_enabled = false
	var no_shadows := await _capture("coastal_no_shadows")
	var shadow_pixels := _difference(lit, no_shadows)
	print("shadow changed samples: ", shadow_pixels)
	if shadow_pixels < 100:
		failures += 1
		push_error("Cast shadows did not affect enough pixels")
	sun.shadow_enabled = true
	var shore: Vector3 = study.anchor
	for step in range(1, 80):
		var p: Vector3 = study.anchor - study.inland * float(step)
		if terrain.height_at(p.x, p.z) <= terrain.sea_level() - 0.7:
			shore = Vector3(p.x, terrain.sea_level(), p.z)
			break
	camera.global_position = shore - study.inland * 9.0 + Vector3.UP * 19.0
	camera.look_at(shore + study.inland * 2.0)
	camera.fov = 58.0
	var caustics := await _capture("shore_materials")
	terrain.material.set_shader_parameter("caustic_strength", 0.0)
	var no_caustics := await _capture("shore_no_caustics")
	var caustic_pixels := _difference(caustics, no_caustics)
	print("caustic changed samples: ", caustic_pixels)
	if caustic_pixels < 100:
		failures += 1
		push_error("Caustics are not visible through the water")
	terrain.material.set_shader_parameter("caustic_strength", terrain.caustic_strength)
	camera.global_position = shore - study.inland * 20.0 + Vector3.UP * 5.0
	camera.look_at(shore + study.inland * 30.0 + Vector3.UP * 2.0)
	await _capture("shore_low")
	print("material views: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
