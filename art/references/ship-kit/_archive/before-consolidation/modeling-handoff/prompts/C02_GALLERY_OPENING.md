# Model C02_GALLERY_OPENING

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "C02_GALLERY_OPENING",
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
  "sockets": [
    {
      "name": "GALLERY",
      "interface": "GALLERY_18",
      "position": [
        0,
        0,
        0.1
      ],
      "outward_normal": [
        0,
        0,
        1
      ],
      "roll_reference": [
        0,
        1,
        0
      ]
    }
  ],
  "modeling_instructions": "Replaces C01. Open rectangle X=-0.9..0.9, Y=0..2.2 through wall. Frame only above opening and in junction-post strips. No window, back wall, floor lip or door in passage."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
