class_name ImportCheck
extends SceneTree
## Run: godot --headless --path . --script res://tests/import_check.gd
##
## Checks the import settings that cannot be set anywhere else.
##
## A rigged model's scale has to be set in its `.import` file. It cannot be set on the node,
## because scaling above a Skeleton3D breaks Godot's skinning and tears the mesh apart - see the
## long note at the top of captain.gd. So `nodes/root_scale` is the only place it can live, and
## `.import` files were gitignored: a fresh clone regenerated them with the defaults, and the
## captain came out at 53% of his height with his jump broken, silently, looking merely odd.
##
## This is here because a comment warning about it was not enough. The files that carry
## non-default settings are committed now, and this fails loudly if any is ever lost.
##
## An unrigged model should not need an entry at all - tools/reorient_model.py --scale bakes the
## size into the .glb, where git keeps it. fish_blue is listed the other way round, pinned at the
## default, so a scale cannot quietly move back into a file a fresh clone will not receive.

## file -> the settings it must carry, and why.
const REQUIRED := {
	"res://art/models/captain.glb.import": {
		"nodes/root_scale": "1.9",
		# The jump clip pins the hips to a constant value, and Godot's importer strips constant
		# tracks by default - which would snap them to the bone rest halfway through the jump.
		"animation/remove_immutable_tracks": "false",
	},
	"res://art/models/grunt.glb.import": {
		"nodes/root_scale": "1.794",
	},
	# Rigged, so this one has no choice either - the swim is written onto its spine bones.
	"res://art/models/shark.glb.import": {
		"nodes/root_scale": "4.0",
	},
	# Not rigged, so this COULD have been baked into the .glb with reorient_model.py --scale.
	# It is here instead because the arch is already placed by hand in main.tscn, and re-baking
	# a placed asset is a chance to move it.
	"res://art/models/rocks/rock_arch.glb.import": {
		"nodes/root_scale": "8.0",
	},
	# The opposite case, and the one to copy: the fish carries its 0.35 m length in the .glb, so
	# the .import holds nothing and stays ignored. Pinned at the default here so that nobody
	# "fixes" the size by putting a scale back into a file a fresh clone will not get.
	"res://art/models/fish_blue.glb.import": {
		"nodes/root_scale": "1.0",
	},
}

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in REQUIRED:
		var settings: Dictionary = REQUIRED[path]
		if not FileAccess.file_exists(path):
			_fail("%s is missing entirely" % path)
			continue
		var text := FileAccess.get_file_as_string(path)
		for key in settings:
			var want: String = settings[key]
			var found := ""
			for line in text.split("\n"):
				if line.begins_with(key + "="):
					found = line.substr(key.length() + 1).strip_edges()
					break
			if found == want:
				print("  ok   %-42s %s=%s" % [path.get_file(), key, want])
			else:
				_fail("%s has %s=%s, needs %s. A fresh clone regenerates .import with the"
						% [path.get_file(), key, found if found != "" else "<missing>", want]
						+ " defaults - re-set it in the Import dock and commit the file.")
	print("import check: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(1 if failures > 0 else 0)


func _fail(message: String) -> void:
	failures += 1
	push_error(message)
