extends SceneTree
## Run: D:\Godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/sky_view.gd
##
## The sky against its sheets. art/references/sky-and-clouds-v1.png ("day sky.png") and
## night-sky-and-moon-v1.png ("night sky.png") were measured - median colour of the panel's
## top and bottom bands, of the lit and shaded cloud pixels, of the sun's disc, and the number
## of stars in a clear panel - and the sky is rendered from the beach and measured the same
## way: by day looking up (the zenith band) and out (the band over the sea), and by night with
## the sun sent under the horizon as world/day.gd sends it. Not headless - no renderer there.
##
## The fog's sky affect matters here: at 0.15 (main.tscn's old value) a seventh of the pale
## fog colour is mixed into the whole dome and the zenith cannot get darker than (0.29, ...)
## whatever the shader says; the sheet's zenith is (0.13, 0.50, 0.90). The check reads the
## scene as it is, so it says so if that is why it fails.

const SHOTS := "user://sky"

## From the sheets. Day: TROPICAL CLEAR top fifth and bottom fifth; TRADE-WIND CUMULUS cloud
## faces and shadow planes; the disc. Night: FULL MOON top fifth and middle, its clouds.
const DAY_ZENITH := Color(0.13, 0.50, 0.90)
const DAY_LOW := Color(0.47, 0.85, 0.99)
## The cloud's white-and-light faces and its blue-lavender mid-and-shadow stamps, measured
## on TRADE-WIND CUMULUS's big cloud up close.
const CLOUD_FACE := Color(0.95, 0.92, 0.91)
const CLOUD_PLANE := Color(0.72, 0.79, 0.93)
const SUN := Color(1.0, 0.96, 0.75)
const NIGHT_ZENITH := Color(0.05, 0.17, 0.43)
const NIGHT_MID := Color(0.05, 0.25, 0.56)
## FULL MOON's clouds through this file's own classifier (unsaturated pixels, faces above
## 0.62 of luminance, planes between 0.36 and 0.62), so the render is held to what the same
## sieve finds on the sheet.
const NIGHT_CLOUD_FACE := Color(0.70, 0.71, 0.85)
const NIGHT_CLOUD_PLANE := Color(0.49, 0.50, 0.61)
const MOON := Color(0.99, 0.96, 0.80)
## How much of the sky is cloud, by height: TRADE-WIND CUMULUS is 27% in its top third, 34% in
## the middle and 40% in the bottom, measured with _cloud_cover's own sieve. The views here
## are lower than the sheet's panel (it runs to about 55 degrees, these to 40), so the bottom
## band is held to at least the sheet's bottom third, and each band to at least the one above
## it: the cloud piles up toward the horizon, not away from it.
const COVER_LOW_MIN := 0.28
const COVER_LOW_MAX := 0.65
const COVER_MID_MIN := 0.20
## Cloud shadows at the same cover: some of the island in shadow, not all of it and not none.
const SHADOWED_MIN := 0.08
const SHADOWED_MAX := 0.5

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("sky views need a renderer")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
	for n in ["Day", "Wind"]:
		var node := scene.get_node_or_null(n)
		if node != null:
			node.set_process(false)
			node.set_physics_process(false)
	for n in ["HUD", "TouchControls", "Spyglass", "GlassView"]:
		var node := scene.get_node_or_null(n)
		if node != null:
			node.hide()
	var terrain := scene.get_node("Terrain")
	var ocean := scene.get_node("Ocean")
	var sun := scene.get_node("Sun") as DirectionalLight3D
	var player := scene.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	player.global_position = Vector3(0.0, terrain.sea_level() + 40.0, 0.0)
	var environment: Environment = scene.get_node("WorldEnvironment").environment
	var sky_material: ShaderMaterial = environment.sky.sky_material
	var terrain_material: ShaderMaterial = terrain.get("material")
	# The clouds stand still for the pictures.
	sky_material.set_shader_parameter("preview_time", 100.0)
	ocean.wave_speed = 0.0
	var to_sun := sun.global_transform.basis.z
	var bearing := atan2(to_sun.x, to_sun.z)
	print("sun: bearing %.0f deg, elevation %.1f deg; fog sky affect %.2f" % [rad_to_deg(bearing), rad_to_deg(asin(to_sun.y)), environment.fog_sky_affect])
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 60.0
	camera.far = 1000.0
	camera.current = true
	var eye := Vector3(0.0, terrain.height_at(0.0, 0.0) + 1.7, 0.0)

	# ---- Day ----------------------------------------------------------------------------
	# Camera3D.fov is the VERTICAL field of view (keep_aspect defaults to height), so 60 here
	# is 30 degrees above and below the centre row; rows map to elevation as
	# row = 0.5 - tan(elevation - pitch) / (2 tan 30).
	# Up: the frame spans 30 to 90 degrees of elevation; its top fifth is 78 to 90, the zenith.
	var up := await _shot("00_day_up", camera, eye, bearing, 60.0)
	_check_band("day zenith", _band_median(up, 0.0, 0.2, true), DAY_ZENITH, 0.10,
			"; if the fog's sky affect is above zero that alone pales the zenith - set it to 0 on the Environment in main.tscn")
	# Out over the sea at pitch 12: rows 57.6% to 66% of the frame are 7 down to 1.5 degrees
	# up, the sheet's bottom fifth; the horizon itself is at 68.4%.
	var low := await _shot("01_day_low", camera, eye, bearing, 12.0)
	_check_band("day low band", _band_median(low, 0.576, 0.66, true), DAY_LOW, 0.10, "")
	# Faces are the white and light stamps, planes the mid and shadow ones; the band for the
	# planes starts at 0.7 so the cloud's edge pixels, blended with the sky, stay out of it,
	# and only rows above the horizon count, so the horizon line and the hazed sea - the
	# same pale colour - do not.
	var clouds := _cloud_medians(low, 0.88, 0.70, 0.86, 0.6)
	_check_band("cloud faces", clouds[0], CLOUD_FACE, 0.08, "")
	_check_band("cloud shadow planes", clouds[1], CLOUD_PLANE, 0.08, "")
	var disc := _warm_median(low)
	_check_band("sun disc", disc, SUN, 0.06, " (no warm disc in frame counts as a miss)")

	await _check_cover(camera, eye, bearing)
	await _check_shadows(camera, terrain)

	# ---- Night --------------------------------------------------------------------------
	# What world/day.gd sets with the sun 30 degrees under: its daylight 0 everywhere it
	# publishes it, and the sun's direction, which puts the moon 30 degrees up opposite. The
	# sun is sent down at azimuth 90, so the moon stands at 270, between cloud masses (the
	# clouds hold still at preview_time 100) and above them - the moon check aims straight
	# at it and wants the disc, not a cloud in front of it.
	var night_azimuth := deg_to_rad(90.0)
	var night_sun := Vector3(sin(night_azimuth) * cos(0.52), -sin(0.52), cos(night_azimuth) * cos(0.52))
	var x_axis := Vector3.UP.cross(night_sun).normalized()
	sun.global_transform = Transform3D(x_axis, night_sun.cross(x_axis), night_sun, sun.global_position)
	sun.light_energy = 0.04
	sun.light_color = Color(0.62, 0.74, 1.0)
	environment.ambient_light_sky_contribution = 0.0
	environment.fog_light_color = Color(0.06, 0.10, 0.18)
	sky_material.set_shader_parameter("daylight", 0.0)
	sky_material.set_shader_parameter("sun_direction", night_sun)
	terrain_material.set_shader_parameter("daylight", 0.0)
	ocean.sun_direction = night_sun
	ocean.daylight = 0.0
	var night := await _shot("02_night", camera, eye, bearing, 30.0)
	var night_top := _band_median(night, 0.0, 0.2, true)
	var night_ok := _within(night_top, NIGHT_ZENITH, 0.10) or _within(night_top, NIGHT_MID, 0.10)
	print("night top band: (%.2f %.2f %.2f), sheet zenith (%.2f %.2f %.2f) to middle (%.2f %.2f %.2f)"
			% [night_top.r, night_top.g, night_top.b, NIGHT_ZENITH.r, NIGHT_ZENITH.g, NIGHT_ZENITH.b, NIGHT_MID.r, NIGHT_MID.g, NIGHT_MID.b])
	if not night_ok:
		_failures += 1
		push_error("the night sky's top band is off the sheet")
	var night_clouds := _cloud_medians(night, 0.62, 0.36, 0.62, 1.0)
	_check_band("moonlit cloud faces", night_clouds[0], NIGHT_CLOUD_FACE, 0.08, "")
	_check_band("moonlit cloud planes", night_clouds[1], NIGHT_CLOUD_PLANE, 0.08, "")
	var stars := _count_stars(night)
	print("stars in a 60 degree view: %d (the sheet's clear panels hold 40 to 60, and this frame is a little bigger)" % stars)
	if stars < 25 or stars > 200:
		_failures += 1
		push_error("star count %d is off the sheet" % stars)
	# The moon, straight on, from above the island so no hill is in the way.
	var moon_dir := -night_sun
	var moon_eye := Vector3(0.0, terrain.sea_level() + 120.0, 0.0)
	camera.global_position = moon_eye
	camera.look_at(moon_eye + moon_dir, Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var moon_shot := root.get_texture().get_image()
	moon_shot.save_png("%s/03_moon.png" % SHOTS)
	var centre := moon_shot.get_pixel(moon_shot.get_width() / 2, moon_shot.get_height() / 2)
	_check_band("the moon", centre, MOON, 0.08, " (the frame's centre pixel, aimed at the moon)")

	print("sky views: ", ProjectSettings.globalize_path(SHOTS))
	print("sky views: ", "PASS" if _failures == 0 else "FAIL")
	quit(0 if _failures == 0 else 1)


## Cloud cover by height, round the whole sky: four bearings at the chase camera's pitch,
## averaged. At pitch 12 in this 60 degree frame, the rows from 0.645 up to 0.5 are 2.5 to 12
## degrees up (clear of the pale horizon line, which the sieve would take for cloud), 0.5 to
## 0.284 are 12 to 26, and 0.284 to 0.04 are 26 to 40.
func _check_cover(camera: Camera3D, eye: Vector3, bearing: float) -> void:
	var low := 0.0
	var mid := 0.0
	var high := 0.0
	for turn in 4:
		var image := await _shot("04_cover_%d" % turn, camera, eye, bearing + float(turn) * PI * 0.5, 12.0)
		low += _cloud_cover(image, 0.5, 0.645) / 4.0
		mid += _cloud_cover(image, 0.284, 0.5) / 4.0
		high += _cloud_cover(image, 0.04, 0.284) / 4.0
	print("cloud cover round the sky: %.0f%% at 2-12 degrees, %.0f%% at 12-26, %.0f%% at 26-40 (sheet: 40%%, 34%%, 27%% bottom to top)"
			% [low * 100.0, mid * 100.0, high * 100.0])
	if low < COVER_LOW_MIN or low > COVER_LOW_MAX:
		_failures += 1
		push_error("the cloud low round the horizon is off the sheet")
	if mid < COVER_MID_MIN:
		_failures += 1
		push_error("the sky between 12 and 26 degrees is nearly empty")
	if mid > low or high > mid + 0.03:
		_failures += 1
		push_error("the cloud does not pile up toward the horizon")


## Cloud shadows, from above the island: the same frame with the cover taken away and put
## back, and the share of the frame that the clouds darken by a tenth or more. The sea and
## the ground both count - the shadows are meant to run across both.
func _check_shadows(camera: Camera3D, terrain: Node) -> void:
	var cover: float = ProjectSettings.get_setting("shader_globals/cloud_cover", {}).get("value", 0.55)
	var eye := Vector3(0.0, terrain.sea_level() + 240.0, 120.0)
	camera.global_position = eye
	camera.look_at(Vector3(0.0, terrain.sea_level(), -40.0), Vector3.UP)
	RenderingServer.global_shader_parameter_set("cloud_cover", 0.0)
	var clear := await _frame()
	RenderingServer.global_shader_parameter_set("cloud_cover", cover)
	var shaded := await _frame()
	shaded.save_png("%s/05_cloud_shadows.png" % SHOTS)
	var darker := 0
	var counted := 0
	for y in range(0, clear.get_height(), 4):
		for x in range(0, clear.get_width(), 4):
			var was := clear.get_pixel(x, y).get_luminance()
			if was < 0.05:
				continue
			counted += 1
			if shaded.get_pixel(x, y).get_luminance() < was * 0.9:
				darker += 1
	var share := float(darker) / float(maxi(counted, 1))
	print("cloud shadows at cover %.2f: %.0f%% of the island and sea darkened" % [cover, share * 100.0])
	if share < SHADOWED_MIN or share > SHADOWED_MAX:
		_failures += 1
		push_error("the cloud shadows cover %.0f%% of the frame" % (share * 100.0))


func _frame() -> Image:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## The share of the sky in a band of rows that is cloud. Cloud is pale (saturation under
## 0.33) and bright (value over 0.55); sky is saturated and blue. Anything else - the
## mountain, which since the terrain stamps fills half of two of these views, a palm - is
## neither and does not count either way.
func _cloud_cover(image: Image, from: float, to: float) -> float:
	var cloud := 0
	var sky := 0
	for y in range(int(image.get_height() * from), int(image.get_height() * to), 3):
		for x in range(0, image.get_width(), 3):
			var c := image.get_pixel(x, y)
			if c.s < 0.33 and c.v > 0.55:
				cloud += 1
			elif c.s >= 0.33 and c.v > 0.5 and c.h > 0.5 and c.h < 0.7:
				sky += 1
	return float(cloud) / float(maxi(cloud + sky, 1))


func _shot(tag: String, camera: Camera3D, eye: Vector3, yaw: float, pitch_degrees: float) -> Image:
	var pitch := deg_to_rad(pitch_degrees)
	camera.global_position = eye
	camera.look_at(eye + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)), Vector3.UP)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [SHOTS, tag])
	print("  %-12s pitch %+5.1f" % [tag, pitch_degrees])
	return image


func _within(got: Color, want: Color, tolerance: float) -> bool:
	return absf(got.r - want.r) <= tolerance and absf(got.g - want.g) <= tolerance \
			and absf(got.b - want.b) <= tolerance


func _check_band(name: String, got: Color, want: Color, tolerance: float, hint: String) -> void:
	print("%s: (%.2f %.2f %.2f), sheet (%.2f %.2f %.2f), tolerance %.2f" % [name, got.r, got.g, got.b, want.r, want.g, want.b, tolerance])
	if not _within(got, want, tolerance):
		_failures += 1
		push_error("%s is off the sheet%s" % [name, hint])


## Median colour of the sky pixels (saturated, bluer than red) between two fractions of the
## frame's height. With `sky_only` off, every pixel counts.
func _band_median(image: Image, from: float, to: float, sky_only: bool) -> Color:
	var reds := PackedFloat32Array()
	var greens := PackedFloat32Array()
	var blues := PackedFloat32Array()
	for y in range(int(image.get_height() * from), int(image.get_height() * to), 3):
		for x in range(0, image.get_width(), 3):
			var c := image.get_pixel(x, y)
			if sky_only and (c.s < 0.35 or c.b <= c.r or c.get_luminance() < 0.08):
				continue
			reds.append(c.r)
			greens.append(c.g)
			blues.append(c.b)
	if reds.size() < 50:
		return Color(-1.0, -1.0, -1.0)
	reds.sort()
	greens.sort()
	blues.sort()
	return Color(reds[reds.size() / 2], greens[greens.size() / 2], blues[blues.size() / 2])


## Median colours of the cloud pixels (unsaturated) that are lit faces (luminance above
## `face`) and shadow planes (between `plane_low` and `plane_high`).
func _cloud_medians(image: Image, face: float, plane_low: float, plane_high: float, rows_to: float) -> Array[Color]:
	# Six packed arrays rather than arrays of them: a packed array taken out of an Array is
	# a copy, and appending to it appends to nothing.
	var face_r := PackedFloat32Array()
	var face_g := PackedFloat32Array()
	var face_b := PackedFloat32Array()
	var plane_r := PackedFloat32Array()
	var plane_g := PackedFloat32Array()
	var plane_b := PackedFloat32Array()
	for y in range(0, int(image.get_height() * rows_to), 3):
		for x in range(0, image.get_width(), 3):
			var c := image.get_pixel(x, y)
			if c.s > 0.35:
				continue
			var l := c.get_luminance()
			if l > face:
				face_r.append(c.r)
				face_g.append(c.g)
				face_b.append(c.b)
			elif l > plane_low and l < plane_high:
				plane_r.append(c.r)
				plane_g.append(c.g)
				plane_b.append(c.b)
	return [_median_colour(face_r, face_g, face_b), _median_colour(plane_r, plane_g, plane_b)]


func _median_colour(reds: PackedFloat32Array, greens: PackedFloat32Array, blues: PackedFloat32Array) -> Color:
	if reds.size() < 50:
		return Color(-1.0, -1.0, -1.0)
	reds.sort()
	greens.sort()
	blues.sort()
	return Color(reds[reds.size() / 2], greens[greens.size() / 2], blues[blues.size() / 2])


## Median colour of the warm bright pixels: the sun's disc.
func _warm_median(image: Image) -> Color:
	var reds := PackedFloat32Array()
	var greens := PackedFloat32Array()
	var blues := PackedFloat32Array()
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var c := image.get_pixel(x, y)
			if c.r > 0.9 and c.g > 0.85 and c.b < 0.85:
				reds.append(c.r)
				greens.append(c.g)
				blues.append(c.b)
	if reds.size() < 20:
		return Color(-1.0, -1.0, -1.0)
	reds.sort()
	greens.sort()
	blues.sort()
	return Color(reds[reds.size() / 2], greens[greens.size() / 2], blues[blues.size() / 2])


## Bright specks: bright pixels whose four neighbours two pixels out are not bright. Clouds
## and the moon are wide, stars are not.
func _count_stars(image: Image) -> int:
	var count := 0
	for y in range(3, image.get_height() - 3, 1):
		for x in range(3, image.get_width() - 3, 1):
			if image.get_pixel(x, y).get_luminance() < 0.75:
				continue
			if image.get_pixel(x - 3, y).get_luminance() > 0.5 or image.get_pixel(x + 3, y).get_luminance() > 0.5 \
					or image.get_pixel(x, y - 3).get_luminance() > 0.5 or image.get_pixel(x, y + 3).get_luminance() > 0.5:
				continue
			# Count a star once, at its top-left bright pixel.
			if image.get_pixel(x - 1, y).get_luminance() >= 0.75 or image.get_pixel(x, y - 1).get_luminance() >= 0.75:
				continue
			count += 1
	return count
