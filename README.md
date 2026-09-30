# Pillage People (Godot 4.7)

A stylised pirate game on a generated island. A captain with a cutlass, grunts who fight
back, a shore to swim off and a waterfall to walk through.

Open the folder in Godot and press F5, or run:

```
D:\Godot\Godot_v4.7.2-stable_win64.exe --path D:\code\pillage_people
```

See [CONVENTIONS.md](CONVENTIONS.md) for where files go and how behaviour is split up. Read
that before adding anything.

**Keyboard:** WASD move (relative to the camera) · Space jump · **C** dives, and once under he
stays under: C sinks, Space rises, and Space held until he breaks the surface puts him back on it
· **1** cutlass, **2** flintlock
· left click uses whichever is in his hand · **hold right click** to guard · **Z** spyglass,
wheel zooms while it is up · middle-drag turn and tilt the camera · mouse wheel zoom · Q/E
turn · E beside the ship climbs onto the deck · E at the helm drives (W/S way, A/D turn, E lets go).

R and F used to tilt the camera. The middle-button drag does that better, and R is where a
player looks for a sidearm.

**Touch (iPad):** left half = virtual stick (appears where your thumb lands) · right half drag
= turn and tilt · two-finger pinch = zoom · bottom-right button = jump · a second button, left
of it, appears while swimming: hold it to dive and sink, hold jump to rise. These appear only on
a real touchscreen; on desktop add `--touch` to see them.

## What is in it

Laid out by thing rather than by file type — see [CONVENTIONS.md](CONVENTIONS.md).

| Where | What it does |
|---|---|
| `main.tscn` / `main.gd` | The scene, and the orchestrator: builds the island, scatters the props, spawns the grunts, and wires everything to the audio. |
| `actors/captain/` | The captain. `CharacterBody3D`: camera-relative movement, jumping, swimming, swinging a cutlass, taking hits, dying. |
| `actors/grunt/` | A grunt. Idles, chases, swings back, staggers, dies. 3 hp against the captain's 5. |
| `actors/parts/` | Shared by both: the blade (hung off a hand bone with a hitbox along it) and the hit spark. |
| `actors/outfit/` | Modular characters: a rigged body plus swappable pieces (heads, hats, coats, boots), and the workshop scene they are tried on in. See Modular characters below. |
| `props/` | Placeable prefabs, one folder each, every one a `.tscn`: rocks, the rock arch, cargo (barrels and crates, which float), palms, grass, corals and seaweed with one scene per kind (the dive crater's reef is a `ScatterPatch` under the crater in `main.tscn`, so it moves with it; `reef/` grows beds of them through the shallows), fish schools, the shark, the cannon, the waterfall, and the double-deck ship moored off the beach. `grass/grass_patch.tscn` is a clump you place by hand under Terrain; `grass/grass.tscn` is the island-wide scatter. |
| `world/terrain.*` | Lays down its Seabed, applies every stamp under it in order - the island is the first - and builds the mesh + a `HeightMapShape3D` collider. |
| `world/seabed/` | The sea floor the ground starts from, under Terrain: a depth, a `FastNoiseLite` for bumps, and how it deepens past the island's area. Worked out on the CPU, so the collider, `height_at()` and the water all read it. |
| `world/ocean.*` | The sea: waves, depth colour, shoreline foam, and an overhead camera that lets objects push a band through the surface. |
| `world/sky.*` | The sky, day, golden hour and night: the dome's gradients, sun, moon and stars, and the clouds - see Clouds and weather below. `world/cloud_shadow.gdshaderinc` lays the clouds' shadows on the ground and the sea. |
| `world/underwater.*` | The sea from below: a full-screen pass that fogs everything under the waterline blue, splits the screen along the swell when the camera is half in, and lays light shafts through the water. `world/waves.gdshaderinc` is the surface both it and the ocean draw. |
| `world/tunnel.gd` | Tunnels and caves, placed under Terrain: draw a curve, pick a section (round, arch, shaft). Dead ends are capped, corners mitred, crossings opened. See Tunnels below. |
| `world/terrain_stamp/` | Reshapes the island under it. Instance `terrain_stamp.tscn` under Terrain, place and turn it. Every stamp follows one rule: its shape gives a height (a signed fraction of the stamp's `height` in metres) and a mask, and the mode blends that into the ground - **Add** puts it on top (a mountain, mesa, volcano or canyon; negative digs), **Replace** sets the ground to the stamp's own Y plus the shape, **Min** only cuts down to that and **Max** only fills up to it, then mask x `opacity` decides how much lands. Replace, Min and Max show a see-through sheet in the editor at the level they work to. Shapes: a `.stamp` image, or a soft rectangle or circle (full height, with a fade round its edge - so a levelling pad wants `height` 0 to sit at the gizmo); the ground mesh is cut along a soft shape's outline and along the foot of its bank, so an edge as sharp as 0.25 m is a real edge at any angle, with a straight lip, a straight shadow and a collider that matches (Terrain's `cut_edges` turns this off). A `.stamp` holds a 16-bit height (mid-grey is zero) and a 16-bit mask per sample; `tools/make_stamp.py` makes one from the "Terrain - Stamp" ComfyUI workflow's output in `D:\code\gan`, or from an old `.r16`. Add `*.stamp` to the export filter beside `*.r16`. |
| `addons/biome_painter/` | Editor plugin: a brush that hand-overrides the automatic ground biome (grass, sand, rock, jungle) straight in the 3D viewport. See Painting the biome below. |
| `ui/` | HUD, the floating health bars over the grunts, the touch controls, and the `SpringArm3D` chase camera. |
| `systems/` | Sound: `sfx.gd`, `music.gd`, `ambience.gd`. See below. |
| `art/` | Data only — imported models, generated audio, reference images. Nothing here is loaded as code. |
| `art/models/characters/` | Bodies and pieces for the modular characters, named `<slot>_<name>.glb`. See the README there. |
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

## Modular characters

A character can be built from parts instead of one solid model: a rigged **body**, and
**pieces** worn on it - head, jaw, hair, face, hat, shirt, coat, trousers, waist, boots and an
accessory. Six heads, six hats, five coats and four skin colours is hundreds of different
pirates from twenty-one models. The captain and grunts are still single models; the zombie is
the first body built this way.

**The workshop** is `actors/outfit/workshop.tscn` - open it and run it with F6. You pick a body
and one piece per slot, press R for a random outfit, play any clip to watch the pieces move, and
nudge whichever piece is selected in the Fit section. **Save piece** keeps its fit and **Save
outfit** keeps the whole character. It finds bodies and pieces by file name in
`art/models/characters/` (see the README there), plus the primitive placeholders in
`actors/outfit/placeholders/`, so a new part from Tripo is a file dropped in a folder.

Pieces are worn in one of two ways:

- **Skinned** pieces bend with the body. Tripo delivers them as unrigged statues, so
  `skin_copy.gd` gives each vertex the skin weights of the body nearest to it, blending the
  four nearest body points so loose cloth does not tear between the legs. This is Blender's
  "copy weights from the nearest surface", done in Godot so fitting a piece and seeing it walk
  is one step.
- **Pinned** pieces are rigid and ride one bone - a hat on the head - the same way the cutlass
  rides the hand.

Everything is placed in **fit space** (`rig_space.gd`): metres, the T-pose, feet on the floor,
Y up, facing +Z. The rigs themselves disagree about all of it. The captain's and grunt's
skeletons work in centimetres and lie face down at rest, and each clip's hip track stands
them up. The zombie's stands upright in metres. Fit space is read off where the bones actually
are, so a hat moved up two centimetres means two centimetres on every rig.

**Clips are shared, not re-downloaded.** `retarget.gd` copies the captain's twelve Mixamo clips
onto any body with the same bone names. It copies how far each bone has turned from its T-pose,
not the raw rotation, so the captain's lying-down rest does not lay the zombie flat. The hips
travel in proportion to hip height, so a longer-legged body takes a longer stride.

**The zombie body** came from Tripo's auto-rig with every bone at the origin, and the mesh tore
apart on import. The joints survive only in the skin's inverse bind matrices, which were built
in Blender's axes - Z up, facing +X, origin halfway up the body. `tools/repair_rig.py` finds the turn and shift that
put every joint inside its own limb (on the 1 m export, the median bone sits 7 mm from its limb's
centre, against 49 mm for the next-best candidate), writes the joints back, and bakes the height - 1.8 m - into the file.

Not done yet: nothing in the game spawns a dressed character; the zombie is only in the
workshop so far. Body skin still exists under clothes, so a sleeve can show an elbow through it
in an extreme pose. The zombie's jaw has no hinge.

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

The island is a stamp: `terrain/island.stamp`, the TerrainStamp named **Island** that comes first
under Terrain in `main.tscn` - a Replace, 620 m square, over a Seabed. It used to be the whole
ground, read as `terrain/island.r16`; that file stays until the old loader is removed, so
`tests/island_stamp_check.gd` can show the stamp gives the same ground (to 0.011 mm).

Its outer slope fades into the **Seabed** (`world/seabed/seabed.gd`, a child of Terrain) over
`border_fade` (90 m), so at the square's edge the ground is the Seabed alone, and the Terrain
carries it on as a coarse **far ring** out to `far_extent`, 1200 m - past the camera's 1 km.
The ring is stitched to the square's own edge vertices, so there is no seam; it has its own
coarse collider, and the water reads its depth off it. A stamp whose reach crosses the edge
shapes the ring too. `tests/far_seabed_check.gd` checks the stitch, the collider, the water and
the far depth; `tests/seabed_view.gd` renders the border from above, the ship, the beach and
three dives.

| Seabed setting | Default | Meaning |
|---|---|---|
| `depth` | 4 m | water over the bed near the island - deeper than the shallows' reef band, so no coastal bed grows out on it |
| `noise_height`, `noise` | 1 m | bumps on top, from a FastNoiseLite |
| `shelf_radius` | 200 m | how far from the Terrain's middle the bed stays at `depth` |
| `deepening_distance` | 350 m | over which it then drops to `far_depth` |
| `far_depth` | 60 m | the open sea's depth, and the water's bed past the far ring |

Everything on it is placed from `main.gd`: 40 rocks, 14 palms, 70 grass patches (about 1400
tufts in one MultiMesh), 5 barrels and 6 crates ashore with more afloat, 5 grunts, a reef of
corals and weed on the dive crater's floor, and about 450 more through the shallows in some
twenty coral reefs and weed patches.

The shallows are `props/reef/reef.gd` again, told a band of water (0.9 to 2.8 m) instead of a
crater, and it finds the coast by depth rather than from a list of beaches. They grow the way
the real things do, **in beds of one kind**: a coral reef, or a patch of weed, 14 to 26 plants
packed closer than they are wide, thinner and smaller toward the rim. How big a bed is and how
tight it packs belongs to the family - `BED_RADIUS` and `BED_SPACING` in `coral.gd` and
`seaweed.gd` - because weed is blades a handspan deep and needs a smaller, tighter patch than a
reef to read as one. Each bed is a node (`CoralBed3`, `SeaweedBed7`) you can find, move or
delete in the editor. Beds of the two kinds mixed, a metre apart, read as single plants dotted
about.

About half the beds go along the beach he starts on (`shallows_beds_here`, within
`shallows_reach` of the spawn) and the rest round the island (`shallows_beds_round`), because
the coast is 1.5 km long and filling all of it at a beach's density would be over a thousand
plants. Weed grows from the foam line out; a reef only where all of it is past 1.4 m, where he
is swimming rather than wading, because corals have no collider and walking through one reads
as a bug. Nothing grows under the moored hull.

**Near the beach the swell decides how big they can be.** The waves sum to 1.32 m and only
flatten as the bed rises, so in 1.5 m of water the surface can fall to 0.64 m. Each growth is
sized against the lowest the water gets where it stands (`Ocean.deepest_trough`), and the
shallows ask for half of that trough (`trough_share = 0.5` in `_grow_shallows`): plants in a
metre of water average 0.55 m tall rather than the 0.35 m the whole trough would allow, and
the tallest tips show at the bottom of the biggest swells - the most exposed about 9% of the
time. Lower `trough_share` for bigger plants and more showing, 1.0 for none ever showing. No
setting lets one reach the still level, which is what keeps them off layer 20. Beyond 110 m from
the camera they are not drawn (`visible_within`).

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
| `height_samples` | 1025 | height samples per side when the ground starts from a Seabed (2 x `mesh_resolution` + 1). An image stamp the ground's size with this many samples - the island - lands sample on sample and is applied without interpolating. |
| `collision_resolution` | 513 | collision samples per side (match `mesh_resolution` + 1) |
| `cut_edges` | on | cut the ground mesh along soft stamps' outlines and bank feet, so a sharp pad edge is a real edge. Off, sharp edges are drawn from the height field alone and come out saw-toothed; edges wider than about 2.5 m look the same either way. No cost per frame. |
| `far_extent` | 1200 | how far out from the middle the far ring goes, in metres. Only with a Seabed. |
| `far_cell` | 8 | detail quads per far ring cell (8 is 9.7 m on the island). Must divide `mesh_resolution` / 2. |
| `chunk_quads` | 32 | quads per chunk side. The ground is built in chunks so an edit only rebuilds the chunks it touches: the whole island is about 3 s, one chunk about 10 ms, so a ticked stamp or tunnel follows the gizmo. Chunks are culled one by one too. |
| `biome_path` | `terrain/island_biome.png` | the hand-painted overrides on the automatic biome. See Painting the biome below. |
| `biome_palette_path` | `terrain/biome_palette.png` | the named colours `biome_path` indexes into. See Painting the biome below. |

## Painting the biome

The ground's colour - grass, sand, rock, jungle - is decided entirely in `terrain.gdshader`
from height, slope and noise. `world/terrain_stamp/` can force a whole shaped area to a chosen
*height*; it has no opinion on colour. For "I don't want rock there" or "a patch of sand in
the grass," or a biome the automatic rules have no name for at all - a scorched patch, a worn
path, anything you can name and pick a colour for - there is a brush instead: the **Biome
Painter** dock, enabled in `project.godot` like any other editor plugin. It docks to the
bottom of the right-hand column, next to the Inspector's own tabs - the first time, it may be
behind another tab there; click its tab to bring it forward.

Select the Terrain node, tick **Paint**, and drag across the ground - a ring follows the mouse
showing where and how big the brush is:

- The **list** holds the palette: as many named biomes as you give a name and a colour to.
  Click one to paint with it. **+ Add** appends a new one (name, then a colour swatch to pick
  from); **Remove selected** takes one away. A fresh Terrain starts with four, matching its own
  Grass/Jungle/Sand/Rock colours, so the tool is useful before you have named anything yourself.
- **Erase** paints back to automatic instead of any named biome - a slider was not needed for
  "undo this patch": tick Erase and brush over it.
- **Radius** and **Flow** are the brush's size and how fast a held stroke builds up - low flow
  and repeated passes give a soft, partial blend; flow at 1 paints the chosen biome (or clears
  to automatic) fully in one dab.
- A stroke saves **the moment the mouse is released** - live, no extra step, but also **outside
  Godot's own undo history**: Ctrl+Z will not take a stroke back. Both files are checked into
  version control precisely so a bad stroke can be reverted there instead. Renaming or
  recolouring a palette entry changes every stroke that used it, everywhere, at once - a
  palette edit is not itself a stroke.

Mechanically: `biome_map`'s red channel is which column of `biome_palette` is painted at that
point (0 = none, the automatic colour stands), green is how strongly, so a soft brush edge
fades back to automatic rather than cutting to it. The shader looks up that column's colour and
blends the whole finished automatic colour toward it by that strength (`terrain.gdshader`) -
after everything else (sheen, caustics, the rim light) still runs on top, so a painted patch
still catches the sun and the tide like anywhere else. An earlier version of this pushed three
fixed axes (vegetation, rock, jungle) instead of looking up a named colour; it could not add a
biome outside those three, which was the whole point of asking for "as many as I want."

Painting changes two small textures only: no mesh rebuild, no collider change, nothing to wait
for. `tests/biome_map_check.gd` covers both files' round-trip and the default palette;
`tests/biome_paint_view.gd` (a real, non-headless render - `--headless` has no rendering server
behind a live texture update, so it cannot see one) paints a colour the automatic rules could
never produce onto a real cliff and real flat grass and measures that it visibly shows up on
both; `tests/biome_painter_live_check.sh` drives the actual editor plugin - selection, paint,
drag, release, save, erase, adding a biome - inside a headless editor, the same way
`editor_live_check.sh` covers stamps and tunnels.

## Tunnels

A tunnel is a node you place **under the Terrain node**: `Tunnel` extends `Path3D`, so you draw
a curve and pick a cross-section. Two points make a straight cave, points with handles a winding
one, points without handles a passage with sharp corners. Like a terrain stamp, it only shows in
the editor once **Preview** is ticked, and from then on it is live; the game builds every tunnel.
`--tunnel` still generates one when the scene has none.

- **Sections:** `Round` (a bore), `Arch` (flat floor, straight walls, rounded roof - the cave),
  `Shaft` (flat floor and roof), each `width` x `height`. The curve runs through the middle of
  the section, so the floor is half the height below it.
- The tube is **clipped to the ground**: every triangle is cut against `terrain height - y`, so
  the tube ends exactly on the surface and the mouth is that intersection curve, whatever the
  slope. An end of the curve that stays underground gets a **rounded cap** - a dead end.
- The terrain is cut **against the tube itself**, triangle by triangle along the exact contour
  rather than in grid squares, so an opening is always the tube's own section where it breaks
  the surface. The cut stops a little inside the wall (`cut_margin`), so ground and tube overlap
  instead of meeting exactly on one surface.
- **The ground at a mouth is left as it is.** Where the floor comes out of a hillside is where
  the entrance is; to make it walkable, shape the ground there with terrain stamps (Replace,
  Min, Max); a ticked tunnel follows as it is moved, like a ticked stamp.
- **Sharp corners are mitred**: the section at the corner faces halfway round and is stretched
  across the bend, so the walls stay parallel through it instead of pinching shut on the inside.
- **Tunnels that cross open into each other**: each one's walls are trimmed where they run
  inside another.
- Collision: the height field gets `NaN` wherever the opening is, the cut rim quads add a
  trimesh, and the tube's own trimesh has `backface_collision = true` - without it you fall
  straight through a tube walked on from the inside.

`tests/tunnel_check.gd` measures a dead-end cave, a 90 degree corner and a crossing with rays.

## Clouds and weather

The clouds are painted in the sky shader, no textures, in the four shades measured off
`art/references/sky-and-clouds-v1.png`, back to front:

- **The deck** - a flat layer overhead seen in perspective: thin cirrus streaks (`wisps` on
  the sky material), and past about 0.6 cover, puffs that join into an overcast sheet.
- **The cloudlets** - small flat clouds mid-sky: a few blobs on a streaky base, white top, blue
  underside, trailing streaks. A few by day, rows of them at the golden hour.
- **The horizon heaps** - eighteen low cumulus round the sea line, overlapping in runs with gaps.
- **The masses** - twenty-four cumulus in three rings, towers on the horizon, middling heaps
  above them, small ones high up. They grow in one by one as the cover rises.

Every cumulus is built by the same recipe, a port of a prototype matched side by side against
the sheet, following thirteen rules read off it. The rules are written out at the top of
**THE PAINTED CUMULUS** in `world/sky.gdshader`, and each is commented where it is used. A cloud
is a path of big blobs (base run, off-centre tower with a bulging sun side, a crown, shoulders
stepping down), each big blob is a body with a run of medium bumps round its rim, and the
sun-side bumps carry small leaning scallops: the white band. Every shape is a circle wobbled by
sines. Lower blobs are in front and darker, the bumps under a blob sit behind it, and a shelf of
streaks runs under the base. The values come from a diagonal gradient toward the light, in four
steps. The knobs are in the material's **Cloud Shapes** group: `cloud_detail` (2 all, 1 no
scallops, 0 big blobs only - the first thing to turn down if a device is slow; the cost on
iPad has not been measured), `smallest_lobe`, `base_squash`, and the `value_*` numbers for the
gradient. The clouds' placement and seeds are the two tables near the end of `sky()`.

**The weather is two numbers**, `cloud_cover` (0 clear, about 0.55 the sheet's trade-wind
cumulus, 1 overcast) and `cloud_storm` (0 fair, 1 the sheet's squall slate). They are global
shader parameters - Project Settings > Shader Globals - because the ground and the sea read them
too: `world/cloud_shadow.gdshaderinc` lays hard-edged cloud shadows across both, about a quarter
of the island at 0.55, projected along the sun and drifting with `Wind`. Only the terrain and the
sea take them; rocks, palms and the ship do not.

`tests/sky_view.gd` holds the colours to the sheets, the cloud to piling up toward the horizon
as the sheet's does (more low than high, and a fifth or more of the sky between 12 and 26
degrees), and the shadows to between a tenth and half of the island.


`Waterfall` (`props/waterfall/`) extends `Path3D` like a tunnel: draw a curve from the lip down
the rock, set `width` and `spread`, and it rebuilds as you drag. **End the curve on the water's
surface** - its last point is where the splash, the mist and the foam ring go.

It is built in the layers stylised games use (Zelda, RiME, A Short Hike), all toon-shaded to
match the ground and the sea, and all without textures:

- **Body** - the sheet, bowed out into a shallow half-pipe (`bulge`) so it has volume side on,
  with long vertical streaks scrolling down it in three flat bands and a white, speeding up as
  they fall. Ragged hard edges, a white lip, and a bottom that turns white in steps.
- **Veil** - a wider sheet just in front drawing only the brightest streaks, faster. The two
  sliding past each other is what makes it read as falling water.
- **Splash**, **lip spray** and **mist** - `GPUParticles3D` puffs (`splash.gdshader`): lumpy
  hard-edged blobs lit as balls, eaten away as they die; the mist is the same puff, big, soft
  and see-through.
- **Foam** - a plane on the pool with a white churn along the landing line and broken rings
  spreading out (`pool_foam.gdshader`), drawn after the sea.

All three shaders light the water in two tones and ignore cast shadows: the plain toon diffuse
turned every white into a strong blue wherever the sun was behind the fall or the mountain's
shadow was on it. It still goes dark at night. `tests/waterfall_view.gd` photographs it from
five places, and measures the column and the landing against the art sheets.

## Is it really physics?

Yes. The terrain is a `StaticBody3D` with a `HeightMapShape3D`; the captain is a
`CharacterBody3D` moved with `move_and_slide()`, so Godot (Jolt) resolves the contacts. Gravity
is applied in script, which is how a kinematic body is meant to work. Nothing snaps him to the
height map — the only direct sampling is choosing the spawn point.

The project uses **Jolt**. A `NaN` sample in `HeightMapShape3D.map_data` becomes a hole with no
collision; the default engine does the same but spams "Vector3 cannot be normalized", so holes
want Jolt.

Keep `collision_resolution` at `mesh_resolution + 1`, or you stand on a surface coarser than
the one you see. Measured against the height map (then 1024 samples a side, now 1025 so that mesh vertices sit on samples) over 400 m:

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
Godot.exe --headless --path . --script res://tests/coral_check.gd
Godot.exe --headless --path . --script res://tests/placement_check.gd
Godot.exe --headless --path . --script res://tests/outfit_check.gd
Godot.exe --headless --path . -- --deathtest
```

`placement_check` covers `world/ground.gd` and `ScatterPatch` — that a model's BOTTOM lands on
the ground rather than its node origin, and that one patch can grow a reef on the crater floor
and a rock field up the beach with nothing between them but a signed water band.
`coral_check` measures the reef on the crater floor: that the corals carry their size in the
`.glb` rather than a gitignored `.import`, that every one sits on the seabed, and that none
breaks the surface — which is what makes it correct for a coral to be the one prop here that
stays off the ocean's layer 20 - and that moving the crater replants the reef on its new
floor. It then measures the shallows the same way, but reads the sea
itself - `surface_y` at every growth over three quarters of a minute - rather than trusting the
trough the reef planted against: no tip may be out of the water more than an eighth of the
time. It also checks each bed is one kind and packed like a patch, the corals stay out of
wading depth, the beds reach round the island and thicken at the start, and nothing grows under
the moored hull. `coastal_smoke` checks the island builds and the captain stands
on it. `ambience_check` walks
him from the sea to the hilltop and prints what every sound bed is doing, and checks the
assumption underneath the mix — that on this island low ground *is* the shore (ground below
3.5 m is 12 m from water on average, ground above 34 m is 74 m). `--deathtest` kills him and
checks the island comes back.

`outfit_check` covers the modular characters: fit space on both kinds of rig, the T-pose, a
coat landing on its fit to the tenth of a millimetre and its cuff staying on the wrist through a
swing, a hat staying on the head bone, the captain's walk on the zombie keeping his feet on the
floor, skin tint, and an outfit surviving save and load. It also fails if a body in
`art/models/characters/` still has every bone at the origin. `tests/outfit_view.gd` (not
headless) photographs the workshop in the T-pose and mid-walk.

`items_check` confirms every held thing hangs where its resource says. `clips_check` drives
both characters through their states and reads back which clip is playing, because a character
frozen in its rest pose fights exactly as well as one that animates. `guard_check` and
`balance_check` cover the fight.

`tests/waterfall_view.gd` (not headless) photographs the waterfall and holds its column to the
blue the art sheets draw, its landing to white, and its night to dark.

`tests/captain_view.gd` renders him from four angles, and `tests/outline_probe.gd` renders the
same view with one suspect disabled at a time. Both exist because the bugs they found — a
cutlass rolled a quarter turn in his fist, a white line around everything at distance — could
only be seen, not reasoned about.

## Working on two machines (PC + iPad)

Godot writes a `.import` file next to every asset, and the contents differ per machine — so
with both a PC and an iPad in one repo, every pull collides on files nobody edited. The screenshots
in `docs/` and the art in `art/references/` are data rather than textures, so each carries a
`.gdignore`. `*.import` is gitignored.

`terrain/` must NOT carry one, whatever it looks like it saves. A `.gdignore` hides a folder
from the exporter as well as from the editor, and no export filter reaches back in: `*.r16` in
the preset looked right and shipped nothing, so the exported game opened with no island. The
game reads `res://terrain/island.stamp` with `FileAccess` at run time, and a file the exporter
cannot see is a file the build does not have - so the preset needs `*.stamp` as well as `*.r16`.

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
