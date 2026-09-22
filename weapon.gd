extends MeshInstance3D
## A placeholder blade hung off a hand bone, with a hitbox running along it.
##
## Shared by the captain and the grunts. It was the captain's alone first; it moved here when
## the grunts needed to swing back, because the two fiddly parts of it - which way a blade
## leaves a fist, and cancelling the rig's unit scale - are not worth getting right twice.
##
## The blade runs along the hand bone's +X axis. Measured rather than guessed: on these rigs
## the knuckles run index to ring along -X, so a blade leaving the fist on the index side -
## pommel by the little finger, the way a sword is actually held - points along +X. A real
## mesh authored along some other axis only needs a rotation passed in.

## The overlap volume around the blade. Whoever owns the weapon decides when a hit counts;
## this only reports what the blade is touching.
var hitbox: Area3D

var _offset := Vector3.ZERO


## Builds the blade and parents it to the bone. Returns false if the bone is not there, so a
## body with an unexpected rig ends up unarmed rather than half-built.
func setup(skeleton: Skeleton3D, bone: String, size: Vector3, offset: Vector3,
		rotation_deg: Vector3, colour: Color) -> bool:
	if skeleton == null or skeleton.find_bone(bone) == -1:
		push_warning("weapon.gd: no bone called '%s', so the weapon has nowhere to hang." % bone)
		return false
	_offset = offset

	var mount := BoneAttachment3D.new()
	mount.name = "WeaponMount"
	skeleton.add_child(mount)
	# Set after it is in the tree, or there is no skeleton yet to look the name up in.
	mount.bone_name = bone

	var box := BoxMesh.new()
	box.size = size
	mesh = box
	position = offset
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
	mount.add_child(self)
	# Layer 20 is the overhead water-interaction camera; anything visible has to be on it.
	set_layer_mask_value(20, true)

	hitbox = Area3D.new()
	hitbox.name = "BladeHit"
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	hitbox.add_child(collider)
	# Left monitoring the whole time. Toggling it costs a physics frame before overlaps are
	# reported again, and a strike window is only a dozen frames wide - long enough to lose a
	# hit to that delay. The owner gates whether a hit counts, not whether the area is watching.
	hitbox.monitoring = true
	add_child(hitbox)

	_fit.call_deferred(mount)
	return true


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
func _fit(mount: BoneAttachment3D) -> void:
	if not is_instance_valid(mount):
		return
	var inherited := mount.global_transform.basis.get_scale()
	var factor := 1.0 / maxf(inherited.x, 0.0001)
	scale = Vector3.ONE * factor
	# The offset is a local position, so it is in the same inherited units and needs the same
	# correction - otherwise the blade comes out the right size in the wrong place.
	position = _offset * factor
