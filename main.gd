extends Node3D
## Drops the player onto the generated terrain, wires the camera to it, and shows the controls.
##
## Run with --screenshot to save a picture after a few frames and quit (used to check the
## project renders without opening the editor).

const CoastalStudy = preload("res://world/coastal_study.gd")
const Grunts = preload("res://actors/grunt/grunts.gd")
const Hud = preload("res://ui/hud.gd")
const Rocks = preload("res://props/rock/rocks.gd")
const FishSchoolScene = preload("res://props/fish/fish_school.tscn")
const CargoField = preload("res://props/cargo/cargo_field.gd")
const GrassScene = preload("res://props/grass/grass.tscn")
const Palms = preload("res://props/palm/palms.gd")
const Corals = preload("res://props/coral/corals.gd")
const ShipScene = preload("res://props/ship/ship.tscn")
const SharkScene = preload("res://props/shark/shark.tscn")
const Music = preload("res://systems/music.gd")
const Sfx = preload("res://systems/sfx.gd")
const Ambience = preload("res://systems/ambience.gd")
const Modes = preload("res://tests/modes.gd")
const Crosshair = preload("res://ui/crosshair.gd")
## How far up a body the shot is aimed, in metres. Its origin is at the feet, so this is the
## difference between shooting a man in the chest and shooting the sand he is standing on.
const AIM_CHEST := 1.0
## Degrees the barrel swings between the top of the screen and the bottom. See aim_look.
const AIM_SKY_DEGREES := 55.0
const AIM_GROUND_DEGREES := 40.0
## How far out an aim at nothing is placed, in metres. Only has to be past anything he could
## be shooting at; the shot itself is capped by the gun's own carry.
const AIM_SKY_RANGE := 120.0

var _glass: Spyglass
var _crosshair: Crosshair
## Where the crosshair was when the mouse went down on a cannon. The bearing locks on
## that press, so the crosshair locks with it - letting it follow the mouse up the screen
## while the elevation is being dragged would draw a promise the gun is not making.
var _cannon_mark := Vector2.ZERO
var _coastal_study: Node3D

## Grunts, scattered around the island. They idle until the player comes near, walk over and
## swing at him - see actors/grunt/grunt.gd.
@export var enemy_count := 5
## How far out they are scattered. Far enough that none is visible from the spawn, so they are
## something you walk into rather than something waiting on top of you.
@export var enemy_near := 18.0
@export var enemy_far := 45.0
## Generated rocks scattered over the island - see props/rock/rocks.gd. Zero turns them off.
@export var rock_count := 40
## Cargo washed up and adrift. Rigid bodies, so barrels roll when shoved, crates do not, and
## both bob when they end up in the sea - see props/cargo/cargo.gd.
@export var barrels_ashore := 5
@export var barrels_afloat := 4
@export var crates_ashore := 6
@export var crates_afloat := 3
## Grass tufts over the island's green band. One MultiMesh, so this is a count rather than a
## node budget - see props/grass/grass.gd.
## Clumps of grass, not tufts: each patch holds 7 to 20. See props/grass/grass.gd.
@export var grass_patches := 70
## Palms along the shore. Nodes rather than a MultiMesh: there are a dozen and you walk into
## them - see props/palm/palm.gd.
@export var palm_count := 14

## Metres of water a school needs. It keeps 1.2 m under the surface and 0.7 m over the seabed,
## so below about three there is nowhere left for it to swim and it spends its life pinned
## between the two rules.
const WATER_FOR_FISH := 3.2

## Fish, for when NO FishSchool nodes have been placed in main.tscn. Three are placed, so these
## are the fallback - a placed school's size is its own `count`, set on the node. Several small
## schools beat one large one either way, for the reason in _stock_fish.
@export var fish_schools := 3
@export var fish_per_school := 120
## Corals, grown on the floor of whatever dive crater the scene has. Per crater, not in total -
## see _grow_reef, which finds them rather than being told where they are.
@export var coral_count := 26
## How long the captain lies there before the island resets. His death clip runs 2.63 s, so
## this lets it finish and land before anything moves.
@export var restart_delay := 3.4

@onready var _terrain: StaticBody3D = $Terrain
@onready var _player: CharacterBody3D = $Player
@onready var _camera_rig: Node3D = $CameraRig
@onready var _ocean: MeshInstance3D = $Ocean


## Adds the player's health bar to the HUD layer that is already in the scene.
##
## Built here rather than placed in main.tscn so it can follow whatever the player's max_health
## is set to, and so it is wired to the signals in one place instead of half in the scene.
func _add_health_bar() -> void:
	var bar: Control = Hud.new()
	bar.name = "PlayerHealth"
	$HUD.add_child(bar)
	bar.show_health(_player.health(), _player.max_health)
	_player.damaged.connect(func(_amount: int, remaining: int) -> void:
		bar.show_health(remaining, _player.max_health))
	_player.revived.connect(func() -> void:
		bar.show_health(_player.health(), _player.max_health))


## Puts the island back after the captain is killed.
##
## The whole scene is reloaded rather than the pieces being put back one at a time. Respawning
## by hand means remembering every stateful thing there is - health, position, each grunt's
## health and its corpse, the scatter, whatever gets added next - and the list only grows. A
## reload cannot miss any of it, and at this size it is instant.
##
## The wait is so the death clip actually plays. Cutting to a fresh island the instant he dies
## reads as a bug rather than as dying.
func _on_player_died() -> void:
	if not is_inside_tree():
		return
	# The iris shuts ON him rather than after him: it starts closing straight away and takes
	# restart_delay to do it, so the last thing visible is the captain going down, framed
	# tighter and tighter. Waiting the delay and THEN fading would spend the whole death clip
	# on a wide shot and the reload on a black one.
	if _glass != null:
		await _glass.close(restart_delay)
	else:
		await get_tree().create_timer(restart_delay).timeout
	if is_inside_tree():
		get_tree().reload_current_scene()


## The spyglass iris, shut, so the scene opens into view rather than appearing.
##
## Skipped in the capture and test modes for the same reason the music is: --screenshot settles
## for ninety frames and then grabs a picture, and a picture taken part-way through the opening
## is a black circle.
func _start_spyglass() -> void:
	if "--noassets" in OS.get_cmdline_user_args() or "--screenshot" in OS.get_cmdline_user_args():
		return
	_glass = Spyglass.new()
	_glass.name = "Spyglass"
	add_child(_glass)
	# Shut before the first frame is drawn, then opened. Snapping shut rather than starting
	# open and fading is what stops a single bright frame of the island appearing before the
	# iris takes hold - the usual giveaway that a fade was added afterwards.
	_glass.snap(false)
	_glass.open()

	# A SECOND iris, for the captain's own spyglass on Z. Separate from the one above because
	# the two want opposite things: that one is opaque, covers everything and ends shut; this
	# one stops part way open because it has to be looked through. Below it in the layer order,
	# so dying while glassing still fades to black over the top rather than under it.
	var view := Spyglass.new()
	view.name = "GlassView"
	view.layer = 90
	view.falloff_strength = 0.75
	add_child(view)
	# Open, so there is nothing over the picture until Z is pressed. Shut would be a black
	# screen: for this iris, out of the way means wide, not closed.
	view.snap(true)
	_camera_rig.glass = view


## Hands the sky the sun's real direction.
##
## The sky shader can read it from the engine as LIGHT0_DIRECTION, but only when the light is
## actually feeding the sky - and when it is not, the shader falls back to a constant without
## complaining. That is how the disc ended up at a bearing sixty degrees away from the light
## casting the shadows, visible only by going looking for it. Pushed here, they cannot differ.
func _tell_sky_about(to_sun: Vector3) -> void:
	var world := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world == null or world.environment == null or world.environment.sky == null:
		return
	var material := world.environment.sky.sky_material
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("sun_direction", to_sun)


## The flintlock's cursor, and firing it.
##
## Here rather than in the captain because both halves are questions about the CAMERA. Where
## the cursor points is a ray from the camera through the mouse, and the captain knows nothing
## about either - he is handed a point in the world and told to shoot at it.
func _start_crosshair() -> void:
	if "--noassets" in OS.get_cmdline_user_args() or "--screenshot" in OS.get_cmdline_user_args():
		return
	_crosshair = Crosshair.new()
	_crosshair.name = "Crosshair"
	add_child(_crosshair)
	_player.aiming_changed.connect(func(up: bool) -> void:
		_crosshair.visible = up or _player.is_manning())


## The fog under the sea. Built after the ocean, because it reads the ocean's waves.
func _start_underwater() -> void:
	var under := Underwater.new()
	under.name = "Underwater"
	add_child(under)
	under.setup(_ocean as Ocean)


## Turns the mouse position into a point in the world.
##
## Where the gun POINTS, as opposed to where the ball goes. Screen space, not world space.
##
## These are two different questions and answering both with one world point is why the pistol
## looked broken. The camera looks down, so every world point under the cursor is below him -
## and a gun honestly pointing at one reads as pointing at the floor no matter how high up the
## screen the pointer is. Aiming at the man rather than the sand under him helped and did not
## fix it; nothing that starts from a world point can, because the world point is down there.
##
## So the pose comes from the pointer instead: bearing from the camera, pitch from how far up
## the screen the cursor sits. Point up, the barrel goes up. What it will actually HIT is still
## aim_point below, and the two are allowed to disagree - a shot through palm fronds lands
## somewhere behind them, and that is fine. Looking wrong is not.
func aim_look() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _player == null:
		return Vector3.ZERO
	var at := get_viewport().get_mouse_position()
	var bearing := camera.project_ray_normal(at)
	bearing.y = 0.0
	if bearing.length() < 0.001:
		bearing = -camera.global_transform.basis.z
		bearing.y = 0.0
	bearing = bearing.normalized()

	var height := float(get_viewport().get_visible_rect().size.y)
	var horizon := _horizon_row(camera, at.x)
	# With the horizon off screen there is no natural zero, so the middle of the view is level.
	if horizon < 0.0:
		horizon = height * 0.5
	var pitch := 0.0
	if at.y < horizon:
		pitch = deg_to_rad(AIM_SKY_DEGREES) * clampf((horizon - at.y) / maxf(horizon, 1.0),
				0.0, 1.0)
	else:
		pitch = -deg_to_rad(AIM_GROUND_DEGREES) * clampf((at.y - horizon)
				/ maxf(height - horizon, 1.0), 0.0, 1.0)
	var eye: Vector3 = _player.global_position + Vector3.UP * AIM_CHEST
	return eye + (bearing * cos(pitch) + Vector3.UP * sin(pitch)) * AIM_SKY_RANGE


## Where the shot is aimed, in world space.
##
## Two answers, because there are two situations and they do not overlap.
##
## With something under the cursor there IS a world point, and it wins: click the thing, hit
## the thing. That is the whole promise of aiming with a cursor rather than a centre reticle,
## and screen position must not be allowed to argue with it.
##
## With NOTHING under the cursor - open sky, sea past the island, beyond the 400 m world -
## there is no world point to be consistent with, so the cursor's height on screen sets the
## elevation directly and he fires into the air. This used to return the far end of the camera
## ray, and that ray points DOWN from a camera looking down: a cursor on the sky aimed at a
## patch of ground hundreds of metres away, and slammed the barrel at the floor.
func aim_point() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return _player.global_position - _player.global_transform.basis.z * 10.0
	var at := get_viewport().get_mouse_position()
	# Above the horizon he is pointing at sky, whatever a 400 m ray eventually lands on. This
	# used to ask whether the ray MISSED, and it almost never did: the height map runs on under
	# the sea for the width of the world, so a cursor at the very top of the screen still found
	# distant ground. The elevation only engaged once the pointer left the window, and then it
	# jumped straight to full - which is exactly what it looked like.
	var horizon := _horizon_row(camera, at.x)
	if horizon >= 0.0 and at.y < horizon:
		return _sky_aim(camera, at, horizon)
	var from := camera.project_ray_origin(at)
	var along := camera.project_ray_normal(at) * 400.0
	var query := PhysicsRayQueryParameters3D.create(from, from + along)
	var skip: Array[RID] = [_player.get_rid()]
	# ...and the gun he is stood at. Its collider is a metre in front of him and square in the
	# ray's path, so without this the aim point snaps onto the carriage and the shot goes
	# nowhere. aim_point() only ever excluded the player because nothing else was ever that close.
	if _player.is_manning():
		for body in _player.cannon().find_children("*", "StaticBody3D", true, false):
			skip.append((body as StaticBody3D).get_rid())
	query.exclude = skip
	var found := get_world_3d().direct_space_state.intersect_ray(query)
	if found.is_empty():
		# Below the horizon and still nothing: off the edge of the world. Aim level and far.
		return _player.global_position + Vector3.UP * AIM_CHEST 				+ camera.project_ray_normal(at).slide(Vector3.UP).normalized() * AIM_SKY_RANGE
	# Aim at the MAN, not at the patch of him the ray grazed.
	#
	# Everything else returns the surface it struck, which is right for the ground and a rock.
	# But a target is a body, and the ground in front of it is roughly a metre below the
	# captain's hands - so with surface points alone the barrel could only ever point DOWN,
	# further down or level, and never up. Whichever way the cursor moved.
	var body := found.get("collider") as Node3D
	if body != null and body.has_method("take_damage"):
		return body.global_position + Vector3.UP * AIM_CHEST
	return found["position"]


## An aim at nothing. Keeps the camera's bearing, but takes the pitch from how far up the
## screen the cursor is: level at the horizon, AIM_SKY_DEGREES at the very top.
##
## The horizon is found rather than assumed, because the camera tilts - it is the screen row
## where the camera's own ray comes out flat.
## The screen row where the camera's own ray comes out flat, or -1 when the horizon is not on
## screen at all - which is a camera looking too steeply down for there to be any sky to aim at.
##
## Found rather than assumed at mid-screen, because the camera tilts. Binary search: the ray's
## y component falls monotonically as the row goes down the screen.
func _horizon_row(camera: Camera3D, x: float) -> float:
	var height := float(get_viewport().get_visible_rect().size.y)
	if camera.project_ray_normal(Vector2(x, 0.0)).y < 0.0:
		return -1.0
	var high := 0.0
	var low := height
	for step in 12:
		var middle := (high + low) * 0.5
		if camera.project_ray_normal(Vector2(x, middle)).y >= 0.0:
			high = middle
		else:
			low = middle
	return low


func _sky_aim(camera: Camera3D, at: Vector2, horizon: float) -> Vector3:
	var bearing := camera.project_ray_normal(at)
	bearing.y = 0.0
	if bearing.length() < 0.001:
		bearing = -camera.global_transform.basis.z
		bearing.y = 0.0
	bearing = bearing.normalized()
	# Level at the horizon, climbing to AIM_SKY_DEGREES at the top of the screen.
	var above := clampf((horizon - at.y) / maxf(horizon, 1.0), 0.0, 1.0)
	var pitch := deg_to_rad(AIM_SKY_DEGREES) * above
	var eye: Vector3 = _player.global_position + Vector3.UP * AIM_CHEST
	return eye + (bearing * cos(pitch) + Vector3.UP * sin(pitch)) * AIM_SKY_RANGE


func _unhandled_input(event: InputEvent) -> void:
	if _player == null:
		return
	# A gun he is stood at takes the click before a gun he is holding does.
	if _player.is_manning():
		_cannon_input(event)
		return
	if not _player.is_aiming():
		return
	if event.is_action_pressed("attack"):
		_player.shoot_at(aim_point())


## Press locks the bearing, dragging sets the elevation, release fires.
##
## The press/drag/release split lives here rather than in the cannon because it is entirely
## about the screen - pixels and a mouse - and the cannon knows only about angles. Same
## division as shoot_at and aim_point: the scene answers screen questions, the thing being
## driven answers world ones.
func _cannon_input(event: InputEvent) -> void:
	var gun: Node3D = _player.cannon()
	if gun == null:
		return
	if event.is_action_pressed("attack"):
		_cannon_mark = get_viewport().get_mouse_position()
		gun.press(_cannon_mark.y)
	elif event.is_action_released("attack"):
		gun.release()
	elif event is InputEventMouseMotion and gun.is_charging():
		gun.drag((event as InputEventMouseMotion).position.y)


func _process(_delta: float) -> void:
	# He turns to face the cursor while a ranged weapon is out. Where the cursor points is a
	# question about the camera and the screen, which he knows nothing about, so it is answered
	# here and handed over - the same split as shoot_at.
	if _player != null and _player.is_manning():
		# The cursor keeps steering the bearing right up until the press locks it; the cannon
		# itself decides whether to accept that, from lock_bearing_on_press.
		var gun_here: Node3D = _player.cannon()
		gun_here.aim_towards(aim_point())
		if _crosshair != null:
			# Shown while manning, and it doubles as the reload gauge - the same ring the
			# pistol uses, so a cannon that is not ready reads the same way a pistol does.
			_crosshair.visible = true
			# Pinned while charging. The bearing stopped moving on the press, so the crosshair
			# stops with it; the drag from here is elevation, which the mark does not show.
			var mark: Vector2 = _cannon_mark if gun_here.is_charging() else get_viewport().get_mouse_position()
			_crosshair.track(mark, gun_here.reload_fraction())
		return
	elif _player != null and _player.is_aiming():
		_player.aim_at(aim_look())
	# Stepping off the gun has to put the crosshair away again. It is raised by `aiming_changed`
	# when a pistol comes out, and manning a cannon switches it on directly in the branch above -
	# so nothing was ever switching it off, and it stayed on screen after leaving the gun.
	if _crosshair != null and _crosshair.visible and _player != null 			and not _player.is_aiming() and not _player.is_manning():
		_crosshair.visible = false
	if _crosshair == null or not _crosshair.visible:
		return
	var gun: Gun = _player.pistol()
	_crosshair.track(get_viewport().get_mouse_position(),
			gun.reload_fraction() if gun != null else 1.0)


## Brings up the sound effects and connects them to the things that make noise.
##
## Wired here rather than inside the player and the grunts, so neither has to know a sound
## system exists. They emit what happened; this decides what that sounds like.
func _start_sfx() -> void:
	if "--noassets" in OS.get_cmdline_user_args() or "--screenshot" in OS.get_cmdline_user_args():
		return
	var sfx: Node3D = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	_player.attacked.connect(func() -> void:
		sfx.play("swoosh", _player.global_position + Vector3.UP))
	_player.damaged.connect(func(_amount: int, _left: int) -> void:
		# The captain's own hits carry louder: they are happening to you, not near you.
		sfx.play("flesh", _player.global_position + Vector3.UP, 3.0))
	_player.stepped.connect(func() -> void:
		# Quieter than anything else here. Footsteps are constant, and at full volume they are
		# the only thing you hear.
		sfx.play("steps", _player.global_position, -9.0))
	_player.splashed.connect(func(entering: bool) -> void:
		if entering:
			sfx.play("splash", _player.global_position))
	# The guard. Clang is steel on steel and now means ONLY that - a block or a parry. It used
	# to play on every grunt that took a hit as well, which made a cut and a turned blade sound
	# the same, and the sound is the fastest way to tell them apart.
	# Both borrow the one clip, because it is the nearest thing in the
	# folder - a parry rings, a block is the same sound taken down and given room. Nothing else
	# plays clang at that moment (a parry does no damage, so no grunt is reporting a hit), so it
	# still reads. A dedicated pair is one generation away and would be better.
	_player.parried.connect(func(attacker: Node) -> void:
		sfx.play("clang", (attacker as Node3D).global_position + Vector3.UP, 3.0))
	_player.blocked.connect(func(attacker: Node) -> void:
		sfx.play("clang", (attacker as Node3D).global_position + Vector3.UP, -5.0))
	# The flintlock. Wired through the same signal route as everything else, so the gun knows
	# nothing about sound - it reports where the ball went and this decides what that sounds
	# like. Both clips are listed from the folder, so they are silent until they exist rather
	# than erroring: see sfx.gd.
	var gun: Gun = _player.pistol()
	if gun != null:
		gun.fired.connect(func(from: Vector3, _to: Vector3, _hit: Node) -> void:
			# Louder than a blade. It is a gunshot, and it is going off in your own hand.
			sfx.play("shot", from, 4.0))
		gun.reloaded.connect(func() -> void:
			sfx.play("reload", _player.global_position, -4.0))
	# The grunts are NOT wired here. _start_sfx runs before _spawn_enemies, so this used to
	# loop over an empty scene and silently connect nothing - a grunt could be cut down without
	# a sound and every part of it looked correct. Each one is wired as it is created instead,
	# which also covers any spawned later.


## Grows a reef on the floor of every dive crater.
##
## Takes no spawn point, unlike every other scatterer here, because the reef does not belong
## near the player - it belongs in the hole he dives into. That hole is authored in main.tscn,
## so writing its coordinates here would put the same number in two places and make the second
## one wrong the first time the crater moved.
##
## A crater is found the way tests/dive_hole_view.gd defines one: a stamp under Terrain that
## ADDs a negative height, below the waterline. Sharing the definition is the point - a second
## crater dug tomorrow gets a reef without anyone remembering to come back here.
func _grow_reef() -> void:
	if "--noassets" in OS.get_cmdline_user_args() or coral_count <= 0:
		return
	var craters: Array[Vector3] = []
	for child in _terrain.get_children():
		var stamp := child as TerrainStamp
		if stamp == null or stamp.mode != TerrainStamp.Mode.ADD or stamp.strength >= 0.0:
			continue
		var at := stamp.global_position
		if _terrain.height_at(at.x, at.z) < _terrain.sea_level():
			craters.append(at)
	if craters.is_empty():
		print("reef: no dive crater in the scene, so nothing to grow in")
		return
	var reef: Node3D = Corals.new()
	reef.name = "Reef"
	reef.count = coral_count
	add_child(reef)
	# Its own generator, like every other field: adding a coral should not move every grunt.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("corals") + randi()
	var grown := 0
	for centre in craters:
		grown += reef.scatter(_terrain, centre, rng)
	print("reef: %d corals of %d in %d crater(s)" % [grown, coral_count * craters.size(), craters.size()])


## One grunt's noises. Split out because the lambdas need to capture this grunt, not the last
## one in the loop.
func _wire_enemy(sfx: Node3D, grunt: Node3D) -> void:
	# Whatever hurt him, and from wherever. Keyed to the grunt being damaged rather than to the
	# captain landing a blow, so a pistol ball and a cutlass both sound like a hit without the
	# gun needing its own wiring.
	grunt.damaged.connect(func(_amount: int, _left: int) -> void:
		sfx.play("flesh", grunt.global_position + Vector3.UP))
	grunt.died.connect(func() -> void:
		sfx.play("death", grunt.global_position + Vector3.UP))


## One hull, off the beach the player starts on. Not scattered: there is a single ship.
## One shark, circling out past the shallows. Scenery - see props/shark/shark.gd.
##
## Placed off the beach the player starts on rather than somewhere in the round, because a
## shark nobody ever sees is the same as no shark.
func _loose_shark(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args():
		return
	var shark: Shark = SharkScene.instantiate()
	shark.name = "Shark"
	add_child(shark)
	shark.ocean = _ocean
	# Straight out from the island's centre through the beach, so the beat sits in open water
	# rather than halfway up the sand.
	var seaward := Vector3(around.x, 0.0, around.z)
	if seaward.length() < 0.01:
		seaward = Vector3.FORWARD
	seaward = seaward.normalized()
	var out: Vector3 = Vector3(around.x, _terrain.sea_level(), around.z) + seaward * 46.0
	# Along the shore is across the seaward line. He works up and down it, so from the beach
	# he passes rather than circles.
	var along := Vector3(-seaward.z, 0.0, seaward.x)
	if not shark.setup(out, along):
		shark.queue_free()
		return
	print("shark patrolling (%.0f, %.0f), %.0f m each way" % [out.x, out.z, shark.patrol])


## Schools of fish in the lagoon, on the same side of the island the shark patrols, so that the
## two are in the same water and the shark actually scatters something.
##
## Several small schools rather than one large one. Boids cost time per fish per NEIGHBOUR, and
## neighbours are what a dense school is made of, so doubling one school costs more than twice
## as much while two schools cost exactly twice - and two schools moving independently read as
## a populated sea, where one large one reads as a single object.
## The camera follows whoever takes hold of a gun. Wired once, to every cannon in the scene,
## rather than from the captain - the rig is a scene concern and the captain knows nothing
## about it, the same split as shoot_at and aim_point.
func _watch_cannons() -> void:
	var sfx := get_node_or_null("Sfx")
	for node in get_tree().get_nodes_in_group("cannons"):
		var gun := node as Node3D
		if gun == null or not gun.has_signal("manned_changed"):
			continue
		if gun.manned_changed.is_connected(_on_manned):
			continue
		gun.manned_changed.connect(_on_manned.bind(gun))
		# The shot, wired on this same pass rather than in _start_sfx. That runs four lines
		# earlier, which is before the ship has hung its guns - see the note at the call - so a
		# pass over the group there would find the hilltop cannon and nothing else, and the
		# broadside would fire in silence. Same reason the grunts are wired where they are.
		#
		# The gun still knows nothing about sound: it reports where the shot left, and this
		# decides what that sounds like.
		if sfx != null:
			gun.fired.connect(func(from: Vector3, _velocity: Vector3) -> void:
				# Louder than the flintlock, which was already the loudest thing here. You are
				# standing directly behind it when it goes off.
				sfx.play("cannon", from, 6.0))


func _on_manned(manned: bool, gun: Node3D) -> void:
	if _camera_rig != null and _camera_rig.has_method("set_gun"):
		_camera_rig.set_gun(gun if manned else null)


func _stock_fish(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args():
		return
	var shark := get_node_or_null("Shark")
	# Hand-placed schools win. A FishSchool is a @tool node that draws a still school in the
	# editor at wherever it has been dragged to, so the water can be stocked by eye - and if
	# any have been placed, nothing here should be second-guessing them by adding more.
	var placed: Array[Node] = []
	for node in get_children():
		if node is FishSchool:
			placed.append(node)
	if not placed.is_empty():
		var counted := 0
		for school in placed:
			school.terrain = _terrain
			if shark != null:
				school.predators = [shark] as Array[Node3D]
			var at: Vector3 = school.global_position
			if not school.setup(at, _terrain.sea_level(), hash(at)):
				continue
			var under: float = _terrain.sea_level() - _terrain.height_at(at.x, at.z)
			if under < WATER_FOR_FISH:
				push_warning("%s is in %.1f m of water at (%.0f, %.0f) - it wants %.1f"
						% [school.name, under, at.x, at.z, WATER_FOR_FISH])
			counted += school.fish_count()
		print("fish: %d in %d placed schools" % [counted, placed.size()])
		return
	var seaward := Vector3(around.x, 0.0, around.z)
	seaward = seaward.normalized() if seaward.length() > 0.01 else Vector3.FORWARD
	var along := Vector3(-seaward.z, 0.0, seaward.x)
	var sea: float = _terrain.sea_level()
	var total := 0
	for i in fish_schools:
		# Spread along the shore inside the shark's beat, and short of it, so they are in water
		# the player can see into from the beach rather than out in the deep.
		var side: float = (float(i) - (float(fish_schools) - 1.0) * 0.5) * 24.0
		# Fish need water under them, and the shoreline is not a circle, so the distance out
		# cannot be written down - a figure that clears the sand on one bearing runs a school
		# aground on the next. Walk out from the beach until there is enough water and stop
		# there, so each school sits as close in as its own stretch of coast allows and the
		# player can actually see it from the shore.
		var base := Vector3(around.x, sea, around.z) + along * side
		var home := Vector3.ZERO
		var water := 0.0
		var step := 16.0
		while step <= 96.0:
			var at: Vector3 = base + seaward * step
			var deep: float = sea - _terrain.height_at(at.x, at.z)
			if deep > water:
				water = deep
				home = at
			if deep >= WATER_FOR_FISH:
				break
			step += 6.0
		if water < WATER_FOR_FISH:
			print("fish: school %d skipped, deepest water on that bearing is %.1f m" % [i, water])
			continue
		var school: MultiMeshInstance3D = FishSchoolScene.instantiate()
		school.name = "FishSchool%d" % i
		school.count = fish_per_school
		add_child(school)
		school.terrain = _terrain
		if shark != null:
			school.predators = [shark] as Array[Node3D]
		if not school.setup(home, sea, hash(home)):
			print("fish: school %d failed to build" % i)
			school.queue_free()
			continue
		total += school.fish_count()
		print("fish: %s found %.1f m of water at (%.0f, %.0f)"
				% [school.name, water, home.x, home.z])
	print("fish: %d in the lagoon" % total)


func _moor_ship() -> void:
	# The hull is placed in the main scene so it shows in the editor. Reuse that node; only
	# build one when the scene has none.
	var ship := get_node_or_null("Ship") as Node3D
	if ship == null:
		ship = ShipScene.instantiate()
		ship.name = "Ship"
		add_child(ship)
	if not ship.moor_off(_coastal_study, _terrain):
		ship.queue_free()
		return
	ship.ocean = _ocean
	ship.rider = _player
	_player.set_ship(ship)


## Starts the background track. Silent in the capture and test modes, which run headless or
## save a picture and quit - neither wants two minutes of guitar.
func _start_music() -> void:
	if "--noassets" in OS.get_cmdline_user_args() or "--screenshot" in OS.get_cmdline_user_args():
		return
	var player: AudioStreamPlayer = Music.new()
	player.name = "Music"
	add_child(player)


## Brings up the island's own noise and tells it what is standing on the island.
##
## Called LAST, after the palms and the cargo are down. The occasional sounds are placed
## against real objects - a rustle comes from a palm that is actually there - so starting this
## alongside the music would hand it an empty scene and leave those sounds with nowhere to come
## from. The grunts were wired that way by mistake once and died in silence for it.
func _start_ambience(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or "--screenshot" in OS.get_cmdline_user_args():
		return
	var air: Node3D = Ambience.new()
	air.name = "Ambience"
	add_child(air)
	air.begin(_terrain, _player)

	# Asked of the containers rather than scanned out of the scene by name. Matching children
	# whose name begins with "Palm" worked only while every palm was a direct child of main,
	# and would have said nothing the moment that stopped being true.
	var palms: Array[Vector3] = []
	var cargo: Array[Vector3] = []
	var stand := get_node_or_null("Palms")
	if stand != null:
		palms = stand.positions()
	var crates := get_node_or_null("Cargo")
	if crates != null:
		cargo = crates.positions()
	air.anchor(palms, cargo)

	# The waterfall gets a pinned loop rather than a bed, because it is in one place and should
	# grow as you walk to it. Its emitter goes at the foot of its own curve - where the water
	# lands and the noise actually is, not at the lip forty metres up.
	var falls := get_node_or_null("Waterfall")
	var pinned := false
	var lapping := false
	if falls != null and falls.curve != null and falls.curve.point_count > 0:
		var foot: Vector3 = falls.to_global(
				falls.curve.get_point_position(falls.curve.point_count - 1))
		pinned = air.pin("waterfall", foot, 4.0, 70.0)
		# The pond goes at the same spot, but quieter and carrying further. The two then trade
		# off on their own as you walk: the roar is loud and local, so close to the falls it is
		# all you hear, and it drops away faster than the lapping does - which leaves still
		# water at the far side of the pond without needing to know where the far side is.
		lapping = air.pin("pond", foot, -9.0, 120.0)
	print("ambience: %d palms, %d cargo, waterfall %s, pond %s"
			% [palms.size(), cargo.size(), "pinned" if pinned else "silent",
			"pinned" if lapping else "silent"])


## Fills the island with the generated rocks.
##
## Its own RandomNumberGenerator, seeded from the project seed, so the layout is reproducible
## without the rocks consuming draws from the global one - adding a rock would otherwise move
## every grunt, and a change to scenery would look like a change to the fight.
func _scatter_rocks(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or rock_count <= 0:
		return
	var field: Node3D = Rocks.new()
	field.name = "Rocks"
	field.count = rock_count
	add_child(field)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rocks") + randi()
	print("scattered %d of %d rocks" % [field.scatter(_terrain, around, rng), rock_count])


## Plants palms along the shore - see props/palm/palms.gd for where they will grow.
##
## Its own RandomNumberGenerator, seeded from the project seed, for the same reason the rocks
## have one: sharing the global one means adding a palm moves every grunt.
func _plant_palms(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or palm_count <= 0:
		return
	var stand: Node3D = Palms.new()
	stand.name = "Palms"
	stand.count = palm_count
	add_child(stand)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("palms") + randi()
	print("palms: %d of %d" % [stand.plant(_terrain, around, rng), palm_count])


## Fills the green band with grass.
##
## Its own RandomNumberGenerator, seeded from the project seed, for the same reason the rocks
## have one: sharing the global one means adding a tuft moves every grunt.
func _scatter_grass(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or grass_patches <= 0:
		return
	var field: MultiMeshInstance3D = GrassScene.instantiate()
	field.name = "Grass"
	field.patches = grass_patches
	add_child(field)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("grass") + randi()
	# The rocks come along as extra patch centres. Grass grows against a boulder rather than
	# keeping a polite distance from it, and seeding the scatter with them is most of what makes
	# the ground look grown rather than sprinkled.
	var against_rocks: Array[Vector3] = []
	var field_of_rocks := get_node_or_null("Rocks")
	if field_of_rocks != null:
		for rock in field_of_rocks.get_children():
			against_rocks.append((rock as Node3D).global_position)
	print("grass: %d tufts in %d patches, %d of them against rocks"
			% [field.scatter(_terrain, around, rng, against_rocks), grass_patches,
			against_rocks.size()])


## Drops cargo on the beach and floats some of it offshore - see props/cargo/cargo_field.gd.
func _place_barrels(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args():
		return
	var field: Node3D = CargoField.new()
	field.name = "Cargo"
	field.barrels_ashore = barrels_ashore
	field.barrels_afloat = barrels_afloat
	field.crates_ashore = crates_ashore
	field.crates_afloat = crates_afloat
	add_child(field)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("cargo") + randi()
	print(field.summary(field.place(_terrain, around, rng, _ocean)))


## Scatters grunts around the spawn point - see actors/grunt/grunts.gd.
##
## Their sounds are connected here rather than inside the grunt, so a grunt never has to know
## a sound system exists. The field announces each one as it is made, which is what makes that
## possible without this having to find them afterwards.
func _spawn_enemies(near: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or enemy_count <= 0:
		return
	var band: Node3D = Grunts.new()
	band.name = "Grunts"
	band.count = enemy_count
	band.nearest = enemy_near
	band.furthest = enemy_far
	add_child(band)
	var noise := get_node_or_null("Sfx")
	if noise != null:
		band.spawned.connect(func(grunt: Node3D) -> void: _wire_enemy(noise, grunt))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("grunts") + randi()
	print("spawned %d of %d grunts between %.0f and %.0f m out"
			% [band.spawn(_terrain, _player, near, rng), enemy_count, enemy_near, enemy_far])


func _ready() -> void:
	# same layout every run unless --seed N is passed: reproducible problems, but easy to
	# check that the tunnel generator copes with more than one arrangement
	var chosen_seed := 20260920
	for i in OS.get_cmdline_user_args().size():
		if OS.get_cmdline_user_args()[i] == "--seed" and i + 1 < OS.get_cmdline_user_args().size():
			chosen_seed = int(OS.get_cmdline_user_args()[i + 1])
	seed(chosen_seed)
	# start the player on the ground near the middle, plus a little clearance
	var spawn: Vector3 = _terrain.find_spawn()
	# Tunnels placed under Terrain win; the generated one is only a fallback so the demo is
	# never empty. The terrain builds its own Tunnel children in generate().
	var authored: Array = []
	for child in _terrain.get_children():
		if child is Tunnel:
			authored.append(child)
	if "--noscene" in OS.get_cmdline_user_args():   # --noscene: generate one instead
		for tunnel in authored:
			_terrain.remove_child(tunnel)
			tunnel.queue_free()
		authored = []
	var holes: Array[Vector3] = []
	if not authored.is_empty():
		print("using %d tunnel(s) from the scene" % authored.size())
	elif "--tunnel" in OS.get_cmdline_user_args():
		# Only on request now: the island slice is about terrain and water, and a generated
		# tunnel punches a hole through the shoreline that reads as a bug.
		var ends: Array[Vector3] = _terrain.plan_tunnel_ends(spawn)
		if ends.size() == 2:
			var tunnel := _make_tunnel(ends[0], ends[1])
			holes = [Vector3(ends[0].x, ends[0].z, tunnel.width * 0.5),
					Vector3(ends[1].x, ends[1].z, tunnel.width * 0.5)]
	_terrain.generate()
	var tunnel_mode := false
	for argument in OS.get_cmdline_user_args():
		if argument in ["--tunnel", "--tunneltest", "--probepath", "--probe", "--holeview", "--holeshot", "--printcurve", "--second"]:
			tunnel_mode = true
	# A tunnel used to cancel the coastal layout outright, which is why a cave meant giving up
	# the shoreline spawn, the moored ship and the rock-and-palm grouping - and why it looked
	# like the study could not cope with holes in the terrain. It copes fine; it was never asked.
	#
	# The exclusion is only right for a GENERATED tunnel. plan_tunnel_ends() is planned around
	# the spawn as it stands BEFORE the study runs, so letting the study move the spawn
	# afterwards puts that tunnel somewhere it was not planned for - through the shoreline,
	# which is what the note above _make_tunnel describes.
	#
	# An AUTHORED tunnel has no such tie. It is where it was drawn, and nothing reads the spawn
	# to place it, so the beach can be laid out as normal around it.
	# Annotated: _terrain.tunnels is reached through an untyped property, so := cannot infer
	# a bool from it.
	var generated_tunnel: bool = authored.is_empty() and not _terrain.tunnels.is_empty()
	if not generated_tunnel and not tunnel_mode and "--noassets" not in OS.get_cmdline_user_args():
		_coastal_study = CoastalStudy.new()
		_coastal_study.name = "CoastalStudy"
		add_child(_coastal_study)
		if _coastal_study.setup(_terrain):
			spawn = _coastal_study.spawn
			var towards: Vector3 = _coastal_study.global_position - spawn
			_camera_rig.rotation.y = atan2(-towards.x, -towards.z)
			_moor_ship()
	# Start next to the tunnel mouth, looking at it: the tunnel used to be tens of metres away
	# with nothing pointing at it, so it was easy to miss entirely.
	#
	# Only for a tunnel this code generated, or in the tunnel test modes. A tunnel someone drew
	# in the scene is one they know the location of, and dragging the spawn to it would throw
	# away the shoreline start the study just chose - which is the whole point of letting the
	# study run alongside an authored tunnel.
	if _terrain.tunnels.size() > 0 and (generated_tunnel or tunnel_mode):
		var tunnel = _terrain.tunnels[0]
		var mouth: Vector3 = tunnel.to_global(tunnel.curve.sample_baked(0.0))
		var inward: Vector3 = tunnel.to_global(tunnel.curve.sample_baked(10.0)) - mouth
		inward.y = 0.0
		inward = inward.normalized()
		var stand: Vector3 = mouth - inward * 11.0
		spawn = Vector3(stand.x, _terrain.height_at(stand.x, stand.z), stand.z)
		_camera_rig.rotation.y = atan2(-inward.x, -inward.z)   # face the entrance
		if "--printcurve" in OS.get_cmdline_user_args():
			var printed := PackedStringArray()
			for i in tunnel.curve.point_count:
				printed.append(str(tunnel.curve.get_point_position(i)))
			print("curve points: ", ", ".join(printed))
	_player.global_position = spawn + Vector3.UP * 2.0
	_player.died.connect(_on_player_died)
	_add_health_bar()
	_start_music()
	_start_sfx()
	_scatter_rocks(spawn)
	_scatter_grass(spawn)
	_plant_palms(spawn)
	_place_barrels(spawn)
	_grow_reef()
	_loose_shark(spawn)
	_stock_fish(spawn)
	_spawn_enemies(spawn)
	# After the ship: its guns join the group when they enter the tree.
	_watch_cannons.call_deferred()
	_start_ambience(spawn)
	# Shut before anything else is visible, then opened once the island is built. Sound comes
	# up over the same span - music fades in over 2 s, ambience over 3 - so the two arrive
	# together rather than the picture beating the noise by a second.
	_start_spyglass()
	_start_crosshair()
	# The water is told where the sun is, rather than carrying its own guess. They disagreed:
	# the shader's default had its Z the wrong way round, so the sea was lit from roughly the
	# opposite bearing to the sand it meets.
	# The clock turns the sun from here on. The wind is the same breeze the sail and the
	# waves read. Both are created in code so the scene file does not have to grow a node
	# for something that has no mesh of its own.
	var day := (load("res://world/day.gd") as GDScript).new() as Node
	day.name = "Day"
	add_child(day)
	var wind := (load("res://world/wind.gd") as GDScript).new() as Node
	wind.name = "Wind"
	add_child(wind)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		# A DirectionalLight sends its photons along -Z, so +Z is the way back to the sun.
		var to_sun := sun.global_transform.basis.z
		_ocean.sun_direction = to_sun
		_tell_sky_about(to_sun)
	_ocean.setup(_terrain.sea_level(), _terrain, spawn)
	_start_underwater()
	_player.water_level = _terrain.sea_level()
	_camera_rig.water_level = _terrain.sea_level()
	_player.camera_rig = _camera_rig
	_camera_rig.set_target(_player)
	# The camera goes under with him. Wired here rather than in either of them: the captain
	# does not know anything follows his dives, and the rig does not know what a dive is.
	_player.dived.connect(_camera_rig.set_diving)
	var touch: CanvasLayer = $TouchControls
	_player.touch_controls = touch
	_camera_rig.touch_controls = touch
	touch.jumped.connect(_player.request_jump)
	touch.released.connect(_player.release_jump)
	touch.dive_changed.connect(_player.set_diving)
	# Every --something mode lives in tests/modes.gd: the renders, the walk-throughs, the
	# death test. They were nearly half of this file and none of them runs during a game.
	var modes: Node = Modes.new()
	modes.name = "Modes"
	add_child(modes)
	modes.begin(self, holes)


## Builds a Tunnel node whose curve runs from above ground at `a`, down at `entry_slope`,
## along at depth, and back up to `b`. Everything else (tube, collision, the hole in the
## terrain) follows from the curve and the radius. Kept a round bore, the shape it has always
## had, so the --tunnel walk-throughs in tests/modes.gd still measure the tunnel they were
## written against.
func _make_tunnel(a: Vector3, b: Vector3, tunnel_radius := 3.0, depth := 9.0,
		entry_slope_degrees := 25.0) -> Tunnel:
	var tunnel := Tunnel.new()
	tunnel.name = "Tunnel"
	tunnel.section = Tunnel.Section.ROUND
	tunnel.width = tunnel_radius * 2.0
	tunnel.height = tunnel_radius * 2.0
	var towards := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var run: float = depth / tan(deg_to_rad(entry_slope_degrees))
	var floor_y: float = minf(a.y, b.y) - depth
	var ramp_bottom_a := Vector3(a.x, floor_y, a.z) + towards * (run * 0.65)
	var ramp_bottom_b := Vector3(b.x, floor_y, b.z) - towards * (run * 0.65)
	# Start just above the chosen spot and dive: the tube is trimmed where it crosses the
	# surface, so that crossing becomes the mouth. No need to hunt for daylight.
	var points: Array[Vector3] = [
		Vector3(a.x, a.y + tunnel_radius * 0.8, a.z),
		ramp_bottom_a,
		ramp_bottom_b,
		Vector3(b.x, b.y + tunnel_radius * 0.8, b.z),
	]
	var curve := Curve3D.new()
	for i in points.size():
		# smooth handles: the ramps blend into the level run instead of kinking
		var handle := Vector3.ZERO
		if i > 0 and i < points.size() - 1:
			handle = (points[i + 1] - points[i - 1]).normalized() * 7.0
		curve.add_point(points[i], -handle, handle)
	tunnel.curve = curve
	_terrain.add_child(tunnel)
	return tunnel
