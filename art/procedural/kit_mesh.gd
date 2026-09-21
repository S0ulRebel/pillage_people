@tool
extends RefCounted
## Input faces use counter-clockwise outward normals; Godot receives clockwise vertices.

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.00000001:
		return
	st.set_color(colour.srgb_to_linear())
	st.set_normal(normal.normalized())
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	triangle(st, a, b, c, colour)
	triangle(st, a, c, d, colour)


static func material(leaves: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.vertex_color_use_as_albedo = true
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.roughness = 1.0
	if leaves:
		result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result


static func instance(parent: Node3D, mesh: ArrayMesh, mat: Material, label: String) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	result.mesh = mesh
	result.material_override = mat
	if mat is StandardMaterial3D and mat.cull_mode == BaseMaterial3D.CULL_DISABLED:
		result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	parent.add_child(result)
	return result


static func clear_generated(parent: Node3D) -> Node3D:
	# Only remove our generated root: authored children must survive inspector edits.
	for child in parent.get_children():
		if child.has_meta("coastal_generated"):
			parent.remove_child(child)
			child.queue_free()
	var root := Node3D.new()
	root.name = "Generated"
	root.set_meta("coastal_generated", true)
	parent.add_child(root)
	return root
