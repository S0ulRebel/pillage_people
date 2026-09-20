# Terrain Demo (Godot 4.7)

A generated height map as playable terrain, with a bird's-eye third-person controller.
Open the folder in Godot and press F5, or run:

```
D:\Godot\Godot_v4.7.2-stable_win64.exe --path D:\code\gan\godot\terrain_demo
```

**Touch (iPad / Xogot):** left half = virtual stick (appears where your thumb lands) ·
right half drag = orbit the camera · two-finger pinch = zoom · bottom-right button = jump.

**Keyboard:** WASD move (relative to the camera) · Space jump · Q/E orbit · mouse wheel zoom.

The touch controls show themselves automatically on a touchscreen; on desktop add `--touch`
to see them. Mouse-to-touch emulation is on, so they can be tried with a mouse.

## What is in it

| File | What it does |
|---|---|
| `main.tscn` / `main.gd` | Scene: sun, sky, fog, terrain, player, camera. Picks a spawn point and wires the camera to the player. |
| `terrain.gd` | Reads the height map and builds the mesh (vertex-coloured by altitude) + a `HeightMapShape3D` collider. |
| `player.gd` | `CharacterBody3D`: camera-relative movement, game-feel jump (see below), and a body built from primitives (capsule torso, sphere head, box limbs that swing while walking) so the project needs no imported model. |
| `camera_rig.gd` | `SpringArm3D` chase camera: follows smoothly, orbits, zooms, and will not clip through hills. |
| `touch_controls.gd` | iPad controls, drawn in code (no image assets): virtual stick, jump button, drag-to-orbit, pinch-to-zoom. |
| `terrain/*.r16`, `terrain/*.png` | Height maps from `tools\make_heightmap.py`. |

## Jump feel

Real-world gravity (Godot's 9.8 default) makes a jump feel like the moon: 2.5 m high and
1.4 s in the air. The settings on the Player node instead give **1.68 m in 0.63 s**:

| Setting | Default | What it does |
|---|---|---|
| `jump_height` | 1.6 m | Take-off speed is derived from this: `v = sqrt(2 * g * h)` |
| `rise_gravity` | 26 | Gravity while going up (~2.6x real) |
| `fall_gravity` | 38 | Heavier on the way down - this is what kills the floatiness |
| `short_hop_cut` | 0.58 | Release early and the jump is cut to a 0.43 m hop |
| `coyote_time` | 0.12 s | Still jumpable just after walking off an edge |
| `jump_buffer` | 0.15 s | A press just before landing fires on touchdown |

Measure any change with `Godot.exe --path . -- --jumptest --touch`, which prints the height
and airtime of a held jump and a tapped one.

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
- **Renderer is Mobile**, not Forward+, so it runs on iPad. SSAO is off for the same reason.
- `--screenshot` (as a user arg) renders a frame after the physics settles and quits:
  `Godot.exe --path . -- --screenshot` — it is how this project was checked without the editor.
- `--touchtest` feeds synthetic touch events through the real input path and prints what
  happened, so the iPad controls can be tested from a desktop run:
  `Godot.exe --path . -- --touchtest --touch`
  Expected: the stick moves the player several metres, the drag turns the camera, the jump
  button sets an upward velocity. (`physics_frame` fires *before* `_physics_process`, so a
  check straight after emitting a jump reads the old velocity — wait one more frame.)
