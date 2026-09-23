r"""Simplify a vertex-coloured GLB down to a game-ready face count.

    python simplify_mesh.py <input.glb> [--faces 40000] [--out name.glb]

TRELLIS 2 produces roughly eighteen million faces with the colour stored per vertex as the
glTF COLOR_0 attribute. Both of the obvious ways to bring that down failed on an 8 GB card:
unwrapping and baking an atlas ran out of memory against the dense mesh as its reference, and
simplifying inside ComfyUI ran out of memory too. This does it on the CPU instead.

Quadric edge collapse, via fast_simplification, with the colours carried across afterwards by
nearest neighbour. Vertex clustering was the first attempt and it destroyed the model: the
reconstruction is a thin shell, so snapping to a grid merges its front and back surfaces into
each other and the figure comes out shredded while the colours stay perfectly correct.
"""
import argparse
import json
import struct
from pathlib import Path

import numpy as np

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    """Positions, colours and faces out of a GLB, without going through a mesh library.

    trimesh drops COLOR_0 when the primitive also names a PBR material, which is exactly the
    shape of file TRELLIS writes - it reports the mesh as textured and hands back no colours.
    """
    data = Path(path).read_bytes()
    _, _, _ = struct.unpack("<III", data[:12])
    json_length, _ = struct.unpack("<II", data[12:20])
    gltf = json.loads(data[20:20 + json_length].decode("utf-8"))
    binary_start = 20 + json_length + 8
    blob = data[binary_start:]

    def accessor(index):
        acc = gltf["accessors"][index]
        view = gltf["bufferViews"][acc["bufferView"]]
        fmt = COMPONENTS[acc["componentType"]]
        size = COUNTS[acc["type"]]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        count = acc["count"] * size
        values = np.frombuffer(blob, dtype=np.dtype("<" + fmt), count=count, offset=offset)
        return values.reshape(acc["count"], size)

    primitive = gltf["meshes"][0]["primitives"][0]
    positions = accessor(primitive["attributes"]["POSITION"]).astype(np.float64)
    faces = accessor(primitive["indices"]).astype(np.int64).reshape(-1, 3)
    colours = None
    if "COLOR_0" in primitive["attributes"]:
        raw = accessor(primitive["attributes"]["COLOR_0"])
        # Colours arrive as bytes, shorts or floats depending on the writer.
        if raw.dtype == np.float32:
            colours = np.clip(raw[:, :3], 0.0, 1.0)
        else:
            colours = raw[:, :3].astype(np.float64) / np.iinfo(raw.dtype).max
    return positions, colours, faces


def cluster(positions, colours, faces, cell):
    """Merge every vertex within one `cell`-sized grid box into a single vertex."""
    keys = np.floor((positions - positions.min(axis=0)) / cell).astype(np.int64)
    _, index, inverse = np.unique(keys, axis=0, return_index=True, return_inverse=True)
    merged = len(index)

    sums = np.zeros((merged, 3))
    np.add.at(sums, inverse, positions)
    counts = np.bincount(inverse, minlength=merged).reshape(-1, 1)
    new_positions = sums / counts

    new_colours = None
    if colours is not None:
        colour_sums = np.zeros((merged, 3))
        np.add.at(colour_sums, inverse, colours)
        new_colours = colour_sums / counts

    new_faces = inverse[faces]
    # Any face whose corners landed in the same cell has collapsed to a line or a point.
    keep = (new_faces[:, 0] != new_faces[:, 1]) & (new_faces[:, 1] != new_faces[:, 2]) \
        & (new_faces[:, 0] != new_faces[:, 2])
    return new_positions, new_colours, new_faces[keep]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--faces", type=int, default=40000)
    ap.add_argument("--out")
    args = ap.parse_args()

    positions, colours, faces = read_glb(args.source)
    print(f"in:  {len(faces):,} faces, {len(positions):,} vertices, "
          f"colour: {'yes' if colours is not None else 'no'}")

    import fast_simplification
    keep = min(max(args.faces / max(len(faces), 1), 0.0001), 1.0)
    reduced_points, reduced_faces = fast_simplification.simplify(
        positions.astype(np.float32), faces.astype(np.int32), target_reduction=1.0 - keep)

    if colours is not None:
        # Edge collapse makes new vertex positions rather than keeping a subset, so the
        # colours cannot be indexed across - each new vertex takes the colour of the original
        # nearest to it.
        from scipy.spatial import cKDTree
        _, nearest = cKDTree(positions).query(reduced_points, k=1)
        colours = colours[nearest]
    positions, faces = reduced_points.astype(np.float64), reduced_faces.astype(np.int64)

    import trimesh
    mesh = trimesh.Trimesh(vertices=positions, faces=faces, process=False)
    if colours is not None:
        mesh.visual = trimesh.visual.ColorVisuals(
            mesh=mesh, vertex_colors=(np.clip(colours, 0, 1) * 255).astype(np.uint8))
    # Drop the specks: the reconstruction leaves thousands of tiny shells around the model.
    parts = mesh.split(only_watertight=False)
    if len(parts) > 1:
        biggest = max(len(p.faces) for p in parts)
        mesh = trimesh.util.concatenate([p for p in parts if len(p.faces) >= biggest * 0.004])

    out = Path(args.out or Path(args.source).with_name(Path(args.source).stem + "_small.glb"))
    mesh.export(str(out))
    print(f"out: {len(mesh.faces):,} faces, {len(mesh.vertices):,} vertices -> {out}")


if __name__ == "__main__":
    main()
