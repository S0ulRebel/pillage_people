# Terrain plan: seabed + island stamps

Replaces the single baked 620 m square (`terrain/island.r16`) with a seabed generated in code
and islands placed on it as stamps. Seven phases, each its own commit or PR, with every test
passing before the next starts. The game looks identical until phase 5, and phase 5 changes
only the ground outside the island and its outer slope.

## What was agreed

**Structure.** A `Seabed` node under Terrain generates an endless seabed. Islands are stamps
placed on top of it.

**Seabed node.** Its noise is evaluated on the CPU, because collision, `height_at()` and the
water's depth all need the real height; fine visual detail stays in the terrain shader.
Settings:

- depth, in metres below sea level
- noise height, in metres
- noise: a `FastNoiseLite` resource (seed, frequency, octaves, with a live preview)
- deepening: how fast the seabed drops away with distance, down to a far depth

The seabed is built first, then the stamps apply on top in child order.

**Units.** Sea level is fixed at y = 0. All heights are in metres.

**Stamp height.** Signed: mid-grey (32768) is zero, brighter raises, darker lowers. Each stamp
has a height in metres that scales both directions.

**Blend modes.**

| Mode | What it does | Use |
|---|---|---|
| Add | ground + stamp, relative to the ground | details: dunes, ridges, craters |
| Max | only raises the ground | islands |
| Min | only lowers the ground | canyons, rivers, coves |
| Replace | the ground becomes the stamp | exact set pieces |

Max, Min and Replace measure from the stamp's own Y. Today's Flatten, Cut down and Fill up are
Replace, Min and Max with a flat shape.

**Opacity as a mask.** result = mix(ground, blended result, opacity), so opacity 0 means no
influence. The final influence is the image's opacity × the stamp's edge fade × an opacity
slider on the stamp.

**File format: `.stamp`.** Raw data with a small header: the identifier `STMP`, a version,
width and height, then 16-bit height and 16-bit opacity per sample, little-endian. Not 16-bit
PNG, which Godot drops to 8-bit. `*.stamp` goes into the export filter next to `*.r16`.

**ComfyUI stamp workflow.** Outputs mid-grey height plus opacity.

**Tagging.**

- Placing things: a `ScatterPatch` goes under whatever it belongs to. The reef becomes a
  `ScatterPatch` under the dive crater.
- Finding things: Godot groups, with snake_case names stored as constants in one file.

## Key technical decisions

- **The blend-mode order keeps saved scenes working.** The new modes are
  `{ADD, REPLACE, MIN, MAX}`. Today's are `{ADD, FLATTEN, CUT_DOWN, FILL_UP}`, so each saved
  number means the equivalent mode and `main.tscn` needs no mode edits.
- **One rule for every stamp.** The target is Y + value × height; Add uses
  ground + value × height instead. The result is mix(ground, blended result, opacity). Soft
  rectangles and circles have value 1 everywhere.
- **Signed decode:** value = (u − 32768) / 32768.
- **The island converts exactly.** It becomes a Replace stamp with
  Y = height = 180 × 32768 / 65535 ≈ 90.0014 m, at opacity 1, with no edge fade, 620 m across
  and centred on the origin. Its samples land exactly on the terrain grid (both map a sample
  as u × (N − 1)), so Y + value × height gives back the old heights apart from floating-point
  rounding.
- **Speed.** An image stamp that lands sample on sample on the ground's grid - the island -
  skips the terrain's exact-height path (`_stamp_rects` / `height_exact()`): its baked samples
  are its own, and it covers everything, so it would slow every ground lookup for nothing.

## Phase 1: group name constants (done)

- Add `systems/groups.gd` (`class_name Groups`) with `TERRAIN`, `CANNONS` and `WIND`.
- Replace the string names in `world/terrain.gd`, `world/terrain_stamp/terrain_stamp.gd`,
  `world/tunnel.gd`, `props/grass/grass_patch.gd`, `props/cannon/cannon.gd`,
  `actors/captain/captain.gd`, `world/wind.gd`, `props/ship/ship.gd`, `props/ship/sail.gd`,
  `main.gd` and the tests.
- **Done when:** no group names are left as plain strings, and the tests pass.

## Phase 2: the reef becomes a ScatterPatch (done)

- A `ScatterPatch` named `Reef` sits under `DiveCrater` in `main.tscn`, with the old reef's
  numbers: 26 plants, 22 m radius, 2.2 m spacing, size 0.7-1.45, sink 0.06 m, at least 4 m of
  water, `stay_submerged` with 1.5 m clearance.
- The coral and seaweed scenes already dress themselves. To keep the mix of all nine models,
  each kind got its own scene inheriting `coral.tscn` / `seaweed.tscn`
  (`props/coral/coral_fingers.tscn` ... `props/seaweed/seaweed_arching.tscn`).
- Removed `_grow_reef()`, `coral_count` and the crater search from `main.gd`, and deleted
  `props/reef/reef.gd`.
- `ScatterPatch` fixes this needed:
  - Terrain emits a new `reshaped` signal when its heights are laid down or rebuilt, and a
    patch replants on it. Under the Terrain a patch is ready before the ground is, so without
    this nothing grew at all.
  - `height_of()` builds the scene in the tree before measuring it. Measured outside the tree,
    every coral was 0 m tall and `stay_submerged` let any height through.
  - A move replants at the end of the frame, not inside the move notification, which crashed
    the engine when the crater moved with its reef under it. It skips moves that leave the
    position unchanged.
- Changes in behaviour: the reef is the same every run (the patch's `seed`, where the old reef
  was random per run), and like the other hand-placed nodes it stays under `--noassets`.
- `tests/coral_check.gd` now also moves the crater 60 m and checks the reef replants on the new
  floor. `tests/placement_check.gd` and `tests/dive_hole_view.gd` still find the crater as a
  negative Add stamp; phase 3 changes them with the `strength` rename.

## Phase 3: the `.stamp` format and blend modes (done)

- `world/terrain_stamp/terrain_stamp.gd`:
  - modes `{ADD, REPLACE, MIN, MAX}`, numbered as Flatten, Cut down and Fill up were, so saved
    scenes load unchanged
  - `strength` is now `height` (metres); new `opacity` slider and `border_fade` (image stamps
    only, metres faded inside the image's border, 0 = off)
  - the one rule: level = Y + shape x height (Add: ground + shape x height), then
    mix(ground, blended, mask x opacity); soft shapes are full height with their edge fade as
    the mask
  - loads `.stamp` (header `STMP`, version 1, columns, rows, then uint16 height with 32768 as
    zero and uint16 mask per sample); images need not be square
  - the editor's see-through sheet sits at the level a soft shape actually works to, Y + height
- `tools/make_stamp.py` (stdlib only): `r16` (old stamps, or `--signed` to copy the numbers as
  they are, `--opacity` for a mask), `png` (grey / grey+alpha / RGB / RGBA, 8 or 16 bit, alpha
  as the mask) and `info`.
- The four image stamps are now `.stamp`; the old `.r16` copies are deleted. The largest change
  is 1.4 mm on a 45 m stamp.
- `main.tscn`: the three levelling pads have `height = 0`, the crater `height = -10`. The
  terrain was dumped before and after: all 1,050,625 samples and 100,000 `height_at()` points
  are bit-identical.
- A levelling pad made in code needs `height = 0.0` - the default is 40, so a new stamp dragged
  in is a visible mountain. The tests and the live-check addon set it.
- `tests/terrain_stamp_check.gd` gained a signed-image check: a `.stamp` written by the test
  (+0.75 / -0.5 height, a quarter masked off) on every mode, with opacity and border fade, held
  to the file's own numbers. Ignoring the mask fails it by metres.
- Still to do by hand: add `*.stamp` to the export filter beside `*.r16`
  (`export_presets.cfg` is not in the repo).

## Phase 4: Seabed node and exact island rebuild (done)

- `world/seabed/seabed.gd` (`Seabed`, under Terrain): `depth`, `noise_height`, a
  `FastNoiseLite`, `far_depth` and `deepening_distance`, measured from the edge of the detailed
  area (the Terrain's square) rather than from each island. `height_at()` for one point,
  `fill()` for the whole grid at once. Any change rebuilds the whole ground in the editor.
- Terrain: a Seabed child wins over `raw_path`; `height_samples` (1025) sets the grid when the
  ground starts from the Seabed. An image on the grid (the island) skips the exact-height
  path, which would add nothing for it and slow every lookup; other images keep it. An image's
  edge samples now count as inside it - the island's outer ring was being left to the seabed.
- `terrain/island.stamp` (made with `make_stamp.py r16 --signed`) is the `Island` stamp, first
  under Terrain in `main.tscn`: Replace, 620 m, Y = height = 90.001373291015625 (180 x 32768 /
  65535 to a 32-bit float's width).
- Speed: an image that lands sample on sample on the ground's grid is applied by
  `TerrainStamp.reshape_grid()`, with no transform and no interpolation. The island went from
  1.55 s to about 0.2 s; the Seabed's grid is 0.27 s. The Terrain is ready in about 0.5 s
  against 0.04 s from the height file.
- `tests/island_stamp_check.gd`: the old and new islands differ by at most 0.011 mm at a
  sample (one 32-bit step, in 1.8% of them), 0.003 mm between samples, 0.015 mm at a mesh
  vertex; and main.tscn's Island is checked to be the stamp the test builds. `main.tscn` as a
  whole matches the phase 3 dump to 0.006 mm everywhere inside the square.
- Outside the square there is no ground yet. `height_at()` there, inside a pad's reach (only
  TerrainStamp4's fade crosses the edge), now reads the seabed rather than repeating the
  island's edge. Phase 5 builds that ground.
- Changed from the plan: the tests that build their own terrain still use `raw_path` - the
  comparison test shows it is the same ground - and move over when phase 7 removes the loader.
  `addons/terrain_live_check` gained a Seabed section and now edits a pad in main.tscn, not
  its first stamp, which is now the island.

## Phase 5: seamless border and far seabed

- **Border:** at the edge of the square the island file is 7–12.6 m deep. Turn on the island
  stamp's edge fade across its outer slope (roughly 220–310 m from the centre, which is a
  plain slope with no features), and tune the seabed to meet it.
- **Far seabed:** a coarse ring of mesh from the square out to about 1.2 km, past the camera's
  1 km view distance. It gets coarse collision, and a short skirt hides cracks where it meets
  the detailed grid.
- **Water shader:** `bed_height()` in `world/waves.gdshaderinc` reads a coarse far-seabed
  texture instead of the fake drop to 60 m.
- **Done when:** there is no visible seam from the beach, from the ship or from a dive. Check
  with `tests/underwater_view.gd` and `tests/dive_hole_view.gd`.

## Phase 6: sea level at y = 0, all heights in metres

- **Terrain:** remove `height_scale` and `sea_fraction`. `sea_level()` returns 0. Heights are
  stored in metres. `find_spawn()` works in metres above sea.
- **Water:** the water shaders get `terrain_scale` 1, and their `sea_y` defaults change from 18
  to 0.
- **Migration script:** subtract 18 m from every hand-placed height in `main.tscn`: the ship,
  arch, ocean, fish, stamps, tunnel and island (90.0014 becomes 72.0014 m). Tunnel curves are
  stored relative to their node, so they move with it.
- **Audit the remaining fixed heights:** the test cameras (`tests/modes.gd`) and
  `systems/ambience.gd:229`.
- **Done when:** every test passes and screenshots match the ones taken before the phase.

## Phase 7: clean-up and docs

- Remove the `raw_path`/PNG loader and the old-against-new comparison test.
- Remove the unused `terrain/heightmap.png`, `terrain/heightmap.r16`, `terrain/island_a.r16`,
  `terrain/island_b.r16`, `terrain/mountains.png` and `terrain/island.r16`.
- Update `README.md`, `world/README.md` and `CONVENTIONS.md`: the stamp format, blend modes,
  Seabed node, groups rule and sea level at 0.

## Risks

- **Load time:** the island stamp covers about 1 million samples in GDScript. Measured in
  phase 4.
- **Seams in the far ring:** where the coarse ring meets the detailed grid, in phase 5.
- **Testing:** Godot 4.7 is needed to run the tests; it is not installed in the cloud sessions
  by default.
