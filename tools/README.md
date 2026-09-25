# Asset tools

The scripts that turn a generated or downloaded asset into something this game can load.

They live here rather than in the generation workspace because the game depends on them.
`.gitignore` drops Godot's `.import` files, so a model's orientation, pivot and scale have to
be baked into the `.glb` itself — and the tool that bakes them is therefore part of the game,
not a convenience that happens to exist on one machine. Half the comments in `props/` and
`world/` name one of these by path.

## What is here

| Script | What it does |
| --- | --- |
| `reorient_model.py` | Rotate, centre, scale and decimate a GLB, with the transforms **applied**. |
| `prepare_game_model.py` | Scale a generated GLB to a real height and copy it into `art/models/`. |
| `simplify_mesh.py` | Cut a vertex-coloured GLB down to a game-ready face count. |
| `retexture_model.py` | Swap the texture inside a GLB, leaving the mesh, rig and pivot alone. |
| `merge_animations.py` | Bake a character plus a folder of Mixamo clips into one GLB. |
| `trim_clip.py` | Cut, pin, rename and drop clips on a rigged GLB. |
| `inspect_clips.py` | Report what a rigged GLB's clips actually do — seams, length, motion. |
| `make_loop.py` | Cut a generated music track into a seamless loop and encode it. |
| `make_bed.py` | Pick the best ambience take and cut it into a seamless loop. Imports `make_loop`. |
| `encode_ogg.py` | Encode a WAV to OGG Vorbis through Blender's libvorbis. |

## Running them

The Blender ones — `reorient_model.py`, `prepare_game_model.py`, `merge_animations.py`,
`trim_clip.py`, `inspect_clips.py` — need Blender's own Python, not a system one:

    "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" --background --factory-startup ^
        --python tools/reorient_model.py -- <in.glb> <out.glb> --rotate 0 0 -90 --centre --scale 0.35

`--factory-startup` matters. Blender's FBX and glTF importers **overwrite the scene frame rate**
from whatever the file they read declares, and a merge done at the wrong rate silently rescales
every clip already in the file. `merge_animations.py` pins the rate at both ends because of it.

`retexture_model.py` needs nothing at all - it is a binary patch on the glTF container,
stdlib only, on whatever Python is to hand. Use it when a model is right but its texture is
not: re-exporting to carry one new image puts the mesh, the rig, the pivot and the import
scale back in play, and those are usually the settled part.

`simplify_mesh.py`, `make_loop.py` and `make_bed.py` are ordinary Python and want packages —
`fast_simplification`, `scipy` and `trimesh` for the first, `av` for the second, `numpy` for the
third. `make_bed.py` does `from make_loop import ...`, so the two have to stay siblings; that
import is the reason `make_loop.py` could not simply be left behind in the other workspace.

## What is deliberately not here

The generation side — the ComfyUI graphs, the LoRA training, the dataset builders, the model
downloads — stays in the separate workspace. It is a much larger pile, it needs a GPU and a
ComfyUI install, and nothing in this repository calls it.

The ship kit has its own `ship_kit/tools/` - `build_kit.py` builds the hull modules and
`validate_kit.py` checks them. Run those from `ship_kit/`, not from the repository root: they
resolve their output relative to the script, so `ship_kit/canonical/` is where the geometry
lands. That directory is generated and is not committed.

`art/references/ship-kit/START_HERE.md` also names `render_kit.py`, `package_kit.py`,
`build_handoff.py`, `build_floors.py` and `build_rounded_stern.py`. The first two are previews
and a distributable ZIP, which the game does not need. The last three do not exist anywhere on
disk - the doc is stale about them.

The line is import-shaped rather than a matter of taste: a tool belongs here when it runs
against an asset on its own. `make_heightmap.py` is the one the game names that stayed behind,
because it does `from comfy import ...` and would not run without that workspace.

## The thing these exist to prevent

A wrong orientation, pivot or scale must be fixed in the **file**, once, not compensated for by
the code that loads it. A compensation does not remove the error, it moves it — and every later
consumer of that model inherits it. This has cost real time more than once:

- the shark arrived nose-up and was "fixed" by aiming the node, which left it swimming sideways
- its origin sat at its **belly**, so a depth measured from it put the whole animal 1.80 m into
  the air
- the fish had the same belly origin, and the swim shader rolls a fish about its own origin, so
  it swung the body sideways instead of rolling it
- a scale left in a `.import` file is dropped by `.gitignore`, and a fresh clone got a captain
  at 53% height and a one-metre shark

`tests/import_check.gd` guards the last of those. The rest are what `--rotate`, `--centre` and
`--scale` are for.
