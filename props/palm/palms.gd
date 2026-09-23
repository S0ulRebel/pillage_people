extends Node3D
## A stand of palms along the shore.
##
## A container, like rocks.gd beside props/rock - the palms are its children rather than the
## scene's, so the main scene does not end up with a flat list of every tree, barrel and grunt
## on the island next to the handful of nodes that actually matter.
##
## What a palm IS - trunk collision, two-sided fronds, the lean - lives in palm.gd next to
## this. This only decides where they stand.

const Palm := preload("res://props/palm/palm.tscn")

@export var count := 14
## How far out to search, in metres.
@export var spread := 80.0
## Where a palm will grow, in metres above sea level. Lower and nearer the water than the
## grass: palms belong on the sand and the first rise behind it, not up on the hillside.
@export var lowest := 0.8
@export var highest := 6.0
## Nothing on a slope steep enough to leave the trunk hanging out of the hillside. Measured as
## the height change across a metre.
@export var max_slope := 0.5
## Each palm gets its own size and lean. A stand of identical upright palms reads as wallpaper
## rather than as trees.
@export var size_range := Vector2(0.75, 1.3)
@export var lean_range := Vector2(4.0, 16.0)


## Plants up to `count` palms and returns how many found somewhere to stand.
func plant(terrain: Node, around: Vector3, rng: RandomNumberGenerator) -> int:
	var sea: float = terrain.sea_level()
	var planted := 0
	for i in count:
		# Several bearings per palm: most of a circle drawn around the spawn is either sea or
		# hillside, so a single try would quietly plant far fewer than asked for.
		for attempt in 40:
			var angle := rng.randf() * TAU
			var away := sqrt(rng.randf()) * spread
			var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
			var ground: float = terrain.height_at(at.x, at.z)
			var above := ground - sea
			if above < lowest or above > highest:
				continue
			var slope: float = maxf(
					absf(terrain.height_at(at.x + 1.0, at.z) - terrain.height_at(at.x - 1.0, at.z)),
					absf(terrain.height_at(at.x, at.z + 1.0) - terrain.height_at(at.x, at.z - 1.0))
					) * 0.5
			if slope > max_slope:
				continue
			var palm: StaticBody3D = Palm.instantiate()
			palm.name = "Palm%d" % i
			palm.size = rng.randf_range(size_range.x, size_range.y)
			palm.lean = rng.randf_range(lean_range.x, lean_range.y)
			palm.lean_towards = rng.randf() * 360.0
			add_child(palm)
			# Sunk a little, so a trunk on a slope does not stand on one edge.
			palm.global_position = Vector3(at.x, ground - 0.1, at.z)
			palm.rotation.y = rng.randf() * TAU
			planted += 1
			break
	return planted


## Where the palms ended up. The ambience plants its frond rustles on these, so it needs the
## positions rather than the nodes.
func positions() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for child in get_children():
		found.append((child as Node3D).global_position)
	return found
