extends Node3D
## Grows a reef of corals on the seabed.
##
## The first thing in this world that is scattered UNDER water. Every other scatterer excludes
## the sea explicitly - rocks want 0.6 m of clearance above it, palms a band 0.8 to 6 m up,
## grass 3.6 to 9 - so none of them could be pointed at a seabed by changing a number. This one
## inverts the test: it wants water, and enough of it to swim over what it plants.
##
## Where it plants is not written down here. main.gd finds the dive crater in the scene and
## passes its middle, the same way it hands every other scatterer the player's spawn - so
## moving the crater in the editor moves the reef with it, and a second crater gets its own.
##
## What a coral is made of - the model, the flat shading, the render layer it stays OFF - lives
## in coral.gd beside this, which is also what you drag into a scene to place one by hand.

const CoralProp = preload("res://props/coral/coral.gd")

@export var count := 26
## How far from the middle of the reef they spread. The dive crater is 25 m of full-depth floor
## before the ground ramps back up over the next ten, so this stays inside the floor.
@export var spread := 22.0
## Metres of water a coral needs over the seabed before it will plant there. Not the same as
## the clearance below: this is what keeps the reef off the shallows at the crater's edge,
## where a coral would be scenery nobody swims through.
@export var min_depth := 4.0
## Metres of clear water that must remain over the top of the coral once it is planted.
##
## THIS IS WHAT KEEPS LAYER 20 OFF - see coral.gd. A coral that breached the surface would need
## to punch a hole in the ocean's foam band like a rock does; one that stays under does not,
## because the band camera cannot see it. Rather than carry that case, the reef refuses to
## plant anything that would break through.
@export var surface_clearance := 1.5
## Nothing plants within this of another coral. Rocks do not bother - a boulder half inside
## another boulder still reads as rock - but two coral heads in the same place read as one
## broken coral.
@export var spacing := 2.2
## Each one a little off its authored size. A handful of models across two dozen corals is
## repetition the eye finds at once without this.
@export var size_jitter := Vector2(0.7, 1.45)
## Sunk a little, so a coral on the crater's slope does not stand on one edge of its base.
@export var sink := 0.06

var _planted: Array[Vector3] = []


## Plants the reef and returns how many went down. `around` is the middle of the water it
## should fill; `terrain` answers for the seabed and the waterline.
func scatter(terrain: Node, around: Vector3, rng: RandomNumberGenerator) -> int:
	var loaded := {}
	for kind in CoralProp.MODELS:
		var path: String = CoralProp.MODELS[kind]
		if ResourceLoader.exists(path):
			loaded[kind] = load(path) as PackedScene
	if loaded.is_empty():
		push_warning("corals.gd: no coral models found under art/models/props.")
		return 0
	var kinds: Array = loaded.keys()
	var sea: float = terrain.sea_level()
	var grown := 0
	for i in count:
		# Eight tries each, like the rocks. A reef that comes up short is a thinner reef; a reef
		# that searches forever is a hang.
		for attempt in 8:
			var angle := rng.randf() * TAU
			# sqrt, so they spread evenly over the area rather than crowding the middle.
			var away: float = sqrt(rng.randf()) * spread
			var at := Vector3(around.x + cos(angle) * away, 0.0, around.z + sin(angle) * away)
			var ground: float = terrain.height_at(at.x, at.z)
			var depth := sea - ground
			if depth < min_depth:
				continue
			var too_near := false
			for other in _planted:
				if Vector2(other.x - at.x, other.z - at.z).length() < spacing:
					too_near = true
					break
			if too_near:
				continue
			var kind = kinds[rng.randi() % kinds.size()]
			var coral := (loaded[kind] as PackedScene).instantiate() as Node3D
			var size := rng.randf_range(size_jitter.x, size_jitter.y)
			# Measured from the model rather than assumed, and BEFORE it is planted: whether
			# this one fits under the water is the question, and a coral that does not fit must
			# never be added and then moved - a half-second of a coral standing out of the sea
			# is still a coral standing out of the sea.
			var tall := _height_of(coral) * size
			if ground + tall + surface_clearance > sea:
				coral.free()
				continue
			coral.name = "Coral%d" % grown
			add_child(coral)
			coral.global_position = Vector3(at.x, ground - sink, at.z)
			coral.rotation.y = rng.randf() * TAU
			coral.scale *= size
			CoralProp.dress(coral)
			_planted.append(coral.global_position)
			grown += 1
			break
	return grown


## Where each coral went. The scatterer's own list, because the nodes are the only other record
## and a test that walks children is measuring the tree rather than the decision.
func planted() -> Array[Vector3]:
	return _planted


## The height of a model that is not in the tree yet, from its meshes. It has no global
## transform to measure through at this point, so the AABBs are merged in the model's own space
## - which is what the scale will be applied to anyway.
static func _height_of(model: Node) -> float:
	var box := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var here: AABB = mesh_node.transform * mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box.size.y
