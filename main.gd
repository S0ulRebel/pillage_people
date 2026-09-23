extends Node3D
## Drops the player onto the generated terrain, wires the camera to it, and shows the controls.
##
## Run with --screenshot to save a picture after a few frames and quit (used to check the
## project renders without opening the editor).

const CoastalStudy = preload("res://world/coastal_study.gd")
const Enemy = preload("res://actors/grunt/grunt.gd")
const Hud = preload("res://ui/hud.gd")
const Rocks = preload("res://props/rock/rocks.gd")
const Cargo = preload("res://props/cargo/cargo.tscn")
const CargoKind = preload("res://props/cargo/cargo.gd")
const Grass = preload("res://props/grass/grass.gd")
const Palm = preload("res://props/palm/palm.tscn")
const Music = preload("res://systems/music.gd")
const Sfx = preload("res://systems/sfx.gd")
const Ambience = preload("res://systems/ambience.gd")
const Modes = preload("res://tests/modes.gd")
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
	await get_tree().create_timer(restart_delay).timeout
	if is_inside_tree():
		get_tree().reload_current_scene()


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
	_player.hit.connect(func(target: Node) -> void:
		sfx.play("flesh", (target as Node3D).global_position + Vector3.UP))
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
	# The grunts are NOT wired here. _start_sfx runs before _spawn_enemies, so this used to
	# loop over an empty scene and silently connect nothing - a grunt could be cut down without
	# a sound and every part of it looked correct. Each one is wired as it is created instead,
	# which also covers any spawned later.


## One grunt's noises. Split out because the lambdas need to capture this grunt, not the last
## one in the loop.
func _wire_enemy(sfx: Node3D, grunt: Node3D) -> void:
	grunt.damaged.connect(func(_amount: int, _left: int) -> void:
		sfx.play("clang", grunt.global_position + Vector3.UP))
	grunt.died.connect(func() -> void:
		sfx.play("death", grunt.global_position + Vector3.UP))


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

	var palms: Array[Vector3] = []
	var cargo: Array[Vector3] = []
	for child in get_children():
		var named := String((child as Node).name)
		if named.begins_with("Palm"):
			palms.append((child as Node3D).global_position)
		elif named.begins_with("Cargo"):
			cargo.append((child as Node3D).global_position)
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


## Plants palms along the shore.
##
## Lower down than the grass and closer to the water: palms belong on the sand and the first
## rise behind it, not up on the hillside. Each gets its own lean and size, because a stand of
## identical upright palms reads as wallpaper rather than as trees.
func _plant_palms(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or palm_count <= 0:
		return
	var sea: float = _terrain.sea_level()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("palms") + randi()
	var planted := 0
	for i in palm_count:
		for attempt in 40:
			var angle := rng.randf() * TAU
			var away := sqrt(rng.randf()) * 80.0
			var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
			var ground: float = _terrain.height_at(at.x, at.z)
			var above := ground - sea
			if above < 0.8 or above > 6.0:
				continue
			# Not on a slope steep enough to leave the trunk hanging out of the hillside.
			var slope: float = maxf(
				absf(_terrain.height_at(at.x + 1.0, at.z) - _terrain.height_at(at.x - 1.0, at.z)),
				absf(_terrain.height_at(at.x, at.z + 1.0) - _terrain.height_at(at.x, at.z - 1.0))) * 0.5
			if slope > 0.5:
				continue
			var palm: StaticBody3D = Palm.instantiate()
			palm.name = "Palm%d" % i
			palm.size = rng.randf_range(0.75, 1.3)
			palm.lean = rng.randf_range(4.0, 16.0)
			palm.lean_towards = rng.randf() * 360.0
			add_child(palm)
			palm.global_position = Vector3(at.x, ground - 0.1, at.z)
			palm.rotation.y = rng.randf() * TAU
			planted += 1
			break
	print("palms: %d of %d" % [planted, palm_count])


## Fills the green band with grass.
##
## Its own RandomNumberGenerator, seeded from the project seed, for the same reason the rocks
## have one: sharing the global one means adding a tuft moves every grunt.
func _scatter_grass(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or grass_patches <= 0:
		return
	var field: MultiMeshInstance3D = Grass.new()
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


## Drops cargo on the beach and floats some of it offshore.
##
## The floating pieces are put over seabed that is actually deep enough - dropping one where
## the water is ankle deep gives a barrel resting on the bottom, which looks like buoyancy is
## broken rather than like shallow water.
func _place_barrels(around: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args():
		return
	var sea: float = _terrain.sea_level()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("cargo") + randi()
	var counts := {
		CargoKind.Kind.BARREL: [barrels_ashore, barrels_afloat],
		CargoKind.Kind.CRATE: [crates_ashore, crates_afloat],
	}
	var placed := {}
	var index := 0
	for kind in counts:
		var dry: int = counts[kind][0]
		var wet_count: int = counts[kind][1]
		placed[kind] = [0, 0]
		for i in dry + wet_count:
			var wet := i >= dry
			for attempt in 24:
				var angle := rng.randf() * TAU
				var away := rng.randf_range(6.0, 32.0)
				var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
				var ground: float = _terrain.height_at(at.x, at.z)
				var depth: float = sea - ground
				var ok: bool = depth > 1.2 if wet else ground > sea + 0.4
				if not ok:
					continue
				var piece: RigidBody3D = Cargo.instantiate()
				piece.kind = kind
				piece.name = "Cargo%d" % index
				piece.water_level = sea
				add_child(piece)
				# Floating pieces start at the surface so they settle rather than plunge and
				# bounce back up; the rest stand on the sand.
				piece.global_position = Vector3(at.x, sea - 0.3 if wet else ground, at.z)
				piece.rotation.y = rng.randf() * TAU
				placed[kind][1 if wet else 0] += 1
				index += 1
				break
	print("cargo: %d barrels (%d afloat), %d crates (%d afloat)"
			% [placed[CargoKind.Kind.BARREL][0] + placed[CargoKind.Kind.BARREL][1],
			placed[CargoKind.Kind.BARREL][1],
			placed[CargoKind.Kind.CRATE][0] + placed[CargoKind.Kind.CRATE][1],
			placed[CargoKind.Kind.CRATE][1]])


## Scatters grunts around the spawn point at varied distances and bearings.
##
## Built from a script rather than placed in the scene, so the count and spread are one export
## away and nothing has to be re-laid-out when more enemy types arrive.
##
## Each one is dropped onto the terrain surface, not at the spawn height - the spawn is lifted
## clear of the ground for the player to fall from, and a grunt started up there would drop
## through his own idle. Anywhere at or below the waterline is rejected and the bearing retried,
## because a grunt standing on the seabed is not a fight, it is a bug report.
func _spawn_enemies(near: Vector3) -> void:
	if "--noassets" in OS.get_cmdline_user_args() or enemy_count <= 0:
		return
	var placed := 0
	for i in enemy_count:
		var spot := Vector3.ZERO
		var found := false
		for attempt in 16:
			# Sweep the bearing further on each retry. Jitter alone kept searching the same
			# sector, so a grunt whose slice of the circle is all sea never found land and was
			# dropped - two of five went missing that way.
			var angle := TAU * (float(i) / float(enemy_count)) + randf_range(-0.4, 0.4) 					+ attempt * 0.4
			var away := randf_range(enemy_near, enemy_far)
			var at := near + Vector3(cos(angle), 0.0, sin(angle)) * away
			var ground: float = _terrain.height_at(at.x, at.z)
			if ground > _terrain.sea_level() + 0.5:
				spot = Vector3(at.x, ground + 0.1, at.z)
				found = true
				break
		if not found:
			continue
		var enemy: CharacterBody3D = Enemy.new()
		enemy.name = "Enemy%d" % i
		add_child(enemy)
		enemy.global_position = spot
		enemy.target = _player
		# Wired here, not in _start_sfx. That runs before this does, so its loop over the
		# scene's Enemy children found an empty scene and connected nothing - a grunt could
		# be cut down in silence while every part of the setup looked correct.
		var noise := get_node_or_null("Sfx")
		if noise != null:
			_wire_enemy(noise, enemy)
		placed += 1
	print("spawned %d of %d grunts between %.0f and %.0f m out"
			% [placed, enemy_count, enemy_near, enemy_far])


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
	# Tunnels placed in the scene win; the generated one is only a fallback so the demo is
	# never empty. Add a Tunnel node, draw its curve, and it is picked up here.
	var authored: Array = []
	if "--noscene" not in OS.get_cmdline_user_args():   # --noscene: generate one instead
		for child in get_children():
			if child is Tunnel:
				authored.append(child)
	var holes: Array[Vector3] = []
	if not authored.is_empty():
		for tunnel in authored:
			tunnel.build(_terrain)
		_terrain.tunnels = authored
		print("using %d tunnel(s) from the scene" % authored.size())
	elif "--tunnel" in OS.get_cmdline_user_args():
		# Only on request now: the island slice is about terrain and water, and a generated
		# tunnel punches a hole through the shoreline that reads as a bug.
		var ends: Array[Vector3] = _terrain.plan_tunnel_ends(spawn)
		if ends.size() == 2:
			var tunnel := _make_tunnel(ends[0], ends[1])
			_terrain.tunnels = [tunnel]
			holes = [Vector3(ends[0].x, ends[0].z, tunnel.radius),
					Vector3(ends[1].x, ends[1].z, tunnel.radius)]
	_terrain.generate()
	# Tunnel scenes and tunnel test arguments retain their original layout and spawn.
	var tunnel_mode := false
	for argument in OS.get_cmdline_user_args():
		if argument in ["--tunnel", "--tunneltest", "--probepath", "--probe", "--holeview", "--holeshot", "--printcurve", "--second"]:
			tunnel_mode = true
	if authored.is_empty() and _terrain.tunnels.is_empty() and not tunnel_mode and "--noassets" not in OS.get_cmdline_user_args():
		_coastal_study = CoastalStudy.new()
		_coastal_study.name = "CoastalStudy"
		add_child(_coastal_study)
		if _coastal_study.setup(_terrain):
			spawn = _coastal_study.spawn
			var towards: Vector3 = _coastal_study.global_position - spawn
			_camera_rig.rotation.y = atan2(-towards.x, -towards.z)
	# Start next to the tunnel mouth, looking at it: the tunnel used to be tens of metres away
	# with nothing pointing at it, so it was easy to miss entirely.
	if _terrain.tunnels.size() > 0:
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
	_spawn_enemies(spawn)
	_start_ambience(spawn)
	_ocean.setup(_terrain.sea_level(), _terrain, spawn)
	_player.water_level = _terrain.sea_level()
	_player.camera_rig = _camera_rig
	_camera_rig.set_target(_player)
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
## terrain) follows from the curve and the radius.
func _make_tunnel(a: Vector3, b: Vector3, tunnel_radius := 3.0, depth := 9.0,
		entry_slope_degrees := 25.0) -> Tunnel:
	var tunnel := Tunnel.new()
	tunnel.name = "Tunnel"
	tunnel.radius = tunnel_radius
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
	add_child(tunnel)
	tunnel.build(_terrain)
	return tunnel
