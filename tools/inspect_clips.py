r"""Report what a rigged GLB's animation clips actually do.

    python inspect_clips.py captain.glb
    python inspect_clips.py captain.glb --clip jump --profile

Names lie. A clip called "Jump" turned out to be a run-up - two approach steps, a hop, a
landing and a recovery step across 2.20 seconds - and playing it from the start showed a
character who shuffled in mid-air and never left the ground. Nothing in the file said so.
The only way to know was to work out where the feet were.

So: for each clip this prints its length, how far the hips travel (root motion that will
fight a controller, or double up with it), and how long the feet spend off the ground.
--profile draws the foot height over time, which is what shows the shape - approach steps,
the push-off, the apex, the touchdown - and tells you which slice is worth keeping.

Foot height is measured against the clip's own lowest point rather than y=0, because a rig
that stands slightly above or below the origin would otherwise report every frame airborne.
"""
import argparse
import json
import struct
from pathlib import Path

import numpy as np

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = path.read_bytes()
    if struct.unpack("<I", data[:4])[0] != 0x46546C67:
        raise SystemExit(f"{path.name} is not a GLB")
    json_length = struct.unpack("<I", data[12:16])[0]
    return json.loads(data[20:20 + json_length].decode("utf-8")), data[20 + json_length + 8:]


def accessor(header, blob, index):
    spec = header["accessors"][index]
    view = header["bufferViews"][spec["bufferView"]]
    offset = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    size = COUNTS[spec["type"]]
    values = np.frombuffer(blob, dtype=np.dtype("<" + COMPONENTS[spec["componentType"]]),
                           count=spec["count"] * size, offset=offset)
    return values.reshape(spec["count"], size).astype(np.float64)


def matrix(translation, rotation, scale):
    x, y, z, w = rotation
    out = np.eye(4)
    out[:3, :3] = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]) * scale
    out[:3, 3] = translation
    return out


class Rig:
    def __init__(self, header, blob):
        self.header, self.blob = header, blob
        self.parent = {}
        for index, node in enumerate(header["nodes"]):
            for child in node.get("children", []):
                self.parent[child] = index
        self.by_name = {}
        for index, node in enumerate(header["nodes"]):
            self.by_name.setdefault(node.get("name", "").split(":")[-1], index)

    def find(self, *candidates):
        for name in candidates:
            if name in self.by_name:
                return self.by_name[name]
        return None

    def sampled(self, clip):
        """Every channel of a clip, keyed by (node, path)."""
        table = {}
        for channel in clip["channels"]:
            spec = clip["samplers"][channel["sampler"]]
            table[(channel["target"]["node"], channel["target"]["path"])] = (
                accessor(self.header, self.blob, spec["input"]).ravel(),
                accessor(self.header, self.blob, spec["output"]),
                spec.get("interpolation", "LINEAR"))
        return table

    def world(self, table, node, moment):
        chain = []
        cursor = node
        while cursor is not None:
            chain.append(cursor)
            cursor = self.parent.get(cursor)
        out = np.eye(4)
        for index in reversed(chain):
            node_spec = self.header["nodes"][index]
            parts = []
            for path, default in (("translation", [0, 0, 0]), ("rotation", [0, 0, 0, 1]),
                                  ("scale", [1, 1, 1])):
                if (index, path) in table:
                    times, values, _ = table[(index, path)]
                    at = int(np.searchsorted(times, moment, side="right")) - 1
                    parts.append(values[max(0, min(at, len(times) - 1))])
                else:
                    parts.append(np.array(node_spec.get(path, default), dtype=float))
            out = out @ matrix(*parts)
        return out[:3, 3]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--clip", action="append", help="only these (repeatable)")
    ap.add_argument("--profile", action="store_true", help="draw foot height over time")
    args = ap.parse_args()

    header, blob = load(Path(args.source))
    if not header.get("animations"):
        raise SystemExit("no animations in this file")
    rig = Rig(header, blob)
    hips = rig.find("Hips", "hips", "mixamorig:Hips")
    foot = rig.find("LeftToeBase", "LeftToe_End", "LeftFoot")
    if hips is None or foot is None:
        raise SystemExit("cannot find Hips and a left foot - is this a Mixamo-named rig?")

    print(f"{Path(args.source).name}: {len(header['animations'])} clips, "
          f"{len(header['skins'][0]['joints'])} joints\n")
    print(f"{'clip':<26}{'length':>7}{'drift':>8}{'rise':>7}{'air':>7}   shape")
    for clip in header["animations"]:
        if args.clip and clip["name"] not in args.clip:
            continue
        table = rig.sampled(clip)
        times = np.unique(np.concatenate([t for t, _, _ in table.values()]))
        drift = rise = 0.0
        if (hips, "translation") in table:
            track = table[(hips, "translation")][1]
            # Two different things, and summing them together hides both. Horizontal
            # displacement from first key to last is root motion - the clip walks the
            # character somewhere, and a controller that also moves him makes him slide or
            # travel twice. Vertical range is the bob or the launch, which is wanted: a walk
            # with no bob is a character on rails.
            drift = float(np.linalg.norm(track[-1, [0, 2]] - track[0, [0, 2]]))
            rise = float(track[:, 1].max() - track[:, 1].min())
        heights = np.array([rig.world(table, foot, t)[1] for t in times])
        lift = heights - np.percentile(heights, 5)
        span = max(lift.max(), 1e-9)
        up = lift > span * 0.25
        airborne = float(times[up][-1] - times[up][0]) if up.any() else 0.0
        # ASCII on purpose: the Windows console this runs on is cp1252 and block-drawing
        # characters abort the whole report with an encoding error.
        bars = "".join("._-=co0#@"[min(8, int(v / span * 8.4))]
                       for v in lift[np.linspace(0, len(lift) - 1, 40).astype(int)])
        print(f"{clip['name']:<26}{times[-1]:6.2f}s{drift:8.1f}{rise:7.1f}{airborne:6.2f}s   {bars}")
        if args.profile:
            for i in range(len(times)):
                print(f"     {times[i]:6.2f}s {lift[i]:8.4f}  "
                      f"{'#' * int(lift[i] / span * 40)}")
    print("\ndrift: how far the hips finish from where they started, horizontally. Above "
          "about 1\n       this is root motion, and a controller that also moves the "
          "character will fight\n       it - re-export the clip In Place."
          "\nrise:  vertical range of the hips: bob on a walk, the crouch and launch on a "
          "jump.\n       Worth keeping, unless the controller supplies the same arc itself.")


if __name__ == "__main__":
    main()
