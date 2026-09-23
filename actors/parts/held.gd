class_name Held
extends MeshInstance3D
## Something in a character's hand: hung off a hand bone, turned the right way up, and scaled
## out of the rig's own units.
##
## This is the awkward half of holding anything, and it is awkward enough that it should exist
## once. It was the captain's cutlass alone, then the grunts needed a sword too, and a pistol
## makes three - which is when shared code stops being a coincidence. A torch, a lantern or a
## chest would want exactly the same and none of them is a weapon, which is why this is Held
## rather than Weapon.
##
## What it does NOT do is decide what the thing is for. A sword adds a hitbox, a gun adds a
## muzzle and a ray, a lantern adds a light. Those live in their own scripts next to this one.
##
## Things hang along the hand bone's +X axis. Measured rather than guessed: on these rigs the
## knuckles run index to ring along -X, so something leaving the fist on the index side - the
## way a sword or a pistol is actually held - points along +X. A mesh authored along some other
## axis only needs a rotation passed in.

var _offset := Vector3.ZERO


## Hangs `model_path` off `bone`, or a plain box if there is no model. Returns false when the
## bone is missing, so a body with an unexpected rig ends up empty-handed rather than
## half-built.
##
## `rotation_deg` turns the model onto the +X axis above, and `grip` then slides it along so the
## hand holds the handle. A rotation alone cannot do that second part: the model's origin is
## wherever it was authored - the cutlass is modelled tip-down, so its origin is the point - and
## turning it only ever spins that same origin about the fist.
func mount(skeleton: Skeleton3D, bone: String, size: Vector3, offset: Vector3,
		rotation_deg: Vector3, colour: Color, model_path := "",
		grip := Vector3.ZERO) -> bool:
	if skeleton == null or skeleton.find_bone(bone) == -1:
		push_warning("held.gd: no bone called '%s', so there is nowhere to hang this." % bone)
		return false
	_offset = offset

	var socket := BoneAttachment3D.new()
	socket.name = "HandSocket"
	skeleton.add_child(socket)
	# Set after it is in the tree, or there is no skeleton yet to look the name up in.
	socket.bone_name = bone

	position = offset
	if has_model(model_path):
		# A real model. This node keeps no mesh of its own and works as the socket: the model
		# hangs off it, rotated onto the axis everything else assumes.
		var model: Node3D = (load(model_path) as PackedScene).instantiate()
		model.name = "Model"
		add_child(model)
		# The rotation goes on the MODEL, not on this node. A sword's hitbox is placed along
		# +X of this node, and turning the whole node would carry the hitbox off the blade.
		model.rotation_degrees = rotation_deg
		model.position = grip
		_flatten(model)
	else:
		var box := BoxMesh.new()
		box.size = size
		mesh = box
		rotation_degrees = rotation_deg
		# Flat, like everything else in this world. A placeholder that arrives shinier than the
		# character holding it reads as a bug rather than as a stand-in.
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		material.metallic = 0.0
		material.roughness = 1.0
		material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		material_override = material
	socket.add_child(self)
	# Layer 20 is the overhead water-interaction camera; anything visible has to be on it.
	set_layer_mask_value(20, true)
	_fit.call_deferred(socket)
	return true


## Whether there is a model to hang, as opposed to falling back to the box. Subclasses need to
## know, because a modelled thing and a box sit differently about the origin.
static func has_model(model_path: String) -> bool:
	return model_path != "" and ResourceLoader.exists(model_path)


## Flat toon shading and the water camera's layer, same as every other imported mesh here.
func _flatten(model: Node3D) -> void:
	for node in _descendants(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		mesh_node.set_layer_mask_value(20, true)
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				var flat: BaseMaterial3D = material.duplicate()
				flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				flat.metallic = 0.0
				flat.roughness = 0.55
				flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				mesh_node.set_surface_override_material(surface, flat)


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## Cancels the rig's own unit scale.
##
## A BoneAttachment3D reproduces the bone's pose, and that pose carries whatever units the
## skeleton was authored in - 0.01 on these rigs, because Mixamo works in centimetres. A child
## inherits it, so the first version of this put a 0.70 m blade in the captain's hand measuring
## seven millimetres. Nothing reports it: the node exists, the mesh is right, the size is what
## was asked for, and only the render shows a sword the size of a splinter.
##
## Deferred because a node's global transform is not settled the moment it is added, and the
## scale has to be read after the skeleton has posed it.
func _fit(socket: BoneAttachment3D) -> void:
	if not is_instance_valid(socket):
		return
	var inherited := socket.global_transform.basis.get_scale()
	var factor := 1.0 / maxf(inherited.x, 0.0001)
	scale = Vector3.ONE * factor
	# The offset is a local position, so it is in the same inherited units and needs the same
	# correction - otherwise the thing comes out the right size in the wrong place.
	position = _offset * factor
