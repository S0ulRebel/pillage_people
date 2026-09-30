extends SceneTree
## Run: godot --headless --path . --script res://tests/outfit_check.gd
##
## Checks the modular characters - actors/outfit - by measuring rather than looking.
##
## Everything here can be wrong while every render looks nearly right. A coat bound a few
## centimetres off still looks like a coat in the T-pose; it is only mid-swing that the sleeve
## leaves the wrist. A hat on the wrong bone sits perfectly still until he turns his head. A
## retargeted walk that forgets the rig lies face down is obvious, but one that gets the hip
## height wrong just has him wading ankle-deep through the floor. So each is measured:
##
##   - fit space comes out upright, metres, facing +Z, on a rig that lies face down at rest
##     (the grunt) and on one that stands up in metres (the zombie)
##   - stand_at_rest() puts every bone where fit space says it is
##   - a skinned coat lands exactly on its fit in the T-pose, and its cuff stays on the wrist
##     through a swing
##   - a pinned hat keeps its place on the head bone through a swing
##   - the captain's walk, copied onto the zombie, keeps him upright with his feet on the floor
##   - skin tint reaches the body and skin pieces and nothing else
##   - an outfit survives being saved and loaded
##   - every body in art/models/characters has a real skeleton - an un-repaired Tripo export has
##     every bone at the origin, which tools/repair_rig.py exists to fix

const ZOMBIE := "res://art/models/characters/body_zombie.glb"
const GRUNT := "res://art/models/grunt.glb"
const COAT := "res://actors/outfit/placeholders/coat_placeholder.tscn"
const HAT := "res://actors/outfit/placeholders/hat_placeholder.tscn"
const SCRATCH := "user://outfit_check"

var failures := 0
## The last body whose checks all ran. See _run().
var _finished := ""


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_check_bodies_are_rigged()
	for body in [ZOMBIE, GRUNT]:
		await _check_body(body)
		# A script error returns from _check_body early rather than failing a check, so each
		# body also has to have got to the end.
		check(_finished == body, "%s: the checks stopped part-way through" % body.get_file())
	_check_round_trip()
	await _check_workshop()
	print("outfit check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


func _check_bodies_are_rigged() -> void:
	var dir := "res://art/models/characters"
	for file in DirAccess.get_files_at(dir):
		if not (file.begins_with("body_") and file.get_extension() == "glb"):
			continue
		var model := (load(dir.path_join(file)) as PackedScene).instantiate()
		var skeletons := model.find_children("*", "Skeleton3D", true, false)
		check(not skeletons.is_empty(), "%s has no skeleton - it has to be rigged" % file)
		if not skeletons.is_empty():
			var skeleton: Skeleton3D = skeletons[0]
			var spread := 0.0
			for bone in skeleton.get_bone_count():
				spread = maxf(spread, skeleton.get_bone_global_rest(bone).origin.length())
			check(spread > 0.1, "%s has every bone at the origin - run tools/repair_rig.py on it"
					% file)
		model.free()


func _check_body(path: String) -> void:
	var tag := path.get_file().get_basename()
	var model := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var dresser := Dresser.new()
	root.add_child(dresser)
	check(dresser.attach(model), "%s: the dresser could not attach" % tag)
	var skeleton := dresser.skeleton()
	# Taken before anything is worn: after that the skeleton has other meshes under it.
	var body_mesh := model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D

	# Fit space: upright, facing +Z, left hand on +X, in metres.
	var hips := dresser.bone_position("mixamorig_Hips")
	var head := dresser.bone_position("mixamorig_Head")
	var left_hand := dresser.bone_position("mixamorig_LeftHand")
	var foot := dresser.bone_position("mixamorig_LeftFoot")
	var toe := dresser.bone_position("mixamorig_LeftToeBase")
	print("%s: hips %.2f m, head %.2f m, left hand x %.2f, foot %.2f -> toe z %+.2f"
			% [tag, hips.y, head.y, left_hand.x, foot.y, toe.z - foot.z])
	check(hips.y > 0.6 and hips.y < 1.2, "%s: hips at %.2f m - fit space is not metres, or not"
			% [tag, hips.y] + " upright")
	check(head.y > hips.y + 0.4, "%s: the head is not above the hips in fit space" % tag)
	check(left_hand.x > 0.4, "%s: the left hand is at x %.2f - fit space is turned" % [tag,
			left_hand.x])
	check(toe.z > foot.z, "%s: the toes point backwards - fit space faces the wrong way" % tag)
	check(absf(hips.x) < 0.01 and absf(hips.z) < 0.01, "%s: the hips are not over the origin"
			% tag)

	# The T-pose puts every bone where fit space says it is, including on a rig that lies
	# face down at rest.
	dresser.stand_at_rest()
	var worst := 0.0
	for bone in skeleton.get_bone_count():
		var shown := RigSpace.chain(skeleton, model) * skeleton.get_bone_global_pose(bone).origin
		var said := dresser.bone_position(skeleton.get_bone_name(bone))
		worst = maxf(worst, shown.distance_to(said))
	check(worst < 0.001, "%s: the T-pose puts a bone %.1f mm from where fit space says"
			% [tag, worst * 1000.0])

	# Weights copied from the body add up to one and belong to the arm at the wrist.
	var meshes: Array[MeshInstance3D] = [body_mesh]
	var copier := SkinCopy.new(skeleton, meshes, dresser.frame())
	var at_wrist: Array = copier.weights_at(left_hand)
	var sum := 0.0
	for w in (at_wrist[1] as PackedFloat32Array):
		sum += w
	var main_bone := skeleton.get_bone_name((at_wrist[0] as PackedInt32Array)[0])
	check(absf(sum - 1.0) < 0.001, "%s: copied weights add up to %.3f" % [tag, sum])
	check(main_bone.begins_with("mixamorig_Left") and (main_bone.contains("Hand")
			or main_bone.contains("Arm")), "%s: the left wrist copies its weights mostly from %s"
			% [tag, main_bone])

	# A coat and a hat, fitted by hand here so the test does not depend on the workshop's guess.
	var coat := OutfitPiece.for_model(COAT)
	coat.scale = Vector3.ONE * (left_hand.x * 2.0)
	coat.position = Vector3(0.0, left_hand.y - 0.575 * coat.scale.y, 0.0)
	var hat := OutfitPiece.for_model(HAT)
	hat.scale = Vector3.ONE * 0.4
	hat.position = Vector3(head.x, dresser.body_bounds().end.y - 0.05, head.z)
	check(dresser.wear(coat), "%s: the coat would not go on" % tag)
	check(dresser.wear(hat), "%s: the hat would not go on" % tag)
	await process_frame

	# In the T-pose the coat is exactly where its fit puts it.
	var coat_node := dresser.node_for("coat") as MeshInstance3D
	check(coat_node != null, "%s: no coat node after wearing one" % tag)
	if coat_node == null:
		return
	var baked := _skinned(coat_node, skeleton)
	var to_model := RigSpace.chain(coat_node, model)
	var baked_box := _box_of(baked, to_model)
	var expected := coat.fit() * _shape_box(COAT)
	var off := maxf(baked_box.position.distance_to(expected.position),
			baked_box.end.distance_to(expected.end))
	check(off < 0.002, "%s: the coat is %.1f mm off its fit in the T-pose" % [tag, off * 1000.0])

	# The coat vertex nearest the left wrist, and the hat's place on the head, at rest...
	var wrist_bone := skeleton.find_bone("mixamorig_LeftHand")
	var head_bone := skeleton.find_bone("mixamorig_Head")
	var cuff := _nearest_vertex(baked, to_model, left_hand)
	var cuff_gap := (to_model * baked[cuff]).distance_to(left_hand)
	var hat_node := dresser.node_for("hat")
	var hat_on_head := _model_pose(skeleton, model, head_bone).affine_inverse() \
			* _model_of(hat_node, model)

	# ...and mid-swing.
	var player := AnimationPlayer.new()
	model.add_child(player)
	player.add_animation_library("captain", Retarget.library("res://art/models/captain.glb",
			model, skeleton, model))
	player.play("captain/slash")
	player.seek(1.1, true)
	player.pause()
	await process_frame
	await process_frame
	var swung := _skinned(coat_node, skeleton)
	var wrist_now := _model_pose(skeleton, model, wrist_bone).origin
	var cuff_now := (to_model * swung[cuff]).distance_to(wrist_now)
	var hat_now := _model_pose(skeleton, model, head_bone).affine_inverse() \
			* _model_of(hat_node, model)
	var slid := hat_now.origin.distance_to(hat_on_head.origin)
	print("%s: coat %.2f mm off its fit; cuff %.1f cm from the wrist at rest, %.1f mid-swing"
			% [tag, off * 1000.0, cuff_gap * 100.0, cuff_now * 100.0]
			+ " (wrist moved %.2f m); hat slid %.2f mm" % [wrist_now.distance_to(left_hand),
			slid * 1000.0])
	check(wrist_now.distance_to(left_hand) > 0.2, "%s: the slash did not move the wrist" % tag)
	check(absf(cuff_now - cuff_gap) < 0.06, "%s: the cuff was %.1f cm from the wrist at rest and"
			% [tag, cuff_gap * 100.0] + " is %.1f cm from it mid-swing" % (cuff_now * 100.0))
	check(slid < 0.002, "%s: the hat slid %.1f mm on the head bone mid-swing" % [tag,
			slid * 1000.0])

	# The borrowed walk keeps him upright, at his own hip height, feet on the floor.
	player.play("captain/walk")
	var lowest := INF
	var hip_low := INF
	var hip_high := -INF
	var walk := player.get_animation("captain/walk")
	for step in 12:
		player.seek(walk.length * step / 12.0, true)
		var hips_now := _model_pose(skeleton, model, skeleton.find_bone("mixamorig_Hips")).origin
		hip_low = minf(hip_low, hips_now.y)
		hip_high = maxf(hip_high, hips_now.y)
		for side in ["Left", "Right"]:
			var bone := skeleton.find_bone("mixamorig_%sFoot" % side)
			lowest = minf(lowest, _model_pose(skeleton, model, bone).origin.y)
	print("%s walk: hips %.2f..%.2f m (rest %.2f), lowest ankle %.2f m (rest %.2f)"
			% [tag, hip_low, hip_high, hips.y, lowest, foot.y])
	check(hip_low > hips.y * 0.85 and hip_high < hips.y * 1.08,
			"%s: the walk carries the hips between %.2f and %.2f m against %.2f at rest"
			% [tag, hip_low, hip_high, hips.y])
	check(absf(lowest - foot.y) < 0.08, "%s: the lowest ankle in the walk is at %.2f m against"
			% [tag, lowest] + " %.2f at rest - he is floating or wading" % foot.y)

	# Tint: the body and skin pieces take it, a hat does not.
	var colour := Color(0.5, 1.0, 0.5)
	dresser.set_skin_colour(colour)
	var body_material := body_mesh.get_surface_override_material(0) as BaseMaterial3D
	var base: BaseMaterial3D = body_mesh.get_meta("untinted_0")
	check(body_material != null and body_material.albedo_color.is_equal_approx(
			base.albedo_color * colour), "%s: the skin colour did not reach the body" % tag)
	var hat_mesh := hat_node.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var hat_material := hat_mesh.get_surface_override_material(0) as BaseMaterial3D
	check(hat_material == null or not hat_material.albedo_color.is_equal_approx(
			(hat_mesh.get_meta("untinted_0") as BaseMaterial3D).albedo_color * colour),
			"%s: the skin colour tinted the hat" % tag)

	# Taking off leaves nothing behind - no socket on the head bone for each hat ever worn.
	var sockets := skeleton.find_children("*", "BoneAttachment3D", false, false).size()
	dresser.take_off_all()
	await process_frame
	var after := skeleton.find_children("*", "BoneAttachment3D", false, false).size()
	check(after == sockets - 1, "%s: taking the hat off left %d sockets behind" % [tag,
			after - (sockets - 1)])
	check(dresser.pieces().is_empty(), "%s: something is still worn after take_off_all" % tag)
	_finished = path
	dresser.queue_free()
	model.queue_free()
	await process_frame


func _check_round_trip() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var coat := OutfitPiece.for_model(COAT)
	coat.position = Vector3(0.0, 0.8, 0.01)
	coat.fitted = true
	check(ResourceSaver.save(coat, SCRATCH + "/coat.tres") == OK, "could not save a piece")
	coat.take_over_path(SCRATCH + "/coat.tres")
	var outfit := Outfit.new()
	outfit.body = ZOMBIE
	outfit.skin_colour = Color(0.8, 1.0, 0.86)
	outfit.pieces.append(coat)
	check(ResourceSaver.save(outfit, SCRATCH + "/outfit.tres") == OK, "could not save an outfit")
	var loaded := ResourceLoader.load(SCRATCH + "/outfit.tres", "",
			ResourceLoader.CACHE_MODE_IGNORE) as Outfit
	check(loaded != null and loaded.body == ZOMBIE and loaded.pieces.size() == 1,
			"an outfit did not survive saving and loading")
	if loaded != null and loaded.pieces.size() == 1:
		check(loaded.piece_in("coat") != null and loaded.piece_in("coat").position.is_equal_approx(
				coat.position), "the coat's fit did not survive the round trip")
		check(loaded.skin_colour.is_equal_approx(outfit.skin_colour),
				"the skin colour did not survive the round trip")
		# Pointed at, not copied in: a coat re-fitted later has to reach every outfit wearing it.
		check(loaded.pieces[0].resource_path == SCRATCH + "/coat.tres",
				"the outfit carries its own copy of the coat instead of pointing at coat.tres")


func _check_workshop() -> void:
	var shop: Node3D = load("res://actors/outfit/workshop.tscn").instantiate()
	root.add_child(shop)
	await process_frame
	check(not shop._bodies.is_empty(), "the workshop found no bodies")
	check(shop._bodies[0] == ZOMBIE, "the workshop does not start on the zombie")
	var filled := 0
	for slot in OutfitPiece.SLOTS:
		if not (shop._catalogue[slot] as Array).is_empty():
			filled += 1
	check(filled >= 7, "the workshop found pieces for only %d slots" % filled)
	for i in 3:
		shop.randomise()
	# Every chosen piece is actually on.
	for slot in shop._chosen:
		check(shop.dresser.worn(slot) == shop._chosen[slot],
				"the workshop chose a %s that is not being worn" % slot)
	# A guess belongs to its body: the same unplaced hat on the grunt sits lower than on the
	# 1.8 m zombie.
	var hat := OutfitPiece.for_model(HAT)
	shop.choose("hat", hat)
	var on_zombie := hat.position.y
	shop.load_body(GRUNT)
	var on_grunt := hat.position.y
	check(on_grunt < on_zombie - 0.05, "an unplaced hat guessed for the zombie (%.2f m) was not"
			% on_zombie + " guessed again for the grunt (%.2f m)" % on_grunt)
	shop.queue_free()
	await process_frame


func _shape_box(path: String) -> AABB:
	var model := (load(path) as PackedScene).instantiate()
	var box := AABB()
	var started := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		var placed := RigSpace.chain(mesh_node, model) * mesh_node.mesh.get_aabb()
		box = placed if not started else box.merge(placed)
		started = true
	model.free()
	return box


func _model_pose(skeleton: Skeleton3D, model: Node, bone: int) -> Transform3D:
	return RigSpace.chain(skeleton, model) * skeleton.get_bone_global_pose(bone)


func _model_of(node: Node3D, model: Node) -> Transform3D:
	return (model as Node3D).global_transform.affine_inverse() * node.global_transform


## Where a skinned mesh's vertices are right now, in its own space - skinning done here on the
## CPU, the same sum the GPU does: each vertex carried by its bones' current pose times their
## bind. MeshInstance3D.bake_mesh_from_current_skeleton_pose() would do this, but it reads the
## bones back from the renderer, and under --headless the renderer is a dummy with none.
func _skinned(mesh_node: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var carry: Array[Transform3D] = []
	for bind in mesh_node.skin.get_bind_count():
		var bone := mesh_node.skin.get_bind_bone(bind)
		if bone == -1:
			bone = skeleton.find_bone(mesh_node.skin.get_bind_name(bind))
		carry.append(skeleton.get_bone_global_pose(bone) * mesh_node.skin.get_bind_pose(bind))
	var out := PackedVector3Array()
	for surface in mesh_node.mesh.get_surface_count():
		var arrays := mesh_node.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in vertices.size():
			var at := Vector3.ZERO
			for k in 4:
				at += (carry[bones[i * 4 + k]] * vertices[i]) * weights[i * 4 + k]
			out.append(at)
	return out


func _box_of(points: PackedVector3Array, placed: Transform3D) -> AABB:
	var box := AABB(placed * points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(placed * point)
	return box


func _nearest_vertex(points: PackedVector3Array, to_model: Transform3D, point: Vector3) -> int:
	var best := -1
	var best_distance := INF
	for index in points.size():
		var distance := (to_model * points[index]).distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = index
	return best
