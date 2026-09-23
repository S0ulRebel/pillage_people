extends Node3D
## Sound effects: a small library and a pool of players.
##
## Everything is looked up by name and everything is optional. A sound that has not been
## generated yet simply does not play, so the hooks can be wired before the audio exists and
## nothing breaks while it is missing - which is the state this started in.
##
## Sounds in the world are positional, so a grunt dying twenty metres away is quieter and off
## to one side. The pool exists because one player can only carry one sound: two blades meeting
## while a third grunt is still falling needs three at once, and a single player would cut the
## first two off.

## Where the clips live. A file called clang.ogg is played as "clang".
const FOLDER := "res://art/audio/sfx"
const EXTENSIONS := [".ogg", ".wav", ".flac", ".mp3"]

## How many sounds can overlap. Past this the oldest is taken over, which is better than
## dropping the newest - the sound you just caused is the one you are listening for.
@export var voices := 12
@export var volume := -6.0
## Small random shifts, so the same clip twice in a row is not obviously the same clip. A
## footstep especially gives itself away without this.
@export var pitch_jitter := 0.12
@export var volume_jitter := 2.0
## How far a world sound carries.
@export var carry := 34.0

var _clips: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


func _ready() -> void:
	_load_clips()
	for i in voices:
		var player := AudioStreamPlayer3D.new()
		player.name = "Voice%d" % i
		player.max_distance = carry
		player.unit_size = 6.0
		# Logarithmic falloff: a fight across the beach should fade with distance rather than
		# cut out at the edge of a radius.
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player)
		_pool.append(player)


## Reads whatever is in the folder. Done by listing rather than by a hard-coded list, so
## dropping a new clip in is all it takes to have it available.
func _load_clips() -> void:
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		push_warning("sfx.gd: no folder at %s, so nothing will play." % FOLDER)
		return
	for file in dir.get_files():
		# Godot appends .import to what it ships; the real resource is the base name.
		var name_ := file.trim_suffix(".import")
		for extension in EXTENSIONS:
			if not name_.ends_with(extension):
				continue
			var path := "%s/%s" % [FOLDER, name_]
			if not ResourceLoader.exists(path):
				continue
			var key := name_.trim_suffix(extension)
			# A name can have numbered variants - clang_1, clang_2 - and they are collected
			# under one key so a repeated sound is not identically repeated.
			var base := key
			var underscore := key.rfind("_")
			if underscore > 0 and key.substr(underscore + 1).is_valid_int():
				base = key.substr(0, underscore)
			if not _clips.has(base):
				_clips[base] = []
			(_clips[base] as Array).append(load(path))
	if not _clips.is_empty():
		print("sfx: %d sounds (%s)" % [_clips.size(), ", ".join(_clips.keys())])


func has(sound: String) -> bool:
	return _clips.has(sound)


## Plays a sound somewhere in the world. Unknown names are ignored on purpose - see the note
## at the top.
func play(sound: String, at: Vector3, loudness := 0.0) -> void:
	if not _clips.has(sound) or _pool.is_empty():
		return
	var takes: Array = _clips[sound]
	var player := _pool[_next]
	_next = (_next + 1) % _pool.size()
	player.stream = takes[randi() % takes.size()]
	player.global_position = at
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume + loudness + randf_range(-volume_jitter, volume_jitter)
	player.play()
