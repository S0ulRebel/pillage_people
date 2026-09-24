# Model C05_ROOF_TILE

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "C05_ROOF_TILE",
  "bounds_min": [
    -1,
    2.4,
    0
  ],
  "bounds_max": [
    1,
    2.58,
    2
  ],
  "origin": "Cabin floor datum, tile fore centre",
  "sockets": [],
  "modeling_instructions": "2x2 m tile, four make 4x4 m cabin roof. Walkable top Y=2.58. No railing across adjacent tile edges. Exterior fascia a separate decoration, never resize tile."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
