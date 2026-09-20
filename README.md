# Terrain Demo (Godot 4.7)

A generated height map as playable terrain, with a bird's-eye third-person controller.
Open the folder in Godot and press F5, or run:

```
D:\Godot\Godot_v4.7.2-stable_win64.exe --path D:\code\gan\godot\terrain_demo
```

**Controls:** WASD move (relative to the camera) · Space jump · Q/E orbit · mouse wheel zoom.

## What is in it

| File | What it does |
|---|---|
| `main.tscn` / `main.gd` | Scene: sun, sky, fog, terrain, player, camera. Picks a spawn point and wires the camera to the player. |
| `terrain.gd` | Reads the height map and builds the mesh (vertex-coloured by altitude) + a `HeightMapShape3D` collider. |
| `player.gd` | `CharacterBody3D`: camera-relative movement, gravity, jump, and a body built from primitives (capsule torso, sphere head, box limbs that swing while walking) so the project needs no imported model. |
| `camera_rig.gd` | `SpringArm3D` chase camera: follows smoothly, orbits, zooms, and will not clip through hills. |
| `terrain/*.r16`, `terrain/*.png` | Height maps from `tools\make_heightmap.py`. |

## Swapping in another terrain

Generate one (`make_terrain.bat` in `D:\code\gan`), copy the `.r16` into `terrain\`, and set
`raw_path` on the Terrain node — or just overwrite `terrain/heightmap.r16`.

Useful settings on the Terrain node:

| Setting | Default | Meaning |
|---|---|---|
| `world_size` | 400 | metres across |
| `height_scale` | 60 | metres from lowest to highest |
| `mesh_resolution` | 256 | quads per side (visual detail) |
| `collision_resolution` | 129 | collision samples per side |

## Notes worth keeping

- **Use the `.r16`, not the PNG.** Godot's image loader converts a 16-bit PNG down to 8-bit,
  which shows up as terracing. `terrain.gd` reads the raw file directly and only falls back
  to the PNG.
- **Vertex colours are linear.** sRGB values need `srgb_to_linear()`, or the terrain looks
  washed out.
- **Triangle winding**: `[0,1,2] / [0,2,3]` over the grid. The other order faces away and
  backface culling makes the terrain look like scattered fragments.
- `--screenshot` (as a user arg) renders a frame after the physics settles and quits:
  `Godot.exe --path . -- --screenshot` — it is how this project was checked without the editor.
