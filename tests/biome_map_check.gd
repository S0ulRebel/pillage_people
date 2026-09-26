extends SceneTree
## Run: godot --headless --path . --script res://tests/biome_map_check.gd
##
## Does the hand-painted biome override load, save, and reach the shader the way
## addons/biome_painter assumes it does?
##
## The paint tool never touches the mesh or the collider - only a texture - so nothing here
## can be checked by dropping a ray on the ground the way the stamp and tunnel tests do, and
## --headless has no real rendering server behind an ImageTexture, so reading one back never
## shows an update either (checked directly - it does not, even a frame later). What is
## checked here: an unpainted island gets a real, neutral image rather than a missing one; a
## painted image round-trips through disk exactly; the shader's biome_map is a real texture of
## the right size; and biome_image() - the CPU-side image the next upload is always made from -
## reflects every paint and every reload straight away. What the shader actually draws with it
## is checked in tests/biome_paint_view.gd, a real (non-headless) render.

const TERRAIN := preload("res://world/terrain.gd")
const TMP_PATH := "res://tests/_tmp_biome.png"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


## Within one 8-bit step: an RGBA8 image rounds 0.5 to 127 or 128 on write, never exactly
## back to 0.5, so an exact is_equal_approx() would fail on the very first read of a texel
## nobody painted.
func close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))

	# No file on disk yet: a real, neutral image, not null and not zero-sized.
	var fresh := StaticBody3D.new()
	fresh.set_script(TERRAIN)
	fresh.raw_path = "res://terrain/island.r16"
	fresh.world_size = 620.0
	fresh.height_scale = 180.0
	fresh.biome_path = TMP_PATH
	root.add_child(fresh)
	await process_frame
	fresh.generate()   # _setup_material() - and so the biome_map uniform - only runs here

	var blank: Image = fresh.biome_image()
	check(blank != null, "biome_image() returned null with nothing painted")
	check(blank.get_width() > 0 and blank.get_width() == blank.get_height(),
			"the blank biome image is not square: %dx%d" % [blank.get_width(), blank.get_height()])
	var corner := blank.get_pixel(0, 0)
	var centre := blank.get_pixel(blank.get_width() / 2, blank.get_height() / 2)
	check(close(corner, Color(0.5, 0.5, 0.5, 1.0)) and close(centre, corner),
			"a fresh biome map should read neutral (0.5, 0.5, 0.5) everywhere, got %s" % corner)

	var texture: Texture2D = fresh.material.get_shader_parameter("biome_map")
	check(texture != null, "_setup_material() did not give the shader a biome_map texture")
	check(texture != null and Vector2i(texture.get_size()) == blank.get_size(),
			"the shader's biome_map is not the same size as biome_image()")

	# Paint one pixel by hand, the way a brush dab would, and show it live: no save yet.
	#
	# What actually reached the GPU is not checked by reading the texture back - under
	# --headless there is no real rendering server behind it, so an ImageTexture never reports
	# an update through get_image() there (checked directly: it does not, even a frame later).
	# biome_image() is the CPU-side truth the shader's upload is always made from, so that is
	# what is checked instead; the render test (biome_paint_view) checks the pixels the shader
	# actually draws.
	var painted := blank
	painted.set_pixel(10, 10, Color(0.1, 0.9, 0.5, 1.0))
	fresh.set_biome_image(painted)
	var live_texture: Texture2D = fresh.material.get_shader_parameter("biome_map")
	check(live_texture == fresh._biome_texture,
			"set_biome_image() should reuse the same ImageTexture, updated in place, not swap it every dab")
	var live_pixel: Color = fresh.biome_image().get_pixel(10, 10)
	check(close(live_pixel, Color(0.1, 0.9, 0.5, 1.0)),
			"biome_image() does not show the dab that was just painted: got %s" % live_pixel)

	# Save it (what the paint tool does when a stroke ends) and read it back into a second,
	# independent Terrain, the way a fresh editor session or the built game would.
	painted.save_png(ProjectSettings.globalize_path(TMP_PATH))

	var reloaded := StaticBody3D.new()
	reloaded.set_script(TERRAIN)
	reloaded.raw_path = "res://terrain/island.r16"
	reloaded.world_size = 620.0
	reloaded.height_scale = 180.0
	reloaded.biome_path = TMP_PATH
	root.add_child(reloaded)
	await process_frame
	reloaded.generate()

	var round_tripped: Image = reloaded.biome_image()
	var round_pixel := round_tripped.get_pixel(10, 10)
	check(close(round_pixel, Color(0.1, 0.9, 0.5, 1.0)),
			"the saved dab did not survive a save/load round trip: got %s" % round_pixel)
	var round_neutral := round_tripped.get_pixel(500, 500)
	check(close(round_neutral, Color(0.5, 0.5, 0.5, 1.0)),
			"a point nobody painted came back from disk as %s, not neutral" % round_neutral)
	check(round_tripped.get_format() == Image.FORMAT_RGBA8,
			"the loaded biome image is %s, not RGBA8 - Godot's importer may have recompressed it"
			% round_tripped.get_format())

	# reload_biome_map(): pick up a save made by someone else without a full rebuild.
	painted.set_pixel(20, 20, Color(0.9, 0.1, 0.1, 1.0))
	painted.save_png(ProjectSettings.globalize_path(TMP_PATH))
	reloaded.reload_biome_map()
	var after_reload: Color = reloaded.biome_image().get_pixel(20, 20)
	check(close(after_reload, Color(0.9, 0.1, 0.1, 1.0)),
			"reload_biome_map() did not pick up a change made on disk: got %s" % after_reload)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PATH))
	print("biome_map_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
