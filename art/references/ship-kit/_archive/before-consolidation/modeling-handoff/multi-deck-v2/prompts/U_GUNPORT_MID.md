# Model U_GUNPORT_MID

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "U_GUNPORT_MID",
  "role": "upper gun-deck wall",
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
  "origin": "Fore station centre at current finished floor height",
  "mesh": "meshes/U_GUNPORT_MID.obj",
  "notes": "Replaces U_MID. Openings on both sides: Z=0.5..1.5, Y=0.8..1.6 ABOVE this level floor. Bottom and top wall strips are unchanged. Cannon barrel centre must be fitted to this opening; do not scale whole hull."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
