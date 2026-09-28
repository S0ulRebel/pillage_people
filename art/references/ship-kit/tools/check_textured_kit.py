"""Prove the textured kit is the canonical kit with UVs added - nothing moved.

    python tools/check_textured_kit.py

Writes textured/validation.json and exits non-zero if any check fails. Each part is checked
three ways, the last independently of the canonical GLB:
  1. POSITION and NORMAL bytes are identical to canonical/meshes/<PART>.glb, primitive by
     primitive and material by material.
  2. Every textured vertex lies within 1e-6 m of an OBJ vertex, and the oriented triangles,
     with their materials, are the same multiset as the OBJ's faces. So parity reaches back to
     the OBJ that validate_kit.py checks, not just to another export.
  3. Every contract socket point is still a vertex (<= 1 mm, the contract tolerance).
Then the UVs are finite, the embedded images decode and wrap (REPEAT), and every joined
placement sits on a whole texture period so plank courses meet across joins. Each assembly
places the textured part meshes byte-for-byte at the contract's translations.

The report records the sha256 of every file it checked. tools/package_art_breakdown.py
refuses a report whose hashes no longer match the files on disk, so a re-export after the
check cannot ride on an old "passed".
"""
import hashlib
import json
import math
from collections import Counter
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image

import glb_io

ROOT = Path(__file__).resolve().parent.parent
CANON = ROOT / 'canonical'
TEXTURED = ROOT / 'textured'
VERTEX_TOL = 1e-6
PERIOD = {'x': 2.0, 'y': 2.6, 'z': 2.0}
# Free-standing: meets no textured neighbour, so its offset need not be a tile period.
UNJOINED = {'STAIRS_260'}


class Checks:
    def __init__(self):
        self.failures, self.count = [], Counter()

    def check(self, ok, group, message):
        self.count[group] += 1
        if not ok:
            self.failures.append(f'{group}: {message}')
        return ok


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


def read_obj(path):
    vertices, faces, material = [], [], None
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        fields = line.split('#')[0].split()
        if not fields:
            continue
        if fields[0] == 'v':
            vertices.append([float(v) for v in fields[1:4]])
        elif fields[0] == 'usemtl':
            material = fields[1]
        elif fields[0] == 'f':
            faces.append(([int(item.split('/')[0]) - 1 for item in fields[1:]], material))
    return np.array(vertices), faces


def oriented(triangle):
    """A triangle's vertex ids, rotated so the smallest leads; the winding is kept."""
    i = triangle.index(min(triangle))
    return tuple(triangle[i:] + triangle[:i])


def primitives(path):
    gltf, binary = glb_io.read(path)
    out = []
    for primitive in gltf['meshes'][0]['primitives']:
        attributes = primitive['attributes']
        out.append({
            'material': gltf['materials'][primitive['material']]['name'],
            'mode': primitive.get('mode', 4),
            'indexed': 'indices' in primitive,
            'POSITION': glb_io.accessor_bytes(gltf, binary, attributes['POSITION']),
            'NORMAL': glb_io.accessor_bytes(gltf, binary, attributes['NORMAL']),
            'TEXCOORD_0': (glb_io.accessor_bytes(gltf, binary, attributes['TEXCOORD_0'])
                           if 'TEXCOORD_0' in attributes else None),
        })
    return gltf, binary, out


def check_images(checks, group, gltf, binary):
    for sampler in gltf.get('samplers', []):
        checks.check(sampler.get('wrapS') == 10497 and sampler.get('wrapT') == 10497, group,
                     'sampler does not REPEAT; tiles would not line up across joins')
    for material in gltf['materials']:
        texture = material.get('pbrMetallicRoughness', {}).get('baseColorTexture')
        checks.check(texture is not None, group, f"material {material['name']} has no baseColorTexture")
    for image in gltf.get('images', []):
        try:
            with Image.open(BytesIO(glb_io.view_bytes(gltf, binary, image['bufferView']))) as im:
                im.load()
                ok = im.format == 'JPEG' and image.get('mimeType') == 'image/jpeg' and min(im.size) > 0
        except Exception as error:  # A broken image is a failed check, not a crash.
            ok = False
            image = {**image, 'error': str(error)}
        checks.check(ok, group, f"embedded image {image.get('name')} does not decode as declared")


def check_part(checks, part, hashes):
    part_id = part['id']
    group = f'part {part_id}'
    canonical_glb = CANON / 'meshes' / f'{part_id}.glb'
    obj = CANON / 'meshes' / f'{part_id}.obj'
    textured_glb = TEXTURED / 'meshes' / f'{part_id}.glb'
    if not checks.check(textured_glb.is_file(), group, 'textured GLB missing'):
        return None
    for path in (canonical_glb, obj, textured_glb):
        hashes[rel(path)] = sha(path)

    _, _, source = primitives(canonical_glb)
    gltf, binary, textured = primitives(textured_glb)
    checks.check([p['material'] for p in source] == [p['material'] for p in textured], group,
                 'primitive materials differ from the canonical GLB')
    for a, b in zip(source, textured):
        tag = f"{group} [{b['material']}]"
        checks.check(b['mode'] == 4 and not b['indexed'], tag, 'not an unindexed triangle list')
        checks.check(a['POSITION'] == b['POSITION'], tag, 'POSITION bytes differ from canonical GLB')
        checks.check(a['NORMAL'] == b['NORMAL'], tag, 'NORMAL bytes differ from canonical GLB')
        if checks.check(b['TEXCOORD_0'] is not None, tag, 'no TEXCOORD_0'):
            uv = np.frombuffer(b['TEXCOORD_0'], dtype='<f4')
            checks.check(len(uv) == len(b['POSITION']) // 12 * 2, tag, 'UV count differs from vertex count')
            checks.check(bool(np.isfinite(uv).all()), tag, 'non-finite UV')
    check_images(checks, group, gltf, binary)

    # Independent of the canonical GLB: back to the OBJ.
    vertices, faces = read_obj(obj)
    checks.check(all(len(f) == 3 for f, _ in faces), group, 'OBJ has non-triangle faces')
    # Touching panel solids repeat positions under different indices; one id per position.
    _, first, same = np.unique(np.round(vertices, 9), axis=0, return_index=True, return_inverse=True)
    position_id = first[same.reshape(-1)]
    expected = Counter((oriented([int(position_id[i]) for i in f]), m) for f, m in faces if len(f) == 3)
    found, worst = Counter(), 0.0
    for p in textured:
        coords = np.frombuffer(p['POSITION'], dtype='<f4').reshape(-1, 3).astype(np.float64)
        distance = np.linalg.norm(coords[:, None, :] - vertices[None, :, :], axis=2)
        nearest = distance.argmin(axis=1)
        worst = max(worst, float(distance[np.arange(len(coords)), nearest].max()))
        for t in position_id[nearest].reshape(-1, 3).tolist():
            found[(oriented(t), p['material'])] += 1
    checks.check(worst <= VERTEX_TOL, group, f'a vertex is {worst:.3g} m from every OBJ vertex')
    checks.check(found == expected, group,
                 f'triangles differ from the OBJ ({sum((found - expected).values())} extra, '
                 f'{sum((expected - found).values())} missing)')

    all_coords = np.concatenate([np.frombuffer(p['POSITION'], dtype='<f4').reshape(-1, 3)
                                 for p in textured]).astype(np.float64)
    socket_error = 0.0
    for socket in part.get('sockets', []):
        points = np.array(socket['points'], dtype=np.float64)
        d = np.linalg.norm(points[:, None, :] - all_coords[None, :, :], axis=2).min(axis=1)
        socket_error = max(socket_error, float(d.max()))
    tolerance = json.loads((CANON / 'contract.json').read_text(encoding='utf-8'))['interfaces']['tolerance_m']
    checks.check(socket_error <= tolerance, group, f'socket point moved {socket_error:.3g} m')
    return {'vertex_to_obj_max_m': worst, 'socket_point_max_m': socket_error,
            'triangles': sum(expected.values())}


def check_assembly(checks, assembly, hashes):
    group = f"assembly {assembly['id']}"
    path = TEXTURED / 'assemblies' / f"{assembly['id']}.glb"
    if not checks.check(path.is_file(), group, 'textured assembly missing'):
        return
    hashes[rel(path)] = sha(path)
    gltf, binary = glb_io.read(path)
    nodes = gltf['scenes'][gltf.get('scene', 0)]['nodes']
    checks.check(len(nodes) == len(assembly['placements']), group,
                 f"{len(nodes)} nodes for {len(assembly['placements'])} placements")
    part_bytes = {}
    for number, (node_index, placement) in enumerate(zip(nodes, assembly['placements'])):
        node, part_id = gltf['nodes'][node_index], placement['part']
        mesh = gltf['meshes'][node['mesh']]
        checks.check(mesh.get('name') == part_id, group, f'node {number} holds {mesh.get("name")}, not {part_id}')
        translation = node.get('translation', [0, 0, 0])
        checks.check(all(abs(a - b) <= 1e-9 for a, b in zip(translation, placement['position']))
                     and not any(k in node for k in ('rotation', 'scale', 'matrix')), group,
                     f'node {number} ({part_id}) is not placed at exactly {placement["position"]}')
        if part_id not in part_bytes:
            _, _, part_prims = primitives(TEXTURED / 'meshes' / f'{part_id}.glb')
            part_bytes[part_id] = [(p['material'], p['POSITION'], p['NORMAL'], p['TEXCOORD_0']) for p in part_prims]
        mine = []
        for primitive in mesh['primitives']:
            a = primitive['attributes']
            mine.append((gltf['materials'][primitive['material']]['name'],
                         glb_io.accessor_bytes(gltf, binary, a['POSITION']),
                         glb_io.accessor_bytes(gltf, binary, a['NORMAL']),
                         glb_io.accessor_bytes(gltf, binary, a['TEXCOORD_0'])))
        checks.check(mine == part_bytes[part_id], group, f'node {number} ({part_id}) mesh differs from its part GLB')
        if part_id not in UNJOINED:
            off_period = [axis for axis, value in zip('xyz', placement['position'])
                          if abs(value / PERIOD[axis] - round(value / PERIOD[axis])) > 1e-9]
            checks.check(not off_period, group,
                         f'{part_id} at {placement["position"]} is off the texture period on {off_period}')
    check_images(checks, group, gltf, binary)


def main():
    contract_path = CANON / 'contract.json'
    contract = json.loads(contract_path.read_text(encoding='utf-8'))
    checks, hashes, parts = Checks(), {rel(contract_path): sha(contract_path)}, {}
    for part in contract['parts']:
        result = check_part(checks, part, hashes)
        if result:
            parts[part['id']] = result
    assemblies = [a for a in contract['assemblies'] if not a['exploded']]
    for assembly in assemblies:
        check_assembly(checks, assembly, hashes)
    for extra in sorted((TEXTURED / 'textures').glob('*')) + [TEXTURED / 'texture-recipe.json']:
        hashes[rel(extra)] = sha(extra)

    report = {
        'passed': not checks.failures,
        'failure_count': len(checks.failures),
        'failures': checks.failures,
        'checks_run': sum(checks.count.values()),
        'checks': [
            'POSITION and NORMAL bytes identical to the canonical GLB, per primitive and material',
            f'every vertex within {VERTEX_TOL} m of an OBJ vertex; oriented triangles and materials equal the OBJ faces',
            'every contract socket point still a vertex within the contract tolerance',
            'UVs present, one per vertex, finite',
            'embedded JPEG images decode; samplers REPEAT; every material textured',
            'assemblies place the part meshes byte-for-byte at the contract translations, translation only',
            'every joined placement sits on a whole texture period (x 2 m, y 2.6 m, z 2 m)',
        ],
        'exempt_from_period_check': {p: 'free-standing; meets no textured neighbour' for p in sorted(UNJOINED)},
        'parts': parts,
        'assemblies': [a['id'] for a in assemblies],
        'not_checked': 'Visual continuity of grain across joins, engine import, collision, and any new '
                       'art geometry. This proves the construction geometry is unchanged, nothing more.',
        'sha256': dict(sorted(hashes.items())),
    }
    (TEXTURED / 'validation.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('passed', 'failure_count', 'checks_run')}, indent=2))
    for failure in checks.failures[:20]:
        print('FAIL', failure)
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
