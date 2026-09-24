# Model C01_CABIN_WALL

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "C01_CABIN_WALL",
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
  "origin": "Bottom centre of 2 m wall",
  "sockets": [
    {
      "name": "LEFT",
      "interface": "WALL_EDGE",
      "position": [
        -1,
        0,
        0
      ],
      "outward_normal": [
        -1,
        0,
        0
      ],
      "roll_reference": [
        0,
        1,
        0
      ]
    },
    {
      "name": "RIGHT",
      "interface": "WALL_EDGE",
      "position": [
        1,
        0,
        0
      ],
      "outward_normal": [
        1,
        0,
        0
      ],
      "roll_reference": [
        0,
        1,
        0
      ]
    }
  ],
  "modeling_instructions": "Wall runs along X; exterior +Z. Final 0.10 m at each end is reserved for junction posts: wall geometry spans X=-0.9..0.9. Y=0 sits on deck. Opaque solid variant."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
