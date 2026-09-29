"""Cut the rail's handrail and base, and the hull's wale, down to profiles for ship.gd to sweep.

    python tools/rail_profiles.py

Laid as copies of Tripo's 1.76 m pieces, the handrail and base read as a dashed line: every
copy has its own rounded ends, and each is stretched by a different amount, so the grain jumps
at every joint. Swept as one profile along the whole path, the rail is continuous, mitred at
its corners, and its grain runs at one density everywhere.

From art/models/ship/deck/rail_parts.glb (tools/split_rail.py), for the handrail and the base:
  - the profile: the piece sliced across its middle, resampled to PROFILE_POINTS evenly round
    its outline, with each point's outward normal;
  - a texture: the piece's own wood, baked off Tripo's atlas by casting from the profile onto
    the piece, TILE metres of its length (clear of its rounded ends) round its whole outline,
    and cross-faded at its ends so it repeats along the rail without a seam.

Writes art/models/ship/deck/rail_sweep.glb: a node per piece, one TILE-long straight length of
the sweep. Ring 0 (x=0) is the profile, in order, closed by a repeat of its first point; ring 1
is the same at x=TILE. U runs 0 to 1 along it, V round the profile. The sampler repeats, so
ship.gd lays U at (metres along the rail) / TILE.
"""
import io
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
SOURCE = REPO / 'art' / 'models' / 'ship' / 'deck' / 'rail_parts.glb'
OUT = SOURCE.with_name('rail_sweep.glb')
# The hull's wale (tools/extract_tripo_sheet.py, tripo/hull.json): one 2 m bay running along Z
# from its origin, its inner face at X=0 against the hull and its outer face out along +X.
WALE = REPO / 'art' / 'models' / 'ship' / 'hull' / 'wale.glb'
WALE_BAY = 2.0
PROFILE_POINTS = 24
TILE = 1.0
BAKE = (512, 128)
FADE = 0.25


def load(path):
    gltf, binary = glb_io.read(path)
    atlas = Image.open(io.BytesIO(glb_io.view_bytes(gltf, binary, gltf['images'][0]['bufferView']))).convert('RGB')
    pieces = {}
    for node in gltf['nodes']:
        prim = gltf['meshes'][node['mesh']]['primitives'][0]
        get = lambda i, w: np.frombuffer(glb_io.accessor_bytes(gltf, binary, i), dtype=np.float32).reshape(-1, w)
        kind = {5125: np.uint32, 5123: np.uint16}[gltf['accessors'][prim['indices']]['componentType']]
        index = np.frombuffer(glb_io.accessor_bytes(gltf, binary, prim['indices']), dtype=kind).reshape(-1, 3).astype(np.int64)
        pieces[node['name']] = (get(prim['attributes']['POSITION'], 3).astype(np.float64),
                                get(prim['attributes']['TEXCOORD_0'], 2).astype(np.float64), index)
    return pieces, np.asarray(atlas, dtype=np.float64)


def slice_at_middle(positions, index):
    """The outline where the plane x=0 cuts the piece, as the longest closed loop, in (z, y)."""
    segments = []
    for tri in positions[index]:
        side = tri[:, 0]
        points = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            if (side[a] < 0) != (side[b] < 0):
                t = side[a] / (side[a] - side[b])
                p = tri[a] + (tri[b] - tri[a]) * t
                points.append((p[2], p[1]))
        if len(points) == 2:
            segments.append(points)
    if not segments:
        raise SystemExit('the piece does not cross its middle')
    ends = np.array([p for s in segments for p in s]).round(6)
    keys = [tuple(k) for k in ends]
    links = {}
    for i in range(0, len(keys), 2):
        links.setdefault(keys[i], []).append(keys[i + 1])
        links.setdefault(keys[i + 1], []).append(keys[i])
    loops, seen = [], set()
    for start in links:
        if start in seen:
            continue
        loop, previous, current = [start], None, start
        seen.add(start)
        while True:
            step = [n for n in links[current] if n != previous and n not in seen]
            if not step:
                break
            previous, current = current, step[0]
            loop.append(current)
            seen.add(current)
        loops.append(np.array(loop))
    loop = max(loops, key=lambda l: np.linalg.norm(np.diff(np.vstack([l, l[:1]]), axis=0), axis=1).sum())
    # Counter-clockwise seen from -X, so outward normals come out on the same side every time.
    area = 0.5 * np.sum(loop[:, 0] * np.roll(loop[:, 1], -1) - np.roll(loop[:, 0], -1) * loop[:, 1])
    return loop if area > 0 else loop[::-1]


def resample(loop, count):
    """`count` points evenly round a closed loop, starting at its lowest point, with the
    outward normal at each and the distance round to it as a fraction of the whole."""
    closed = np.vstack([loop, loop[:1]])
    step = np.linalg.norm(np.diff(closed, axis=0), axis=1)
    reach = np.concatenate([[0.0], np.cumsum(step)])
    start = reach[np.argmin(loop[:, 1] + 1e-3 * np.abs(loop[:, 0]))]
    wanted = (start + np.linspace(0.0, reach[-1], count, endpoint=False)) % reach[-1]
    points = np.array([np.interp(wanted, reach, closed[:, k]) for k in (0, 1)]).T
    ahead, behind = np.roll(points, -1, axis=0), np.roll(points, 1, axis=0)
    tangent = ahead - behind
    normal = np.stack([tangent[:, 1], -tangent[:, 0]], axis=1)
    normal /= np.linalg.norm(normal, axis=1, keepdims=True)
    centre = points.mean(axis=0)
    if np.mean(np.sum(normal * (points - centre), axis=1)) < 0:
        normal = -normal
    return points, normal, np.linspace(0.0, 1.0, count, endpoint=False)


def cast(tris, uvs, origins, direction):
    """UV where each ray first meets the piece, or NaN where it misses. Möller-Trumbore."""
    e1, e2 = tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    found = np.full((len(origins), 2), np.nan)
    for i, (o, d) in enumerate(zip(origins, direction)):
        p = np.cross(d, e2)
        det = np.einsum('ij,ij->i', e1, p)
        ok = np.abs(det) > 1e-12
        inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
        s = o - tris[:, 0]
        u = np.einsum('ij,ij->i', s, p) * inv
        q = np.cross(s, e1)
        v = (q @ d) * inv
        t = np.einsum('ij,ij->i', e2, q) * inv
        hit = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 0)
        if hit.any():
            k = np.flatnonzero(hit)[np.argmin(t[hit])]
            found[i] = uvs[k, 0] * (1 - u[k] - v[k]) + uvs[k, 1] * u[k] + uvs[k, 2] * v[k]
    return found


def sample(atlas, uv):
    h, w, _ = atlas.shape
    x = np.clip(uv[:, 0] * w - 0.5, 0, w - 1.001)
    y = np.clip(uv[:, 1] * h - 0.5, 0, h - 1.001)
    x0, y0 = x.astype(int), y.astype(int)
    fx, fy = (x - x0)[:, None], (y - y0)[:, None]
    return (atlas[y0, x0] * (1 - fx) * (1 - fy) + atlas[y0, x0 + 1] * fx * (1 - fy)
            + atlas[y0 + 1, x0] * (1 - fx) * fy + atlas[y0 + 1, x0 + 1] * fx * fy)


def bake(positions, uvs, index, atlas, points, normals):
    """TILE metres of the piece's own surface, round its outline, as a repeating strip."""
    width, height = BAKE
    fade = int(width * FADE)
    # Centred on the piece, and clear of its rounded ends (at about +/-0.88 m).
    span = TILE * (1 + FADE)
    xs = np.linspace(-span / 2, span / 2, width + fade, endpoint=False)
    # Densely round the outline, then down to the texture's rows.
    rows = np.linspace(0.0, 1.0, height, endpoint=False)
    pts = np.array([np.interp(rows, np.linspace(0, 1, len(points), endpoint=False), points[:, k], period=1) for k in (0, 1)]).T
    nrm = np.array([np.interp(rows, np.linspace(0, 1, len(points), endpoint=False), normals[:, k], period=1) for k in (0, 1)]).T
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    tris, tri_uvs = positions[index], uvs[index]
    image = np.zeros((height, width + fade, 3))
    for col, x in enumerate(xs):
        origins = np.column_stack([np.full(height, x), pts[:, 1] + nrm[:, 1] * 0.1, pts[:, 0] + nrm[:, 0] * 0.1])
        direction = -np.column_stack([np.zeros(height), nrm[:, 1], nrm[:, 0]])
        uv = cast(tris, tri_uvs, origins, direction)
        miss = np.isnan(uv[:, 0])
        if miss.any():
            # Where the piece dips under the profile here, look outward from inside instead.
            uv[miss] = cast(tris, tri_uvs, origins[miss] + direction[miss] * 0.2, -direction[miss])[:, :]
        miss = np.isnan(uv[:, 0])
        colour = np.zeros((height, 3))
        colour[~miss] = sample(atlas, uv[~miss])
        if miss.any() and (~miss).any():
            near = np.flatnonzero(~miss)
            for r in np.flatnonzero(miss):
                colour[r] = colour[near[np.argmin(np.abs(near - r))]]
        image[:, col] = colour
    # Cross-fade the overrun onto the start, so the last column runs straight into the first.
    t = np.linspace(0.0, 1.0, fade)[None, :, None]
    image[:, :fade] = image[:, width:] * (1 - t) + image[:, :fade] * t
    return Image.fromarray(image[:, :width].clip(0, 255).astype(np.uint8))


def sweep_node(writer, gltf, name, points, normals, around, image):
    """One TILE-long straight length of the sweep, textured with its baked strip."""
    ring = len(points) + 1
    closed = np.vstack([points, points[:1]])
    closed_n = np.vstack([normals, normals[:1]])
    closed_v = np.concatenate([around, [1.0]])
    pos, nrm, uv = [], [], []
    for x, u in ((0.0, 0.0), (TILE, 1.0)):
        for (z, y), (nz, ny), v in zip(closed, closed_n, closed_v):
            pos.append((x, y, z))
            nrm.append((0.0, ny, nz))
            uv.append((u, v))
    faces = []
    for i in range(ring - 1):
        a, b, c, d = i, i + 1, ring + i, ring + i + 1
        faces += [(a, c, b), (b, c, d)]
    pos = np.array(pos, np.float32)
    faces = np.array(faces, np.uint32)
    # Wind each triangle to face outward.
    for f in faces:
        n = np.cross(pos[f[1]] - pos[f[0]], pos[f[2]] - pos[f[0]])
        if np.dot(n, np.array(nrm[f[0]])) < 0:
            f[1], f[2] = f[2], f[1]
    buffer = io.BytesIO()
    image.save(buffer, 'PNG')
    gltf['images'].append({'bufferView': writer.view(buffer.getvalue()), 'mimeType': 'image/png'})
    gltf['textures'].append({'sampler': 0, 'source': len(gltf['images']) - 1})
    gltf['materials'].append({'name': f'rail_{name}', 'pbrMetallicRoughness': {
        'baseColorTexture': {'index': len(gltf['textures']) - 1}, 'metallicFactor': 0, 'roughnessFactor': 0.85}})
    writer.accessors.append({'bufferView': writer.view(faces.tobytes(), 34963), 'componentType': 5125,
                             'count': int(faces.size), 'type': 'SCALAR'})
    index = len(writer.accessors) - 1
    prim = {'attributes': {'POSITION': writer.floats(pos.tobytes(), 'VEC3', bounds=True),
                           'NORMAL': writer.floats(np.array(nrm, np.float32).tobytes(), 'VEC3'),
                           'TEXCOORD_0': writer.floats(np.array(uv, np.float32).tobytes(), 'VEC2')},
            'indices': index, 'material': len(gltf['materials']) - 1, 'mode': 4}
    gltf['meshes'].append({'name': name, 'primitives': [prim]})
    gltf['nodes'].append({'name': name, 'mesh': len(gltf['meshes']) - 1})
    gltf['scenes'][0]['nodes'].append(len(gltf['nodes']) - 1)


def main():
    pieces, atlas = load(SOURCE)
    writer = glb_io.Writer()
    gltf = {'asset': {'version': '2.0', 'generator': 'ship-kit tools/rail_profiles.py'},
            'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [], 'images': [], 'textures': [],
            'materials': [], 'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}]}
    # Laid the way the rail's pieces lie - its length along X about its middle, its outer face
    # toward +Z - so it is sliced and baked the same way.
    wale, wale_atlas = load(WALE)
    positions, uvs, index = wale['wale']
    pieces['wale'] = (np.column_stack([positions[:, 2] - WALE_BAY / 2, positions[:, 1], positions[:, 0]]), uvs, index)
    atlases = {'handrail': atlas, 'base': atlas, 'wale': wale_atlas}
    for name in ('handrail', 'base', 'wale'):
        positions, uvs, index = pieces[name]
        points, normals, around = resample(slice_at_middle(positions, index), PROFILE_POINTS)
        if name == 'base':
            # Tripo's base sags a little off the deck along its middle: sit the profile on it.
            positions = positions - [0.0, points[:, 1].min(), 0.0]
            points = points - [0.0, points[:, 1].min()]
        image = bake(positions, uvs, index, atlases[name], points, normals)
        sweep_node(writer, gltf, name, points, normals, around, image)
        perimeter = np.linalg.norm(np.diff(np.vstack([points, points[:1]]), axis=0), axis=1).sum()
        print(f'{name:9s} profile {np.ptp(points[:, 0]):.3f} deep, y {points[:, 1].min():.3f} to '
              f'{points[:, 1].max():.3f}, {perimeter:.2f} m round; texture {BAKE[0]}x{BAKE[1]} for {TILE} m')
    OUT.write_bytes(writer.glb(gltf))
    print(f'{OUT.relative_to(REPO)} written')


if __name__ == '__main__':
    main()
