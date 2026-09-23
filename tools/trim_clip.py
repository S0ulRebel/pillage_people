r"""Clip surgery on a rigged GLB - cut, pin, rename, drop - without a Blender round-trip.

    python trim_clip.py captain.glb --cut jump=jumping_up:0.53:0.87 --pin jump \
        --rename walking=walk --keep idle,walk,run,jump,fall

Each --cut is  new_name=source_clip:start:end  in seconds. Cuts are all taken from the
file as it was read, so a clip can be re-cut from itself and several clips can be carved
out of one source in a single pass. Then --pin, --rename and --keep apply to the result.

Why this exists: Mixamo's clip names describe the motion, not what a game needs. "Jumping"
is a run-up - two approach steps, a hop, a landing and a recovery step, 2.20s end to end -
and a platformer controller leaves the ground instantly and is back down in 0.6s, so
playing it from the start shows an approach shuffle and the character never jumps at all.
Even "Jumping Up" spends its first 0.53s crouching. The usable part is the launch.

--pin holds the hips at their first key, which is for clips whose root motion the game
already supplies. Measure before reaching for it. Pinning a clip whose whole read is in
the root leaves a character waving his legs while his body hangs still - that happened
here once. It is safe when the pose carries the motion by itself: in the launch window of
"Jumping Up" the legs drive down and then tuck up through 26% of body height on their own,
while the hips climb 34% of body height that the controller's arc would add a second time.

Done in Python rather than Blender on purpose. Every Blender pass in this project has
cost something on the way back out - the exporter writes alphaMode BLEND and drops
metallic/roughness, and its FBX bone rolls do not survive contact with a glTF rig. Here
nothing is reinterpreted: the mesh, the skin, the materials and the untouched clips keep
their original bytes, and only the sampler data for the named clips is rewritten.

Resampling holds to each sampler's own interpolation - linear between keys, or the
previous key's value for STEP - and rotations are slerped, not lerped, so a fast spin
does not cut the corner. The endpoints are sampled exactly, so the cut starts and ends
on the pose that was actually at that instant rather than the nearest key.
"""
import argparse
import json
import struct
from pathlib import Path

import numpy as np

COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FPS = 30.0


def load(path):
    data = path.read_bytes()
    if struct.unpack("<I", data[:4])[0] != 0x46546C67:
        raise SystemExit(f"{path.name} is not a GLB")
    json_length = struct.unpack("<I", data[12:16])[0]
    header = json.loads(data[20:20 + json_length].decode("utf-8"))
    binary = data[20 + json_length + 8:]
    declared = struct.unpack("<I", data[20 + json_length:20 + json_length + 4])[0]
    return header, bytearray(binary[:declared])


def accessor(header, blob, index):
    spec = header["accessors"][index]
    view = header["bufferViews"][spec["bufferView"]]
    offset = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    size = COUNTS[spec["type"]]
    values = np.frombuffer(bytes(blob), dtype=np.dtype("<" + COMPONENTS[spec["componentType"]]),
                           count=spec["count"] * size, offset=offset)
    return values.reshape(spec["count"], size).astype(np.float64)


def append(header, blob, array, kind):
    """Add an accessor for this array and return its index."""
    packed = np.ascontiguousarray(array, dtype="<f4").tobytes()
    while len(blob) % 4:
        blob.append(0)
    offset = len(blob)
    blob.extend(packed)
    header["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(packed)})
    spec = {"bufferView": len(header["bufferViews"]) - 1, "componentType": 5126,
            "count": len(array), "type": kind}
    if kind == "SCALAR":
        # The spec requires min/max on an animation's input accessor; players use it to
        # know a clip's length without walking the keys.
        spec["min"] = [float(array.min())]
        spec["max"] = [float(array.max())]
    header["accessors"].append(spec)
    return len(header["accessors"]) - 1


def slerp(a, b, t):
    """Shortest-arc interpolation between two xyzw quaternions."""
    dot = float(np.dot(a, b))
    if dot < 0.0:
        b, dot = -b, -dot
    if dot > 0.9995:
        out = a + t * (b - a)
        return out / np.linalg.norm(out)
    theta = np.arccos(np.clip(dot, -1.0, 1.0))
    sin_theta = np.sin(theta)
    return (np.sin((1 - t) * theta) * a + np.sin(t * theta) * b) / sin_theta


def resample(times, values, at, step, rotation):
    out = np.empty((len(at), values.shape[1]))
    for i, moment in enumerate(at):
        j = int(np.searchsorted(times, moment, side="right")) - 1
        j = max(0, min(j, len(times) - 1))
        if step or j + 1 >= len(times) or times[j + 1] <= times[j]:
            out[i] = values[j]
            continue
        f = (moment - times[j]) / (times[j + 1] - times[j])
        f = float(np.clip(f, 0.0, 1.0))
        if rotation:
            out[i] = slerp(values[j], values[j + 1], f)
        else:
            out[i] = values[j] * (1 - f) + values[j + 1] * f
    return out


def clip_length(header, blob, clip):
    return max(float(accessor(header, blob, clip["samplers"][c["sampler"]]["input"]).max())
               for c in clip["channels"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--cut", action="append", default=[],
                    metavar="NAME=CLIP:START:END", help="repeatable")
    ap.add_argument("--pin", action="append", default=[], metavar="CLIP",
                    help="hold this clip's hips still - see the note below")
    ap.add_argument("--rename", action="append", default=[], metavar="OLD=NEW")
    ap.add_argument("--keep", help="comma-separated; everything else is dropped")
    ap.add_argument("--out", help="default: overwrite the source")
    args = ap.parse_args()

    source = Path(args.source)
    header, blob = load(source)
    originals = {a["name"]: a for a in header["animations"]}

    cuts = []
    for text in args.cut:
        name, _, rest = text.partition("=")
        clip_name, start, end = rest.split(":")
        if clip_name not in originals:
            raise SystemExit(f"no clip called {clip_name}. Have: {', '.join(originals)}")
        cuts.append((name, clip_name, float(start), float(end)))

    for index, (name, clip_name, start, end) in enumerate(cuts):
        full = clip_length(header, blob, originals[clip_name])
        if start < 0 or start >= full:
            raise SystemExit(f"{name}: starts at {start}s, but {clip_name} is only "
                             f"{full:.2f}s long")
        if end > full:
            # Asking to run to the end is normal, and a clip's length is rarely a round
            # number - 26 frames at 30fps is 0.8667s, so "0.87" would otherwise be refused.
            cuts[index] = (name, clip_name, start, full)
        elif end <= start:
            raise SystemExit(f"{name}: {start}-{end}s is not a forward range")

    built = []
    for name, clip_name, start, end in cuts:
        clip = originals[clip_name]
        # Every key instant that falls inside the window, plus the exact endpoints, so the
        # cut opens and closes on the true pose rather than drifting to the nearest key.
        keys = np.unique(np.concatenate(
            [accessor(header, blob, clip["samplers"][c["sampler"]]["input"]).ravel()
             for c in clip["channels"]]))
        inside = keys[(keys > start) & (keys < end)]
        grid = np.arange(start, end, 1.0 / FPS)
        at = np.unique(np.concatenate([[start], inside, grid, [end]]))
        at = at[(at >= start) & (at <= end)]

        samplers, channels = [], []
        for channel in clip["channels"]:
            spec = clip["samplers"][channel["sampler"]]
            path = channel["target"]["path"]
            times = accessor(header, blob, spec["input"]).ravel()
            values = accessor(header, blob, spec["output"])
            picked = resample(times, values, at, spec.get("interpolation") == "STEP",
                              path == "rotation")
            if path == "rotation":
                picked /= np.linalg.norm(picked, axis=1, keepdims=True)
            samplers.append({
                "input": append(header, blob, (at - start).astype("f4"), "SCALAR"),
                "output": append(header, blob, picked, COUNTS and
                                 {"translation": "VEC3", "scale": "VEC3",
                                  "rotation": "VEC4", "weights": "SCALAR"}[path]),
                "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": dict(channel["target"])})
        built.append({"name": name, "samplers": samplers, "channels": channels})
        print(f"  {name:6s} <- {clip_name} [{start:.2f}-{end:.2f}s]  "
              f"{end - start:.2f}s, {len(at)} keys")

    replaced = {name for name, *_ in cuts}
    header["animations"] = [a for a in header["animations"] if a["name"] not in replaced] + built
    clips = {a["name"]: a for a in header["animations"]}

    if args.pin:
        hips = next((i for i, n in enumerate(header["nodes"])
                     if n.get("name", "").split(":")[-1] == "Hips"), None)
        if hips is None:
            raise SystemExit("--pin needs a bone called Hips and there isn't one")
        for name in args.pin:
            if name not in clips:
                raise SystemExit(f"--pin {name}: no such clip")
            for channel in clips[name]["channels"]:
                if channel["target"]["node"] != hips or channel["target"]["path"] != "translation":
                    continue
                spec = clips[name]["samplers"][channel["sampler"]]
                times = accessor(header, blob, spec["input"]).ravel()
                values = accessor(header, blob, spec["output"])
                held = np.repeat(values[:1], len(values), axis=0)
                spec["output"] = append(header, blob, held, "VEC3")
                moved = float(np.linalg.norm(values - values[0], axis=1).max())
                print(f"  {name}: hips pinned, removing {moved:.3f} units of root motion "
                      f"over {times[-1]:.2f}s")

    for text in args.rename:
        old, _, new = text.partition("=")
        if old not in clips:
            raise SystemExit(f"--rename {old}: no such clip. Have: {', '.join(clips)}")
        clips[old]["name"] = new
        clips[new] = clips.pop(old)

    if args.keep:
        wanted = [w.strip() for w in args.keep.split(",")]
        missing = [w for w in wanted if w not in clips]
        if missing:
            raise SystemExit(f"--keep names clips that do not exist: {', '.join(missing)}")
        dropped = [n for n in clips if n not in wanted]
        header["animations"] = [clips[w] for w in wanted]
        if dropped:
            print(f"  dropped: {', '.join(sorted(dropped))}")

    header["buffers"][0]["byteLength"] = len(blob)

    encoded = json.dumps(header, separators=(",", ":")).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    blob.extend(b"\x00" * (-len(blob) % 4))
    out = Path(args.out) if args.out else source
    out.write_bytes(
        struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(encoded) + 8 + len(blob))
        + struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
        + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    order = ", ".join(a["name"] for a in header["animations"])
    print(f"\n{len(header['animations'])} clips -> {out}\n  {order}")


if __name__ == "__main__":
    main()
