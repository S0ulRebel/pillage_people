"""Independent checks of exported canonical OBJ meshes and assembly contracts.

Usage: python tools/validate_kit.py [canonical_folder]
Does not import or execute the mesh generator. Indices are deliberately NOT welded:
separate closed timber panels may touch and remain separate solids.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from collections import defaultdict
from pathlib import Path

TOL = 0.001
AREA_TOL = 1e-12
VOLUME_TOL = 1e-10


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def match_points(a, b, tolerance=TOL):
    """Bidirectional distance comparison allows harmless repeated seam vertices."""
    if not a or not b:
        return False, None
    error = max(max(min(math.dist(p, q) for q in b) for p in a),
                max(min(math.dist(p, q) for q in a) for p in b))
    return error <= tolerance, error


def read_obj(path):
    vertices, faces = [], []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        words = line.split()
        if not words or words[0].startswith("#"):
            continue
        if words[0] == "v":
            if len(words) < 4:
                raise ValueError(f"Line {line_number}: incomplete vertex")
            vertex = tuple(map(float, words[1:4]))
            if not all(math.isfinite(x) for x in vertex):
                raise ValueError(f"Line {line_number}: non-finite vertex")
            vertices.append(vertex)
        elif words[0] == "f":
            raw = [int(s.split("/")[0]) for s in words[1:]]
            indices = [i - 1 if i > 0 else len(vertices) + i for i in raw]
            if len(indices) != 3 or any(i < 0 or i >= len(vertices) for i in indices):
                raise ValueError(f"Line {line_number}: requires valid indexed triangles")
            faces.append(tuple(indices))
    if not vertices or not faces:
        raise ValueError("Empty mesh")
    return vertices, faces


class Checks:
    def __init__(self):
        self.records = []

    def check(self, condition, label, **details):
        self.records.append(dict(check=label, passed=bool(condition), **details))
        return bool(condition)


def check_solids(vertices, faces, checks, label):
    edge_faces = defaultdict(list)
    adjacency = defaultdict(set)
    degenerate = []
    for fi, face in enumerate(faces):
        a, b, c = [vertices[i] for i in face]
        normal = cross(sub(b, a), sub(c, a))
        if dot(normal, normal) <= AREA_TOL * AREA_TOL:
            degenerate.append(fi)
        for i, j in zip(face, face[1:] + face[:1]):
            edge_faces[tuple(sorted((i, j)))].append((fi, i, j))
    bad_counts, bad_directions = [], []
    for edge, incidents in edge_faces.items():
        if len(incidents) != 2:
            bad_counts.append(edge)
        if len(incidents) == 2:
            p, q = incidents
            adjacency[p[0]].add(q[0])
            adjacency[q[0]].add(p[0])
            if (p[1], p[2]) != (q[2], q[1]):
                bad_directions.append(edge)
    checks.check(not degenerate, label + ": nondegenerate triangles", count=len(degenerate))
    checks.check(not bad_counts, label + ": two faces per indexed edge", count=len(bad_counts))
    checks.check(not bad_directions, label + ": opposite shared-edge directions", count=len(bad_directions))
    components, unvisited = [], set(range(len(faces)))
    while unvisited:
        first = unvisited.pop()
        component, pending = [first], [first]
        while pending:
            fi = pending.pop()
            for neighbor in adjacency[fi] & unvisited:
                unvisited.remove(neighbor)
                component.append(neighbor)
                pending.append(neighbor)
        components.append(component)
    volumes = []
    for component in components:
        # Shift origin into each component to avoid cancellation on placed ships.
        origin = vertices[faces[component[0]][0]]
        volume = sum(dot(sub(vertices[faces[fi][0]], origin),
                         cross(sub(vertices[faces[fi][1]], origin),
                               sub(vertices[faces[fi][2]], origin))) / 6.0
                     for fi in component)
        volumes.append(volume)
    checks.check(all(v > VOLUME_TOL for v in volumes), label + ": outward closed solid volumes",
                 components=len(components), minimum_volume_m3=min(volumes, default=0))
    return components


def inside_component(point, vertices, faces, component):
    """Odd ray crossing test; oblique ray avoids common axis-aligned degeneracy."""
    direction = (1.0, 0.173205, 0.071067)
    hits = []
    for fi in component:
        a, b, c = [vertices[i] for i in faces[fi]]
        e1, e2 = sub(b, a), sub(c, a)
        p = cross(direction, e2)
        determinant = dot(e1, p)
        if abs(determinant) < 1e-12:
            continue
        inverse = 1.0 / determinant
        tvec = sub(point, a)
        u = dot(tvec, p) * inverse
        if not -1e-9 <= u <= 1.0 + 1e-9:
            continue
        q = cross(tvec, e1)
        v = dot(direction, q) * inverse
        if v < -1e-9 or u + v > 1.0 + 1e-9:
            continue
        t = dot(e2, q) * inverse
        if t > 1e-9 and all(abs(t - hit) > 1e-7 for hit in hits):
            hits.append(t)
    return len(hits) % 2 == 1


def floor_part(part):
    return (str(part.get("tier", "")).lower() in {"floor", "deck"}
            or str(part.get("role", "")).lower() in {"floor", "deck", "floor insert"}
            or part["id"].startswith(("FLOOR_", "DECK_", "F_")))


def point_in_triangle_xz(point, triangle):
    p = (point[0], point[1])
    q = [(v[0], v[2]) for v in triangle]
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    area = orient(q[0], q[1], q[2])
    if abs(area) < 1e-12:
        return False
    s = [orient(q[i], q[(i + 1) % 3], p) for i in range(3)]
    return all(x >= -1e-8 for x in s) or all(x <= 1e-8 for x in s)


def validate(root):
    checks = Checks()
    contract_path = root / "contract.json"
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    parts = {part["id"]: part for part in contract["parts"]}
    checks.check(len(parts) == len(contract["parts"]), "Unique part IDs")
    meshes, digests = {}, {}
    for part_id, part in parts.items():
        path = root / part["mesh"]
        try:
            vertices, faces = read_obj(path)
        except (OSError, ValueError) as exc:
            checks.check(False, part_id + ": readable triangle OBJ", error=str(exc))
            continue
        meshes[part_id] = (vertices, faces)
        digests[part_id] = hashlib.sha256(path.read_bytes()).hexdigest()
        components = check_solids(vertices, faces, checks, part_id)
        for socket in part.get("sockets", []):
            points = socket.get("points", [])
            error = max((min(math.dist(p, v) for v in vertices) for p in points), default=float("inf"))
            checks.check(bool(points) and error <= TOL, part_id + ": socket " + socket["name"] + " is exported geometry",
                         max_error_m=error if math.isfinite(error) else None)
            normal = socket.get("normal", [])
            checks.check(len(normal) == 3 and abs(dot(normal, normal) - 1) <= 1e-5,
                         part_id + ": socket " + socket["name"] + " unit normal")
            if len(normal) == 3 and points:
                error = max(abs(dot(sub(p, socket["position"]), normal)) for p in points)
                checks.check(error <= TOL, part_id + ": socket " + socket["name"] + " coplanar", max_error_m=error)
        is_floor = floor_part(part)
        if is_floor:
            ys = [p[1] for p in vertices]
            checks.check(abs(min(ys) + .18) <= TOL and abs(max(ys)) <= TOL,
                         part_id + ": flat 0.18 m floor without posts", bounds_y=[min(ys), max(ys)])
        for key in ["floor_outline_xz", "inner_outline_xz", "outer_outline_xz"]:
            outline = part.get(key)
            if outline:
                xz = [(p[0], p[2]) for p in vertices]
                error = max(min(math.dist(p, q) for q in xz) for p in outline)
                checks.check(error <= TOL, part_id + ": declared " + key + " is exported geometry", max_error_m=error)
        if str(part.get("section", "")).lower() == "bow":
            ok, error = match_points(vertices, [(-x, y, z) for x, y, z in vertices])
            checks.check(ok, part_id + ": bow vertex mirror symmetry", max_error_m=error)
            outline = part.get("outer_outline_xz", part.get("floor_outline_xz"))
            if outline:
                nose_z = min(p[1] for p in outline)
                checks.check(any(abs(x) <= TOL and abs(z - nose_z) <= TOL for x, z in outline),
                             part_id + ": symmetric centreline prow")
            # Explicit supplied test points also work for curved lower bilges.
            closure_points = part.get("nose_solid_test_points", [])
            if closure_points:
                checks.check(all(any(inside_component(p, vertices, faces, comp) for comp in components)
                                 for p in closure_points), part_id + ": closed solid across bow nose",
                             test_points=closure_points)
    total_joins, total_fits, stair_tests = 0, 0, 0
    for assembly in contract.get("assemblies", []):
        label = assembly["id"]
        placements = assembly["placements"]
        valid = all(p["part"] in meshes for p in placements)
        checks.check(valid, label + ": all parts supplied locally")
        if not valid:
            continue
        for ji, join in enumerate(assembly.get("joins", [])):
            a, b = placements[join["a"]], placements[join["b"]]
            sa = next((s for s in parts[a["part"]].get("sockets", []) if s["name"] == join["socket_a"]), None)
            sb = next((s for s in parts[b["part"]].get("sockets", []) if s["name"] == join["socket_b"]), None)
            jl = f"{label}: join {ji}"
            if not checks.check(sa is not None and sb is not None, jl + " named sockets exist"):
                continue
            total_joins += 1
            checks.check(sa["interface"] == sb["interface"], jl + " interface IDs")
            error = math.dist(add(sa["position"], a["position"]), add(sb["position"], b["position"]))
            checks.check(error <= TOL, jl + " coincident origins", error_m=error)
            checks.check(dot(sa["normal"], sb["normal"]) <= -.999, jl + " opposing normals")
            ap = [add(p, a["position"]) for p in sa.get("points", [])]
            bp = [add(p, b["position"]) for p in sb.get("points", [])]
            ok, error = match_points(ap, bp)
            checks.check(ok, jl + " complete boundary match", max_error_m=error)
        for fit in assembly.get("floorfits", []):
            floor, shell = placements[fit["floor"]], placements[fit["shell"]]
            fp, sp = parts[floor["part"]], parts[shell["part"]]
            fo, so = fp.get("floor_outline_xz", []), sp.get("inner_outline_xz", [])
            world = lambda outline, p: [(v[0] + p["position"][0], v[1] + p["position"][2]) for v in outline]
            ok, error = match_points(world(fo, floor), world(so, shell))
            checks.check(ok, label + ": floor fits " + floor["part"] + " into " + shell["part"], max_error_m=error)
            total_fits += 1
        for stair in assembly.get("stair_checks", []):
            instance = placements[stair["stair"]]
            vertices, _ = meshes[instance["part"]]
            world_vertices = [add(v, instance["position"]) for v in vertices]
            top = max(v[1] for v in world_vertices)
            checks.check(abs(top - stair["upper_y"]) <= TOL, label + ": stair reaches upper floor", top_y=top)
            checks.check(abs(instance["position"][1] - stair["lower_y"]) <= TOL,
                         label + ": stair begins at lower floor")
            opening = stair["opening"]
            x0, x1 = opening["x"]
            z0, z1 = opening["z"]
            checks.check(min(v[0] for v in world_vertices) >= x0 - TOL and max(v[0] for v in world_vertices) <= x1 + TOL,
                         label + ": stair width fits shaft")
            checks.check(abs(max(v[2] for v in world_vertices) - z1) <= TOL,
                         label + ": stair meets shaft exit")
            blocked = []
            for pi in stair.get("floor_indices", []):
                floor = placements[pi]
                fv, ff = meshes[floor["part"]]
                fv = [add(v, floor["position"]) for v in fv]
                for face in ff:
                    triangle = [fv[i] for i in face]
                    if max(abs(v[1] - stair["upper_y"]) for v in triangle) > TOL:
                        continue
                    for ix in range(1, 10):
                        for iz in range(1, 20):
                            sample = (x0 + (x1 - x0) * ix / 10, z0 + (z1 - z0) * iz / 20)
                            if point_in_triangle_xz(sample, triangle):
                                blocked.append(sample)
            checks.check(not blocked, label + ": stair shaft has no upper floor covering", blocked_samples=len(blocked))
            stair_tests += 1
        if assembly.get("mesh"):
            try:
                av, af = read_obj(root / assembly["mesh"])
                expected_v, expected_f = [], []
                for placement in placements:
                    v, f = meshes[placement["part"]]
                    offset = len(expected_v)
                    expected_v.extend(add(p, placement["position"]) for p in v)
                    expected_f.extend(tuple(i + offset for i in face) for face in f)
                matches = len(av) == len(expected_v) and len(af) == len(expected_f)
                if matches:
                    matches = all(math.dist(a, b) <= TOL for a, b in zip(av, expected_v)) and af == expected_f
                checks.check(matches, label + ": exported assembly equals declared placements")
            except (OSError, ValueError) as exc:
                checks.check(False, label + ": readable assembly OBJ", error=str(exc))
    failed = [r for r in checks.records if not r["passed"]]
    result = dict(passed=not failed, tolerance_m=TOL, parts=len(meshes), assemblies=len(contract.get("assemblies", [])),
                  joins_tested=total_joins, floorfits_tested=total_fits, stair_connections_tested=stair_tests,
                  checks=len(checks.records), failure_count=len(failed), failures=failed, results=checks.records,
                  mesh_sha256=digests, contract_sha256=hashlib.sha256(contract_path.read_bytes()).hexdigest(),
                  limitations=["Construction geometry validation; no styled model, game collision or buoyancy test.",
                               "Stair opening checks sample exported floor triangles; no humanoid traversal simulation.",
                               "Separate indexed solids are checked without welding touching timber panels."])
    (root / "validation.json").write_text(json.dumps(result, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ["passed", "parts", "assemblies", "joins_tested", "floorfits_tested", "stair_connections_tested", "checks", "failure_count"]}))
    for failure in failed:
        print(json.dumps(failure))
    return not failed


if __name__ == "__main__":
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "canonical"
    sys.exit(0 if validate(folder) else 1)
