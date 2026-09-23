@tool
extends RigidBody3D
## Cargo: a barrel or a crate. Shoveable, and floats if it ends up in the sea.
##
## One script for both, because the only real differences are the shape of the collision and
## whether it rolls. Everything that matters - the buoyancy, the flat shading, the water
## camera's layer - is identical, and two scripts would be two places to fix it.
##
## A RigidBody3D rather than the StaticBody the rocks use, because cargo that cannot be knocked
## over is scenery pretending to be a prop - and because floating needs forces.
##
## The buoyancy is one upward force proportional to how much of it is under the surface, plus
## drag while it is down there - no per-face displacement. The surface itself IS wave-sampled:
## see ocean.gd's surface_y, which repeats the vertex shader's Gerstner sum on the CPU.
## At this camera distance what sells a floating barrel is that it sits at the right depth and
## settles instead of oscillating, and both of those come out of the equilibrium and the damping
## rather than out of the model being right.

enum Kind {BARREL, CRATE}

const MODELS := {
	Kind.BARREL: "res://art/models/props/barrel.glb",
	Kind.CRATE: "res://art/models/props/crate.glb",
}

## What each was installed at, in metres: the barrel stands 1.0 and is about 0.88 across, the
## crate 0.85 and roughly square. The collision is built from these rather than from the mesh -
## see _add_shape for why that is not optional.
const SIZES := {
	Kind.BARREL: Vector3(0.88, 1.0, 0.88),
	Kind.CRATE: Vector3(0.92, 0.85, 0.89),
}

@export var kind: Kind = Kind.BARREL

## Sea level in metres. main.gd sets this from the terrain so the two cannot disagree. The
## default is far below any ground, so a barrel dropped in by hand without one simply never
## floats rather than bobbing on an invisible surface at zero.
@export var water_level := -10000.0:
	set(value):
		water_level = value

## Upward acceleration when fully submerged. Gravity here is 9.8, so 20 balances at a little
## under half submerged, which is where a sealed empty barrel sits.
## The ocean, so the buoyancy can ask where the surface is rather than assume it is flat.
## Optional: without it this falls back to water_level and floats on the average, which is what
## it used to do for everything.
var ocean: Node3D

@export var buoyancy := 20.0
## Water resists. Without these it bobs up and down forever, because nothing takes the energy
## out of the spring the buoyancy makes.
@export var water_drag := 2.6
@export var water_spin_drag := 3.2

var _built := false


## How tall this piece of cargo stands, in metres. The buoyancy needs it to work out how much
## is under the surface.
func height() -> float:
	return (SIZES[kind] as Vector3).y


func _ready() -> void:
	mass = 35.0 if kind == Kind.BARREL else 28.0
	physics_material_override = PhysicsMaterial.new()
	# A barrel on its side should roll; a crate should not. That is the whole behavioural
	# difference between the two, and it is one number.
	physics_material_override.friction = 0.55 if kind == Kind.BARREL else 0.92
	physics_material_override.bounce = 0.05
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var path: String = MODELS.get(kind, "")
	if path == "" or not ResourceLoader.exists(path):
		push_warning("cargo.gd: no model at %s" % path)
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
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


## A primitive the size of the cargo, rather than a hull built from its mesh.
##
## The hull was the first attempt and it was a hundred times too large: the model's scale is
## baked onto the glTF root node, so the mesh's own vertices are still the 98 units Tripo
## exported, and a CollisionShape3D parented to the body inherits none of that scale. The
## barrels came to rest four to five metres above the sand, balanced on collision nobody could
## see. A cylinder sized in metres cannot drift from the model that way, is cheaper, and rolls
## better than a faceted hull besides.
func _add_shape() -> void:
	var size: Vector3 = SIZES[kind]
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	if kind == Kind.BARREL:
		var cylinder := CylinderShape3D.new()
		cylinder.height = size.y
		cylinder.radius = size.x * 0.5
		shape.shape = cylinder
	else:
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	# The model's origin is at its base, so the shape has to be lifted to match.
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
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
	# The surface, not the sea level. These are not the same thing: the ocean's vertex shader
	# lifts the water into waves, so a barrel floating against the flat plane sits at the
	# average height while the water visibly rises and falls around it - which reads as the
	# barrel being pinned rather than as it floating. Asking the ocean where its surface
	# actually is puts the barrel on the wave.
	var surface := water_level
	if ocean != null:
		surface = ocean.surface_y(global_position.x, global_position.z)
	var depth := surface - global_position.y
	if depth <= 0.0:
		linear_damp = 0.0
		angular_damp = 0.2
		return
	var submerged := clampf(depth / maxf(height(), 0.01), 0.0, 1.0)
	apply_central_force(Vector3.UP * buoyancy * mass * submerged)
	linear_damp = water_drag * submerged
	angular_damp = water_spin_drag * submerged


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child in node.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found
