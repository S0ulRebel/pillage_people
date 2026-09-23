class_name Clips
extends Node
## The model's AnimationPlayer, and whichever clip should be running on it.
##
## Both characters grew their own version of this and the two drifted. The captain's could fall
## back through alternatives, so a half-finished clip set still animated instead of freezing;
## the grunt's could not. Both found the AnimationPlayer the same way, both kept the same two
## variables, and both had the same "do not replay the clip that is already playing" check
## written out twice.
##
## It decides nothing about WHICH clip - that is the character's business, and the captain's
## answer (dead, swinging, swimming, airborne, running, walking, idle) has nothing in common
## with a grunt's. This only owns the player and the bookkeeping.

## Seconds to cross-fade. Too short snaps, too long makes turns feel sluggish.
@export var blend := 0.15

var _anim: AnimationPlayer
var _playing := ""


## Takes the player straight, for callers already walking the model's nodes.
func use(player: AnimationPlayer) -> void:
	_anim = player


## Finds the AnimationPlayer inside an imported model. Returns false when there is not one,
## which is normal for a stand-in body built from primitives.
func attach(model: Node) -> bool:
	for node in model.find_children("*", "AnimationPlayer", true, false):
		_anim = node as AnimationPlayer
		return true
	return false


## The clip itself, for the rare caller that needs to change it rather than play it - setting
## loop_mode on the ones that were authored as cycles, for instance.
func animation(clip: String) -> Animation:
	return _anim.get_animation(clip) if has(clip) else null


func ready() -> bool:
	return _anim != null


func has(clip: String) -> bool:
	return _anim != null and clip != "" and _anim.has_animation(clip)


func current() -> String:
	return _playing


## Plays the first of `wanted` and `fallbacks` that the model actually has, and returns the one
## it chose - or "" if none of them exist.
##
## Falling back matters while a character is half-built: a model with no run clip should walk
## rather than freeze mid-stride, and one with no fall clip should hold the jump.
func play(wanted: String, fallbacks: Array[String] = []) -> String:
	if _anim == null:
		return ""
	for candidate in [wanted] + fallbacks:
		if not has(candidate):
			continue
		if candidate != _playing:
			_anim.play(candidate, blend)
			_playing = candidate
		return candidate
	return ""


## Jumps to a point inside whatever is playing. Used for clips that are entered part-way in,
## like a swing whose first second is a wind-up.
func seek(to: float) -> void:
	if _anim != null:
		_anim.seek(to, true)


## Forgets what is playing, so the next play() treats its clip as a change and restarts it.
## A captain who has just been revived is otherwise left holding the last frame of his death.
func forget() -> void:
	_playing = ""
