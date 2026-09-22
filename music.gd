extends AudioStreamPlayer
## Background music for the island.
##
## One track for now. It is a Suno export cut to a seamless loop by tools/make_loop.py in the
## generation repo - the song it came from has an intro and a fade that only make sense once,
## so what plays here is the 103 second middle that joins back onto itself.
##
## AudioStreamPlayer rather than AudioStreamPlayer3D: this is score, not something happening at
## a place in the world, so it should not pan as the camera turns.

@export_file("*.ogg") var track := "res://art/audio/beach.ogg"
## Quiet by default. Music that arrives at the same level as the sound effects is music the
## player turns off.
@export var volume := -14.0
## Seconds to come up from silence when the scene starts, so it fades in rather than lands.
@export var fade_in := 2.0

var _fading := 0.0


func _ready() -> void:
	bus = "Master"
	volume_db = volume
	if not ResourceLoader.exists(track):
		push_warning("music.gd: no track at %s" % track)
		return
	var loaded := load(track)
	if loaded is AudioStream:
		stream = loaded
		# glTF is not the only format that drops a loop flag: an Ogg imported without one plays
		# through and stops. Set it on the resource so it holds however the file was imported.
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		if fade_in > 0.0:
			_fading = fade_in
			volume_db = -60.0
		play()


func _process(delta: float) -> void:
	if _fading <= 0.0:
		return
	_fading = maxf(0.0, _fading - delta)
	var through := 1.0 - (_fading / maxf(fade_in, 0.001))
	# Interpolating in decibels sounds like a jump at the end; interpolating loudness and
	# converting is what reads as an even fade.
	volume_db = linear_to_db(maxf(db_to_linear(volume) * through, 0.0001))
	if _fading <= 0.0:
		volume_db = volume
