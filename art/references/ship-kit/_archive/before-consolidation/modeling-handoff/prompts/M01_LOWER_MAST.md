# Model M01_LOWER_MAST

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "M01_LOWER_MAST",
  "bounds_min": [
    -0.25,
    0,
    -0.25
  ],
  "bounds_max": [
    0.25,
    5.5,
    0.25
  ],
  "origin": "Deck centre",
  "sockets": [
    {
      "name": "TOP",
      "interface": "MAST_036",
      "position": [
        0,
        5.5,
        0
      ],
      "outward_normal": [
        0,
        1,
        0
      ],
      "roll_reference": [
        0,
        0,
        1
      ]
    }
  ],
  "modeling_instructions": "Solid round wooden spar: radius 0.25 at deck tapering to 0.18 at Y=5.5. Last 0.15 m stays exact circular radius 0.18. Mount on deck replacing hatch tile if necessary; collision is not decorative rope."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
