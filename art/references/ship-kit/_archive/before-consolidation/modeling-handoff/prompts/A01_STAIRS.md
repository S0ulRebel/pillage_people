# Model A01_STAIRS

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "A01_STAIRS",
  "bounds_min": [
    -0.5,
    0,
    0
  ],
  "bounds_max": [
    0.5,
    2.58,
    3.3
  ],
  "origin": "Bottom landing edge centre",
  "sockets": [
    {
      "name": "LOW",
      "interface": "WALK_10",
      "position": [
        0,
        0,
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
      "name": "HIGH",
      "interface": "WALK_10",
      "position": [
        0,
        2.58,
        3.3
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
  "modeling_instructions": "12 equal rises of 0.215 m over 3.3 m run; 0.275 m tread. Reaches C05 roof. Reserve 1x1 m clear landings at both ends and 2 m headroom. Not for arbitrary deck heights."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
