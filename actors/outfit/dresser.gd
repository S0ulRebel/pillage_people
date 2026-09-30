class_name Dresser
extends Node
## Puts outfit pieces on a rigged body and takes them off again.
##
## Given the body's model (the instanced .glb, skeleton and all), it hangs each piece off the
## body's own skeleton: skinned pieces as extra meshes the skeleton deforms, pinned ones on a
## bone. The body's animations then move everything, because as far as the skeleton is
## concerned the coat is just more skin. Nothing here plays a clip or decides what to wear -
## the owner does that and tells this.
##
##
## Every placement in OutfitPiece is in FIT SPACE - metres, T-pose, feet on the floor, Y up,
## facing +Z - and never in whatever units and axes a rig happens to use. See rig_space.gd.

## Flat toon shading on the body and every piece, the same treatment the captain and grunts
## give their own models. Off shows the textures exactly as exported.
@export var flat := true

var _model: Node3D
var _skeleton: Skeleton3D
## Skeleton space to fit space. See rig_space.gd.
var _frame := Transform3D.IDENTITY
## The body's own meshes, captured before anything was worn - so a coat copies its weights
## from the skin and not from the shirt under it.
var _body_meshes: Array[MeshInstance3D] = []
## Built on the first skinned piece and kept; sampling the body is the slow part.
var _copier: SkinCopy
## One skin for every copied piece: each bone's rest, inverted. See _skinned_mesh().
var _skin: Skin
var _colour := Color.WHITE
## slot -> {"piece": OutfitPiece, "node": Node3D}
var _worn := {}

## Bound meshes, by body, model and fit, shared by every Dresser. The copy is the expensive
## part, and a crowd of zombies in one coat needs it once, not once each.
static var _bound := {}


## Takes over `model`: finds its skeleton and works out its fit space. Everything else needs
## this first. Returns false, loudly, for a model with no skeleton - nothing can be worn on a
## statue.
func attach(model: Node3D) -> bool:
	take_off_all()
	_model = model
	_skeleton = null
	_copier = null
	_skin = null
	_body_meshes.clear()
	if model == null:
		push_error("Dresser: nothing to dress.")
		return false
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		push_error("Dresser: '%s' has no skeleton, so nothing can be worn on it. A body has to "
				% model.scene_file_path + "be rigged before it can be dressed.")
		return false
	_skeleton = skeletons[0]
	_frame = RigSpace.frame_of(_skeleton, model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).skin != null:
			_body_meshes.append(node)
	if flat:
		flatten(model)
	_apply_colour(model)
	return true


func skeleton() -> Skeleton3D:
	return _skeleton


## Skeleton space to fit space for this body.
func frame() -> Transform3D:
	return _frame


## Takes everything off and puts `outfit` on, colour included. The body must already be
## attached - an outfit names its body, but loading and placing it is the owner's business.
func dress(outfit: Outfit) -> void:
	take_off_all()
	set_skin_colour(outfit.skin_colour)
	for piece in outfit.pieces:
		if piece != null:
			wear(piece)


## Puts `piece` on, replacing whatever was in its slot. Returns false when it could not be
## worn - no body, no model, or a model with nothing in it - having said why.
func wear(piece: OutfitPiece) -> bool:
	if _skeleton == null:
		push_error("Dresser: wear() before attach() - there is no body to put it on.")
		return false
	take_off(piece.slot)
	if not ResourceLoader.exists(piece.model):
		push_error("Dresser: no model at '%s' for the %s." % [piece.model, piece.slot])
		return false
	var node: Node3D
	if piece.hold == OutfitPiece.Hold.SKINNED:
		node = _wear_skinned(piece)
	else:
		node = _wear_pinned(piece)
	if node == null:
		return false
	_worn[piece.slot] = {"piece": piece, "node": node}
	if flat:
		flatten(node)
	if piece.skin:
		_apply_colour(node)
	return true


func take_off(slot: String) -> void:
	if not _worn.has(slot):
		return
	var node: Node = _worn[slot]["node"]
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()
	_worn.erase(slot)


func take_off_all() -> void:
	for slot in _worn.keys():
		take_off(slot)


## The piece in `slot`, or null.
func worn(slot: String) -> OutfitPiece:
	return _worn[slot]["piece"] if _worn.has(slot) else null


## Every piece being worn, in slot order.
func pieces() -> Array[OutfitPiece]:
	var out: Array[OutfitPiece] = []
	for slot in OutfitPiece.SLOTS:
		if _worn.has(slot):
			out.append(_worn[slot]["piece"])
	return out


## The node a worn piece is drawn by - a MeshInstance3D for a skinned piece, the holder under
## a BoneAttachment3D for a pinned one. For tests and the workshop.
func node_for(slot: String) -> Node3D:
	return _worn[slot]["node"] if _worn.has(slot) else null


## Puts the piece in `slot` where its fit now says. A pinned piece just moves; a skinned one
## has to be bound again, because its weights depend on where it sits.
func refit(slot: String) -> void:
	if not _worn.has(slot):
		return
	var piece: OutfitPiece = _worn[slot]["piece"]
	var holder: Node3D = _worn[slot]["node"]
	var socket := holder.get_parent() as BoneAttachment3D
	# Same bone: just move it. A new bone, or a piece that now bends, has to be put on again.
	if piece.hold == OutfitPiece.Hold.PINNED and socket != null and socket.bone_name == piece.bone:
		holder.transform = _holder_transform(piece)
	else:
		wear(piece)


## Tints the body and every piece marked `skin`. White is the texture as painted.
func set_skin_colour(colour: Color) -> void:
	_colour = colour
	if _model == null:
		return
	# The body, but not pieces hung under its skeleton: those are tinted only if they are skin.
	for mesh_node in _body_meshes:
		_tint(mesh_node)
	for entry in _worn.values():
		if (entry["piece"] as OutfitPiece).skin:
			_apply_colour(entry["node"])


func skin_colour() -> Color:
	return _colour


## Stands the body in its rest pose, the T-pose, upright - the pose pieces are fitted in.
##
## Not simply the rest pose: on these rigs that is lying face down, and each clip's hip
## track is what stands him up. So the rest is restored and the root bone alone is turned to
## put fit space the right way up, which carries every other bone with it.
func stand_at_rest() -> void:
	if _skeleton == null:
		return
	_skeleton.reset_bone_poses()
	var to_skeleton := RigSpace.chain(_skeleton, _model)
	for bone in _skeleton.get_bone_count():
		if _skeleton.get_bone_parent(bone) != -1:
			continue
		var upright := to_skeleton.affine_inverse() * _frame * _skeleton.get_bone_rest(bone)
		_skeleton.set_bone_pose(bone, upright)


## Where a bone's joint is in fit space, at rest. The workshop guesses fits from these.
func bone_position(bone_name: String) -> Vector3:
	var bone := _skeleton.find_bone(bone_name) if _skeleton != null else -1
	if bone == -1:
		return Vector3.ZERO
	return _frame * _skeleton.get_bone_global_rest(bone).origin


func has_bone(bone_name: String) -> bool:
	return _skeleton != null and _skeleton.find_bone(bone_name) != -1


## The box round the body's own skin between two heights, in fit space, at rest. Whatever is
## worn is not counted. The workshop reads skull and hip widths off this to guess a first fit.
func body_slice(from_y: float, to_y: float) -> AABB:
	var copier := _body_copier()
	return copier.slice(from_y, to_y) if copier != null else AABB()


## The whole body's box, in fit space, at rest.
func body_bounds() -> AABB:
	return body_slice(-INF, INF)


## The body sampled for weight copying, built on first use. Null, having said so, when the
## body has no skinned mesh.
func _body_copier() -> SkinCopy:
	if _copier == null and _skeleton != null:
		_copier = SkinCopy.new(_skeleton, _body_meshes, _frame)
		if _copier.size() == 0:
			push_error("Dresser: the body has no skinned mesh to copy weights from.")
	return _copier if _copier != null and _copier.size() > 0 else null


## Toon-flat materials, as the captain and grunts use. Each mesh keeps its unflattened material
## in metadata, so tinting later starts from the original colour rather than compounding.
static func flatten(root: Node) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		# Layer 20 is the overhead water-interaction camera; anything visible has to be on it.
		mesh_node.set_layer_mask_value(20, true)
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface)
			if not (material is BaseMaterial3D):
				continue
			var flat_material: BaseMaterial3D = material.duplicate()
			flat_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
			flat_material.metallic = 0.0
			flat_material.roughness = 1.0
			flat_material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
			mesh_node.set_surface_override_material(surface, flat_material)
			mesh_node.set_meta("untinted_%d" % surface, flat_material)


func _wear_skinned(piece: OutfitPiece) -> Node3D:
	var mesh := _skinned_mesh(piece)
	if mesh == null:
		return null
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "%s_%s" % [piece.slot.capitalize(), piece.label().to_pascal_case()]
	mesh_node.mesh = mesh
	mesh_node.skin = _skin
	# Under the skeleton at no offset, which is exactly where the body's own mesh sits: the
	# vertices below are in the skeleton's space, and the skeleton moves them from there.
	_skeleton.add_child(mesh_node)
	mesh_node.skeleton = NodePath("..")
	return mesh_node


func _wear_pinned(piece: OutfitPiece) -> Node3D:
	var bone := _skeleton.find_bone(piece.bone)
	if bone == -1:
		push_error("Dresser: the %s rides '%s', and this body has no such bone." % [piece.slot,
				piece.bone])
		return null
	var model := _instance(piece.model)
	if model == null:
		return null
	var socket := BoneAttachment3D.new()
	socket.name = "%sSocket" % piece.slot.capitalize()
	_skeleton.add_child(socket)
	# Set after it is in the tree, or there is no skeleton yet to look the name up in.
	socket.bone_name = piece.bone
	var holder := Node3D.new()
	holder.name = piece.slot.capitalize()
	holder.transform = _holder_transform(piece)
	socket.add_child(holder)
	holder.add_child(model)
	# The holder is what the workshop moves and what take_off() frees, so it has to take its
	# socket with it - an empty socket per swap would pile up on the head bone.
	holder.tree_exiting.connect(socket.queue_free)
	return holder


## Where the holder sits under its bone so the piece lands on its fit in the T-pose.
##
## The socket follows the bone, so in the T-pose it sits at frame * rest. Undoing that and then
## applying the fit puts the piece where the fit says - and because the undo includes the rig's
## centimetre scale, the piece comes out at its own size rather than a hundredth of it, which
## held.gd has to correct by measuring after the fact.
func _holder_transform(piece: OutfitPiece) -> Transform3D:
	var bone := _skeleton.find_bone(piece.bone)
	var at_rest := _frame * _skeleton.get_bone_global_rest(bone)
	return at_rest.affine_inverse() * piece.fit()


## The piece's geometry, moved into the skeleton's space and weighted to its bones.
##
## The skin it is drawn with binds each bone at its rest, so a vertex placed at its rest
## position in the skeleton's space stays exactly there in the T-pose and is carried by its
## bones from there - no per-rig bind conventions to reproduce.
func _skinned_mesh(piece: OutfitPiece) -> ArrayMesh:
	var key := "%s|%s|%s" % [_model.scene_file_path, piece.model, piece.fit()]
	if _skin == null:
		_skin = Skin.new()
		for bone in _skeleton.get_bone_count():
			_skin.add_named_bind(_skeleton.get_bone_name(bone),
					_skeleton.get_bone_global_rest(bone).affine_inverse())
	if _bound.has(key):
		return _bound[key]
	var model := _instance(piece.model)
	if model == null:
		return null
	var into_skeleton := _frame.affine_inverse()
	var out := ArrayMesh.new()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if source.mesh == null:
			continue
		for surface in source.mesh.get_surface_count():
			# Primitive meshes are always triangles; an imported one might be lines or points.
			if source.mesh is ArrayMesh and (source.mesh as ArrayMesh) \
					.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := source.mesh.surface_get_arrays(surface)
			if not _bind_surface(arrays, source, model, piece.fit(), into_skeleton):
				continue
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1,
					source.get_active_material(surface))
	model.free()
	if out.get_surface_count() == 0:
		push_error("Dresser: '%s' has no triangles to wear." % piece.model)
		return null
	_bound[key] = out
	return out


## Rewrites one surface's arrays in place: positions, normals and tangents into the skeleton's
## space, bones and weights added. False when there was nothing to bind.
func _bind_surface(arrays: Array, source: MeshInstance3D, model: Node3D, fit: Transform3D,
		into_skeleton: Transform3D) -> bool:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return false
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	var tangents := PackedFloat32Array()
	if arrays[Mesh.ARRAY_TANGENT] != null:
		tangents = arrays[Mesh.ARRAY_TANGENT]
	var own := _own_weights(source)
	var to_fit: Transform3D
	var own_rest: Array[Transform3D] = []
	var own_bones := PackedInt32Array()
	var own_weights := PackedFloat32Array()
	var stride := 0
	if own.is_empty():
		to_fit = fit * RigSpace.chain(source, model)
	else:
		# Already rigged to the same bone names: keep its weights, and stand it in its own
		# T-pose the same way the body is stood in its own.
		to_fit = fit * (own["frame"] as Transform3D)
		own_rest = own["rest"]
		own_bones = arrays[Mesh.ARRAY_BONES]
		own_weights = arrays[Mesh.ARRAY_WEIGHTS]
		stride = own_bones.size() / vertices.size()
	if own.is_empty() and _body_copier() == null:
		return false
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(vertices.size() * 4)
	weights.resize(vertices.size() * 4)
	var placed := (into_skeleton * to_fit).basis
	for i in vertices.size():
		var at: Vector3
		var packed: Array
		# What happens to this vertex's directions on the way into the skeleton's space. For a
		# rigged piece that includes its own bind, which on a Tripo rig is itself a quarter turn.
		var turn := placed
		if own.is_empty():
			at = to_fit * vertices[i]
			packed = _copier.weights_at(at)
		else:
			var rest_at := Vector3.ZERO
			var rest_turn := Basis()
			var heaviest := 0.0
			var influences := {}
			var bone_map: PackedInt32Array = own["bone_map"]
			for k in stride:
				var w := own_weights[i * stride + k]
				if w <= 0.0:
					continue
				var bind := own_bones[i * stride + k]
				rest_at += (own_rest[bind] * vertices[i]) * w
				# Every bind turns directions the same way at rest; the heaviest one will do.
				if w > heaviest:
					heaviest = w
					rest_turn = own_rest[bind].basis
				var bone := bone_map[bind]
				influences[bone] = influences.get(bone, 0.0) + w
			at = to_fit * rest_at
			turn = placed * rest_turn
			packed = SkinCopy.top_four(influences)
		vertices[i] = into_skeleton * at
		for k in 4:
			bones[i * 4 + k] = (packed[0] as PackedInt32Array)[k]
			weights[i * 4 + k] = (packed[1] as PackedFloat32Array)[k]
		# Normals by the inverse transpose, so a coat stretched wider than it was modelled
		# still shades as if its surface faces the way it now does.
		if i < normals.size():
			normals[i] = (turn.inverse().transposed() * normals[i]).normalized()
		if i * 4 + 2 < tangents.size():
			var t := (turn * Vector3(tangents[i * 4], tangents[i * 4 + 1],
					tangents[i * 4 + 2])).normalized()
			tangents[i * 4] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if not tangents.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	return true


## For a piece that arrived rigged: its bind transforms at rest, its fit space, and which of
## the body's bones each of its binds means. Empty when it is not rigged, or not to anything
## this body has.
##
## A bone the body lacks - a jaw, say - hands its weight to the nearest ancestor the body does
## have, so the piece moves with the head rather than tearing loose.
func _own_weights(source: MeshInstance3D) -> Dictionary:
	if source.skin == null:
		return {}
	var own_skeleton := source.get_node_or_null(source.skeleton) as Skeleton3D
	if own_skeleton == null:
		return {}
	var rest: Array[Transform3D] = []
	var bone_map := PackedInt32Array()
	var matched := 0
	for bind in source.skin.get_bind_count():
		var own_bone := source.skin.get_bind_bone(bind)
		if own_bone == -1:
			own_bone = own_skeleton.find_bone(source.skin.get_bind_name(bind))
		rest.append(own_skeleton.get_bone_global_rest(maxi(own_bone, 0))
				* source.skin.get_bind_pose(bind))
		var body_bone := -1
		var walk := own_bone
		while walk != -1 and body_bone == -1:
			body_bone = _skeleton.find_bone(own_skeleton.get_bone_name(walk))
			walk = own_skeleton.get_bone_parent(walk)
		if body_bone != -1:
			matched += 1
		bone_map.append(maxi(body_bone, 0))
	if matched == 0:
		return {}
	var root := source.owner if source.owner != null else own_skeleton.get_parent()
	return {"rest": rest, "bone_map": bone_map, "frame": RigSpace.frame_of(own_skeleton, root)}


func _apply_colour(root: Node) -> void:
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for node in meshes:
		_tint(node as MeshInstance3D)


func _tint(mesh_node: MeshInstance3D) -> void:
	if mesh_node.mesh == null:
		return
	for surface in mesh_node.mesh.get_surface_count():
		var key := "untinted_%d" % surface
		if not mesh_node.has_meta(key):
			var original := mesh_node.get_active_material(surface)
			if not (original is BaseMaterial3D):
				continue
			mesh_node.set_meta(key, original)
		var base: BaseMaterial3D = mesh_node.get_meta(key)
		if _colour == Color.WHITE:
			mesh_node.set_surface_override_material(surface, base)
			continue
		var tinted: BaseMaterial3D = base.duplicate()
		tinted.albedo_color = base.albedo_color * _colour
		mesh_node.set_surface_override_material(surface, tinted)


static func _instance(path: String) -> Node3D:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("Dresser: '%s' is not a scene or model." % path)
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		push_error("Dresser: '%s' is not a 3D model." % path)
	return node
