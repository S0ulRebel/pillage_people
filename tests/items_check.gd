extends SceneTree
## Run: godot --headless --path . --script res://tests/items_check.gd
##
## Every held thing is hanging where its HeldItem says it should be.
##
## Mounting moved out of the actors and into .tres resources, and that traded one failure mode
## for another. A weapon that fails to mount is already caught - combat_check and pistol_check
## both stop working, because a null sword swings at nothing. What nothing caught is a weapon
## that mounts SUCCESSFULLY on the wrong bone. A cutlass in the left fist is a working sword
## held in the wrong hand: hits are resolved by range and facing, so every combat test passes
## and the only evidence is a picture.
##
## It also checks the models resolve. A .tres is the one place a path can go stale without the
## compiler noticing - rename a .glb and held.gd quietly falls back to a grey box, which looks
## exactly like a weapon that was always meant to be a placeholder.
##
## Rotation, grip and offset are deliberately NOT checked. Which way a blade's flat faces is
## not recoverable from a number - the reasoning is written out in held_item.gd - and
## `tests/captain_view.gd --spin` is what answers it.

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
	for i in 90:
		await physics_frame
	var captain: CharacterBody3D = scene.get_node("Player")
	var grunt: CharacterBody3D = scene.get_node("Grunts").get_child(0)

	print("%-18s %-14s %-22s %s" % ["held", "item", "bone it hangs from", "model"])
	var wielded := [
		["captain cutlass", captain.cutlass, captain._sword],
		["captain pistol", captain.flintlock, captain._pistol],
		["grunt blade", grunt.blade, grunt._sword],
	]
	for row in wielded:
		var label: String = row[0]
		var item: HeldItem = row[1]
		var held: Node3D = row[2]
		check(item != null, "%s has no HeldItem at all" % label)
		if item == null:
			continue
		check(item.is_real(),
				"%s names neither a model nor a box size, so it would hang an invisible" % label
				+ " nothing off a bone and report success")
		check(held != null,
				"%s never mounted - see the warning from held.gd for which bone it wanted"
				% label)
		var on := ""
		if held != null and held.get_parent() is BoneAttachment3D:
			on = (held.get_parent() as BoneAttachment3D).bone_name
		print("%-18s %-14s %-22s %s" % [label, item.resource_name, on,
				item.model if item.model != "" else "(box)"])
		check(on == item.bone,
				"%s is hanging off '%s' but its item says '%s' - a weapon in the wrong hand"
				% [label, on, item.bone] + " still swings, so nothing else notices")
		# held.gd is documented as "something in a character's hand", and the +X axis it hangs
		# things along is the knuckle axis - so a bone that is not a hand is outside what any
		# of the rotations mean. This does not catch the RIGHT hand versus the left; that is
		# what the pair check below is for.
		check(on.is_empty() or on.contains("Hand"),
				"%s hangs off '%s', which is not a hand - held.gd's +X is the knuckle axis,"
				% [label, on] + " so nothing it does to the rotation means anything there")
		check(item.model == "" or ResourceLoader.exists(item.model),
				"%s points at '%s', which does not exist - held.gd falls back to a grey box"
				% [label, item.model] + " and it looks like a deliberate placeholder")

	# The captain's whole identity: a sword in one hand and a pistol in the other. If these ever
	# name the same bone they are inside each other, which reads as one broken weapon.
	if captain.cutlass != null and captain.flintlock != null:
		check(captain.cutlass.bone != captain.flintlock.bone,
				"the cutlass and the flintlock both hang off '%s' - they are in the same fist"
				% captain.cutlass.bone)

	print("items check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)
