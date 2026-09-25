@tool
class_name ScatterPatch
extends Node3D
## Scatters any prefab over a patch of ground. Drag it in, point it at some scenes, tune it,
## and when you like what you see, bake it into real nodes you can move one by one.
##
## THE ONE IDEA. Every scatterer in this project differs from the others in two things: which
## scenes it places, and a band relative to sea level. Rocks want ground at least 0.6 m above
## the water, palms 0.8 to 6 m above, grass 3.6 to 9, corals at least 4 m under. Said as one
## signed number - metres of water over the ground, negative above it - those are four values
## of the same parameter, and everything else they do is jitter, spacing and slope. So this
## node has no idea what a rock or a coral is.
##
## It keeps deciding and drawing apart. `placements()` works out a list of transforms and
## nothing else; the emitter turns that list into something you can see. Tests read the list.
##
## PREVIEW, THEN BAKE. Until you bake, the instances are children with no owner, so Godot does
## not save them: the scene file stays a few lines whatever the count, and every change to a
## parameter throws them away and starts again. Baking gives them an owner, which saves them
## into the scene and stops this node touching them ever again - from that moment they are
## ordinary nodes to select, nudge, rotate, duplicate or delete. That is the whole point of it;
## a scatter you cannot correct by hand is a dice roll you have to accept.

## What to place. Each is picked at random per instance, so two scenes give you two kinds mixed.
@export var scenes: Array[PackedScene] = []:
	set(value):
		scenes = value
		_replant()
@export var count := 24:
	set(value):
		count = value
		_replant()
## Metres. Nothing lands outside this, or inside `inner_radius`.
@export_range(0.5, 120.0, 0.5, "suffix:m") var radius := 20.0:
	set(value):
		radius = value
		_replant()
@export_range(0.0, 120.0, 0.5, "suffix:m") var inner_radius := 0.0:
	set(value):
		inner_radius = value
		_replant()
@export var seed := 1:
	set(value):
		seed = value
		_replant()
## Even over the area, or crowded toward the middle and ragged at the edge.
##
## A knob rather than a fork in the code: grass wants the second - a clump reads as a clump -
## and a reef wants the first. They were two different lines in two different files before.
enum Spread {EVEN, CENTRE_HEAVY}
@export var spread: Spread = Spread.EVEN:
	set(value):
		spread = value
		_replant()
## Nothing plants within this of another. 0 lets them overlap, which is right for rocks and
## wrong for anything with a silhouette you can read.
@export_range(0.0, 20.0, 0.1, "suffix:m") var spacing := 2.0:
	set(value):
		spacing = value
		_replant()
@export var size_jitter := Vector2(0.8, 1.3):
	set(value):
		size_jitter = value
		_replant()
@export var random_yaw := true:
	set(value):
		random_yaw = value
		_replant()

@export_group("Ground")
## Sit each one on the ground under it. Off, they stay on this node's own plane.
@export var on_ground := true:
	set(value):
		on_ground = value
		_replant()
## How far into the ground they sink. Palms use 0.1, grass 0.05, corals 0.06.
@export_range(-2.0, 2.0, 0.01, "suffix:m") var sink := 0.0:
	set(value):
		sink = value
		_replant()
## Tilt to the slope instead of standing bolt upright. Everything in this world is planted
## upright today; this is here because a rock field on a hillside wants it and nothing else did.
@export var align_to_slope := false:
	set(value):
		align_to_slope = value
		_replant()
@export_range(0.0, 1.0) var slope_weight := 0.6:
	set(value):
		slope_weight = value
		_replant()
## Refuse ground steeper than this, on the measure palms and grass already use: 0.5 is about 27
## degrees. 1.0 accepts anything.
@export_range(0.0, 1.0) var max_slope := 1.0:
	set(value):
		max_slope = value
		_replant()

@export_group("Water")
## METRES OF WATER over the ground, as a band. Negative is dry land above the waterline, so one
## number covers both sides of it and this is the parameter that makes the node general:
##
##     rocks   Vector2(-1000, -0.6)      at least 0.6 m above the sea
##     palms   Vector2(-6.0, -0.8)       a band up the beach
##     grass   Vector2(-9.0, -3.6)       higher still
##     corals  Vector2(4.0, 1000)        at least 4 m under
@export var water_band := Vector2(-1000.0, 1000.0):
	set(value):
		water_band = value
		_replant()
## Refuse anywhere the instance would stick out of the sea. For things that live under it: a
## coral that breaches is the one thing in the water that punches no foam ring.
@export var stay_submerged := false:
	set(value):
		stay_submerged = value
		_replant()
@export_range(0.0, 10.0, 0.1, "suffix:m") var surface_clearance := 1.0:
	set(value):
		surface_clearance = value
		_replant()

@export_group("Bake")
## Tick to turn the preview into real, saved nodes and let go of them. It unticks itself: it is
## an action, not a state - Godot has no button in the inspector without an editor plugin.
@export var bake: bool = false:
	set(value):
		bake = false
		if value:
			_bake()
## Tick to throw away what was baked and go back to a live preview.
@export var clear: bool = false:
	set(value):
		clear = false
		if value:
			_clear()
## Set by _bake. While it is on, this node does not touch its children at all - they are yours.
@export var baked: bool = false:
	set(value):
		baked = value
		if not baked:
			_replant()

## How many the last pass actually planted. Fewer than `count` means the filters are refusing;
## read it before blaming the seed.
var planted := 0


func _ready() -> void:
	_replant()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_replant()


func _enter_tree() -> void:
	set_notify_transform(true)


## Where everything goes, and nothing about what it looks like.
##
## Returns one transform per instance IN WORLD SPACE, plus which scene index each one wants.
## World rather than local on purpose: every rule here is about the world - how deep the water
## is, how steep the ground is, how far apart two things are - and a patch the author has
## rotated would otherwise tip everything it plants on its side.
##
## Separated from the planting so a test can measure the decision without reading the tree: a
## check that walks children measures the emitter, and the emitter is the part least likely to
## be wrong.
func placements() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= 0 or radius <= 0.0:
		return out
	var terrain := Ground.find(self)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var taken: Array[Vector3] = []
	var here := global_position
	for i in count:
		for attempt in 12:
			var angle := rng.randf() * TAU
			# EVEN uses sqrt so the instances spread over the AREA rather than crowding the
			# middle; CENTRE_HEAVY multiplies two randoms, which is grass's dense-middle clump.
			var t := rng.randf()
			var reach: float = sqrt(t) if spread == Spread.EVEN else t * rng.randf()
			var away: float = inner_radius + reach * maxf(radius - inner_radius, 0.0)
			var at := Vector3(here.x + cos(angle) * away, here.y, here.z + sin(angle) * away)
			if terrain != null:
				if not _ground_allows(terrain, at):
					continue
				at.y = terrain.height_at(at.x, at.z) - sink if on_ground else here.y
			var clash := false
			for other in taken:
				if Vector2(other.x - at.x, other.z - at.z).length() < spacing:
					clash = true
					break
			if clash:
				continue
			var which: int = rng.randi() % maxi(scenes.size(), 1)
			var size := rng.randf_range(size_jitter.x, size_jitter.y)
			if terrain != null and stay_submerged and scenes.size() > which:
				var tall := _height_of(scenes[which]) * size
				if at.y + tall + surface_clearance > terrain.sea_level():
					continue
			var basis := Basis.IDENTITY
			if random_yaw:
				basis = basis.rotated(Vector3.UP, rng.randf() * TAU)
			basis = basis.scaled(Vector3.ONE * size)
			taken.append(at)
			out.append({"scene": which, "at": at, "basis": basis})
			break
	return out


## Whether the ground at `at` passes the band and the slope.
func _ground_allows(terrain: Node, at: Vector3) -> bool:
	var deep := Ground.depth(terrain, at.x, at.z)
	if deep < minf(water_band.x, water_band.y) or deep > maxf(water_band.x, water_band.y):
		return false
	return Ground.slope(terrain, at.x, at.z) <= max_slope


func _replant() -> void:
	if not is_inside_tree() or baked:
		return
	for child in get_children():
		child.free()
	planted = 0
	if scenes.is_empty():
		return
	var terrain := Ground.find(self)
	for spot in placements():
		var packed: PackedScene = scenes[spot["scene"]]
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		if instance == null:
			continue
		instance.name = "Scattered%d" % planted
		add_child(instance)
		instance.global_transform = Transform3D(spot["basis"], spot["at"])
		if align_to_slope and terrain != null:
			Ground.lean(instance, terrain, slope_weight)
		planted += 1


## Hands the instances over: gives them an owner so the scene saves them, and stops managing
## them. Anything with an owner survives a reload and can be edited like any other node.
func _bake() -> void:
	if not Engine.is_editor_hint() or baked:
		return
	var root := get_tree().edited_scene_root if get_tree() != null else null
	if root == null:
		push_warning("scatter_patch: nothing to bake into - this only works in the editor.")
		return
	for child in get_children():
		child.owner = root
		for deep in child.find_children("*", "", true, false):
			deep.owner = root
	baked = true


## Throws the baked children away and goes back to a preview.
func _clear() -> void:
	for child in get_children():
		child.free()
	planted = 0
	baked = false
	_replant()


## How tall one of these scenes stands, before scaling. Instantiated and thrown away, because a
## PackedScene will not tell you without building it.
static func _height_of(packed: PackedScene) -> float:
	if packed == null:
		return 0.0
	var probe := packed.instantiate() as Node3D
	if probe == null:
		return 0.0
	var box := AABB()
	var first := true
	for node in probe.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var here: AABB = mesh_node.transform * mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	probe.free()
	return box.size.y
