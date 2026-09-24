extends SceneTree
## Run: godot --headless --path . --script res://tests/grass_patch_check.gd
##
## Does a hand-placed GrassPatch grow on the ground as it finally is?
##
## The terrain plants its patches after the stamps have reshaped the ground. Planted before,
## the tufts would stand where the ground used to be - so this one sits on a flatten stamp
## raised 6 m above the island, where that mistake would bury every tuft.

const TERRAIN := preload("res://world/terrain.gd")
const STAMP := preload("res://world/terrain_stamp/terrain_stamp.tscn")
const PATCH := preload("res://props/grass/grass_patch.tscn")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var terrain := StaticBody3D.new()
	terrain.set_script(TERRAIN)
	terrain.raw_path = "res://terrain/island.r16"
	terrain.world_size = 620.0
	terrain.height_scale = 180.0
	var at := Vector3(-60.0, 0.0, 40.0)

	# A plain terrain first, only to read the island's height there.
	var probe := StaticBody3D.new()
	probe.set_script(TERRAIN)
	probe.raw_path = terrain.raw_path
	probe.world_size = terrain.world_size
	probe.height_scale = terrain.height_scale
	root.add_child(probe)
	await process_frame
	var plateau: float = probe.height_at(at.x, at.z) + 6.0

	var stamp := STAMP.instantiate() as TerrainStamp
	stamp.mode = TerrainStamp.Mode.FLATTEN
	stamp.shape = TerrainStamp.Shape.SOFT_RECT
	stamp.length = 20.0
	stamp.width = 20.0
	stamp.edge_softness = 4.0
	stamp.position = Vector3(at.x, plateau, at.z)
	terrain.add_child(stamp)
	var patch := PATCH.instantiate() as GrassPatch
	patch.radius = 3.0
	patch.tufts = 24
	patch.position = Vector3(at.x, plateau, at.z)
	terrain.add_child(patch)
	root.add_child(terrain)
	await process_frame
	terrain.generate()
	await process_frame

	var field := patch.get_node_or_null("Tufts") as MultiMeshInstance3D
	check(field != null and field.multimesh != null, "the patch planted nothing")
	if field == null or field.multimesh == null:
		_finish()
		return
	# Read from the field's own list of planted transforms, in world space. The MultiMesh copy
	# cannot be read back here: --headless runs a dummy renderer that keeps no instance data,
	# and every tuft came back at the origin.
	var planted: Array[Transform3D] = field._placed
	var count := planted.size()
	var worst := 0.0
	var furthest := 0.0
	for placed in planted:
		var tuft := placed.origin
		var ground: float = terrain.height_at(tuft.x, tuft.z)
		# planted a few centimetres into the ground on purpose - see GrassField._clump
		worst = maxf(worst, absf(tuft.y - (ground - 0.05)))
		furthest = maxf(furthest, Vector2(tuft.x - at.x, tuft.z - at.z).length())
	print("grass patch: %d tufts, worst %.3f m off the stamped ground (plateau %.2f), furthest %.2f m out"
			% [count, worst, plateau, furthest])
	check(count == 24, "%d tufts, not the 24 asked for" % count)
	check(worst < 0.02, "tufts are %.3f m off the ground they should stand on" % worst)
	check(furthest <= 3.0 + 0.01, "a tuft is %.2f m out, past the 3 m radius" % furthest)
	_finish()


func _finish() -> void:
	print("grass_patch_check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
