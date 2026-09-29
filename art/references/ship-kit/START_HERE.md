# Modular pirate ship kit

This is the single active structural kit. Open **previews/index.html** to inspect the actual supplied meshes. Import **canonical/assemblies/DOUBLE_DECK.glb** for the fitted example or **DOUBLE_DECK_EXPLODED.glb** to see how its layers separate.

## Structure

Nine core shells form three tiers and three longitudinal sections:

- **BOTTOM:** BOTTOM_BOW, BOTTOM_CENTRE, BOTTOM_STERN. The bilge occurs once, at Y=0.
- **MIDDLE:** MIDDLE_BOW, MIDDLE_CENTRE_GUN, MIDDLE_STERN. Uniform 2.6 m high walls. Add an entire tier for each enclosed gun deck. MIDDLE_CENTRE is an optional solid substitute for the gunport bay.
- **TOP:** TOP_BOW, TOP_CENTRE, TOP_STERN. Final 0.8 m bulwarks. No elevated bow or stern, and nothing is stacked on these.

Use FLOOR_BOW, FLOOR_CENTRE and FLOOR_STERN at every floor level. These separate 0.18 m slabs match the inner shell outlines; they contain no posts, curbs or walls. Bow walls join into one symmetric pointed prow; stern walls share one rounded outline. The lower bow/stern and the upper wall tiers meet at the same plan boundaries.

The remaining five parts are paired port/starboard stair-opening tiles and STAIRS_260. Replace solid floor tiles with START followed by END. Never overlay them. Thirteen 0.20 m rises reach a floor 2.6 m above; the 3.25 m opening ends at the top tread and continues into a solid landing. Keep at least 1 m clear on approach and exit. More ship length adds whole centre columns through every tier, including floors.

## Modeling source

**canonical/contract.json** and its **18 OBJ/GLB parts** are authoritative. All parts are supplied locally; no old version is a dependency. Dimensions are metres, X starboard, Y up, Z aft. Keep unit scale. For Blender coordinates map (X,Y,Z) to (X,-Z,Y); GLB uses Y up.

Named sockets, exact exported boundary points, dimensions and assembly transforms are in the contract. Preserve a 0.10 m zone next to each join and keep socket errors below 1 mm. Add broad wooden planks, restrained dark iron and faceted bevels away from those zones. The meshes are construction forms for a modeling pass, not finished textured assets. Touching panel solids have internal mating faces; remove those only during final assembly/optimization without changing exterior shape or sockets.

The preview sheets are rendered from these same OBJ meshes. Individual overview cells are framed separately; use the assembled examples to judge scale. No generated concept image overrides their geometry.

## Retained accessories

**accessories/** preserves the earlier mast/lookout and deck-fitting designs, including the helm. These remain separate attachments. The retained dimensions describe reference envelopes; accessories are not included in the structural fit validation. Place on the highest floor. A mast that passes through floors needs a dedicated aligned aperture in every crossed floor. Cabin/gallery redesign is outside this structural consolidation.

## Checks and regeneration

- `python tools/build_kit.py` creates every part and assembly from shared outlines, without importing older handoffs.
- `python tools/validate_kit.py canonical` independently checks exported indexed solids, winding, closure, bow symmetry, sockets, floor fits, assembled placements and sampled stair-opening clearance.
- `python tools/render_kit.py --contract canonical/contract.json --out previews` renders the actual geometry. Requires Pillow and NumPy.
- `python tools/package_kit.py` writes the single active portable ZIP. Archived work is excluded.

## Textured templates and the art breakdown

**textured/** is the canonical kit with UVs and a flat plank albedo added. Every vertex and normal is copied byte-for-byte from canonical/meshes, so the sockets are exactly where they were. Plank courses repeat every 2.6 m tier and 2 m along the hull, so they run straight across every join and stack. No light is baked in. **textured/assemblies/** places those part meshes by translation only.

**art-breakdown/** holds the finished-ship art direction: the corrected master (00), the part sheets, kit-manifest.json and generation-prompts.json. Sheet 01 is rendered from textured/meshes, not painted. The painted version drew H02 with a rocker and a wall across its join, so it is kept only in drafts/. Measure from the contract, never from a sheet.

- `python tools/texture_kit.py` builds textured/ deterministically from canonical/ meshes.
- `python tools/check_textured_kit.py` proves parity against the canonical GLBs and, independently, the OBJ faces and sockets. It records a sha256 for every file it checked.
- `python tools/render_textured.py` renders art-breakdown/01-hull-modules.png and 01b-hull-assembly.png.
- `python tools/package_art_breakdown.py` runs every check before it writes anything. It refuses a stale validation report or a sheet that no longer matches a fresh render, then writes art-breakdown/package-check.json and art-breakdown.zip.

## Parts cut from Tripo sheets

Tripo, given a whole reference sheet, returns one fused mesh: every part in one object sharing one 4096 texture, each part turned the way the sheet drew it, and the whole sheet squeezed into a 1-unit cube. `python tools/extract_tripo_sheet.py tripo/<sheet>.json` cuts it into separate parts. Each part is stood upright, squared to the axes, scaled to one stated real dimension and given its attachment origin. It gets its own texture at the source pixel density, with the atlas gutter filled so it cannot bleed in as seams. The config names every piece by its centre on the sheet, and a piece that is left unclaimed or claimed twice stops the run. The tool writes `tripo/<sheet>-report.json` and a `-parts.png` contact sheet.

Done so far:
- **Fittings** (tripo/fittings.json) into `art/models/ship/fittings/`, 17 files. The helm, capstan and rudder match the envelopes ship.gd reserves for them. The cannon barrel's origin is on its trunnion axis. The anchor stock was turned 90 degrees to cross the flukes.
- **Cabin** (tripo/cabin.json) into `art/models/ship/cabin/`, 8 files. Walls are 2.42 m, the kit's clear room height. The quarterdeck panels were flattened from about 0.45 m to the kit's 0.18 m, so the walking surface lands at 2.6 m, where STAIRS_260 arrives. The door leaf is sized to the doorway, and a threshold block across it was dropped. Tripo's 8-step stairs were dropped for STAIRS_260.
- **Whole cabin** (`cabin_house.glb`, same sheet). The separate walls cannot close a room, because their widths (2.44, 2.79 and 4.46 m) share no bay. It was first placed whole, turned so its door faces the bow; the stern castle has since replaced it. Tripo had it pitched about 1.4 degrees nose-up, which is levelled out. It is scaled so its roof, the quarterdeck, is 2.6 m up. Its stairs (about 65 degrees, too steep to walk) were fused to the front wall, so they are cut away triangle by triangle (`cut` in the config) rather than claimed as a piece. It comes out 3.80 m wide, 5.38 m long and 3.48 m to the rail tops.
- **Deck** (tripo/deck.json) into `art/models/ship/deck/`, 8 files. The six floor slabs were dropped for the canonical floors. The straight rail fills a 2 m bay and comes out 0.81 m tall, and the other rails match that height. The beam's knees keep their shape while its middle stretches to the 5.6 m span. The stair rail is sheared (balusters stay vertical) to the stairs' 38.7 degrees.

- **Rigging** (tripo/rigging.json) into `art/models/ship/rigging/`, 18 files, sized to what ship.gd already builds. Tripo drew every spar squat: its mainmast was about 4.4 times as tall as it is wide, where the game's is 22 times. Each spar is scaled by its thickness, and only the plain timber between the iron bands is lengthened, so the bands, heels, jaws and sling bands keep their shape. The mast top is sized by its hole, so it clears the 0.18 m mast head. The sails are mainly texture and shape references, because sail.gd simulates the cloth. The fixed shroud and stay ropes were dropped, because ship.gd draws ropes to fit each hull. A rope coil fused to the stays was kept as a prop.

- **Hull extras** (tripo/hull.json) into `art/models/ship/hull/`: the gunport lid (H11) and one bay of wale (H12). Tripo's hull shells were dropped; they copied the old painted sheet's errors, and the textured canonical shells replace them. The frame's opening is sized to the kit's 1.0 m gunport. The lid is exported closed, re-hung on its own hinge node, so the engine opens it by turning that one node. The wale is one 2 m bay with straight butt ends; the ship sweeps its profile rather than laying bays.

**On the ship:** props/ship/ship.gd loads these into the slots its placeholders used: the helm, capstan, rudder with its hinge strip, mainmast, topmast, mast top, both yard sizes, foremast and bowsprit. It adds a binnacle, two mast collars, the stern lantern, and a frame and open lid on every gunport. On the weather deck there are the bitts, the anchor cable and rope coils, the hatch with its grating, cleats and belaying racks. A cathead sits on each bow with its anchor, and deck beams run under the weather deck. Where a model file is missing, the placeholder is built instead.

**The stern castle and quarterdeck:**
- `python tools/build_stern_castle.py` builds the castle from the game hull's own outline (`cabin/stern_castle.glb`). Its walls stand on the hull's outer edge from z 10.4 round the stern, one 2.6 m tier high, facet for facet with the hull below and planked with the same texture. The stern's point is cut square into a flat transom about 1.2 m wide, so a window stands flat on it. A front wall closes it across the deck, and its roof is the quarterdeck.
- It replaces Tripo's cabin_house.glb, a 3.8 m box that could not follow a hull that narrows to a point over its last four metres. That model stays in `cabin/` but is not placed.
- STAIRS_260 (copied to `art/models/ship/deck/stairs_260.glb`) climbs to the quarterdeck on the port side, from just aft of the stair opening. A rail runs up each side, laid from the same parts as every other rail. Tripo's sheared stair rail (`deck/rail_stair.glb`) is no longer placed.
- Tripo's door leaf is on the front wall, shut. Tripo's arched window (`cabin/cabin_window.glb`, used as delivered, scaled to 1.1 m) is repeated along the castle's wall, the way the rail follows its path. ship.gd reads the wall's outline off the castle model, spreads CASTLE_WINDOW_COUNT windows (5) evenly round it from front corner to front corner, and centres each on the wall panel it falls on, facing out. The Ship node's `window_offset` (inspector, metres along each window's normal, negative into the wall) moves them all in or out while you look.
  - Its 4096 px texture was 64 MB of video memory for a 1.1 m window. `python tools/shrink_glb_texture.py art/models/ship/cabin/cabin_window.glb` shrank it to 1024 px, in the model and in the copy Godot extracted from it, without touching the geometry. Godot's own size limit would live in the `.import` file, which is not kept in git.
- **Pillars:** Tripo's carved pillar (`cabin/cabin_pillar.glb`, texture shrunk to 1024 px), scaled to 2.35 m. Each stands on the deck line with the bottom rim running into its base, and its capital carries the trim. They frame the castle the way the corner posts of a stern castle do:
  - one at each corner of the front wall, its outer side 2 cm proud of the castle's side. The weather deck's rail stops 0.25 m short of it on a post of its own, rather than springing out of the pillar; the gap is too narrow to slip through, and the corner pillars collide;
  - round the stern, one between each pair of windows, except that the two nearest the stern window stand on the panels either side of it, framing it.

  The Ship node's `pillar_offset` moves them in or out along the wall's normal, like `window_offset`.
- **Bottom rim:** the trim's profile again, swept round the castle's outside walls with its foot on the deck line, covering the joint with the hull. It is left off the front wall, where it would be a step in the walkway: it turns each front corner and ends inside the corner pillar's base.
- **Trim:** the wale's profile is swept round the castle's walls with its top just under the quarterdeck's edge, where the rail's base overhangs them. It runs round the stern and across the front wall, stopping either side of the stairs. At both ends it turns into the wall, so the stairs see a returned end, not an open one.
- The castle, stairs and hull collide as their exact meshes.
- The wheel, the binnacle, a rope coil and two cleats stand on the quarterdeck. The capstan is on the gun deck under it.
- **Mizzen:** the foremast's model again (4.2 m), on the quarterdeck between its front edge and the binnacle. It carries the spanker, a fore-and-aft sail laced to the mast, a boom and a gaff. Both spars are the topsail yard's model stretched to length, and they reach aft over the wheel, the boom 2.5 m up, clear of the helmsman's head. The spanker's luff is laced down the mast (`Sail.pin_luff`), so only its leech is free and it fills on either tack. Two shrouds a side hold the mast, with deadeyes just above the quarterdeck's rail. A topping lift holds up the boom's end and a peak halyard the gaff's.
- **Foremast and bowsprit:** the foremast is the M01 model stretched to 6.8 m (four fifths of the main) and thickened; the bowsprit is M07 stretched to 5.2 m and thickened as far as the knightheads allow. The jib and bobstay follow them.
- **Fore yards:** the foremast carries the main's two yard models at about four fifths of their size: the fore yard at 4.3 m (6.4 m across) with the fore course, its foot free 2 m above the foredeck, and the fore topsail yard at 6.3 m (4.2 m across) with the fore topsail laced down to the fore yard. There is a block under each arm.
- The course's foot hangs free, so a following wind swings it back toward the castle. The cloth is kept out of the castle's box and away from the mizzen's foot.

**The rail:** the solid wall round the weather deck is gone, bow to stern, and a rail stands in its place.
- `python tools/strip_game_bulwarks.py` takes the top tier off the game hull down to the deck. The tier below ends in a flat wall top, 0.2 m wide along the sides.
- `python tools/split_rail.py` splits Tripo's straight rail into a handrail, a base rail and one baluster (`deck/rail_parts.glb`).
- `python tools/rail_profiles.py` slices the handrail and base across their middles into profiles. It bakes each one's wood off Tripo's atlas into a strip that repeats every metre without a seam (`deck/rail_sweep.glb`).
- ship.gd lays a rail along any path, as follows:
  - posts spaced evenly along the whole length, at most 2 m apart;
  - the handrail and base each swept along the path as one continuous mesh, mitred at every corner, with the grain at the same density everywhere;
  - balusters spread about 0.45 m apart.
- Laid as stretched copies of Tripo's pieces instead, the rail read as a dashed line: each copy had its own rounded ends and its own stretch.
- Here the path is the centre line of the hull's wall top. On the weather deck the rail runs from the bow to the castle's front. The quarterdeck's rail runs on the castle's wall top round the stern, and across its front, leaving a gap where the stairs arrive.
- The stairs' two rails run up the slope and on into the quarterdeck's front rail as one line. On the slope the swept profile stays upright, so the handrail and base are sheared like the balusters. They stand 0.1 m outside the treads, leaving the stairs' full 1 m clear. Each has a post only at its foot and its head, with balusters all the way between. Where two legs of rail meet, their corner post stands once.
- A turn sharper than 30 degrees (the quarterdeck's front corners, the head of each stair rail) always gets a post.
- At the bow the rail ends on two knightheads. The bowsprit rests on the deck and passes over the stem between them.
- Each straight length collides as one box.

**The gunports:** `python tools/strip_game_gunports.py` takes the kit's gun-deck side walls, with their fixed holes, out of the game hull (z 4 to 12, both sides). ship.gd builds them again with a hole wherever its ports go:
- the Ship node's `gun_port_count` (inspector, 4 a side) spreads the ports evenly along that straight run, 1 m in from its ends, so 4 lands on the kit's 5, 7, 9 and 11 m;
- the walls, the frames with their open lids, and the cannons are all built from that one list, so changing the count moves them together;
- `gun_port_offset` moves the frames in or out along the hull's normal;
- the new walls are planked with the hull's own material and UV rule, and collide exactly.

**The wale and the small rigging:**
- **Wale:** swept round the whole hull at 4.4 m, between the gunport frames and the weather deck, closed round the stem and the stern. `tools/rail_profiles.py` slices and bakes the wale bay like the rail's pieces (`deck/rail_sweep.glb`). Each side follows its own outline measured off the hull, because the kit's bow is not quite symmetrical.
- **Deadeyes:** one on each shroud's foot, just above the rail, lying along the rope.
- **Blocks:** a single block under each end of the course yard and the topsail yard. The double blocks are not placed.
- **Flag:** on a short staff above the topmast, held by its three rings, and turned each physics frame to stream downwind with the breeze the sails feel. `python tools/rig_flag.py` sets Tripo's flag up for that (`rigging/flag_rigged.glb`):
  - straightens its hoist so the rings stand in one line;
  - turns the picture upright;
  - turns each ring so its hole runs up the staff;
  - moves the cloth's edge clear of the staff.

  The staff, 11 mm round, passes through all three rings (holes 13 mm).

`python tools/texture_game_hull.py` gives the game's own hull (art/models/ship/double_deck.glb, with its raked bow and bulged stern) the kit's plank texture without moving a vertex. tests/ship_fittings_check.gd fails in any of these cases:
- a slot falls back to its placeholder;
- a part sits off its mark;
- the castle's sides do not meet the hull's;
- the way up the stairs to the wheel has a step the captain cannot take, or no room for him;
- the course hangs inside the castle or through the mizzen;
- the castle's trim is off the wall, into the stairs' rails, or over a window or the door;
- the mizzen stands in a fitting, its boom comes down into the helmsman's head room, or the spanker's luff comes off the mast;
- a pillar is off the wall, not under the trim, or in a window, the door or the stairs' rails; a corner pillar is off its corner, the rail reaches into it or does not stop 0.25 m short, or it does not collide; or the stern window is not framed;
- the bottom rim is off the deck line or the wall, or runs across the front wall's walkway;
- the window's or pillar's texture is over 1024 px;
- a rail post is off the hull's edge or unevenly spaced, the rail's collision has a gap, or a wall still stands above the deck.

The curved bow and stern rails keep Tripo's curves, which do not follow the kit outlines, so they are not placed on the ship; neither are the separate cabin walls, transom, corners, door, quarterdeck panels and gallery brackets. Each report lists what was dropped and why.

See canonical/validation.json for measured results. These are geometric construction checks; final materials, collision, character traversal and buoyancy are not validated here. Existing abandoned versions live only in _archive and must not be mixed with this kit.
