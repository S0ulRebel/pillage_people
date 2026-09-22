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
	var ocean := scene.get_node("Ocean") as Ocean
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
			var saved_position := player.global_position
			player.global_position.y = terrain.sea_level() - 1.35
			await process_frame
			check(ocean.material.get_shader_parameter("band_mask_ready"), "Overhead water mask not connected")
			# Descendants, not direct children. This asked for a MeshInstance3D per child, which
			# was right when the body was built from primitives; the captain model arrives as a
			# single Node3D with the meshes under it, so the check had been failing ever since -
			# and the layer it guards was fine the whole time.
			var parts: Array[Node] = player.get_node("Body").find_children("*", "MeshInstance3D", true, false)
			check(not parts.is_empty(), "Player has no visible parts")
			for part in parts:
				check((part as MeshInstance3D).get_layer_mask_value(20),
					"Player part missing overhead water-mask layer")
			var prop := MeshInstance3D.new()
			prop.mesh = BoxMesh.new()
			var capture_marker := WaterBandEmitter.new()
			prop.add_child(capture_marker)
			scene.add_child(prop)
			await process_frame
			check(prop.get_layer_mask_value(20), "Generic prop not added to overhead water mask")
			prop.queue_free()
			player.global_position = saved_position
			check(study.get_child_count() == 11, "Expected nine rocks, one palm and one grass field")
			check(player.global_position.distance_to(study.spawn + Vector3.UP * 2.0) < 0.2, "Player not at study spawn")
			check(study.spawn.y > terrain.sea_level() + 0.75, "Spawn is wet")
			var colliders := study.find_children("*", "CollisionShape3D", true, false)
			check(colliders.size() == 10, "Expected nine rock hulls and a palm trunk")
			# Primitives count now. This asked for a polygon hull, which was right when every
			# shape here came off a generated mesh; the modelled palm carries a cylinder for its
			# trunk, which is cheaper and steadier than a hull of its fronds would ever be.
			for collider in colliders:
				check(collider.shape is ConvexPolygonShape3D or collider.shape is ConcavePolygonShape3D
					or collider.shape is CylinderShape3D or collider.shape is BoxShape3D,
					"Invalid collision shape: " + collider.shape.get_class())
			# The rocks are modelled now rather than generated, so what used to be checked -
			# that a seeded mesh rebuilt identically - no longer exists to check. What still
			# matters is what the rest of the scene depends on: that each water rock straddles
			# the surface, and that it carries the overhead camera's layer so the ocean has a
			# silhouette to draw its band against.
			for i in range(1, 4):
				var water_rock := study.get_node("WaterRock%d" % i)
				check(water_rock.global_position.y < terrain.sea_level(), "Water rock base is not submerged")
				check(water_rock.global_position.y + water_rock.height() > terrain.sea_level(), "Water rock does not cross the surface")
				var water_meshes: Array[Node] = water_rock.find_children("*", "MeshInstance3D", true, false)
				check(not water_meshes.is_empty(), "Water rock has no mesh")
				check((water_meshes[0] as MeshInstance3D).get_layer_mask_value(20), "Water rock missing band-mask layer")
			var rock := study.get_node("LargeOutcrop")
			check(rock.height() > 3.0, "Large outcrop is not the tallest of the shore group")
			var meshes: Array[Node] = rock.find_children("*", "MeshInstance3D", true, false)
			check(not meshes.is_empty(), "Shore rock has no mesh")
			check((meshes[0] as MeshInstance3D).get_layer_mask_value(20), "Shore rock missing band-mask layer")
			# Swapping the variant in the inspector has to replace what is drawn.
			var before_swap: Mesh = (meshes[0] as MeshInstance3D).mesh
			rock.kind = rock.Kind.PILE_TALL
			await process_frame
			await process_frame
			var after: Array[Node] = rock.find_children("*", "MeshInstance3D", true, false)
			check(not after.is_empty() and (after[0] as MeshInstance3D).mesh != before_swap, "Changing kind did not rebuild the rock")
			# The palm is modelled now rather than generated, so there is no seeded mesh to
			# rebuild identically. What the rest of the scene depends on is that it is there,
			# that it stands on the water camera's layer, and that its trunk stops the player.
			var palm := study.get_node("Palm")
			var fronds: Array[Node] = palm.find_children("*", "MeshInstance3D", true, false)
			check(not fronds.is_empty(), "Palm has no mesh")
			check((fronds[0] as MeshInstance3D).get_layer_mask_value(20), "Palm missing band-mask layer")
			check(palm.get_node_or_null("Trunk") != null, "Palm has no trunk collision")
			# The foliage generator is gone; the study plants the modelled grass instead. What
			# is worth checking is that it planted anything - a MultiMesh that silently ends up
			# empty looks exactly like ground with no grass on it.
			var grass: MultiMeshInstance3D = study.get_node("Grass")
			check(grass.multimesh != null and grass.multimesh.instance_count > 0,
				"Shoreline group planted no grass")
			for i in 180:
				await physics_frame
			check(player.is_on_floor(), "Player did not settle on terrain")
			check(player.global_position.distance_to(study.spawn) < 1.0, "Player drifted from study spawn")
			print("player beside study: ", player.global_position, " on_floor=", player.is_on_floor())
	print("coastal smoke: ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(0 if failures == 0 else 1)
