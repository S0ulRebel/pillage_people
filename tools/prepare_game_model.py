r"""Scale a generated GLB to a real height and copy it into the game.

    python prepare_game_model.py "C:\Users\...\Downloads\model.glb" --height 1.9 --name captain

Tripo normalises everything to a unit cube, so a character arrives 1.0 units tall. In Godot
that is a one metre pirate, and it has to be scaled somewhere.

DO NOT WRITE A SCALE ONTO THE glTF ROOT NODE. That was the first version of this script and
it produced a visibly distorted character: a skinned mesh carries inverse-bind matrices that
do not scale with the node, so skeleton and skin end up in different spaces. Nothing catches
it - the file loads, the bounds report the height asked for, and only the render shows it.

So the file is copied untouched and the scale is reported. player.gd measures the model on
load and scales the instantiated node, which moves skeleton and skin together.
"""
import argparse
import json
import shutil
import struct
from pathlib import Path

GAME = Path(r"D:\code\pillage_people")


def read_glb(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack("<III", data[:12])
    if magic != 0x46546C67:
        raise SystemExit(f"{path.name} is not a GLB")
    json_length, _ = struct.unpack("<II", data[12:20])
    header = json.loads(data[20:20 + json_length].decode("utf-8"))
    return data, header, json_length


def model_height(header):
    """Tallest extent across every mesh, from the accessors' own min/max."""
    lows, highs = [], []
    for mesh in header.get("meshes", []):
        for primitive in mesh["primitives"]:
            accessor = header["accessors"][primitive["attributes"]["POSITION"]]
            if "min" in accessor and "max" in accessor:
                lows.append(accessor["min"][1])
                highs.append(accessor["max"][1])
    if not lows:
        raise SystemExit("no POSITION bounds in the file, cannot measure it")
    return min(lows), max(highs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--height", type=float, default=1.9,
                    help="finished height in metres (the player collider is 1.9)")
    ap.add_argument("--name", default="captain")
    ap.add_argument("--out", help="where to write it (default: the game's art/models)")
    ap.add_argument("--bake", action="store_true",
                    help="write the scale onto the root node; refused on a rigged file")
    args = ap.parse_args()

    source = Path(args.source)
    if not source.is_file():
        raise SystemExit(f"No such file: {source}")

    data, header, json_length = read_glb(source)
    low, high = model_height(header)
    current = high - low
    factor = args.height / current

    out_dir = Path(args.out) if args.out else GAME / "art" / "models"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{args.name}.glb"
    skins = len(header.get("skins", []))

    if args.bake:
        # Only ever on an unrigged file. The warning at the top of this script is about skinned
        # meshes: their inverse-bind matrices do not scale with the node, so skeleton and skin
        # end up in different spaces and the character arrives shattered. With no skin there are
        # no such matrices and nothing to fall out of step - the scale is just a transform on a
        # static mesh, and baking it here beats setting nodes/root_scale in the .import, because
        # .import files are gitignored and that setting is lost on every fresh clone.
        if skins:
            raise SystemExit("--bake refused: this file is rigged. Writing a scale onto the "
                             "root of a skinned mesh leaves its inverse-bind matrices behind "
                             "and distorts it. Use nodes/root_scale in the .import instead.")
        roots = header["scenes"][header.get("scene", 0)]["nodes"]
        for index in roots:
            node = header["nodes"][index]
            if "matrix" in node:
                raise SystemExit("root node uses a matrix rather than TRS; not touching it")
            existing = node.get("scale", [1.0, 1.0, 1.0])
            node["scale"] = [existing[axis] * factor for axis in range(3)]
        encoded = json.dumps(header, separators=(",", ":")).encode("utf-8")
        encoded += b" " * (-len(encoded) % 4)
        binary = data[20 + json_length + 8:]
        binary = binary[:struct.unpack("<I", data[20 + json_length:20 + json_length + 4])[0]]
        binary += b"\x00" * (-len(binary) % 4)
        out.write_bytes(
            struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(encoded) + 8 + len(binary))
            + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
            + struct.pack("<II", len(binary), 0x004E4942) + binary)
    else:
        # Copied byte for byte. See the note at the top: writing the scale into the file is what
        # distorted the first captain, and every check still passed while it was wrong.
        shutil.copy(source, out)

    joints = len(header["skins"][0]["joints"]) if skins else 0
    mixamo = sum(1 for j in header["skins"][0]["joints"]
                 if header["nodes"][j].get("name", "").lower().startswith("mixamorig")) if skins else 0
    print(f"{source.name}")
    print(f"  {current:.3f} units tall, feet at {low:.3f}")
    print(f"  needs scaling by {factor:.3f} to reach {args.height} m")
    if skins:
        print(f"  rig: {joints} bones, {mixamo} of them Mixamo-named")
    print(f"  -> {out}")
    if args.bake:
        print(f"\nScale {factor:.3f} baked onto the root node. Safe here because the file has "
              f"no skin:\nthere are no inverse-bind matrices to be left behind, so nothing can "
              f"fall out of step\nwith the mesh. It now arrives at {args.height} m with no "
              f".import setting to remember.")
    elif skins:
        print("\nCopied unchanged. It is skinned, so the scale is NOT written into the file:")
        print("player.gd measures it on load and scales the instantiated node. Writing a")
        print("scale onto the glTF root leaves the inverse-bind matrices behind, and the")
        print("character arrives distorted while every check still reports the right height.")
    else:
        print("\nCopied unchanged. Set model_height on the player, or scale it where used.")


if __name__ == "__main__":
    main()
