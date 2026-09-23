extends Node3D
## The island's own noise: what you hear when nothing is happening.
##
## Three kinds of thing here, and the difference between them is most of the design.
##
## BEDS are continuous. Surf, wind and the jungle run as loops that never stop, and what
## changes is how loud each one is - which follows the ground the captain is standing on.
## Walk up off the sand and the surf falls away while the insects come up, without anything
## having to trigger it. Three loops and a height do the work of a map full of trigger volumes.
##
## OCCASIONALS are single sounds fired from points in the world at uneven intervals. A gull is
## deliberately NOT a bed: looped, it is the same gull, crying on the same schedule, forever,
## and the ear catches that inside a minute. Cries at random bearings, heights and gaps read as
## a flock instead. They are also placed against real things - a rustle comes from a palm that
## is actually standing there, a creak from a barrel that exists - so the noise agrees with
## what you can see.
##
## PINNED loops are the third case, for something loud that lives in one place. A bed cannot
## get louder as you walk toward it, and for a waterfall that is the entire point.
##
## Everything is optional. A sound that has not been generated does not play, and the rest
## carries on without it.

const Sfx := preload("res://sfx.gd")

## Where the looping beds live. Kept apart from the one-shots because they are loaded
## differently - a bed has its loop flag forced on, and a one-shot must never have one.
@export_dir var beds_folder := "res://art/audio/beds"
## Where the occasional one-shots live.
@export_dir var calls_folder := "res://art/audio/ambience"

## Overall level. Ambience sits under the music, which sits under the effects: it is the floor
## of the mix, and the moment you notice it as a sound it is too loud.
@export var volume := -8.0
## Seconds to come up from silence, so the island fades in rather than switches on.
@export var fade_in := 3.0
## How quickly a bed follows the captain uphill, in seconds. Without this the surf pumps with
## every step on a slope, which is far more noticeable than the change it is tracking.
@export var drift := 2.5

## Each bed, and the heights it belongs to in metres above sea level.
##
## `full` is where it plays at its own weight and `gone` where it fades away; which of the two
## is the higher number is what decides whether a bed belongs to the shore or to the hill, so
## the same two lines of mixing serve both. `floor` keeps a trace of it everywhere - wind on
## the beach is quiet, not absent.
##
## The bands come from the terrain shader: it paints sand to about 3.5 m above the water and
## has turned to jungle by 8.8, so those are the real edges of the beach and the treeline
## rather than numbers that sound about right.
const BEDS := {
	"surf": {"full": 3.5, "gone": 34.0, "db": -3.0, "floor": 0.0},
	"wind": {"full": 30.0, "gone": 1.0, "db": -9.0, "floor": 0.30},
	"jungle": {"full": 16.0, "gone": 5.0, "db": -7.0, "floor": 0.0},
}

## Each occasional, how long to wait between them, and where it comes from.
##
## The gaps are ranges, never a fixed period. Anything on a regular beat stops being weather
## and starts being a metronome.
##
## The levels are doing more work than they look like they are. Every clip is trimmed and
## levelled to the SAME peak before it gets here, which is right for effects - it stops one
## sword landing at twice the loudness of the next - and wrong for everything else, because it
## also hands a palm frond the same level as a blade. So these numbers are not a mix, they are
## the real difference in loudness between the things making the sounds, put back by hand. A
## frond shifting is barely audible standing under the tree; a wave breaking carries.
const CALLS := {
	"gull": {"gap": Vector2(6.0, 21.0), "db": -8.0, "from": "sky"},
	"gull_far": {"gap": Vector2(17.0, 48.0), "db": -15.0, "from": "far"},
	"wave_break": {"gap": Vector2(8.0, 23.0), "db": -4.0, "from": "sea"},
	"palm_rustle": {"gap": Vector2(11.0, 33.0), "db": -24.0, "from": "palm"},
	"wood_creak": {"gap": Vector2(19.0, 58.0), "db": -17.0, "from": "cargo"},
}

var _terrain: Node = null
var _listener: Node3D = null
var _beds: Dictionary = {}
var _weights: Dictionary = {}
var _due: Dictionary = {}
var _calls: Node3D = null
var _palms: Array[Vector3] = []
var _cargo: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _fading := 0.0


## `terrain` answers height_at and sea_level; `listener` is whoever the mix follows, which is
## the captain.
func begin(terrain: Node, listener: Node3D) -> void:
	_terrain = terrain
	_listener = listener
	_rng.seed = hash("ambience") + randi()
	_fading = fade_in

	for sound in BEDS:
		var stream := _load_bed(sound as String)
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.name = "Bed_%s" % sound
		player.stream = stream
		player.bus = "Master"
		player.volume_db = -60.0
		add_child(player)
		player.play()
		_beds[sound] = player
		# Started at the weight of wherever the captain actually is, rather than at zero. Coming
		# up from silence is the fade's job; starting the surf at nothing on a beach would have
		# it swell in over a couple of seconds as though the tide were arriving.
		_weights[sound] = _weight_for(sound as String)

	# Its own pool, pointed at its own folder. Sharing the effects pool would mean a gull could
	# take the voice out from under a sword landing, which in a busy fight it eventually would.
	_calls = Sfx.new()
	_calls.name = "Calls"
	_calls.folder = calls_folder
	_calls.voices = 4
	_calls.carry = 90.0
	_calls.volume = volume
	add_child(_calls)
	for sound in CALLS:
		# Staggered, so the first minute is not every ambient sound in the game at once.
		_due[sound] = _rng.randf_range(1.0, (CALLS[sound]["gap"] as Vector2).y)

	if not _beds.is_empty():
		print("ambience: %d beds (%s)" % [_beds.size(), ", ".join(_beds.keys())])


## Pins a looping sound to one spot in the world. Used for the waterfall, which is loud, fixed
## and wants to grow as you approach.
func pin(sound: String, at: Vector3, loudness := 0.0, carry := 60.0) -> bool:
	var stream := _load_bed(sound)
	if stream == null:
		return false
	var player := AudioStreamPlayer3D.new()
	player.name = "Pinned_%s" % sound
	player.stream = stream
	player.max_distance = carry
	player.unit_size = 14.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.volume_db = volume + loudness
	add_child(player)
	player.global_position = at
	player.play()
	return true


## Points for the occasionals to come from, collected once at startup. main.gd hands over what
## it planted, because a rustle should come from a palm that is really there.
func anchor(palms: Array[Vector3], cargo: Array[Vector3]) -> void:
	_palms = palms
	_cargo = cargo


func _process(delta: float) -> void:
	if _listener == null or not is_instance_valid(_listener):
		return
	if _fading > 0.0:
		_fading = maxf(0.0, _fading - delta)
	_mix_beds(delta)
	_fire_calls(delta)


## Moves each bed toward the weight its height asks for, and sets the level from that.
func _mix_beds(delta: float) -> void:
	# Converted to a fraction of the way there per frame, so the speed does not depend on the
	# frame rate - at 30 fps and at 240 the surf takes the same couple of seconds to fade.
	var follow: float = 1.0 - exp(-delta / maxf(drift, 0.01))
	var through: float = 1.0 - (_fading / maxf(fade_in, 0.001)) if fade_in > 0.0 else 1.0
	for sound in _beds:
		var want := _weight_for(sound as String)
		var now: float = lerpf(_weights[sound], want, follow)
		_weights[sound] = now
		var settings: Dictionary = BEDS[sound]
		var loudness: float = db_to_linear(volume + (settings["db"] as float)) * now * through
		# Faded in loudness and converted, not interpolated in decibels: a decibel ramp is
		# nearly silent for most of its length and then arrives all at once.
		(_beds[sound] as AudioStreamPlayer).volume_db = linear_to_db(maxf(loudness, 0.0001))


## How much of a bed belongs at the captain's present height.
func _weight_for(sound: String) -> float:
	var settings: Dictionary = BEDS[sound]
	var above: float = _listener.global_position.y - _terrain.sea_level()
	# inverse_lerp handles both directions: for the surf `gone` is the higher number and the
	# weight falls as he climbs, for the jungle it is the lower one and the weight rises.
	var weight: float = clampf(
			inverse_lerp(settings["gone"] as float, settings["full"] as float, above), 0.0, 1.0)
	return maxf(weight, settings["floor"] as float)


## Counts each occasional down on its own clock, so the gulls keep their rhythm whatever the
## barrels are doing.
func _fire_calls(delta: float) -> void:
	if _calls == null:
		return
	for sound in CALLS:
		var left: float = (_due[sound] as float) - delta
		if left > 0.0:
			_due[sound] = left
			continue
		var settings: Dictionary = CALLS[sound]
		var gap: Vector2 = settings["gap"]
		_due[sound] = _rng.randf_range(gap.x, gap.y)
		if not _calls.has(sound):
			continue
		# Variant, because there may be nowhere for this one to come from. A wave breaking is
		# inaudible in the middle of the island and a creak needs a barrel, so the right answer
		# is sometimes silence rather than a sound from nowhere.
		var at: Variant = _point_for(settings["from"] as String)
		if at == null:
			continue
		_calls.play(sound, at as Vector3, settings["db"] as float)


## Where an occasional comes from. Returns null when there is nowhere it could sensibly be.
func _point_for(kind: String) -> Variant:
	var here := _listener.global_position
	match kind:
		"sky":
			var bearing := _rng.randf() * TAU
			var away := _rng.randf_range(12.0, 40.0)
			return here + Vector3(cos(bearing) * away, _rng.randf_range(9.0, 22.0),
					sin(bearing) * away)
		"far":
			var bearing := _rng.randf() * TAU
			var away := _rng.randf_range(55.0, 110.0)
			return here + Vector3(cos(bearing) * away, _rng.randf_range(18.0, 40.0),
					sin(bearing) * away)
		"sea":
			# Found by looking rather than assumed: bearings are sampled until one is over water,
			# so a break always comes from the direction the sea actually is. Standing inland
			# there is no such bearing within range and nothing plays, which is right.
			var sea: float = _terrain.sea_level()
			for attempt in 14:
				var bearing := _rng.randf() * TAU
				var away := _rng.randf_range(14.0, 46.0)
				var at := here + Vector3(cos(bearing) * away, 0.0, sin(bearing) * away)
				if _terrain.height_at(at.x, at.z) < sea:
					return Vector3(at.x, sea, at.z)
			return null
		"palm":
			return _nearby(_palms, 42.0, 2.6)
		"cargo":
			return _nearby(_cargo, 30.0, 0.4)
	return null


## One of a set of points, chosen from those within earshot. Firing at a barrel two hundred
## metres away spends a voice on something inaudible.
func _nearby(points: Array[Vector3], reach: float, lift: float) -> Variant:
	var here := _listener.global_position
	var within: Array[Vector3] = []
	for point in points:
		if here.distance_to(point) <= reach:
			within.append(point)
	if within.is_empty():
		return null
	return within[_rng.randi() % within.size()] + Vector3.UP * lift


## Loads a bed and forces its loop flag on. An Ogg imported without one plays through once and
## stops, which for a bed is silence a minute in rather than an obvious error.
func _load_bed(sound: String) -> AudioStream:
	for extension in [".ogg", ".wav"]:
		var path := "%s/%s%s" % [beds_folder, sound, extension]
		if not ResourceLoader.exists(path):
			continue
		var loaded := load(path)
		if loaded is AudioStreamOggVorbis:
			(loaded as AudioStreamOggVorbis).loop = true
			return loaded
		if loaded is AudioStreamWAV:
			var wav := loaded as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = wav.data.size() / (4 if wav.stereo else 2)
			return wav
	return null
