extends SceneTree
## Run: D:\Godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/waterfall_view.gd
##
## Pictures of the waterfall in main.tscn, from where a player would see it: across the pool,
## at the foot looking up, side on, and from the top of the lip. Then measures the front view
## against the art: the "Waterfall" swatch in art/references/water-rock-wood-plant-studies.jpg
## and the jungle panel's falls in environment-kits-and-materials.jpg. Both draw a mid-blue
## column with long light streaks, and a white splash where it lands. The numbers are the
## point: a translucent veil over dark rock measures dark, however good it looks in the editor
## against the default grey. Not headless - no renderer there.
##
## Shots land in user://waterfall.

const SHOTS := "user://waterfall"

## Measured on the two sheets: the median of the falling column's pixels - (0.49, 0.69, 0.83)
## on the swatch, (0.44, 0.65, 0.85) and (0.44, 0.65, 0.87) on the jungle panel's two falls.
## The sheets are small and soft, so the tolerance is wide.
const COLUMN := Color(0.46, 0.67, 0.85)
## Where it lands is the whitest thing in both pictures. Its colour is not held to a number:
## on a thumbnail thirty pixels across the splash is blurred into the pool and the rock round
## it, and measures bluer than the white it is drawn as. What both sheets do agree on is that
## it is white, and whiter than the column - by this much at least, in luminance.
const SPLASH_WHITE := 0.78
const SPLASH_OVER_COLUMN := 0.10

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("waterfall views need a renderer")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 60:
		await process_frame
	for n in ["HUD", "TouchControls", "Spyglass", "GlassView"]:
		var node := scene.get_node_or_null(n)
		if node != null:
			node.hide()
	# The sun holds still. world/day.gd turns it a full circle in eight minutes, and the
	# renderer here is slow enough that two runs measured the same column at 0.38 and 0.57
	# under different light.
	var day := scene.get_node_or_null("Day")
	if day != null:
		day.set_process(false)
	var player := scene.get_node("Player") as Node3D
	player.set_physics_process(false)
	var falls := scene.get_node_or_null("Waterfall") as Path3D
	if falls == null or falls.curve == null or falls.curve.point_count < 2:
		push_error("main.tscn has no Waterfall with a curve")
		quit(1)
		return
	var curve := falls.curve
	var lip := falls.to_global(curve.get_point_position(0))
	var foot := falls.to_global(curve.get_point_position(curve.point_count - 1))
	# The way the water faces: across the fall, horizontal, pointing out from the cliff. The
	# curve runs from the lip out and down, so its horizontal run is "out".
	var out := Vector3(foot.x - lip.x, 0.0, foot.z - lip.z)
	if out.length() < 0.5:
		out = Vector3.FORWARD
	out = out.normalized()
	var across := out.cross(Vector3.UP).normalized()
	print("waterfall: lip %s, foot %s, drop %.1f m" % [lip, foot, lip.y - foot.y])
	# The captain is parked out of every frame.
	player.global_position = foot + out * 200.0 + Vector3.UP * 50.0

	DirAccess.make_dir_recursive_absolute(SHOTS)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 60.0
	camera.far = 1500.0
	camera.current = true
	var middle := lip.lerp(foot, 0.5)

	var front := await _shot("00_front", camera, foot + out * 34.0 + Vector3.UP * 6.0, middle)
	await _shot("01_foot", camera, foot + out * 11.0 + across * 3.0 + Vector3.UP * 2.0, foot + Vector3.UP * 3.0)
	await _shot("02_side", camera, middle + across * 30.0 + out * 8.0, middle)
	await _shot("03_lip", camera, lip + out * 6.0 + Vector3.UP * 5.0 + across * 2.0, lip.lerp(foot, 0.25))
	await _shot("04_far", camera, foot + out * 80.0 + across * 20.0 + Vector3.UP * 15.0, middle)

	# The column: a box round the fall a third of the way down, clear of the white lip. The
	# splash: a box just above where it lands. Both found by projecting the curve, so moving
	# the fall does not leave the test measuring rock.
	camera.global_position = foot + out * 34.0 + Vector3.UP * 6.0
	camera.look_at(middle, Vector3.UP)
	# In the viewport's own units, which the project stretches: 1920 by 1080 whatever the window.
	var size := root.get_visible_rect().size
	var column_at := camera.unproject_position(falls.to_global(curve.sample_baked(curve.get_baked_length() * 0.35))) / size
	var splash_at := camera.unproject_position(foot + Vector3.UP * 1.2) / size
	print("column at %s, splash at %s (fractions of the frame)" % [column_at, splash_at])
	# The streaks move, and one frame can catch a dark one sliding through the box - the same
	# fall measured 0.51 on one run and 0.27 on the next. So the column is sampled over two
	# seconds and the medians averaged, which is what the eye does looking at it.
	var column := Color(0.0, 0.0, 0.0)
	var samples := 8
	for i in samples:
		for f in 15:
			await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		column += _median(frame, column_at.x - 0.012, column_at.x + 0.012,
				column_at.y - 0.04, column_at.y + 0.04) / float(samples)
	_check("column", column, COLUMN, 0.12)
	var landing := _median(front, splash_at.x - 0.03, splash_at.x + 0.03,
			splash_at.y - 0.03, splash_at.y + 0.01)
	print("splash: (%.2f %.2f %.2f), luminance %.2f against the column's %.2f"
			% [landing.r, landing.g, landing.b, landing.get_luminance(), column.get_luminance()])
	if landing.get_luminance() < SPLASH_WHITE \
			or landing.get_luminance() < column.get_luminance() + SPLASH_OVER_COLUMN:
		_failures += 1
		push_error("where the waterfall lands is not white - the splash or the foam is missing")

	# Behind the fall, where the caves are meant to go: the water seen from its back.
	var low := falls.to_global(curve.sample_baked(curve.get_baked_length() * 0.9))
	await _shot("05_behind", camera, low - out * 5.0 + Vector3.UP * 3.0, low + out * 6.0)
	# Night, set the way world/day.gd sets it with the sun under the horizon. The water has
	# to go dark with everything else, not glow.
	var sun := scene.get_node_or_null("Sun") as DirectionalLight3D
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if sun != null and world != null:
		sun.light_energy = 0.04
		sun.light_color = Color(0.62, 0.74, 1.0)
		world.environment.ambient_light_sky_contribution = 0.0
		world.environment.fog_light_color = Color(0.06, 0.10, 0.18)
		var night := await _shot("06_night", camera, foot + out * 34.0 + Vector3.UP * 6.0, middle)
		var dark := _median(night, column_at.x - 0.012, column_at.x + 0.012,
				column_at.y - 0.04, column_at.y + 0.04)
		print("night column: (%.2f %.2f %.2f)" % [dark.r, dark.g, dark.b])
		if dark.get_luminance() > column.get_luminance() * 0.6:
			_failures += 1
			push_error("the waterfall does not darken at night")
	print("%d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _shot(tag: String, camera: Camera3D, eye: Vector3, target: Vector3) -> Image:
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, tag])
	print("  %s" % tag)
	return image


func _check(name: String, got: Color, want: Color, tolerance: float) -> void:
	print("%s: (%.2f %.2f %.2f), swatch (%.2f %.2f %.2f), tolerance %.2f"
			% [name, got.r, got.g, got.b, want.r, want.g, want.b, tolerance])
	if absf(got.r - want.r) > tolerance or absf(got.g - want.g) > tolerance \
			or absf(got.b - want.b) > tolerance:
		_failures += 1
		push_error("the waterfall's %s is off the swatch" % name)


## Median colour of a rectangle given in fractions of the frame.
func _median(image: Image, x0: float, x1: float, y0: float, y1: float) -> Color:
	var reds := PackedFloat32Array()
	var greens := PackedFloat32Array()
	var blues := PackedFloat32Array()
	var w := image.get_width()
	var h := image.get_height()
	for y in range(clampi(int(y0 * h), 0, h - 1), clampi(int(y1 * h), 1, h), 2):
		for x in range(clampi(int(x0 * w), 0, w - 1), clampi(int(x1 * w), 1, w), 2):
			var c := image.get_pixel(x, y)
			reds.append(c.r)
			greens.append(c.g)
			blues.append(c.b)
	if reds.is_empty():
		return Color.BLACK
	reds.sort()
	greens.sort()
	blues.sort()
	var mid := reds.size() / 2
	return Color(reds[mid], greens[mid], blues[mid])
