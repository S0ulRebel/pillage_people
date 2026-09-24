# Model F_STAIR_STARBOARD

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "F_STAIR_STARBOARD",
  "role": "stair-opening floor",
  "bounds_min": [
    -2.8,
    -0.18,
    0
  ],
  "bounds_max": [
    2.8,
    0,
    2
  ],
  "origin": "Fore station centre at current finished floor height",
  "mesh": "meshes/F_STAIR_STARBOARD.obj",
  "notes": "Mirrored port slot X=0.95..2.05. Follow with the matching END tile. Do not rotate port mesh silently or change its origin."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
