# Model F03_BOWSPRIT

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "F03_BOWSPRIT",
  "bounds_min": [
    -0.15,
    -0.15,
    0
  ],
  "bounds_max": [
    0.15,
    0.15,
    3
  ],
  "origin": "Base centre, spar extends local +Z",
  "sockets": [],
  "modeling_instructions": "Solid spar. Requires named bow mounting fixture; no HULL_U6 socket. V1 geometry envelope only; not included in validated hull assemblies."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
