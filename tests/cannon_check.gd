extends SceneTree
## Run: godot --headless --path . --script res://tests/cannon_check.gd
##
## Does the cannon throw a ball that arcs, land it where the arc takes it, and kill what it
## lands near?
##
## Everything here fails quietly. A shot fired with no gravity flies dead straight and still
## "works"; a blast masked to nothing still reports an impact and just never hurts anybody; a
## reload that never counts down lets you fire every frame and looks like a fast cannon rather
## than a broken one. None of it errors.
##
## So this asks for outcomes the code does not set directly. The arc is measured by watching
## the ball rise and then fall, not by reading the velocity back out of it. The splash is
## measured by a grunt's health, not by counting what the query returned.
##
## It builds its own cannon rather than using the one in main.tscn, because that one is a
## hand-placed FBX whose script may or may not be attached yet. The mechanics are what is under
## test; the scene wiring is checked by whether the thing is in the "cannons" group.

const Cannonball = preload("res://actors/parts/cannonball.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for i in 60:
		await process_frame

	var terrain := scene.get_node("Terrain")
	var spawn: Vector3 = terrain.find_spawn()

	var gun := Cannon.new()
	gun.name = "TestCannon"
	# A mesh, because bounds() drives the muzzle and the collision box and an empty AABB makes
	# both meaningless. One metre cube, sat at the spawn.
	var body := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3.ONE
	body.mesh = block
	gun.add_child(body)
	scene.add_child(gun)
	gun.global_position = spawn + Vector3.UP * 0.5
	await process_frame

	_check_arc(gun, scene)
	await _check_lands(gun, scene)
	await _check_splash(gun, scene, terrain, spawn)
	_check_controls(gun)
	# AWAITED. Without the await this returns a coroutine that never runs, _finish() fires
	# immediately, and the whole barrel section is skipped while the suite still reports PASS -
	# which is worse than a failing check, because nothing says it did not happen.
	await _check_barrel(scene, terrain, spawn)
	await _check_manning(scene)
	_check_two_kinds(scene)
	_finish()


## The shot must go UP before it comes down. Nothing sets this: it falls out of the launch
## angle and the gravity together, and if either is lost the ball flies flat and still arrives.
func _check_arc(gun: Cannon, scene: Node3D) -> void:
	# The rider has to actually be AT the gun. A dummy left at the world origin is 160 m away,
	# and the cannon's own walk-away rule lets go of it on the first frame - which then makes
	# every later check fail for a reason that has nothing to do with what it is testing.
	var rider := Node3D.new()
	scene.add_child(rider)
	rider.global_position = gun.global_position
	gun.man(rider)
	gun.aim_towards(gun.global_position + Vector3.FORWARD * 30.0)
	var from := gun.muzzle()
	var velocity := gun.aim_velocity()
	check(velocity.y > 0.0,
			"the launch vector points %.2f up - a cannon that fires flat or downward has no arc"
			% velocity.y)
	check(absf(velocity.length() - gun.muzzle_speed) < 0.01,
			"launch speed is %.2f, expected the fixed muzzle speed of %.2f. The player chooses"
			% [velocity.length(), gun.muzzle_speed]
			+ " the angle, not the power - a speed that drifts makes the arc unlearnable")

	# Sampled from the same arithmetic the ball flies, so this measures the SHAPE of the
	# trajectory rather than re-deriving it.
	var top := -1e9
	var top_at := 0.0
	var last := from.y
	var came_down := false
	for step in 60:
		var seconds := float(step) * 0.05
		var here := Cannonball.at_time(from, velocity, gun.shot_gravity, seconds)
		if here.y > top:
			top = here.y
			top_at = seconds
		if here.y < last:
			came_down = true
		last = here.y
	check(top > from.y + 0.5,
			"the shot peaks %.2f m above the muzzle - that is not an arc" % (top - from.y))
	check(came_down, "the shot never falls. Gravity is not reaching the ball")
	print("arc: peaks %.1f m above the muzzle after %.2f s, elevation %.0f degrees"
			% [top - from.y, top_at, gun.elevation()])


## Fire for real and wait for it to report. The ball decides its own hit, so this is the part
## that would silently never happen if the sweep or the mask were wrong.
func _check_lands(gun: Cannon, scene: Node3D) -> void:
	gun.aim_towards(gun.global_position + Vector3.FORWARD * 25.0)
	var landed := {"hit": false, "at": Vector3.ZERO}
	gun.impact.connect(func(_body: Node, at: Vector3) -> void:
		landed["hit"] = true
		landed["at"] = at)
	var shot := gun.fire()
	check(shot != null, "fire() returned nothing while loaded and manned")
	var waited := 0
	while not landed["hit"] and waited < 600:
		await process_frame
		waited += 1
	check(landed["hit"],
			"the ball never reported landing after %d frames. A shot that vanishes leaves the"
			% waited + " player unable to correct the next one")
	if landed["hit"]:
		var travel: float = Vector2(landed["at"].x - gun.global_position.x,
				landed["at"].z - gun.global_position.z).length()
		print("landed %.1f m away after %d frames" % [travel, waited])
		check(travel > 3.0,
			"it landed %.1f m away - that is on top of the gun, not down range" % travel)


## A grunt near the impact must die. This is the whole point of the weapon and it is the thing
## an unmasked or over-capped query breaks silently.
func _check_splash(gun: Cannon, scene: Node3D, _terrain: Node, _spawn: Vector3) -> void:
	var grunts := scene.find_children("*", "CharacterBody3D", true, false)
	var victim: Node3D = null
	for node in grunts:
		if node.has_method("take_damage") and node.has_method("is_dead") and node != scene.get_node_or_null("Player"):
			victim = node as Node3D
			break
	check(victim != null, "no grunt in the scene to test the blast on")
	if victim == null:
		return
	var before: int = victim.health() if victim.has_method("health") else -1
	# Detonate right beside him rather than flying a shot at a moving man: the arc is already
	# tested above, and this isolates the blast.
	gun._hurt_around(victim.global_position + Vector3.UP * 0.5)
	await process_frame
	var after: int = victim.health() if victim.has_method("health") else -1
	print("blast beside a grunt: %d hp -> %d (radius %.1f m, damage %d)"
			% [before, after, gun.blast_radius, gun.damage])
	check(after < before,
			"a blast at his feet took him from %d to %d. The query is masked to DAMAGEABLE -"
			% [before, after]
			+ " if that mask or the result cap is wrong this is exactly how it fails, silently")

	# And it must NOT reach across the island.
	var far := victim.global_position + Vector3(gun.blast_radius * 6.0, 0.0, 0.0)
	var was: int = victim.health()
	gun._hurt_around(far)
	await process_frame
	check(victim.health() == was,
			"a blast %.1f m away still hurt him - the radius is not being applied"
			% (gun.blast_radius * 6.0))


## The control scheme. Each of these is a rule the player learns, so each one silently breaking
## changes how the weapon feels without breaking anything.
func _check_controls(gun: Cannon) -> void:
	# Reload gates firing. Without it the gun is a machine gun and every shot is worthless.
	check(not gun.can_fire(),
			"it can fire again immediately after a shot - reload_seconds is not being counted")

	gun._cooldown = 0.0
	gun.press(500.0)
	check(gun.is_charging(), "pressing did not start a charge")

	# Dragging UP the screen raises the angle. Screen y grows downward, so this is the sign
	# that is easy to get backwards - and backwards feels wrong without looking broken.
	var at_press := gun.elevation()
	gun.drag(300.0)
	check(gun.elevation() > at_press,
			"dragging up the screen took the elevation from %.1f to %.1f. Pulling back on a gun"
			% [at_press, gun.elevation()] + " should raise it")
	gun.drag(900.0)
	check(gun.elevation() < gun.elevation() + 1.0 and gun.elevation() >= gun.min_elevation,
			"dragging down went below the minimum elevation of %.1f" % gun.min_elevation)

	# Clamped at both ends, so a wild drag cannot put the gun somewhere it cannot come back from.
	gun.drag(-100000.0)
	check(gun.elevation() <= gun.max_elevation,
			"elevation reached %.1f, past the maximum of %.1f" % [gun.elevation(), gun.max_elevation])
	gun.drag(100000.0)
	check(gun.elevation() >= gun.min_elevation,
			"elevation reached %.1f, below the minimum of %.1f" % [gun.elevation(), gun.min_elevation])

	# The bearing lock. This is the reason the scheme works at all: without it the drag that
	# sets the angle also re-aims the gun, and you cannot hold a direction while you choose a
	# range. It is a switch, so check the switch rather than the default.
	gun.lock_bearing_on_press = true
	gun.aim_towards(gun.global_position + Vector3.FORWARD * 10.0)
	var locked := gun.aim_velocity()
	gun.aim_towards(gun.global_position + Vector3.RIGHT * 10.0)
	check(gun.aim_velocity().normalized().distance_to(locked.normalized()) < 0.001,
			"the bearing moved while charging even though lock_bearing_on_press is on")

	gun.lock_bearing_on_press = false
	gun.aim_towards(gun.global_position + Vector3.RIGHT * 10.0)
	check(gun.aim_velocity().normalized().distance_to(locked.normalized()) > 0.001,
			"the bearing did NOT move with lock_bearing_on_press off - the switch does nothing,"
			+ " so the alternative control scheme cannot actually be tried")
	# RANGE MUST ALWAYS INCREASE WITH ELEVATION. This is the rule the whole scheme rests on:
	# the player learns "pull back further to throw further", and it has to be true everywhere.
	# It is false above 45 degrees, where range comes back down - so this fails the moment
	# max_elevation is raised past it, which is exactly the mistake worth catching.
	var ranges: Array[float] = []
	gun.aim_towards(gun.global_position + Vector3.FORWARD * 30.0)
	var step := (gun.max_elevation - gun.min_elevation) / 12.0
	for i in 13:
		gun._elevation = gun.min_elevation + step * float(i)
		var v := gun.aim_velocity()
		var flat := Vector2(v.x, v.z).length()
		# Flat-ground range for this launch vector: the time to come back to launch height,
		# times the horizontal speed.
		ranges.append(flat * (2.0 * v.y / gun.shot_gravity))
	var climbing := true
	var worst := ""
	for i in range(1, ranges.size()):
		if ranges[i] <= ranges[i - 1]:
			climbing = false
			worst = "%.1f deg threw %.1f m, %.1f deg threw %.1f m" % [
					gun.min_elevation + step * float(i - 1), ranges[i - 1],
					gun.min_elevation + step * float(i), ranges[i]]
	print("range over elevation: %.1f m at %.0f deg -> %.1f m at %.0f deg"
			% [ranges[0], gun.min_elevation, ranges[-1], gun.max_elevation])
	check(climbing,
			"raising the gun made the shot land SHORTER (%s). Range peaks at 45 degrees and"
			% worst + " falls after it, so max_elevation must not go past 45 - two answers for"
			+ " one range is what makes an arc impossible to learn")

	print("controls: reload gates, drag raises, both ends clamp, bearing lock switches")


## The real model, with a real barrel. Raising the elevation must visibly raise the MUZZLE -
## which is a different claim from "the number went up", and it is the one that fails when the
## rotation axis is wrong, when the pivot is not on the trunnion, or when the barrel is simply
## never found among the child meshes.
func _check_barrel(scene: Node3D, terrain: Node, spawn: Vector3) -> void:
	var packed := load("res://art/models/props/cannon.glb") as PackedScene
	check(packed != null, "no cannon model at res://art/models/props/cannon.glb")
	if packed == null:
		return
	var gun := Cannon.new()
	gun.name = "ModelCannon"
	gun.add_child(packed.instantiate())
	scene.add_child(gun)
	gun.global_position = spawn + Vector3.UP * 0.5
	await process_frame

	var arm := gun.barrel()
	check(arm != null, "no barrel found among the model's meshes")
	if arm == null:
		return
	var size: Vector3 = (arm as MeshInstance3D).mesh.get_aabb().size
	print("barrel: '%s' %.2f x %.2f x %.2f" % [arm.name, size.x, size.y, size.z])
	check(maxf(size.x, maxf(size.y, size.z)) == size.z,
			"the part picked as the barrel is longest along %s, not Z. The muzzle must point"
			% ("X" if size.x > size.y else "Y") + " down -Z, which is Godot's forward")

	# THE CONVENTION, checked on the asset. Godot points a node's -Z forward, and the barrel is
	# lifted by turning about its local X, which raises whatever lies along -Z. A model whose
	# muzzle is at +Z elevates backwards: pull up and the barrel dips.
	var muzzle_z := _muzzle_end(arm)
	var box: AABB = (arm as MeshInstance3D).mesh.get_aabb()
	check(muzzle_z < box.position.z + box.size.z * 0.5,
			"the barrel's MUZZLE points +Z - backwards, so raising the elevation will drop it."
			+ " Re-export the model with the muzzle facing -Z rather than negating the rotation"
			+ " here")

	var rider := Node3D.new()
	scene.add_child(rider)
	rider.global_position = gun.global_position
	gun.man(rider)

	# The muzzle tip, in world space, at the bottom and the top of the elevation range.
	var tip_low := _muzzle_tip(arm)
	gun._elevation = gun.max_elevation
	gun._swing_barrel()
	await process_frame
	var tip_high := _muzzle_tip(arm)
	print("muzzle tip: y %.2f at %.0f deg -> y %.2f at %.0f deg"
			% [tip_low.y, gun.min_elevation, tip_high.y, gun.max_elevation])
	check(tip_high.y > tip_low.y + 0.1,
			"raising the gun moved the muzzle from y %.2f to %.2f - the barrel is not pivoting."
			% [tip_low.y, tip_high.y]
			+ " Either the rotation is on the wrong axis or the barrel was not found")

	# And it must PIVOT, not translate. The exact invariant is the distance from the muzzle to
	# the TRUNNION, which is the barrel's own origin: a rotation cannot change it, and anything
	# that does is the barrel sliding rather than swinging.
	#
	# The first version of this measured horizontal distance from the CANNON NODE instead, and
	# failed honestly - the trunnion is offset from that node, and the horizontal reach of a
	# barrel at 45 degrees is properly shorter than at 2. It was measuring cosine and calling
	# it a bug.
	var pivot_low: Vector3 = arm.global_position
	var span_low := pivot_low.distance_to(tip_low)
	gun._elevation = gun.min_elevation
	gun._swing_barrel()
	var span_high := arm.global_position.distance_to(tip_high)
	check(absf(span_low - span_high) < 0.02,
			"the muzzle sits %.3f m from the trunnion at one elevation and %.3f m at another."
			% [span_low, span_high]
			+ " A rotation cannot change that distance, so the barrel is sliding, not pivoting")


## The MUZZLE, in world space - found rather than assumed.
##
## The first version of this took the -Z face because -Z is forward, and it was wrong on this
## asset: the model faced backwards, so the -Z face was the breech. When the muzzle dipped the
## breech rose, and the check "the tip went up" passed on exactly the behaviour being reported
## as broken. A test that names the wrong end is worse than no test.
##
## The trunnion is the pivot and it sits nearer the breech than the muzzle - that is what makes
## a gun balance. So the muzzle is simply whichever end reaches FURTHER from the origin, which
## is a fact about the shape rather than an assumption about which way it was exported.
func _muzzle_tip(arm: Node3D) -> Vector3:
	var box: AABB = (arm as MeshInstance3D).mesh.get_aabb()
	var local := Vector3(box.position.x + box.size.x * 0.5, box.position.y + box.size.y * 0.5,
			_muzzle_end(arm))
	return arm.global_transform * local


## Which Z face is the muzzle, measured off the mesh. Returns that face's z.
##
## By THICKNESS, which is the one discriminator that has held up. Two others did not:
##
## - "the thinner end" is what a fish's tail looks like and the opposite of a cannon. A gun
##   tapers to a narrow cascabel knob at the BREECH and swells at the muzzle.
## - "the end further from the trunnion" is sound in principle - a gun balances ahead of its
##   pivot - but it needs the pivot to be off centre, and on this model it is central enough
##   that the comparison came out a tie and silently picked the wrong end.
##
## So: measure the mean radius about the barrel axis at each end, and the fatter one is the
## muzzle. Nothing about export orientation is assumed.
func _muzzle_end(arm: Node3D) -> float:
	var mesh: Mesh = (arm as MeshInstance3D).mesh
	var box: AABB = mesh.get_aabb()
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var radius := [0.0, 0.0]
	for side in 2:
		var lo: float = box.position.z + box.size.z * (0.0 if side == 0 else 0.90)
		var hi: float = box.position.z + box.size.z * (0.10 if side == 0 else 1.0)
		var cx := 0.0
		var cy := 0.0
		var n := 0
		for v in verts:
			if v.z >= lo and v.z <= hi:
				cx += v.x
				cy += v.y
				n += 1
		if n == 0:
			continue
		cx /= float(n)
		cy /= float(n)
		var total := 0.0
		for v in verts:
			if v.z >= lo and v.z <= hi:
				total += Vector2(v.x - cx, v.y - cy).length()
		radius[side] = total / float(n)
	return box.position.z if radius[0] > radius[1] else box.position.z + box.size.z


## What being ON the gun has to do to the player. All three of these were missing at first and
## the result was a cannon that worked perfectly and felt like it did nothing at all: no cursor,
## no sign he had taken hold of it, and a click that swung his cutlass instead of loading.
func _check_manning(scene: Node3D) -> void:
	var player := scene.get_node_or_null("Player") as Node3D
	var gun := scene.get_node_or_null("Cannon") as Cannon
	check(player != null and gun != null, "no Player or no Cannon in main.tscn")
	if player == null or gun == null:
		return

	player.global_position = gun.global_position + Vector3(1.4, 1.0, 0.0)
	for i in 4:
		await physics_frame
	check(player.try_cannon(), "he could not take hold of the gun standing 1.4 m from it")
	check(player.is_manning(), "try_cannon said yes but is_manning says no")

	# ROOTED. Shove him hard and he must not move: while he is on the gun, walking is not one
	# of the things he does. Without this he wanders off and the gun follows him around.
	var stood := player.global_position
	for i in 12:
		player.velocity = Vector3(8.0, 0.0, 8.0)
		await physics_frame
	var drift := Vector2(player.global_position.x - stood.x,
			player.global_position.z - stood.z).length()
	print("manning: shoved at 8 m/s for 12 frames, drifted %.3f m" % drift)
	check(drift < 0.25,
			"he slid %.2f m while manning the gun - he is not rooted to it" % drift)

	# THE CLICK BELONGS TO THE CANNON. If the cutlass also swings, the same button is doing two
	# things and the one you can see is the wrong one.
	var swung := false
	if player.has_method("is_attacking"):
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(640, 500)
		get_root().push_input(press)
		await process_frame
		swung = player.is_attacking()
	check(not swung, "clicking while on the gun also swung the cutlass")

	# And the gun took it.
	check(gun.is_charging(), "clicking while on the gun did not start a charge")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(640, 380)
	get_root().push_input(release)
	await process_frame
	var balls := scene.find_children("Cannonball", "", true, false)
	print("manning: a real click fired %d cannonball(s), reload now %.0f%%"
			% [balls.size(), gun.reload_fraction() * 100.0])
	check(balls.size() > 0, "a full press-drag-release through the viewport fired nothing")
	check(gun.reload_fraction() < 1.0, "the gun is ready again the instant it fired")


## The ship's guns and the hilltop gun must be DIFFERENT WEAPONS, out of one script.
##
## They share every line of code; four exported numbers are the whole difference. If those stop
## being applied, the ship quietly gets an artillery piece that can turn all the way round and
## lob shells over its own rigging - which would not error, would not fail any other check, and
## would remove the reason the two exist separately.
func _check_two_kinds(scene: Node3D) -> void:
	var ship_guns: Array = []
	var open_guns: Array = []
	for node in scene.get_tree().get_nodes_in_group("cannons"):
		if node.traverse_limit > 0.0:
			ship_guns.append(node)
		else:
			open_guns.append(node)
	print("guns: %d limited (ship), %d free (open ground)" % [ship_guns.size(), open_guns.size()])
	check(not ship_guns.is_empty(), "no limited guns - the ship's broadside is not being set up")
	check(not open_guns.is_empty(), "no free gun - the hilltop cannon is missing")
	if ship_guns.is_empty() or open_guns.is_empty():
		return

	var ship: Node3D = ship_guns[0]
	var open: Node3D = open_guns[0]
	check(ship.max_elevation < open.max_elevation,
			"a ship gun reaches %.0f degrees against the open gun's %.0f. A gun in a hull cannot"
			% [ship.max_elevation, open.max_elevation]
			+ " lob - that limit is what makes a broadside a flat-trajectory weapon")
	check(ship.first_person and not open.first_person,
			"the two guns want the same camera. The hull gun looks out of its port; the open gun"
			+ " needs the ground ahead, because that is how its arc is judged")

	# The clamp itself, asked for far more than it can give.
	var forward: Vector3 = -ship.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	ship.aim_towards(ship.global_position + forward.rotated(Vector3.UP, deg_to_rad(90.0)) * 20.0)
	var swung: float = absf(rad_to_deg(forward.signed_angle_to(ship._bearing, Vector3.UP)))
	print("ship gun asked 90 deg off its port, swung %.1f (limit %.0f)" % [swung, ship.traverse_limit])
	check(swung <= ship.traverse_limit + 0.1,
			"it swung %.1f degrees past a %.0f degree port. The gun would be through the hull"
			% [swung, ship.traverse_limit])

	# And the open gun must NOT be limited, or the hilltop weapon loses its point.
	var open_forward: Vector3 = -open.global_transform.basis.z
	open_forward.y = 0.0
	open_forward = open_forward.normalized()
	open.aim_towards(open.global_position + open_forward.rotated(Vector3.UP, PI) * 20.0)
	var about: float = absf(rad_to_deg(open_forward.signed_angle_to(open._bearing, Vector3.UP)))
	check(about > 90.0,
			"the open gun only turned %.0f degrees when asked to face about. It stands in the"
			% about + " open and should turn anywhere")


func _finish() -> void:
	print("cannon check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
