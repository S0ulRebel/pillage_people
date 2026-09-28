"""Cut a Tripo "whole reference sheet" model into separate, upright, real-size parts.

    python tools/extract_tripo_sheet.py tripo/fittings.json

Tripo's image-to-3D, given a sheet of parts, returns ONE mesh: every part fused into a single
object, one material, one 4096 atlas shared by all of them, each part turned the way the sheet
drew it, and the whole sheet squeezed into a 1-unit cube. This undoes that, per the config:

  1. SEGMENT. Triangles are grouped by connectivity plus a proximity gap, because bolts, bands
     and wheels are separate shells that sit a hair off the body they belong to. Each output
     names its pieces by their centre in sheet coordinates; a centre that matches nothing
     closely is an error, and so is a piece left unclaimed, so a changed source cannot quietly
     drop or double a part.
  2. STRAIGHTEN. 'flat' levels the part on its own base (the area-weighted normal of its
     downward faces becomes -Y), then squares it up with the minimum-area rectangle of its
     footprint. 'pca' maps principal axes to world axes, for round or thin parts with no base.
     'turns' then picks which side faces which way, in quarter turns about Y. Rotations only:
     a mirror would flip the texture and the winding.
  3. SCALE to one stated real dimension, uniformly.
  4. ORIGIN where the part attaches (deck contact, hinge axis, trunnion axis...), per axis.
  5. RETEXTURE. Only the UV islands the part uses are copied out of the atlas into a new,
     tightly packed one at the SAME pixel density - nothing is resampled. Then every pixel
     outside the part's own triangles is filled outward from the island edges. That filling is
     what removes the blue-grey gutter Tripo leaves around islands, which otherwise bleeds in as
     seams once mipmaps average it in.

Axes follow the kit and Godot: X starboard, Y up, -Z forward. Writes one .glb per output plus
<config stem>-report.json beside the config.
"""
import argparse
import json
import sys
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import ConvexHull, cKDTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glb_io  # noqa: E402

AXES = {'x': 0, 'y': 1, 'z': 2}
MATCH_TOLERANCE = 0.01      # sheet units; parts sit ~0.03 apart
ISLAND_PAD = 4              # px of source copied around each island
BLEED = 8                   # px the edge colour is pushed into the gutter


def load(path):
    gltf, binary = glb_io.read(path)
    if len(gltf['meshes']) != 1 or len(gltf['meshes'][0]['primitives']) != 1:
        raise SystemExit(f'{path}: expected one mesh with one primitive, as Tripo writes them')
    primitive = gltf['meshes'][0]['primitives'][0]
    a = primitive['attributes']
    positions = np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['POSITION']), '<f4').reshape(-1, 3).astype(np.float64)
    normals = np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['NORMAL']), '<f4').reshape(-1, 3).astype(np.float64)
    uvs = np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['TEXCOORD_0']), '<f4').reshape(-1, 2).astype(np.float64)
    kind = {5125: '<u4', 5123: '<u2', 5121: 'u1'}[gltf['accessors'][primitive['indices']]['componentType']]
    indices = np.frombuffer(glb_io.accessor_bytes(gltf, binary, primitive['indices']), kind).reshape(-1, 3).astype(np.int64)
    # Tripo leaves the scene transform on the nodes; the sheet is authored in mesh space, and
    # every node here is identity - refuse anything else rather than silently ignore it.
    for node in gltf['nodes']:
        if any(k in node for k in ('matrix', 'rotation', 'scale')) or any(node.get('translation', [0, 0, 0])):
            raise SystemExit(f'{path}: node {node.get("name")} has a transform; this tool assumes none')
    image = gltf['images'][gltf['textures'][gltf['materials'][primitive.get('material', 0)]
                                            ['pbrMetallicRoughness']['baseColorTexture']['index']]['source']]
    atlas = Image.open(BytesIO(glb_io.view_bytes(gltf, binary, image['bufferView']))).convert('RGB')
    return positions, normals, uvs, indices, atlas


def segment(positions, indices, gap):
    """Cluster label per triangle: shared vertices OR vertices within `gap` of each other."""
    n = len(positions)
    edges = [indices[:, [0, 1]], indices[:, [1, 2]]]
    close = cKDTree(positions).query_pairs(gap, output_type='ndarray')
    if len(close):
        edges.append(close)
    edges = np.concatenate(edges)
    graph = coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(n, n))
    _, vertex_label = connected_components(graph, directed=False)
    labels = vertex_label[indices[:, 0]]
    centres = {}
    for label in np.unique(labels):
        points = positions[indices[labels == label].reshape(-1)]
        centres[int(label)] = (points.min(axis=0) + points.max(axis=0)) / 2
    return labels, centres


def claim(centres, wanted, where):
    label, distance = min(((k, float(np.linalg.norm(c - wanted))) for k, c in centres.items()), key=lambda t: t[1])
    if distance > MATCH_TOLERANCE:
        raise SystemExit(f'{where}: nothing within {MATCH_TOLERANCE} of {list(wanted)} (nearest {distance:.4f})')
    return label


def rotation_between(a, b):
    """Smallest rotation taking unit vector a to unit vector b."""
    a, b = a / np.linalg.norm(a), b / np.linalg.norm(b)
    v, c = np.cross(a, b), float(a @ b)
    if np.linalg.norm(v) < 1e-12:
        if c > 0:
            return np.eye(3)
        axis = np.cross(a, [1, 0, 0] if abs(a[0]) < 0.9 else [0, 1, 0])
        axis /= np.linalg.norm(axis)
        return 2 * np.outer(axis, axis) - np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * (1 / (1 + c))


def yaw(degrees):
    return axis_rotation('y', degrees)


def axis_rotation(axis, degrees):
    """Right-handed rotation about a world axis ('x', 'y' or 'z')."""
    u = np.eye(3)[AXES[axis]]
    t = np.radians(degrees)
    k = np.array([[0, -u[2], u[1]], [u[2], 0, -u[0]], [-u[1], u[0], 0]])
    return np.eye(3) + np.sin(t) * k + (1 - np.cos(t)) * k @ k


def square_up(points):
    """Yaw (degrees) that aligns the minimum-area footprint rectangle with X and Z."""
    footprint = points[:, [0, 2]]
    hull = footprint[ConvexHull(footprint).vertices]
    best = None
    for i in range(len(hull)):
        d = hull[(i + 1) % len(hull)] - hull[i]
        angle = np.arctan2(d[1], d[0])
        c, s = np.cos(-angle), np.sin(-angle)
        r = hull @ np.array([[c, s], [-s, c]])
        area = np.ptp(r[:, 0]) * np.ptp(r[:, 1])
        if best is None or area < best[0]:
            best = (area, angle)
    # A right-handed turn by t about Y takes (x, z) at angle theta to theta - t, so t = theta
    # lands that edge on X.
    return np.degrees(best[1])


def straighten(spec, tris, key_points):
    method = spec.get('method', 'flat')
    if method == 'flat':
        n = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        area = np.linalg.norm(n, axis=1)
        unit = n / np.maximum(area, 1e-15)[:, None]
        down = unit[:, 1] < -0.8
        if area[down].sum() <= 0:
            raise SystemExit('flat alignment needs downward faces; use pca for this part')
        base = (unit[down] * area[down, None]).sum(axis=0)
        r = rotation_between(base, np.array([0.0, -1.0, 0.0]))
        r = yaw(square_up(key_points @ r.T)) @ r
    elif method == 'pca':
        centred = key_points - key_points.mean(axis=0)
        _, vectors = np.linalg.eigh(centred.T @ centred)   # ascending variance
        major, minor = vectors[:, 2], vectors[:, 0]
        target = np.zeros((3, 3))
        target[AXES[spec['major']]] = major
        target[AXES[spec['minor']]] = minor
        rest = 3 - AXES[spec['major']] - AXES[spec['minor']]
        target[rest] = np.cross(target[(rest + 1) % 3], target[(rest + 2) % 3])
        r = target                                          # rows: where each world axis comes from
    else:
        raise SystemExit(f'unknown alignment method {method}')
    r = yaw(90 * spec.get('turns', 0)) @ r
    for axis, degrees in spec.get('then', []):
        r = axis_rotation(axis, degrees) @ r
    if 'refine' in spec:
        # Snap one face direction exactly onto an axis: the faces already within `within`
        # degrees of it, area-weighted. Used where a straight edge must be truly vertical.
        sign = -1.0 if spec['refine']['toward'].startswith('-') else 1.0
        target = np.eye(3)[AXES[spec['refine']['toward'][-1]]] * sign
        t = tris @ r.T
        n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
        area = np.linalg.norm(n, axis=1)
        unit = n / np.maximum(area, 1e-15)[:, None]
        near = unit @ target > np.cos(np.radians(spec['refine'].get('within', 25)))
        if area[near].sum() <= 0:
            raise SystemExit(f"refine: no faces within {spec['refine'].get('within', 25)} degrees of {spec['refine']['toward']}")
        mean = (unit[near] * area[near, None]).sum(axis=0)
        if 'about' in spec['refine']:
            # Turn only about this axis, so the snap cannot tip the part out of its plane.
            about = np.eye(3)[AXES[spec['refine']['about']]]
            mean = mean - (mean @ about) * about
        r = rotation_between(mean, target) @ r
    if abs(np.linalg.det(r) - 1) > 1e-6:
        raise SystemExit('alignment produced a reflection')
    return r


def origin_of(spec, low, high, marks):
    point = np.zeros(3)
    for axis, i in AXES.items():
        rule = spec.get(axis, 'mid')
        offset = 0.0
        if isinstance(rule, list):
            rule, offset = rule
        if rule.startswith('mark:'):
            value = marks[rule[5:]][i]
        else:
            value = {'min': low[i], 'mid': (low[i] + high[i]) / 2, 'max': high[i]}[rule]
        point[i] = value + offset
    return point


def repack(pieces, atlas):
    """New atlas from only the islands these pieces use; returns (image, remapped uv per piece)."""
    width, height = atlas.size
    source = np.asarray(atlas)
    rects, owners = [], []
    for p_index, (uv, tri) in enumerate(pieces):
        # Tripo splits vertices at every seam, so index connectivity IS the UV island.
        n = len(uv)
        edges = np.concatenate([tri[:, [0, 1]], tri[:, [1, 2]]])
        _, island = connected_components(coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])),
                                                    shape=(n, n)), directed=False)
        for label in np.unique(island[tri[:, 0]]):
            used = np.unique(tri[island[tri[:, 0]] == label])
            px = uv[used] * [width, height]
            x0, y0 = np.maximum(np.floor(px.min(axis=0)).astype(int) - ISLAND_PAD, 0)
            x1, y1 = np.minimum(np.ceil(px.max(axis=0)).astype(int) + ISLAND_PAD, [width, height])
            rects.append([x0, y0, x1, y1])
            owners.append((p_index, used))
    # Shelf packing, tallest first, into the smallest power-of-two square that holds them.
    order = sorted(range(len(rects)), key=lambda i: -(rects[i][3] - rects[i][1]))
    total = sum((r[2] - r[0]) * (r[3] - r[1]) for r in rects)
    size = 256
    while size * size < total:
        size *= 2
    while True:
        placed, x, y, shelf = {}, 0, 0, 0
        for i in order:
            w, h = rects[i][2] - rects[i][0], rects[i][3] - rects[i][1]
            if x + w > size:
                x, y, shelf = 0, y + shelf, 0
            if y + h > size or w > size:
                break
            placed[i] = (x, y)
            x, shelf = x + w, max(shelf, h)
        if len(placed) == len(rects):
            break
        size *= 2
    out = np.zeros((size, size, 3), dtype=np.uint8)
    new_uvs = [uv.copy() for uv, _ in pieces]
    for i, (dx, dy) in placed.items():
        x0, y0, x1, y1 = rects[i]
        out[dy:dy + y1 - y0, dx:dx + x1 - x0] = source[y0:y1, x0:x1]
        p_index, used = owners[i]
        px = pieces[p_index][0][used] * [width, height]
        new_uvs[p_index][used] = (px - [x0, y0] + [dx, dy]) / size
    # Fill everything outside the real triangles from the island edges inward-out.
    mask_image = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask_image)
    for (uv, tri), new_uv in zip(pieces, new_uvs):
        for t in tri:
            draw.polygon([tuple(p) for p in new_uv[t] * size], fill=255)
    mask = np.asarray(mask_image) > 0
    colour = out.astype(np.float32)
    known = mask.copy()
    for _ in range(BLEED):
        total_c = np.zeros_like(colour)
        count = np.zeros(mask.shape, dtype=np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            shifted = np.roll(known, (dy, dx), axis=(0, 1))
            total_c += np.roll(colour, (dy, dx), axis=(0, 1)) * shifted[..., None]
            count += shifted
        grow = ~known & (count > 0)
        colour[grow] = total_c[grow] / count[grow, None]
        known |= grow
    # Beyond the bleed band nothing samples; a flat mean keeps the JPEG small and seam-free.
    colour[~known] = colour[mask].mean(axis=0) if mask.any() else 0
    return Image.fromarray(np.uint8(np.clip(np.round(colour), 0, 255))), new_uvs, size


def write_glb(path, nodes, image):
    writer, gltf = glb_io.Writer(), {
        'asset': {'version': '2.0', 'generator': 'ship-kit tools/extract_tripo_sheet.py'}, 'scene': 0,
        'scenes': [{'nodes': list(range(len(nodes)))}], 'nodes': [], 'meshes': [],
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
        'textures': [{'sampler': 0, 'source': 0}], 'images': [], 'materials': []}
    buffer = BytesIO()
    image.save(buffer, 'JPEG', quality=90, subsampling=0, optimize=True)
    gltf['images'].append({'bufferView': writer.view(buffer.getvalue()), 'mimeType': 'image/jpeg'})
    gltf['materials'].append({'name': path.stem, 'pbrMetallicRoughness': {
        'baseColorTexture': {'index': 0}, 'metallicFactor': 0, 'roughnessFactor': 0.85}})
    for name, positions, normals, uvs, tri in nodes:
        index_kind, fmt = (5123, '<u2') if len(positions) < 65536 else (5125, '<u4')
        indices_view = writer.view(tri.astype(fmt).tobytes(), 34963)
        writer.accessors.append({'bufferView': indices_view, 'componentType': index_kind,
                                 'count': int(tri.size), 'type': 'SCALAR'})
        indices = len(writer.accessors) - 1
        gltf['meshes'].append({'name': name, 'primitives': [{
            'attributes': {'POSITION': writer.floats(positions.astype('<f4').tobytes(), 'VEC3', bounds=True),
                           'NORMAL': writer.floats(normals.astype('<f4').tobytes(), 'VEC3'),
                           'TEXCOORD_0': writer.floats(uvs.astype('<f4').tobytes(), 'VEC2')},
            'indices': indices, 'material': 0, 'mode': 4}]})
        gltf['nodes'].append({'name': name, 'mesh': len(gltf['meshes']) - 1})
    path.write_bytes(writer.glb(gltf))


def contact_sheet(out_dir, report, path):
    """Every part from the bow (-Z), from starboard (+X) and three-quarter, with its size."""
    import render_textured as R
    views = [('front (from -Z)', [0, 0.3, -1]), ('starboard (from +X)', [1, 0.3, 0]),
             ('three-quarter', [0.9, 0.75, -1])]
    cell, label_h = (250, 210), 34
    sheet = Image.new('RGB', (cell[0] * len(views) + 230, (cell[1] + label_h) * len(report)), (226, 229, 232))
    draw = ImageDraw.Draw(sheet)
    for row, part in enumerate(report):
        gltf, binary = glb_io.read(out_dir / part['file'])
        with Image.open(BytesIO(glb_io.view_bytes(gltf, binary, gltf['images'][0]['bufferView']))) as im:
            texture = np.asarray(im.convert('RGB'), dtype=np.float32)
        tris, uv = [], []
        for mesh in gltf['meshes']:
            a = mesh['primitives'][0]['attributes']
            kind = {5123: '<u2', 5125: '<u4'}[gltf['accessors'][mesh['primitives'][0]['indices']]['componentType']]
            index = np.frombuffer(glb_io.accessor_bytes(gltf, binary, mesh['primitives'][0]['indices']), kind).reshape(-1, 3)
            tris.append(np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['POSITION']), '<f4').reshape(-1, 3)[index])
            uv.append(np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['TEXCOORD_0']), '<f4').reshape(-1, 2)[index])
        tris = np.concatenate(tris).astype(np.float64)
        normal = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
        normal /= np.maximum(np.linalg.norm(normal, axis=1, keepdims=True), 1e-12)
        mesh = {'tris': tris, 'normals': normal, 'uvs': np.concatenate(uv).astype(np.float64),
                'tex': np.zeros(len(tris), int), 'textures': [texture]}
        y = row * (cell[1] + label_h)
        for col, (title, eye) in enumerate(views):
            view = R.camera(eye)
            image = R.render(mesh, cell, R.fit_scale([mesh], cell, 0.06, view), view)
            sheet.paste(image, (col * cell[0], y + label_h), image)
            draw.text((col * cell[0] + 6, y + label_h + 4), title, fill=(90, 100, 110))
        draw.text((6, y + 6), f"{part['id']}  {part['name']}  -  {part['file']}", fill=(20, 30, 40))
        x = cell[0] * len(views) + 10
        size = part['size_m']
        draw.text((x, y + label_h + 10), f"X {size[0]:.2f} m\nY {size[1]:.2f} m\nZ {size[2]:.2f} m\n\n"
                  f"{part['triangles']} tris\n{part['texture_px']} px texture\n{part['texel_density_px_per_m']:.0f} px/m",
                  fill=(20, 30, 40), spacing=4)
        draw.line((0, y, sheet.width, y), fill=(190, 195, 200))
    sheet.save(path, optimize=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('config')
    config_path = Path(parser.parse_args().config).resolve()
    config = json.loads(config_path.read_text(encoding='utf-8'))
    base = config_path.parent
    positions, normals, uvs, indices, atlas = load(base / config['source'])
    labels, centres = segment(positions, indices, config['gap'])
    # A piece that sits inside another part's gap can be claimed at a finer gap instead; it
    # is then taken out of whatever coarse cluster it fell into.
    fine_labels, fine_centres = segment(positions, indices, config.get('fine_gap', 0.002))
    detached, fine_claimed = np.zeros(len(indices), bool), {}
    for output in config['outputs']:
        for node in output['nodes']:
            for c in node.get('fine_pieces', []):
                label = claim(fine_centres, np.array(c), f"{output['file']}/{node['name']}")
                if label in fine_claimed:
                    raise SystemExit(f"fine piece {c} claimed twice")
                fine_claimed[label] = output['file']
                detached |= fine_labels == label
    out_dir = (base / config['out_dir']).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    claimed, report, scales = {}, [], {}

    for output in config['outputs']:
        where = output['file']
        node_tris, node_labels = [], []
        for node in output['nodes']:
            mine = [claim(centres, np.array(c), f"{where}/{node['name']}") for c in node.get('pieces', [])]
            for label in mine:
                if label in claimed:
                    raise SystemExit(f"{where}: piece {list(centres[label].round(4))} already claimed by {claimed[label]}")
                claimed[label] = where
            fine = [claim(fine_centres, np.array(c), where) for c in node.get('fine_pieces', [])]
            node_labels.append(mine)
            node_tris.append((np.isin(labels, mine) & ~detached) | np.isin(fine_labels, fine))
        key = node_tris[0]
        key_tris = positions[indices[key]]
        r = straighten(output['align'], key_tris, key_tris.reshape(-1, 3))
        everything = np.any(node_tris, axis=0)
        rotated = positions[np.unique(indices[everything])] @ r.T
        raw_marks = {name: centres[claim(centres, np.array(c), where)] @ r.T
                     for name, c in output.get('marks', {}).items()}
        size = output['size']
        if 'same_scale_as' in size:
            scale = scales[size['same_scale_as']]
        elif 'between_marks' in size:
            a, b = size['between_marks']
            scale = size['metres'] / float(np.linalg.norm(raw_marks[a] - raw_marks[b]))
        elif size['axis'] == 'xz':
            scale = size['metres'] / max(np.ptp(rotated[:, 0]), np.ptp(rotated[:, 2]))
        else:
            scale = size['metres'] / np.ptp(rotated[:, AXES[size['axis']]])
        scales[output['file']] = scale
        marks = {name: m * scale for name, m in raw_marks.items()}

        pieces, geometry = [], []
        for node, mask in zip(output['nodes'], node_tris):
            tri = indices[mask]
            used, local = np.unique(tri, return_inverse=True)
            local = local.reshape(-1, 3)
            p = positions[used] @ r.T * scale
            n = normals[used] @ r.T
            if 'rotate' in node:
                # A piece Tripo modelled at the wrong angle, turned about its own centre.
                turn = axis_rotation(*node['rotate'])
                centre = (p.min(axis=0) + p.max(axis=0)) / 2
                p = (p - centre) @ turn.T + centre
                n = n @ turn.T
            n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            pieces.append((uvs[used], local))
            geometry.append([node['name'], p, n, None, local])
        every = np.concatenate([g[1] for g in geometry])
        origin = origin_of(output['origin'], every.min(axis=0), every.max(axis=0), marks)
        for g in geometry:
            g[1] = g[1] - origin
        image, new_uvs, tex_size = repack(pieces, atlas)
        for g, uv in zip(geometry, new_uvs):
            g[3] = uv
        write_glb(out_dir / output['file'], geometry, image)

        all_p = np.concatenate([g[1] for g in geometry])
        tris = sum(len(g[4]) for g in geometry)
        surface = uv_area = 0.0
        for _, gp, _, guv, gt in geometry:
            t3, t2 = gp[gt], guv[gt] * tex_size
            surface += 0.5 * np.linalg.norm(np.cross(t3[:, 1] - t3[:, 0], t3[:, 2] - t3[:, 0]), axis=1).sum()
            e1, e2 = t2[:, 1] - t2[:, 0], t2[:, 2] - t2[:, 0]
            uv_area += 0.5 * np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]).sum()
        uv_all = np.concatenate([g[3] for g in geometry])
        report.append({
            'file': Path(output['file']).name, 'id': output.get('id'), 'name': output.get('name'),
            'nodes': [g[0] for g in geometry], 'triangles': int(tris),
            'bounds_min_m': all_p.min(axis=0).round(4).tolist(), 'bounds_max_m': all_p.max(axis=0).round(4).tolist(),
            'size_m': np.ptp(all_p, axis=0).round(4).tolist(), 'scale_from_sheet': round(float(scale), 4),
            'origin': output['origin'], 'texture_px': tex_size,
            'texel_density_px_per_m': round(float(np.sqrt(uv_area / max(surface, 1e-12))), 1),
            'uv_in_unit_square': bool((uv_all >= 0).all() and (uv_all <= 1).all()),
            'notes': output.get('notes', ''),
        })

    problems = []
    unclaimed = [list(centres[k].round(4)) for k in centres
                 if k not in claimed and ((labels == k) & ~detached).any()]
    if unclaimed:
        problems.append(f'unclaimed pieces: {unclaimed}')
    if sum(r['triangles'] for r in report) != len(indices):
        problems.append('triangle count does not add up to the source')
    for r in report:
        if not r['uv_in_unit_square']:
            problems.append(f"{r['file']}: UVs outside the unit square")
    summary = {'source': config['source'], 'source_triangles': int(len(indices)), 'parts': report,
               'passed': not problems, 'problems': problems}
    (base / f'{config_path.stem}-report.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    contact_sheet(out_dir, report, base / f'{config_path.stem}-parts.png')
    for r in report:
        print(f"{r['file']:28s} {r['triangles']:5d} tris  size {r['size_m']}  tex {r['texture_px']}  {r['texel_density_px_per_m']} px/m")
    if problems:
        print('PROBLEMS:', *problems, sep='\n  ')
        raise SystemExit(1)


if __name__ == '__main__':
    main()
