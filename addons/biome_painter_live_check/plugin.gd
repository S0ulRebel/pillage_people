@tool
extends EditorPlugin
## Run: tests/biome_painter_live_check.sh
##
## Drives the real addons/biome_painter plugin - the one already running, permanently enabled
## in project.godot, found via Engine.get_meta() rather than a second instance of its own,
## which would add a second, conflicting dock - through a full paint stroke with synthetic
## input events, inside a real headless editor: EditorInterface, EditorSelection and a physics
## raycast against a real World3D all as they actually are, not stood in for.
##
## Nothing here can be reached by a plain --script test: painting needs Engine.is_editor_hint()
## and a running EditorPlugin's _forward_3d_gui_input, both editor-only, the same reason
## addons/terrain_live_check exists for stamps and tunnels.

const TERRAIN := preload("res://world/terrain.gd")
const TMP_BIOME := "res://tests/_tmp_painter_check.png"

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _enter_tree() -> void:
	_run.call_deferred()


func _mouse_button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return e


func _mouse_motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func _run() -> void:
	var tree := get_tree()
	for i in 3:
		await tree.process_frame

	check(Engine.is_editor_hint(), "not running as the editor - this proves nothing")
	check(Engine.has_meta(&"biome_painter_plugin"),
			"addons/biome_painter is not running - is it in project.godot's enabled plugins?")
	if not Engine.has_meta(&"biome_painter_plugin"):
		print("biome_painter_live_check: %d FAILED" % failures)
		tree.quit(1)
		return
	var painter: EditorPlugin = Engine.get_meta(&"biome_painter_plugin")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_BIOME))
	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	terrain.biome_path = TMP_BIOME
	tree.root.add_child(terrain)
	await tree.process_frame
	terrain.generate()
	await tree.process_frame

	var point := Vector2(60.0, -20.0)
	var height: float = terrain.height_at(point.x, point.y)
	var cam := Camera3D.new()
	tree.root.add_child(cam)
	cam.global_position = Vector3(point.x, height + 40.0, point.y + 0.001)
	cam.look_at(Vector3(point.x, height, point.y), Vector3(0, 0, -1))
	cam.fov = 45.0
	cam.current = true
	await tree.process_frame
	var screen := Vector2(640, 360)   # look_at always puts the target dead centre

	# Where the mouse ray actually lands: the same cast _paint_at does, run here first so the
	# check below knows which pixel to look at, rather than assuming the headless editor's
	# viewport is exactly the 1280x720 `screen` was chosen for.
	var space: PhysicsDirectSpaceState3D = (terrain as Node3D).get_world_3d().direct_space_state
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 4000.0
	var probe: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	check(probe.get("collider") == terrain, "the mouse ray does not hit the terrain at all - nothing below can mean anything")
	if probe.is_empty():
		print("biome_painter_live_check: %d FAILED (no ray hit)" % failures)
		tree.quit(1)
		return

	painter._enable_button.button_pressed = true
	painter._radius_slider.value = 6.0
	painter._flow_slider.value = 1.0   # one dab should already move it most of the way
	for channel in painter._channels:
		channel.check.button_pressed = channel.index == 1   # rock only
		channel.slider.value = -1.0                          # target: no rock

	# Nothing selected: painting must do nothing.
	EditorInterface.get_selection().clear()
	var before_g: float = terrain.biome_image().get_pixel(512, 512).g
	var result := painter._forward_3d_gui_input(cam, _mouse_button(screen, true))
	check(result == EditorPlugin.AFTER_GUI_INPUT_PASS,
			"a click with nothing selected should pass through, not be consumed")
	check(not painter._painting(), "a click with nothing selected should not start a stroke")
	check(is_equal_approx(terrain.biome_image().get_pixel(512, 512).g, before_g),
			"painting happened with nothing selected")

	# Selected, Paint ticked: press starts a stroke and dabs once immediately.
	EditorInterface.get_selection().add_node(terrain)
	await tree.process_frame
	check(painter._selected_terrain() == terrain, "the plugin did not see the terrain as selected")
	result = painter._forward_3d_gui_input(cam, _mouse_button(screen, true))
	check(result == EditorPlugin.AFTER_GUI_INPUT_STOP, "a paint click should be consumed, not passed through")
	check(painter._painting(), "pressing with Paint on and a terrain selected should start a stroke")
	# Where the ray actually lands, not where `point` says it should: the headless editor's
	# viewport is not necessarily 1280x720, so `screen` (the middle of that assumption) is not
	# reliably the middle of the real one, and project_ray_* answers for the real one.
	var world := Vector2(probe.position.x, probe.position.z)
	var image_px := Vector2i((world.x / 620.0 + 0.5) * terrain.biome_image().get_width(),
			(world.y / 620.0 + 0.5) * terrain.biome_image().get_height())
	var after_press: float = terrain.biome_image().get_pixel(image_px.x, image_px.y).g
	print("after one press: rock channel at the target is %.3f (was 0.5, wants 0.0)" % after_press)
	check(after_press < 0.4, "one press at full flow barely moved the rock channel (%.3f)" % after_press)

	# Dragging (motion with the button held) keeps painting.
	painter._forward_3d_gui_input(cam, _mouse_motion(screen))
	var after_motion: float = terrain.biome_image().get_pixel(image_px.x, image_px.y).g
	print("after a drag: rock channel at the target is %.3f" % after_motion)
	check(after_motion <= after_press + 0.05, "dragging should not move the value backwards")

	# Release: the stroke ends and saves.
	check(not FileAccess.file_exists(TMP_BIOME), "the biome file should not exist before the stroke ends")
	result = painter._forward_3d_gui_input(cam, _mouse_button(screen, false))
	check(result == EditorPlugin.AFTER_GUI_INPUT_STOP, "releasing mid-stroke should be consumed too")
	check(not painter._painting(), "releasing the mouse should end the stroke")
	check(FileAccess.file_exists(TMP_BIOME), "ending the stroke should have saved biome_path")
	if FileAccess.file_exists(TMP_BIOME):
		var saved := Image.load_from_file(ProjectSettings.globalize_path(TMP_BIOME))
		var saved_pixel := saved.get_pixel(image_px.x, image_px.y).g
		print("saved file, rock channel at the target: %.3f" % saved_pixel)
		check(absf(saved_pixel - after_motion) < 0.01,
				"the saved file does not match what was painted: %.3f vs %.3f" % [saved_pixel, after_motion])

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_BIOME))
	print("biome_painter_live_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	tree.quit(1 if failures > 0 else 0)
