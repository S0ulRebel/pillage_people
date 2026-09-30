"""Bake Tripo's sails into flat canvas textures for the game's cloth sails.

    python tools/bake_sail_canvas.py

The game simulates its sails as cloth (props/ship/sail.gd): a grid laced between four corners,
its texture coordinates running 0 to 1 across the head (U) and down from the head to the foot
(V). Tripo's sails (art/models/ship/rigging/sail_*.glb) are shaped, bellied meshes with the
canvas painted on an atlas: seams, patches, the hem and its grommets. This lays each one out
flat in the cloth's own coordinates:

  - flattens the sail onto its own plane (the course and topsails hang across X, the jib lies
    along the ship in Z) and draws its triangles into a lookup of atlas coordinates;
  - finds the sail's corners and maps the cloth's square onto them (the jib's head is one
    corner, so both head corners of the cloth map to it);
  - samples the atlas through that for every texel, and fills the few texels that fall outside
    Tripo's sail, where its edges curve in, from the nearest canvas.

Writes art/models/ship/rigging/canvas_<sail>.png. Run again after a sail model changes.
"""
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.spatial import ConvexHull

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
RIGGING = REPO / 'art' / 'models' / 'ship' / 'rigging'
# Sail: (plane's across axis, output size in texels (width, height)). Up is always +Y.
SAILS = {
    'course': (0, (1024, 640)),
    'topsail': (0, (768, 512)),
    'jib': (2, (512, 512)),
}
LOOKUP = 1024
# How far in from each of a square sail's grommet corners, toward its middle, the cloth's corner
# is taken: clear of the grommet and of the edges' inward curve, so the cloth shows canvas and
# its seams right to its edges.
INSET = 0.1
# The rim of Tripo's sail, in lookup cells, is its hem's shadow and the grommets' rope: it is
# trimmed off before the gaps outside the sail are filled, so they fill with canvas, not rim.
RIM = 24


def load(path):
    gltf, binary = glb_io.read(path)
    prim = gltf['meshes'][0]['primitives'][0]
    get = lambda i, w: np.frombuffer(glb_io.accessor_bytes(gltf, binary, i), dtype=np.float32).reshape(-1, w)
    positions = get(prim['attributes']['POSITION'], 3).astype(np.float64)
    uvs = get(prim['attributes']['TEXCOORD_0'], 2).astype(np.float64)
    kind = {5125: np.uint32, 5123: np.uint16}[gltf['accessors'][prim['indices']]['componentType']]
    faces = np.frombuffer(glb_io.accessor_bytes(gltf, binary, prim['indices']), dtype=kind).reshape(-1, 3).astype(np.int64)
    atlas = Image.open(io.BytesIO(glb_io.view_bytes(gltf, binary, gltf['images'][0]['bufferView']))).convert('RGB')
    return positions, uvs, faces, np.asarray(atlas, dtype=np.float64) / 255.0


def lookup_table(flat, uvs, faces):
    """Every point of the flattened sail's bounding box, on a LOOKUP grid, with the atlas
    coordinates of the sail there (NaN outside it). Returns (table, lower corner, size)."""
    low, high = flat.min(axis=0), flat.max(axis=0)
    size = high - low
    table = np.full((LOOKUP, LOOKUP, 2), np.nan)
    grid = (flat - low) / size * (LOOKUP - 1)
    for tri in faces:
        a, b, c = grid[tri]
        x0, y0 = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
        x1, y1 = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
        xs, ys = np.meshgrid(np.arange(max(x0, 0), min(x1, LOOKUP - 1) + 1), np.arange(max(y0, 0), min(y1, LOOKUP - 1) + 1))
        p = np.stack([xs.ravel(), ys.ravel()], axis=1).astype(np.float64)
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (p[:, 0] - c[0]) + (c[0] - b[0]) * (p[:, 1] - c[1])) / d
        w1 = ((c[1] - a[1]) * (p[:, 0] - c[0]) + (a[0] - c[0]) * (p[:, 1] - c[1])) / d
        w2 = 1.0 - w0 - w1
        inside = (w0 >= -1e-6) & (w1 >= -1e-6) & (w2 >= -1e-6)
        if not inside.any():
            continue
        uv = w0[inside, None] * uvs[tri[0]] + w1[inside, None] * uvs[tri[1]] + w2[inside, None] * uvs[tri[2]]
        table[p[inside, 1].astype(int), p[inside, 0].astype(int)] = uv
    return table, low, size


def corners(name, flat):
    """The sail's corners in the flattened plane, as the cloth's (head start, head end, foot
    start, foot end): its U runs from the first head corner to the second, V from head to foot."""
    if name == 'jib':
        # A triangle: its corners are the three points of its outline that span the most area.
        # The head is the highest, the tack the lowest (the luff between them, on the stay), the
        # clew the third, out aft. The cloth's head is on the mast and its second column on the
        # stay, so both head corners map to the head, the foot's start to the clew and its end to
        # the tack.
        ring = flat[ConvexHull(flat).vertices]
        best, found = -1.0, None
        for i in range(len(ring)):
            for j in range(i + 1, len(ring)):
                for k in range(j + 1, len(ring)):
                    a, b, c = ring[i], ring[j], ring[k]
                    area = abs((b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1]))
                    if area > best:
                        best, found = area, (a, b, c)
        head, tack = max(found, key=lambda p: p[1]), min(found, key=lambda p: p[1])
        clew = next(p for p in found if p is not head and p is not tack)
        # Each corner a little way in, clear of its grommet: the head's a short way down the
        # leech and the luff, so the cloth's head row is canvas, not the ring at the head.
        middle = (head + tack + clew) / 3.0
        return (head + (clew - head) * 0.12, head + (tack - head) * 0.12,
                clew + (middle - clew) * INSET, tack + (middle - tack) * INSET)
    # A square sail: its four grommet corners, the points furthest out along the diagonals,
    # each taken INSET of the way in toward the sail's middle.
    pick = lambda sx, sy: flat[np.argmax(sx * flat[:, 0] + sy * flat[:, 1])]
    ends = [pick(-1, 1), pick(1, 1), pick(-1, -1), pick(1, -1)]
    middle = sum(ends) / 4.0
    return tuple(p + (middle - p) * INSET for p in ends)


def bake(name, across, size):
    positions, uvs, faces, atlas = load(RIGGING / f'sail_{name}.glb')
    flat = np.stack([positions[:, across], positions[:, 1]], axis=1)
    table, low, extent = lookup_table(flat, uvs, faces)
    head_from, head_to, foot_from, foot_to = corners(name, flat)
    width, height = size
    u = (np.arange(width) + 0.5) / width
    v = (np.arange(height) + 0.5) / height
    uu, vv = np.meshgrid(u, v)
    head = head_from[None, None] * (1 - uu[..., None]) + head_to[None, None] * uu[..., None]
    foot = foot_from[None, None] * (1 - uu[..., None]) + foot_to[None, None] * uu[..., None]
    point = head * (1 - vv[..., None]) + foot * vv[..., None]
    cell = np.clip(np.round((point - low) / extent * (LOOKUP - 1)).astype(int), 0, LOOKUP - 1)
    # Outside Tripo's sail, and on its rim, the canvas is mirrored in from across the edge, so
    # its weave and seams carry on instead of being smeared out from the edge.
    inside = ndimage.binary_erosion(~np.isnan(table[..., 0]), iterations=RIM)
    atlas_uv = table[cell[..., 1], cell[..., 0]]
    hole = ~inside[cell[..., 1], cell[..., 0]]
    if hole.any():
        _, nearest = ndimage.distance_transform_edt(hole, return_indices=True)
        rows, cols = np.indices(hole.shape)
        mirror_r = np.clip(2 * nearest[0] - rows, 0, hole.shape[0] - 1)
        mirror_c = np.clip(2 * nearest[1] - cols, 0, hole.shape[1] - 1)
        use_mirror = ~hole[mirror_r, mirror_c]
        src_r = np.where(use_mirror, mirror_r, nearest[0])
        src_c = np.where(use_mirror, mirror_c, nearest[1])
        atlas_uv = np.where(hole[..., None], atlas_uv[src_r, src_c], atlas_uv)
    ah, aw = atlas.shape[:2]
    px = np.clip((atlas_uv[..., 0] * aw).astype(int), 0, aw - 1)
    py = np.clip((atlas_uv[..., 1] * ah).astype(int), 0, ah - 1)
    image = (atlas[py, px] * 255).round().astype(np.uint8)
    out = RIGGING / f'canvas_{name}.png'
    Image.fromarray(image).save(out, optimize=True)
    print(f'{out.relative_to(REPO)}: {width}x{height}, {hole.mean() * 100:.0f}% filled from the nearest canvas')


def main():
    for name, (across, size) in SAILS.items():
        bake(name, across, size)


if __name__ == '__main__':
    main()
