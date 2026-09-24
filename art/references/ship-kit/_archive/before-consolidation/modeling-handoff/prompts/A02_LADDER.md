# Model A02_LADDER

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "A02_LADDER",
  "bounds_min": [
    -0.35,
    0,
    -0.15
  ],
  "bounds_max": [
    0.35,
    2.58,
    0.15
  ],
  "origin": "Bottom centre",
  "sockets": [],
  "modeling_instructions": "Fixed roof-height ladder, 0.7 m wide. Top Y=2.58. Needs separate clear 0.8x0.8 m roof hatch and side access; do not run through a solid roof tile. Place against exterior wall, away from projecting galleries."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
