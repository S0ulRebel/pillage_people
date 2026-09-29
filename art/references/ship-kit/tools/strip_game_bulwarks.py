"""Take the solid bulwark off the game hull's weather deck, so a rail can stand there instead.

    python tools/strip_game_bulwarks.py

The top tier of art/models/ship/double_deck.glb is a plain 0.8 m plank wall round the weather
deck, bow to stern. This removes all of it down to the deck (Y=5.2), where the tier below
ends in a flat wall top: ship.gd stands the rail posts on that top and lays the rail between
them. The kit's panels are closed solids, so taking whole panels away leaves no hole.

Kept triangles are copied byte for byte and keep the kit's plank UVs (texture_game_hull
.textured). Refuses if a triangle crosses the deck line, and does nothing if the wall is
already gone.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texture_game_hull  # noqa: E402

HULL = texture_game_hull.HULL
DECK_Y = 5.2
EPS = 1e-3


def triangles(data):
    return np.frombuffer(data, dtype=np.float32).reshape(-1, 3, 3)


def main():
    source = texture_game_hull.primitives(HULL)
    stripped, dropped = [], 0
    for name, pos_bytes, nrm_bytes in source:
        pos, nrm = triangles(pos_bytes), triangles(nrm_bytes)
        low, high = pos[:, :, 1].min(axis=1), pos[:, :, 1].max(axis=1)
        if ((low < DECK_Y - EPS) & (high > DECK_Y + EPS)).any():
            raise SystemExit(f'{name}: a triangle crosses the deck line; the tiers are not separate here')
        wall = (low >= DECK_Y - EPS) & (high > DECK_Y + EPS)
        # The wall's own underside, lying face down on the tier below.
        underside = (np.abs(pos[:, :, 1] - DECK_Y) < EPS).all(axis=1) & (nrm[:, 0, 1] < -0.5)
        drop = wall | underside
        dropped += int(drop.sum())
        stripped.append((name, pos[~drop].tobytes(), nrm[~drop].tobytes()))
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
            if (triangles(new_bytes)[:, :, 1] > DECK_Y + EPS).any():
                raise SystemExit(f'{name}: wall still stands above the deck; not written')
        staged.replace(HULL)
    finally:
        staged.unlink(missing_ok=True)
    print(f'{HULL.name}: {dropped} bulwark triangles removed above the deck')


if __name__ == '__main__':
    main()
