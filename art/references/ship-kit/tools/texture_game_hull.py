"""Give the game's own hull the kit's plank texture, without moving a vertex.

    python tools/texture_game_hull.py

The game does not load canonical DOUBLE_DECK.glb. It loads art/models/ship/double_deck.glb,
a copy whose bow was later raked forward (to Z=-3.2) and stern bulged aft (to Z=16.7) - see
the commits that touched it. Swapping in textured/assemblies/DOUBLE_DECK.glb would silently
undo that shaping, so this textures the game's file in place instead.

Same UV rule and same texture as tools/texture_kit.py, applied to the positions actually in
the file, so the planks follow the rake and the bulge. POSITION and NORMAL bytes are copied
unchanged, and checked afterwards: this refuses to write if a single byte of them differs.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402
import texture_kit  # noqa: E402

REPO = Path(__file__).resolve().parents[4]
HULL = REPO / 'art' / 'models' / 'ship' / 'double_deck.glb'


def primitives(path):
    gltf, binary = glb_io.read(path)
    out = []
    for primitive in gltf['meshes'][0]['primitives']:
        if primitive.get('mode', 4) != 4 or 'indices' in primitive:
            raise SystemExit(f'{path}: expected an unindexed triangle list, like the kit writes')
        a = primitive['attributes']
        out.append((gltf['materials'][primitive['material']]['name'],
                    glb_io.accessor_bytes(gltf, binary, a['POSITION']),
                    glb_io.accessor_bytes(gltf, binary, a['NORMAL'])))
    return out


def textured(source, name='double_deck'):
    """A .glb of one node, `name`: these (material, POSITION bytes, NORMAL bytes) primitives
    with the kit's plank texture and UVs laid on them."""
    images = {name: texture_kit.texture(name) for name in texture_kit.RECIPES}
    writer, gltf = glb_io.Writer(), texture_kit.new_gltf()
    materials = texture_kit.add_materials(writer, gltf, images, {name for name, _, _ in source})
    gltf['nodes'].append({'name': name, 'mesh': texture_kit.add_mesh(writer, gltf, name, source, materials)})
    gltf['scenes'][0]['nodes'] = [0]
    return writer.glb(gltf)


def main():
    source = primitives(HULL)
    if len(glb_io.read(HULL)[0]['nodes']) != 1:
        raise SystemExit(f'{HULL}: expected one node, as the kit writes it')
    data = textured(source)

    staged = HULL.with_suffix('.textured.tmp')
    staged.write_bytes(data)
    try:
        after = primitives(staged)
        same = [(a[0], a[1], a[2]) == (b[0], b[1], b[2]) for a, b in zip(source, after)]
        if len(after) != len(source) or not all(same):
            raise SystemExit('the textured hull does not carry the same POSITION/NORMAL bytes; not written')
        staged.replace(HULL)
    finally:
        staged.unlink(missing_ok=True)
    print(f'{HULL.relative_to(REPO)}: {sum(len(p[1]) // 36 for p in source)} triangles textured, geometry byte-identical')


if __name__ == '__main__':
    main()
