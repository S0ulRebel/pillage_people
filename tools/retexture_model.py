r"""Swap the texture inside a .glb, leaving every vertex, bone and pivot exactly where it was.

    python tools/retexture_model.py art/models/shark.glb "C:/Users/Nikola/Downloads/clean.jpg"
    python tools/retexture_model.py model.glb new.jpg --out retextured.glb
    python tools/retexture_model.py model.glb --extract current.jpg

WHY THIS EXISTS. Tripo bakes its lighting into the texture it hands back. In a world with its
own sun that arrives already shaded, so the model is lit twice: the sun adds highlights on top
of painted ones, and the shark reads as a cut-out from a different game. Regenerating the
texture without the lighting fixes it - but the fix is 1.5 MB of JPEG, and everything else in
the file is right and already working.

Re-exporting the whole model to carry that one change is the expensive way to do it. The mesh,
the rig, the pivot and the import scale are all settled by then, and a second trip through a
generator or through Blender puts every one of them back in play - the raw model this texture
came with sits 0.199 units further back along Z than the one in the game, which at the shark's
import scale of 4 is 0.8 m. This changes the pixels and nothing else, so nothing has to be
re-checked but the look.

It is also the only place the texture CAN live. Godot's import settings keep the image inside
the .glb (materials/extract=0), and .gitignore drops the .import files - so a loose .jpg beside
the model is a copy the game never reads. tools/README.md makes the same point about a model's
orientation and scale, and for the same reason.

Stdlib only: this is a binary patch on a container, not a modelling operation.
"""
import argparse
import json
import struct
from pathlib import Path

HEADER = b"glTF"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}


def split(raw):
    """The chunks of a .glb, in order. Returns [(type, bytes), ...]."""
    if raw[:4] != HEADER:
        raise SystemExit("not a .glb (no glTF magic); a .gltf with a separate .bin is not handled")
    chunks = []
    offset = 12
    while offset < len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        chunks.append((kind, raw[offset + 8:offset + 8 + length]))
        # chunkLength already covers the chunk's own padding, but tolerate a writer that leaves
        # it out rather than reading a byte into the next header.
        offset += 8 + length + (-length % 4)
    return chunks


def join(gltf, binary):
    """A .glb from a parsed JSON chunk and a binary chunk, padded as the spec asks."""
    text = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)            # JSON pads with spaces
    binary += b"\x00" * (-len(binary) % 4)     # BIN pads with zeros
    total = 12 + 8 + len(text) + 8 + len(binary)
    out = bytearray(HEADER)
    out += struct.pack("<II", 2, total)
    out += struct.pack("<II", len(text), JSON_CHUNK) + text
    out += struct.pack("<II", len(binary), BIN_CHUNK) + binary
    return bytes(out)


def jpeg_size(data):
    """Width and height out of a JPEG's frame header, without a decoder."""
    if data[:2] != b"\xff\xd8":
        return None
    at = 2
    while at < len(data) - 9:
        if data[at] != 0xFF:
            at += 1
            continue
        marker = data[at + 1]
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width = struct.unpack_from(">HH", data, at + 5)
            return width, height
        at += 2 + struct.unpack_from(">H", data, at + 2)[0]
    return None


def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack_from(">II", data, 16)


def picture_size(data):
    return jpeg_size(data) or png_size(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", help="the .glb to patch")
    ap.add_argument("texture", nargs="?", help="the image to put in it")
    ap.add_argument("--out", help="write here instead of over the model")
    ap.add_argument("--extract", metavar="FILE",
                    help="write the model's CURRENT image here and stop")
    ap.add_argument("--index", type=int, default=0, help="which image, if there are several")
    args = ap.parse_args()

    model = Path(args.model)
    chunks = split(model.read_bytes())
    gltf = json.loads(next(body for kind, body in chunks if kind == JSON_CHUNK))
    binary = next((body for kind, body in chunks if kind == BIN_CHUNK), b"")

    images = gltf.get("images", [])
    if not images:
        raise SystemExit("%s carries no image at all" % model.name)
    if args.index >= len(images):
        raise SystemExit("%s has %d image(s); asked for index %d"
                         % (model.name, len(images), args.index))
    image = images[args.index]
    if "bufferView" not in image:
        raise SystemExit("that image is a URI, not embedded - replace the file it points at")
    view_index = image["bufferView"]
    views = gltf["bufferViews"]
    start = views[view_index].get("byteOffset", 0)
    current = binary[start:start + views[view_index]["byteLength"]]

    if args.extract:
        Path(args.extract).write_bytes(current)
        print("%s image %d -> %s (%.2f MB, %s, %s)"
              % (model.name, args.index, args.extract, len(current) / 1e6,
                 image.get("mimeType", "?"), picture_size(current)))
        return 0
    if not args.texture:
        raise SystemExit("give a texture to put in, or --extract to take the current one out")

    fresh = Path(args.texture).read_bytes()
    mime = MIME.get(Path(args.texture).suffix.lower())
    if mime is None:
        raise SystemExit("textures must be .jpg or .png - glTF carries no others")
    was, now = picture_size(current), picture_size(fresh)
    if was and now and was != now:
        # Not fatal: UVs live in 0..1 and do not care about resolution. Worth saying, because a
        # texture that is suddenly a quarter the size is usually a mistake rather than a plan.
        print("note: %dx%d -> %dx%d" % (was[0], was[1], now[0], now[1]))

    # Every buffer view repacked in its original order, with this one's bytes swapped. Repacked
    # rather than patched in place because the new image is a different length, and every view
    # sitting after it in the buffer would otherwise read from the wrong offset.
    order = sorted(range(len(views)), key=lambda i: views[i].get("byteOffset", 0))
    for first, second in zip(order, order[1:]):
        ends = views[first].get("byteOffset", 0) + views[first]["byteLength"]
        if views[second].get("byteOffset", 0) < ends:
            raise SystemExit("buffer views overlap - this file shares bytes between views, and "
                             "repacking it would corrupt one of them")
    packed = bytearray()
    moved = {}
    for index in order:
        at = views[index].get("byteOffset", 0)
        data = fresh if index == view_index else binary[at:at + views[index]["byteLength"]]
        packed += b"\x00" * (-len(packed) % 4)
        moved[index] = len(packed)
        packed += data
    for index in order:
        views[index]["byteOffset"] = moved[index]
    views[view_index]["byteLength"] = len(fresh)
    image["mimeType"] = mime
    gltf["buffers"][0]["byteLength"] = len(packed)

    out = Path(args.out) if args.out else model
    # Written beside the target and moved into place, so a failure halfway through leaves the
    # model that was working still working.
    scratch = out.with_suffix(out.suffix + ".part")
    scratch.write_bytes(join(gltf, bytes(packed)))
    scratch.replace(out)
    print("%s: image %d %.2f MB -> %.2f MB, file now %.2f MB"
          % (out.name, args.index, len(current) / 1e6, len(fresh) / 1e6, out.stat().st_size / 1e6))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
