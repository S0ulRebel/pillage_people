extends SceneTree
## Run: D:\Godot\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tests/underwater_view.gd
##
## Puts the camera in the sea and takes pictures: half in at the waterline, in the shallows
## over the sand, down in open water, and looking up at the surface. Then measures each one
## the way the reference was measured - median colour of the top, middle and bottom thirds -
## and prints it beside the reference's numbers, so the fog is judged against the art rather
## than by eye. Not headless - no renderer there.

const SHOTS := "user://underwater"

## Median RGB of the top, middle and bottom thirds of the "Underwater (shallow)" and
## "Underwater (deep)" panels in art/references/water-rock-wood-plant-studies.jpg.
const REFERENCE := {
	"shallow": [Color(0.008, 0.431, 0.694), Color(0.094, 0.682, 0.722), Color(0.255, 0.584, 0.58)],
	"deep": [Color(0.098, 0.765, 0.953), Color(0.027, 0.486, 0.8), Color(0.008, 0.31, 0.522)],
}

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("underwater views need a renderer")
		quit(1)
		return
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 90:
		await process_frame
	scene.get_node("HUD").hide()
	scene.get_node("TouchControls").hide()
	# Both irises, or their dark ring is in every measurement.
	scene.get_node("Spyglass").hide()
	scene.get_node("GlassView").hide()
	scene.get_node("Player").set_physics_process(false)
	var terrain := scene.get_node("Terrain")
	var ocean := scene.get_node("Ocean") as Ocean
	var under := scene.get_node("Underwater") as Underwater
	var sea: float = terrain.sea_level()
	# The sea stands still for the pictures. The camera is put AT the surface for the half-in
	# shot, and a swell moving at half a metre a second carries the waterline clean off a near
	# plane six centimetres tall in the frames between placing it and reading the picture back.
	ocean.wave_speed = 0.0
	# --nochop takes the sideways Gerstner displacement out of the waves. With it the surface
	# is a plain sum and the shader, the mesh and surface_y all have to agree; if the
	# waterline check below fails only WITH the displacement, the solve for it is what broke.
	if "--nochop" in OS.get_cmdline_user_args():
		# Through the setter, which pushes it to the shader as well: surface_y reads the
		# property, and zeroing only the uniform leaves it solving with the full displacement
		# while the mesh has none.
		ocean.choppiness = 0.0
	DirAccess.make_dir_recursive_absolute(SHOTS)

	# Its own camera: the rig keeps writing to the rigged one every frame.
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.fov = 60.0
	camera.far = 1000.0
	camera.current = true

	# Walk out from the island's centre until there is open water, noting where the sand
	# first goes under (the shallows) and where it is as deep as this sea gets - the bed
	# slopes gently to about seven metres at the edge of the map, there is no deeper.
	var wading := Vector3.ZERO
	var shallows := Vector3.ZERO
	var deep := Vector3.ZERO
	var out := Vector3(0.0, 0.0, 1.0)
	for step in range(1, 400):
		var p: Vector3 = out * float(step)
		var depth: float = sea - terrain.height_at(p.x, p.z)
		if wading == Vector3.ZERO and depth >= 1.3:
			wading = Vector3(p.x, sea, p.z)
		if shallows == Vector3.ZERO and depth >= 2.5:
			shallows = Vector3(p.x, sea, p.z)
		if depth >= 5.5:
			deep = Vector3(p.x, sea, p.z)
			break
	if shallows == Vector3.ZERO or deep == Vector3.ZERO:
		push_error("no water found along +Z from the centre")
		quit(1)
		return
	print("wading at (%.0f, %.0f), shallows at (%.0f, %.0f), deep at (%.0f, %.0f)"
			% [wading.x, wading.z, shallows.x, shallows.z, deep.x, deep.z])

	# Half in, at the waterline, looking along the shore so both halves have something in them.
	var at := shallows + out * 6.0
	var split_eye: Vector3 = await _check_waterline(camera, under, ocean, at, "shallows")
	# And again where he wades. The bed rises inside shoal_depth here, the waves flatten over
	# it, and the mesh takes the depth under where each vertex STARTED - so a solve that reads
	# the depth at the query point is wrong exactly here and nowhere else. See surface_height.
	await _check_waterline(camera, under, ocean, wading + out * 0.5, "wading")
	_level(camera, split_eye)
	await _shot("00_half_in", camera)

	# In the shallows, a metre and a half down, looking a little down at the sand.
	camera.global_position = Vector3(at.x, sea - 1.5, at.z)
	camera.look_at(camera.global_position - out * 10.0 + Vector3.DOWN * 3.0, Vector3.UP)
	var shallow := await _shot("01_shallow", camera)
	_compare("shallow", shallow)

	# Open water, four metres down, level, looking out to sea.
	camera.global_position = Vector3(deep.x, sea - 4.0, deep.z)
	camera.look_at(camera.global_position + out * 10.0, Vector3.UP)
	var deep_shot := await _shot("02_deep", camera)
	_compare("deep", deep_shot)

	# The pass has to be doing something: the same view with it off must differ.
	under.visible = false
	under.set_process(false)
	var bare := await _shot("03_deep_no_pass", camera)
	under.set_process(true)
	var changed := _difference(deep_shot, bare)
	print("underwater pass changed samples: %d" % changed)
	if changed < 1000:
		_failures += 1
		push_error("the underwater pass is not changing the picture")

	# Looking up at the surface from three metres down.
	camera.global_position = Vector3(deep.x, sea - 3.0, deep.z)
	camera.look_at(camera.global_position + out * 3.0 + Vector3.UP * 4.0, Vector3.UP)
	await _shot("04_up", camera)

	# And above it, where the pass has to be off.
	camera.global_position = Vector3(deep.x, sea + 3.0, deep.z)
	camera.look_at(camera.global_position + out * 10.0 - Vector3.UP * 2.0, Vector3.UP)
	await _shot("05_above", camera)
	if under.visible:
		_failures += 1
		push_error("the underwater pass is still on with the camera 3 m above the sea")

	print("underwater views: ", "PASS" if _failures == 0 else "FAIL")
	quit(0 if _failures == 0 else 1)


## The waterline at `at`, three ways, which have to agree to the millimetre.
##
## It is FOUND, not computed from ocean.surface_y, because surface_y is one of the things under
## test - it was centimetres off once, which a near plane six centimetres tall cannot survive.
## So the camera is walked up and down on the shader's own split view until the crossing sits
## in the middle of the frame - and that view is what proves the split is in the picture at
## all. The picture alone cannot: the terrain paints the seabed teal itself, and the first
## version of this test passed with the pass drawing nothing.
##
## Returns where the camera ended up, half in.
func _check_waterline(camera: Camera3D, under: Underwater, ocean: Ocean, at: Vector3,
		label: String) -> Vector3:
	var guess: float = ocean.surface_y(at.x, at.z)
	var low := guess - 0.25
	var high := guess + 0.25
	under.material.set_shader_parameter("split_preview", true)
	var split: Image
	var crossing := -1
	for attempt in 10:
		var y := (low + high) * 0.5
		_level(camera, Vector3(at.x, y, at.z))
		split = await _shot("00_%s_split_preview" % label, camera)
		crossing = _crossing_row(split)
		if crossing >= 0:
			break
		# All water: the eye is too low. All air: too high.
		if split.get_pixel(split.get_width() / 2, split.get_height() / 2).g > 0.5:
			low = y
		else:
			high = y
	under.material.set_shader_parameter("split_preview", false)
	# Where the shader puts the surface at the eye: the crossing row, converted from pixels
	# up the near plane to metres.
	var half_plane: float = camera.near * tan(deg_to_rad(camera.fov * 0.5))
	var split_eye := camera.global_position
	var shader_surface: float = split_eye.y 			+ (0.5 - float(crossing) / float(split.get_height())) * 2.0 * half_plane
	# And where the sea's MESH is, found the same way with the pass hidden: from above it the
	# bottom of the frame shows the sea's top, from below it the bare seabed. All three are the
	# same waves - the history of getting them to agree is on surface_height in
	# waves.gdshaderinc and surface_y in ocean.gd. surface_y is the one everything floats on;
	# before it solved for the sideways displacement it was 102 mm above the mesh here.
	var mesh_surface: float = await _mesh_surface(camera, under, at, guess, half_plane)
	# Both of those are read off the near plane, which is camera.near ahead of the eye along
	# +X. surface_y is asked at that same point, not at the eye: five centimetres along a wave
	# slope of 0.2 is a centimetre, and the first version of this comparison reported exactly
	# that as an error in surface_y.
	var cpu_surface: float = ocean.surface_y(at.x + camera.near, at.z)
	print("waterline (%s): shader %.4f m, mesh %.4f m, surface_y %.4f m (shader-mesh %+.1f mm, surface_y-mesh %+.1f mm)"
			% [label, shader_surface, mesh_surface, cpu_surface,
			(shader_surface - mesh_surface) * 1000.0, (cpu_surface - mesh_surface) * 1000.0])
	if crossing < 0:
		_failures += 1
		push_error("%s: never found the air-to-water crossing in the frame" % label)
	elif absf(shader_surface - mesh_surface) > 0.005:
		_failures += 1
		push_error("%s: the waterline is %.0f mm off the sea's mesh"
				% [label, (shader_surface - mesh_surface) * 1000.0])
	if absf(cpu_surface - mesh_surface) > 0.005:
		_failures += 1
		push_error("%s: surface_y is %.0f mm off the sea's mesh - things float on that"
				% [label, (cpu_surface - mesh_surface) * 1000.0])
	if crossing >= 0:
		var band := 0
		for y in range(crossing, mini(crossing + 40, split.get_height())):
			var c := split.get_pixel(split.get_width() / 2, y)
			if c.g > 0.5 and c.r > 0.5:
				band += 1
		print("waterline band (%s): %d px" % [label, band])
		if band < 5:
			_failures += 1
			push_error("%s: no waterline band under the crossing" % label)
	return split_eye


## Puts the camera at `eye`, looking level along +X.
func _level(camera: Camera3D, eye: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(eye + Vector3(1.0, 0.0, 0.0), Vector3.UP)


## The height of the sea's mesh at the eye, found by bisection with the underwater pass off:
## the bottom middle of the frame shows the sea's top from above the mesh and the seabed from
## below it. Classified against a capture from each side, not against a fixed colour.
func _mesh_surface(camera: Camera3D, under: Underwater, at: Vector3, guess: float,
		half_plane: float) -> float:
	under.set_process(false)
	under.visible = false
	# The sea drawn as its flat opaque palette, so its top is one colour and the seabed is
	# another however shallow the water: shaded, a metre of turquoise over sand and the sand
	# itself are close enough to confuse the classification below.
	var ocean := under.ocean
	ocean.material.set_shader_parameter("palette_preview", true)
	var above := await _bottom_pixel(camera, Vector3(at.x, guess + 0.3, at.z))
	var below := await _bottom_pixel(camera, Vector3(at.x, guess - 0.3, at.z))
	print("mesh probe: sea top reads %s, seabed reads %s" % [above, below])
	var low := guess - 0.3
	var high := guess + 0.3
	for attempt in 10:
		var y := (low + high) * 0.5
		var seen := await _bottom_pixel(camera, Vector3(at.x, y, at.z))
		if _distance(seen, above) < _distance(seen, below):
			high = y
		else:
			low = y
	ocean.material.set_shader_parameter("palette_preview", false)
	under.set_process(true)
	# The bottom of the frame is half a near plane below the eye, so the mesh is that much
	# below the eye that just stopped seeing it.
	return (low + high) * 0.5 - half_plane


func _bottom_pixel(camera: Camera3D, eye: Vector3) -> Color:
	_level(camera, eye)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	return image.get_pixel(image.get_width() / 2, image.get_height() - 2)


func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


## The row where the split view's middle column goes from air to water, or -1 if it does not,
## or does so more than once, or does so at the very edge of the frame.
func _crossing_row(split: Image) -> int:
	var x := split.get_width() / 2
	var found := -1
	for y in range(1, split.get_height()):
		if (split.get_pixel(x, y - 1).g > 0.5) != (split.get_pixel(x, y).g > 0.5):
			if found >= 0:
				return -1
			found = y
	if found < split.get_height() / 10 or found > split.get_height() * 9 / 10:
		return -1
	return found


func _shot(label: String, camera: Camera3D) -> Image:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := SHOTS + "/" + label + ".png"
	if image.save_png(path) != OK:
		_failures += 1
		push_error("could not save " + label)
	print("shot: ", ProjectSettings.globalize_path(path), " from ", camera.global_position)
	return image


## Median colour of each horizontal third, printed beside the reference's.
func _compare(name: String, image: Image) -> void:
	var thirds := _thirds(image)
	var reference: Array = REFERENCE[name]
	for i in 3:
		var got: Color = thirds[i]
		var want: Color = reference[i]
		print("%s %s: render (%.2f %.2f %.2f) reference (%.2f %.2f %.2f) off by (%+.2f %+.2f %+.2f)" % [
			name, ["top", "mid", "bot"][i], got.r, got.g, got.b, want.r, want.g, want.b,
			got.r - want.r, got.g - want.g, got.b - want.b])


func _thirds(image: Image) -> Array[Color]:
	var result: Array[Color] = []
	var height := image.get_height()
	for third in 3:
		var reds := PackedFloat32Array()
		var greens := PackedFloat32Array()
		var blues := PackedFloat32Array()
		for y in range(third * height / 3, (third + 1) * height / 3, 4):
			for x in range(0, image.get_width(), 4):
				var c := image.get_pixel(x, y)
				reds.append(c.r)
				greens.append(c.g)
				blues.append(c.b)
		reds.sort()
		greens.sort()
		blues.sort()
		var mid := reds.size() / 2
		result.append(Color(reds[mid], greens[mid], blues[mid]))
	return result


func _difference(a: Image, b: Image) -> int:
	var count := 0
	for y in range(0, a.get_height(), 3):
		for x in range(0, a.get_width(), 3):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				count += 1
	return count
