class_name Groups
## The node group names, by name.
##
## A group is a string-keyed contract: a node joins "cannons" in one file and something asks
## for "cannon" in another, and nothing fails - the query just comes back empty and whatever
## depended on it quietly does nothing. With the names here, a typo is a parse error instead.
##
## Every group the project uses is listed, and no file spells a group name out itself.

## The Terrain node. TerrainStamp, Tunnel and GrassPatch check their parent is in it, to warn
## when one is placed somewhere it reshapes or plants nothing.
const TERRAIN := &"terrain"
## Every placed cannon, so the captain can find the nearest one and main.gd can wire them up.
const CANNONS := &"cannons"
## The Wind node, which the ship and its sails read.
const WIND := &"wind"
