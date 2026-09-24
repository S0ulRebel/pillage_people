# Model F_STAIR_PORT

Read ../START_HERE.md and ../contract.json. Preserve supplied starter-mesh connection vertices within 0.001 m. Use the approved ship PNGs only for style.

{
  "id": "F_STAIR_PORT",
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
  "mesh": "meshes/F_STAIR_PORT.obj",
  "notes": "Replaces F_MID. Through-slot X=-2.05..-0.95 over full 2 m length. Use this tile followed by its END variant for a 1.10x3.25 m shaft. No framing intrudes into clear opening."
}

Deliver metre-scale GLB, source scene, named socket empties and orthographic PNGs. Apply the coordinate conversion in the base handoff for Blender. No deformation within 0.10 m of joins. Do not auto-centre, auto-scale or fill access openings.
