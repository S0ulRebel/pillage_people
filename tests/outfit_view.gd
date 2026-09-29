extends SceneTree
## Run: godot --path . --script res://tests/outfit_view.gd [-- --body grunt]
##
## Photographs the workshop with every placeholder piece worn: the T-pose from the front and
## the side, then mid-walk and mid-swing, so a coat that does not follow the arms, a hat that
## floats off the skull or boots that stay behind when he steps can be seen rather than argued
## about. Not headless - --headless has no renderer.
##
## Writes to user://outfit/.

const SHOTS := "user://outfit"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var shop: Node3D = load("res://actors/outfit/workshop.tscn").instantiate()
	root.add_child(shop)
	current_scene = shop
	await process_frame
	var args := OS.get_cmdline_user_args()
	var body_index := args.find("--body")
	if body_index != -1 and body_index + 1 < args.size():
		for path in shop._bodies:
			if (path as String).get_file().contains(args[body_index + 1]):
				shop.load_body(path)
	var tag: String = shop._body_path.get_file().get_basename()
	# Everything on, so every piece is in the picture.
	for slot in OutfitPiece.SLOTS:
		var options: Array = shop._catalogue[slot]
		shop.choose(slot, options[0] if not options.is_empty() else null)
	shop.set_skin(Color.WHITE)
	var views := [["tpose_front", "", 0.0], ["tpose_side", "", 1.5708],
			["walk", "walk", 0.5], ["slash", "slash", 0.5]]
	for view in views:
		var clip: String = view[1]
		var wanted := ""
		for name in shop._player.get_animation_list():
			if String(name).get_file() == clip:
				wanted = name
		shop.play(wanted)
		if wanted != "":
			shop._player.seek(0.45 if clip == "walk" else 1.1, true)
			shop._player.pause()
		shop._yaw = view[2]
		shop._place_camera()
		for i in 6:
			await process_frame
		var file := "%s/%s_%s.png" % [SHOTS, tag, view[0]]
		root.get_texture().get_image().save_png(file)
		print("wrote ", ProjectSettings.globalize_path(file))
	quit()
