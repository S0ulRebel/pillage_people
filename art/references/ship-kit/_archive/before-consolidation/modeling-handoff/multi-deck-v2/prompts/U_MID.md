# Model U_MID

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "U_MID",
  "role": "stackable upper hull wall",
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
  "mesh": "meshes/U_MID.obj",
  "notes": "Footprint follows H02_MID. Open top and bottom. At lengthwise interfaces, side-wall strips only; no transverse bulkhead. Bottom Y=0, top Y=2.6. Locks first/last 0.10 m of each mating surface."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
