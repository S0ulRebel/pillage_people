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
