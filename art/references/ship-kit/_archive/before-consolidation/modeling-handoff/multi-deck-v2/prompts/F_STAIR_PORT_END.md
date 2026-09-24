# Model F_STAIR_PORT_END

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "F_STAIR_PORT_END",
  "role": "stair exit floor",
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
  "mesh": "meshes/F_STAIR_PORT_END.obj",
  "notes": "Use after the matching opening tile. Slot ends at local Z=1.25; the final 0.75 m is solid landing. Together the two tiles form a 1.10 x 3.25 m shaft, exactly matching the stair run."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
