"""Texture the canonical construction meshes without moving a single vertex.

    python tools/texture_kit.py

For every part in canonical/contract.json this reads canonical/meshes/<PART>.glb, copies its
POSITION and NORMAL bytes unchanged, adds TEXCOORD_0 and an embedded plank albedo, and writes
textured/meshes/<PART>.glb. The non-exploded assemblies are then written to
textured/assemblies/<ID>.glb as nodes placing those same meshes - translation only, so an
assembly holds each part's bytes exactly once and nothing is re-baked.

WHY COPY BYTES. The kit's whole value is that the sockets meet to within 1 mm. A texture pass
that goes through a modelling package or a generator re-exports the geometry and puts every
socket back in play. Copying the accessors means tools/check_textured_kit.py can prove parity
by byte comparison, not by tolerance.

THE UV RULE. The modules only read as one hull if plank courses run straight across every join,
so UVs are world-scaled and each texture tile is exactly one joining period:
  - hull timber ('wood'): one tile is 2.0 m along the hull by 2.6 m (one tier) up.
    Walls project on their dominant horizontal axis with v = -y/2.6. Tiers sit at multiples of
    2.6 m and bays at multiples of 2 m, so ten courses per tier line up at every stack and join.
    Faces within 45 degrees of horizontal (bilge floor, wall tops, treads) take u = z/2,
    v = x/2.6, so their planks run fore and aft.
  - deck slabs ('deck'): top projection, u = x/2, v = z/2; planks run fore and aft.
The texture is painted flat - no light direction baked in - so the engine's sun is the only
shading (see tools/retexture_model.py for what happens otherwise).

The albedo is procedural and seeded, so a rebuild is byte-identical. textured/texture-recipe.json
records the parameters.
"""
import json
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image

import glb_io

ROOT = Path(__file__).resolve().parent.parent
CANON = ROOT / 'canonical'
OUT = ROOT / 'textured'

PX_PER_M = 256
HULL_TILE_M = (2.0, 2.6)      # (along the hull, up one tier)
DECK_TILE_M = (2.0, 2.0)      # (across the beam, along the hull)
FLAT_NORMAL_Y = 0.7071        # |n.y| at or above this is a floor-like face

RECIPES = {
    'wood': {
        'file': 'hull_planks.jpg', 'seed': 1701, 'tile_m': HULL_TILE_M,
        'courses': 10, 'butts_per_tile': 2, 'orientation': 'courses horizontal',
        'palette': [[170, 98, 48], [184, 110, 54], [158, 88, 42], [192, 120, 62], [176, 104, 50]],
        'seam': [74, 40, 20], 'knot': [118, 62, 28],
    },
    'deck': {
        'file': 'deck_planks.jpg', 'seed': 2603, 'tile_m': DECK_TILE_M,
        'courses': 10, 'butts_per_tile': 1, 'orientation': 'planks vertical (fore-aft)',
        'palette': [[206, 150, 90], [196, 140, 82], [214, 160, 98], [200, 146, 86]],
        'seam': [96, 58, 30], 'knot': [150, 96, 52],
    },
}


def paint(length_px, width_px, recipe):
    """Rows of planks, `courses` across the width, broken at staggered butt joints.

    Everything periodic along the length uses whole harmonics of the tile and the courses divide
    the width exactly, so the tile repeats with no seam in either direction.
    """
    rng = np.random.default_rng(recipe['seed'])
    courses, butts = recipe['courses'], recipe['butts_per_tile']
    palette = np.array(recipe['palette'], dtype=np.float64)
    seam = np.array(recipe['seam'], dtype=np.float64)
    knot = np.array(recipe['knot'], dtype=np.float64)
    x = (np.arange(length_px) + 0.5) / length_px                  # 0..1 along the planks
    y = (np.arange(width_px) + 0.5) / width_px * courses          # course coordinate
    course = np.floor(y).astype(int)
    fy = (y - course)[:, None]                                      # 0 top .. 1 bottom of course
    seam_y = 2.2 / (width_px / courses)                             # ~2 px seam
    seam_x = 2.2 / length_px * butts
    image = np.zeros((width_px, length_px, 3))
    for k in range(courses):
        rows = course == k
        offset = (k * 0.382 + rng.uniform(0, 0.1)) % 1.0            # stagger the butts
        position = ((x - offset) % 1.0) * butts
        plank = np.floor(position).astype(int)
        fx = position - plank
        tone = palette[rng.integers(len(palette), size=butts)]
        tone = tone * rng.uniform(0.95, 1.05, size=(butts, 1))
        base = np.broadcast_to(tone[plank], (rows.sum(), length_px, 3)).copy()
        # Grain: a few whole harmonics give a periodic wobble; each plank gets its own phase.
        wobble = sum(rng.uniform(0.02, 0.06) * np.sin(2 * np.pi * h * x + rng.uniform(0, 6.3))
                     for h in (1, 2, 3, 5))
        phase = rng.uniform(0, 1, size=butts)[plank]
        frequency = rng.uniform(2.2, 3.4)
        fyk = np.broadcast_to(fy[rows], (rows.sum(), length_px))
        grain = np.sin(2 * np.pi * (fyk * frequency + wobble[None, :] * 2.5 + phase[None, :]))
        base[grain > 0.86] *= 0.88                                  # two flat grain tones,
        base[grain < -0.93] *= 1.05                                 # painted, not noisy
        # Painted bevel: a light lip under the upper seam, a darker band above the lower one.
        base[(fyk > seam_y) & (fyk < seam_y + 0.07)] *= 1.08
        base[(fyk > 0.90) & (fyk < 1 - seam_y)] *= 0.93
        # Knots: at most one per plank, placed away from the butts.
        for p in range(butts):
            if rng.random() < 0.3:
                cx = (offset + (p + rng.uniform(0.25, 0.75)) / butts) % 1.0
                cy, rx, ry = rng.uniform(0.35, 0.65), rng.uniform(0.012, 0.02) * butts, 0.13
                dx = (x[None, :] - cx + 0.5) % 1.0 - 0.5
                r = np.sqrt((dx / (rx / butts)) ** 2 + ((fyk - cy) / ry) ** 2)
                base[r < 1.0] = knot
                base[(r >= 1.0) & (r < 1.6)] *= 0.9
        # Treenails beside each butt joint, then the seams themselves.
        near = np.minimum(fx, 1 - fx)[None, :] * (length_px / butts)
        for ny in (0.3, 0.7):
            dist = np.sqrt((near - 7.0) ** 2 + ((fyk - ny) * (width_px / courses)) ** 2)
            base[dist < 2.2] = seam
        base[(fyk < seam_y) | (fyk > 1 - seam_y)] = seam
        base[:, (fx < seam_x / 2) | (fx > 1 - seam_x / 2)] = seam
        image[rows] = base
    return np.uint8(np.clip(np.round(image), 0, 255))


def texture(material):
    recipe = RECIPES[material]
    along, across = recipe['tile_m']
    if material == 'wood':
        pixels = paint(round(along * PX_PER_M), round(across * PX_PER_M), recipe)
    else:
        # Deck planks run along v (fore-aft), so paint rows and stand them up.
        pixels = paint(round(across * PX_PER_M), round(along * PX_PER_M), recipe).transpose(1, 0, 2)
    buffer = BytesIO()
    Image.fromarray(pixels).save(buffer, 'JPEG', quality=90, subsampling=0, optimize=True)
    return buffer.getvalue()


def uvs(material, positions, normals):
    """TEXCOORD_0 for one triangle-list primitive. positions/normals are (n, 3) float arrays."""
    x, y, z = positions[:, 0], positions[:, 1], positions[:, 2]
    # Decide per triangle from its flat normal, so all three corners share one projection.
    n = normals.reshape(-1, 3, 3)[:, 0, :]
    flat = np.repeat(np.abs(n[:, 1]) >= FLAT_NORMAL_Y, 3)
    side = np.repeat(np.abs(n[:, 0]) >= np.abs(n[:, 2]), 3)
    if material == 'deck':
        # Slab edges show the side of one plank, or its end grain, instead of a smear.
        across, along = DECK_TILE_M
        u = np.where(flat, x / across, np.where(side, -y / across, x / across))
        v = np.where(flat | side, z / along, -y / along)
    else:
        along, tier = HULL_TILE_M
        u = np.where(flat | side, z / along, x / along)
        v = np.where(flat, x / tier, -y / tier)
    return np.column_stack((u, v)).astype('<f4')


def load_canonical(part_id):
    """[(material name, position bytes, normal bytes)] straight out of the canonical GLB."""
    gltf, binary = glb_io.read(CANON / 'meshes' / f'{part_id}.glb')
    primitives = []
    for primitive in gltf['meshes'][0]['primitives']:
        if primitive.get('mode', 4) != 4 or 'indices' in primitive:
            raise SystemExit(f'{part_id}: expected an unindexed triangle list')
        name = gltf['materials'][primitive['material']]['name']
        if name not in RECIPES:
            raise SystemExit(f'{part_id}: material {name!r} has no texture recipe')
        attributes = primitive['attributes']
        primitives.append((name,
                           glb_io.accessor_bytes(gltf, binary, attributes['POSITION']),
                           glb_io.accessor_bytes(gltf, binary, attributes['NORMAL'])))
    return primitives


def add_materials(writer, gltf, images, used):
    """Embed one image per used material; returns {material name: material index}."""
    index = {}
    for name in RECIPES:
        if name not in used:
            continue
        view = writer.view(images[name])
        gltf['images'].append({'bufferView': view, 'mimeType': 'image/jpeg', 'name': RECIPES[name]['file']})
        gltf['textures'].append({'sampler': 0, 'source': len(gltf['images']) - 1})
        gltf['materials'].append({
            'name': name,
            'pbrMetallicRoughness': {'baseColorTexture': {'index': len(gltf['textures']) - 1},
                                     'baseColorFactor': [1, 1, 1, 1],
                                     'metallicFactor': 0, 'roughnessFactor': 0.85},
        })
        index[name] = len(gltf['materials']) - 1
    return index


def new_gltf():
    return {'asset': {'version': '2.0', 'generator': 'ship-kit tools/texture_kit.py'}, 'scene': 0,
            'scenes': [{'nodes': []}], 'nodes': [], 'meshes': [], 'materials': [],
            'textures': [], 'images': [],
            # 10497 = REPEAT: the tiles only line up across joins if they wrap.
            'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}]}


def add_mesh(writer, gltf, part_id, primitives, materials):
    mesh = {'name': part_id, 'primitives': []}
    for name, position, normal in primitives:
        count = len(position) // 12
        coords = np.frombuffer(position, dtype='<f4').reshape(count, 3).astype(np.float64)
        normals = np.frombuffer(normal, dtype='<f4').reshape(count, 3).astype(np.float64)
        mesh['primitives'].append({
            'attributes': {'POSITION': writer.floats(position, 'VEC3', bounds=True),
                           'NORMAL': writer.floats(normal, 'VEC3'),
                           'TEXCOORD_0': writer.floats(uvs(name, coords, normals).tobytes(), 'VEC2')},
            'material': materials[name], 'mode': 4})
    gltf['meshes'].append(mesh)
    return len(gltf['meshes']) - 1


def main():
    contract = json.loads((CANON / 'contract.json').read_text(encoding='utf-8'))
    for folder in ('meshes', 'assemblies', 'textures'):
        (OUT / folder).mkdir(parents=True, exist_ok=True)
    images = {name: texture(name) for name in RECIPES}
    for name, data in images.items():
        (OUT / 'textures' / RECIPES[name]['file']).write_bytes(data)

    canonical = {part['id']: load_canonical(part['id']) for part in contract['parts']}
    for part_id, primitives in canonical.items():
        writer, gltf = glb_io.Writer(), new_gltf()
        materials = add_materials(writer, gltf, images, {name for name, _, _ in primitives})
        gltf['nodes'].append({'name': part_id, 'mesh': add_mesh(writer, gltf, part_id, primitives, materials)})
        gltf['scenes'][0]['nodes'] = [0]
        (OUT / 'meshes' / f'{part_id}.glb').write_bytes(writer.glb(gltf))

    written = []
    for assembly in contract['assemblies']:
        if assembly['exploded']:
            continue  # Exploded offsets are not tile periods; a textured one would mislead.
        writer, gltf = glb_io.Writer(), new_gltf()
        used = {name for placement in assembly['placements'] for name, _, _ in canonical[placement['part']]}
        materials = add_materials(writer, gltf, images, used)
        meshes = {}
        for number, placement in enumerate(assembly['placements']):
            part_id = placement['part']
            if part_id not in meshes:
                meshes[part_id] = add_mesh(writer, gltf, part_id, canonical[part_id], materials)
            gltf['nodes'].append({'name': f'{number:02d}_{part_id}', 'mesh': meshes[part_id],
                                  'translation': [float(value) for value in placement['position']]})
        gltf['scenes'][0]['nodes'] = list(range(len(gltf['nodes'])))
        (OUT / 'assemblies' / f"{assembly['id']}.glb").write_bytes(writer.glb(gltf))
        written.append(assembly['id'])

    recipe = {
        'generator': 'tools/texture_kit.py',
        'pixels_per_metre': PX_PER_M,
        'flat_normal_y_threshold': FLAT_NORMAL_Y,
        'uv_rule': {
            'wood_walls': 'u = z/2 (x/2 when the face points fore/aft), v = -y/2.6',
            'wood_flat': 'u = z/2, v = x/2.6 (|normal.y| >= threshold)',
            'deck': 'flat: u = x/2, v = z/2; side edges: u = -y/2, v = z/2; fore/aft edges: u = x/2, v = -y/2',
            'joining_periods_m': {'along_hull': 2.0, 'tier': 2.6},
        },
        'lighting': 'None baked. Flat painted albedo; shading comes from the engine.',
        'materials': RECIPES,
        'parts': list(canonical),
        'assemblies': written,
    }
    (OUT / 'texture-recipe.json').write_text(json.dumps(recipe, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'parts': len(canonical), 'assemblies': written,
                      'textures': [RECIPES[n]['file'] for n in RECIPES]}, indent=2))


if __name__ == '__main__':
    main()
