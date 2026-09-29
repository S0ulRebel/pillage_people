class_name Retarget
extends RefCounted
## Copies animation clips from one rig onto another with the same bone names.
##
## The zombie arrives from Tripo with a skeleton and no clips at all, and every body after it
## will too. The captain's twelve Mixamo clips are the library everyone borrows from.
##
## Matching names is not enough on its own, because the rigs disagree about everything else.
## The captain's skeleton works in centimetres and lies face down at rest, and his hip track
## is what stands him up; the zombie's stands up in metres with nothing to undo. Copying the
## captain's hip rotation onto the zombie as it stands would lay the zombie flat. So nothing is
## copied as written. For each bone, each frame, what is taken is how far it has turned from
## its T-pose, seen in the upright space both rigs share (rig_space.gd); that same turn is then
## applied to the other rig's own T-pose. Different bone axes, units and rest orientations all
## cancel, and an arm held 10 degrees lower in one T-pose stays 10 degrees lower in every
## frame, which is what "the same motion on a different body" means.
##
## The hips are the one bone that also moves. They travel in proportion: a body with longer
## legs covers more ground in the same stride, and a shorter one bobs less.

## Frames sampled per second of clip. Mixamo's are authored at 30.
const RATE := 30.0


## A library of every clip in `source` (a model path) remade for `target`, whose skeleton is
## `skeleton`. `player_root` is the node the target's AnimationPlayer resolves paths from.
static func library(source: String, target: Node3D, skeleton: Skeleton3D,
		player_root: Node) -> AnimationLibrary:
	var out := AnimationLibrary.new()
	var scene := load(source) as PackedScene
	if scene == null:
		push_error("Retarget: '%s' is not a model." % source)
		return out
	var model := scene.instantiate() as Node3D
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skeletons.is_empty():
		push_error("Retarget: '%s' has no clips or no skeleton to copy from." % source)
		model.free()
		return out
	var from := _Rig.new(skeletons[0], model)
	var to := _Rig.new(skeleton, target)
	var path := String(player_root.get_path_to(skeleton))
	var player := players[0] as AnimationPlayer
	for clip in player.get_animation_list():
		out.add_animation(clip, _copy(player.get_animation(clip), from, to, path))
	model.free()
	return out


static func _copy(clip: Animation, from: _Rig, to: _Rig, skeleton_path: String) -> Animation:
	# Which bone each of the source's rotation tracks turns, and which track moves the hips.
	var turned := {}
	var moved := {}
	for track in clip.get_track_count():
		var bone := from.skeleton.find_bone(
				clip.track_get_path(track).get_concatenated_subnames())
		if bone == -1:
			continue
		match clip.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				turned[bone] = track
			Animation.TYPE_POSITION_3D:
				if from.skeleton.get_bone_parent(bone) == -1:
					moved[bone] = track
	var out := Animation.new()
	out.length = clip.length
	out.loop_mode = clip.loop_mode
	# One output track per target bone that the source animates.
	var rotation_track := {}
	for bone in turned:
		var target_bone := to.skeleton.find_bone(from.skeleton.get_bone_name(bone))
		if target_bone == -1:
			continue
		var track := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(track, "%s:%s" % [skeleton_path,
				to.skeleton.get_bone_name(target_bone)])
		rotation_track[target_bone] = track
	var position_track := {}
	for bone in moved:
		var target_bone := to.skeleton.find_bone(from.skeleton.get_bone_name(bone))
		if target_bone == -1 or to.skeleton.get_bone_parent(target_bone) != -1:
			continue
		var track := out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(track, "%s:%s" % [skeleton_path,
				to.skeleton.get_bone_name(target_bone)])
		position_track[target_bone] = [bone, track]

	var frames := maxi(1, ceili(clip.length * RATE))
	for frame in frames + 1:
		var time := minf(frame / RATE, clip.length)
		var source_globals := from.pose_at(clip, turned, time)
		var target_globals := {}
		for bone in to.order:
			var parent := to.skeleton.get_bone_parent(bone)
			var match_bone := from.skeleton.find_bone(to.skeleton.get_bone_name(bone))
			var global: Quaternion
			if match_bone != -1:
				# The turn from the source's upright T-pose, applied to this rig's own.
				var delta: Quaternion = from.up * (source_globals[match_bone] as Quaternion) \
						* from.rest_global[match_bone].inverse() * from.fit.inverse()
				global = to.up.inverse() * delta * to.fit * to.rest_global[bone]
			else:
				var above: Quaternion = target_globals[parent] if parent != -1 \
						else Quaternion.IDENTITY
				global = above * to.rest_local[bone]
			target_globals[bone] = global
			if rotation_track.has(bone):
				var local := global if parent == -1 \
						else (target_globals[parent] as Quaternion).inverse() * global
				out.rotation_track_insert_key(rotation_track[bone], time, local.normalized())
		for bone in position_track:
			var pair: Array = position_track[bone]
			var source_bone: int = pair[0]
			var shown := from.model_from_skeleton * from.hips_at(clip, moved, source_bone, time)
			var travel := (shown - from.fit_hips) * (to.fit_hips.y / from.fit_hips.y)
			var here := to.model_from_skeleton.affine_inverse() * (to.fit_hips + travel)
			out.position_track_insert_key(pair[1], time, here)
	return out


## One rig, measured once: its bones in parent-first order, their rests, and how its skeleton
## space sits in its model and in fit space.
class _Rig:
	var skeleton: Skeleton3D
	var order := PackedInt32Array()
	## Rotations only - the scale in these transforms is the rig's units, not a turn.
	var rest_global := {}
	var rest_local := {}
	## Skeleton space to model space, and skeleton space to fit space.
	var model_from_skeleton: Transform3D
	var up: Quaternion
	var fit: Quaternion
	## Where the hips stand when the rig is upright in its T-pose, in metres - turned into fit
	## space's axes but not moved, so this is where they really are rather than centred.
	var fit_hips := Vector3.ZERO

	func _init(bones: Skeleton3D, model: Node) -> void:
		skeleton = bones
		model_from_skeleton = RigSpace.chain(bones, model)
		var frame := RigSpace.frame_of(bones, model)
		up = model_from_skeleton.basis.get_rotation_quaternion()
		fit = frame.basis.get_rotation_quaternion()
		var placed := {}
		while order.size() < bones.get_bone_count():
			for bone in bones.get_bone_count():
				var parent := bones.get_bone_parent(bone)
				if placed.has(bone) or (parent != -1 and not placed.has(parent)):
					continue
				placed[bone] = true
				order.append(bone)
		for bone in order:
			rest_local[bone] = bones.get_bone_rest(bone).basis.get_rotation_quaternion()
			rest_global[bone] = bones.get_bone_global_rest(bone).basis.get_rotation_quaternion()
		var hips := RigSpace.find_any(bones, ["mixamorig_Hips", "Hips"])
		fit_hips = frame.basis * bones.get_bone_global_rest(maxi(hips, 0)).origin

	## Every bone's global rotation at `time`, from the clip where it has a track and from the
	## rest pose where it does not.
	func pose_at(clip: Animation, turned: Dictionary, time: float) -> Dictionary:
		var globals := {}
		for bone in order:
			var local: Quaternion = rest_local[bone]
			if turned.has(bone):
				local = clip.rotation_track_interpolate(turned[bone], time)
			var parent := skeleton.get_bone_parent(bone)
			globals[bone] = local if parent == -1 else (globals[parent] as Quaternion) * local
		return globals

	## Where a root bone is at `time`, in skeleton space.
	func hips_at(clip: Animation, moved: Dictionary, bone: int, time: float) -> Vector3:
		if moved.has(bone):
			return clip.position_track_interpolate(moved[bone], time)
		return skeleton.get_bone_rest(bone).origin
