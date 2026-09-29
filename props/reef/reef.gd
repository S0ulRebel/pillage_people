extends Node3D
## Grows a reef on the seabed: corals and the weed between them.
##
## The first thing in this world that is scattered UNDER water. Every other scatterer excludes
## the sea explicitly - rocks want 0.6 m of clearance above it, palms a band 0.8 to 6 m up,
## grass 3.6 to 9 - so none of them could be pointed at a seabed by changing a number. This one
## inverts the test: it wants water, and enough of it to keep what it plants under the swell.
##
## It grows in two kinds of place, and main.gd makes one of these for each:
##
##   scatter()  a disc round a point. main.gd finds the dive crater in the scene and passes its
##              middle, so moving the crater in the editor moves the reef with it.
##   fringe()   beds in the shallows along the coast, found by their depth - so a different
##              height map, or a stamp that pushes the beach out, is followed without anyone
##              writing down where the coast is. Near a point, or all the way round.
##
## Both hand each spot to the same _plant(), which is where every rule about what may grow
## there lives. The two differ only in how they choose the spots.
##
## What a coral or a weed is made of - the model, the flat shading, the render layer it stays
## OFF - lives in its own script, which is also what you drag into a scene to place one by
## hand. This file only decides WHERE, and asks the family to dress what it planted.
##
## It was corals.gd until the weed arrived. A file called corals that plants seaweed is a file
## nobody can grep for.

## The families it draws from. Each is a prop script with a MODELS dictionary, a SHALLOWEST
## depth and a static dress(); adding a third is one line here and nothing else.
const FAMILIES := [
	preload("res://props/coral/coral.gd"),
	preload("res://props/seaweed/seaweed.gd"),
]

@export var count := 26
## How far from the middle of the reef they spread. The dive crater is 25 m of full-depth floor
## before the ground ramps back up over the next ten, so this stays inside the floor.
@export var spread := 22.0
## Metres of water a growth needs over the seabed before it will plant there. In the crater
## this is what keeps the reef off the shallows at its edge, where a coral would be scenery
## nobody swims through; along the coast it keeps the beds out of the breaking foam.
@export var min_depth := 4.0
## Metres of water past which nothing plants. The crater has no need of one. The coast is
## nothing but one: the shelf round this island falls to 2.5 m over its first 30 m out and then
## barely deepens for another thirty, so without a ceiling the "shallows" are mostly a lagoon
## floor too far out to see from the beach.
@export var max_depth := 1000.0
## Metres of clear water that must stay over the top of a growth when the swell is at its
## LOWEST there - see Ocean.deepest_trough, which is added to this at every spot.
##
## THIS IS WHAT KEEPS LAYER 20 OFF - see coral.gd. A coral that breached the surface would need
## to punch a hole in the ocean's foam band like a rock does; one that stays under does not,
## because the band camera cannot see it. Rather than carry that case, the reef refuses to
## plant anything that would break through.
##
## It was 1.5 m of still water, which is the full swell (1.32 m) plus a little, worked out by
## hand for the crater. That is right fifteen metres down and wrong on the coast, where the
## shoal flattens the waves and 1.5 m would leave nothing growing inside two metres of water.
@export var surface_clearance := 0.15
## Nothing plants within this of another growth. Rocks do not bother - a boulder half inside
## another boulder still reads as rock - but two coral heads in the same place read as one
## broken coral.
@export var spacing := 2.2
## Each one a little off its authored size. A handful of models across two dozen corals is
## repetition the eye finds at once without this.
##
## The upper end is a wish, not a promise: a growth is never planted taller than the water over
## it allows, so in the shallows the range is cut down to what fits, and a model that does not
## fit even at the lower end is not picked there at all. That is what makes the weed near the
## beach small and the corals further out bigger, without a rule that says so.
@export var size_jitter := Vector2(0.7, 1.45)
## Sunk a little, so a coral on the crater's slope does not stand on one edge of its base.
@export var sink := 0.06

@export_group("Beds")
## fringe() only. How many growths a bed tries for, fewest to most.
@export var bed_size := Vector2i(4, 9)
## How far from its middle a bed reaches, in metres. Crowded toward the middle, like a grass
## patch - an even sprinkle along a coast reads as a texture rather than as things growing.
@export var bed_radius := 5.0
## The least distance between two beds' middles. At least twice bed_radius plus spacing, so
## two beds can never crowd each other - which is what lets a bed check its spacing against
## its own growths only, rather than against the whole coast.
@export var bed_spacing := 14.0

@export_group("Drawing")
## Metres from the camera past which a growth is not drawn. 0 draws them at any distance.
##
## For the coast, where there are a few hundred of them round the whole island and most of
## them are behind the hill or the horizon. Seen low across the water from further than about
## this, the sea has absorbed all but the blue of them anyway (ocean.gdshader, optical_depth).
@export var visible_within := 0.0

## Boxes in world space that nothing grows under - the hull moored over the shallows. Its keel
## sits two metres into water the beds grow in, so a coral there stands inside it. Only the
## footprint is read: whatever floats over a bed is lower than the swell lets a growth reach.
var keep_clear: Array[AABB] = []

var _planted: Array[Vector3] = []
## The middle of every bed fringe() has grown, across calls, so a second call keeps its beds
## clear of the first's.
var _middles: Array[Vector3] = []
## Every model the families offer, measured once: {scene, family, tall}.
var _pool: Array[Dictionary] = []
var _ocean: Ocean
var _warned := false


## Plants the reef and returns how many went down. `around` is the middle of the water it
## should fill; `terrain` answers for the seabed and the waterline, `ocean` for how low the
## swell pulls the water.
func scatter(terrain: Node, around: Vector3, rng: RandomNumberGenerator,
		ocean: Ocean = null) -> int:
	if not _prepare(ocean):
		return 0
	var grown := 0
	for i in count:
		# Eight tries each, like the rocks. A reef that comes up short is a thinner reef; a reef
		# that searches forever is a hang.
		for attempt in 8:
			var angle := rng.randf() * TAU
			# sqrt, so they spread evenly over the area rather than crowding the middle.
			var away: float = sqrt(rng.randf()) * spread
			var at := Vector3(around.x + cos(angle) * away, 0.0, around.z + sin(angle) * away)
			if _plant(terrain, at, rng, _planted):
				grown += 1
				break
	return grown


## Grows up to `beds` beds in the shallows within `reach` metres of `around` - or anywhere
## round the island when `reach` is 0 - and returns how many growths went down in them.
##
## A bed's middle is a spot whose water is between min_depth and max_depth. Picked by area
## rather than walked along a traced coastline: there is no coastline to trace - the island has
## a lake, and a crater, and whatever a stamp does next - and the band is about an eighth of
## the map, so sixty tries a bed almost never come back empty. By area, so they spread along the
## coast about as evenly as the band is wide.
func fringe(terrain: Node, beds: int, rng: RandomNumberGenerator, ocean: Ocean = null,
		around := Vector3.ZERO, reach := 0.0) -> int:
	if not _prepare(ocean):
		return 0
	var sea: float = terrain.sea_level()
	var half: float = terrain.world_size * 0.5
	var middles: Array[Vector3] = []
	for i in beds:
		for attempt in 60:
			var at: Vector3
			if reach > 0.0:
				var angle := rng.randf() * TAU
				var away: float = sqrt(rng.randf()) * reach
				at = Vector3(around.x + cos(angle) * away, 0.0, around.z + sin(angle) * away)
			else:
				at = Vector3(rng.randf_range(-half, half), 0.0, rng.randf_range(-half, half))
			var depth: float = sea - terrain.height_at(at.x, at.z)
			if depth < min_depth or depth > max_depth or _kept_clear(at, bed_radius):
				continue
			var crowded := false
			for other in _middles:
				if Vector2(other.x - at.x, other.z - at.z).length() < bed_spacing:
					crowded = true
					break
			if crowded:
				continue
			middles.append(at)
			_middles.append(at)
			break
	var grown := 0
	for middle in middles:
		var bed: Array[Vector3] = []
		for i in rng.randi_range(bed_size.x, bed_size.y):
			for attempt in 8:
				var angle := rng.randf() * TAU
				# Two randoms multiplied: dense in the middle, ragged at the edge. grass.gd's clump.
				var away: float = rng.randf() * rng.randf() * bed_radius
				var at := Vector3(middle.x + cos(angle) * away, 0.0, middle.z + sin(angle) * away)
				if _plant(terrain, at, rng, bed):
					grown += 1
					break
	return grown


## Where each growth went. The scatterer's own list, because the nodes are the only other
## record and a test that walks children is measuring the tree rather than the decision.
func planted() -> Array[Vector3]:
	return _planted


## Loads and measures every model once, and takes the ocean. False if there is nothing to plant.
func _prepare(ocean: Ocean) -> bool:
	_ocean = ocean
	if _ocean == null and not _warned:
		# Not a silent fallback: without the sea's troughs only the still water is kept clear,
		# and on the coast that is a coral standing in the air every time the swell goes by.
		push_warning("reef.gd: no Ocean handed in - only still water is kept clear of the"
				+ " growths, and the swell will uncover the tall ones.")
		_warned = true
	if not _pool.is_empty():
		return true
	for family in FAMILIES:
		for kind in family.MODELS:
			var path: String = family.MODELS[kind]
			if not ResourceLoader.exists(path):
				continue
			var packed := load(path) as PackedScene
			# Measured from the model rather than assumed, and BEFORE any is planted: whether
			# one fits under the water is the question, and a growth that does not fit must
			# never be added and then moved - a half-second of a coral standing out of the sea
			# is still a coral standing out of the sea.
			var probe := packed.instantiate()
			_pool.append({"scene": packed, "family": family, "tall": _height_of(probe)})
			probe.free()
	if _pool.is_empty():
		push_warning("reef.gd: no coral or weed models found under art/models/props.")
		return false
	return true


## Plants one growth at `at` if the water there allows one, and says whether it did. `near` is
## what it must keep `spacing` from, and it is added to that list too.
func _plant(terrain: Node, at: Vector3, rng: RandomNumberGenerator,
		near: Array[Vector3]) -> bool:
	var sea: float = terrain.sea_level()
	var ground: float = terrain.height_at(at.x, at.z)
	var depth := sea - ground
	if depth < min_depth or depth > max_depth or _kept_clear(at, 1.0):
		return false
	for other in near:
		if Vector2(other.x - at.x, other.z - at.z).length() < spacing:
			return false
	# The tallest thing that stays under here with the swell at its lowest.
	var trough := _ocean.deepest_trough(depth) if _ocean != null else 0.0
	var room := depth - trough - surface_clearance
	# Only what may grow at this depth and fits even at its smallest. Picked from those,
	# rather than picked from everything and then refused, so the shallow edge of a bed fills
	# with the short weeds instead of coming up empty after eight tries at a tall coral.
	var fits: Array[Dictionary] = []
	for entry in _pool:
		if depth >= entry["family"].SHALLOWEST and entry["tall"] * size_jitter.x <= room:
			fits.append(entry)
	if fits.is_empty():
		return false
	var pick: Dictionary = fits[rng.randi() % fits.size()]
	var size := rng.randf_range(size_jitter.x, minf(size_jitter.y, room / pick["tall"]))
	var growth := (pick["scene"] as PackedScene).instantiate() as Node3D
	# Named for the family that planted it. Not decoration: it is the only honest record of
	# which branch the pick took. A check tried to read that off the material instead - seaweed
	# forces two-sided shading and coral does not - and it was measuring the asset rather than
	# the code, because two of the four corals come out of Tripo doubleSided already and two do
	# not.
	growth.name = "%s%d" % [(pick["family"] as Script).resource_path.get_file()
			.get_basename().capitalize(), _planted.size()]
	add_child(growth)
	growth.global_position = Vector3(at.x, ground, at.z)
	# Ground puts the model's BOTTOM on the bed rather than its node origin. For these that is
	# the same thing to within 5 mm, but it is the same call the hand placed ones make, so a
	# scattered coral and a dragged one cannot drift apart.
	Ground.sit(growth, terrain, sink)
	growth.rotation.y = rng.randf() * TAU
	growth.scale *= size
	pick["family"].dress(growth)
	if visible_within > 0.0:
		for node in growth.find_children("*", "GeometryInstance3D", true, false):
			var drawn := node as GeometryInstance3D
			drawn.visibility_range_end = visible_within
			# Faded over the last stretch rather than popped, which is what the margin is for.
			drawn.visibility_range_end_margin = visible_within * 0.15
			drawn.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	near.append(growth.global_position)
	# is_same, not !=: arrays compare by their contents, and the crater hands in _planted itself.
	if not is_same(near, _planted):
		_planted.append(growth.global_position)
	return true


## Whether `at` is within `margin` of the footprint of anything in keep_clear.
func _kept_clear(at: Vector3, margin: float) -> bool:
	for box in keep_clear:
		var footprint := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		if footprint.grow(margin).has_point(Vector2(at.x, at.z)):
			return true
	return false


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
