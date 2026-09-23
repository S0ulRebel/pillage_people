class_name Shark
extends Node3D
## A shark circling offshore. Scenery: it swims, it does not fight.
##
## Scenery ON PURPOSE, for now. Making it a threat means health, damage, an attack and a reason
## the captain can fight or flee it, and that is combat work. This way the thing is in the water
## and looking right while that decision is still open - and when it is made, what moves here
## does not have to change.
##
##
## WHY THERE IS NO SWIM CLIP
##
## The model arrived rigged with no animations, and the right answer was not to make one.
##
## A fish swimming is a travelling sine wave down its spine: each bone yaws a little later than
## the one in front of it, and the tail - last in the chain and furthest from the nose - swings
## hardest. That is four lines of maths, and it beats a baked clip on this particular animal,
## because the amplitude and the rate can follow how fast it is actually going. Cruising,
## turning and a hard burst all fall out of the same code, where clips would need three
## animations and a blend between them that never quite works.
##
## Mixamo was never an option either way: it retargets humanoid rigs, and this is a fish.
##
## The ocean's own surface is the same idea - see the Gerstner sum in ocean.gdshader - so this
## is vocabulary the project already speaks.

## The spine, nose to tail. Named in order because the WAVE needs the order: bone n lags bone
## n-1, and getting the sequence wrong gives a fish that shivers instead of one that swims.
## DOUBLE underscore: the glTF calls these `tripo::Spine_0`, and Godot's importer replaces the
## colons because a bone name cannot contain one. The same reason the captain's are
## `mixamorig_LeftHand` rather than `mixamorig:LeftHand`. Read off the imported skeleton, not
## off the file.
const CHAIN := ["tripo__Spine_0", "tripo__Spine_1", "tripo__Spine_2",
		"tripo__Tail_0", "tripo__Tail_1"]

@export_file("*.glb") var model_path := "res://art/models/shark.glb"
## Metres it runs each way from the middle of its beat, along the shore.
@export var patrol := 40.0
## Metres per second. A cruising shark, not a charging one.
@export var speed := 2.2
## How much of him shows above the water, in metres. The dorsal fin and nothing else - that
## is the whole picture from the beach.
##
## Stated as "how much shows" rather than "how deep", and the depth worked out from the model's
## own height, because the model's origin is at its BELLY. A depth of 0.55 sounded like a shark
## just under the surface and actually left the top of him 1.80 m into the air.
@export var fin_above := 0.25
## Degrees the LAST bone in the chain swings. Everything ahead of it gets less, in proportion
## to how far up the chain it is - a tail moves, a nose barely does.
@export_range(0.0, 45.0) var sway_degrees := 26.0
## Beats per second of the tail.
@export var beat := 1.1
## How far the wave travels along the body, in radians across the whole chain. This is what
## makes it a travelling wave rather than the whole fish wagging in unison.
@export var wave_spread := 1.0
## How quickly it comes round at the end of a run. Low, because a shark turning on the spot
## reads as a toy on a string - it should take a few body lengths about it.
@export var turn_rate := 1.1

## The ocean, so it can sit in the real surface instead of on a flat plane - the same sampler
## the floating cargo uses. Set by whoever builds the scene.
var ocean: Node3D

var _bones: Array[int] = []
## The axis each bone must turn about to yaw the body, in that bone's own rest frame.
##
## Not Vector3.UP. A bone's local axes are whatever the rigger left them as, and on this model
## turning about local UP moved the tail 1 cm VERTICALLY - the fish flexed like a dolphin, and
## barely. The model's own up, carried into each bone's frame, is the one that yaws.
var _axis: Array[Vector3] = []
## Metres from the belly to the top of the dorsal fin, measured off the mesh.
var _height := 0.0
## The rest pose of each spine bone, as a QUATERNION, captured once.
##
## Once, and as a quaternion, both deliberately. The first version read the current pose back
## each frame, decomposed it to Euler angles and rebuilt it - so every frame it was re-reading
## its own output. Euler round-tripping an arbitrary rotation is lossy, the error compounded,
## and within a second the whole chain had tumbled: the shark swam nose-up, standing on its
## tail. Composing from a stored rest cannot drift, because nothing is ever read back.
var _rest: Array[Quaternion] = []
var _skeleton: Skeleton3D
var _model: Node3D
var _centre := Vector3.ZERO
## Unit vector along the shore, and which way down it he is currently going.
var _along := Vector3.FORWARD
var _heading := Vector3.FORWARD
var _travel := 0.0
var _direction := 1.0
var _clock := 0.0


## Puts one in the water off `centre`, working the shore along `along`. Returns false if the
## model could not be loaded, so a missing file leaves no half-built shark behind.
func setup(centre: Vector3, along: Vector3) -> bool:
	_centre = centre
	_along = along.normalized() if along.length() > 0.01 else Vector3.FORWARD
	_heading = _along
	if not ResourceLoader.exists(model_path):
		push_warning("shark.gd: no model at %s" % model_path)
		return false
	_model = (load(model_path) as PackedScene).instantiate()
	add_child(_model)
	for node in _model.find_children("*", "Skeleton3D", true, false):
		_skeleton = node as Skeleton3D
		break
	if _skeleton == null:
		push_warning("shark.gd: the model has no skeleton, so it cannot swim.")
		return false
	# Looked up once. find_bone walks the whole list by name, and doing that for five bones
	# every frame for a piece of scenery is work nobody asked for.
	for name_ in CHAIN:
		var index := _skeleton.find_bone(name_)
		if index == -1:
			continue
		_bones.append(index)
		_rest.append(_skeleton.get_bone_pose_rotation(index))
		var upright := _skeleton.get_bone_global_rest(index).basis.inverse() * Vector3.UP
		_axis.append(upright.normalized() if upright.length() > 0.001 else Vector3.UP)
	if _bones.is_empty():
		push_warning("shark.gd: none of the spine bones were found - the rig changed.")
		return false
	# How tall he is, so fin_above can be turned into a depth. Measured rather than guessed:
	# the origin is at the belly on this model and could be anywhere on the next one.
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var box: AABB = mesh_node.mesh.get_aabb()
			_height = maxf(_height, box.position.y + box.size.y)
	_flatten()
	return true


func bones_found() -> int:
	return _bones.size()


func _process(delta: float) -> void:
	_clock += delta
	# Up and down the shore rather than round in a circle. A circle seen from the beach reads
	# as a semicircle out, a semicircle back, which is the one thing it should not look like.
	_travel += speed * _direction * delta
	if absf(_travel) >= patrol:
		_travel = clampf(_travel, -patrol, patrol)
		_direction = -_direction
	var here := _centre + _along * _travel
	# The real surface, not the sea level. Those are different by the wave height, and a shark
	# pinned to the mean reads as a shark on rails - see the same note in cargo.gd.
	var surface := here.y
	if ocean != null and ocean.has_method("surface_y"):
		surface = ocean.surface_y(here.x, here.z)
	# Sunk by his own height, less whatever should show. The dorsal breaks the water; the rest
	# of him does not.
	here.y = surface - maxf(_height - fin_above, 0.0)
	global_position = here
	# Eased rather than snapped, so the turn at the end of a run is a turn and not a flip.
	_heading = _heading.lerp(_along * _direction, clampf(turn_rate * delta, 0.0, 1.0))
	if _heading.length() > 0.01:
		# look_at, not a hand-built yaw. Godot points a node's -Z at the target, and after the
		# Blender pass this model's nose IS -Z - working that out by hand is how it ended up
		# swimming sideways.
		look_at(global_position + _heading.normalized(), Vector3.UP)
	_swim()


## The travelling wave. Bone i lags bone i-1, and swings harder the further down the body it
## sits, which is what separates a fish from a windscreen wiper.
func _swim() -> void:
	if _skeleton == null:
		return
	var last := maxf(float(_bones.size() - 1), 1.0)
	for i in _bones.size():
		var along := float(i) / last
		var phase := _clock * TAU * beat - along * wave_spread
		var swing := deg_to_rad(sway_degrees) * along * sin(phase)
		# Rest, then the swing on top. Never the other way round, and never from the pose that
		# is already there - see the note on _rest.
		_skeleton.set_bone_pose_rotation(_bones[i],
				_rest[i] * Quaternion(_axis[i], swing))


## Flat shading, like everything else in this world. A shark that arrives with a specular
## highlight reads as a different game from the one it is swimming in.
func _flatten() -> void:
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material is StandardMaterial3D:
				var flat := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				flat.metallic = 0.0
				flat.roughness = 1.0
				flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				mesh_node.set_surface_override_material(surface, flat)
		# Layer 20 is the ocean's overhead mask: something in the water belongs on it.
		mesh_node.set_layer_mask_value(20, true)
