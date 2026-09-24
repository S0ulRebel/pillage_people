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

See canonical/validation.json for measured results. These are geometric construction checks; final materials, collision, character traversal and buoyancy are not validated here. Existing abandoned versions live only in _archive and must not be mixed with this kit.
