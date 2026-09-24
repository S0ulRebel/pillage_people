# Model F02_CAPSTAN

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "F02_CAPSTAN",
  "bounds_min": [
    -1.4,
    0,
    -1.4
  ],
  "bounds_max": [
    1.4,
    1.1,
    1.4
  ],
  "origin": "Deck contact centre",
  "sockets": [],
  "modeling_instructions": "Bounds include extended bars. Reserve radius1.7 for operation. Keep outside stairs and mast clearances; do not shrink solely to fit a crowded deck."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
