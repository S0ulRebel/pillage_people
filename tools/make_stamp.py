r"""Make a terrain stamp file (.stamp) from a height map, or report what is in one.

    python tools/make_stamp.py r16 world/terrain_stamp/stamps/mountain.r16 mountain.stamp
    python tools/make_stamp.py r16 island.r16 island.stamp --signed
    python tools/make_stamp.py r16 dunes.r16 dunes.stamp --opacity dunes_mask.r16
    python tools/make_stamp.py png crater.png crater.stamp
    python tools/make_stamp.py info world/terrain_stamp/stamps/mountain.stamp

WHAT A .stamp HOLDS. Two 16-bit numbers per sample, height and opacity, after a 16-byte header:

    bytes 0-3    b"STMP"
    bytes 4-7    version, uint32, currently 1
    bytes 8-11   columns, uint32 - samples along the stamp's own X (its `length`)
    bytes 12-15  rows, uint32 - samples along the stamp's own Z (its `width`)
    then rows x columns samples, row by row, each two little-endian uint16:
                 height   32768 is zero; brighter raises, darker lowers, and the stamp's
                          `height` in metres is what full white (65535) adds
                 opacity  0 leaves the ground alone, 65535 applies the stamp in full

WHY MID-GREY IS ZERO. One image can raise and lower at once - a crater with a raised rim, a
canyon with banks. The old .r16 stamps had black as zero and could only go one way, and
opacity is what makes the change safe: where it is 0 the height does not matter, so an edge
never leaves a step however the height channel drifts.

WHY NOT PNG. Godot's image loader cuts a 16-bit PNG down to 8-bit, and on a 60 m mountain 256
steps are 23 cm terraces. The game reads .stamp raw with FileAccess, so nothing on the way in
can round it. A 16-bit PNG is fine as the INPUT here - this reads it itself.

THE CONVERSIONS.
  r16       An old stamp: one uint16 per sample, black = nothing. Its heights are halved into
            the upper half of the range (one bit of precision lost - a 40 m mountain goes from
            0.6 mm steps to 1.2 mm) and opacity is full everywhere, so as an Add stamp it lands
            exactly where it did. --signed copies the numbers across untouched instead, for a
            map that already puts zero at mid-grey (or that is to be read that way on purpose -
            the island). --opacity takes a second .r16 of the same size as the opacity.
  png       Grey, grey + alpha, RGB or RGBA; 8 or 16 bits. Mid-grey is zero; the alpha channel,
            if there is one, is the opacity. --unsigned reads black as zero, as an old stamp.

Stdlib only, like retexture_model.py: this is a container, not an image operation.
"""
import argparse
import math
import struct
import sys
import zlib
from array import array
from pathlib import Path

MAGIC = b"STMP"
VERSION = 1
ZERO = 32768
FULL = 65535


def _little(values):
    """The array's bytes, little-endian whatever machine this runs on."""
    if sys.byteorder == "big":
        values = array("H", values)
        values.byteswap()
    return values.tobytes()


def write_stamp(path, columns, rows, heights, opacities):
    if len(heights) != columns * rows or len(opacities) != columns * rows:
        raise SystemExit(f"{path}: {len(heights)} heights and {len(opacities)} opacities for "
                         f"{columns} x {rows} samples")
    interleaved = array("H", bytes(4 * columns * rows))
    interleaved[0::2] = array("H", heights)
    interleaved[1::2] = array("H", opacities)
    with open(path, "wb") as out:
        out.write(MAGIC + struct.pack("<III", VERSION, columns, rows))
        out.write(_little(interleaved))


def read_stamp(path):
    data = Path(path).read_bytes()
    if data[:4] != MAGIC:
        raise SystemExit(f"{path}: not a .stamp (starts {data[:4]!r})")
    version, columns, rows = struct.unpack_from("<III", data, 4)
    if version != VERSION:
        raise SystemExit(f"{path}: version {version}, this reads {VERSION}")
    samples = array("H")
    samples.frombytes(data[16:16 + 4 * columns * rows])
    if sys.byteorder == "big":
        samples.byteswap()
    return columns, rows, samples[0::2], samples[1::2]


def read_r16(path):
    samples = array("H")
    samples.frombytes(Path(path).read_bytes())
    if sys.byteorder == "big":
        samples.byteswap()
    side = math.isqrt(len(samples))
    if side * side != len(samples):
        raise SystemExit(f"{path}: {len(samples)} samples is not a square")
    return side, samples


def read_png(path):
    """(columns, rows, first channel, alpha or None), all as uint16 values."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path}: not a PNG")
    at = 8
    idat = bytearray()
    header = None
    while at < len(data):
        length, kind = struct.unpack_from(">I4s", data, at)
        body = data[at + 8:at + 8 + length]
        at += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    columns, rows, depth, colour, _, _, interlace = header
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(colour)
    if channels is None or depth not in (8, 16) or interlace:
        raise SystemExit(f"{path}: colour type {colour}, {depth} bits, interlace {interlace} - "
                         "this reads non-interlaced grey, grey+alpha, RGB or RGBA at 8 or 16 bits")
    unit = depth // 8
    pixel = channels * unit
    stride = columns * pixel
    raw = zlib.decompress(bytes(idat))
    lines = []
    previous = bytearray(stride)
    for row in range(rows):
        start = row * (stride + 1)
        kind = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(pixel, stride):
                line[i] = (line[i] + line[i - pixel]) & 255
        elif kind == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 255
        elif kind == 3:
            for i in range(stride):
                left = line[i - pixel] if i >= pixel else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(stride):
                a = line[i - pixel] if i >= pixel else 0
                b = previous[i]
                c = previous[i - pixel] if i >= pixel else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                predictor = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + predictor) & 255
        lines.append(line)
        previous = line
    joined = b"".join(lines)
    if unit == 2:
        values = array("H", joined)
        if sys.byteorder == "little":
            values.byteswap()          # PNG is big-endian
    else:
        values = array("H", (v * 257 for v in joined))
    first = values[0::channels]
    alpha = values[channels - 1::channels] if colour in (4, 6) else None
    return columns, rows, first, alpha


def from_r16(args):
    side, heights = read_r16(args.source)
    if not args.signed:
        heights = array("H", (ZERO + (u >> 1) for u in heights))
    if args.opacity:
        mask_side, opacities = read_r16(args.opacity)
        if mask_side != side:
            raise SystemExit(f"{args.opacity} is {mask_side} square, {args.source} is {side}")
    else:
        opacities = array("H", [FULL]) * (side * side)
    write_stamp(args.out, side, side, heights, opacities)
    report(args.out)


def from_png(args):
    columns, rows, heights, alpha = read_png(args.source)
    if args.unsigned:
        heights = array("H", (ZERO + (u >> 1) for u in heights))
    opacities = alpha if alpha is not None else array("H", [FULL]) * (columns * rows)
    write_stamp(args.out, columns, rows, heights, opacities)
    report(args.out)


def report(path):
    columns, rows, heights, opacities = read_stamp(path)
    border = [i for i in range(columns)] + [(rows - 1) * columns + i for i in range(columns)] \
        + [r * columns for r in range(rows)] + [r * columns + columns - 1 for r in range(rows)]
    loud = max(abs(heights[i] - ZERO) * opacities[i] / FULL for i in border) / ZERO
    print(f"{path}: {columns} x {rows}, version {VERSION}")
    print(f"  height  {(min(heights) - ZERO) / ZERO:+.5f} to {(max(heights) - ZERO) / ZERO:+.5f}"
          " of the stamp's height")
    print(f"  opacity {min(opacities) / FULL:.5f} to {max(opacities) / FULL:.5f}")
    print(f"  at the border: height x opacity reaches {loud:.5f} - "
          + ("fades out cleanly" if loud < 0.001 else
             "NOT zero: in Add mode this edge is a step unless the stamp's border_fade covers it"))


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    r16 = commands.add_parser("r16", help="an old .r16 stamp (black = nothing) to .stamp")
    r16.add_argument("source")
    r16.add_argument("out")
    r16.add_argument("--signed", action="store_true",
                     help="copy the numbers as they are: the map already has zero at mid-grey")
    r16.add_argument("--opacity", help="a second .r16, the same size, to use as the opacity")
    r16.set_defaults(run=from_r16)
    png = commands.add_parser("png", help="a grey (+ alpha) PNG, mid-grey = zero, to .stamp")
    png.add_argument("source")
    png.add_argument("out")
    png.add_argument("--unsigned", action="store_true", help="black is zero, as an old stamp")
    png.set_defaults(run=from_png)
    info = commands.add_parser("info", help="what a .stamp holds")
    info.add_argument("stamp")
    info.set_defaults(run=lambda args: report(args.stamp))
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
