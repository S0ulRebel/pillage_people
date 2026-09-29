"""Split the straight rail into the parts a rail of any shape is laid from.

    python tools/split_rail.py

Tripo's straight rail (art/models/ship/deck/rail_straight.glb, cut by extract_tripo_sheet.py)
is six loose pieces in one mesh: a handrail along the top, a base rail along the foot and four
balusters between them. On the sheet they touch, so the extractor cannot claim them apart; in
the exported mesh they share no vertex, so they separate cleanly here.

Writes art/models/ship/deck/rail_parts.glb with three nodes:
    handrail, base   the long rails, laid one per span between two posts
    baluster         the one nearest the middle, repeated along each span
Each part keeps the rail's height (the base's foot at Y=0, the handrail on top) and is centred
on X and Z, with its length along X. Same texture, same UVs, vertices copied unchanged apart
from that shift. ship.gd lays them along the hull's edge between the rail posts.
"""
import struct
import sys
from pathlib import Path

import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
SOURCE = REPO / 'art' / 'models' / 'ship' / 'deck' / 'rail_straight.glb'
OUT = SOURCE.with_name('rail_parts.glb')


def load(path):
    gltf, binary = glb_io.read(path)
    if len(gltf['meshes']) != 1 or len(gltf['meshes'][0]['primitives']) != 1:
        raise SystemExit(f'{path}: expected one mesh with one primitive, as the extractor writes')
    primitive = gltf['meshes'][0]['primitives'][0]
    attributes = {name: np.frombuffer(glb_io.accessor_bytes(gltf, binary, index), dtype=np.float32)
                  .reshape(gltf['accessors'][index]['count'], -1)
                  for name, index in primitive['attributes'].items()}
    kind = {5125: np.uint32, 5123: np.uint16}[gltf['accessors'][primitive['indices']]['componentType']]
    indices = np.frombuffer(glb_io.accessor_bytes(gltf, binary, primitive['indices']), dtype=kind).reshape(-1, 3)
    image = glb_io.view_bytes(gltf, binary, gltf['images'][0]['bufferView'])
    return gltf, attributes, indices.astype(np.int64), image


def pieces(positions, indices):
    """Triangle masks of the connected pieces, joined where vertices share a position."""
    _, weld = np.unique(positions.round(5), axis=0, return_inverse=True)
    welded = weld.reshape(-1)[indices]
    rows = np.concatenate([welded[:, 0], welded[:, 1], welded[:, 2]])
    cols = np.concatenate([welded[:, 1], welded[:, 2], welded[:, 0]])
    size = weld.max() + 1
    count, label = connected_components(coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(size, size)),
                                        directed=False)
    return [label[welded[:, 0]] == k for k in range(count)]


def main():
    source, attributes, indices, image = load(SOURCE)
    positions = attributes['POSITION']
    parts = [m for m in pieces(positions, indices) if m.sum() >= 12]
    if len(parts) < 3:
        raise SystemExit(f'{SOURCE}: {len(parts)} pieces; expected a handrail, a base and balusters')
    corners = [positions[indices[m]].reshape(-1, 3) for m in parts]
    tops = [c[:, 1].max() for c in corners]
    handrail = int(np.argmax(tops))
    base = int(np.argmin([c[:, 1].min() for c in corners]))
    rest = [i for i in range(len(parts)) if i not in (handrail, base)]
    baluster = min(rest, key=lambda i: abs(corners[i][:, 0].mean()))
    for name, i in (('handrail', handrail), ('base', base)):
        if np.ptp(corners[i][:, 0]) < 0.8 * np.ptp(positions[:, 0]):
            raise SystemExit(f'the {name} does not run the rail\'s length; the pieces are not what this expects')

    writer = glb_io.Writer()
    gltf = {'asset': {'version': '2.0', 'generator': 'ship-kit tools/split_rail.py'},
            'scene': 0, 'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [],
            'samplers': source['samplers'], 'textures': source['textures'],
            'images': [{'bufferView': writer.view(image), 'mimeType': source['images'][0]['mimeType']}],
            'materials': source['materials']}
    report = []
    for name, i in (('handrail', handrail), ('base', base), ('baluster', baluster)):
        used, local = np.unique(indices[parts[i]], return_inverse=True)
        p = positions[used].copy()
        shift = np.array([(p[:, 0].min() + p[:, 0].max()) / 2, 0.0, (p[:, 2].min() + p[:, 2].max()) / 2])
        p -= shift
        accessor = {'bufferView': writer.view(local.astype(np.uint32).tobytes(), 34963),
                    'componentType': 5125, 'count': int(local.size), 'type': 'SCALAR'}
        writer.accessors.append(accessor)
        index_accessor = len(writer.accessors) - 1
        prim = {'attributes': {'POSITION': writer.floats(p.astype(np.float32).tobytes(), 'VEC3', bounds=True),
                               'NORMAL': writer.floats(attributes['NORMAL'][used].tobytes(), 'VEC3'),
                               'TEXCOORD_0': writer.floats(attributes['TEXCOORD_0'][used].tobytes(), 'VEC2')},
                'indices': index_accessor, 'material': 0, 'mode': 4}
        gltf['meshes'].append({'name': name, 'primitives': [prim]})
        gltf['nodes'].append({'name': name, 'mesh': len(gltf['meshes']) - 1})
        gltf['scenes'][0]['nodes'].append(len(gltf['nodes']) - 1)
        report.append(f'{name:9s} {local.size // 3:4d} tris  length {np.ptp(p[:, 0]):.3f}  '
                      f'y {p[:, 1].min():.3f} to {p[:, 1].max():.3f}  depth {np.ptp(p[:, 2]):.3f}')
    OUT.write_bytes(writer.glb(gltf))
    print(f'{OUT.relative_to(REPO)}: {len(parts)} pieces in the rail, kept the handrail, the base and one baluster')
    print('\n'.join(report))


if __name__ == '__main__':
    main()
