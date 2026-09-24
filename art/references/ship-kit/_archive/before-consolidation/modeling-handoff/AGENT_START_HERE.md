# Modular pirate ship: modeling-agent handoff v1

Build one compatible ship family from this package. The approved PNG sheets are the visual style target. They are NOT dimensional drawings and several of their imagined joints are wrong. This package supersedes their connection geometry.

## Files to give the modeling agent

Give the agent this entire `modeling-handoff` folder and the six PNG concept sheets in its parent directory. Start with `contract.json`, the relevant file under `prompts/`, and that part's OBJ under `meshes/` when provided. `index.html` previews the exact orthographic hull drawings. OBJ files are untextured geometric starters, not finished art assets.

Use an agent that can run a 3D editor or manipulate mesh geometry. An image-only 3D generator cannot enforce this contract by itself; its output must be fitted and checked by the modeling agent afterward.

## Non-negotiable shared geometry

- All measurements are metres. X points starboard, Y up, Z aft. Bow is negative Z relative to the rest of the vessel.
- Hull family U6 is 6 m wide at the rails, with deck top Y=2.0 and bulwark top Y=2.6. A repeatable middle bay is 2 m long. The bow is 4 m long and stern 2 m long.
- The local origin of each hull part is its forward station at keel baseline. Hull and deck origins coincide; never centre these meshes automatically.
- `HULL_U6` uses the exact outer and inner profile vertices in the contract. Match positions AND edge ordering. Preserve the starter geometry in a 0.10 m band next to each mating plane. No bevel, displacement, decorative overlap or random variation in this band.
- Bow AFT joins MID FORE. MID AFT joins another MID FORE or STERN FORE. Matching interface IDs, coincident positions, opposite normals and matching roll references are required. Unit scale only.
- Connection ends remain U-shaped and open. Thickness end caps can close the wood skin; they must never span the air inside the hull. Only the bow's terminal nose and stern's terminal transom close the interior.
- Deck tiles replace each other; never stack D01 and D02. D03 and D04 are shaped end decks, not resized middle tiles.
- OBJ has no unit metadata: import explicitly at one metre per coordinate unit. For Blender convert `(X,Y,Z)` to `(X,-Z,Y)`. Do not also apply an importer axis conversion. GLB export should return the asset to the contract's Y-up coordinates. Verify this on reimport.

## Modeling sequence

1. Import H02 and D01; preserve their reference meshes in a locked collection. Style the visible surfaces with broad planks and simple material regions away from the locked seams.
2. Model H01/H03 and their shaped decks. Assemble the three supplied hull configurations before proceeding. No scaling to make the joins fit.
3. Build cabin walls, opening walls, junction posts and roof tiles. Use the cabin example below. Do not model a solid cabin box and attach galleries over its solid walls.
4. Build gallery bays around `GALLERY_18`. The inboard face is open. The host wall must be C02, not C01. Gallery floor top coincides with cabin floor; the roof underside datum is cabin Y=2.4.
5. Add stairs at the fixed floor-to-roof rise of 2.58 m. Preserve clear landings and headroom. A ladder requires a dedicated opening in the roof; a solid C05 tile must be replaced or modified as a separate hatch variant.
6. Add solid mast pieces, matching collars and lookout with a through-hole. Decorative sockets shown in old artwork do not override the contract.
7. Place helm/capstan only after checking their access envelopes. Rudder and bowsprit require separately designed host fixtures before production; their v1 briefs define envelopes only.

## Cabin and gallery placement example

Use TRADER_HULL (12 m long). Cabin floor is the existing ship deck at Y=2, not an extra slab. Cabin centreline walls span X=-2..2 and Z=6..10, giving a nominal 4x4 m footprint. Local +Z is each wall's exterior. Rotate about Y using the right-hand rule: `(x,z)` becomes `(cos(a)*x+sin(a)*z, -sin(a)*x+cos(a)*z)`.

- Forward walls: centres (-1,2,6) and (1,2,6), yaw 180 degrees. Choose one C03 door wall and one C01 wall.
- Aft walls: centres (-1,2,10) and (1,2,10), yaw 0. Use C02 opening walls with two G01 bays. Gallery origins (-1,2,10.1) and (1,2,10.1), yaw 0.
- Port walls: centres (-2,2,7), (-2,2,9), yaw -90. Use C01 at Z=7 and C02 at Z=9. G02 origin (-2.1,2,9), yaw -90.
- Starboard walls: centres (2,2,7), (2,2,9), yaw +90. Use C01 at Z=7 and C02 at Z=9. G03 origin (2.1,2,9), yaw +90.
- Junction posts: at each unique wall endpoint, Y=2; do not duplicate shared posts. Include the four corners and four side midpoints.
- Four C05 roof tiles: origins (-1,2,6), (1,2,6), (-1,2,8), (1,2,8), yaw 0. Roof top is world Y=4.58.
- Stair example: A01 origin (1,2,2.7), yaw 0, upper end at (1,4.58,6). The forward starboard cabin wall is C01, so stairs do not obstruct its door. Door belongs to the port half. Reserve roof landing X=.5..1.5, Z=6..7.

This arrangement is a coordinate recipe, not a finished collision-tested cabin. The gallery underside extends below floor level: verify it clears the exterior hull before adding brackets. Side galleries occupy X up to +/-2.9 within the 6 m rail beam, but need local clearance checks where their support brackets meet the bulwark. Do not hide collisions with decorative trim.

## Acceptance checks for finished models

- Reimport each GLB: exact metre scale, origin, axes and socket transforms survive export.
- Each hull interface vertex deviates by no more than 0.001 m; compare against its starter ring, not the adjacent model's potentially wrong ring.
- Check both rendered exterior and walkable interior for gaps, doubled faces and obstructions. Assembly seam thickness caps may be suppressed at joined instances; never delete exterior skin.
- Check normals, zero-area triangles, non-manifold edges, collision shapes, open hatch access and stair headroom in the actual 3D editor.
- Keep planks readable at gameplay distance. Do not put detailed noise into the silhouettes or modify the fixed connections for aesthetics.
- Deliver one GLB and source file per part, named socket empties, collision geometry, orthographic front/side/top PNGs, plus a report of measured bounds and connection errors.

## Scope and verification

`build_handoff.py` generates seven hull/deck starter meshes and three assembled hulls. `validation.json` records numerical hull ring comparisons only. The rest of the parts are modeling briefs, not completed meshes. This is a first family, not a universal ship constructor. Different beams or deck heights need a new versioned interface family.

Gunport hulls are deliberately excluded: the previous concept has gunports below the main deck but no defined gun deck. Do not cut holes into H02 and call the result validated. Rigging, sails, physics, buoyancy and gameplay integration are outside this handoff.

Run `python build_handoff.py` to regenerate the package. It overwrites its generated files; keep agent-produced final models in a separate output directory.
