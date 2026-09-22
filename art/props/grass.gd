extends MultiMeshInstance3D
## Grass, scattered in patches over the island's green band.
##
## A MultiMesh, not a node each. Hundreds of tufts as separate MeshInstance3Ds is hundreds of
## things for the engine to cull and draw one at a time; as a MultiMesh it is one draw call and
## one node. The rocks and the cargo are nodes because they are few and they collide - grass is
## neither, and you walk through it.
##
## Grass grows in patches, not evenly. Scattering tufts one at a time over an area gives a lawn
## of equally spaced dots that reads as a texture rather than as plants, however many there are.
## So the work is done twice over: a handful of patch centres are chosen against the terrain,
## and each one is then filled with a clump whose tufts crowd toward its middle.
##
## No collision at all. A tuft that stopped the captain would be worse than no grass.

const MODEL := "res://art/models/foliage/grass.glb"

## How many clumps, and how many tufts in each. The total is roughly the two multiplied.
@export var patches := 70
@export var per_patch := Vector2i(7, 20)
## How wide a clump spreads, in metres.
@export var patch_radius := Vector2(1.1, 3.2)
## Where grass grows, in metres above sea level. The terrain shader paints sand up to 3.5 and
## turns to jungle around 8.8, so this is the green band between - see terrain.gdshader.
@export var lowest := 3.6
@export var highest := 9.0
## How far out to scatter, from the point handed in.
@export var spread := 110.0
## Nothing on cliffs. The shader turns steep ground to rock, and grass standing on a rock face
## reads as grass floating, so anything over this is skipped. Measured as the height change
## across a metre.
@export var max_slope := 0.55
## The model is about 0.91 m tall as authored - a big clump. These are the finished heights.
@export var size_min := 0.30
@export var size_max := 0.70

var _placed: Array[Transform3D] = []
var _mesh: Mesh
var _material: BaseMaterial3D


## Chooses patch centres across the green band and fills each one. `extra` is a list of world
## points to plant a clump on regardless of the usual search - main.gd passes the rocks, so
## grass grows against them the way it does in life.
func scatter(terrain: Node, around: Vector3, rng: RandomNumberGenerator,
		extra: Array[Vector3] = []) -> int:
	if not _load_mesh():
		return 0
	for point in extra:
		if _suits(terrain, point.x, point.z):
			_clump(terrain, point.x, point.z, rng)
	for attempt in patches * 8:
		if _placed.size() >= patches * per_patch.y:
			break
		var angle := rng.randf() * TAU
		var away := sqrt(rng.randf()) * spread
		var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
		if not _suits(terrain, at.x, at.z):
			continue
		_clump(terrain, at.x, at.z, rng)
		if _clumps >= patches + extra.size():
			break
	return commit()


var _clumps := 0


## One clump: tufts crowded toward a centre rather than spread evenly across it.
func _clump(terrain: Node, x: float, z: float, rng: RandomNumberGenerator) -> void:
	_clumps += 1
	var radius := rng.randf_range(patch_radius.x, patch_radius.y)
	var tufts := rng.randi_range(per_patch.x, per_patch.y)
	for i in tufts:
		var angle := rng.randf() * TAU
		# Squaring the radius pulls tufts inward, so a clump has a dense middle and a ragged
		# edge. A flat random radius spreads them evenly and gives a disc, not a clump.
		var away := rng.randf() * rng.randf() * radius
		var px := x + cos(angle) * away
		var pz := z + sin(angle) * away
		var ground: float = terrain.height_at(px, pz)
		var scaled := rng.randf_range(size_min, size_max) / 0.91
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scaled)
		# Sunk a few centimetres, so a tuft on a slope does not stand on one corner.
		_placed.append(Transform3D(basis, Vector3(px, ground - 0.05, pz)))


## Plants clumps at named points and nothing else - used by the shoreline group, which composes
## its own planting rather than taking whatever the island scatter gives it.
func plant(terrain: Node, points: Array[Vector3], rng: RandomNumberGenerator) -> int:
	if not _load_mesh():
		return 0
	for point in points:
		_clump(terrain, point.x, point.z, rng)
	return commit()


## Is this ground grass at all? Above the sand, below the jungle, and not a cliff.
func _suits(terrain: Node, x: float, z: float) -> bool:
	var ground: float = terrain.height_at(x, z)
	var above: float = ground - terrain.sea_level()
	if above < lowest or above > highest:
		return false
	var slope: float = maxf(
		absf(terrain.height_at(x + 1.0, z) - terrain.height_at(x - 1.0, z)),
		absf(terrain.height_at(x, z + 1.0) - terrain.height_at(x, z - 1.0))) * 0.5
	return slope <= max_slope


func _load_mesh() -> bool:
	if _mesh != null:
		return true
	if not ResourceLoader.exists(MODEL):
		push_warning("grass.gd: no model at %s" % MODEL)
		return false
	var source: Node3D = (load(MODEL) as PackedScene).instantiate()
	var found: Array[Node] = source.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		source.queue_free()
		return false
	_mesh = (found[0] as MeshInstance3D).mesh
	var material := _mesh.surface_get_material(0)
	if material is BaseMaterial3D:
		var flat: BaseMaterial3D = material.duplicate()
		flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		flat.metallic = 0.0
		flat.roughness = 1.0
		flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		# Grass is thin and one-sided as exported, which makes half of every tuft vanish
		# depending on which way the camera is looking.
		flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_material = flat
	source.queue_free()
	return true


## Hands everything collected to the multimesh.
func commit() -> int:
	if _placed.is_empty() or _mesh == null:
		return 0
	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.mesh = _mesh
	grass.instance_count = _placed.size()
	# Instance transforms are read in the node's OWN space, and the positions above are world
	# ones because that is what the terrain answers in. On a node parented to the scene root the
	# two are the same and nothing shows; the shoreline group sits at (135, 19.7, -90) with a
	# rotation of its own, so its planting was transformed a second time and ended up hundreds
	# of metres out and up in the sky.
	var into_local := global_transform.affine_inverse()
	for i in _placed.size():
		grass.set_instance_transform(i, into_local * _placed[i])
	multimesh = grass
	if _material != null:
		material_override = _material
	# Layer 1 only. Layer 20 is the ocean's overhead mask, and grass grows above the waterline
	# anyway - putting it there would only punch holes in the foam band along the shore.
	layers = 1
	return _placed.size()
