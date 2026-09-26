extends SceneTree
## Run: godot --headless --path . --script res://tests/biome_map_check.gd
##
## Do the hand-painted biome override and its palette load, save, and reach the shader the way
## addons/biome_painter assumes they do?
##
## The paint tool never touches the mesh or the collider - only two textures - so nothing here
## can be checked by dropping a ray on the ground the way the stamp and tunnel tests do, and
## --headless has no real rendering server behind an ImageTexture, so reading one back never
## shows an update either (checked directly - it does not, even a frame later). What is
## checked here: an unpainted island gets a real, blank map and a real, sensible palette rather
## than nothing; both round-trip through disk exactly; the shader's two uniforms are real
## textures of the right size; and biome_image()/biome_palette_image() - the CPU-side images
## the next upload is always made from - reflect every paint, every palette edit and every
## reload straight away. What the shader actually draws with them is checked in
## tests/biome_paint_view.gd, a real (non-headless) render.

const TERRAIN := preload("res://world/terrain.gd")
const TMP_BIOME := "res://tests/_tmp_biome.png"
const TMP_PALETTE := "res://tests/_tmp_biome_palette.png"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


## Within one 8-bit step: an RGBA8 image rounds a value on write, never exactly back to it, so
## an exact is_equal_approx() would fail on the very first read of a texel nobody painted.
func close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01


func _make_terrain(biome_path: String, palette_path: String) -> Node:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	terrain.biome_path = biome_path
	terrain.biome_palette_path = palette_path
	root.add_child(terrain)
	return terrain


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_BIOME))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PALETTE))

	# Nothing on disk yet: a real, blank map (index 0 everywhere - "nothing painted") and a
	# real, four-colour palette built from this terrain's own grass/jungle/sand/rock, not null
	# and not empty.
	var fresh := _make_terrain(TMP_BIOME, TMP_PALETTE)
	await process_frame
	fresh.generate()   # _setup_material() - and so both uniforms - only runs here

	var blank: Image = fresh.biome_image()
	check(blank != null, "biome_image() returned null with nothing painted")
	check(blank.get_width() > 0 and blank.get_width() == blank.get_height(),
			"the blank biome image is not square: %dx%d" % [blank.get_width(), blank.get_height()])
	var corner := blank.get_pixel(0, 0)
	var centre := blank.get_pixel(blank.get_width() / 2, blank.get_height() / 2)
	check(close(corner, Color(0.0, 0.0, 0.0, 1.0)) and close(centre, corner),
			"a fresh biome map should read index 0, strength 0 everywhere, got %s" % corner)

	var palette: Image = fresh.biome_palette_image()
	check(palette != null and palette.get_height() == 1,
			"biome_palette_image() should be one row, got height %d" % (0 if palette == null else palette.get_height()))
	check(palette != null and palette.get_width() == 4,
			"a fresh palette should default to 4 entries (grass, jungle, sand, rock), got %d"
			% (0 if palette == null else palette.get_width()))
	check(close(palette.get_pixel(0, 0), fresh.grass_colour),
			"the default palette's first entry should be this terrain's own grass colour")
	check(close(palette.get_pixel(3, 0), fresh.rock_colour),
			"the default palette's fourth entry should be this terrain's own rock colour")

	var texture: Texture2D = fresh.material.get_shader_parameter("biome_map")
	check(texture != null and Vector2i(texture.get_size()) == blank.get_size(),
			"the shader's biome_map is not a real texture of the right size")
	var palette_texture: Texture2D = fresh.material.get_shader_parameter("biome_palette")
	check(palette_texture != null and Vector2i(palette_texture.get_size()) == palette.get_size(),
			"the shader's biome_palette is not a real texture of the right size")

	# Paint one pixel by hand - index 3 (rock, the fourth entry), strength 0.8 - the way a
	# brush dab would, and show it live: no save yet.
	#
	# What actually reached the GPU is not checked by reading the texture back - under
	# --headless there is no real rendering server behind it, so an ImageTexture never reports
	# an update through get_image() there (checked directly: it does not, even a frame later).
	# biome_image() is the CPU-side truth the shader's upload is always made from, so that is
	# what is checked instead; the render test (biome_paint_view) checks the pixels the shader
	# actually draws.
	var painted := blank
	painted.set_pixel(10, 10, Color(4.0 / 255.0, 0.8, 0.0, 1.0))
	fresh.set_biome_image(painted)
	var live_texture: Texture2D = fresh.material.get_shader_parameter("biome_map")
	check(live_texture == fresh._biome_texture,
			"set_biome_image() should reuse the same ImageTexture, updated in place, not swap it every dab")
	var live_pixel: Color = fresh.biome_image().get_pixel(10, 10)
	check(close(live_pixel, Color(4.0 / 255.0, 0.8, 0.0, 1.0)),
			"biome_image() does not show the dab that was just painted: got %s" % live_pixel)

	# Save it (what the paint tool does when a stroke ends) and read it back into a second,
	# independent Terrain, the way a fresh editor session or the built game would.
	painted.save_png(ProjectSettings.globalize_path(TMP_BIOME))

	var reloaded := _make_terrain(TMP_BIOME, TMP_PALETTE)
	await process_frame
	reloaded.generate()

	var round_tripped: Image = reloaded.biome_image()
	var round_pixel := round_tripped.get_pixel(10, 10)
	check(close(round_pixel, Color(4.0 / 255.0, 0.8, 0.0, 1.0)),
			"the saved dab did not survive a save/load round trip: got %s" % round_pixel)
	var round_blank := round_tripped.get_pixel(500, 500)
	check(close(round_blank, Color(0.0, 0.0, 0.0, 1.0)),
			"a point nobody painted came back from disk as %s, not blank" % round_blank)
	check(round_tripped.get_format() == Image.FORMAT_RGBA8,
			"the loaded biome image is %s, not RGBA8 - Godot's importer may have recompressed it"
			% round_tripped.get_format())

	# reload_biome_map(): pick up a save made by someone else without a full rebuild.
	painted.set_pixel(20, 20, Color(1.0 / 255.0, 1.0, 0.0, 1.0))
	painted.save_png(ProjectSettings.globalize_path(TMP_BIOME))
	reloaded.reload_biome_map()
	var after_reload: Color = reloaded.biome_image().get_pixel(20, 20)
	check(close(after_reload, Color(1.0 / 255.0, 1.0, 0.0, 1.0)),
			"reload_biome_map() did not pick up a change made on disk: got %s" % after_reload)

	# A saved, custom palette (what "+ Add" in the dock does) round-trips too, and
	# reload_biome_palette() picks it up the same way reload_biome_map() does above.
	var custom_palette := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	custom_palette.set_pixel(0, 0, Color(0.9, 0.1, 0.6))
	custom_palette.set_pixel(1, 0, Color(0.1, 0.1, 0.1))
	custom_palette.save_png(ProjectSettings.globalize_path(TMP_PALETTE))
	reloaded.reload_biome_palette()
	var loaded_palette: Image = reloaded.biome_palette_image()
	check(loaded_palette.get_width() == 2, "reload_biome_palette() kept the old width (%d), not the new one"
			% loaded_palette.get_width())
	check(close(loaded_palette.get_pixel(0, 0), Color(0.9, 0.1, 0.6)),
			"the saved palette's first colour did not survive a save/load round trip")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_BIOME))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PALETTE))
	print("biome_map_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
