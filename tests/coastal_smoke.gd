extends SceneTree
## Run: godot --headless --path . --script res://tests/coastal_smoke.gd [-- --noassets|--authoredfixture]
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	var authored := "--authoredfixture" in OS.get_cmdline_user_args()
	if authored:
		var tunnel := Tunnel.new()
		tunnel.name = "AuthoredFixture"
		tunnel.curve = Curve3D.new()
		for p in [Vector3(135, 23, -90), Vector3(125, 10, -90), Vector3(105, 10, -90), Vector3(95, 25, -90)]:
			tunnel.curve.add_point(p)
		scene.add_child(tunnel)
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var terrain := scene.get_node("Terrain")
	var player := scene.get_node("Player") as CharacterBody3D
	var study := scene.get_node_or_null("CoastalStudy")
	if authored or "--noassets" in OS.get_cmdline_user_args():
		check(study == null, "Study must be absent in noassets/authored runs")
		if authored:
			check(terrain.tunnels.size() == 1, "Authored tunnel must be registered")
			check(not scene.get_node("AuthoredFixture").find_children("*", "CollisionShape3D", true, false).is_empty(), "Authored tunnel collision missing")
		else:
			seed(20260920)
			check(player.global_position.distance_to(terrain.find_spawn() + Vector3.UP * 2.0) < 0.2, "Original spawn changed")
	else:
		check(study != null and study.valid, "No valid shoreline study")
		if study != null and study.valid:
			check(study.get_child_count() == 13, "Expected nine rocks, one palm and three foliage groups")
			check(player.global_position.distance_to(study.spawn + Vector3.UP * 2.0) < 0.2, "Player not at study spawn")
			check(study.spawn.y > terrain.sea_level() + 0.75, "Spawn is wet")
			var colliders := study.find_children("*", "CollisionShape3D", true, false)
			check(colliders.size() == 10, "Expected nine rock hulls and a trunk trimesh")
			for collider in colliders:
				check(collider.shape is ConvexPolygonShape3D or collider.shape is ConcavePolygonShape3D, "Invalid collision shape")
			for i in range(1, 4):
				var water_rock := study.get_node("WaterRock%d" % i)
				check(water_rock.global_position.y < terrain.sea_level(), "Water rock base is not submerged")
				check(water_rock.global_position.y + water_rock.dimensions.y > terrain.sea_level(), "Water rock does not cross the surface")
				check(water_rock.get_node("Generated/Stone").get_layer_mask_value(20), "Water rock missing band-mask layer")
			var rock := study.get_node("LargeOutcrop")
			var original: PackedVector3Array = rock.get_node("Generated/Stone").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			rock.rebuild()
			var rebuilt: PackedVector3Array = rock.get_node("Generated/Stone").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check(original == rebuilt, "Rock rebuild not deterministic")
			var authored_child := Node3D.new()
			rock.add_child(authored_child)
			rock.dimensions = Vector3(6, 4, 4)
			await process_frame
			check(is_instance_valid(authored_child) and authored_child.get_parent() == rock, "Rebuild removed authored child")
			check(rock.get_child_count() == 2, "Generated children leaked on inspector rebuild")
			var changed: PackedVector3Array = rock.get_node("Generated/Stone").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check(changed != original, "Inspector edit did not rebuild rock")
			var palm := study.get_node("Palm")
			var leaves: PackedVector3Array = palm.get_node("Generated/Fronds").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			palm.rebuild()
			check(leaves == palm.get_node("Generated/Fronds").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "Palm not deterministic")
			var foliage := study.get_node("BroadLeaves")
			var foliage_vertices: PackedVector3Array = foliage.get_node("Generated/Leaves").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			foliage.rebuild()
			check(foliage_vertices == foliage.get_node("Generated/Leaves").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "Foliage not deterministic")
			for i in 180:
				await physics_frame
			check(player.is_on_floor(), "Player did not settle on terrain")
			check(player.global_position.distance_to(study.spawn) < 1.0, "Player drifted from study spawn")
			print("player beside study: ", player.global_position, " on_floor=", player.is_on_floor())
	print("coastal smoke: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
