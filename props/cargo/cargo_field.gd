extends Node3D
## Cargo washed up on the beach and adrift offshore.
##
## A container, like rocks.gd and palms.gd. What a barrel IS - which mesh, how it rolls, how it
## bobs - lives in cargo.gd next to this; this only decides how many and where.

const Cargo := preload("res://props/cargo/cargo.tscn")
const CargoKind := preload("res://props/cargo/cargo.gd")

@export var barrels_ashore := 5
@export var barrels_afloat := 4
@export var crates_ashore := 6
@export var crates_afloat := 3
## How far from the spawn to scatter, in metres.
@export var reach := Vector2(6.0, 32.0)
## A floating piece needs water genuinely deeper than the piece is tall. Dropped where the
## water is ankle deep it rests on the bottom, which reads as buoyancy being broken rather
## than as shallow water.
@export var afloat_depth := 1.2
## And a dry piece needs to be clear of the waterline, not sitting in the wash.
@export var ashore_height := 0.4


## Places everything and returns {kind: [ashore, afloat]} so the caller can report it.
func place(terrain: Node, around: Vector3, rng: RandomNumberGenerator,
		ocean: Node3D = null) -> Dictionary:
	var sea_y: float = terrain.sea_level()
	var wanted := {
		CargoKind.Kind.BARREL: [barrels_ashore, barrels_afloat],
		CargoKind.Kind.CRATE: [crates_ashore, crates_afloat],
	}
	var placed := {}
	var index := 0
	for kind in wanted:
		var dry: int = wanted[kind][0]
		var wet_count: int = wanted[kind][1]
		placed[kind] = [0, 0]
		for i in dry + wet_count:
			var wet := i >= dry
			for attempt in 24:
				var angle := rng.randf() * TAU
				var away := rng.randf_range(reach.x, reach.y)
				var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
				var ground: float = terrain.height_at(at.x, at.z)
				var ok: bool = (sea_y - ground) > afloat_depth if wet \
						else ground > sea_y + ashore_height
				if not ok:
					continue
				var piece: RigidBody3D = Cargo.instantiate()
				piece.kind = kind
				piece.name = "Cargo%d" % index
				piece.water_level = sea_y
				piece.ocean = ocean
				add_child(piece)
				# Floating pieces start at the surface so they settle rather than plunge and
				# bounce back up; the rest stand on the sand.
				piece.global_position = Vector3(at.x, sea_y - 0.3 if wet else ground, at.z)
				piece.rotation.y = rng.randf() * TAU
				placed[kind][1 if wet else 0] += 1
				index += 1
				break
	return placed


## One line describing what was placed, for the caller to print.
func summary(placed: Dictionary) -> String:
	var barrel: Array = placed.get(CargoKind.Kind.BARREL, [0, 0])
	var crate: Array = placed.get(CargoKind.Kind.CRATE, [0, 0])
	return "cargo: %d barrels (%d afloat), %d crates (%d afloat)" % [
			barrel[0] + barrel[1], barrel[1], crate[0] + crate[1], crate[1]]


## Where the cargo ended up. The ambience puts its wood creaks on these.
func positions() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for child in get_children():
		found.append((child as Node3D).global_position)
	return found
