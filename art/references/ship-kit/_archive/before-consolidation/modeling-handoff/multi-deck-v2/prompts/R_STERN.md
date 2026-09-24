# Model R_STERN

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "R_STERN",
  "role": "topmost bulwark",
  "bounds_min": [
    -3,
    0,
    0
  ],
  "bounds_max": [
    3,
    0.6,
    2
  ],
  "origin": "Fore station centre at current finished floor height",
  "mesh": "meshes/R_STERN.obj",
  "notes": "Place only on highest exposed deck. Do not retain it under another U wall. No ceiling or floor included."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
