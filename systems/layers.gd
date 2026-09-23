class_name Layers
## The physics layer bits, by name.
##
## MIRRORS Project Settings > Layer Names > 3D Physics. Nothing keeps the two in step
## automatically, so if a bit is renamed in the editor it has to be renamed here too.
##
## The point is that no file contains a bare layer number. A bit with no name gets quietly
## reused for something unrelated six months later, and the code that depended on the old
## meaning keeps running and keeps being wrong.

## Everything solid: terrain, rocks, cargo, the hull. Bodies stay on this so ordinary
## collision is unchanged by any tag below.
const WORLD := 1
## Anything a blow can land on. A tag for QUERYING - it does not change what collides with
## what, it lets a swing ask the physics server for things that can be hurt instead of asking
## for everything nearby and sorting it out in script.
const DAMAGEABLE := 2


## The mask value for a layer number. Layer N is bit N-1, and getting that wrong is the
## classic mistake: `collision_layer = 2` means layer 2 ONLY and silently drops layer 1.
static func bit(layer: int) -> int:
	return 1 << (layer - 1)
