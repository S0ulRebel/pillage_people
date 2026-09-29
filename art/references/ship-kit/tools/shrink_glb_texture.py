"""Shrink the textures inside a .glb, and the copies Godot extracted from it, to a size cap.

    python tools/shrink_glb_texture.py art/models/ship/cabin/cabin_window.glb [--max 1024]

A model used as delivered can carry a texture far bigger than it is ever seen: Tripo's arched
window is 1.1 m on the ship and came with a 4096 px atlas, 64 MB of video memory with its
mipmaps. Godot's size limit lives in the .import file, which this project does not keep in git
(see .gitignore), so the cap would be lost on a fresh clone; this shrinks the image itself.

Every image over --max on its longer side is resized to it (aspect kept) and re-encoded in its
own format; everything else in the file is copied byte for byte, the geometry included. Godot
extracts a .glb's embedded images next to it as <model>_<image name>, and the material uses
that file, so an extracted copy is replaced with the same shrunk bytes. Does nothing if every
image is already within the cap.
"""
import argparse
import io
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402

REPO = Path(__file__).resolve().parents[4]


def shrunk(data, mime, cap):
    """The image's bytes resized so its longer side is `cap`, or None if it already fits."""
    image = Image.open(io.BytesIO(data))
    if max(image.size) <= cap:
        return None
    scale = cap / max(image.size)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    out = io.BytesIO()
    if mime == 'image/jpeg':
        image.convert('RGB').resize(size, Image.LANCZOS).save(out, 'JPEG', quality=92)
    else:
        image.resize(size, Image.LANCZOS).save(out, 'PNG', optimize=True)
    return out.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('model', type=Path)
    parser.add_argument('--max', type=int, default=1024)
    args = parser.parse_args()
    path = args.model if args.model.is_absolute() else REPO / args.model
    gltf, binary = glb_io.read(path)

    replace = {}
    for image in gltf.get('images', []):
        if 'bufferView' not in image:
            continue
        data = glb_io.view_bytes(gltf, binary, image['bufferView'])
        smaller = shrunk(data, image.get('mimeType', ''), args.max)
        if smaller is not None:
            replace[image['bufferView']] = (smaller, image)
    if not replace:
        print(f'{path.name}: every texture is already {args.max} px or smaller; nothing to do')
        return

    # The same views in the same order, so accessors and images keep their indices.
    writer = glb_io.Writer()
    views = []
    for index, view in enumerate(gltf['bufferViews']):
        data = replace[index][0] if index in replace else glb_io.view_bytes(gltf, binary, index)
        writer.view(data)
        entry = dict(view)
        entry.update(writer.views[-1])
        views.append(entry)
    writer.views = views
    writer.accessors = gltf.get('accessors', [])
    path.write_bytes(writer.glb(gltf))

    for data, image in replace.values():
        extracted = path.with_name(f'{path.stem}_{image.get("name", "")}')
        note = ''
        if image.get('name') and extracted.exists():
            extracted.write_bytes(data)
            note = f', and {extracted.name}'
        size = Image.open(io.BytesIO(data)).size
        print(f'{path.name}: {image.get("name", "image")} shrunk to {size[0]}x{size[1]} ({len(data) // 1024} KB){note}')


if __name__ == '__main__':
    main()
