@tool
extends RigidBody3D
## A barrel. Rolls when shoved, and floats if it ends up in the sea.
##
## A RigidBody3D rather than the StaticBody the rocks use, because a barrel that cannot be
## knocked over is scenery pretending to be a prop - and because floating needs forces.
##
## The buoyancy is deliberately crude: one upward force proportional to how much of it is under
## the surface, plus drag while it is down there. No wave sampling and no per-face displacement.
## At this camera distance what sells a floating barrel is that it sits at the right depth and
## settles instead of oscillating, and both of those come out of the equilibrium and the damping
## rather than out of the model being right.

const MODEL := "res://art/models/props/barrel.glb"

## Sea level in metres. main.gd sets this from the terrain so the two cannot disagree. The
## default is far below any ground, so a barrel dropped in by hand without one simply never
## floats rather than bobbing on an invisible surface at zero.
@export var water_level := -10000.0:
	set(value):
		water_level = value
## Authored size, in metres. The model is 1.0 tall and about 0.88 across, and the collision
## cylinder is built from these - see _add_shape.
@export var height := 1.0
@export var radius := 0.44
## Upward acceleration when fully submerged. Gravity here is 9.8, so 20 balances at a little
## under half submerged, which is where a sealed empty barrel sits.
@export var buoyancy := 20.0
## Water resists. Without these it bobs up and down forever, because nothing takes the energy
## out of the spring the buoyancy makes.
@export var water_drag := 2.6
@export var water_spin_drag := 3.2

var _built := false


func _ready() -> void:
	mass = 35.0
	# Barrels on their side should roll rather than skid to a halt.
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.55
	physics_material_override.bounce = 0.05
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	if not ResourceLoader.exists(MODEL):
		push_warning("barrel.gd: no model at %s" % MODEL)
		return
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		model.owner = get_tree().edited_scene_root
	var shaped := false
	for node in _descendants(model):
		if not (node is MeshInstance3D):
			continue
		var mesh_node := node as MeshInstance3D
		# Layer 20 is the ocean's overhead mask, same as the rocks - a barrel bobbing in the
		# shallows should break the water band the way anything else standing in it does.
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
		shaped = true
	if shaped:
		_add_shape()


## A cylinder the size of the barrel, rather than a hull built from its mesh.
##
## The hull was the first attempt and it was a hundred times too large: the model's scale is
## baked onto the glTF root node, so the mesh's own vertices are still the 98 units Tripo
## exported, and a CollisionShape3D parented to the body inherits none of that scale. The
## barrels came to rest four to five metres above the sand, balanced on collision nobody could
## see. A cylinder sized in metres cannot drift from the model that way, is cheaper, and rolls
## better than a faceted hull besides.
func _add_shape() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var cylinder := CylinderShape3D.new()
	cylinder.height = height
	cylinder.radius = radius
	shape.shape = cylinder
	# The model's origin is at its base, so the shape has to be lifted to match.
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)


## Pushes up by however much of the barrel is under the surface.
##
## The force is proportional to the submerged fraction, which is what makes it settle: too deep
## and it pushes harder than gravity, too shallow and it pushes less. The depth it comes to rest
## at is gravity over buoyancy - about 49% here - and the drag is what stops it oscillating
## about that point forever.
func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var depth := water_level - global_position.y
	if depth <= 0.0:
		linear_damp = 0.0
		angular_damp = 0.2
		return
	var submerged := clampf(depth / maxf(height, 0.01), 0.0, 1.0)
	apply_central_force(Vector3.UP * buoyancy * mass * submerged)
	linear_damp = water_drag * submerged
	angular_damp = water_spin_drag * submerged


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
