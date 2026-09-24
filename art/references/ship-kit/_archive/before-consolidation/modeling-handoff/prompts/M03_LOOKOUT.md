# Model M03_LOOKOUT

Read ../contract.json and ../../01-hull-modules-v1.png (style only).

{
  "id": "M03_LOOKOUT",
  "bounds_min": [
    -1.1,
    -0.18,
    -1.1
  ],
  "bounds_max": [
    1.1,
    1.1,
    1.1
  ],
  "origin": "Floor top centre",
  "sockets": [],
  "modeling_instructions": "Floor thickness .18, central circular through-hole radius .185; mounts around M01 mast neck at local Y=5.5. Separate access opening X=.3..1.0,Z=-.4.. .4 through floor. No geometry in mast hole. Rails height1.1, offset hatch clear. This is a wrap attachment, not an end-to-end mast socket."
}

Deliver one GLB named after this ID, one source Blender file, and front/side/top orthographic PNG renders. Keep metre scale, prescribed origin and axes. If working in Blender use the conversion in contract.json, then export GLB Y-up. Socket empties retain names and coordinates. Do not invent missing sockets, resize to match concept art, fill connection openings, or claim other parts fit without checking coordinates. If a starter OBJ exists, import it and preserve the locked interface band; add detail only away from joins. Materials: broad warm timber, dark iron, restrained brass, toon-readable detail. Separate collision from render mesh. Report measured bounds, socket errors and any deviation.
