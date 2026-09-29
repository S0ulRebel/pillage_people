extends Node3D
## The character workshop: try pieces on a body, fit them, watch them move, save the result.
##
## Open actors/outfit/workshop.tscn and run it on its own (F6). Everything it offers is found
## on disk when it starts - nothing is listed by hand:
##
##   bodies   art/models/characters/body_*.glb, then the grunt and captain as stand-ins
##   pieces   art/models/characters/<slot>_*.glb, and the primitive stand-ins in placeholders/
##
## so a new part from Tripo is a file dropped in a folder, named for its slot. See
## art/models/characters/README.md.
##
## A piece nobody has placed yet gets a first guess read off the body - a coat is scaled so its
## cuffs reach the wrists, a hat sits on the skull, boots stand on the floor - and from there it
## is nudged by hand in the Fit section and saved to actors/outfit/pieces/, where every outfit
## that wears it picks the fit up. A whole character saves to actors/outfit/outfits/.
##
## Drag in the view to turn him, the wheel (or a pinch) to zoom, the right button (or two
## fingers) to raise and lower the camera. R rolls a random outfit; T stands him in the T-pose.

const STAND_INS := ["res://art/models/grunt.glb", "res://art/models/captain.glb"]
const BODY_DIRS := ["res://art/models/characters"]
const PIECE_MODEL_DIRS := ["res://art/models/characters", "res://actors/outfit/placeholders"]
const PIECE_DIR := "res://actors/outfit/pieces"
const OUTFIT_DIR := "res://actors/outfit/outfits"
## The clips every body borrows, through Retarget. A body with its own keeps them as well.
const CLIP_SOURCE := "res://art/models/captain.glb"
## Multipliers on the body's texture - the four the zombie sheet asks for, and none.
const SKIN_PRESETS := {
	"Painted": Color.WHITE,
	"Sea green": Color(0.8, 1.0, 0.86),
	"Blue grey": Color(0.84, 0.9, 1.04),
	"Olive": Color(0.98, 0.96, 0.7),
	"Pale grey": Color(1.1, 1.08, 1.1),
}
## How often a slot is left empty when rolling a random outfit. Nobody wears everything.
const EMPTY_CHANCE := 0.3
## Seconds a skinned piece waits after the last nudge before it is bound again. Binding a big
## coat takes a moment, and doing it on every click of a spin box makes the panel stutter.
const REBIND_DELAY := 0.25

var dresser: Dresser

var _bodies: Array[String] = []
## slot -> Array[OutfitPiece], every piece that could go there.
var _catalogue := {}
## slot -> OutfitPiece, what is chosen, kept across a change of body.
var _chosen := {}
var _body_path := ""
var _model: Node3D
var _player: AnimationPlayer
var _clip := ""
var _rng := RandomNumberGenerator.new()
## The piece model's vertices in its own space, by path, for guessing fits.
var _shapes := {}

# The view.
var _camera: Camera3D
var _yaw := 0.0
var _pitch := -0.12
var _distance := 4.3
var _aim_height := 0.9

# The panel.
var _body_pick: OptionButton
var _slot_picks := {}
var _clip_pick: OptionButton
var _colour_pick: ColorPickerButton
var _edit_pick: OptionButton
var _bone_pick: OptionButton
var _bone_row: Control
var _fit_rows: Control
var _position_boxes: Array[SpinBox] = []
var _rotation_boxes: Array[SpinBox] = []
var _scale_boxes: Array[SpinBox] = []
var _name_edit: LineEdit
var _outfit_pick: OptionButton
var _status: Label
var _editing := ""
var _rebind: Timer


func _ready() -> void:
	_rng.randomize()
	dresser = Dresser.new()
	dresser.name = "Dresser"
	add_child(dresser)
	_rebind = Timer.new()
	_rebind.one_shot = true
	_rebind.wait_time = REBIND_DELAY
	_rebind.timeout.connect(func() -> void:
		dresser.refit(_editing)
		_after_wear())
	add_child(_rebind)
	_build_stage()
	_build_panel()
	_scan()
	_fill_lists()
	if _bodies.is_empty():
		_say("No rigged body found. Put one in art/models/characters/ as body_<name>.glb.")
		return
	_load_body(_bodies[0])
	randomise()


# --- what the panel does -----------------------------------------------------------------------

## Loads the body at `path`, gives it clips, and puts back on whatever was chosen.
func load_body(path: String) -> void:
	_load_body(path)


## Puts `piece` in its slot, or empties `slot` when piece is null.
func choose(slot: String, piece: OutfitPiece) -> void:
	if piece == null:
		_chosen.erase(slot)
		dresser.take_off(slot)
	else:
		_chosen[slot] = piece
		if not piece.fitted:
			guess(piece)
		dresser.wear(piece)
	_after_wear()


## A random piece or nothing in every slot, and a random skin.
func randomise() -> void:
	for slot in OutfitPiece.SLOTS:
		var options: Array = _catalogue.get(slot, [])
		if options.is_empty() or _rng.randf() < EMPTY_CHANCE:
			choose(slot, null)
		else:
			choose(slot, options[_rng.randi() % options.size()])
	var colours := SKIN_PRESETS.values()
	set_skin(colours[_rng.randi() % colours.size()])


func set_skin(colour: Color) -> void:
	dresser.set_skin_colour(colour)
	_colour_pick.color = colour


func play(clip: String) -> void:
	_clip = clip
	if clip == "" or _player == null or not _player.has_animation(clip):
		_clip = ""
		if _player != null:
			_player.stop()
		dresser.stand_at_rest()
	else:
		_player.play(clip)
	for i in _clip_pick.item_count:
		if _clip_pick.get_item_metadata(i) == _clip:
			_clip_pick.select(i)


## A first fit for `piece` on the current body, read off its bones and outline. See the
## comment at the top of the file; each slot's rule is below.
##
## Does NOT mark the piece fitted. A guess belongs to the body it was read off, so until someone
## has nudged or saved it, changing body guesses again - a hat guessed onto the 1.8 m zombie
## would otherwise float above the grunt.
func guess(piece: OutfitPiece) -> void:
	var shape := _shape_of(piece.model)
	if shape.is_empty():
		return
	var own := _bounds_of(shape)
	var bone := func(bone_name: String) -> Vector3: return dresser.bone_position(bone_name)
	var neck: Vector3 = bone.call("mixamorig_Neck")
	var head: Vector3 = bone.call("mixamorig_Head")
	var hips: Vector3 = bone.call("mixamorig_Hips")
	var spine: Vector3 = bone.call("mixamorig_Spine")
	var foot: Vector3 = bone.call("mixamorig_LeftFoot")
	var knee: Vector3 = bone.call("mixamorig_LeftLeg")
	var body := dresser.body_bounds()
	var top := body.end.y
	var skull := dresser.body_slice(head.y, top)
	var skull_width := maxf(skull.size.x, 0.05)
	var size := 1.0
	var anchor := Vector3.ZERO     # a point in the piece's own space...
	var target := Vector3.ZERO     # ...and where on the body it goes.
	match piece.slot:
		"head":
			# Chin-to-crown fills neck-to-crown, standing on the neck.
			size = (top - neck.y) / own.size.y
			anchor = _bottom_centre(own)
			target = Vector3(head.x, neck.y, head.z)
		"hair":
			size = skull_width * 1.1 / own.size.x
			anchor = _top_centre(own)
			target = Vector3(head.x, top + skull_width * 0.04, skull.get_center().z)
		"hat":
			# Wider than the skull, and sat down onto it by a third of its width.
			size = skull_width * 1.7 / own.size.x
			anchor = _bottom_centre(own)
			target = Vector3(head.x, top - skull_width * 0.35, skull.get_center().z)
		"face", "jaw":
			size = skull_width * 0.7 / maxf(own.size.x, own.size.y)
			anchor = own.get_center()
			var at_y: float = head.y if piece.slot == "face" else lerpf(neck.y, head.y, 0.5)
			var front := dresser.body_slice(at_y - 0.03, at_y + 0.03)
			target = Vector3(head.x, at_y, front.end.z if front.has_volume() else head.z)
		"shirt", "coat":
			# Cuff to cuff is wrist to wrist, and the cuffs are at the wrists' height. The
			# cuffs are found in the model itself - the vertices furthest out along X - so a
			# long coat and a short shirt both land with their sleeves on the arms.
			var left: Vector3 = bone.call("mixamorig_LeftHand")
			var right: Vector3 = bone.call("mixamorig_RightHand")
			size = (left.x - right.x) / own.size.x
			anchor = Vector3(own.get_center().x, _cuff_height(shape, own), own.get_center().z)
			target = Vector3(hips.x, (left.y + right.y) / 2.0, spine.z)
		"trousers":
			var waist := lerpf(hips.y, spine.y, 0.6)
			size = (waist - foot.y) / own.size.y
			anchor = _top_centre(own)
			target = Vector3(hips.x, waist, hips.z)
		"waist":
			var at_hips := dresser.body_slice(hips.y - 0.04, spine.y)
			size = maxf(at_hips.size.x, 0.1) * 1.1 / own.size.x
			anchor = _top_centre(own)
			target = Vector3(hips.x, spine.y + 0.02, at_hips.get_center().z)
		"boots":
			# Floor to halfway up the shin - or bigger, if that would leave toes sticking out.
			# The zombie's feet are a third longer than a boot scaled by height alone, so the
			# feet themselves, measured off the skin below the ankle, set the least it can be.
			var feet := dresser.body_slice(-INF, foot.y * 0.8)
			size = lerpf(foot.y, knee.y, 0.55) / own.size.y
			if feet.has_volume():
				size = maxf(size, maxf(feet.size.x * 1.08 / own.size.x,
						feet.size.z * 1.08 / own.size.z))
				anchor = _bottom_centre(own)
				target = Vector3(feet.get_center().x, 0.0, feet.get_center().z)
			else:
				anchor = _bottom_centre(own)
				target = Vector3(hips.x, 0.0, foot.z)
		_:
			# Anything pinned: 15 cm across, sitting on the front of the body at its bone.
			var at: Vector3 = bone.call(piece.bone)
			size = 0.15 / maxf(own.size.x, maxf(own.size.y, own.size.z))
			anchor = own.get_center()
			var front := dresser.body_slice(at.y - 0.03, at.y + 0.03)
			target = Vector3(at.x, at.y, (front.end.z if front.has_volume() else at.z) + 0.02)
	piece.rotation = Vector3.ZERO
	piece.scale = Vector3.ONE * size
	piece.position = target - anchor * size


## Saves `piece` to actors/outfit/pieces/, named after its model. Returns the path, or "".
func save_piece(piece: OutfitPiece) -> String:
	# Saved is placed: from here on it keeps this fit on every body rather than being guessed.
	piece.fitted = true
	var path := "%s/%s.tres" % [PIECE_DIR, piece.model.get_file().get_basename()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIECE_DIR))
	var error := ResourceSaver.save(piece, path)
	if error != OK:
		_say("Could not save %s (error %d)." % [path, error])
		return ""
	# Claimed explicitly: ResourceSaver.FLAG_CHANGE_PATH leaves resource_path empty in 4.7, and
	# a piece with no path is copied INTO every outfit that wears it rather than pointed at -
	# so re-fitting the coat later would leave every saved outfit wearing the old one.
	piece.take_over_path(path)
	return path


## Saves what is on the body as an outfit called `outfit_name`. Returns the path, or "".
func save_outfit(outfit_name: String) -> String:
	var clean := outfit_name.strip_edges().to_snake_case().validate_filename()
	if clean == "":
		_say("Give the outfit a name first.")
		return ""
	var outfit := Outfit.new()
	outfit.body = _body_path
	outfit.skin_colour = dresser.skin_colour()
	for piece in dresser.pieces():
		# The outfit points at its pieces, so each has to exist as a file of its own first.
		if save_piece(piece) == "":
			return ""
		outfit.pieces.append(piece)
	var path := "%s/%s.tres" % [OUTFIT_DIR, clean]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTFIT_DIR))
	var error := ResourceSaver.save(outfit, path)
	if error != OK:
		_say("Could not save %s (error %d)." % [path, error])
		return ""
	_fill_outfits()
	_say("Saved %s - %d pieces." % [path, outfit.pieces.size()])
	return path


func load_outfit(path: String) -> void:
	var outfit := load(path) as Outfit
	if outfit == null:
		_say("%s is not an outfit." % path)
		return
	_chosen.clear()
	for piece in outfit.pieces:
		if piece != null:
			_chosen[piece.slot] = piece
	if outfit.body != _body_path and ResourceLoader.exists(outfit.body):
		_load_body(outfit.body)
	else:
		dresser.dress(outfit)
		_after_wear()
	set_skin(outfit.skin_colour)
	_name_edit.text = path.get_file().get_basename()
	_say("Loaded %s." % path)


# --- bodies and clips --------------------------------------------------------------------------

func _load_body(path: String) -> void:
	if _model != null:
		_model.queue_free()
		_model = null
		_player = null
	var scene := load(path) as PackedScene
	if scene == null:
		_say("Could not load %s." % path)
		return
	_body_path = path
	_model = scene.instantiate() as Node3D
	add_child(_model)
	if not dresser.attach(_model):
		_say("%s has no skeleton - it has to be rigged before anything can be worn." % path)
		return
	_give_clips()
	for i in _body_pick.item_count:
		if _body_pick.get_item_metadata(i) == path:
			_body_pick.select(i)
	# Put back what was chosen. Pieces are fitted in metres, so they carry across bodies of a
	# build; one that has never been placed gets its guess for this body.
	for slot in _chosen.keys():
		var piece: OutfitPiece = _chosen[slot]
		if not piece.fitted:
			guess(piece)
		dresser.wear(piece)
	_after_wear()
	play(_clip)
	_say("%s - %d bones." % [path.get_file(), dresser.skeleton().get_bone_count()])


## The body's own clips, plus the captain's retargeted onto it. Cycles are set to loop, since
## glTF carries no loop flag.
func _give_clips() -> void:
	var players := _model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		_player = AnimationPlayer.new()
		_player.name = "AnimationPlayer"
		_model.add_child(_player)
	else:
		_player = players[0]
	if _body_path != CLIP_SOURCE and ResourceLoader.exists(CLIP_SOURCE):
		var root := _player.get_node(_player.root_node)
		var borrowed := Retarget.library(CLIP_SOURCE, _model, dresser.skeleton(), root)
		if _player.has_animation_library("captain"):
			_player.remove_animation_library("captain")
		_player.add_animation_library("captain", borrowed)
	_clip_pick.clear()
	_clip_pick.add_item("T-pose")
	_clip_pick.set_item_metadata(0, "")
	for clip in _player.get_animation_list():
		var animation := _player.get_animation(clip)
		if not clip.contains("death"):
			animation.loop_mode = Animation.LOOP_LINEAR
		_clip_pick.add_item(clip)
		_clip_pick.set_item_metadata(_clip_pick.item_count - 1, String(clip))
	if _clip != "" and not _player.has_animation(_clip):
		_clip = ""


# --- finding things ----------------------------------------------------------------------------

func _scan() -> void:
	_bodies.clear()
	for dir in BODY_DIRS:
		for path in _files(dir):
			if path.get_file().begins_with("body_") and _is_model(path):
				_bodies.append(path)
	for path in STAND_INS:
		if ResourceLoader.exists(path):
			_bodies.append(path)
	var saved := {}
	for path in _files(PIECE_DIR):
		if path.ends_with(".tres"):
			var piece := load(path) as OutfitPiece
			if piece != null:
				saved[piece.model] = piece
	_catalogue.clear()
	for slot in OutfitPiece.SLOTS:
		_catalogue[slot] = []
	for dir in PIECE_MODEL_DIRS:
		for path in _files(dir):
			if not _is_model(path) or path.get_file().begins_with("body_"):
				continue
			var piece: OutfitPiece = saved.get(path, OutfitPiece.for_model(path))
			if piece != null:
				(_catalogue[piece.slot] as Array).append(piece)


static func _is_model(path: String) -> bool:
	return path.get_extension() in ["glb", "gltf", "tscn"]


## Every file under `dir`, recursively. Empty when the folder does not exist yet.
static func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for file in DirAccess.get_files_at(dir):
		out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	return out


## The piece model's vertices in its own space.
func _shape_of(path: String) -> PackedVector3Array:
	if _shapes.has(path):
		return _shapes[path]
	var points := PackedVector3Array()
	var scene := load(path) as PackedScene
	if scene != null:
		var model := scene.instantiate()
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := node as MeshInstance3D
			if mesh_node.mesh == null:
				continue
			var placed := RigSpace.chain(mesh_node, model)
			for surface in mesh_node.mesh.get_surface_count():
				var arrays := mesh_node.mesh.surface_get_arrays(surface)
				for vertex in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					points.append(placed * vertex)
		model.free()
	_shapes[path] = points
	return points


static func _bounds_of(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box


## The height of a garment's cuffs: the average height of its vertices in the outermost 5% of
## its width, on both sides.
static func _cuff_height(points: PackedVector3Array, box: AABB) -> float:
	var reach := box.size.x * 0.05
	var total := 0.0
	var count := 0
	for point in points:
		if point.x < box.position.x + reach or point.x > box.end.x - reach:
			total += point.y
			count += 1
	return total / count if count > 0 else box.get_center().y


static func _bottom_centre(box: AABB) -> Vector3:
	return Vector3(box.get_center().x, box.position.y, box.get_center().z)


static func _top_centre(box: AABB) -> Vector3:
	return Vector3(box.get_center().x, box.end.y, box.get_center().z)


# --- the stage ---------------------------------------------------------------------------------

func _build_stage() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	# The grey the concept sheets are drawn on, so a piece reads against it as it does there.
	environment.background_color = Color(0.6, 0.6, 0.62)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.62, 0.66)
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 1.1
	floor_mesh.bottom_radius = 1.1
	floor_mesh.height = 0.02
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.5, 0.5, 0.52)
	floor_mesh.material = floor_material
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.position.y = -0.011
	add_child(floor_node)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	add_child(_camera)
	_camera.make_current()
	_place_camera()


func _place_camera() -> void:
	var direction := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	var aim := Vector3(0.0, _aim_height, 0.0)
	_camera.position = aim + direction * _distance
	_camera.look_at(aim)
	# The panel covers the left of the screen, so the body is framed right of centre.
	_camera.h_offset = -0.18 * _distance


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var button := (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(0.6, _distance * 0.9)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(9.0, _distance / 0.9)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_turn(motion.relative)
		elif motion.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
			_aim_height = clampf(_aim_height + motion.relative.y * 0.004, 0.1, 2.2)
	elif event is InputEventScreenDrag:
		_turn((event as InputEventScreenDrag).relative)
	elif event is InputEventMagnifyGesture:
		_distance = clampf(_distance / (event as InputEventMagnifyGesture).factor, 0.6, 9.0)
	elif event is InputEventPanGesture:
		_aim_height = clampf(_aim_height - (event as InputEventPanGesture).delta.y * 0.02,
				0.1, 2.2)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_R:
				randomise()
			KEY_T:
				play("")
	_place_camera()


func _turn(by: Vector2) -> void:
	_yaw -= by.x * 0.01
	_pitch = clampf(_pitch + by.y * 0.006, -1.2, 1.2)


# --- the panel ---------------------------------------------------------------------------------

func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.anchor_bottom = 1.0
	panel.custom_minimum_size = Vector2(400.0, 0.0)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	scroll.add_child(margin)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(rows)

	_heading(rows, "Character workshop")
	_body_pick = OptionButton.new()
	_body_pick.item_selected.connect(func(index: int) -> void:
		_load_body(_body_pick.get_item_metadata(index)))
	_row(rows, "Body", _body_pick)
	for slot in OutfitPiece.SLOTS:
		var pick := OptionButton.new()
		pick.item_selected.connect(func(index: int) -> void:
			choose(slot, pick.get_item_metadata(index)))
		_slot_picks[slot] = pick
		_row(rows, slot.capitalize(), pick)

	var swatches := HBoxContainer.new()
	for preset in SKIN_PRESETS:
		var swatch := Button.new()
		swatch.tooltip_text = preset
		swatch.custom_minimum_size = Vector2(28.0, 28.0)
		var style := StyleBoxFlat.new()
		style.bg_color = (SKIN_PRESETS[preset] as Color) * Color(0.62, 0.66, 0.6)
		swatch.add_theme_stylebox_override("normal", style)
		swatch.pressed.connect(set_skin.bind(SKIN_PRESETS[preset]))
		swatches.add_child(swatch)
	_colour_pick = ColorPickerButton.new()
	_colour_pick.custom_minimum_size = Vector2(40.0, 28.0)
	_colour_pick.color_changed.connect(func(colour: Color) -> void:
		dresser.set_skin_colour(colour))
	swatches.add_child(_colour_pick)
	_row(rows, "Skin", swatches)

	_clip_pick = OptionButton.new()
	_clip_pick.item_selected.connect(func(index: int) -> void:
		play(_clip_pick.get_item_metadata(index)))
	_row(rows, "Animation", _clip_pick)
	var actions := HBoxContainer.new()
	_button(actions, "Random  (R)", randomise)
	_button(actions, "T-pose  (T)", play.bind(""))
	rows.add_child(actions)

	_heading(rows, "Fit")
	_edit_pick = OptionButton.new()
	_edit_pick.item_selected.connect(func(index: int) -> void:
		_edit(_edit_pick.get_item_metadata(index)))
	_row(rows, "Piece", _edit_pick)
	_fit_rows = VBoxContainer.new()
	rows.add_child(_fit_rows)
	_bone_pick = OptionButton.new()
	_bone_pick.item_selected.connect(func(index: int) -> void:
		var piece := dresser.worn(_editing)
		if piece != null:
			piece.bone = _bone_pick.get_item_text(index)
			_nudged(true))
	_bone_row = _row(_fit_rows, "Bone", _bone_pick)
	_position_boxes = _vector_row(_fit_rows, "Position", 0.005, -3.0, 3.0)
	_rotation_boxes = _vector_row(_fit_rows, "Turn", 1.0, -180.0, 180.0)
	_scale_boxes = _vector_row(_fit_rows, "Scale", 0.01, 0.01, 20.0)
	var fit_actions := HBoxContainer.new()
	_button(fit_actions, "Guess again", func() -> void:
		var piece := dresser.worn(_editing)
		if piece != null:
			guess(piece)
			piece.fitted = false
			dresser.refit(_editing)
			_after_wear())
	_button(fit_actions, "Save piece", func() -> void:
		var piece := dresser.worn(_editing)
		if piece != null:
			var path := save_piece(piece)
			if path != "":
				_say("Saved %s." % path))
	_fit_rows.add_child(fit_actions)

	_heading(rows, "Outfit")
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "zombie_sailor"
	_row(rows, "Name", _name_edit)
	var outfit_actions := HBoxContainer.new()
	_button(outfit_actions, "Save outfit", func() -> void: save_outfit(_name_edit.text))
	_outfit_pick = OptionButton.new()
	_outfit_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outfit_pick.item_selected.connect(func(index: int) -> void:
		var path: String = _outfit_pick.get_item_metadata(index)
		if path != "":
			load_outfit(path))
	outfit_actions.add_child(_outfit_pick)
	rows.add_child(outfit_actions)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360.0, 0.0)
	rows.add_child(_status)


func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	parent.add_child(label)


func _row(parent: Control, label_text: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)
	return row


func _button(parent: Control, text: String, pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(pressed)
	parent.add_child(button)


func _vector_row(parent: Control, label_text: String, step: float, low: float,
		high: float) -> Array[SpinBox]:
	var boxes: Array[SpinBox] = []
	var holder := HBoxContainer.new()
	for axis in 3:
		var box := SpinBox.new()
		box.step = step
		box.min_value = low
		box.max_value = high
		box.allow_greater = true
		box.allow_lesser = true
		box.custom_arrow_step = step
		box.select_all_on_focus = true
		box.prefix = "XYZ"[axis]
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.value_changed.connect(func(_value: float) -> void: _nudged(false))
		holder.add_child(box)
		boxes.append(box)
	_row(parent, label_text, holder)
	return boxes


func _fill_lists() -> void:
	_body_pick.clear()
	for path in _bodies:
		_body_pick.add_item(path.get_file().get_basename())
		_body_pick.set_item_metadata(_body_pick.item_count - 1, path)
	for slot in OutfitPiece.SLOTS:
		var pick: OptionButton = _slot_picks[slot]
		pick.clear()
		pick.add_item("-")
		pick.set_item_metadata(0, null)
		for piece in _catalogue[slot]:
			pick.add_item((piece as OutfitPiece).label())
			pick.set_item_metadata(pick.item_count - 1, piece)
		pick.disabled = pick.item_count == 1
	_fill_outfits()


func _fill_outfits() -> void:
	_outfit_pick.clear()
	_outfit_pick.add_item("Load outfit...")
	_outfit_pick.set_item_metadata(0, "")
	for path in _files(OUTFIT_DIR):
		if path.ends_with(".tres"):
			_outfit_pick.add_item(path.get_file().get_basename())
			_outfit_pick.set_item_metadata(_outfit_pick.item_count - 1, path)


## Brings the panel in line with what is being worn.
func _after_wear() -> void:
	for slot in OutfitPiece.SLOTS:
		var pick: OptionButton = _slot_picks[slot]
		var worn := dresser.worn(slot)
		pick.select(0)
		for i in pick.item_count:
			if worn != null and pick.get_item_metadata(i) == worn:
				pick.select(i)
	var keep := _editing
	_edit_pick.clear()
	for piece in dresser.pieces():
		_edit_pick.add_item("%s - %s" % [piece.slot.capitalize(), piece.label()])
		_edit_pick.set_item_metadata(_edit_pick.item_count - 1, piece.slot)
	if _edit_pick.item_count == 0:
		_edit("")
		return
	var index := 0
	for i in _edit_pick.item_count:
		if _edit_pick.get_item_metadata(i) == keep:
			index = i
	_edit_pick.select(index)
	_edit(_edit_pick.get_item_metadata(index))


func _edit(slot: String) -> void:
	_editing = slot
	_fit_rows.visible = dresser.worn(slot) != null
	_show_fit()


func _show_fit() -> void:
	var piece := dresser.worn(_editing)
	if piece == null:
		return
	for axis in 3:
		_position_boxes[axis].set_value_no_signal(piece.position[axis])
		_rotation_boxes[axis].set_value_no_signal(piece.rotation[axis])
		_scale_boxes[axis].set_value_no_signal(piece.scale[axis])
	_bone_row.visible = piece.hold == OutfitPiece.Hold.PINNED
	_bone_pick.clear()
	var skeleton := dresser.skeleton()
	for bone in skeleton.get_bone_count():
		_bone_pick.add_item(skeleton.get_bone_name(bone))
		if skeleton.get_bone_name(bone) == piece.bone:
			_bone_pick.select(bone)


## The fit boxes changed. A pinned piece moves at once; a skinned one is bound again once the
## clicking stops.
func _nudged(now: bool) -> void:
	var piece := dresser.worn(_editing)
	if piece == null:
		return
	for axis in 3:
		piece.position[axis] = _position_boxes[axis].value
		piece.rotation[axis] = _rotation_boxes[axis].value
		piece.scale[axis] = _scale_boxes[axis].value
	piece.fitted = true
	if piece.hold == OutfitPiece.Hold.PINNED:
		dresser.refit(_editing)
		if now:
			_after_wear()
	elif now:
		dresser.refit(_editing)
		_after_wear()
	else:
		_rebind.start()


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
	print("workshop: ", text)
