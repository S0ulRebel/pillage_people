@tool
extends EditorPlugin
## Paints hand-placed overrides onto the automatic ground biome, live, straight in the 3D
## viewport - the answer to "I don't want rock there" or "a patch of sand in the grass" that a
## TerrainStamp cannot give: a stamp is a placed, moveable shape, good for one deliberate patch;
## this is a brush, good for an uneven edge or a few small touch-ups scattered by hand.
##
## Select a Terrain node. The dock appears at the bottom of the right-hand dock column
## (alongside where the Inspector's own tabs live) - it may be behind another tab the first
## time; click its own tab to bring it forward. Tick **Paint**, pick a biome from the list (or
## add a new one - name and colour, nothing else needed), and drag across the ground: a soft
## white ring follows the mouse showing where and how big the brush is. **Erase** paints back
## to automatic instead of any named biome, so a stroke never has to be perfect the first time.
##
## The list can hold as many biomes as you give it a name and a colour for - this is not the
## same tool it was at first, which only had three fixed sliders (vegetation, rock, jungle) and
## could not add a biome the automatic rules have no idea about, like a scorched patch or a
## worn path. Painting an entry writes a colour looked up by name; renaming or recolouring an
## entry later changes every stroke that used it, everywhere at once.
##
## What this does NOT give you: Ctrl+Z. A stroke is saved straight to disk the moment you
## release the mouse, outside Godot's own undo history, the same way saving a document is not
## undoable by the app that saved it. Keep the file under version control (it already is - see
## README.md) and revert it there if a stroke goes wrong.
##
## See world/terrain.gd's biome_path and biome_palette_path docs for the two files this reads
## and writes, and terrain.gdshader's biome_map/biome_palette uniforms for how they draw.

const TERRAIN_SCRIPT := preload("res://world/terrain.gd")

## For a test to reach the one running instance without standing up a second plugin (which
## would add a second, conflicting dock) - see addons/biome_painter_live_check.
const ENGINE_META := &"biome_painter_plugin"

## One entry in the palette list: a name (shown in the dock and saved to the names sidecar
## file) and a colour (saved into biome_palette_path itself, column-for-column).
class Entry:
	var biome_name: String
	var colour: Color

var _dock: PanelContainer
var _enable_button: CheckButton
var _erase_button: CheckButton
var _radius_slider: HSlider
var _flow_slider: HSlider
var _status: Label
var _list: ItemList
var _new_name: LineEdit
var _new_colour: ColorPickerButton

## The palette of the currently selected terrain, kept in step with _list's rows - see
## _refresh_palette(). Empty when no terrain is selected.
var _palette: Array[Entry] = []
var _selected_index := 0

## The stroke in progress: the image being painted into (biome_image(), mutated directly) and
## the terrain it belongs to. Null outside a stroke - _painting() is exactly "these are set".
var _stroke_image: Image = null
var _stroke_terrain: Node = null

## The brush's on-screen ring, a child of whichever terrain it is currently shown on - never
## saved into a scene (never given an owner), the same way TerrainStamp's own outline and
## sheet helpers are not. Hidden rather than freed between moves, so a hover that never leaves
## the terrain never has to rebuild it.
var _cursor: MeshInstance3D = null


func _enter_tree() -> void:
	Engine.set_meta(ENGINE_META, self)
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	if Engine.has_meta(ENGINE_META) and Engine.get_meta(ENGINE_META) == self:
		Engine.remove_meta(ENGINE_META)
	if EditorInterface.get_selection().selection_changed.is_connected(_on_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	_free_cursor()
	remove_control_from_docks(_dock)
	_dock.queue_free()


## The one Terrain among the current editor selection, or null - painting needs exactly one,
## the way a brush needs to know which canvas it is on.
func _selected_terrain() -> Node:
	for node in EditorInterface.get_selection().get_selected_nodes():
		if is_instance_valid(node) and node.get_script() == TERRAIN_SCRIPT:
			return node
	return null


func _on_selection_changed() -> void:
	if _painting():
		return   # do not disturb a stroke in progress because the selection blinked mid-drag
	var terrain := _selected_terrain()
	_status.text = ("Painting on %s" % terrain.name) if terrain != null \
			else "Select a Terrain node to paint on it."
	_refresh_palette(terrain)
	if terrain == null:
		_hide_cursor()


func _painting() -> bool:
	return _stroke_image != null and _stroke_terrain != null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _enable_button.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseMotion:
		_update_cursor(camera, event.position)
		if _painting() and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_paint_at(camera, event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var terrain := _selected_terrain()
			if terrain == null or _palette.is_empty():
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_stroke_terrain = terrain
			_stroke_image = terrain.biome_image()
			_status.text = "Painting on %s - unsaved stroke..." % terrain.name
			_paint_at(camera, event.position)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _painting():
			_end_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


## Saves the stroke to biome_path and clears it - what makes a stroke permanent. A stroke
## abandoned any other way (disabling the plugin mid-drag, say) is simply lost, same as a
## keystroke never sent - see the doc comment above on why this has no undo to fall back on.
func _end_stroke() -> void:
	var path: String = _stroke_terrain.biome_path if _stroke_terrain != null else ""
	if _stroke_image != null and path != "":
		_stroke_image.save_png(ProjectSettings.globalize_path(path))
		var fs := EditorInterface.get_resource_filesystem()
		if fs != null:
			fs.update_file(path)
	_stroke_image = null
	_stroke_terrain = null
	_on_selection_changed()


## Casts from the camera through the mouse into the terrain's own physics space (not the
## editor's "currently edited scene", which a node added any other way than through the Scene
## dock does not have - see addons/biome_painter_live_check) and, on a hit, dabs the selected
## biome (or erases) there.
func _paint_at(camera: Camera3D, screen_pos: Vector2) -> void:
	if _stroke_terrain == null or not is_instance_valid(_stroke_terrain):
		return
	var hit := _cast(_stroke_terrain, camera, screen_pos)
	if hit.is_empty():
		return
	var world := Vector2(hit.position.x, hit.position.z)
	var erasing := _erase_button.button_pressed
	var target_index := 0 if erasing else _selected_index + 1
	var target_strength := 0.0 if erasing else 1.0
	_dab(_stroke_image, _stroke_terrain, world, target_index, target_strength,
			_radius_slider.value, _flow_slider.value)
	_stroke_terrain.set_biome_image(_stroke_image)


func _cast(terrain: Node, camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = (terrain as Node3D).get_world_3d().direct_space_state
	if space == null:
		return {}
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 4000.0
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty() or hit.collider != terrain:
		return {}
	return hit


## One brush dab: every pixel within radius_m of centre_world moves towards (target_index,
## target_strength) by flow times a soft circular falloff - flow rather than jumping straight
## there so a slow drag builds up gradually and a fast one barely marks the ground, the way a
## real brush's flow setting works.
##
## The index itself is never blended, only strength is - two different biomes' indices have no
## in-between that means anything, unlike two heights or two colour channels. Painting a new
## biome over a pixel that already holds a different one starts that pixel's opacity from 0
## rather than inheriting whatever the old biome had built up, or a light touch of a new colour
## at the edge of an old, fully-opaque patch would show fully opaque instead of a light touch.
## Erasing is the one case that is not "a new biome starting from 0": it fades out whatever is
## there now, whichever biome that is, so target_index 0 always reads the pixel's own current
## strength as its starting point.
func _dab(image: Image, terrain: Node, centre_world: Vector2, target_index: int,
		target_strength: float, radius_m: float, flow: float) -> void:
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
			var brush_strength := flow * (1.0 - smoothstep(0.0, radius_px, d))
			var c := image.get_pixel(x, y)
			var current_index := int(round(c.r * 255.0))
			var base_strength := c.g if (target_index == 0 or current_index == target_index) else 0.0
			c.r = float(target_index) / 255.0
			c.g = lerpf(base_strength, target_strength, brush_strength)
			image.set_pixel(x, y, c)


## Moves (and shows, or hides if the ray misses) the brush ring - called on every mouse motion
## while Paint is ticked, drag or no drag, so the ring always shows where a click would land.
func _update_cursor(camera: Camera3D, screen_pos: Vector2) -> void:
	var terrain := _selected_terrain()
	if terrain == null:
		_hide_cursor()
		return
	var hit := _cast(terrain, camera, screen_pos)
	if hit.is_empty():
		_hide_cursor()
		return
	var cursor := _ensure_cursor(terrain)
	cursor.visible = true
	cursor.global_position = hit.position
	var radius: float = _radius_slider.value
	cursor.scale = Vector3(radius, radius, radius)
	var mat := cursor.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = Color(1, 0.25, 0.25, 0.9) if _erase_button.button_pressed \
				else _current_colour().lightened(0.3)


func _hide_cursor() -> void:
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.visible = false


func _free_cursor() -> void:
	if _cursor != null and is_instance_valid(_cursor):
		_cursor.queue_free()
	_cursor = null


## A flat ring (not a disc) so the ground under the brush stays visible while painting; drawn
## over the terrain (no_depth_test) so it never disappears into a slope. Lazily built the first
## time it is needed, moved to whichever terrain is currently selected rather than rebuilt.
func _ensure_cursor(terrain: Node) -> MeshInstance3D:
	if _cursor != null and is_instance_valid(_cursor) and _cursor.get_parent() == terrain:
		return _cursor
	_free_cursor()
	_cursor = MeshInstance3D.new()
	_cursor.name = "__BiomeBrushCursor"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.88
	mesh.outer_radius = 1.0
	mesh.rings = 48
	mesh.ring_segments = 6
	_cursor.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cursor.material_override = mat
	_cursor.visible = false
	(terrain as Node3D).add_child(_cursor)
	return _cursor


func _current_colour() -> Color:
	if _selected_index >= 0 and _selected_index < _palette.size():
		return _palette[_selected_index].colour
	return Color.WHITE


## --- the palette: as many named biomes as the list is given ---

func _names_path(terrain: Node) -> String:
	return (terrain.biome_palette_path as String).get_basename() + "_names.txt"


const _DEFAULT_NAMES := ["Grass", "Jungle", "Sand", "Rock"]


func _load_names(terrain: Node, count: int) -> Array[String]:
	var names: Array[String] = []
	var path := _names_path(terrain)
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		while f != null and not f.eof_reached():
			var line := f.get_line()
			if not (line == "" and f.eof_reached()):
				names.append(line)
	while names.size() < count:
		var i := names.size()
		names.append(_DEFAULT_NAMES[i] if i < _DEFAULT_NAMES.size() else "Biome %d" % (i + 1))
	return names


## Reloads _palette from the given terrain's own files (biome_palette_image() for colours, the
## names sidecar for names - see _names_path) and rebuilds the list to match. Called whenever
## the selection changes, since a different Terrain can have a completely different palette.
func _refresh_palette(terrain: Node) -> void:
	_palette.clear()
	_list.clear()
	if terrain == null:
		return
	var image: Image = terrain.biome_palette_image()
	var names := _load_names(terrain, image.get_width())
	for i in image.get_width():
		var entry := Entry.new()
		entry.biome_name = names[i]
		entry.colour = image.get_pixel(i, 0)
		_palette.append(entry)
		_list.add_item(entry.biome_name, _swatch(entry.colour))
	_selected_index = clampi(_selected_index, 0, maxi(_palette.size() - 1, 0))
	if not _palette.is_empty():
		_list.select(_selected_index)


func _swatch(colour: Color) -> ImageTexture:
	var image := Image.create(16, 16, false, Image.FORMAT_RGB8)
	image.fill(colour)
	return ImageTexture.create_from_image(image)


## Saves _palette to the selected terrain's biome_palette_path and names sidecar, and shows it
## live - the same split as a paint stroke, except a palette edit has no "in progress" state to
## wait out, so it saves immediately rather than waiting for a mouse-up that will never come.
func _save_palette() -> void:
	var terrain := _selected_terrain()
	if terrain == null or _palette.is_empty():
		return
	var image := Image.create(_palette.size(), 1, false, Image.FORMAT_RGBA8)
	for i in _palette.size():
		image.set_pixel(i, 0, _palette[i].colour)
	terrain.set_biome_palette_image(image)
	image.save_png(ProjectSettings.globalize_path(terrain.biome_palette_path))
	var f := FileAccess.open(_names_path(terrain), FileAccess.WRITE)
	for entry in _palette:
		f.store_line(entry.biome_name)
	f = null
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(terrain.biome_palette_path)


func _on_add_pressed() -> void:
	var terrain := _selected_terrain()
	var name := _new_name.text.strip_edges()
	if terrain == null or name == "":
		return
	var entry := Entry.new()
	entry.biome_name = name
	entry.colour = _new_colour.color
	_palette.append(entry)
	_save_palette()
	_refresh_palette(terrain)
	_selected_index = _palette.size() - 1
	_list.select(_selected_index)
	_new_name.text = ""


func _on_remove_pressed() -> void:
	var terrain := _selected_terrain()
	if terrain == null or _palette.size() <= 1:
		return   # always leave at least one entry - an empty palette has no width to paint
	_palette.remove_at(_selected_index)
	_save_palette()
	_refresh_palette(terrain)


## --- the dock itself ---

func _build_dock() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Biome Painter"
	panel.custom_minimum_size = Vector2(0, 340)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)

	var title := Label.new()
	title.text = "Biome Painter"
	title.add_theme_font_size_override("font_size", 16)
	root.add_child(title)

	var toggles := HBoxContainer.new()
	_enable_button = CheckButton.new()
	_enable_button.text = "Paint"
	_enable_button.toggled.connect(func(on: bool) -> void:
		if not on:
			_hide_cursor())
	toggles.add_child(_enable_button)
	_erase_button = CheckButton.new()
	_erase_button.text = "Erase (back to automatic)"
	toggles.add_child(_erase_button)
	root.add_child(toggles)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)

	root.add_child(HSeparator.new())

	_radius_slider = _labelled_slider(root, "Radius (m)", 1.0, 40.0, 0.5, 8.0)
	_flow_slider = _labelled_slider(root, "Flow", 0.02, 1.0, 0.02, 0.18)

	root.add_child(HSeparator.new())

	var list_label := Label.new()
	list_label.text = "Biomes (pick one to paint with)"
	root.add_child(list_label)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 110)
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(func(index: int) -> void: _selected_index = index)
	root.add_child(_list)

	var remove_row := HBoxContainer.new()
	var remove_button := Button.new()
	remove_button.text = "Remove selected"
	remove_button.pressed.connect(_on_remove_pressed)
	remove_row.add_child(remove_button)
	root.add_child(remove_row)

	root.add_child(HSeparator.new())

	var add_row := HBoxContainer.new()
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "New biome name"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_new_name)
	_new_colour = ColorPickerButton.new()
	_new_colour.color = Color(0.6, 0.6, 0.6)
	_new_colour.custom_minimum_size = Vector2(36, 0)
	add_row.add_child(_new_colour)
	var add_button := Button.new()
	add_button.text = "+ Add"
	add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(add_button)
	root.add_child(add_row)

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
