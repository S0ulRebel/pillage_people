extends Node3D
## Scatters the generated rock models across the island.
##
## These are the Tripo rocks in art/models/rocks - about a thousand triangles each, which is
## what makes scattering dozens of them reasonable. The procedural coastal_rock.gd is still
## there and still builds the shoreline group; this is the wider, cheaper scatter that fills
## the ground between landmarks.
##
## Their scale is baked into the files rather than set on import, which only works because none
## of them is rigged - see prepare_game_model.py. The sizes are real metres: the boulder stands
## 2.2 m, the platform 0.9 m and about 3.3 m across.

const MODELS := [
	"res://art/models/rocks/rock_boulder.glb",
	"res://art/models/rocks/rock_cluster.glb",
	"res://art/models/rocks/rock_pile.glb",
	"res://art/models/rocks/rock_pile_tall.glb",
	"res://art/models/rocks/stone_platform.glb",
	"res://art/models/rocks/stone_rock.glb",
	"res://art/models/rocks/stone_rocks.glb",
]

@export var count := 40
## Nothing lands inside this of the player's spawn. Waking up wedged against a boulder is a
## poor first impression, and the camera's spring arm collapses against anything that close.
@export var clear_radius := 7.0
@export var spread := 95.0
## Each one is scaled a little off its authored size. Seven models across forty rocks reads as
## repetition without it - the eye finds the same silhouette immediately.
@export var size_jitter := Vector2(0.65, 1.55)
## How far above the waterline a rock has to sit. Below this they are half-submerged, which the
## shoreline group already covers deliberately and this one would only do by accident.
@export var above_water := 0.6


## Places the rocks and returns how many went down. Needs the terrain for its heights, and the
## spawn point to keep clear of.
func scatter(terrain: Node, around: Vector3, rng: RandomNumberGenerator) -> int:
	var loaded: Array[PackedScene] = []
	for path in MODELS:
		if ResourceLoader.exists(path):
			loaded.append(load(path) as PackedScene)
	if loaded.is_empty():
		push_warning("rocks.gd: no rock models found under art/models/rocks.")
		return 0

	var placed := 0
	for i in count:
		var spot := Vector3.ZERO
		var found := false
		for attempt in 8:
			var angle := rng.randf() * TAU
			var away := sqrt(rng.randf()) * spread
			# sqrt spreads them evenly over the area rather than crowding the middle, which is
			# what a flat random radius does.
			if away < clear_radius:
				continue
			var at := around + Vector3(cos(angle), 0.0, sin(angle)) * away
			var ground: float = terrain.height_at(at.x, at.z)
			if ground > terrain.sea_level() + above_water:
				spot = Vector3(at.x, ground, at.z)
				found = true
				break
		if not found:
			continue
		var rock: Node3D = loaded[rng.randi() % loaded.size()].instantiate()
		rock.name = "Rock%d" % i
		add_child(rock)
		rock.global_position = spot
		rock.rotation.y = rng.randf() * TAU
		rock.scale *= rng.randf_range(size_jitter.x, size_jitter.y)
		_dress(rock)
		placed += 1
	return placed


## Gives an imported rock the same treatment the procedural ones get: flat shading, the water
## camera's layer, and something to walk into.
func _dress(rock: Node3D) -> void:
	for node in _descendants(rock):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		# Layer 20 is sampled by the ocean's overhead silhouette camera. Keeping layer 1 as well
		# means the same mesh supplies both the visible rock and its water-band mask, which is
		# how coastal_rock.gd does it - a second proxy mesh would be one more thing to keep in
		# step with the first.
		mesh_node.layers = 1 | (1 << 19)
		if mesh_node.mesh == null:
			continue
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				var flat: BaseMaterial3D = material.duplicate()
				flat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				flat.metallic = 0.0
				flat.roughness = 1.0
				flat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
				mesh_node.set_surface_override_material(surface, flat)
		# Built from the mesh rather than a box, because these are the shapes the player will be
		# climbing onto and walking around. create_trimesh_collision parents the body to the mesh
		# itself, so whatever scale the rock was given carries through to the shape with it.
		mesh_node.create_trimesh_collision()


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
