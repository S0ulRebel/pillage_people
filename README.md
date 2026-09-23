# Pillage People (Godot 4.7)

A stylised pirate game on a generated island. A captain with a cutlass, grunts who fight
back, a shore to swim off and a waterfall to walk through.

Open the folder in Godot and press F5, or run:

```
D:\Godot\Godot_v4.7.2-stable_win64.exe --path D:\code\pillage_people
```

See [CONVENTIONS.md](CONVENTIONS.md) for where files go and how behaviour is split up. Read
that before adding anything.

**Keyboard:** WASD move (relative to the camera) · Space jump · left click swing · middle-drag
turn and tilt the camera · mouse wheel zoom · Q/E turn · R/F tilt.

**Touch (iPad):** left half = virtual stick (appears where your thumb lands) · right half drag
= turn and tilt · two-finger pinch = zoom · bottom-right button = jump. These appear only on a
real touchscreen; on desktop add `--touch` to see them.

## What is in it

Laid out by thing rather than by file type — see [CONVENTIONS.md](CONVENTIONS.md).

| Where | What it does |
|---|---|
| `main.tscn` / `main.gd` | The scene, and the orchestrator: builds the island, scatters the props, spawns the grunts, and wires everything to the audio. |
| `actors/captain/` | The captain. `CharacterBody3D`: camera-relative movement, jumping, swimming, swinging a cutlass, taking hits, dying. |
| `actors/grunt/` | A grunt. Idles, chases, swings back, staggers, dies. 3 hp against the captain's 5. |
| `actors/parts/` | Shared by both: the blade (hung off a hand bone with a hitbox along it) and the hit spark. |
| `props/` | Placeable prefabs, one folder each: rocks, cargo (barrels and crates, which float), palms, grass, the waterfall. |
| `world/terrain.*` | Reads the height map and builds the mesh + a `HeightMapShape3D` collider. |
| `world/ocean.*` | The sea: waves, depth colour, shoreline foam, and an overhead camera that lets objects push a band through the surface. |
| `world/tunnel.gd` | Draw a curve, get a tunnel bored through the terrain. Opt-in with `--tunnel`. |
| `ui/` | HUD, the floating health bars over the grunts, the touch controls, and the `SpringArm3D` chase camera. |
| `systems/` | Sound: `sfx.gd`, `music.gd`, `ambience.gd`. See below. |
| `art/` | Data only — imported models, generated audio, reference images. Nothing here is loaded as code. |
| `terrain/*.r16` | Height maps from `tools\make_heightmap.py` in `D:\code\gan`. |

## The fight

Left click swings. The blade carries a hitbox and a hit lands when it overlaps a grunt; the
grunts do **not** use blade overlap, because their Mixamo swing sweeps *across* the body — the
tip travels 0.37–0.51 m to their left and barely 0.3 m forward, so it can never reach the
person in front of them. They use a range and facing check instead (`attack_range` 1.00 m,
`hit_reach` 1.35 m).

A hit gives a spark, a knockback impulse and a moment of stagger. Knockback is a **single
impulse**, not a per-frame push: feeding a push back into `move_toward` every frame sent the
captain 2.31 m from a hit the grunt took for 0.43. Being hit does not cancel the captain's
swing — when it did, he lost every fight (6 swings, 1 landed, dead). It still cancels the
grunt's.

When the captain dies the whole scene reloads after `restart_delay`, rather than putting the
pieces back by hand — a reload cannot forget one.

## Sound

Three layers, all generated locally with Stable Audio 3 (see `tools/` in `D:\code\gan`).

- **Effects** (`art/audio/sfx`) — swoosh, clang, flesh, death, steps, splash, dig. Fired from
  signals the characters emit, so neither the captain nor the grunts know a sound system
  exists.
- **Ambience** (`art/audio/beds`, `art/audio/ambience`) — surf, wind and jungle run as
  continuous loops whose levels follow the captain's height above the water; gulls, waves,
  fronds and creaking cargo fire as single calls from real objects. The waterfall and pond are
  pinned where they stand.
- **Music** (`art/audio/beach.ogg`) — a 103 s seamless loop.

Two things worth knowing. Every clip is **peak-levelled to the same loudness**, which is right
for effects and wrong for everything else, so the levels in `ambience.gd` put the real
difference back by hand. And a clip must hold **one** sound: the first batch shipped a swoosh
containing four swooshes and a footstep containing five footfalls, because the scorer rewarded
silence around the sound and a long clip has more of it.

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

Measure any change with `--jumptest`, which prints the height and airtime of a held jump and a
tapped one. Mixamo's clips describe motion, not game needs: its "Jumping" is 2.20 s of
approach, hop and recovery against 0.64 s of actual airtime, so the jump uses a 0.34 s slice
of "Jumping Up" with the hips pinned.

Wading becomes swimming past `swim_depth` (1.3 m, about chest height).

## The island

`terrain/heightmap.r16` is a **stylised** map: wide flat plains with a few isolated flat-topped
mesas, about 78% of it near-level. Deliberate — the first map was ridges edge to edge, which
left nowhere to build.

Everything on it is placed from `main.gd`: 40 rocks, 14 palms, 70 grass patches (about 1400
tufts in one MultiMesh), 5 barrels and 6 crates ashore with more afloat, and 5 grunts.

Grass grows in **patches, not a scatter** — the patch centres are chosen first and each is
filled with tufts crowded toward its middle, with the rocks handed in as extra centres so
grass grows against a boulder the way it does in life. An even scatter reads as a texture
rather than as plants, however many you use.

Swapping the map means re-drawing any tunnel curve, since the curve is world-space geometry.
Useful settings on the Terrain node:

| Setting | Default | Meaning |
|---|---|---|
| `world_size` | 400 | metres across |
| `height_scale` | 60 | metres from lowest to highest |
| `mesh_resolution` | 256 | quads per side (visual detail) |
| `collision_resolution` | 257 | collision samples per side (match `mesh_resolution` + 1) |

## Tunnels

A tunnel is a node you place in the scene: `Tunnel` extends `Path3D`, so you draw a curve and
set a radius. Everything else follows. Opt in with `--tunnel`; the island slice is about
terrain and water, and a generated tunnel punches a hole through the shoreline that reads as a
bug.

- The tube is extruded along the curve and **clipped to the ground**: every triangle is cut
  against `terrain height - y`, so the tube ends exactly on the surface and the mouth is that
  intersection curve, whatever the slope. Whole-ring trimming left a flat end hanging out of
  one side of a hill and buried in the other.
- The terrain is cut **against the tube itself**, not against a separate hole shape, so an
  opening is always exactly the tube's cross-section where it breaks the surface. (The first
  version cut circular holes and tried to match craters to them; every mismatch was either a
  gap to fall through or a dome to walk over.)
- The cut stops short of the tube's ends and a little inside its wall (`cut_margin`), so ground
  and tube overlap instead of meeting exactly on one surface.
- Collision: the height field gets `NaN` wherever the opening is, the cut rim quads add a
  trimesh, and the tube's own trimesh has `backface_collision = true` — without it you fall
  straight through a tube walked on from the inside.

Keep the middle of the curve 10–20 m below the surface and the ends within about 25 degrees of
the ground for a walkable ramp. The captain's `floor_max_angle` is raised to 55 degrees because
faceted tube walls throw normals past Godot's 45 degree default and stop you dead halfway out.

## Is it really physics?

Yes. The terrain is a `StaticBody3D` with a `HeightMapShape3D`; the captain is a
`CharacterBody3D` moved with `move_and_slide()`, so Godot (Jolt) resolves the contacts. Gravity
is applied in script, which is how a kinematic body is meant to work. Nothing snaps him to the
height map — the only direct sampling is choosing the spawn point.

The project uses **Jolt**. A `NaN` sample in `HeightMapShape3D.map_data` becomes a hole with no
collision; the default engine does the same but spams "Vector3 cannot be normalized", so holes
want Jolt.

Keep `collision_resolution` near `mesh_resolution`, or you stand on a surface coarser than the
one you see. Measured against this 1024 height map over 400 m:

| `collision_resolution` | spacing | mean error | worst |
|---|---|---|---|
| 129 | 3.12 m | 0.50 m | 8.06 m |
| **257** (current) | 1.56 m | 0.19 m | 3.68 m |
| 513 | 0.78 m | 0.08 m | 2.39 m |

## Tests

```
Godot.exe --headless --path . --script res://tests/coastal_smoke.gd
Godot.exe --headless --path . --script res://tests/ambience_check.gd
Godot.exe --headless --path . -- --deathtest
```

`coastal_smoke` checks the island builds and the captain stands on it. `ambience_check` walks
him from the sea to the hilltop and prints what every sound bed is doing, and checks the
assumption underneath the mix — that on this island low ground *is* the shore (ground below
3.5 m is 12 m from water on average, ground above 34 m is 74 m). `--deathtest` kills him and
checks the island comes back.

`tests/captain_view.gd` renders him from four angles, and `tests/outline_probe.gd` renders the
same view with one suspect disabled at a time. Both exist because the bugs they found — a
cutlass rolled a quarter turn in his fist, a white line around everything at distance — could
only be seen, not reasoned about.

## Working on two machines (PC + iPad)

Godot writes a `.import` file next to every asset, and the contents differ per machine — so
with both a PC and an iPad in one repo, every pull collides on files nobody edited. The height
maps and the screenshots are data rather than textures, so `terrain/` and `docs/` each carry a
`.gdignore`. `*.import` is gitignored.

If Working Copy says a pull was aborted because of uncommitted changes, check what they are
first: if they are only `.import`/`.godot` files, discard them and pull again.

## Notes worth keeping

- **Use the `.r16`, not the PNG.** Godot's image loader converts a 16-bit PNG down to 8-bit,
  which shows up as terracing.
- **Vertex colours are linear.** sRGB values need `srgb_to_linear()`, or the terrain looks
  washed out.
- **Renderer is Mobile**, not Forward+, so it runs on iPad. SSAO is off for the same reason.
- **Never scale a rigged model on its root.** Skinning cancels the root against the inverse
  bind matrices and the mesh distorts. Use `nodes/root_scale` in the `.import` — which is
  gitignored, so any such setting has to be written down.
- **Screen-space effects must not be sharper than a pixel.** The shoreline foam's
  anti-aliasing width was capped, so two hundred metres out — where one pixel spans metres of
  beach — the band resolved as a hard white line around every waterline. Take `fwidth` *before*
  any `discard`, where it is still defined.
- **`CPUParticles3D` arrives already emitting**, so a one-shot burst spends its cycle before
  you have configured it. Call `restart()`.
- **Letting the captain die frees the whole scene.** `main.gd` reloads it `restart_delay`
  after his `died` signal — measured, the scene and every node in it are gone at exactly
  3.40 s. A test holding a reference to him, a grunt or the scene past that point is holding
  a freed object, and touching one raises an error that aborts the test function. Since that
  function is the only thing that calls `quit()`, the run does not fail — it hangs, with no
  window and no output. Either keep the damage below fatal, or do what `--deathtest` does and
  carry state across the reload in a `static var`, which lives on the script rather than the
  node.
- **MultiMesh instance transforms are in the node's own space**, and headless reads them back
  as identity with a zero AABB. Grass positioned in world coordinates on a rotated parent ended
  up hundreds of metres away in the sky.
- `--screenshot` renders a frame after the physics settles and quits. `--jumptest`,
  `--swimtest`, `--touchtest`, `--deathtest`, `--tunneltest`, `--probe`, `--probepath`,
  `--holeview` and `--overview` each print or render one thing. They exist because most bugs
  here looked identical from the outside and only a measurement said why.
