extends RefCounted
## The island as a Terrain of its own, for the tests that build one: a Seabed with main.tscn's
## Island stamp laid over the whole square - but not faded into the bed, so the ground in the
## square is exactly terrain/island.stamp, the island these tests were written against.
##
## No far ring past the square unless asked for: most of them never leave it, and it is another
## second to build.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")
## main.tscn's Island: 180 x 32768 / 65535 m of height, to a float's width, standing 18 m lower
## than that - the stamp's file puts its sea a tenth of the way up its 180 m. See
## tests/island_stamp_check.gd, which holds main.tscn to these.
const HEIGHT := 90.001373291015625
const Y := HEIGHT - 18.0
const SIZE := 620.0


## A Terrain, not yet in the tree, with a Seabed and the Island under it and nothing else. Add
## stamps, tunnels or grass after these, so the island is under them.
static func make(far_ring := false) -> StaticBody3D:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.world_size = SIZE
	if not far_ring:
		terrain.far_extent = 0.0
	var seabed := Seabed.new()
	seabed.name = "Seabed"
	terrain.add_child(seabed)
	terrain.add_child(island())
	return terrain


## The Island stamp on its own, unfaded: `fade` metres of border_fade to give way to the bed.
static func island(fade := 0.0) -> TerrainStamp:
	var stamp := STAMP.instantiate() as TerrainStamp
	stamp.name = "Island"
	stamp.mode = TerrainStamp.Mode.REPLACE
	stamp.stamp_path = "res://terrain/island.stamp"
	stamp.height = HEIGHT
	stamp.length = SIZE
	stamp.width = SIZE
	stamp.border_fade = fade
	stamp.position = Vector3(0.0, Y, 0.0)
	# Ticked, so the editor's live checks build it too; the game builds every stamp anyway.
	stamp.preview = true
	return stamp
