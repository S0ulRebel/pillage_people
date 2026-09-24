# Model H03_STERN

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "H03_STERN",
  "bounds_min": [
    -3,
    0,
    0
  ],
  "bounds_max": [
    3,
    2.6,
    2
  ],
  "origin": "Fore station on keel baseline; bow nose for H01",
  "sockets": [
    {
      "name": "FORE",
      "interface": "HULL_U6",
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
    }
  ],
  "modeling_instructions": "Preserve supplied OBJ vertices within 0.10 m of each HULL_U6 connection. Open U-shaped ends, never a wall across the interior. End caps close shell thickness ONLY. Bow nose / stern transom may close their non-connection ends.",
  "starter_mesh": "meshes/H03_STERN.obj"
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
