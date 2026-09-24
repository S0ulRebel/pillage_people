# Model G03_STARBOARD_BAY

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "G03_STARBOARD_BAY",
  "bounds_min": [
    -1,
    -0.3,
    0
  ],
  "bounds_max": [
    1,
    2.4,
    0.8
  ],
  "origin": "Floor centre at inboard mating plane",
  "sockets": [
    {
      "name": "INBOARD",
      "interface": "GALLERY_18",
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
  "modeling_instructions": "Window bay projects along local +Z. Open attachment rectangle X=-0.9..0.9,Y=0..2.2. Floor TOP Y=0; roof aligns to cabin Y=2.4. Windowed exterior at +Z. Mount only into C02; no solid wall behind. Side variants may add mirrored trim strictly inside bounds. Local topology is shared; placement rotation selects ship side."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
