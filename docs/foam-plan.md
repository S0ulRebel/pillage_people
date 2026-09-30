# Sea foam: the plan

The plan for making the sea's foam look like the art references, written before any of it is
built. It covers what the references draw, why ours differs, what the research on other games
found, what was decided, and the build order.

References: `art/references/terrain-water-and-shore-transitions.jpg`, panels 9 (wet to dry
sand, surf) and 10 (shallow water to beach, calm), and the "Foam patterns", "Shoreline foam"
and water-type swatches in `art/references/water-rock-wood-plant-studies.jpg`.

## Decisions

- **Foam goes on the sand too.** Tongues run up the beach, lace is left on the wet sand,
  there's a wash line, and wet sand dries.
- **The sand colour changes island-wide** toward the reference. The reference's dry sand is
  paler and less orange than ours, and its wet sand is greyer, not more orange.
- **We judge from the gameplay camera, as true to the reference as possible.** Every step is
  judged from in-engine captures on a real beach, side by side with panels 9 and 10, and
  repeated until it matches, the way the clouds were done.

## What the reference draws

Sizes are in character heights (CH, the pirate, about 1.9 m), the only scale the paintings and
the game share. They were measured on small JPEGs, so read them as approximate.

- **The front** sits right on the waterline, with no clean water between sand and foam. It is a
  thick, bright, bubbly band whose thickness varies about 4× along it (0.09-0.38 CH). Big rounded
  tongues push up the beach about 2-2.5 CH apart, and both edges are chains of small bubble
  scallops. In places the front curls round a pocket of wet sand filled with froth. Its seaward
  half has round see-through holes.
- **Lace, seaward.** A net of closed cells with hairline walls and fat junctions. The cells grow
  3-4× with distance from the front, and the lace thins from about half cover to nothing by
  about 1.5 CH.
- **Lace, landward.** A fainter net left on the wet sand, then beaded lines, then a beaded wash
  line at the highest reach.
- **Wet sand in three steps**: dark wet, damp, dry. The wet/damp edge is sharp and carries the
  wash line.
- **Colour.** Three tones of off-white: lit on the landward side, mid, and a darker, see-through
  tone seaward. Never pure white, never cyan, hard edges, no glow.
- **Calm water (panel 10).** The same grammar, shrunk: a thin lobed line and a short fringe.
  The net in the clear shallows there is caustics, which are cream, even and under water, not
  foam.
- **Rocks and objects.** A thin, broken contact line, never a filled halo. In the surf, lace
  collects round them.
- **Offshore.** Thin dashed white lines along the wave crests, joining into cells in choppy
  water, with small splashes at the peaks. More of them the rougher the sea.

## What ours does, and why

Measured on `tests/material_views.gd`'s shore captures.

| | Reference | Ours |
|---|---|---|
| Where the front sits | on the waterline | about 1 m out to sea, clean teal between it and the sand |
| Front | thick, bubbly, tongues, 4× thickness range | a smooth, even ribbon (2×), broken into segments |
| Lace | cells behind the front and on the sand | none; two rows of ruled dashes |
| Sand | three wet steps, wash line | one soft, too-orange wet band |
| Colour | three off-white tones | one cyan-tinted white |
| Rocks and crates | thin broken contact line | filled mint discs |
| Shallows | clear, sand shows through | nearly opaque teal |

The causes in the code:

- The shore foam in `world/ocean.gdshader` (section 4) is a line of equal water depth warped by
  noise. A contour of a smooth field is a smooth ribbon, and because it follows depth, not
  distance, its width changes with the slope of the beach.
- The sea shader discards every pixel above the waterline (`if (thickness <= 0.0) { discard; }`
  in section 1), so it can never draw on the sand.
- The object halos sample the top-down `band_mask` at 8 points round each pixel. That can only
  make a filled strip along the outline.

## What the research found

How other games make foam, from search results and source code read on GitHub (most sites
blocked page fetches, so much of it is from search summaries).

- **It isn't only the shader.** Games combine four tools:
  - *The water shader* draws the shoreline band, from distance to shore or depth, cut through a
    painted foam texture (Sea of Thieves, Unity's Boat Attack, A Short Hike, Stylized Water 2).
    Every game found that shows lace gets it from a texture, not noise.
  - *Meshes* for coast strips with a scrolling foam texture (Wind Waker's shore planes,
    Bad North and Townscaper's coast skirt, RiME's hand-placed foam) and for wakes.
  - *Particles* for bursts: splashes and spray. Never lace.
  - *Off-screen textures* that the water reads: foam around objects (Sea of Thieves), wakes
    (Boat Attack).
- **Foam memory** is a top-down texture that follows the camera. Every frame it copies the last
  frame's foam (shifted by how far the camera moved), fades it a little, and stamps new foam
  from ships, crates and crests. It needs two textures swapped each frame and 16-bit precision,
  or the fade rounds to nothing and foam never disappears. It is for wakes and trails that
  linger. A beach doesn't need it: waves arrive on a cycle, so the time since the last one can
  be calculated.
- **No flow map is needed.** A flow map moves foam along a painted direction field (rivers,
  water round rocks). The direction toward the shore comes from the shore distance field below.
  A flow map could be added later for foam drifting along the shore.
- **Waves reaching the island.** Real waves slow in shallow water, so their crests bend until
  they arrive parallel to the beach and wrap round the island. That is *wave refraction*; they
  also get shorter and taller before breaking (*shoaling*). Games fake it with a **shore
  distance field**: a texture holding the distance to the shore for every point, with waves
  drawn as lines of equal distance that march inward. The direction toward the shore is that
  field's gradient. The known catch is that pure distance lines copy the coast as rings round
  headlands, which games break up by giving each stretch of shore its own wave timing and
  height. Outerra, Far Cry and Assassin's Creed III drive shore foam from distance to shore;
  Crest and Boat Attack calm the swell in shallow water.
- **The sand has to take part.** Unreal's water tools and the shoreline tutorials found draw
  wet sand and foam in the landscape material, from its distance to the water. The alternative,
  a see-through mesh over the sand, was measured on our island to float off the water in the
  spyglass and to bury itself under the sand in places.
- **The transparent part** isn't water geometry. The thin sheet of water running up the sand
  is drawn by the sand shader: sand darkened and cooled wherever the run-up currently covers
  it, with foam on top. The clear shallows are the sea shader's refraction, made much clearer in
  the first metre or so of depth.

Rejected: water simulation (too heavy and too realistic for the look), particles for lace, a
coast mesh, a foam memory buffer for the beach, and depth-buffer halos round objects (the
project already rejects view-dependent outlines).

## The plan

1. **Shore distance field.** Computed once at load from the terrain heights: for every point,
   the signed distance in metres to the still waterline, and the direction to it. Shared with
   the sea and the sand shaders. Everything below is driven by it.
2. **Shore waves.** Near the island, waves march inward along lines of equal distance, so they
   wrap round the island and arrive parallel to every beach. Each stretch of shore gets its own
   timing and height so the lines never copy the coast as rings. Out at sea the existing swell
   keeps running and calms as the water gets shallow. The shore waves keep the swell's period,
   so each crest rolls in and becomes the next foam front.
3. **Run-up.** One function in a shared shader include, used by the sea and the sand shaders on
   one clock. Each wave runs up fast and drains slowly, and every few waves a bigger one
   arrives. It also returns how old the foam at a point is and how long ago the sand there was
   last wet, which drive the lace and the drying.
4. **Front and lace.** One lace pattern texture, storing the distance to the nearest lace line,
   thinned and broken up as the foam ages. It draws the thick bubbly front, the lace trailing
   out to sea, the leftover lace on the wet sand, and the whitecaps. Foam is three off-white
   tones.
5. **Sand.** The sand shader (`world/terrain.gdshader`) draws everything above the waterline:
   the tongues, the sheet of water on the sand, three steps of wet sand and the wash line. The
   sand is recoloured island-wide toward the reference.
6. **Clearer shallows.** Much clearer water near the shore, so the sand and the lace show
   through, as in panel 10.
7. **Rocks and crates.** The existing top-down `band_mask` turned into a distance, drawn as a
   thin, broken contact line instead of the mint discs, with lace round rocks in the surf.
8. **Whitecaps.** Lines where our waves bunch up at their crests, more of them in rougher
   seas, with small splashes where crests cross.
9. **Wakes.** Foam memory, for ships and crates only. Last.

## How it's judged

- In-engine captures from the gameplay camera on a real beach, side by side with panels 9 and
  10, after every step, plus the low view from the sea and the spyglass.
- The clock is frozen for captures so frames compare fairly.
- The existing tests that look at the sea (`material_views`, `outline_probe`, `sun_view`,
  `underwater_view`) keep passing, or are updated with the reason written down.

## Risks and unknowns

- Nothing has been measured on an iPad. There is no frame-time baseline for the sea yet; one is
  taken before the work starts.
- Whether the Mobile renderer on older iPads filters the float textures the distance field
  needs, and how a bake at load behaves there.
- The sea and the sand are lit differently today (the sand takes palm and cloud shadows), so
  foam crossing the waterline must use the same light on both sides or it will show a seam.
- The distance field must not let the run-up climb cliffs or paint over narrow islets: it is
  capped by slope and kept off rock.
- The Python mockups made during the research did not look like the reference (the best was
  judged about half-way). The shapes are the hard part, which is why every step is judged
  against the reference in-engine rather than trusted from a sketch.

## Progress

### Step 1: the shore distance field (done)

- `world/shore_field.gd` bakes it from the height map when the terrain first needs it: 513 x 513
  texels, 1.2 m apart, about 0.4 s. The waterline is found between height samples; an exact
  distance transform finds each texel's nearest waterline point, and a refinement pass near the
  shore (within 45 m) makes sure it is the truly nearest one, so the contours don't kink.
- Each texel holds the signed distance (+ sea, - land) and the nearest waterline point, so the
  direction to the shore and "which stretch of beach" both come from it.
- `terrain.gd` owns it (`shore_field()`, rebaked after any restamp) and hands it to the sand's
  and the sea's materials (`apply_shore_field()`). Both shaders read it through
  `world/shore_field.gdshaderinc`. Nothing draws from it yet.
- `shore_field_preview` on either material draws the field: metre bands, a white line every
  5 m, red on the waterline.
- `tests/shore_field_check.gd` (headless) checks it against the ground at 600 points: sign,
  nearest point on the waterline, no closer shore missed. Worst distance error 0.56 m.
- `tests/foam_view.gd` is the judging harness: the water clock held (new `Ocean.hold_clock`),
  the captain on a real beach, the gameplay camera's pitch and lens, captures at the panels'
  scale (7 m of arm, where the captain is the panels' size - play's default 18 m shows him at a
  third of that) and at 18 m, each side by side with panels 9 and 10.

### Step 2: shore waves (done)

- Near the island the swell hands over to shore waves (`world/waves.gdshaderinc`): their crests
  are lines of equal distance to the shore, so they come in parallel to every beach and wrap
  round the island. They take over from 40 m out (`shore_wave_reach`) and are the only big
  waves within the last third of that (`shore_wave_calm` 0.9 of the swell handed over).
- They keep the long swell's period. Each stretch of coast gets its own timing and height from
  smooth sines of its nearest shore point, so neighbouring stretches differ without a seam, and
  a slow swell of height gives a bigger wave every fourth or so (sets).
- They keep full height down to 0.6 m of water (`shore_wave_shoal`), where the swell flattens
  over 2.5 m: otherwise they were gone before they reached the beach.
- One sum, three places, kept identical: the sea's mesh and its per-pixel slopes
  (`ocean.gdshader`), the underwater view's copy of the surface (`underwater.gd` mirrors the new
  uniforms), and the CPU surface things float on (`ocean.gd`, which reads the shore field at the
  same half precision the GPU filters). `tests/underwater_view.gd` measures the shader and the
  CPU agreeing to 0.1 mm; its 9 mm shader-to-mesh difference in the shallows was 8 mm before
  and is not from this.
- Tunable on the Ocean node, "Shore Waves" group. `wave_preview` on the ocean material draws the
  surface's height, for seeing them; `tests/foam_view.gd` captures it over the coast at three
  moments.
- On their own they barely show from the gameplay camera: the toon shading hides small slopes,
  and a wave reads top-down by its foam. They are what the run-up (step 3) and the foam (step 4)
  ride.

### Step 3: the run-up (done)

- `world/runup.gdshaderinc`: every shore wave that reaches the waterline (two, by default,
  make one run-up - `runup_waves`) sends a sheet of water up the beach, fast then slowing, and
  drains back slower, past the still waterline down to `runup_drawdown`. How far each reaches
  is the lesser of `runup_reach` and what `runup_height` of climb allows on the slope there, so
  flat beaches get long run-ups and rock almost none; it changes wave to wave, is biggest every
  fourth, and bulges into tongues along the shore.
- Being a formula, it knows its own history at every point: how long since the edge last ran
  up over it (the foam's age, for step 4) and how long since it came out of the water (the
  sand's drying, for step 5).
- One clock: `ocean.gd` now pushes its water clock into the sand's material too, and the
  run-up's settings to both (Ocean node, "Run-Up" group). Each run-up starts as its stretch's
  shore wave reaches the waterline.
- The sand draws the sheet of water over itself (cooler, darker: `swash_tint` on the terrain
  material); the sea thins to a film where the backwash has pulled back below the still
  waterline. `runup_preview` on either material shows the water (blue), the foam's age (white)
  and the drying (orange); `tests/foam_view.gd` captures four moments through one run-up, as
  drawn and in the preview.
- With the defaults it reaches about 2 m up this beach - the captain's feet - where p9's lace
  and wash line sit 1.5-2.7 m up. On its own it shows only as a darker sheet over sand that is
  already dark; the foam (step 4) and the wet sand (step 5) are what make it read.

### Step 4: the front and the lace (first pass, done)

- `world/foam.gdshaderinc`, drawn by the sea on its side of the still waterline and by the
  sand on the other, from the same inputs, so it crosses the waterline without a seam. The old
  noise ribbon and its dashes in `ocean.gdshader` are gone (and its `foam_depth`/`foam_speed`).
- Foam is born at the front and ages: its age is the run-up's (how long since the edge ran over
  the point), and out past the swash, how long since the last shore wave's crest went over
  (a much shorter life, `foam_surf_life`, within `foam_surf_width` of the shore).
- The lace is cut from one texture of round cells made at load (`world/foam_lace.gd`, 256 x 256,
  eight cells a side): each texel holds the distance to its cell's centre, the distance to the
  nearest wall, and a random number for the cell. Two measures at once make panel 9's lace: WALLS
  (foam near the line between cells - even hairlines) and KNOTS (foam far from every centre - the
  fat junctions). Fresh foam is solid with a few windows; the walls thin to hairlines; each cell's
  half of each wall breaks at its own moment; the knots shrink to beads and go. Two sizes of cell
  at once, holes from both, so the cells are uneven and there is no seam between sizes.
- The front's leading edge is pushed out round small bubbles; the run-up's reach is shaped along
  the shore by the same cells at tongue size (squared, so the tongues have round tips and sharp
  cusps between). While a run-up drains a thinner line rides its edge, thick and thin by turns.
- The sand keeps what the last run-up left: fainter, creamier lace that pops as it dries, and a
  beaded wash line at the highest reach, faded where it would be thinner than a pixel (from far
  off it traced the whole coast).
- Three tones measured off panel 9: lit on the fresh foam, mid as it ages, the darker
  see-through tone on the holes' rims. Settings: the Shore_Foam group on either material.
- Against the panels at their scale, the foam now has their grammar: scalloped front, lace with
  thin walls and fat knots, tongues, wash line. Still off: the front at its thickest is thinner
  and less white than p9's; the wet sand is one dark band with a hard edge where the water
  starts (step 5); the water past the foam is flat opaque teal, where the panels' is clear
  (step 6); the object halos are still the old mint discs (step 7). Not measured on an iPad.

### Step 5: the sand (done)

- Three steps, as panels 9 and 10 paint them, replacing the fixed height band: DRY; DAMP where
  run-ups can reach (1.6 x a full run-up's reach on the slope there, `damp_sand_reach`), fading
  softly into dry along an edge that wanders in and out; WET wherever a run-up has been in the
  last `wet_sand_hold` (7) seconds - a sharp edge that moves with every wave, carrying the wash
  line.
- Colours worked back from the panels through the ground's lighting (terrain.gd exports
  `dry_sand_colour`, the new `damp_sand_colour`, `wet_sand_colour`). Island-wide: the sand is
  paler and much less orange. Rendered on the test beach against panel 9:
  dry (212, 172, 124) against (226, 181, 127); damp and wet were 0.73 and 0.60 of dry
  against the panel's 0.76 and 0.63, and were brightened by 8% to match. The dry sand stays a
  little darker than the panels': the sun lights it at about 0.84, and a colour can't be
  brighter than white.
- `tests/ground_check.gd` and `tests/material_views.gd` pass.

### Step 6: clear shallows (done)

- The cause of the opaque teal: the sea measures how much water the eye looks through from the
  depth buffer, and under the Mobile renderer in the test captures that buffer came back empty
  over the whole sea. Every pixel saw the far plane, the path ran to its 52 m cap, and the
  shallows were as opaque as the deep sea - the seabed, its caustics and the wet sand hidden
  under flat teal. Where the buffer has nothing, the path is now the water column over the
  seabed (the height map) along the eye's slant. Whether the buffer is empty on an iPad too is
  not known; with it working, the two measures agree.
- Absorption retuned (it had been set against the broken 52 m path) and a new `inscatter`
  (the water's own colour added per metre, in every channel) against panel 10's shallows. The
  18 m view now measures (36-58, 163, 141-150) a few metres out, against the panels'
  (30-70, 128-167, 134-157); the seabed, its weed and its caustics show through, as in the
  panels' "shallow (sand)" water. Close up the water is still a little greener than panel 9's.
- `material_views` passes, with the caustics now changing 12,701 samples through the water
  against 5,789 before. `underwater_view` fails only on its 9 mm shallows difference, as it did
  before step 2. `sun_view` fails its horizon check (a step of 0.087 between rows) - and fails
  it with the files from before this step too (0.081), so it is not from this.
- `tests/foam_view.gd` also captures the close view with the sea hidden (`seabed_close.png`).

### Step 7: rocks and crates (done)

- The filled mint discs are gone. The overhead mask (`band_mask`, 28 cm a texel) is filtered,
  so across a silhouette's edge it ramps from one to nought over about a texel; its value over
  its slope is the distance to the edge, to a few centimetres. A thin contact line
  (`object_line_width`, 7 cm) is drawn there, thickest on the side the waves come from and a
  third as thick away from them, broken into pieces by the lace cells (`object_line_gaps`),
  and faded wherever it would be thinner than a pixel so that from far off it is no outline.
- The darker water hugging panel 10's rocks is the rock under the water, which the clear
  shallows (step 6) now show by themselves.
- Lace caught round rocks in the surf was tried (eight taps round each pixel, aged outward
  from the object): at the mask's resolution it came out as grey smudges, not lace, and was
  taken out. Splashes on rocks in heavy surf remain for later.
- The old `object_band_*` settings went with the discs.

### Step 8: whitecaps (done)

- The old strokes (the swell's phase bent by noise and thresholded) sat nowhere near the real
  crests and came out as detached dashes. Whitecaps are now thin lines (`crest_line_width`,
  11 cm) along the front of the two long waves' crests - the swell's, and from a fair day up the
  second wave's, which runs another way, so the two sets cross as the sea gets up - bent a
  little by the other waves, broken into dashes by cells a couple of metres across, and shown
  only where the four waves summed by steepness run high (which is also where a Gerstner
  surface folds, and a crest would break), so each crest line comes in pieces of every length.
  Where the sum runs highest the line swells into a tuft.
- `crest_strength` is the sea state: 0 none, 0.3 (the default) a fair day, 1 a storm; it lowers
  the level the sum must pass and closes the gaps.
- Tried first: lines along a level of the four-wave sum itself. Four waves crossing at angles
  peak in isolated spots, so its levels are short arcs round each peak, and its tufts came out
  as holed ovals; taken out.
- `tests/foam_view.gd` captures open water 70 m out (`open_sea.png`) and counts the near-white
  share: 0.5% at the default - counting only near-pure white; the references' swatches are about
  1% calm, 4% choppy, 6% stormy.

### Step 8b: detail waves (done)

- Four regular waves crossing make a sparse, repeating pattern of crests, and what is drawn
  from them came out sparse and regular. Six short DETAIL waves now sit on top of them
  (`Detail_Waves` on the ocean material: `detail_strength`, `detail_longest` 3 m, each next one
  0.78 as long and a little weaker, fanned round the swell's direction). They go into the
  shading and the whitecaps only, not the mesh or anything floating: waves this short barely
  lift a barrel, and keeping them out of the displacement keeps the drawn surface and the one
  things float on the same.
- In the shading they show as fine ripples in the middle distance and a sun streak broken into
  glints; close up the toon bands still hide most of them.
- The whitecaps count them: where they pile onto a crest it breaks, where they dip it does not,
  so each crest line comes in shorter pieces. The two detail waves nearest the swell's direction
  also get short dashes, bent along the swell so they arc, only where the sea runs clearly high,
  so they cluster on the big crests. Every dash, long or short, is a tapered brush stroke - full
  width in the middle of its cell, narrowing to a point - not a line cut off square.
- Tried on the way: dashes on all the longest detail waves, straight, crossed into sticks and
  X's like scratches (2.4% white); aligning them to the swell and bending them fixed it.
- Open water 70 m out from the gameplay camera: 0.7% near-white at the default fair-day
  `crest_strength` 0.3 (references: about 1% calm, 4% choppy).

### Step 8c: the chop, and hairline whitecaps (done, replaces 8b's dashes)

- The detail waves became the CHOP (`Chop` group on the ocean material): six waves from
  `chop_longest` (5 m) down, within 18 degrees of the swell's direction so their crests line up
  in rows, shading the open water in three hard tones (`chop_tone`): darker in the troughs and
  on faces turned from the eye, lighter on the tops. Still shading only - not the mesh, not what
  floats. Fanned wider (50 degrees) they blurred into blobs.
- Whitecaps are now one high level of the chop's height, on the front of each small wave, drawn
  `crest_line_pixels` (1.4) pixels wide at any distance: hairlines along the crests of the rows,
  gathering on the swell's crests, joining up as `crest_strength` rises. Tufts at the tops were
  tried and came out as fat white ovals; not drawn.
- `tests/foam_view.gd` now also frames open water like the reference's water-type swatches
  (8 m up, 30 degrees down) and puts it beside the calm, small-waves and choppy swatches
  (`compare_water.png`). Open water from the gameplay camera: 1.5% white.

### Step 8d: whitecaps as crest lace (done, replaces 8c's hairlines)

- The references' whitecaps aren't lines: they are the shore foam's pattern - the walls of a net
  of cells, zigzagging and branching like lightning, meeting in knots. So the whitecaps are now
  the lace texture's cell walls (two sizes, 0.9 m and 0.45 m, the smaller only mid-strip),
  squeezed across the crests and bent by the chop so most walls run along the waves, shown only
  in a strip along one high level of the chop's height. Each cell's half of each wall comes and
  goes with its own random number, so on a fair day the strip is broken zigzag chains; as
  `crest_strength` rises the strip widens and the chains join into the net. Small beads where
  walls meet; faded where a pixel spans more than a quarter metre.
- Tried on the way: the whole crest band as lace came out as fat white patches with honeycomb in
  them, and solid tufts as blobs; the strip and thin walls fixed it.

### Step 8e: whitecaps tuned

- One net of larger cells (1.2 m, squeezed 1.4x across the crests), a narrower strip on a fair
  day: mostly one branching chain per crest rather than closed cells. The finer second net put a
  spike on every chain and is out.
- Walls taper from full on the crest line to nothing at the strip's edges, a little wider or
  narrower cell by cell; knots are round beads (distance from the cell centre less a share of the
  distance off the wall), not stars.
- A pale glow round the white, the swatches' way: the same walls and beads, wider, in the foam's
  mid tone.
- Open water from the gameplay camera: 1.5% white.

### Step 8f: ridged-noise whitecaps, and the swatches' blue

- Colours measured on the "small waves" swatch against ours: ours were greener and flatter (the
  lit tone only 14 levels above the mid, the swatch's about 50). Offshore colours moved bluer
  (`lagoon_colour` (0.02, 0.45, 0.68), `deep_colour` (0.03, 0.31, 0.56)); the chop's dark faces
  now darken toward blue (0.7, 0.72, 0.8 of the mid) and its tops lift in green and blue. Measured
  dark / mid / light: ours (7, 79, 130) / (9, 93, 144) / (60, 140, 174) against the swatch's
  (1, 80, 138) / (5, 112, 172) / (39, 168, 220).
- Whitecaps are ridged noise (the art director's read of the swatches): value noise folded at
  its middle, |2n - 1|, is zero along sharp creases that zigzag and wander. Each crease is drawn
  a fixed number of pixels wide (its value over its own slope), widest on the crest line and
  thinning to nothing at the strip's edges, with a pale glow round it; three octaves, each finer,
  each shown only near the coarser one's creases, so the fine ones grow off them as branches. In
  the crest-aligned frame, so most run along the waves. Replaces the cell net.
- Tried: thresholding the ridged value itself gave fat blobs where the noise is flat; laying the
  cell net along the height contours gave glyph-like scribbles.
- Open water from the gameplay camera: 2.6% white.

### Step 8g: light through the crests (subsurface scattering, painted)

- The swatches' small waves glow a lighter, saturated turquoise on the thin upper part of each
  face, just under the crest: light through the water. Painted, not simulated: one flat toon
  step on the chop's face turned toward the eye, high on the wave but below the whitecap strip,
  in `sss_colour` (0.16, 0.7, 0.9) at `sss_strength` 0.85 - strongest looking toward the sun,
  never gone (the sky lights it too). It replaces the plain lighter tone on the tops, which read
  grey. Measured light tone now (33, 134, 181) against the swatch's (39, 168, 220).

### Step 8h: whitecaps as a net of wave cells

- The ridged noise read as random whirls, not the swatches' little nets of white on the waves.
  Now each small wave is a cell of a Voronoi net (`wave_cells`), 5 m along the crests and 2.4 m
  across, bent by noise so the crests arch, drifting with the waves. A cell's walls are the net:
  the wall behind each cell is its wave's crest line, the slanting ones are the connectors that
  join crests. `crest_strength` (0.45 by default) decides how many walls show: most crest lines
  and some connectors on a fair day, all of them in a storm; gathered a little onto the swell's
  crests.
- Each shown wall is a band of the shore foam's own lace (`foam_holes`, 0.3 m cells): solid on
  the crest line, opening into a net further from it, beads at its edge. Wide where the wave is
  breaking (a noise along the crest), a beaded hairline where it is not, widest where walls
  meet, and spilling further down the face than over the back. Too far to see as lace, a
  beaded plain line. A soft pale-turquoise glow runs down the face under it.
- The faces are shaded from the cells too: one soft gradient per wave from turquoise just under
  its crest (the painted light through it) to dark in the trough above the next crest - so the
  shading follows the same waves the white sits on. Softer seen from above.
- The swatch comparison now looks into the swell, as the swatches are painted.
  `FOAM_SEA_ONLY=1` makes tests/foam_view.gd render only the open-sea views, for tuning.
- Open water from the gameplay camera: 1.1% white.

### Step 8i: whitecaps, second pass

- Fluffier foam close up: each crest is a solid core whose edge bulges into round lobes (one per
  cell of a larger, turned lace lattice), with a fringe of the small lace round it - open net,
  then beads. It was a scalloped ribbon of even lace.
- The glow under a crest is measured from that wave's own crest line (`wave_cells` now also
  returns the distance to the crest behind and its random number), not from the nearest wall,
  and fades out toward the cell's other walls, so it no longer stops hard at a connector.
- The crests reach further: far off they are drawn at least most of a pixel wide, and fade out
  over 0.2-0.45 m a pixel and 80-200 m, not 0.12-0.3 m and 55-150 m.
- Open water from the gameplay camera: 1.4% white.

### Step 8j: whitecaps, joins and beads

- Where two walls meet, each drew its foam only up to the line half-way between them, so the
  foam of a junction had a straight seam. `wave_cells` now also returns the second-nearest wall
  (distance, direction, random number), and the white is drawn from both walls
  (`crest_wall_foam`, once each, the larger kept): junctions are one lump of foam.
- The fringe round each crest was the small lace's walls breaking, which read as hooks. It is
  now only the lace's knots - round beads, shrinking outward.
- Open water from the gameplay camera: 1.4% white.

### Step 8k: PROTOTYPES - a painted lattice, and whitecap events

Two other ways to draw the whitecaps, from the research (Wind Waker's ocean texture; Sea of
Thieves' foam; stylized-water breakdowns), switchable with `whitecap_style` on the ocean
material to compare against the net (0, still the default):

- 1, a painted lattice. One tile (world/wave_lattice.png, 18 m, made by
  tools/make_wave_lattice.py) painted like the swatches: rows of overlapping arched crests,
  white on part of each, beaded, with dots, breaking clumps and diagonal connectors down to the
  next crest; its green channel shades each face from under its crest to the trough, its blue
  is the glow. Laid in the crest frame drifting with the waves, wobbled by a few sines, and a
  second copy turned 20 degrees and smaller blended in by a slow noise so it does not repeat.
  Read from the PNG at load (no import step) while it is a prototype.
- 2, whitecap events. The net's crest lines as hairlines only; on them, each wall breaks every
  `event_period` (7 s) with chance `event_rate` (0.4), at its own moment: white born at the
  wall's middle, spreading along it and down the face in the first third of its life, a solid
  lumpy core that shrinks while lace of two sizes opens round it, then gone.
- tests/foam_view.gd with FOAM_STYLES=1 renders styles_low.png (choppy swatch | 0 | 1 | 2),
  styles_gameplay.png (0 | 1 | 2 from the gameplay camera) and events_time.png (style 2 at
  four moments 1.2 s apart).

### Step 8l: the painted lattice with whitecap events on its crests (now the default)

- `whitecap_style` 3, the default: the painted lattice (style 1) as the base - its crest lines,
  beads, clumps and connectors, its face shading and glow - with whitecap events breaking along
  the lattice's own crests, not the net's walls, so the white that comes and goes sits on the
  painted crests.
- The tile's alpha now says which crest is above each point (a random number per crest,
  tools/make_wave_lattice.py), read unfiltered (`wave_lattice_ids`) so it is never blended
  between two crests. Each crest is cut into 6 m stretches that break on their own
  (`lattice_event`): white born at a point on the crest, spreading along it and down the face
  (the tile's green, in metres, is the distance down from the crest), then lace and gone - the
  same life as style 2's (`whitecap_event`, now shared).
- `event_rate` 0.3, `event_period` 7 s.
- The net (style 0) and the two prototypes alone (1, 2) stay switchable for comparing; the net
  code can go once this is settled.
