"""Take the solid bulwark off the game hull's weather deck, so a rail can stand there instead.

    python tools/strip_game_bulwarks.py

The top tier of art/models/ship/double_deck.glb is a plain 0.8 m plank wall round the weather
deck. This removes it down to the deck (Y=5.2), where the tier below ends in a flat 0.2 m wall
top: ship.gd stands the rail posts on that top and lays the rail between them.

The bow head is kept: the first pair of wall panels, from the raked stem back to Z=-0.8. The
bowsprit is seated in it. Its open aft ends are closed with a cap each.

Kept triangles are copied byte for byte. Caps get the kit's plank UVs with the rest, from
texture_game_hull.textured. Refuses if a triangle crosses the deck line, and does nothing
if the wall is already gone.
"""
import struct
import sys
from collections import Counter
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texture_game_hull  # noqa: E402

HULL = texture_game_hull.HULL
DECK_Y = 5.2
# Aft end of the bow head: every wall triangle forward of this is kept.
BOW_HEAD_Z = -0.8
EPS = 1e-3


def triangles(data):
    return np.frombuffer(data, dtype=np.float32).reshape(-1, 3, 3)


def caps(kept):
    """Triangles closing each open end left in `kept`, facing away from it."""
    edges = Counter()
    for tri in kept.round(4):
        for a, b in ((0, 1), (1, 2), (2, 0)):
            edges[tuple(sorted((tuple(tri[a]), tuple(tri[b]))))] += 1
    loose = [e for e, n in edges.items() if n == 1]
    links = {}
    for a, b in loose:
        links.setdefault(a, []).append(b)
        links.setdefault(b, []).append(a)
    out, seen = [], set()
    for start in links:
        if start in seen:
            continue
        loop, previous, current = [start], None, start
        seen.add(start)
        while True:
            step = [n for n in links[current] if n != previous and n not in seen]
            if not step:
                break
            previous, current = current, step[0]
            loop.append(current)
            seen.add(current)
        ring = np.array(loop, dtype=np.float64)
        if len(ring) < 3:
            raise SystemExit('an open edge that is not a closed ring; the wall is not what this expects')
        centre = ring.mean(axis=0)
        # The kept wall near this ring: the cap faces away from it.
        near = kept.reshape(-1, 3)
        near = near[np.linalg.norm(near - centre, axis=1) < 1.0].mean(axis=0)
        for i in range(1, len(ring) - 1):
            tri = np.array([ring[0], ring[i], ring[i + 1]])
            normal = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            if np.dot(normal, centre - near) < 0:
                tri = tri[[0, 2, 1]]
            out.append(tri)
    return np.array(out, dtype=np.float32).reshape(-1, 3, 3)


def main():
    source = texture_game_hull.primitives(HULL)
    stripped, dropped, capped = [], 0, 0
    for name, pos_bytes, nrm_bytes in source:
        pos, nrm = triangles(pos_bytes), triangles(nrm_bytes)
        low, high = pos[:, :, 1].min(axis=1), pos[:, :, 1].max(axis=1)
        if ((low < DECK_Y - EPS) & (high > DECK_Y + EPS)).any():
            raise SystemExit(f'{name}: a triangle crosses the deck line; the tiers are not separate here')
        aft = pos[:, :, 2].max(axis=1) > BOW_HEAD_Z
        wall = (low >= DECK_Y - EPS) & (high > DECK_Y + EPS)
        # The wall's own underside, lying face down on the tier below.
        underside = (np.abs(pos[:, :, 1] - DECK_Y) < EPS).all(axis=1) & (nrm[:, 0, 1] < -0.5)
        drop = (wall | underside) & aft
        dropped += int(drop.sum())
        keep_pos, keep_nrm = pos[~drop], nrm[~drop]
        if drop.any():
            head = keep_pos[(keep_pos[:, :, 1] >= DECK_Y - EPS).all(axis=1)
                            & (keep_pos[:, :, 1].max(axis=1) > DECK_Y + EPS)]
            head_under = keep_pos[(np.abs(keep_pos[:, :, 1] - DECK_Y) < EPS).all(axis=1)
                                  & (keep_nrm[:, 0, 1] < -0.5)]
            cap = caps(np.concatenate([head, head_under])) if len(head) else np.zeros((0, 3, 3), np.float32)
            normal = np.cross(cap[:, 1] - cap[:, 0], cap[:, 2] - cap[:, 0])
            normal /= np.linalg.norm(normal, axis=1, keepdims=True)
            keep_pos = np.concatenate([keep_pos, cap])
            keep_nrm = np.concatenate([keep_nrm, np.repeat(normal[:, None, :], 3, axis=1).astype(np.float32)])
            capped += len(cap)
        stripped.append((name, keep_pos.astype(np.float32).tobytes(), keep_nrm.astype(np.float32).tobytes()))
    if dropped == 0:
        print(f'{HULL.name}: no bulwark above the deck; nothing to do')
        return
    data = texture_game_hull.textured(stripped)
    staged = HULL.with_suffix('.stripped.tmp')
    staged.write_bytes(data)
    try:
        after = texture_game_hull.primitives(staged)
        for (name, pos_bytes, _), (_, new_bytes, _) in zip(stripped, after):
            if pos_bytes != new_bytes:
                raise SystemExit(f'{name}: the written positions differ from the stripped ones; not written')
            left = triangles(new_bytes)
            if ((left[:, :, 1].max(axis=1) > DECK_Y + EPS) & (left[:, :, 2].max(axis=1) > BOW_HEAD_Z)).any():
                raise SystemExit(f'{name}: wall still stands aft of the bow head; not written')
        staged.replace(HULL)
    finally:
        staged.unlink(missing_ok=True)
    print(f'{HULL.name}: {dropped} bulwark triangles removed above the deck, bow head kept, {capped} cap triangles added')


if __name__ == '__main__':
    main()
