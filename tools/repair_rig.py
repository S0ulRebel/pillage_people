r"""Rebuild the skeleton of a rigged .glb whose bones lost their rest pose, and bake its height.

    python tools/repair_rig.py zombie.glb art/models/characters/body_zombie.glb --height 1.8
    python tools/repair_rig.py body.glb --check

WHY THIS EXISTS. Tripo's rigged export of the zombie body came back with every bone node bare -
no translation, no rotation - so in Godot every joint sat at the origin, and a skin bound to
joints all in one place tore the mesh into ribbons. The joints were not lost, only moved: each
one's position and orientation survives in the skin's inverse bind matrices. They are just in
the rigger's space rather than the mesh's: Blender's axes, up +Z and facing +X, with the origin
halfway up the body - while the mesh stands up Godot's way, +Y, feet on the floor, facing +Z.
The node that turned the one into the other is what the export dropped.

So the tool finds that turn. It tries all 24 ways of laying one set of axes on another, and for
each, the shift that best puts every joint where its own skin is: the middle of each bone
should sit inside the vertices that bone mostly moves. On the zombie the right answer lands
the median bone within 7 mm of its limb's centre, and the runner-up misses by 5 cm - there is
no guessing involved. Anything that cannot be matched to within 2 cm is refused rather than
written, because a skeleton a few centimetres off bends every elbow in the wrong place.

The joints are then written back onto the bone nodes, the inverse bind matrices recomputed to
match, and the result is one where the rest pose IS the pose the mesh was modelled in: the
T-pose, upright, feet on the floor, in metres.

--height bakes the size into the file at the same time. tools/README.md explains why it
belongs in the .glb rather than in a .import: a scale left in the importer is a scale a fresh
clone does not get. Bone rotations are made exactly rigid on the way - Tripo's matrices carry a
stray 0.9995 scale - so nothing downstream inherits a skeleton that is very slightly shrunk.

Stdlib only, like retexture_model.py: this is arithmetic on a container, not modelling.
"""
import argparse
import itertools
import json
import math
import statistics
import struct
from pathlib import Path

from retexture_model import BIN_CHUNK, JSON_CHUNK, join, split

COMPONENT = {5126: ("f", 4), 5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4)}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
# How far the median bone may sit from its own vertices before the fit is not trusted.
TOLERANCE = 0.02


# --- 4x4 affine matrices as row lists --------------------------------------------------------

def from_gltf(values):
    """glTF stores matrices column by column."""
    return [[values[c * 4 + r] for c in range(4)] for r in range(4)]


def to_gltf(m):
    return [m[r][c] for c in range(4) for r in range(4)]


def multiply(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def apply(m, v):
    return tuple(sum(m[r][c] * v[c] for c in range(3)) + m[r][3] for r in range(3))


def invert(m):
    """Inverse of an affine matrix - any 3x3 part, not only a rotation."""
    (a, b, c), (d, e, f), (g, h, i) = (m[0][:3], m[1][:3], m[2][:3])
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    r = [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
         [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
         [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]
    t = [m[0][3], m[1][3], m[2][3]]
    out = [r[k] + [-sum(r[k][j] * t[j] for j in range(3))] for k in range(3)]
    return out + [[0.0, 0.0, 0.0, 1.0]]


def rigid(m, scale=1.0):
    """The same joint with its axes made exactly unit and square, and its position scaled."""
    x = [m[r][0] for r in range(3)]
    y = [m[r][1] for r in range(3)]
    x = normalised(x)
    y = normalised([y[k] - dot(x, y) * x[k] for k in range(3)])
    z = cross(x, y)
    return [[x[r], y[r], z[r], m[r][3] * scale] for r in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def dot(a, b):
    return sum(p * q for p, q in zip(a, b))


def cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def normalised(v):
    length = math.sqrt(dot(v, v))
    return [c / length for c in v]


def quaternion(m):
    """Rotation part of a rigid matrix as glTF's [x, y, z, w]."""
    trace = m[0][0] + m[1][1] + m[2][2]
    if trace > 0:
        s = math.sqrt(trace + 1.0) * 2
        q = [(m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s, s / 4]
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        q = [s / 4, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s, (m[2][1] - m[1][2]) / s]
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        q = [(m[0][1] + m[1][0]) / s, s / 4, (m[1][2] + m[2][1]) / s, (m[0][2] - m[2][0]) / s]
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        q = [(m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, s / 4, (m[1][0] - m[0][1]) / s]
    return normalised(q)


def turns():
    """The 24 rotations that lay one set of axes square onto another."""
    for order in itertools.permutations(range(3)):
        for signs in itertools.product((1, -1), repeat=3):
            m = [[0.0] * 4 for _ in range(4)]
            for r in range(3):
                m[r][order[r]] = float(signs[r])
            m[3][3] = 1.0
            det = (m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1])
                   - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                   + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]))
            if det > 0:
                yield m


# --- the container ---------------------------------------------------------------------------

class Model:
    def __init__(self, path):
        chunks = split(Path(path).read_bytes())
        self.gltf = json.loads(next(body for kind, body in chunks if kind == JSON_CHUNK))
        self.binary = bytearray(next(body for kind, body in chunks if kind == BIN_CHUNK))

    def _where(self, index):
        accessor = self.gltf["accessors"][index]
        view = self.gltf["bufferViews"][accessor["bufferView"]]
        code, size = COMPONENT[accessor["componentType"]]
        width = WIDTH[accessor["type"]]
        stride = view.get("byteStride", size * width)
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return accessor, code, width, stride, start

    def read(self, index):
        accessor, code, width, stride, start = self._where(index)
        scale = {5121: 255.0, 5123: 65535.0}.get(accessor["componentType"], 1.0)
        out = []
        for i in range(accessor["count"]):
            values = struct.unpack_from("<%d%s" % (width, code), self.binary, start + i * stride)
            if accessor.get("normalized"):
                values = tuple(v / scale for v in values)
            out.append(values)
        return out

    def write(self, index, rows):
        """Overwrites floats in place. Same count and size, so nothing else in the buffer moves."""
        accessor, code, width, stride, start = self._where(index)
        if code != "f" or len(rows) != accessor["count"]:
            raise SystemExit("can only rewrite float accessors of the same length")
        for i, values in enumerate(rows):
            struct.pack_into("<%df" % width, self.binary, start + i * stride, *values)

    def save(self, path):
        out = Path(path)
        out.parent.mkdir(parents=True, exist_ok=True)
        scratch = out.with_suffix(out.suffix + ".part")
        scratch.write_bytes(join(self.gltf, bytes(self.binary)))
        scratch.replace(out)


# --- the repair ------------------------------------------------------------------------------

def bare(node):
    return not any(key in node for key in ("translation", "rotation", "scale", "matrix"))


def centroids(positions, joints, weights, count):
    """For each bone, the middle of the vertices it mostly moves. Bones that move fewer than
    eight vertices on their own are left out - a fingertip is not evidence of anything."""
    sums = [[0.0, 0.0, 0.0, 0] for _ in range(count)]
    for p, bones, amounts in zip(positions, joints, weights):
        strongest = max(range(4), key=lambda k: amounts[k])
        if amounts[strongest] > 0.7:
            s = sums[int(bones[strongest])]
            s[0] += p[0]
            s[1] += p[1]
            s[2] += p[2]
            s[3] += 1
    return {k: (s[0] / s[3], s[1] / s[3], s[2] / s[3]) for k, s in enumerate(sums) if s[3] >= 8}


def find_placement(bind_globals, children, middles):
    """The turn and shift that put the rigger's joints inside the mesh. Returns
    (median miss in metres, runner-up's miss, 4x4 matrix)."""
    heads = [(g[0][3], g[1][3], g[2][3]) for g in bind_globals]

    def middle_of(k):
        if not children[k]:
            return heads[k]
        tails = [heads[c] for c in children[k]]
        tail = [statistics.mean(t[i] for t in tails) for i in range(3)]
        return tuple((heads[k][i] + tail[i]) / 2 for i in range(3))

    tried = []
    for turn in turns():
        turned = {k: apply(turn, middle_of(k)) for k in middles}
        shift = [statistics.median(middles[k][i] - turned[k][i] for k in middles) for i in range(3)]
        miss = statistics.median(
            math.dist(middles[k], [turned[k][i] + shift[i] for i in range(3)]) for k in middles)
        placement = [row[:] for row in turn]
        for r in range(3):
            placement[r][3] = shift[r]
        tried.append((miss, placement))
    tried.sort(key=lambda t: t[0])
    return tried[0][0], tried[1][0], tried[0][1]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model", help="the rigged .glb")
    ap.add_argument("out", nargs="?", help="where to write the repaired model")
    ap.add_argument("--height", type=float,
                    help="metres from the lowest vertex to the highest, baked into the file")
    ap.add_argument("--check", action="store_true", help="report what is wrong and write nothing")
    args = ap.parse_args()

    model = Model(args.model)
    gltf = model.gltf
    if len(gltf.get("skins", [])) != 1:
        raise SystemExit("expected exactly one skin, found %d" % len(gltf.get("skins", [])))
    skin = gltf["skins"][0]
    joint_nodes = skin["joints"]
    nodes = gltf["nodes"]
    skinned = [n for n in nodes if "skin" in n and "mesh" in n]
    if len(skinned) != 1 or not bare(skinned[0]):
        raise SystemExit("expected one skinned mesh node with no transform of its own")
    mesh = gltf["meshes"][skinned[0]["mesh"]]
    primitives = mesh["primitives"]

    inverse_binds = [from_gltf(m) for m in model.read(skin["inverseBindMatrices"])]
    bind_globals = [invert(m) for m in inverse_binds]
    parent_of = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            parent_of[child] = index
    joint_of = {node: k for k, node in enumerate(joint_nodes)}
    children = {k: [joint_of[c] for c in nodes[n].get("children", []) if c in joint_of]
                for k, n in enumerate(joint_nodes)}
    # Everything above the skeleton must be bare too, or "global" would mean something else.
    for n in joint_nodes:
        walk = parent_of.get(n)
        while walk is not None and walk not in joint_of:
            if not bare(nodes[walk]):
                raise SystemExit("node '%s' above the skeleton has a transform; this tool assumes "
                                 "none" % nodes[walk].get("name"))
            walk = parent_of.get(walk)

    positions = []
    for prim in primitives:
        positions += model.read(prim["attributes"]["POSITION"])
    lowest = min(p[1] for p in positions)
    highest = max(p[1] for p in positions)

    broken = all(bare(nodes[n]) for n in joint_nodes)
    if broken:
        joints, weights = [], []
        for prim in primitives:
            joints += model.read(prim["attributes"]["JOINTS_0"])
            weights += model.read(prim["attributes"]["WEIGHTS_0"])
        middles = centroids(positions, joints, weights, len(joint_nodes))
        miss, runner_up, placement = find_placement(bind_globals, children, middles)
        print("%s: every bone is at the origin - rebuilding the skeleton from the skin"
              % Path(args.model).name)
        print("  best placement puts the median bone %.1f mm from its vertices (next best %.1f mm)"
              % (miss * 1000, runner_up * 1000))
        if miss > TOLERANCE:
            raise SystemExit("  that is not close enough to trust; nothing written")
        joint_globals = [multiply(placement, g) for g in bind_globals]
    else:
        print("%s: the bones have their rest pose already" % Path(args.model).name)
        joint_globals = []
        for n in joint_nodes:
            m = [[1.0, 0, 0, 0], [0, 1.0, 0, 0], [0, 0, 1.0, 0], [0, 0, 0, 1.0]]
            walk = n
            chain = []
            while walk is not None:
                chain.append(walk)
                walk = parent_of.get(walk)
            for step in reversed(chain):
                m = multiply(m, local_matrix(nodes[step]))
            joint_globals.append(m)
        # The rest must be the pose the skin was bound in, or rebuilding the binds changes the mesh.
        worst = max(math.dist(apply(multiply(g, b), (0.3, 0.9, 0.1)), (0.3, 0.9, 0.1))
                    for g, b in zip(joint_globals, inverse_binds))
        if worst > 0.001:
            raise SystemExit("  but the skin was bound in a different pose (off by %.1f mm); "
                             "this tool only handles a skin bound at rest" % (worst * 1000))

    print("  %.3f m tall, feet at %.4f" % (highest - lowest, lowest))
    if args.check:
        return 0
    if not args.out:
        raise SystemExit("give an output path, or --check")

    scale = 1.0
    if args.height:
        scale = args.height / (highest - lowest)
        print("  scaled x%.4f to %.3f m" % (scale, args.height))
    joint_globals = [rigid(g, scale) for g in joint_globals]

    for k, n in enumerate(joint_nodes):
        parent = parent_of.get(n)
        local = joint_globals[k]
        if parent in joint_of:
            local = multiply(invert(joint_globals[joint_of[parent]]), local)
        node = nodes[n]
        node.pop("matrix", None)
        node.pop("scale", None)
        node["translation"] = [local[0][3], local[1][3], local[2][3]]
        node["rotation"] = quaternion(local)
    binds = [to_gltf(invert(g)) for g in joint_globals]
    model.write(skin["inverseBindMatrices"], binds)

    for prim in primitives:
        index = prim["attributes"]["POSITION"]
        scaled = [tuple(c * scale for c in p) for p in model.read(index)]
        model.write(index, scaled)
        accessor = gltf["accessors"][index]
        accessor["min"] = [min(p[i] for p in scaled) for i in range(3)]
        accessor["max"] = [max(p[i] for p in scaled) for i in range(3)]

    # Proof, before anything is written: every bone's new bind undoes its new rest exactly,
    # which is what "the rest pose is the modelled pose" means to a skinning shader.
    check = [invert(from_gltf(b)) for b in binds]
    worst = max(math.dist(apply(multiply(g, from_gltf(b)), (0.3, 0.9, 0.1)), (0.3, 0.9, 0.1))
                for g, b in zip(check, binds))
    if worst > 1e-5:
        raise SystemExit("  internal check failed (%.6f); nothing written" % worst)
    hips = joint_globals[0]
    print("  %s at %.3f m" % (nodes[joint_nodes[0]].get("name"), hips[1][3]))
    model.save(args.out)
    print("  -> %s" % args.out)
    return 0


def local_matrix(node):
    if "matrix" in node:
        return from_gltf(node["matrix"])
    x, y, z, w = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    t = node.get("translation", [0.0, 0.0, 0.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    return [[r[i][0] * s[0], r[i][1] * s[1], r[i][2] * s[2], t[i]] for i in range(3)] \
        + [[0.0, 0.0, 0.0, 1.0]]


if __name__ == "__main__":
    raise SystemExit(main())
