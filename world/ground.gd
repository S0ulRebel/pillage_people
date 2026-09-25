class_name Ground
extends RefCounted
## Puts a thing on the island, and finds the island to put it on.
##
## This existed five times before it existed once. Every scatterer worked out the same answer
## with its own arithmetic and its own fudge - rocks land exactly on terrain.height_at, palms
## 0.1 m into it, grass tufts 0.05, grunts 0.1 m above, corals 0.06 under - and cannon.gd had
## the only careful version, because a cannon is the only one whose model does not start at its
## own origin. None of them could be used by anything else, so a prop DRAGGED into the scene
## was on nobody's list: it stayed at whatever height the mouse let go of it, floating or
## buried, and the only fix was to nudge it by eye.
##
## It matters more now than it did. The terrain rebuilds under a stamp as the stamp is dragged,
## so the ground moves while things are standing on it - and anything that cannot be asked to
## sit down again has to be placed twice.
##
## Nothing here knows what a rock or a coral is. It takes a node, a height and a sink.

## The Terrain node, looked up from anywhere in the scene.
##
## Walks up the parents asking each for a child called "Terrain", rather than assuming a path:
## a prop is a child of Main in one scene, of a study group in another, and under the Terrain
## itself in a third. The has_method check keeps a node that merely shares the name out of it.
static func find(from: Node) -> Node:
	if from == null:
		return null
	var node := from
	while node != null:
		if node.name == "Terrain" and node.has_method("height_at"):
			return node
		var found := node.get_node_or_null("Terrain")
		if found != null and found.has_method("height_at"):
			return found
		node = node.get_parent()
	return null


## Every mesh under `of`, merged, in that node's own space.
##
## Its `position.y` is the BOTTOM of the model relative to the node, and it is very often not
## zero - an imported model's node sits wherever the exporter left it, which for the cannon is
## sixty metres from its own geometry. That number is the whole reason sit() takes a box.
static func mesh_box(of: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in of.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		# The mesh's own AABB carried up through however many transforms sit between that node
		# and this one. get_aabb() answers in the mesh's space, not the node's.
		var local := of.global_transform.affine_inverse() * mesh_node.global_transform
		var here := local * mesh_node.mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box


## Sits `node` on the ground under it, and says whether it could.
##
## `sink` pushes it in - positive is down, so a palm passes 0.1 and a grunt passes -0.1. `box`
## is the model's bounds in the node's own space; left out, it is measured, and a node with no
## meshes falls back to its own origin, which is what an empty marker wants.
static func sit(node: Node3D, terrain: Node = null, sink := 0.0, box := AABB()) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	var under := terrain if terrain != null else find(node)
	if under == null or not under.has_method("height_at"):
		return false
	var at := node.global_position
	var height: float = under.height_at(at.x, at.z)
	var bottom := box
	if bottom.size == Vector3.ZERO:
		bottom = mesh_box(node)
	node.global_position = Vector3(at.x, height - bottom.position.y - sink, at.z)
	return true


## Tilts `node` to the slope it stands on, keeping the way it is pointing. `weight` is how far
## of the way from upright to the true normal to go; 1.0 lies flat against the hill.
##
## Only the cannon does this today, and only at 0.35 - a gun that lies flat on a slope looks
## like it fell over. Lifted here so that a scatterer can offer it at all: everything else in
## the world is planted bolt upright with a random yaw.
static func lean(node: Node3D, terrain: Node = null, weight := 1.0) -> bool:
	var under := terrain if terrain != null else find(node)
	if node == null or under == null or not under.has_method("_surface_normal"):
		return false
	var at := node.global_position
	var up: Vector3 = under.call("_surface_normal", at.x, at.z)
	if up.length() < 0.01:
		return false
	up = Vector3.UP.slerp(up.normalized(), clampf(weight, 0.0, 1.0))
	var facing := -node.global_transform.basis.z
	var side := up.cross(facing)
	if side.length() < 0.001:
		# Facing straight up or down the slope normal: there is no projection to keep, so the
		# node is left as it was rather than snapped to something arbitrary.
		return false
	side = side.normalized()
	# side.cross(up) is `facing` projected onto the ground plane - the direction to KEEP. A
	# node's forward is -Z, so it goes in the Z column negated.
	#
	# This is where the lifted version was wrong. It put the projection in Z unnegated, which
	# turns the node round to face backwards: measured at 166 degrees of swing on a 78 degree
	# slope, where the claim in the line above is that the facing does not move at all. It had
	# never shown itself because the only caller, the cannon, has follow_slope off by default -
	# so the whole branch was dormant. It is about to stop being dormant: a scatter patch that
	# offers align_to_slope calls this on everything it plants.
	var forward := side.cross(up).normalized()
	node.global_transform.basis = Basis(side, up, -forward).orthonormalized()
	return true


## How steep the ground is here, 0 for flat and 1 for 45 degrees.
##
## The same measure palms and grass already reject on - the larger of the two central
## differences over a metre either way, halved - written once so a patch and a scatterer cannot
## disagree about what counts as too steep. palms refuse above 0.5, grass above 0.55.
static func slope(terrain: Node, x: float, z: float) -> float:
	if terrain == null or not terrain.has_method("height_at"):
		return 0.0
	var dx: float = terrain.height_at(x + 1.0, z) - terrain.height_at(x - 1.0, z)
	var dz: float = terrain.height_at(x, z + 1.0) - terrain.height_at(x, z - 1.0)
	return maxf(absf(dx), absf(dz)) * 0.5


## Metres of water over the ground at this point. Negative above the waterline, so one signed
## number covers both sides of it.
##
## This is the primitive every scatterer's placement rule is really made of, written five
## different ways: rocks want depth <= -0.6, palms -0.8 down to -6.0, grass -3.6 to -9.0, cargo
## afloat wants 1.2 or more, corals 4.0 or more. Said like that they are one band with a sign.
static func depth(terrain: Node, x: float, z: float) -> float:
	if terrain == null or not terrain.has_method("height_at") \
			or not terrain.has_method("sea_level"):
		return 0.0
	return terrain.sea_level() - terrain.height_at(x, z)
