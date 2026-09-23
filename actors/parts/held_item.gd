@tool
class_name HeldItem
extends Resource
## Everything needed to put one thing in one hand: which bone it hangs from, which model to
## hang, and the corrections that turn "a mesh exists" into "a captain is holding it properly".
##
## Extracted at the third user, which is what CONVENTIONS asks for. The captain's cutlass, the
## captain's flintlock and the grunt's sword each carried the same six or seven exports under
## their own prefix - `sword_offset`, `pistol_offset` - and the paragraph explaining what an
## offset even means was written out more than once. A fourth weapon would have put eighteen
## fields on a single actor, and the slot system that is coming needs weapons to be things
## that can be handed around rather than fields spelled into whoever holds them.
##
## Deliberately only about HOLDING. A blade's reach, a gun's reload and how much either hurts
## belong to sword.gd and gun.gd - one script per kind of thing, which is already the right
## place for them. This answers "where is it and which way is it pointing", nothing else.
##
##
## THE THREE CORRECTIONS, and why none of them can be reasoned out
##
## `rotation` turns the model onto the hand bone's +X, which is the axis held.gd assumes
## because on these rigs the knuckles run index to ring along -X, so something leaving the
## fist on the index side points along +X.
##
## `grip` then slides the model along itself, because a rotation alone cannot fix where the
## origin is. The origin is wherever the artist left it, and turning the model only spins that
## same point about the fist.
##
## `offset` moves the whole thing relative to the bone.
##
## Expect to set all three against a render - `tests/captain_view.gd --spin` - and not by
## thinking about it. The cutlass has been wrong twice: once upside down, and once rolled a
## quarter turn in his fist. Which way a blade's flat faces is not recoverable from anything
## but looking at the mesh, and a rotation that reads correctly in an export panel can still
## be wrong on the model.
##
##
## WORKED EXAMPLE: the cutlass
##
## It is modelled tip-down - the point sits at the origin and the guard is three quarters of
## the way up, which the mesh's own cross-sections give away: 16.75 units wide at the guard
## against 2.3 along the blade. So a quarter turn about Z lays it along +X with the pommel
## backwards, and a `grip` of the blade's whole length then slides it forward until the hand
## holds the grip rather than the point. The X turn rolls it about its own length afterwards -
## Godot applies these in Y, X, Z order, so by the time X runs the blade is already on +X and
## it spins in place rather than swinging somewhere else.

## Where it hangs. A bone name on the holder's skeleton; the mount fails loudly rather than
## half-building if the rig has no such bone.
@export var bone := "mixamorig_RightHand"

## The model. Leave it empty and a plain box of `size` stands in, which is what everything here
## was before the models existed and is still useful for a thing that is not modelled yet - the
## grunt's sword is a box to this day.
@export_file("*.glb") var model := ""

## Metres, along the hand bone's axes.
##
## With a model this is the HITBOX ONLY and nothing here is drawn, so it is deliberately fatter
## than the blade looks: matched to the steel at 0.075 x 0.030 the captain hit once in three
## swings at a metre, because the strike sweeps sideways and a three-centimetre plate slips
## straight past. Widening it costs nothing visually.
##
## Without a model it is the size of the stand-in box, and then it IS what you see.
##
## Zero by default deliberately. A sword-sized default would make every blank item report
## itself as real, and the guard in mount() could never fire - so each item states its own,
## and an item that states nothing is correctly nothing.
@export var size := Vector3.ZERO

## Metres, along the hand bone's own axes. Y runs towards the fingertips, which is downwards
## while the arm hangs, and 0 puts the thing through the wrist joint rather than in the fist -
## on this rig the middle knuckle measures 5.2 cm along it and the joint past that 8.3 cm, so
## a hilt belongs between the two.
@export var offset := Vector3.ZERO

## Degrees, onto the hand bone's +X. See THE THREE CORRECTIONS above.
@export var rotation := Vector3.ZERO

## How far to slide the model along itself so its handle meets the fist. For a sword whose
## origin is its tip, that is the blade's length.
@export var grip := Vector3.ZERO

## Only used by the stand-in box. A placeholder that arrives shinier than the character holding
## it reads as a bug rather than as a stand-in, so held.gd flattens it to match the world.
@export var colour := Color(0.72, 0.74, 0.78)


## Whether this is worth mounting at all. An item with neither a model nor a box would hang an
## invisible nothing off a bone and report success, which is the sort of thing that looks like
## the bone lookup failed.
func is_real() -> bool:
	return model != "" or size.length() > 0.0
