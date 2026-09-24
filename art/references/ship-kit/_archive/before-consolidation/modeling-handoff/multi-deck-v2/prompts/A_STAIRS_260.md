# Model A_STAIRS_260

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "A_STAIRS_260",
  "role": "inter-floor stairs",
  "bounds_min": [
    -0.5,
    0.12000000000000001,
    0.0
  ],
  "bounds_max": [
    0.5,
    2.6,
    3.25
  ],
  "origin": "Fore station centre at current finished floor height",
  "mesh": "meshes/A_STAIRS_260.obj",
  "notes": "13 rises of 0.20 m, 13 treads of 0.25 m; 3.25 m run, top Y=2.60. Width1.0. Upper slot is 1.10x3.25 m. Preserve headroom and add side stringers/handrails in modeling without closing shaft. Require 1 m approach/exit landing."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
