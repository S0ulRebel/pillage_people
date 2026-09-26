extends SceneTree
## Run twice, once per env value of BIOME_PAINT ("0" or "1"):
##   godot --path . --resolution 1280x720 --script res://tests/biome_paint_view.gd
##
## Renders the same island, same two points every time - a cliff (rock by slope alone) and a
## flat mid-elevation patch (grass by height alone), both found by search rather than
## hand-picked. With BIOME_PAINT=1, both are additionally painted with one custom palette
## entry - a colour the automatic rules have no name for, magenta, proving this paints an
## actual named biome and not just a bias on the existing rock/vegetation/jungle rules (an
## earlier version of this tool only had those three). Each run prints one RESULT line with
## the pixel colour it saw at both points; a separate small script
## (tests/_compare_biome_paint.py) runs both and checks that painting moved both points
## visibly towards magenta - low green, high red and blue - and that neither reads that way
## unpainted, since neither rock nor grass ever does.
##
## Two processes, not one render before painting and a second after: the first version of this
## test tried that with one camera pulled back far enough to unproject both points into a
## single shot, and got the identical pixel before and after every time. The cause was not
## staleness - a live-updated texture does show up in the very next render, checked directly -
## it was that the rock point sits on a near-vertical cliff, and from that pulled-back angle
## its own nearer ground stood in front of it: unproject_position() gave the screen pixel that
## point WOULD occupy if it were the closest surface there, not a guarantee that it was, so the
## test kept reading whatever was actually in front of it instead. Looking straight at one
## point at a time (_look_and_sample) and reading dead centre of the screen, which look_at
## always aims at the nearest thing on that exact line, does not have this problem - but two
## renders of the same scene needing two different live states is still simplest as two runs.

const TMP_PALETTE := "res://tests/_tmp_paint_view_palette.png"
const PAINTED_COLOUR := Color(0.95, 0.05, 0.85)   # magenta: no automatic rule ever draws this

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("_run")


## Central difference over a couple of metres, the same measure Ground.slope() and the grass
## and palm scatterers already reject on: 0 flat, 1 at 45 degrees.
func _slope(terrain: Node, x: float, z: float) -> float:
	var dx: float = terrain.height_at(x + 1.0, z) - terrain.height_at(x - 1.0, z)
	var dz: float = terrain.height_at(x, z + 1.0) - terrain.height_at(x, z - 1.0)
	return maxf(absf(dx), absf(dz)) * 0.5


## The most (rising) or least (not rising) sloped point within `radius` metres of `centre`,
## height in [min_height, max_height] - a local grid search rather than a walk in one
## direction, so a steep point and a flat point can be asked for close enough together to
## frame in one shot.
func _find_point(terrain: Node, centre: Vector2, radius: float, rising: bool,
		min_height: float, max_height: float) -> Vector2:
	var best := centre
	var best_slope := -1.0 if rising else 1e9
	var step := 2.0
	var steps := int(radius / step)
	for j in range(-steps, steps + 1):
		for i in range(-steps, steps + 1):
			var p := centre + Vector2(i, j) * step
			var h: float = terrain.height_at(p.x, p.y)
			if h < min_height or h > max_height:
				continue
			var s := _slope(terrain, p.x, p.y)
			if (rising and s > best_slope) or (not rising and s < best_slope):
				best_slope = s
				best = p
	return best


func _run() -> void:
	# One-entry palette, on disk before the terrain reads it, so it comes up painted from the
	# start of _ready() exactly as a saved project would.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PALETTE))
	var palette := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	palette.set_pixel(0, 0, PAINTED_COLOUR)
	palette.save_png(ProjectSettings.globalize_path(TMP_PALETTE))

	var terrain := StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.set_script(load("res://world/terrain.gd"))
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	terrain.biome_palette_path = TMP_PALETTE
	var scene := Node3D.new()
	root.add_child(scene)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	scene.add_child(sun)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.75, 0.92)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.35
	world.environment = env
	scene.add_child(world)
	scene.add_child(terrain)
	await process_frame
	terrain.generate()
	for k in 3:
		await process_frame

	var anchor := Vector2(60.0, -20.0)
	var sea: float = terrain.sea_level()
	var rock_point := _find_point(terrain, anchor, 40.0, true, sea + 3.0, sea + 150.0)
	# height above sea 8-15 m: past the sand (dry_sand_top ~3.5 m) and short of the jungle
	# line, so this reads as plain grass rather than sand or jungle.
	var grass_point := _find_point(terrain, anchor, 40.0, false, sea + 8.0, sea + 15.0)
	var rock_slope := _slope(terrain, rock_point.x, rock_point.y)
	var grass_slope := _slope(terrain, grass_point.x, grass_point.y)
	check(rock_slope > 0.5, "could not find a point steep enough to be rock automatically (got slope %.2f)" % rock_slope)
	# Comfortably under rock_begins (~0.39 - see terrain.gdshader), not dead flat: the search
	# grid is 2 m, and a point 8-15 m above sea level that happens to be a little bumpy is
	# still ground the automatic rules read as grass, never as rock.
	check(grass_slope < 0.3, "could not find a point flat enough to be grass automatically (got slope %.2f)" % grass_slope)

	if OS.get_environment("BIOME_PAINT") == "1":
		var image: Image = terrain.biome_image()
		_dab(image, terrain, rock_point, 1, 1.0, 5.0)
		_dab(image, terrain, grass_point, 1, 1.0, 5.0)
		terrain.set_biome_image(image)
		for k in 3:
			await process_frame

	# Two close-up shots, one per point, camera looking straight at it from just above and to
	# the side, sampling dead centre of the screen - not one pulled-back shot unprojecting
	# both points into it. Pulled back far enough to see both, the rock point (a near-vertical
	# cliff) was hidden behind its own nearer ground from every angle tried, and the "unprojected"
	# pixel silently showed whatever WAS in front of it instead - same colour every time,
	# looking exactly like painting had done nothing.
	var cam := Camera3D.new()
	scene.add_child(cam)
	cam.fov = 45.0
	cam.current = true
	var out_dir := OS.get_environment("BIOME_VIEW_OUT")
	var painted := OS.get_environment("BIOME_PAINT") == "1"

	var rock_pixel := await _look_and_sample(cam, terrain, rock_point, out_dir,
			"biome_rock_" + ("painted" if painted else "baseline") + ".png")
	var grass_pixel := await _look_and_sample(cam, terrain, grass_point, out_dir,
			"biome_grass_" + ("painted" if painted else "baseline") + ".png")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_PALETTE))
	print("RESULT rock_slope=%.3f grass_slope=%.3f rock_pixel=%.4f,%.4f,%.4f grass_pixel=%.4f,%.4f,%.4f"
			% [rock_slope, grass_slope, rock_pixel.r, rock_pixel.g, rock_pixel.b,
			grass_pixel.r, grass_pixel.g, grass_pixel.b])
	print("biome_paint_view render: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


## Points the camera straight at a world point from close by and slightly above, waits for it
## to actually draw, and reads the exact centre pixel - which look_at always puts the target
## on, so there is no unprojection and nothing to be occluded by something else instead.
func _look_and_sample(cam: Camera3D, terrain: Node, point: Vector2, out_dir: String, out_name: String) -> Color:
	var h: float = terrain.height_at(point.x, point.y)
	var target := Vector3(point.x, h, point.y)
	cam.global_position = target + Vector3(6.0, 10.0, 12.0)
	cam.look_at(target, Vector3.UP)
	for k in 4:
		await process_frame
	var image := root.get_texture().get_image()
	if out_dir != "":
		image.save_png(out_dir.path_join(out_name))
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


## The same brush maths as addons/biome_painter._dab (kept in step by eye, not by sharing code -
## this file has no addon to import from): every pixel within radius_m of centre_world moves
## towards (target_index, target_strength) by a soft circular falloff. A pixel switching to a
## different index starts that index's own opacity from 0 rather than inheriting whatever the
## old biome there had built up - irrelevant here, since every dab in this test targets the
## same index 1 from a blank start, but kept for parity with the real tool.
func _dab(image: Image, terrain: Node, centre_world: Vector2, target_index: int,
		target_strength: float, radius_m: float) -> void:
	var world_size: float = terrain.world_size
	var scale: float = image.get_width() / world_size
	var centre_px := Vector2((centre_world.x / world_size + 0.5) * image.get_width(),
			(centre_world.y / world_size + 0.5) * image.get_height())
	var radius_px := radius_m * scale
	var x0 := maxi(0, int(centre_px.x - radius_px))
	var x1 := mini(image.get_width() - 1, int(centre_px.x + radius_px))
	var y0 := maxi(0, int(centre_px.y - radius_px))
	var y1 := mini(image.get_height() - 1, int(centre_px.y + radius_px))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d := Vector2(x, y).distance_to(centre_px)
			if d > radius_px:
				continue
			var brush_strength := 1.0 - smoothstep(0.0, radius_px, d)
			var c := image.get_pixel(x, y)
			var current_index := int(round(c.r * 255.0))
			var base_strength := c.g if (target_index == 0 or current_index == target_index) else 0.0
			c.r = float(target_index) / 255.0
			c.g = lerpf(base_strength, target_strength, brush_strength)
			image.set_pixel(x, y, c)
