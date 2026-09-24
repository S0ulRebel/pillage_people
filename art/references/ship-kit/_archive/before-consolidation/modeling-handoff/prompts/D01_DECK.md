# Model D01_DECK

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "D01_DECK",
  "bounds_min": [
    -2.8,
    1.82,
    0
  ],
  "bounds_max": [
    2.8,
    2,
    2
  ],
  "origin": "Same origin as host H02",
  "sockets": [
    {
      "name": "FORE",
      "interface": "DECK_56",
      "position": [
        0,
        2,
        0
      ],
      "outward_normal": [
        0,
        0,
        -1
      ],
      "roll_reference": [
        0,
        1,
        0
      ]
    },
    {
      "name": "AFT",
      "interface": "DECK_56",
      "position": [
        0,
        2,
        2
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
  "modeling_instructions": "Deck top Y=2.0. Fits H02 only. Follow starter beveled underside to avoid intersecting curved hull. No railings on connection edges.",
  "starter_mesh": "meshes/D01_DECK.obj"
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
