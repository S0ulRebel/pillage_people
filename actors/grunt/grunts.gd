extends Node3D
## The grunts on the island.
##
## A container, so the scene holds one Grunts node rather than five loose Enemy children among
## everything else. What a grunt IS - the idle/chase/swing states, health, staggering, dying -
## lives in grunt.gd next to this. This only decides where they start.

const Grunt := preload("res://actors/grunt/grunt.gd")

@export var count := 5
## How far out they are scattered. Far enough that none is visible from the spawn, so they are
## something you walk into rather than something waiting on top of you.
@export var nearest := 18.0
@export var furthest := 45.0
## Anywhere at or below this above the waterline is rejected. A grunt standing on the seabed
## is not a fight, it is a bug report.
@export var dry_margin := 0.5

## Emitted as each one is created, so whatever wants to hear it can connect without this
## needing to know a sound system exists. main.gd wires the grunt's noises from here.
signal spawned(grunt: Node3D)


## Drops `count` grunts around `near` and returns how many found dry ground.
func spawn(terrain: Node, target: Node3D, near: Vector3, rng: RandomNumberGenerator) -> int:
	var placed := 0
	for i in count:
		var spot := Vector3.ZERO
		var found := false
		for attempt in 16:
			# Sweep the bearing further on each retry. Jitter alone kept searching the same
			# sector, so a grunt whose slice of the circle is all sea never found land and was
			# dropped - two of five went missing that way.
			var angle := TAU * (float(i) / float(count)) + rng.randf_range(-0.4, 0.4) \
					+ attempt * 0.4
			var away := rng.randf_range(nearest, furthest)
			var at := near + Vector3(cos(angle), 0.0, sin(angle)) * away
			var ground: float = terrain.height_at(at.x, at.z)
			if ground > terrain.sea_level() + dry_margin:
				spot = Vector3(at.x, ground + 0.1, at.z)
				found = true
				break
		if not found:
			continue
		var grunt: CharacterBody3D = Grunt.new()
		grunt.name = "Enemy%d" % i
		add_child(grunt)
		grunt.global_position = spot
		grunt.target = target
		# Announced as it is made rather than collected afterwards. The sound used to be wired
		# by looping over the scene's Enemy children from a function that ran BEFORE any grunt
		# existed - it connected nothing, silently, and a grunt could be cut down without a
		# sound while every part of the setup read as correct.
		spawned.emit(grunt)
		placed += 1
	return placed
