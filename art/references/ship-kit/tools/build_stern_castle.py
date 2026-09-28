"""Build the stern castle from the game hull's own outline: the cabin, its roof the quarterdeck.

    python tools/build_stern_castle.py

A cabin modelled on its own cannot follow this hull: the stern narrows from 6 m to a point
over its last four metres, and a box either stands clear of the sides or goes through them.
So the castle is the hull carried up one more tier. Its walls stand on the outer edge of the
hull's wall top, measured off art/models/ship/double_deck.glb after
strip_game_bulwarks.py has taken the old bulwark off. They run from FRONT_Z round the stern,
TIER high, facet for facet with the hull below. A front wall closes it across the deck, and
the roof over the whole outline is the quarterdeck.

Same plank texture and UV rule as the hull (texture_game_hull.textured), and the tiers are
the kit's 2.6 m, so the planking runs on up the castle's sides. Positions are in ship space:
ship.gd places the model at the origin.

Writes art/models/ship/cabin/stern_castle.glb. Run again after the hull changes.
"""
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texture_game_hull  # noqa: E402

HULL = texture_game_hull.HULL
OUT = HULL.parent / 'cabin' / 'stern_castle.glb'
DECK_Y = 5.2
TIER = 2.6
# The castle's front face. ship.gd's CASTLE_FRONT_Z must match.
FRONT_Z = 10.4


def wall_top(path):
    """The hull's outer edge at the deck, starboard half, bow to stern: the outline of the
    flat wall top the tier below ends in."""
    for name, pos_bytes, nrm_bytes in texture_game_hull.primitives(path):
        if name != 'wood':
            continue
        pos = np.frombuffer(pos_bytes, dtype=np.float32).reshape(-1, 3, 3)
        nrm = np.frombuffer(nrm_bytes, dtype=np.float32).reshape(-1, 3, 3)
        if (pos[:, :, 1] > DECK_Y + 1e-3).any():
            raise SystemExit(f'{path.name}: the old bulwark is still on; run strip_game_bulwarks.py first')
        top = pos[(np.abs(pos[:, :, 1] - DECK_Y) < 1e-3).all(axis=1) & (nrm[:, 0, 1] > 0.5)][:, :, [0, 2]]
        edges = Counter()
        for tri in top.round(4):
            for a, b in ((0, 1), (1, 2), (2, 0)):
                edges[tuple(sorted((tuple(tri[a]), tuple(tri[b]))))] += 1
        loose = np.array([e for e, n in edges.items() if n == 1]).reshape(-1, 2)
        # Two rings bound the band: the outer is the one reaching furthest out.
        points = np.unique(loose, axis=0)
        widest = np.abs(points[:, 0]).max()
        ring = _ring_through(edges, points[np.argmax(np.abs(points[:, 0]))])
        if np.abs(ring[:, 0]).max() < widest - 1e-3:
            raise SystemExit('could not find the hull\'s outer edge')
        half = ring[ring[:, 0] >= -1e-6]
        return half[np.argsort(half[:, 1])]
    raise SystemExit(f'{path.name}: no wood surface')


def _ring_through(edges, start):
    links = {}
    for (a, b), n in edges.items():
        if n == 1:
            links.setdefault(a, []).append(b)
            links.setdefault(b, []).append(a)
    start = tuple(start)
    ring, previous, current = [start], None, start
    while True:
        step = [n for n in links[current] if n != previous and n != start and n not in ring]
        if not step:
            break
        previous, current = current, step[0]
        ring.append(current)
    return np.array(ring)


def outline(half):
    """The castle's plan, closed and counter-clockwise seen from above: starboard front corner,
    down the starboard side, round the stern, up the port side to the port front corner."""
    aft = half[half[:, 1] > FRONT_Z]
    ahead = half[half[:, 1] <= FRONT_Z][-1]
    after = aft[0]
    t = (FRONT_Z - ahead[1]) / (after[1] - ahead[1])
    corner = ahead + (after - ahead) * t
    starboard = np.vstack([corner, aft])
    port = starboard[::-1] * [-1.0, 1.0]
    ring = np.vstack([starboard, port[1:] if abs(starboard[-1, 0]) < 1e-6 else port])
    area = 0.5 * np.sum(ring[:, 0] * np.roll(ring[:, 1], -1) - np.roll(ring[:, 0], -1) * ring[:, 1])
    return ring if area > 0 else ring[::-1]


def facing(tri, normal):
    """`tri` wound so its front face looks along `normal`."""
    if np.dot(np.cross(tri[1] - tri[0], tri[2] - tri[0]), normal) < 0:
        tri = tri[[0, 2, 1]]
    return tri


def build(ring):
    low, high = DECK_Y, DECK_Y + TIER
    centre = ring.mean(axis=0)
    walls, roof = [], []
    for i in range(len(ring)):
        a, b = ring[i], ring[(i + 1) % len(ring)]
        edge = b - a
        out = np.array([edge[1], 0.0, -edge[0]])
        mid = (a + b) / 2
        if np.dot(out[[0, 2]], mid - centre) < 0:
            out = -out
        out /= np.linalg.norm(out)
        a0, b0 = np.array([a[0], low, a[1]]), np.array([b[0], low, b[1]])
        a1, b1 = np.array([a[0], high, a[1]]), np.array([b[0], high, b[1]])
        for tri in (np.array([a0, b0, b1]), np.array([a0, b1, a1])):
            walls.append((facing(tri, out), out))
        tri = np.array([[centre[0], high, centre[1]], [a[0], high, a[1]], [b[0], high, b[1]]])
        roof.append((facing(tri, np.array([0.0, 1.0, 0.0])), np.array([0.0, 1.0, 0.0])))
    source = []
    for name, tris in (('wood', walls), ('deck', roof)):
        pos = np.array([t for t, _ in tris], dtype=np.float32)
        nrm = np.array([[n, n, n] for _, n in tris], dtype=np.float32)
        source.append((name, pos.tobytes(), nrm.tobytes()))
    return source


def main():
    ring = outline(wall_top(HULL))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(texture_game_hull.textured(build(ring), 'stern_castle'))
    width = ring[:, 0].max() - ring[:, 0].min()
    print(f'{OUT.relative_to(texture_game_hull.REPO)}: {len(ring)} wall facets, front at z {FRONT_Z}, '
          f'{width:.2f} m wide at the front, to z {ring[:, 1].max():.2f}, roof at {DECK_Y + TIER:.1f}')


if __name__ == '__main__':
    main()
