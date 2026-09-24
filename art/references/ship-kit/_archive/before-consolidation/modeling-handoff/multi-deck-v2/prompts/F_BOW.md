# Model F_BOW

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "F_BOW",
  "role": "floor insert",
  "bounds_min": [
    -2.8,
    -0.18,
    0.08
  ],
  "bounds_max": [
    2.8,
    0,
    4
  ],
  "origin": "Fore station centre at current finished floor height",
  "mesh": "meshes/F_BOW.obj",
  "notes": "Top Y=0, underside Y=-0.18. Place at chosen floor datum, not wall base origin. Same XZ footprint as upper wall interior. Never duplicate an existing floor."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
