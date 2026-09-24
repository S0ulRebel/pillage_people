# Model M02_TOPMAST

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "M02_TOPMAST",
  "bounds_min": [
    -0.18,
    0,
    -0.18
  ],
  "bounds_max": [
    0.18,
    3,
    0.18
  ],
  "origin": "Bottom centre",
  "sockets": [
    {
      "name": "BOTTOM",
      "interface": "MAST_036",
      "position": [
        0,
        0,
        0
      ],
      "outward_normal": [
        0,
        -1,
        0
      ],
      "roll_reference": [
        0,
        0,
        1
      ]
    }
  ],
  "modeling_instructions": "Solid spar radius 0.18 at foot tapering to 0.08 at top. First 0.15 m preserves radius 0.18. Mate directly to M01 TOP at Y=5.5; cosmetic collar may cover joint."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
