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
| `collision_resolution` | 257 | collision samples per side (match `mesh_resolution` + 1) |

## Tunnels

A tunnel is a node you place in the scene: `Tunnel` extends `Path3D`, so you draw a curve and
set a radius. Everything else follows from those two things.

- The tube is extruded along the curve and **clipped to the ground**: every triangle is cut
  against `terrain height - y`, so the tube ends exactly on the surface and the mouth is that
  intersection curve, whatever the slope. Whole-ring trimming (keep the ring if its centre is
  underground) left a flat end that hung out of a hillside on one side and was buried on the
  other. A curve that dips, surfaces over a ridge and dips again becomes two separate tubes.
- The terrain is cut **against the tube itself**, not against a separate hole shape, so an
  opening is always exactly the tube's cross-section where it breaks the surface - at any
  slope, with nothing to line up by hand. (The first version cut circular holes and tried to
  match craters to them; every mismatch was either a gap to fall through or a dome to walk over.)
- The cut stops short of the tube's ends and a little inside its wall (`cut_margin`), so ground
  and tube always overlap instead of meeting exactly on one surface.
- Collision: the height field gets `NaN` wherever the opening is, the cut rim quads add a
  trimesh for the boundary, and the tube's own trimesh has `backface_collision = true` -
  without that the player falls straight through a tube walked on from the inside.

**Adding one by hand** (this is the intended way, including in Xogot):

1. Add a `Tunnel` node to the scene, set `radius`.
2. Draw its curve: start above ground, dive, run along, come back up.
3. `main.gd` passes every `Tunnel` to the terrain before it generates.

Ramps want about 25 degrees. The player's `floor_max_angle` is raised to 55 degrees because
faceted tube walls throw normals past Godot's 45 degree default and stop you dead halfway out.

**Auto-placed tunnels**: `main.gd` picks two spots near the spawn and builds a curve between
them. Measured with `--tunneltest` over six layouts: five are walkable in, through and out
(one of those ends standing in the mouth rather than clear of it); on the sixth the test
walker never found the entrance, though a render shows a clean opening - a navigation quirk
of the test rather than the geometry. Hand-placed curves are the intended way to use this.

## Is it really physics?

Yes. The terrain is a `StaticBody3D` with a `HeightMapShape3D`; the player is a
`CharacterBody3D` moved with `move_and_slide()`, so Godot (Jolt) resolves the contacts.
Gravity is applied in script, which is how a kinematic body is meant to work. Nothing
snaps the player to the height map - the only direct sampling is choosing the spawn point.

The project uses **Jolt** (`physics/3d/physics_engine`). Tested on 4.7.2: a `NaN` sample in
`HeightMapShape3D.map_data` becomes a hole with no collision — bodies fall straight through,
while normal ground still holds them. The default engine does the same but spams
"Vector3 cannot be normalized", so holes (pits, tunnel mouths) want Jolt.

Keep `collision_resolution` near `mesh_resolution`, or you stand on a surface coarser than
the one you see. Measured against this 1024 height map over 400 m:

| `collision_resolution` | spacing | mean error | worst |
|---|---|---|---|
| 129 | 3.12 m | 0.50 m | 8.06 m |
| **257** (current) | 1.56 m | 0.19 m | 3.68 m |
| 513 | 0.78 m | 0.08 m | 2.39 m |

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
- `--tunneltest` walks the player in at one hole and on to the other, printing depth and
  whether they are still standing; `--probe [--second]` casts rays down a crater and reports
  what they hit; `--probepath` checks there is floor under the whole tunnel; `--holeview`
  renders a crater from above. These exist because every tunnel bug so far looked identical
  from the outside (the player falls forever) and only the probes said why.
- `--touchtest` feeds synthetic touch events through the real input path and prints what
  happened, so the iPad controls can be tested from a desktop run:
  `Godot.exe --path . -- --touchtest --touch`
  Expected: the stick moves the player several metres, the drag turns the camera, the jump
  button sets an upward velocity. (`physics_frame` fires *before* `_physics_process`, so a
  check straight after emitting a jump reads the old velocity — wait one more frame.)
