#!/usr/bin/env python3
"""Render canonical ship construction meshes with an orthographic z-buffer.

Requires only Pillow and NumPy. Geometry comes exclusively from the OBJ files
referenced by contract.json. No source mesh is changed by this renderer.

    python tools/render_kit.py --contract canonical/contract.json --out previews

Default coordinates: X starboard, Y up, Z aft (negative Z faces the bow).
Use --up-axis / --forward-axis to override the camera convention.
"""

from __future__ import annotations

import argparse
import html
import json
import math
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
PAPER = (238, 239, 234)
CARD = (248, 247, 240)
INK = (29, 45, 47)
MUTED = (100, 113, 111)
LINE = (210, 215, 205)
ACCENT = (164, 98, 44)
MATERIALS = {
    "wood": (163, 105, 59),
    "iron": (64, 75, 77),
    "deck": (198, 154, 95),
    "default": (163, 105, 59),
}


@dataclass
class Mesh:
    vertices: np.ndarray
    triangles: np.ndarray
    normals: np.ndarray
    colors: np.ndarray
    path: Path
    polygon_count: int


def normalized(vector: np.ndarray) -> np.ndarray:
    length = float(np.linalg.norm(vector))
    if length < 1e-12:
        raise ValueError("Cannot normalize a zero-length vector")
    return vector / length


def axis_vector(name: str) -> np.ndarray:
    sign = -1 if name.startswith("-") else 1
    letter = name.lstrip("+-").lower()
    result = np.zeros(3)
    result["xyz".index(letter)] = sign
    return result


def polygon_normal(points: np.ndarray) -> np.ndarray:
    # Newell's method is stable for quads with collinear leading vertices.
    following = np.roll(points, -1, axis=0)
    return np.sum(np.cross(points, following), axis=0)


def triangulate(indices: list[int], vertices: np.ndarray) -> list[list[int]]:
    """Ear clip planar concave faces; preserve the source polygon boundary."""
    if len(indices) == 3:
        return [indices]
    points = vertices[indices]
    normal = polygon_normal(points)
    if np.linalg.norm(normal) < 1e-12:
        return []
    drop = int(np.argmax(np.abs(normal)))
    flat = np.delete(points, drop, axis=1)
    area = np.sum(flat[:, 0] * np.roll(flat[:, 1], -1) -
                  np.roll(flat[:, 0], -1) * flat[:, 1])
    winding = 1 if area >= 0 else -1
    eps = max(float(np.ptp(flat, axis=0).max()) ** 2 * 1e-11, 1e-14)

    def cross2(a: np.ndarray, b: np.ndarray) -> float:
        return float(a[0] * b[1] - a[1] * b[0])

    remaining = list(range(len(indices)))
    result = []
    while len(remaining) > 3:
        found = False
        for offset, current in enumerate(remaining):
            previous = remaining[offset - 1]
            following = remaining[(offset + 1) % len(remaining)]
            a, b, c = flat[[previous, current, following]]
            if cross2(b - a, c - b) * winding <= eps:
                continue
            occupied = False
            for candidate in remaining:
                if candidate in (previous, current, following):
                    continue
                point = flat[candidate]
                signs = [cross2(b-a, point-a), cross2(c-b, point-b),
                         cross2(a-c, point-c)]
                if min(value * winding for value in signs) >= -eps:
                    occupied = True
                    break
            if not occupied:
                result.append([indices[previous], indices[current], indices[following]])
                remaining.pop(offset)
                found = True
                break
        if not found:
            # Remove a collinear corner before considering a fan fallback.
            for offset, current in enumerate(remaining):
                a = flat[remaining[offset - 1]]
                b = flat[current]
                c = flat[remaining[(offset + 1) % len(remaining)]]
                if abs(cross2(b-a, c-b)) <= eps:
                    remaining.pop(offset)
                    found = True
                    break
            if not found:
                raise ValueError("Non-simple or non-planar OBJ polygon cannot be triangulated")
    if len(remaining) == 3:
        result.append([indices[index] for index in remaining])
    return result


def material_color(name: str) -> tuple[int, int, int]:
    name = name.lower()
    if name in MATERIALS:
        return MATERIALS[name]
    for key in ("iron", "deck", "wood"):
        if key in name:
            return MATERIALS[key]
    return MATERIALS["default"]


def load_obj(path: Path) -> Mesh:
    vertices: list[list[float]] = []
    faces: list[tuple[list[int], str]] = []
    material = "wood"
    for number, line in enumerate(path.read_text(encoding="utf-8-sig").splitlines(), 1):
        fields = line.partition("#")[0].split()
        if not fields:
            continue
        if fields[0] == "v":
            vertices.append([float(value) for value in fields[1:4]])
        elif fields[0] == "usemtl":
            material = " ".join(fields[1:])
        elif fields[0] == "f":
            indices = []
            for item in fields[1:]:
                raw = int(item.split("/")[0])
                index = raw - 1 if raw > 0 else len(vertices) + raw
                if not 0 <= index < len(vertices):
                    raise ValueError(f"{path}:{number}: vertex index {raw} is invalid")
                if not indices or indices[-1] != index:
                    indices.append(index)
            if len(indices) > 1 and indices[0] == indices[-1]:
                indices.pop()
            if len(indices) >= 3:
                faces.append((indices, material))
    coords = np.asarray(vertices, dtype=np.float64)
    if not len(coords) or not faces:
        raise ValueError(f"{path}: no renderable faces")
    triangles, normals, colors = [], [], []
    for indices, material in faces:
        face_normal = polygon_normal(coords[indices])
        if np.linalg.norm(face_normal) < 1e-12:
            continue
        face_normal = normalized(face_normal)
        for triangle in triangulate(indices, coords):
            positions = coords[triangle]
            if np.linalg.norm(np.cross(positions[1]-positions[0], positions[2]-positions[0])) < 1e-12:
                continue
            triangles.append(triangle)
            normals.append(face_normal)
            colors.append(material_color(material))
    if not triangles:
        raise ValueError(f"{path}: all faces are degenerate")
    return Mesh(coords, np.asarray(triangles, dtype=np.int32),
                np.asarray(normals), np.asarray(colors, dtype=np.float32), path, len(faces))


def camera_direction(view: str, forward: np.ndarray, up: np.ndarray) -> np.ndarray:
    across = normalized(np.cross(up, forward))
    if view == "bow":
        return normalized(forward + up * 0.80)
    if view == "stern":
        return normalized(-forward + up * 0.80)
    if view == "floor":
        return up.copy()
    if view == "side":
        return normalized(forward * 0.48 - across + up * 0.57)
    if view == "exploded":
        return normalized(forward * 0.65 - across + up * 0.72)
    return normalized(forward * 0.72 - across + up * 0.72)


def render_mesh(mesh: Mesh, size: tuple[int, int], view: str,
                forward: np.ndarray, up: np.ndarray, supersample: float = 1.5,
                padding: float = 0.065) -> Image.Image:
    """Rasterize faces with barycentric interpolation into a real depth buffer."""
    width, height = [int(value * supersample) for value in size]
    eye = camera_direction(view, forward, up)
    right = normalized(np.cross(forward, up) if view == "floor" else np.cross(up, eye))
    camera_up = normalized(np.cross(eye, right))
    projected = np.column_stack((mesh.vertices @ right,
                                 -(mesh.vertices @ camera_up), mesh.vertices @ eye))
    low, high = projected[:, :2].min(axis=0), projected[:, :2].max(axis=0)
    span = np.maximum(high-low, 1e-8)
    scale = min(width * (1-2*padding)/span[0], height * (1-2*padding)/span[1])
    projected[:, :2] = (projected[:, :2]-(low+high)/2) * scale + np.array([width, height])/2
    depth = np.full((height, width), -np.inf, dtype=np.float32)
    color = np.zeros((height, width, 3), dtype=np.float32)
    normal_map = np.zeros((height, width, 3), dtype=np.float32)
    light = normalized(-right * 0.55 + up * 0.90 + eye * 0.55)
    fill = normalized(right * 0.80 + up * 0.3 + eye * 0.40)

    for index, triangle in enumerate(mesh.triangles):
        points = projected[triangle]
        lo = np.maximum(np.floor(points[:, :2].min(axis=0)).astype(int), 0)
        hi = np.minimum(np.ceil(points[:, :2].max(axis=0)).astype(int), [width-1, height-1])
        if np.any(hi < lo):
            continue
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = points
        determinant = (by-cy)*(ax-cx) + (cx-bx)*(ay-cy)
        if abs(determinant) < 1e-8:
            continue
        xx = np.arange(lo[0], hi[0]+1, dtype=np.float64)[None, :] + 0.5
        yy = np.arange(lo[1], hi[1]+1, dtype=np.float64)[:, None] + 0.5
        a = ((by-cy)*(xx-cx) + (cx-bx)*(yy-cy))/determinant
        b = ((cy-ay)*(xx-cx) + (ax-cx)*(yy-cy))/determinant
        c = 1-a-b
        inside = (a >= -1e-7) & (b >= -1e-7) & (c >= -1e-7)
        distance = a*az + b*bz + c*cz
        region = np.s_[lo[1]:hi[1]+1, lo[0]:hi[0]+1]
        visible = inside & (distance > depth[region])
        if not visible.any():
            continue
        normal = mesh.normals[index].copy()
        if np.dot(normal, eye) < 0:
            normal *= -1  # Display the actual back face of an open construction surface.
        intensity = (0.42 + 0.49 * max(0., float(np.dot(normal, light)))
                     + 0.12 * max(0., float(np.dot(normal, fill))))
        shaded = np.clip(mesh.colors[index]*intensity, 0, 255)
        color[region][visible] = shaded
        depth[region][visible] = distance[visible]
        normal_map[region][visible] = normal

    mask = np.isfinite(depth)
    # A thin silhouette/crease treatment clarifies actual occlusion and folds.
    boundary = np.zeros_like(mask)
    crease = np.zeros_like(mask)
    depth_range = max(float(np.ptp(mesh.vertices @ eye)), 1e-6)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        neighbor = np.roll(mask, (dy, dx), axis=(0, 1))
        boundary |= mask & ~neighbor
        peer_depth = np.roll(depth, (dy, dx), axis=(0, 1))
        peer_normal = np.roll(normal_map, (dy, dx), axis=(0, 1))
        both = mask & neighbor
        normal_change = np.sum(normal_map * peer_normal, axis=2) < 0.70
        step = np.zeros_like(mask)
        step[both] = np.abs(depth[both]-peer_depth[both]) > depth_range*0.022
        crease |= both & (normal_change | step)
    color[crease] *= 0.82
    color[boundary] *= 0.64
    rgba = np.dstack((np.uint8(np.clip(color, 0, 255)), mask.astype(np.uint8)*255))
    return Image.fromarray(rgba).resize(size, Image.Resampling.LANCZOS)


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    paths = [Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts" /
             ("segoeuib.ttf" if bold else "segoeui.ttf"),
             Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold
                  else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
    for path in paths:
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default(size=size)


def fit_text(draw: ImageDraw.ImageDraw, text: str, max_width: int,
             size: int, bold: bool = False) -> ImageFont.ImageFont:
    result = font(size, bold)
    while draw.textbbox((0, 0), text, font=result)[2] > max_width and size > 11:
        size -= 1
        result = font(size, bold)
    return result


def display_name(entry: dict) -> str:
    return str(entry.get("label") or entry.get("name") or entry["id"]).replace("_", " ")


def safe_id(value: str) -> str:
    return re.sub(r"[^a-zA-Z0-9_.-]+", "-", value).strip("-")


def tier_name(entry: dict) -> str:
    return str(entry.get("tier", "")).lower()


def section_name(entry: dict) -> str:
    section = str(entry.get("section", "")).lower()
    return section.replace("center", "centre").replace("-", "_").replace(" ", "_")


def is_floor(entry: dict) -> bool:
    fields = " ".join(str(entry.get(key, "")) for key in
                      ("id", "tier", "section", "kind", "category", "type")).lower()
    return "floor" in fields


def choose_view(entry: dict, assembly: bool = False) -> str:
    explicit = entry.get("preview_view")
    if explicit in ("bow", "stern", "floor", "side", "exploded", "three-quarter"):
        return explicit
    if assembly:
        return "exploded" if "explod" in str(entry["id"]).lower() else "side"
    if is_floor(entry):
        return "floor"
    section = section_name(entry)
    return "bow" if "bow" in section else "stern" if "stern" in section else "three-quarter"


VIEW_LABELS = {
    "bow": "Centred bow view · elevated orthographic",
    "stern": "Centred aft view · elevated orthographic",
    "floor": "Deck plan shape · top-down orthographic",
    "side": "Side / three-quarter · orthographic",
    "three-quarter": "Three-quarter · elevated orthographic",
    "exploded": "Exploded arrangement · orthographic",
}


def image_header(image: Image.Image, kicker: str, title: str, subtitle: str) -> None:
    draw = ImageDraw.Draw(image)
    draw.rectangle((54, 41, 92, 46), fill=ACCENT)
    draw.text((107, 28), kicker.upper(), font=font(20, True), fill=MUTED)
    draw.text((52, 67), title, font=font(47, True), fill=INK)
    draw.text((54, 132), subtitle, font=font(20), fill=MUTED)


def image_footer(image: Image.Image, text: str) -> None:
    draw = ImageDraw.Draw(image)
    y = image.height - 51
    draw.line((54, y-12, image.width-54, y-12), fill=LINE, width=1)
    draw.text((54, y), text, font=font(16), fill=MUTED)
    wordmark = "CANONICAL KIT / CONSTRUCTION MESHES"
    box = draw.textbbox((0, 0), wordmark, font=font(15, True))
    draw.text((image.width-54-box[2], y), wordmark, font=font(15, True), fill=MUTED)


def part_sheet(parts: list[dict], meshes: dict[str, Mesh], forward: np.ndarray,
               up: np.ndarray, supersample: float) -> Image.Image:
    width, height = 1920, 1590
    image = Image.new("RGB", (width, height), PAPER)
    image_header(image, "Modular ship · canonical geometry", "Hull construction meshes",
                 "Tier × section overview · each part fitted independently for inspection")
    draw = ImageDraw.Draw(image)
    left, top, gap, row_gap = 178, 235, 20, 25
    card_width, card_height = 550, 390
    for col, title in enumerate(("BOW", "CENTRE / CENTRE_GUN", "STERN")):
        x = left + col*(card_width+gap)
        draw.text((x+18, 191), title, font=font(23, True), fill=INK)
    for row, tier in enumerate(("bottom", "middle", "top")):
        y = top + row*(card_height+row_gap)
        draw.text((54, y+12), tier.upper(), font=font(21, True), fill=INK)
        draw.text((54, y+46), f"TIER {row+1:02d}", font=font(14), fill=MUTED)
        for col, section in enumerate(("bow", "centre", "stern")):
            x = left + col*(card_width+gap)
            draw.rounded_rectangle((x, y, x+card_width, y+card_height), radius=12,
                                   fill=CARD, outline=LINE, width=1)
            candidates = [part for part in parts if not is_floor(part)
                          and tier_name(part) == tier and section in section_name(part)]
            if section == "centre":
                candidates.sort(key=lambda item: ("gun" in section_name(item)) != (tier == "middle"))
            if not candidates:
                draw.text((x+22, y+22), "No mesh in contract", font=font(21), fill=MUTED)
                continue
            part = candidates[0]
            view = choose_view(part)
            rendering = render_mesh(meshes[part["id"]], (card_width-34, card_height-105),
                                    view, forward, up, supersample)
            image.paste(rendering, (x+17, y+55), rendering)
            title = display_name(part)
            draw.text((x+21, y+13), title, font=fit_text(draw, title, card_width-42, 23, True), fill=INK)
            detail = VIEW_LABELS[view].split(" · ")[0]
            draw.text((x+22, y+card_height-34), detail, font=font(16), fill=MUTED)
    image_footer(image, "Rendered from the supplied OBJ faces · warm timber / iron / deck materials")
    return image


def single_preview(entry: dict, mesh: Mesh, forward: np.ndarray, up: np.ndarray,
                   supersample: float, assembly: bool = False) -> Image.Image:
    view = choose_view(entry, assembly)
    image = Image.new("RGB", (1800, 1260), PAPER)
    image_header(image, "Canonical ship kit · construction meshes", display_name(entry),
                 VIEW_LABELS[view])
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((54, 192, 1746, 1152), radius=16, fill=CARD, outline=LINE, width=1)
    rendering = render_mesh(mesh, (1640, 910), view, forward, up, supersample, padding=0.04)
    image.paste(rendering, (80, 217), rendering)
    image_footer(image, f"{len(mesh.vertices):,} vertices  /  {mesh.polygon_count:,} source faces  /  OBJ geometry")
    return image


def floor_sheet(parts: list[dict], meshes: dict[str, Mesh], forward: np.ndarray,
                up: np.ndarray, supersample: float) -> Image.Image:
    columns = min(3, len(parts))
    rows = math.ceil(len(parts)/columns)
    card_width, card_height, gap = 566, 465, 22
    width = 54*2 + columns*card_width + (columns-1)*gap
    height = 222 + rows*card_height + (rows-1)*gap + 90
    image = Image.new("RGB", (width, height), PAPER)
    image_header(image, "Modular ship · canonical geometry", "Floor construction meshes",
                 "Independent deck shapes · top-down orthographic plan views")
    draw = ImageDraw.Draw(image)
    for index, part in enumerate(parts):
        x = 54 + (index % columns)*(card_width+gap)
        y = 218 + (index // columns)*(card_height+gap)
        draw.rounded_rectangle((x, y, x+card_width, y+card_height), radius=12,
                               fill=CARD, outline=LINE, width=1)
        title = display_name(part)
        draw.text((x+21, y+15), title, font=fit_text(draw, title, card_width-42, 24, True), fill=INK)
        rendering = render_mesh(meshes[part["id"]], (card_width-30, card_height-105),
                                "floor", forward, up, supersample)
        image.paste(rendering, (x+15, y+58), rendering)
        draw.text((x+21, y+card_height-34), "Top-down plan · bow toward top", font=font(16), fill=MUTED)
    image_footer(image, "Actual mesh outlines · each part fitted independently")
    return image


def rel_link(path: Path, output: Path) -> str:
    return Path(os.path.relpath(path, output)).as_posix()


def make_index(output: Path, contract_path: Path, entries: list[dict],
               summary_images: list[tuple[str, str]], manifest: list[dict]) -> None:
    escape = html.escape
    figures = "\n".join(f'<a class="sheet" href="{escape(filename)}"><img src="{escape(filename)}" alt="{escape(title)}"><span>{escape(title)} · full-resolution PNG ↗</span></a>'
                          for title, filename in summary_images)
    cards = []
    for item in manifest:
        cards.append(f'''<article><a href="{escape(item['image'])}"><img loading="lazy" src="{escape(item['image'])}" alt="{escape(item['label'])}"></a>
<div><h3>{escape(item['label'])}</h3><p>{escape(item['view'])}</p><nav><a href="{escape(item['image'])}">Open PNG ↗</a><a href="{escape(item['mesh'])}" download>Download OBJ ↓</a></nav></div></article>''')
    document = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Canonical ship kit · construction meshes</title><style>
:root{{--paper:#eeefea;--card:#f8f7f0;--ink:#1d2d2f;--muted:#64716f;--line:#d2d7cd;--accent:#a4622c}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font:16px/1.6 Segoe UI,system-ui,sans-serif}}main{{max-width:1440px;margin:auto;padding:52px 32px 70px}}
.eyebrow{{font-size:12px;letter-spacing:.17em;text-transform:uppercase;color:var(--muted);font-weight:700}}.eyebrow:before{{content:"";display:inline-block;width:32px;height:3px;background:var(--accent);vertical-align:middle;margin-right:12px}}
h1{{font-size:clamp(32px,4.5vw,62px);letter-spacing:-.035em;line-height:1.13;margin:18px 0}}.intro{{max-width:790px;color:var(--muted);font-size:18px}}a{{color:inherit;text-decoration:none}}a:hover{{color:var(--accent)}}.metadata{{display:flex;gap:22px;flex-wrap:wrap;font-size:13px;padding:20px 0 32px}}.metadata a{{border-bottom:1px solid var(--line)}}
.sheet{{display:block;border:1px solid var(--line);border-radius:12px;overflow:hidden;background:var(--card);margin:0 0 28px}}.sheet img{{display:block;width:100%}}.sheet span{{display:block;border-top:1px solid var(--line);padding:14px 22px;font-size:13px}}
h2{{font-size:27px;margin:48px 0 20px;letter-spacing:-.025em}}.grid{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px}}article{{background:var(--card);border:1px solid var(--line);border-radius:12px;overflow:hidden}}article img{{display:block;width:100%;aspect-ratio:10/7;object-fit:cover}}article div{{padding:16px 20px 21px}}h3{{font-size:18px;margin:0 0 4px}}article p{{font-size:13px;color:var(--muted);margin:0 0 14px}}nav{{display:flex;gap:18px;flex-wrap:wrap;font-size:13px}}footer{{margin-top:48px;padding-top:18px;border-top:1px solid var(--line);color:var(--muted);font-size:13px}}@media(max-width:920px){{.grid{{grid-template-columns:repeat(2,minmax(0,1fr))}}}}@media(max-width:600px){{main{{padding:30px 16px}}.grid{{grid-template-columns:1fr}}}}
</style></head><body><main><div class="eyebrow">Canonical ship kit</div><h1>Construction meshes</h1>
<p class="intro">A geometry review of the modular hull, independent floor shapes, and supplied assembly arrangements. Every image is an orthographic render of the referenced OBJ faces, with flat timber, iron, and deck shading.</p>
<div class="metadata"><span>{len(entries)} construction meshes</span><span>Depth-buffered rasterization</span><a href="{escape(rel_link(contract_path, output))}">Open canonical contract ↗</a></div>
{figures}<h2>Individual meshes &amp; downloads</h2><div class="grid">{''.join(cards)}</div>
<footer>Parts are fitted independently in the overview. Use the supplied assembly views to compare their assembled proportions. These are construction meshes; image framing does not change their geometry.</footer>
</main></body></html>'''
    (output / "index.html").write_text(document, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--contract", type=Path, default=ROOT/"canonical"/"contract.json")
    parser.add_argument("--out", type=Path, default=ROOT/"previews")
    parser.add_argument("--up-axis", choices=("x", "y", "z", "-x", "-y", "-z"), default="y")
    parser.add_argument("--forward-axis", choices=("x", "y", "z", "-x", "-y", "-z"), default="-z")
    parser.add_argument("--supersample", type=float, default=1.5)
    args = parser.parse_args()
    forward, up = axis_vector(args.forward_axis), axis_vector(args.up_axis)
    if abs(float(np.dot(forward, up))) > 0.01:
        parser.error("--up-axis and --forward-axis must be perpendicular")
    if not 1 <= args.supersample <= 3:
        parser.error("--supersample must be between 1 and 3")
    contract_path = args.contract.resolve()
    contract = json.loads(contract_path.read_text(encoding="utf-8-sig"))
    parts, assemblies = contract.get("parts", []), contract.get("assemblies", [])
    if not parts:
        parser.error("contract must contain a nonempty parts array")
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    meshes: dict[str, Mesh] = {}
    entries = parts + assemblies
    for entry in entries:
        path = (contract_path.parent/entry["mesh"]).resolve()
        if not path.is_file():
            raise FileNotFoundError(f"Missing mesh for {entry['id']}: {path}")
        meshes[entry["id"]] = load_obj(path)
    summary_images = []
    if any(not is_floor(part) for part in parts):
        overview = part_sheet(parts, meshes, forward, up, args.supersample)
        overview.save(output/"hull-overview.png", optimize=True)
        summary_images.append(("Hull construction meshes", "hull-overview.png"))
        print("Rendered hull-overview.png", flush=True)
    floors = [part for part in parts if is_floor(part)]
    if floors:
        floor_sheet(floors, meshes, forward, up, args.supersample).save(output/"floor-overview.png", optimize=True)
        summary_images.append(("Floor construction meshes", "floor-overview.png"))
        print("Rendered floor-overview.png", flush=True)
    manifest = []
    assembly_ids = {entry["id"] for entry in assemblies}
    for entry in entries:
        mesh = meshes[entry["id"]]
        filename = safe_id(entry["id"]) + ".png"
        assembly = entry["id"] in assembly_ids
        preview = single_preview(entry, mesh, forward, up, args.supersample, assembly)
        preview.save(output/filename, optimize=True)
        manifest.append({"id": entry["id"], "label": display_name(entry),
                         "image": filename, "mesh": rel_link(mesh.path, output),
                         "view": VIEW_LABELS[choose_view(entry, assembly)],
                         "vertices": len(mesh.vertices), "faces": mesh.polygon_count,
                         "triangles": len(mesh.triangles)})
        if assembly:
            summary_images.append((display_name(entry), filename))
        print(f"Rendered {filename}", flush=True)
    make_index(output, contract_path, entries, summary_images, manifest)
    (output/"render-manifest.json").write_text(json.dumps({
        "contract": rel_link(contract_path, output),
        "coordinate_view": {"up": args.up_axis, "forward": args.forward_axis},
        "renderer": "orthographic barycentric z-buffer, flat materials, two-sided faces",
        "previews": manifest,
    }, indent=2)+"\n", encoding="utf-8")
    print(f"Preview index: {output/'index.html'}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
