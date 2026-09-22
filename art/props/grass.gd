extends MultiMeshInstance3D
## Grass tufts scattered over the island's green band.
##
## A MultiMesh, not a node each. Six hundred tufts as separate MeshInstance3Ds is six hundred
## nodes for the engine to cull and draw one at a time; as a MultiMesh it is one draw call and
## one node. The rocks and the cargo are nodes because they are few and they collide - grass is
## neither.
##
## No collision at all. You walk through it, and a tuft that stopped the captain would be worse
## than no grass.

const MODEL := "res://art/models/foliage/grass.glb"

@export var count := 700
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
@export var size_min := 0.35
@export var size_max := 0.75


## Fills the multimesh and returns how many tufts went down.
func scatter(terrain: Node, around: Vector3, rng: RandomNumberGenerator) -> int:
	if not ResourceLoader.exists(MODEL):
		push_warning("grass.gd: no model at %s" % MODEL)
		return 0
	var source: Node3D = (load(MODEL) as PackedScene).instantiate()
	var found: Array[Node] = source.find_children("*", "MeshInstance3D", true, false)
	if found.is_empty():
		source.queue_free()
		return 0
	var tuft: MeshInstance3D = found[0]
	var mesh_resource: Mesh = tuft.mesh

	var sea: float = terrain.sea_level()
	var placed: Array[Transform3D] = []
	# Tries rather than instances: most of the island is sand, sea or cliff, and a tuft that
	# lands on any of those is dropped rather than moved somewhere it does not belong.
	for attempt in count * 6:
		if placed.size() >= count:
			break
		var angle := rng.randf() * TAU
		var away := sqrt(rng.randf()) * spread
		var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
		var ground: float = terrain.height_at(at.x, at.z)
		var above := ground - sea
		if above < lowest or above > highest:
			continue
		# Slope from the ground either side. Cheaper than a normal and enough to tell a hillside
		# from a cliff.
		var slope := maxf(
			absf(terrain.height_at(at.x + 1.0, at.z) - terrain.height_at(at.x - 1.0, at.z)),
			absf(terrain.height_at(at.x, at.z + 1.0) - terrain.height_at(at.x, at.z - 1.0))) * 0.5
		if slope > max_slope:
			continue
		var scaled := rng.randf_range(size_min, size_max) / 0.91
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scaled)
		# Sunk a few centimetres, so a tuft on a slope does not stand on one corner.
		placed.append(Transform3D(basis, Vector3(at.x, ground - 0.05, at.z)))

	if placed.is_empty():
		source.queue_free()
		return 0

	var grass := MultiMesh.new()
	grass.transform_format = MultiMesh.TRANSFORM_3D
	grass.mesh = mesh_resource
	grass.instance_count = placed.size()
	for i in placed.size():
		grass.set_instance_transform(i, placed[i])
	multimesh = grass

	# The mesh keeps the material it was imported with, flattened to match everything else. It
	# is read off the source instance before that is thrown away.
	var material := mesh_resource.surface_get_material(0)
	if material is BaseMaterial3D:
		var flat: BaseMaterial3D = material.duplicate()
		flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		flat.metallic = 0.0
		flat.roughness = 1.0
		flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		# Grass is thin and one-sided as exported, which makes half of every tuft vanish
		# depending on which way the camera is looking.
		flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		material_override = flat

	# Layer 1 only. Layer 20 is the ocean's overhead mask, and grass grows above the waterline
	# anyway - putting it there would only punch holes in the foam band along the shore.
	layers = 1
	source.queue_free()
	return placed.size()
