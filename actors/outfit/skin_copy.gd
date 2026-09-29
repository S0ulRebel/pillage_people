class_name SkinCopy
extends RefCounted
## Gives an unrigged model the skin weights of the body it is worn on.
##
## Tripo hands back every piece as a statue: vertices and a texture, nothing that says which
## bone moves them. A coat worn like that would stand still while the arms inside it walked
## away. So each vertex of the piece borrows the weights of the body vertices nearest to it -
## a sleeve takes the arm's weights, a cuff the wrist's, a collar the neck's - and from then on
## the piece bends exactly as the skin under it does.
##
## This is Blender's "copy weights from the nearest surface", done here instead so fitting a
## piece and seeing it walk is one step in the workshop rather than a round trip through
## another program.
##
## The nearest FOUR body points are blended, weighted by distance, rather than the single
## nearest. One point is exact on skin-tight clothes and tears on loose ones: halfway between
## the thighs, the nearest point flips from one leg to the other between two neighbouring coat
## vertices, and the coat splits up the middle the moment he takes a step.
##
## Everything here is measured in fit space - metres, T-pose, feet on the floor - which is
## where OutfitPiece's placement lives too. See dresser.gd for how a rig's own space maps to it.

## Grid cell edge, in metres. Small enough that a cell holds a handful of body points, so a
## lookup compares against tens rather than thousands.
const CELL := 0.03
## Body points closer together than this are one point. The grunt's body is 30,573 vertices,
## most of them texture seams and detail no piece of cloth can tell apart; keeping one per
## 1.5 cm is what keeps a 5,000-vertex coat under a second.
const MERGE := 0.015
## How many body points each piece vertex blends between. See above for why not one.
const NEAREST := 4
## Beyond this many cells out, stop searching the grid and take the long way round - something
## a long way from the body, like a parrot on a pole, is rare enough to be allowed to be slow.
const SEARCH := 8

var _points := PackedVector3Array()
## Four bone indices and four weights per point - skeleton bones, not the body skin's binds.
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _grid := {}


## Samples the body. `meshes` are its skinned meshes, `frame` takes the skeleton's own space
## into fit space - see Dresser.frame_of().
##
## Reads the REST pose, not whatever the body is doing right now, so it gives the same answer
## mid-walk as it does standing still.
func _init(skeleton: Skeleton3D, meshes: Array[MeshInstance3D], frame: Transform3D) -> void:
	var seen := {}
	for mesh_node in meshes:
		var skin := mesh_node.skin
		if skin == null or mesh_node.mesh == null:
			continue
		# What each bind does to a vertex at rest, and which skeleton bone it names. A bind is
		# looked up by name when the importer left its index unset, which is how these arrive.
		var rest: Array[Transform3D] = []
		var bone_of := PackedInt32Array()
		for bind in skin.get_bind_count():
			var bone := skin.get_bind_bone(bind)
			if bone == -1:
				bone = skeleton.find_bone(skin.get_bind_name(bind))
			bone_of.append(bone)
			rest.append(skeleton.get_bone_global_rest(maxi(bone, 0)) * skin.get_bind_pose(bind)
					if bone != -1 else Transform3D.IDENTITY)
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty() or arrays[Mesh.ARRAY_BONES] == null:
				continue
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			# 4 or 8 influences a vertex, depending on how the mesh was exported.
			var stride := bones.size() / vertices.size()
			for i in vertices.size():
				var at := Vector3.ZERO
				var influences := {}
				for k in stride:
					var w := weights[i * stride + k]
					if w <= 0.0:
						continue
					var bind := bones[i * stride + k]
					at += (rest[bind] * vertices[i]) * w
					var bone := bone_of[bind]
					if bone != -1:
						influences[bone] = influences.get(bone, 0.0) + w
				var point := frame * at
				var key := Vector3i((point / MERGE).floor())
				if seen.has(key):
					continue
				seen[key] = true
				_add(point, influences)


## How many body points were kept. Zero means the body had no skinned mesh to copy from.
func size() -> int:
	return _points.size()


## The box round every body point between two heights, in fit space - how wide the skull is,
## how far forward the face comes, how broad the hips are. An empty AABB when nothing is there.
func slice(from_y: float, to_y: float) -> AABB:
	var box := AABB()
	var started := false
	for point in _points:
		if point.y < from_y or point.y > to_y:
			continue
		if not started:
			box = AABB(point, Vector3.ZERO)
			started = true
		else:
			box = box.expand(point)
	return box


## The weights for a point in fit space: [PackedInt32Array bones, PackedFloat32Array weights],
## four of each, heaviest first, adding up to one.
func weights_at(point: Vector3) -> Array:
	var found := _nearest(point)
	var blended := {}
	for pick in found:
		var index: int = pick[0]
		# Inverse distance, with a floor so a vertex sitting exactly on a body point does not
		# divide by zero - it simply takes that point's weights.
		var pull := 1.0 / maxf(pick[1], 0.002)
		for k in 4:
			var w := _weights[index * 4 + k]
			if w <= 0.0:
				continue
			var bone := _bones[index * 4 + k]
			blended[bone] = blended.get(bone, 0.0) + w * pull
	return top_four(blended)


func _add(point: Vector3, influences: Dictionary) -> void:
	var packed := top_four(influences)
	var index := _points.size()
	_points.append(point)
	_bones.append_array(packed[0])
	_weights.append_array(packed[1])
	var cell := Vector3i((point / CELL).floor())
	if not _grid.has(cell):
		_grid[cell] = PackedInt32Array()
	# Dictionaries hand back packed arrays by value, so append to a copy and put it back.
	var members: PackedInt32Array = _grid[cell]
	members.append(index)
	_grid[cell] = members


## The NEAREST body points to `point`, as [index, distance] pairs.
##
## Searches outwards a shell of cells at a time. Finding enough points is not the same as
## finding the nearest ones - a point just across a cell wall can be closer than one in the far
## corner of this cell - so once enough are found it searches one more shell and then stops.
func _nearest(point: Vector3) -> Array:
	var centre := Vector3i((point / CELL).floor())
	var best: Array = []
	var last := -1
	for radius in SEARCH + 1:
		_search_shell(centre, radius, point, best)
		if best.size() >= NEAREST and last == -1:
			last = radius + 1
		if last != -1 and radius >= last:
			return best
	if best.size() >= NEAREST:
		return best
	# Too far out for the grid to be worth it. Rare, so the plain way round is fine.
	best.clear()
	for index in _points.size():
		_consider(index, point.distance_to(_points[index]), best)
	return best


func _search_shell(centre: Vector3i, radius: int, point: Vector3, best: Array) -> void:
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				# Only the shell: the inside was searched on the way out.
				if maxi(absi(x), maxi(absi(y), absi(z))) != radius:
					continue
				var members = _grid.get(centre + Vector3i(x, y, z))
				if members == null:
					continue
				for index in members:
					_consider(index, point.distance_to(_points[index]), best)


## Keeps `best` as the NEAREST closest [index, distance] pairs seen so far, closest first.
func _consider(index: int, distance: float, best: Array) -> void:
	if best.size() >= NEAREST and distance >= best[-1][1]:
		return
	var at := best.size()
	while at > 0 and best[at - 1][1] > distance:
		at -= 1
	best.insert(at, [index, distance])
	if best.size() > NEAREST:
		best.pop_back()


## The four heaviest influences in `weights` (bone -> weight), normalised to add up to one.
## Normalised after the cut, so dropping a fifth bone does not leave the other four summing to
## less than one and the vertex shrinking towards the skeleton's origin.
static func top_four(weights: Dictionary) -> Array:
	var ranked := weights.keys()
	ranked.sort_custom(func(a: int, b: int) -> bool: return weights[a] > weights[b])
	var bones := PackedInt32Array([0, 0, 0, 0])
	var values := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var sum := 0.0
	for k in mini(4, ranked.size()):
		bones[k] = ranked[k]
		values[k] = weights[ranked[k]]
		sum += values[k]
	if sum <= 0.0:
		values[0] = 1.0
		return [bones, values]
	for k in 4:
		values[k] /= sum
	return [bones, values]
