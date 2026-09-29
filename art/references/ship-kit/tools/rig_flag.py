"""Set Tripo's flag up to hang from its staff by its three rings.

    python tools/rig_flag.py

art/models/ship/rigging/flag.glb (from extract_tripo_sheet.py) is the cloth and three rings
along its hoist, in one mesh. As drawn, the rings lie flat in the cloth, their holes facing
through it, so no staff could pass through them; the hoist leans about 9 degrees, so no
straight staff could pass through all three; and the picture is upside down. This:

  - splits the mesh into its pieces (they share no vertex): the cloth, and the rings;
  - turns the whole flag in its own plane until the rings' centres stand in a vertical line,
    and on round so the picture is the right way up;
  - turns each ring a quarter about the line along the flag, on its own centre, so its hole
    faces up and down the staff;
  - centres each ring on one vertical line, puts the origin on it level with the top of the
    flag, fly out along +X, and moves the cloth's hoist edge 3 cm out, clear of the staff but
    still under the rings.

Writes art/models/ship/rigging/flag_rigged.glb: ship.gd stands its origin on the staff's axis
at the staff's top, and the staff runs through all three rings. Same texture, same UVs.
"""
import sys
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402
from extract_tripo_sheet import axis_rotation  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
SOURCE = REPO / 'art' / 'models' / 'ship' / 'rigging' / 'flag.glb'
OUT = SOURCE.with_name('flag_rigged.glb')
# How far the cloth's hoist edge stands from the staff's axis: clear of a staff 12 mm round,
# and well inside the rings, which reach 67 mm out.
HOIST_CLEAR = 0.03


def main():
    gltf, binary = glb_io.read(SOURCE)
    prim = gltf['meshes'][0]['primitives'][0]
    get = lambda i, w: np.frombuffer(glb_io.accessor_bytes(gltf, binary, i), dtype=np.float32).reshape(-1, w)
    positions = get(prim['attributes']['POSITION'], 3).astype(np.float64)
    normals = get(prim['attributes']['NORMAL'], 3).astype(np.float64)
    uvs = get(prim['attributes']['TEXCOORD_0'], 2)
    kind = {5125: np.uint32, 5123: np.uint16}[gltf['accessors'][prim['indices']]['componentType']]
    faces = np.frombuffer(glb_io.accessor_bytes(gltf, binary, prim['indices']), dtype=kind).reshape(-1, 3).astype(np.int64)
    image = glb_io.view_bytes(gltf, binary, gltf['images'][0]['bufferView'])

    # The pieces, joined where vertices share a position. The cloth is the one spanning the most
    # space; the rings are small, though Tripo gave each more vertices than the cloth.
    _, weld = np.unique(positions.round(5), axis=0, return_inverse=True)
    welded = weld.reshape(-1)[faces]
    rows = np.concatenate([welded[:, 0], welded[:, 1], welded[:, 2]])
    cols = np.concatenate([welded[:, 1], welded[:, 2], welded[:, 0]])
    size = weld.max() + 1
    _, label = connected_components(coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(size, size)), directed=False)
    piece = label[weld.reshape(-1)]
    spans = {k: float(np.ptp(positions[piece == k], axis=0).max()) for k in np.unique(piece)}
    cloth = max(spans, key=spans.get)
    rings = [k for k in spans if k != cloth]
    if len(rings) != 3:
        raise SystemExit(f'{SOURCE.name}: {len(rings)} rings; expected the three on its hoist')
    middle = lambda k: (positions[piece == k].min(axis=0) + positions[piece == k].max(axis=0)) / 2
    centres = np.array([middle(k) for k in rings])

    # Upright: the rings' centres into a vertical line, and the picture turned right way up.
    top, bottom = centres[np.argmax(centres[:, 1])], centres[np.argmin(centres[:, 1])]
    lean = np.degrees(np.arctan2(bottom[0] - top[0], top[1] - bottom[1]))
    turn = axis_rotation('z', 180.0 - lean)
    positions = positions @ turn.T
    normals = normals @ turn.T
    centres = centres @ turn.T

    # Each ring a quarter turn about the flag's length, on its own centre: hole up the staff.
    quarter = axis_rotation('x', 90.0)
    for k, centre in zip(rings, centres):
        mine = piece == k
        positions[mine] = (positions[mine] - centre) @ quarter.T + centre
        normals[mine] = normals[mine] @ quarter.T

    # Origin on the rings' line, level with the flag's top; the fly out along +X.
    axis = centres.mean(axis=0)
    positions -= [axis[0], positions[:, 1].max(), axis[2]]
    centres -= [axis[0], 0.0, axis[2]]
    # Each ring exactly on the line (they were drawn up to 5 mm off it): their holes are small.
    for k, centre in zip(rings, centres):
        positions[piece == k] -= [centre[0], 0.0, centre[2]]
    # The cloth's hoist edge out of the staff's way, still under the rings so they hold it.
    mine = piece == cloth
    positions[mine, 0] += HOIST_CLEAR - positions[mine, 0].min()
    if positions[piece == cloth][:, 0].mean() < 0:
        raise SystemExit('the fly ended up toward -X; the flag is not the way this expects')

    writer = glb_io.Writer()
    out = {'asset': {'version': '2.0', 'generator': 'ship-kit tools/rig_flag.py'},
           'scene': 0, 'scenes': [{'nodes': [0]}], 'nodes': [{'name': 'flag', 'mesh': 0}],
           'samplers': gltf['samplers'], 'textures': gltf['textures'], 'materials': gltf['materials'],
           'images': [{'bufferView': writer.view(image), 'mimeType': gltf['images'][0]['mimeType']}]}
    writer.accessors.append({'bufferView': writer.view(faces.astype(np.uint32).tobytes(), 34963),
                             'componentType': 5125, 'count': int(faces.size), 'type': 'SCALAR'})
    out['meshes'] = [{'name': 'flag', 'primitives': [{
        'attributes': {'POSITION': writer.floats(positions.astype(np.float32).tobytes(), 'VEC3', bounds=True),
                       'NORMAL': writer.floats(normals.astype(np.float32).tobytes(), 'VEC3'),
                       'TEXCOORD_0': writer.floats(uvs.tobytes(), 'VEC2')},
        'indices': 0, 'material': 0, 'mode': 4}]}]
    OUT.write_bytes(writer.glb(out))
    hole = min(float(np.hypot(positions[piece == k][:, 0], positions[piece == k][:, 2]).min()) for k in rings)
    print(f'{OUT.relative_to(REPO)}: hoist straightened by {lean:.1f} degrees, picture turned upright, '
          f'3 rings turned onto the staff\'s line; the smallest ring hole is {hole * 1000:.1f} mm round')


if __name__ == '__main__':
    main()
