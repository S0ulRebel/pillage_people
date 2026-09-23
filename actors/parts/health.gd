extends Node
## How much damage a thing can take before it is finished.
##
## Owns the number and nothing else. It does not play a death clip, clear a collision layer,
## reload the scene or make a sound - it says what happened and whoever owns it decides what
## that means. A grunt falls over, the captain restarts the island, and a barrel would do
## neither; none of that belongs in here.
##
## Kept apart from knockback.gd deliberately, though the two always fire together. A crate can
## be broken without being shoved, and a wave can shove without hurting.

## Emitted whenever the number changes, including on refill.
signal changed(current: int, maximum: int)
## Emitted once, the moment it reaches zero. The owner decides what dying looks like.
signal emptied

@export var maximum := 5

var _current := 0
var _empty := false


func _ready() -> void:
	_current = maximum


func current() -> int:
	return _current


func fraction() -> float:
	return float(_current) / float(maxi(maximum, 1))


func is_empty() -> bool:
	return _empty


## Takes `amount` off. Returns true if this is the blow that emptied it, so a caller that has
## more to do on the killing blow does not have to compare before and after itself.
func take(amount: int) -> bool:
	if _empty:
		return false
	_current = maxi(0, _current - amount)
	changed.emit(_current, maximum)
	if _current > 0:
		return false
	_empty = true
	emptied.emit()
	return true


func heal(amount: int) -> void:
	if _empty:
		return
	_current = mini(maximum, _current + amount)
	changed.emit(_current, maximum)


## Back to full, and alive again. Used by revive() rather than by anything in a fight.
func refill() -> void:
	_current = maximum
	_empty = false
	changed.emit(_current, maximum)
