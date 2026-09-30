@tool
class_name OutfitPiece
extends Resource
## One piece of a character: a head, a coat, a pair of boots, a hat.
##
## A character is a rigged body plus a handful of these, and the point of splitting him up is
## the multiplication - six heads, six hats, five coats and four skin colours is hundreds of
## pirates for the price of twenty-one models. dresser.gd puts them on; the workshop scene next
## to this file is where they are tried on and fitted.
##
##
## TWO WAYS TO BE WORN
##
## SKINNED pieces bend with the body: a coat's sleeves follow the arms, trousers follow the
## knees. The model arrives from Tripo as a statue with no rig, so every vertex is given the
## skin weights of the body under it - see skin_copy.gd. A piece that arrives already rigged
## to the same bone names keeps its own weights instead.
##
## PINNED pieces are rigid and ride one bone: a hat on the head, a pendant on the chest. This
## is how the cutlass already hangs off the captain's hand (actors/parts/held.gd), and it costs
## nothing - no weights, no copy.
##
##
## WHERE IT SITS
##
## `position`, `rotation` and `scale` place the model on the body in the body's T-pose, in
## metres, with the origin on the floor between the feet, Y up and +Z the way he faces. That
## is the same whatever the rig's own units and axes are - the captain's and grunt's rigs are
## centimetres, lying face down at rest, and nobody should have to know that to move a hat up
## two centimetres. The workshop guesses a first fit from the body's bones; it is then tuned by
## eye and saved.
##
## A fit belongs to one body shape. It carries over between bodies of the same build, and the
## skin weights are copied again automatically for whichever body wears it, but a coat fitted
## to a thin body will not sit on a fat one - a different build wants its own coat.

enum Hold { SKINNED, PINNED }

## The slots, in the order the workshop lists them. A character wears at most one piece per
## slot, so a second hat replaces the first.
##
## A model is sorted into its slot by its file name: `coat_blue.glb` is a coat, `hat_tricorn.glb`
## a hat. See art/models/characters/README.md.
const SLOTS := ["head", "jaw", "hair", "face", "hat", "shirt", "coat", "trousers", "waist",
		"boots", "accessory"]

## How a new model in each slot is worn until someone says otherwise. Heads bend at the neck;
## hair, masks and hats ride the head bone; clothes bend.
const DEFAULTS := {
	"head": {"hold": Hold.SKINNED, "skin": true},
	"jaw": {"hold": Hold.PINNED, "bone": "mixamorig_Head", "skin": true},
	"hair": {"hold": Hold.PINNED, "bone": "mixamorig_Head"},
	"face": {"hold": Hold.PINNED, "bone": "mixamorig_Head"},
	"hat": {"hold": Hold.PINNED, "bone": "mixamorig_Head"},
	"shirt": {"hold": Hold.SKINNED},
	"coat": {"hold": Hold.SKINNED},
	"trousers": {"hold": Hold.SKINNED},
	"waist": {"hold": Hold.SKINNED},
	"boots": {"hold": Hold.SKINNED},
	"accessory": {"hold": Hold.PINNED, "bone": "mixamorig_Spine2"},
}

@export var slot := "hat"
## A .glb from Tripo, or a .tscn - the placeholders are scenes built from primitives.
@export_file("*.glb", "*.gltf", "*.tscn") var model := ""
@export var hold := Hold.PINNED
## Pinned pieces only: the bone it rides. Ignored by skinned pieces, which follow every bone.
@export var bone := "mixamorig_Head"
## Metres, in the T-pose, on the floor between his feet. See WHERE IT SITS above.
@export var position := Vector3.ZERO
## Degrees. Mostly for turning a model that arrived facing the wrong way.
@export var rotation := Vector3.ZERO
@export var scale := Vector3.ONE
## Whether the outfit's skin colour tints this piece. A head does; a hat does not.
@export var skin := false
## False until someone has placed it - nudged it in the workshop, or saved it. A piece that has
## never been placed is guessed afresh for whichever body wears it; one that has keeps its fit.
@export var fitted := false


## A new piece for a model, worn the way its slot usually is. Returns null for a file whose
## name does not start with a slot, so a stray model in the folder is skipped rather than
## turning up as a hat.
static func for_model(path: String) -> OutfitPiece:
	var slot_name := slot_of(path)
	if slot_name == "":
		return null
	var piece := OutfitPiece.new()
	piece.slot = slot_name
	piece.model = path
	var defaults: Dictionary = DEFAULTS[slot_name]
	piece.hold = defaults.get("hold", Hold.PINNED)
	piece.bone = defaults.get("bone", "mixamorig_Head")
	piece.skin = defaults.get("skin", false)
	return piece


## The slot a file name puts a model in: everything before the first underscore, when that is
## a slot. "" otherwise.
static func slot_of(path: String) -> String:
	var prefix := path.get_file().get_basename().get_slice("_", 0).to_lower()
	return prefix if prefix in SLOTS else ""


## What the workshop calls it: the file name without its slot, so `coat_blue.glb` is "blue".
func label() -> String:
	var name := model.get_file().get_basename()
	var cut := name.find("_")
	return name.substr(cut + 1) if cut != -1 else name


## Where the model sits on the body, in metres in the T-pose. See WHERE IT SITS above.
func fit() -> Transform3D:
	var basis := Basis.from_euler(rotation * (PI / 180.0)).scaled(scale)
	return Transform3D(basis, position)
