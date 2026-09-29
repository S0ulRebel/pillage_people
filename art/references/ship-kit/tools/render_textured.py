#!/usr/bin/env python3
"""Render the textured construction kit as the art breakdown's hull sheets.

    python tools/render_textured.py

Writes art-breakdown/01-hull-modules.png and art-breakdown/01b-hull-assembly.png from the
files in textured/ - the GLBs that ship, not the OBJs they came from - so the sheet shows
exactly what a modeller imports. Requires Pillow and NumPy.

WHY A RENDER AND NOT A PAINTING. The painted 01 sheet drew H02 with a rocker and a wall across
its join, and H03 as a canoe; the contract says H02 is a straight prism open at both ends. A
generator will keep making that kind of mistake. A render cannot: every cell is the actual
mesh, one camera, one scale, so relative sizes read true across the sheet as well.
"""
from pathlib import Path
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import glb_io

ROOT = Path(__file__).resolve().parent.parent
TEXTURED = ROOT / 'textured'
OUT = ROOT / 'art-breakdown'
PAPER = (226, 229, 232)
INK = (22, 34, 44)
MUTED = (96, 108, 116)
RULE = (200, 205, 210)
SS = 2  # supersampling

# Display names; the H/D numbers come from the manifest so the two cannot drift.
NAMES = {
    'BOTTOM_BOW': 'LOWER BOW', 'BOTTOM_CENTRE': 'LOWER CENTRE', 'BOTTOM_STERN': 'LOWER STERN',
    'MIDDLE_BOW': 'MIDDLE BOW', 'MIDDLE_CENTRE_GUN': 'GUN BAY', 'MIDDLE_STERN': 'MIDDLE STERN',
    'TOP_BOW': 'TOP BOW', 'TOP_CENTRE': 'TOP CENTRE', 'TOP_STERN': 'TOP STERN',
    'MIDDLE_CENTRE': 'SOLID BAY', 'FLOOR_BOW': 'BOW DECK', 'FLOOR_CENTRE': 'CENTRE DECK',
    'FLOOR_STERN': 'STERN DECK',
}
GRID = [('LOWER', 'TIER 01', ['BOTTOM_BOW', 'BOTTOM_CENTRE', 'BOTTOM_STERN']),
        ('MIDDLE', 'TIER 02', ['MIDDLE_BOW', 'MIDDLE_CENTRE_GUN', 'MIDDLE_STERN']),
        ('TOP', 'TIER 03', ['TOP_BOW', 'TOP_CENTRE', 'TOP_STERN']),
        ('FLOOR', 'EVERY DECK', ['FLOOR_BOW', 'FLOOR_CENTRE', 'FLOOR_STERN'])]


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / np.linalg.norm(v)


# X starboard, Y up, Z aft. Looking from starboard, ahead and above: bow at right, as in the
# corrected master, and high enough to see into the open shells.
EYE = unit([1.0, 1.05, -0.78])
RIGHT = unit(np.cross([0, 1, 0], EYE))
CAM_UP = unit(np.cross(EYE, RIGHT))
LIGHT = unit(-RIGHT * 0.55 + CAM_UP * 0.9 + EYE * 0.6)


def font(size, bold=False):
    candidates = [Path(os.environ.get('WINDIR', 'C:/Windows')) / 'Fonts' / ('segoeuib.ttf' if bold else 'segoeui.ttf'),
                  Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if bold
                       else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]
    for path in candidates:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)


def load(path):
    """Triangles of every scene node, translated, with UVs and a texture per triangle."""
    gltf, binary = glb_io.read(path)
    textures = []
    for image in gltf['images']:
        from io import BytesIO
        with Image.open(BytesIO(glb_io.view_bytes(gltf, binary, image['bufferView']))) as im:
            textures.append(np.asarray(im.convert('RGB'), dtype=np.float32))
    material_texture = [gltf['textures'][m['pbrMetallicRoughness']['baseColorTexture']['index']]['source']
                        for m in gltf['materials']]
    tris, normals, uvs, tex = [], [], [], []
    for node_index in gltf['scenes'][gltf.get('scene', 0)]['nodes']:
        node = gltf['nodes'][node_index]
        offset = np.array(node.get('translation', [0, 0, 0]), dtype=np.float64)
        for primitive in gltf['meshes'][node['mesh']]['primitives']:
            a = primitive['attributes']
            p = np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['POSITION']), '<f4').reshape(-1, 3, 3)
            n = np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['NORMAL']), '<f4').reshape(-1, 3, 3)
            t = np.frombuffer(glb_io.accessor_bytes(gltf, binary, a['TEXCOORD_0']), '<f4').reshape(-1, 3, 2)
            tris.append(p.astype(np.float64) + offset)
            normals.append(n[:, 0, :].astype(np.float64))
            uvs.append(t.astype(np.float64))
            tex.append(np.full(len(p), material_texture[primitive['material']]))
    return {'tris': np.concatenate(tris), 'normals': np.concatenate(normals),
            'uvs': np.concatenate(uvs), 'tex': np.concatenate(tex), 'textures': textures}


def camera(eye):
    """(eye, right, up, light) for an orthographic view from direction `eye`."""
    eye = unit(eye)
    right = unit(np.cross([0, 1, 0], eye)) if abs(eye[1]) < 0.99 else unit([1, 0, 0])
    up = unit(np.cross(eye, right))
    return eye, right, up, unit(-right * 0.55 + up * 0.9 + eye * 0.6)


def project(points, view=None):
    eye, right, up, _ = view or (EYE, RIGHT, CAM_UP, LIGHT)
    return np.stack([points @ right, -(points @ up), points @ eye], axis=-1)


def extent(mesh, view=None):
    xy = project(mesh['tris'].reshape(-1, 3), view)[:, :2]
    return xy.min(axis=0), xy.max(axis=0)


def render(mesh, size, scale, view=None):
    """Toon-shaded, textured, orthographic z-buffer render; transparent background."""
    eye, _, _, light = view or (EYE, RIGHT, CAM_UP, LIGHT)
    width, height = size[0] * SS, size[1] * SS
    low, high = extent(mesh, view)
    screen = project(mesh['tris'], view)
    screen[..., :2] = (screen[..., :2] - (low + high) / 2) * scale * SS + np.array([width, height]) / 2
    depth = np.full((height, width), -np.inf)
    color = np.zeros((height, width, 3), dtype=np.float32)
    normal_map = np.zeros((height, width, 3), dtype=np.float32)
    for index, points in enumerate(screen):
        lo = np.maximum(np.floor(points[:, :2].min(axis=0)).astype(int), 0)
        hi = np.minimum(np.ceil(points[:, :2].max(axis=0)).astype(int), [width - 1, height - 1])
        if np.any(hi < lo):
            continue
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = points
        det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(det) < 1e-9:
            continue
        xx = np.arange(lo[0], hi[0] + 1)[None, :] + 0.5
        yy = np.arange(lo[1], hi[1] + 1)[:, None] + 0.5
        a = ((by - cy) * (xx - cx) + (cx - bx) * (yy - cy)) / det
        b = ((cy - ay) * (xx - cx) + (ax - cx) * (yy - cy)) / det
        c = 1 - a - b
        inside = (a >= -1e-7) & (b >= -1e-7) & (c >= -1e-7)
        z = a * az + b * bz + c * cz
        region = np.s_[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1]
        visible = inside & (z > depth[region])
        if not visible.any():
            continue
        # Orthographic, so affine UV interpolation is exact.
        uv = mesh['uvs'][index]
        u = (a * uv[0, 0] + b * uv[1, 0] + c * uv[2, 0])[visible]
        v = (a * uv[0, 1] + b * uv[1, 1] + c * uv[2, 1])[visible]
        texture = mesh['textures'][mesh['tex'][index]]
        th, tw = texture.shape[:2]
        texel = texture[((v % 1.0) * th).astype(int) % th, ((u % 1.0) * tw).astype(int) % tw]
        normal = mesh['normals'][index].copy()
        if normal @ eye < 0:
            normal = -normal
        lit = float(normal @ light)
        band = 1.0 if lit > 0.55 else 0.86 if lit > 0.15 else 0.7   # three flat toon bands
        color[region][visible] = texel * band
        depth[region][visible] = z[visible]
        normal_map[region][visible] = normal

    mask = np.isfinite(depth)
    boundary, crease = np.zeros_like(mask), np.zeros_like(mask)
    depth_range = max(float(np.ptp(screen[..., 2])), 1e-6)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        neighbour = np.roll(mask, (dy, dx), axis=(0, 1))
        boundary |= mask & ~neighbour
        both = mask & neighbour
        turn = np.sum(normal_map * np.roll(normal_map, (dy, dx), axis=(0, 1)), axis=2) < 0.8
        step = np.zeros_like(mask)
        step[both] = np.abs(depth[both] - np.roll(depth, (dy, dx), axis=(0, 1))[both]) > depth_range * 0.02
        crease |= both & (turn | step)
    color[crease] *= 0.6
    color[boundary] = np.array([48, 28, 16])
    rgba = np.dstack((np.uint8(np.clip(color, 0, 255)), mask.astype(np.uint8) * 255))
    return Image.fromarray(rgba).resize(size, Image.Resampling.LANCZOS)


def fit_scale(meshes, cell, padding=0.03, view=None):
    scale = np.inf
    for mesh in meshes:
        low, high = extent(mesh, view)
        span = np.maximum(high - low, 1e-6)
        scale = min(scale, cell[0] * (1 - 2 * padding) / span[0], cell[1] * (1 - 2 * padding) / span[1])
    return scale


def manifest_ids():
    manifest = json.loads((OUT / 'kit-manifest.json').read_text(encoding='utf-8'))
    ids = {}
    for family in manifest['families']:
        for part in family['parts']:
            canonical = part.get('canonical_ids', [])
            if len(canonical) == 1:
                ids[canonical[0]] = part['id']
    missing = [p for p in NAMES if p not in ids]
    if missing:
        raise SystemExit(f'kit-manifest.json has no single-part id for {missing}')
    return ids


def label(draw, x, y, part_id, ids):
    draw.text((x, y), f'{ids[part_id]}  {NAMES[part_id]}', font=font(15, True), fill=INK)
    draw.text((x, y + 19), part_id, font=font(11), fill=MUTED)


def hull_sheet(ids):
    width, height = 1536, 1024
    sheet = Image.new('RGB', (width, height), PAPER)
    draw = ImageDraw.Draw(sheet)
    draw.text((28, 16), '01 — HULL MODULES', font=font(32, True), fill=INK)
    draw.text((30, 58), 'Rendered from the canonical meshes with the plank texture. Geometry unchanged, '
              'one camera, one scale for every cell.', font=font(13), fill=MUTED)
    left, top, col_w, row_h = 118, 112, 318, 212
    meshes = {p: load(TEXTURED / 'meshes' / f'{p}.glb') for p in NAMES}
    cell = (col_w - 12, row_h - 46)
    scale = fit_scale(meshes.values(), cell)
    for c, heading in enumerate(['BOW', 'CENTRE', 'STERN']):
        draw.text((left + c * col_w + col_w / 2, top - 22), heading, font=font(19, True), fill=INK, anchor='mm')
    draw.line((left - 100, top - 6, left + 3 * col_w, top - 6), fill=RULE, width=1)
    for r, (tier, sub, parts) in enumerate(GRID):
        y = top + r * row_h
        draw.text((24, y + row_h / 2 - 16), tier, font=font(19, True), fill=INK)
        draw.text((25, y + row_h / 2 + 8), sub, font=font(11), fill=MUTED)
        draw.line((left - 100, y + row_h, left + 3 * col_w, y + row_h), fill=RULE, width=1)
        for c, part in enumerate(parts):
            x = left + c * col_w
            sheet.paste(im := render(meshes[part], cell, scale), (x + 6, y + 2), im)
            label(draw, x + 14, y + row_h - 44, part, ids)
    for c in range(4):
        draw.line((left + c * col_w, top - 36, left + c * col_w, top + 4 * row_h), fill=RULE, width=1)

    # Right-hand column: the optional solid bay beside the gun bay, then notes.
    rx, rw = left + 3 * col_w + 24, width - (left + 3 * col_w + 24) - 24
    draw.text((rx + rw / 2, top - 22), 'VARIANT', font=font(19, True), fill=INK, anchor='mm')
    y = top + row_h
    sheet.paste(im := render(meshes['MIDDLE_CENTRE'], cell, scale), (rx + (rw - cell[0]) // 2, y + 4), im)
    label(draw, rx + 6, y + row_h - 44, 'MIDDLE_CENTRE', ids)
    draw.text((rx + 6, top + 18), 'Replaces the gun bay with the same\nsockets. Use either in any centre\ncolumn.',
              font=font(12), fill=MUTED, spacing=4)
    notes = ('Each shell is open at every join and\nclosed only at the prow and the stern.\n\n'
             'Planks: ten courses per 2.6 m tier,\nbutts on a 2 m repeat, so courses run\n'
             'straight across every join and stack.\n\n'
             'Albedo only - no baked light. Iron,\nwales (H12), lids (H11), rails and\n'
             'bevels are separate, not modelled.\n\n'
             'Measure from canonical/contract.json,\nnever from this picture.')
    draw.text((rx + 6, top + 2 * row_h + 18), notes, font=font(12), fill=MUTED, spacing=4)
    draw.text((width - 24, height - 20), 'Shared joins • Separate floors • Repeat centre bays • '
              'Source: textured/meshes/*.glb', font=font(12), fill=MUTED, anchor='rs')
    return sheet


def assembly_sheet(ids):
    width, height = 1536, 1024
    sheet = Image.new('RGB', (width, height), PAPER)
    draw = ImageDraw.Draw(sheet)
    draw.text((28, 16), '01b — HULL ASSEMBLY', font=font(32, True), fill=INK)
    draw.text((30, 58), 'textured/assemblies/DOUBLE_DECK.glb: bow, four gun bays, stern; bilge, one gun deck, '
              'bulwark; floors and a port stair opening. Placed by translation only.', font=font(13), fill=MUTED)
    mesh = load(TEXTURED / 'assemblies' / 'DOUBLE_DECK.glb')
    cell = (width - 80, height - 150)
    sheet.paste(im := render(mesh, cell, fit_scale([mesh], cell, 0.04)), (40, 90), im)
    draw.text((width - 24, height - 20), 'Construction geometry only: no rails, cabin, masts or fittings yet',
              font=font(12), fill=MUTED, anchor='rs')
    return sheet


def main():
    ids = manifest_ids()
    OUT.mkdir(exist_ok=True)
    hull_sheet(ids).save(OUT / '01-hull-modules.png', optimize=True)
    assembly_sheet(ids).save(OUT / '01b-hull-assembly.png', optimize=True)
    print(OUT / '01-hull-modules.png')
    print(OUT / '01b-hull-assembly.png')


if __name__ == '__main__':
    main()
