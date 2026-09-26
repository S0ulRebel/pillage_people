@tool
extends EditorPlugin
## Paints hand-placed overrides onto the automatic ground biome, live, straight in the 3D
## viewport - the answer to "I don't want rock there" or "a patch of sand in the grass" that a
## TerrainStamp cannot give: a stamp is a placed, moveable shape, good for one deliberate patch;
## this is a brush, good for an uneven edge or a few small touch-ups scattered by hand.
##
## Select a Terrain node, tick Paint below, then drag across the ground: each channel ticked
## is pulled towards its slider's value under the brush, everything else is left exactly as
## the automatic rules already draw it. A slider at 0 paints "back to automatic" - painting is
## never destructive to the height map or the mesh, only to terrain/island_biome.png, so an
## area can always be un-painted again by brushing it back to neutral.
##
## What this does NOT give you: Ctrl+Z. A stroke is saved straight to island_biome.png the
## moment you release the mouse, outside Godot's own undo history, the same way saving a
## document is not undoable by the app that saved it. Keep the file under version control (it
## already is - see README.md) and revert it there if a stroke goes wrong.
##
## See world/terrain.gdshader's biome_map uniform for what each channel does to the shader,
## and world/terrain.gd's biome_path doc for the file this reads and writes.

const TERRAIN_SCRIPT := preload("res://world/terrain.gd")

## For a test to reach the one running instance without standing up a second plugin (which
## would add a second, conflicting dock) - see tests/biome_painter_live_check.gd.
const ENGINE_META := &"biome_painter_plugin"

## One row of the dock: a channel to paint, which byte of biome_map it writes (see
## terrain.gdshader's biome_map uniform: R vegetation, G rock, B jungle), its checkbox and its
## target slider.
class Channel:
	var name: String
	var index: int
	var check: CheckBox
	var slider: HSlider

var _dock: PanelContainer
var _enable_button: CheckButton
var _radius_slider: HSlider
var _flow_slider: HSlider
var _status: Label
var _channels: Array[Channel] = []

## The stroke in progress: the image being painted into (biome_image(), mutated directly) and
## the terrain it belongs to. Null outside a stroke - _painting() is exactly "these are set".
var _stroke_image: Image = null
var _stroke_terrain: Node = null


func _enter_tree() -> void:
	Engine.set_meta(ENGINE_META, self)
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_update_status)
	_update_status()


func _exit_tree() -> void:
	if Engine.has_meta(ENGINE_META) and Engine.get_meta(ENGINE_META) == self:
		Engine.remove_meta(ENGINE_META)
	if EditorInterface.get_selection().selection_changed.is_connected(_update_status):
		EditorInterface.get_selection().selection_changed.disconnect(_update_status)
	remove_control_from_docks(_dock)
	_dock.queue_free()


## The one Terrain among the current editor selection, or null - painting needs exactly one,
## the way a brush needs to know which canvas it is on.
func _selected_terrain() -> Node:
	for node in EditorInterface.get_selection().get_selected_nodes():
		if is_instance_valid(node) and node.get_script() == TERRAIN_SCRIPT:
			return node
	return null


func _update_status() -> void:
	if _painting():
		return   # do not overwrite "unsaved stroke..." because the selection blinked mid-drag
	var terrain := _selected_terrain()
	_status.text = ("Painting on %s" % terrain.name) if terrain != null \
			else "Select a Terrain node to paint on it."


func _painting() -> bool:
	return _stroke_image != null and _stroke_terrain != null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _enable_button.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var terrain := _selected_terrain()
			if terrain == null:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_stroke_terrain = terrain
			_stroke_image = terrain.biome_image()
			_status.text = "Painting on %s - unsaved stroke..." % terrain.name
			_paint_at(camera, event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _painting():
			_end_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and _painting() \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_paint_at(camera, event.position)
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Saves the stroke to biome_path and clears it - what makes a stroke permanent. Called on
## mouse-up; also from _exit_tree() by way of nothing (a stroke abandoned by disabling the
## plugin mid-drag is simply lost, same as a keystroke never sent - see the doc comment above
## on why this has no undo to fall back on).
func _end_stroke() -> void:
	var path: String = _stroke_terrain.biome_path if _stroke_terrain != null else ""
	if _stroke_image != null and path != "":
		_stroke_image.save_png(ProjectSettings.globalize_path(path))
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.update_file(path)
	_stroke_image = null
	_stroke_terrain = null
	_update_status()


## Casts from the camera through the mouse into the terrain's own physics space (not the
## editor's "currently edited scene", which a node added any other way than through the Scene
## dock does not have - see tests/biome_painter_live_check.gd) and, on a hit against the
## terrain being painted, dabs every ticked channel there.
func _paint_at(camera: Camera3D, screen_pos: Vector2) -> void:
	if _stroke_terrain == null or not is_instance_valid(_stroke_terrain):
		return
	var space: PhysicsDirectSpaceState3D = (_stroke_terrain as Node3D).get_world_3d().direct_space_state
	if space == null:
		return
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 4000.0
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or hit.collider != _stroke_terrain:
		return
	var world := Vector2(hit.position.x, hit.position.z)
	var radius: float = _radius_slider.value
	var flow: float = _flow_slider.value
	for channel in _channels:
		if channel.check.button_pressed:
			_dab(_stroke_image, _stroke_terrain, world, channel.index,
					(channel.slider.value + 1.0) * 0.5, radius, flow)
	_stroke_terrain.set_biome_image(_stroke_image)


## One brush dab: every pixel within radius_m of centre_world is nudged towards `target`
## (0..1) by `flow` times a soft circular falloff - `flow` rather than jumping straight to
## `target` so a slow drag builds up gradually and a fast one barely marks the ground, the way
## a real brush's flow setting works. `channel` is 0 for R (vegetation), 1 for G (rock), 2 for
## B (jungle) - see terrain.gdshader's biome_map uniform.
func _dab(image: Image, terrain: Node, centre_world: Vector2, channel: int, target: float,
		radius_m: float, flow: float) -> void:
	var world_size: float = terrain.world_size
	var scale: float = image.get_width() / world_size
	var centre_px := Vector2((centre_world.x / world_size + 0.5) * image.get_width(),
			(centre_world.y / world_size + 0.5) * image.get_height())
	var radius_px := maxf(radius_m * scale, 0.5)
	var x0 := maxi(0, int(centre_px.x - radius_px))
	var x1 := mini(image.get_width() - 1, int(centre_px.x + radius_px))
	var y0 := maxi(0, int(centre_px.y - radius_px))
	var y1 := mini(image.get_height() - 1, int(centre_px.y + radius_px))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y).distance_to(centre_px)
			if d > radius_px:
				continue
			var strength := flow * (1.0 - smoothstep(0.0, radius_px, d))
			var c := image.get_pixel(x, y)
			match channel:
				0: c.r = lerpf(c.r, target, strength)
				1: c.g = lerpf(c.g, target, strength)
				2: c.b = lerpf(c.b, target, strength)
			image.set_pixel(x, y, c)


func _build_dock() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Biome Painter"
	panel.custom_minimum_size = Vector2(0, 260)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	var title := Label.new()
	title.text = "Biome Painter"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	_enable_button = CheckButton.new()
	_enable_button.text = "Paint"
	root.add_child(_enable_button)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)

	root.add_child(HSeparator.new())

	_radius_slider = _labelled_slider(root, "Radius (m)", 1.0, 40.0, 0.5, 8.0)
	_flow_slider = _labelled_slider(root, "Flow", 0.02, 1.0, 0.02, 0.18)

	root.add_child(HSeparator.new())

	# Rock ticked and pushed all the way to "off" by default: the case that started this
	# tool ("I don't want rock there") should work the moment Paint is ticked, with nothing
	# else to configure first.
	_channels.append(_channel_row(root, "Vegetation  (sand <-> plants)", 0, false, 0.0))
	_channels.append(_channel_row(root, "Rock  (ground <-> rock)", 1, true, -1.0))
	_channels.append(_channel_row(root, "Jungle  (grass <-> jungle)", 2, false, 0.0))

	return panel


func _labelled_slider(root: VBoxContainer, label: String, min_v: float, max_v: float,
		step: float, default: float) -> HSlider:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = default
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(36, 0)
	value_label.text = "%.2f" % default
	slider.value_changed.connect(func(v: float) -> void: value_label.text = "%.2f" % v)
	row.add_child(value_label)
	root.add_child(row)
	return slider


func _channel_row(root: VBoxContainer, label: String, index: int, active: bool,
		target: float) -> Channel:
	var row := HBoxContainer.new()
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = active
	check.custom_minimum_size = Vector2(190, 0)
	row.add_child(check)
	var slider := HSlider.new()
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = target
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = "-1 = fully the left word above, 0 = automatic, +1 = fully the right word"
	row.add_child(slider)
	root.add_child(row)
	var channel := Channel.new()
	channel.name = label
	channel.index = index
	channel.check = check
	channel.slider = slider
	return channel
