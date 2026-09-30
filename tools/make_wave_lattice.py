# Makes world/wave_lattice.png (whitecap_style 1 prototype):
#   python3 tools/make_wave_lattice.py world/wave_lattice.png 5
# Needs numpy, scipy and Pillow. Also writes a *_look.png preview next to it.
# Painted wave lattice tile (option 1): rows of overlapping arched crests like the swatches.
# R: white crest strokes, beads and clumps  G: face (0 just under a crest -> 1 a row below)
# B: soft glow spilling down the face under the white
# A: which crest is above this pixel (a random number per crest), for the whitecap events
import numpy as np, sys
from PIL import Image
from scipy.ndimage import gaussian_filter

N = 1024
ROWS = 7
rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 3)
white = np.zeros((N, N), np.float32)
face = np.full((N, N), 1e9, np.float32)
owner = np.zeros((N, N), np.float32)
vv = np.arange(N, dtype=np.float32)[:, None]

def stamp(u, v, r):
    r = max(r, 0.6)
    x0, y0 = int(np.floor(u - r - 1)), int(np.floor(v - r - 1))
    xs = np.arange(x0, x0 + int(2 * r + 4))
    ys = np.arange(y0, y0 + int(2 * r + 4))
    d = np.sqrt((xs[None, :] - u) ** 2 + (ys[:, None] - v) ** 2)
    cov = np.clip(r - d + 0.5, 0.0, 1.0)
    iy, ix = np.ix_(ys % N, xs % N)
    white[iy, ix] = np.maximum(white[iy, ix], cov)

def noise1d(n, scale):
    k = max(int(n / scale), 2)
    pts = rng.random(k + 1)
    x = np.linspace(0, k, n)
    i = np.floor(x).astype(int).clip(0, k - 1)
    f = x - i
    f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[i + 1] * f

row_h = N / ROWS
connectors = []
for r in range(ROWS):
    base = (r + 0.5) * row_h + rng.uniform(-0.15, 0.15) * row_h
    u = rng.uniform(0, N)
    end = u + N
    while u < end:
        length = rng.uniform(0.28, 0.5) * N
        arch = rng.uniform(0.2, 0.34) * row_h
        tilt = rng.uniform(-0.12, 0.12) * row_h
        vbase = base + rng.uniform(-0.12, 0.12) * row_h
        s = np.linspace(0, 1, int(length))
        wob = (noise1d(len(s), 70) - 0.5) * 0.16 * row_h
        arc_v = vbase - arch * 4 * s * (1 - s) + tilt * (s - 0.5) + wob
        arc_u = u + s * length
        # the face below this crest: distance down (in v) to each pixel, wrapped - for every
        # whole column the crest spans (sampling along the crest skipped some, and a skipped
        # column kept another crest's id: a hard line through each whitecap)
        col_u = np.arange(int(np.ceil(arc_u[0])), int(np.floor(arc_u[-1])) + 1)
        col_v = np.interp(col_u, arc_u, arc_v)
        cols = col_u % N
        d = (vv - col_v[None, :]) % N
        crest_id = rng.uniform(0.02, 0.98)
        closer = d < face[:, cols]
        face[:, cols] = np.where(closer, d, face[:, cols])
        owner[:, cols] = np.where(closer, crest_id, owner[:, cols])
        # white on part of the crest
        if rng.random() < 0.85:
            a0 = rng.uniform(0.0, 0.35)
            a1 = rng.uniform(a0 + 0.35, 1.0)
            thick = rng.uniform(2.5, 6.5)
            bead = noise1d(len(s), 25)
            for k in range(len(s)):
                if not (a0 <= s[k] <= a1):
                    continue
                t = (s[k] - a0) / (a1 - a0)
                taper = np.sin(np.pi * t) ** 0.5
                rad = thick * taper * (0.35 + 1.1 * bead[k])
                if bead[k] < 0.22:  # gaps, so the line beads
                    continue
                stamp(arc_u[k], arc_v[k] + rad * 0.3, rad)
            # dots strung along beyond the line's ends and just under it
            for _ in range(rng.integers(3, 9)):
                k = rng.integers(0, len(s))
                stamp(arc_u[k] + rng.normal(0, 4), arc_v[k] + abs(rng.normal(3, 5)), rng.uniform(1.2, 3.2))
            # a breaking clump
            if rng.random() < 0.45:
                k = rng.integers(int(len(s) * max(a0, 0.1)), int(len(s) * min(a1, 0.9)) + 1)
                cu, cv = arc_u[k], arc_v[k]
                for _ in range(rng.integers(8, 20)):
                    stamp(cu + rng.normal(0, 14), cv + abs(rng.normal(4, 7)), rng.uniform(2.5, 7.5))
            # a connector down to the next crest (drawn once the crests are all placed)
            if rng.random() < 0.25:
                k = rng.integers(int(len(s) * 0.1), int(len(s) * 0.9))
                connectors.append((arc_u[k], arc_v[k], rng.choice([-1, 1]) * rng.uniform(0.9, 1.6)))
        u += length * rng.uniform(0.55, 0.85)

# connectors: zigzag down from a crest until they meet the next one (where the face is ~0)
for cu, cv, dirn in connectors:
    stamp(cu, cv, 5.0)
    phase = rng.random() * 6.3
    for j in range(1, int(row_h * 1.6)):
        pu = cu + dirn * j + 4.0 * np.sin(j * 0.07 + phase)
        pv = cv + j
        stamp(pu, pv, 2.2 + 0.8 * np.sin(j * 0.21 + phase))
        if j > 12 and face[int(pv) % N, int(pu) % N] < 1.5:
            stamp(pu, pv, 5.0)
            break
face = np.clip(face / row_h, 0, 1)
face = gaussian_filter(face, sigma=(2, 18), mode="wrap")
glow = gaussian_filter(np.roll(white, 7, axis=0), sigma=9, mode="wrap")
glow = np.clip(glow / max(glow.max(), 1e-6) * 2.2, 0, 1)
img = np.stack([white, face, glow, owner], -1)
Image.fromarray((img * 255).round().astype(np.uint8), "RGBA").save(sys.argv[1])
Image.fromarray((np.clip(0.25 + 0.5*(1-face)[..., None] * np.array([0.1, 0.6, 0.8]) + white[..., None], 0, 1) * 255).astype(np.uint8)).save(sys.argv[1].replace(".png", "_look.png"))
print("white %.1f%%" % (100 * (white > 0.5).mean()))
