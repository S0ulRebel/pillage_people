# Pillage People (Godot 4.7)

A stylised pirate game on a generated island. A captain with a cutlass, grunts who fight
back, a shore to swim off and a waterfall to walk through.

Open the folder in Godot and press F5, or run:

```
D:\Godot\Godot_v4.7.2-stable_win64.exe --path D:\code\pillage_people
```

See [CONVENTIONS.md](CONVENTIONS.md) for where files go and how behaviour is split up. Read
that before adding anything.

**Keyboard:** WASD move (relative to the camera) · Space jump · **1** cutlass, **2** flintlock
· left click uses whichever is in his hand · **hold right click** to guard · **Z** spyglass,
wheel zooms while it is up · middle-drag turn and tilt the camera · mouse wheel zoom · Q/E
turn · E beside the ship climbs onto the deck · E at the helm drives (W/S way, A/D turn, E lets go).

R and F used to tilt the camera. The middle-button drag does that better, and R is where a
player looks for a sidearm.

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
| `props/` | Placeable prefabs, one folder each: rocks, cargo (barrels and crates, which float), palms, grass, the waterfall, and the double-deck ship moored off the beach. |
| `world/terrain.*` | Reads the height map and builds the mesh + a `HeightMapShape3D` collider. |
| `world/ocean.*` | The sea: waves, depth colour, shoreline foam, and an overhead camera that lets objects push a band through the surface. |
| `world/sky.*` | The daylight sky: a clear blue dome, the same pale horizon as the fog, and a few large clouds. |
| `world/tunnel.gd` | Draw a curve, get a tunnel bored through the terrain. Opt-in with `--tunnel`. |
| `ui/` | HUD, the floating health bars over the grunts, the touch controls, and the `SpringArm3D` chase camera. |
| `systems/` | Sound: `sfx.gd`, `music.gd`, `ambience.gd`. See below. |
| `art/` | Data only — imported models, generated audio, reference images. Nothing here is loaded as code. |
| `terrain/*.r16` | Height maps from `tools\make_heightmap.py` in `D:\code\gan`. |

## The fight

Left click swings. Hits are resolved by range and facing rather than by the blade's own
overlap — see below, that is a bug fix and not a shortcut. The grunts never used overlap at
all, for a second reason: their Mixamo swing sweeps *across* the body — the tip travels
0.37–0.51 m to their left and barely 0.3 m forward, so it can never reach the person in front
of them (`attack_range` 1.00 m, `hit_reach` 1.35 m).

A hit gives a spark, a knockback impulse and a moment of stagger. Knockback is a **single
impulse**, not a per-frame push: feeding a push back into `move_toward` every frame sent the
captain 2.31 m from a hit the grunt took for 0.43. Being hit does not cancel the captain's
swing — when it did, he lost every fight (6 swings, 1 landed, dead). It still cancels the
grunt's.

When the captain dies the whole scene reloads after `restart_delay`, rather than putting the
pieces back by hand — a reload cannot forget one.

**Hits are resolved by range and facing, not by the blade's own overlap** — 1.35 m in a cone
in front. That is not a simplification, it is the fix for a bug that was there from the start:
the hitbox is 12 cm thick and the hand carrying it moves up to 20 cm per physics step, so the
blade teleported past people between frames. Measured, it landed at 0.40 m and swept straight
through anybody further, while a grunt stands off at 1.00 m and waits.

## Held things

Anything in a hand — the cutlass, the flintlock, and whatever comes next — is a `Held` node
mounted on a bone socket, configured by a **`HeldItem` resource**: `actors/captain/cutlass.tres`,
`actors/captain/flintlock.tres`, `actors/grunt/sword.tres`. Edit them in the inspector.

This was extracted at the third user, which is what CONVENTIONS asks for. Those three each
carried the same six or seven exports under their own prefix — `sword_offset`, `pistol_offset`
— and the paragraph explaining what an offset even means was written out more than once. A
fourth weapon would have put eighteen fields on one actor.

An item answers *where it is and which way it is pointing*, and nothing else. Reach, reload
and damage stay on `sword.gd` and `gun.gd`, one script per kind of thing.

Three corrections turn "a mesh exists" into "he is holding it properly": `rotation` turns the
model onto the hand bone's +X, `grip` slides it along itself so the hand meets the handle
rather than the blade's origin, and `offset` moves it relative to the bone. **Expect to set all
three against a render**, not by reasoning — `tests/captain_view.gd --spin`. The cutlass has
been wrong twice, once upside down and once rolled a quarter turn in his fist, and which way a
blade's flat faces is not recoverable from anything but the mesh. The full reasoning, and the
cutlass worked through as an example, is in `actors/parts/held_item.gd`.

`items_check` covers the failure this design introduced. A weapon that *fails* to mount was
already caught, because a null sword swings at nothing — but one that mounts **successfully on
the wrong bone** is a working sword in the wrong fist, and hits are resolved by range and
facing, so every combat test passes and the only evidence is a picture.

## Guard and parry

**Hold right click.** A blow from the front is turned aside completely — but he is slowed to
40% speed, he cannot swing while the guard is up, and it only covers the front. A guard that
works from behind is a bubble rather than a guard, so there is a facing check and
`guard_check` tests it by holding one facing the wrong way and confirming the blow still lands.

The first **0.18 s** of a guard parries instead, and that difference is the whole point: a
parry throws the attacker back and kills the swing he is in the middle of, where an ordinary
block simply costs him nothing. A parry that only negated damage would be a block with
stricter timing, and nobody would take the risk — so the test asserts the shove, not just the
zero.

The window is not invented. A grunt's blade goes live 0.20 s into a 0.75 s swing, so the
windup is 200 ms of visible tell: raise the guard as the swing starts and you are inside the
parry, leave it any later and you get the block.

Parrying was nearly free to build because knockback is a component — it is the same
`hit_from()` the attacker would have called, pointed back at him.

There is no block clip yet, so he guards in his idle pose, and the parry borrows the `clang`
of a landed hit. `clip_block` is an export and a dedicated parry/block pair is one generation
away; both are one-line changes when they land.

## Weapon slots

**1** draws the cutlass, **2** the flintlock, and only the one he has drawn is in his hands.
Left click uses it — one button with one meaning, rather than a click that changed sense
depending on invisible state.

That is the point of the change, but not the best reason for it. The pistol used to be free:
always in his other hand, so you could swing *and* shoot, and the only brake was the reload. A
weapon change takes **0.25 s** during which nothing works — no swing, no shot, no guard — so
drawing the flintlock means giving up the parry until you put it away. "Which weapon" became a
decision with a price.

The swap also covers a visual problem. There is no sheathing animation, so the cutlass simply
stops existing; a quarter second of committed nothing hides the pop. And the aiming stance only
reads because the sword is gone — Mixamo's pistol clip is a **two-handed** grip, so with the
cutlass still drawn it dragged the sword hand across his face.

A number key will not rescue him from a swing he has committed to. Without that the attack
cooldown is optional: tap 2 then 1 and swing again immediately.

Weapons bring their own clips. The flintlock's `clip_idle` is the levelled hold, which is why
that stance belongs to the weapon rather than being a mode the captain is in — see
`actors/captain/flintlock.tres`. Empty falls back to his own, which is right for a cutlass: a
pirate holding a sword stands like a pirate.

## The flintlock

**2** draws it, left click fires. One ball, then five seconds of reloading — and that is the
design rather than a limitation. A pistol with a magazine turns the cutlass into a backup
weapon, because ranged always beats melee when ammunition is free. The reload is the balance,
and the swap is the rest of it.

It used to live permanently in his off hand: *"a captain with a sword in one hand and a pistol
in the other is the whole picture, and it is less work besides."* That was true until the
aiming clip arrived, because Mixamo's is a two-handed grip — his sword hand came across to meet
the pistol, and the picture it broke was the same one the line was defending. Slots replaced it.

Aiming is a **cursor**, not a centre reticle — this is a bird's-eye camera, so a fixed
crosshair would mean swinging the whole view round to shoot somebody standing beside you. The
ball is traced from the **muzzle** to wherever the cursor points, not from the camera, so he
cannot shoot through the rock he is standing behind.

Drawing it puts him in an **aiming stance** — both hands out, the flintlock level — held for
as long as it is the weapon in his hands. Only while standing still: there is no aiming-walk
clip and no upper-body blend, so moving keeps the walk and lets the pistol ride the arm swing,
which is better than skating a pair of planted feet across the sand. There is still no fire or
reload animation; he fires from the stance.

## Animations

Eleven clips live in `art/models/captain.glb` as one file: idle, walk, run, jump, fall, swim,
dig, punch, slash, death and aim. They are Mixamo's, and they work on a Tripo-generated rig
without retargeting because both use `mixamorig:` bone names — an action written against one
armature applies to the other. `tools/merge_animations.py` bakes a folder of them in;
`tools/trim_clip.py` cuts, pins and renames afterwards without a second Blender pass.

Two traps, both caught by measuring rather than looking.

**Names describe the motion, not the need.** Mixamo's "Jumping" is a run-up — approach, hop,
landing, recovery, 2.20 s — against a controller that leaves the ground and is back down in
0.6 s, so the jump is a 0.34 s slice of "Jumping Up" with the hips pinned. The two pistol
clips are named backwards from how they read: **"Pistol Idle" is the aiming hold** (both hands
out, the pistol hand 28 cm from the hips and travelling 1.3 cm across four seconds) and
**"Pistol Aim" is a 3.6 s lowering** that starts aimed and ends at rest. Only the first is in
the file, as `aim`.

**The frame rate moves under you.** Blender's factory scene is 24 fps and the FBX importer
overwrites it from whatever file it reads — so merging one new clip into a finished character
keyed the existing animations at 24 fps and exported them at 30, and every clip the captain
already had came out 20% shorter in a file that was otherwise perfect. `merge_animations.py`
pins the rate at both ends now. Check any merge with `inspect_clips.py`, which prints each
clip's length, root drift and foot contact: the lengths have to round-trip exactly.

A held clip must also loop, or it freezes into its last frame — which looks like nothing at
all until you hold the pistol up for longer than the aim clip's 4.03 s. `clips_check` asserts
both that and the stance itself.

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
| `mesh_resolution` | 512 | quads per side (visual detail) |
| `collision_resolution` | 513 | collision samples per side (match `mesh_resolution` + 1) |

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

Keep `collision_resolution` at `mesh_resolution + 1`, or you stand on a surface coarser than
the one you see. Measured against this 1024 height map over 400 m:

| `collision_resolution` | spacing | mean error | worst |
|---|---|---|---|
| 129 | 3.12 m | 0.50 m | 8.06 m |
| 257 | 1.56 m | 0.19 m | 3.68 m |
| **513** (current) | 0.78 m | 0.08 m | 2.39 m |

**That middle row shipped, and the captain's boots sank into the grass on every hilltop.** The
number that hid it is the one above: a *mean absolute* error. The error is not noise, it is
**signed and systematic** — a coarser triangle chords across the real surface, so it cuts
**below** convex ground and **above** concave ground. Sampled by curvature at 257:

| ground | mean | worst |
|---|---|---|
| hilltop | **−0.207 m** | −1.646 m |
| flat | +0.004 m | — |
| bowl | +0.175 m | — |

The peaks and the hollows cancel, so the average over the whole island was about a centimetre
while he was ankle-deep on the skyline. At 513 the hilltop figure is −0.061 m, which is the
mesh being made of triangles rather than a defect — the mesh chords the height map at the same
spacing, so the floor and the grass now agree.

`ground_check` asserts it, and samples by curvature for the reason above: an average taken
over flat ground, which is what every other test walks on, reports success.

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

`items_check` confirms every held thing hangs where its resource says. `clips_check` drives
both characters through their states and reads back which clip is playing, because a character
frozen in its rest pose fights exactly as well as one that animates. `guard_check` and
`balance_check` cover the fight.

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
- **A geometry LOD silently takes the shading that depends on it.** The ocean fades its wave
  amplitude to zero past `detail_far` so distant water cannot alias, which also takes the
  normals to exactly `(0,1,0)` — and the sun glitter is a sharp specular off those normals, so
  the glitter path stopped dead in open water with a flat blue sheet beyond it. The fix is not
  a longer fade: it is to give the glitter its own, less faded, copy of the slopes and to
  broaden the specular lobe with range, because a sun road at distance *is* a smooth streak
  rather than resolved flecks. It costs nothing, since `wave_slope` is linear in its amplitude
  — evaluate the slopes once at full height and scale them twice.
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
