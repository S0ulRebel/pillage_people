# Procedural coastal kit

The default scene places six seeded faceted rocks and one curved palm on a dry,
gentle coastal patch. The player starts beside the group and faces it. The rock
and palm scenes can also be dragged into another scene and edited in the inspector.
Generated children regenerate on load; authored children survive parameter edits.

The kit uses the supplied SurfaceTool geometry, linear vertex colours, flat face
normals and toon StandardMaterial3D materials. Rocks have convex collision; the
palm has static trimesh trunk collision and two-sided fronds/shadows. Growth-ring
ledges and trunk end caps close the supplied trunk's segment gaps.

Placement uses the local height gradient for shoreline orientation, checks a grid
across the whole group and spawn for dry ground, slopes below 0.32 and ground at
least two metres from any tunnel opening, and requires water within 36 metres. If
no patch passes, the original spawn remains in use.
It uses local RNGs and never changes terrain generation or the ground.

## Run

From the repository root with Godot 4.7 on PATH:

```sh
godot --path .
godot --path . -- --noassets
godot --path . -- --assetview
```

`--assetview` hides HUD/touch controls, selects a separate camera, writes
`user://coastal_study.png`, and quits. It reports an error and exits with status 1
if the study is unavailable or the display is headless. Existing tunnel/test
arguments retain priority: a generated tunnel (`--tunnel`) and the tunnel test
modes disable the study, because the generated tunnel is planned around the spawn
before the study would move it. A tunnel authored under Terrain does not disable
it: the study runs beside it, keeps clear of its openings, and moves along the
coast if one opens on the beach it would otherwise pick; the player starts at the
study, not at the tunnel. `--noassets` never builds the study, tunnel or not.
`--noscene` retains its existing meaning of ignoring authored tunnels.

## Validation

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . --quit-after 120
godot --headless --path . --script res://tests/coastal_smoke.gd
godot --headless --path . --script res://tests/coastal_smoke.gd -- --noassets
godot --headless --path . --script res://tests/coastal_smoke.gd -- --authoredfixture
godot --headless --path . -- --tunnel --probepath
git diff --check
```

Verified on Godot 4.7.2: script import, scene startup, six rocks and one palm,
collision resources, deterministic rebuilds, inspector refresh, authored-child
preservation, dry coastal spawn, player settling on the floor, original noassets
spawn, and authored tunnel registration/collision. With an authored tunnel opening
on the default beach (`--authoredfixture`, and the smoke run's own check), the
study still runs and nothing it places stands in the opening. The generated-tunnel probe
finds floor at every sample along the path. Desktop Mobile/Vulkan rendering on an
RTX 4060 Ti produced [the study screenshot](../../docs/coastal_study.png).
iPad/Xogot hardware has not been tested.

The initial kit was built from the supplied code and written art direction before
the reference sheets were available. The subsequently supplied images and approved
style direction are now indexed in [art/references](../references/README.md).

## Preserved shading limitation

The existing terrain shader is unshaded and computes its own light bands. It does
not receive real-time cast shadows, so shadows from this kit are visible on lit
assets but not on the sand. Shadow casting is enabled on rocks, trunk and both
sides of the foliage. Terrain/ocean shaders and materials are untouched; adding
terrain shadow reception requires a separate shading change. The screenshot also
retains the current scene's shadow-map artifacts on some asset faces.
