# Model C03_DOOR_WALL

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "C03_DOOR_WALL",
  "bounds_min": [
    -1,
    0,
    -0.1
  ],
  "bounds_max": [
    1,
    2.4,
    0.1
  ],
  "origin": "Same as C01",
  "sockets": [],
  "modeling_instructions": "Replaces C01. Doorway clear X=-0.45..0.45,Y=0..2.0. Door mesh separate, pivot at left jamb. Closed door may occlude doorway; open rotation must clear stairs."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
