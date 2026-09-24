# Model F01_HELM

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "F01_HELM",
  "bounds_min": [
    -0.55,
    0,
    -0.45
  ],
  "bounds_max": [
    0.55,
    1.5,
    0.45
  ],
  "origin": "Deck contact centre",
  "sockets": [],
  "modeling_instructions": "Decorative deck attachment; reserve X +/-0.8 and Z +/-1.1 for player access. No claim of physical steering linkage in v1."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
