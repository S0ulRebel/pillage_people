# Ship floors: additive v2 modeling handoff

Use this specification for ships with two or three walkable decks. The original single-deck v1 handoff remains unchanged.

## How the levels connect

1. Place the v1 curved H01/H02/H03 lower hull ONCE.
2. Omit every v1 D01–D04 floor. Their Y=2.0 floor datum belongs to the old single-deck layout.
3. Place the shaped v2 F_BOW/F_MID/F_STERN floors at Y=2.6. This is the first walkable deck. It is above the curved hold, not the floor of the bilge.
4. Place U_BOW/U_MID/U_STERN wall sections at Y=2.6. They extend to Y=5.2. Their footprint matches the lower hull rail edges, and they have no built-in floors or ceilings.
5. Add F floors at Y=5.2 for the second deck. Repeat U walls and F floors at Y=7.8 for a third deck.
6. Add the matching R bulwark modules ONLY on the highest deck. Remove these when adding another full-height U tier. Never stack a new U wall on top of a 0.6 m R bulwark.

All dimensions are metres. Axes and Blender conversion are inherited from the base handoff. Wall levels are exactly 2.6 m tall; floors are 0.18 m thick, leaving 2.42 m clear room height. Upper walls keep a constant footprint: a tapered upper hull would require a different interface family.

## Openings and access

U_GUNPORT_MID replaces U_MID on a gun deck. Each opening starts 0.8 m above that deck and ends at 1.6 m, with a 1 m width along the bay. This corrects the older art's undefined below-deck openings. Position the actual cannon carriage and barrel against the aperture before approval.

F_STAIR_PORT or F_STAIR_STARBOARD replaces the corresponding solid middle floor. Use an opening tile followed by its matching _END tile. Together they create a clear 1.1x3.25 m shaft; the final 0.75 m of the second tile is solid landing, meeting the top tread without a gap. Do not overlay solid tiles beneath these openings. A_STAIRS_260 has thirteen 0.20 m rises, a 3.25 m run and 1 m width. Preserve the additional space for headroom and landings.

The examples stagger stairs: first-to-second deck uses port bays at Z=4 and 6; second-to-third uses starboard bays at Z=8 and 10. This keeps the next flight's base on a solid floor instead of over the lower flight's shaft. Keep at least 1 m of clear approach and exit landing. Add guards around open shafts without blocking access.

## Cabins and fittings

Move cabin floor origins to the highest deck's Y datum. Cabin roofs still rise 2.58 m from their floor, so use v1 A01 stairs there; the new 2.60 m stairs are for full ship levels only. Do not round one to the other. Gallery floors move with their cabin and require the prescribed open wall; inspect underside bracket clearance against the hull/bulwark.

For a through-deck mast, create an explicit mast-hole tile at every crossed floor and lock all hole centres to one vertical axis. Never extend a mast through solid F tiles. Through-deck mast tiles are not included in these two blockouts; v1 mast parts may instead sit entirely above the highest deck.

## Modeling-agent instructions

Read `contract.json`, use `meshes/` as locked reference geometry, and follow the brief under `prompts/` for each part. Style with the existing PNG references, but never derive connection dimensions from those pictures. Preserve the first/last 0.10 m next to connection surfaces and keep socket errors below 0.001 m. Model each variant separately with stable IDs.

The assembled OBJs in `assemblies/` are geometric blockouts for checking fit. They are not finished textured models and include mating caps at part boundaries. Treads are simple blocks; the modeling pass must add stringers, rails, hatch guards, collision and sensible supports without invading the defined walkable clearance. Merge or suppress coincident internal faces for the final assembled export.

The two examples are 14 m long and 6 m wide. They demonstrate geometric reuse, not safe naval proportions. More decks change weight and silhouette substantially; there is no stability or buoyancy simulation here. Do not advertise unlimited stackability.

Regenerate using `python ../build_floors.py`. See `validation.json` for the precise checks performed. The upper gallery/cabin and final game collision still require inspection in the actual 3D modeling application.
