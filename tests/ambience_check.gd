extends SceneTree
## Run: godot --headless --path . --script res://tests/ambience_check.gd
##
## Checks the island's ambience, and checks the assumption underneath it.
##
## The beds are mixed by the captain's height above the water, on the claim that on an island
## low ground IS the shore. That is an assumption about this terrain, not a fact about islands,
## and if it is wrong the surf plays in the middle of the jungle. So the first thing here does
## not test code at all: it samples the terrain, measures every point's real distance to the
## waterline, and reports how tightly that tracks its height. If the two come apart, the mixing
## rule has to become a distance lookup and this will say so.
##
## The rest walks the captain from the sea to the hilltop and prints what each bed is doing, so
## the crossfade can be read as numbers rather than guessed at by ear.

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
	await process_frame
	await process_frame
	var terrain := scene.get_node("Terrain")
	var player := scene.get_node("Player") as CharacterBody3D
	var air := scene.get_node_or_null("Ambience")
	check(air != null, "no Ambience node - _start_ambience did not run")
	if air == null:
		_finish()
		return

	_height_is_shore(terrain)
	_climb(air, terrain, player)
	_anchors(scene, air)
	_finish()


## Is height above the water a fair stand-in for distance to the shore on this island?
##
## Sampled on a grid: for each dry point, walk outward until the ground drops below sea level
## and record how far that took. Then compare against the height. A tight relationship means
## the cheap mixing rule is justified; a loose one means it is not.
func _height_is_shore(terrain: Node) -> void:
	var sea: float = terrain.sea_level()
	var pairs: Array = []
	for gx in 18:
		for gz in 18:
			var x := lerpf(-150.0, 150.0, gx / 17.0)
			var z := lerpf(-150.0, 150.0, gz / 17.0)
			var ground: float = terrain.height_at(x, z)
			if ground <= sea:
				continue
			var above: float = ground - sea
			var reach := _to_water(terrain, x, z, sea)
			if reach < 0.0:
				continue
			pairs.append([above, reach])
	if pairs.size() < 20:
		check(false, "not enough dry land sampled to judge the mixing rule")
		return

	var n := float(pairs.size())
	var mean_h := 0.0
	var mean_d := 0.0
	for p in pairs:
		mean_h += p[0]
		mean_d += p[1]
	mean_h /= n
	mean_d /= n
	var cov := 0.0
	var var_h := 0.0
	var var_d := 0.0
	for p in pairs:
		var dh: float = p[0] - mean_h
		var dd: float = p[1] - mean_d
		cov += dh * dd
		var_h += dh * dh
		var_d += dd * dd
	var r: float = cov / maxf(sqrt(var_h * var_d), 0.0001)
	print("shore proxy: %d points, height vs distance-to-water r = %.2f" % [pairs.size(), r])

	# What the surf band actually covers on the ground. This is the number that matters: the bed
	# is full below 3.5 m and gone by 34 m, so those heights need to mean "on the sand" and
	# "well inland" rather than two arbitrary points.
	var on_sand: Array = []
	var inland: Array = []
	for p in pairs:
		if p[0] <= 3.5:
			on_sand.append(p[1])
		elif p[0] >= 34.0:
			inland.append(p[1])
	if not on_sand.is_empty():
		print("  at or below 3.5 m (surf full):  %d points, %.0f m from water on average"
				% [on_sand.size(), _mean(on_sand)])
	if not inland.is_empty():
		print("  at or above 34 m (surf gone):   %d points, %.0f m from water on average"
				% [inland.size(), _mean(inland)])
	check(r > 0.45, "height does not track distance to the shore (r = %.2f); the surf bed needs"
			% r + " a real distance lookup rather than a height band")
	if not on_sand.is_empty() and not inland.is_empty():
		check(_mean(inland) > _mean(on_sand) * 2.0,
				"the surf band does not separate beach from inland")


## How far from here to water, walking outward. -1 when there is none within range.
func _to_water(terrain: Node, x: float, z: float, sea: float) -> float:
	var nearest := -1.0
	for step in 12:
		var bearing := step / 12.0 * TAU
		var dx := cos(bearing)
		var dz := sin(bearing)
		var walked := 4.0
		while walked < 220.0:
			if terrain.height_at(x + dx * walked, z + dz * walked) < sea:
				if nearest < 0.0 or walked < nearest:
					nearest = walked
				break
			walked += 4.0
	return nearest


## Walks the captain up from the water and prints every bed's weight on the way.
func _climb(air: Node, terrain: Node, player: CharacterBody3D) -> void:
	var sea: float = terrain.sea_level()
	print("bed mix by height above the water:")
	var names: Array = air.BEDS.keys()
	var header := "  %6s" % "height"
	for n in names:
		header += "  %10s" % n
	print(header)
	var seen := {}
	for n in names:
		seen[n] = []
	for above in [0.0, 2.0, 5.0, 10.0, 18.0, 30.0, 45.0]:
		player.global_position = Vector3(player.global_position.x, sea + above,
				player.global_position.z)
		var line := "  %5.0fm" % above
		for n in names:
			var weight: float = air._weight_for(n as String)
			seen[n].append(weight)
			line += "  %9.2f" % weight
		print(line)

	# The point of three beds is that they do not all do the same thing. Each has to actually
	# move across the island, and the surf and the jungle have to move in opposite directions -
	# otherwise this is one bed with extra steps.
	for n in names:
		var values: Array = seen[n]
		var low: float = values.min()
		var high: float = values.max()
		check(high - low > 0.35, "the %s bed barely changes across the island (%.2f to %.2f)"
				% [n, low, high])
	var surf: Array = seen["surf"]
	var jungle: Array = seen["jungle"]
	check(surf[0] > surf[surf.size() - 1], "surf does not fall away as the captain climbs")
	check(jungle[0] < jungle[jungle.size() - 1], "the jungle does not come up as he climbs")


## The occasionals are placed against real objects, so there have to be some.
func _anchors(scene: Node3D, air: Node) -> void:
	var palms := 0
	var cargo := 0
	for child in scene.get_children():
		var named := String((child as Node).name)
		if named.begins_with("Palm"):
			palms += 1
		elif named.begins_with("Cargo"):
			cargo += 1
	print("anchors: %d palms, %d cargo in the scene; ambience holds %d and %d"
			% [palms, cargo, air._palms.size(), air._cargo.size()])
	# The whole reason _start_ambience runs last. Wired alongside the music it would see an
	# empty scene, hold nothing, and never play a rustle - silently, and looking correct.
	check(air._palms.size() == palms, "ambience missed the palms - is it still running before"
			+ " _plant_palms?")
	check(air._cargo.size() == cargo, "ambience missed the cargo")

	# A wave has to break somewhere the sea actually is. Fired from the spawn, which is near
	# the shore, this should find water; the returned point must be at the waterline.
	var found := 0
	for attempt in 30:
		var at: Variant = air._point_for("sea")
		if at != null:
			found += 1
	print("sea bearings: %d of 30 attempts found water from the spawn" % found)


func _mean(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxf(float(values.size()), 1.0)


func _finish() -> void:
	print("ambience check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
