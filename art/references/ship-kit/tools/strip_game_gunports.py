"""Take the gun deck's side walls, with their gunport holes, out of the game hull.

    python tools/strip_game_gunports.py

The kit's MIDDLE_CENTRE_GUN bays cut one port per side in each 2 m bay, so the ports can only
be where the bays put them. This removes those walls from art/models/ship/double_deck.glb -
both sides, z 4 to 12, gun deck to weather deck, 0.2 m thick - and ship.gd builds them again
with a hole wherever its ports are spread (Ship._build_gun_walls), so the holes, frames, lids
and guns all move together.

Kept: the flat wall tops at the weather deck, which the rail stands on and
build_stern_castle.py reads the hull's outline from, and the bottom tier's top under them.
Kept triangles are copied byte for byte with the kit's plank UVs (texture_game_hull.textured).
Does nothing if the walls are already gone.
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import texture_game_hull  # noqa: E402

HULL = texture_game_hull.HULL
GUN_DECK_Y, DECK_Y = 2.6, 5.2
FORE_Z, AFT_Z = 4.0, 12.0
INNER_X = 2.8
EPS = 1e-3


def main():
    source = texture_game_hull.primitives(HULL)
    stripped, dropped = [], 0
    for name, pos_bytes, nrm_bytes in source:
        pos = np.frombuffer(pos_bytes, dtype=np.float32).reshape(-1, 3, 3)
        nrm = np.frombuffer(nrm_bytes, dtype=np.float32).reshape(-1, 3, 3)
        drop = np.zeros(len(pos), bool)
        if name == 'wood':
            inside = ((np.abs(pos[:, :, 0]) >= INNER_X - 0.01).all(axis=1)
                      & (pos[:, :, 1] >= GUN_DECK_Y - EPS).all(axis=1) & (pos[:, :, 1] <= DECK_Y + EPS).all(axis=1)
                      & (pos[:, :, 2] >= FORE_Z - EPS).all(axis=1) & (pos[:, :, 2] <= AFT_Z + EPS).all(axis=1))
            top = (np.abs(pos[:, :, 1] - DECK_Y) < EPS).all(axis=1)
            below = (np.abs(pos[:, :, 1] - GUN_DECK_Y) < EPS).all(axis=1) & (nrm[:, 0, 1] > 0.5)
            drop = inside & ~top & ~below
        dropped += int(drop.sum())
        stripped.append((name, pos[~drop].tobytes(), nrm[~drop].tobytes()))
    if dropped == 0:
        print(f'{HULL.name}: no gun deck side walls left to take out; nothing to do')
        return
    data = texture_game_hull.textured(stripped)
    staged = HULL.with_suffix('.stripped.tmp')
    staged.write_bytes(data)
    try:
        after = texture_game_hull.primitives(staged)
        for (name, pos_bytes, _), (_, new_bytes, _) in zip(stripped, after):
            if pos_bytes != new_bytes:
                raise SystemExit(f'{name}: the written positions differ from the stripped ones; not written')
        staged.replace(HULL)
    finally:
        staged.unlink(missing_ok=True)
    print(f'{HULL.name}: {dropped} gun deck wall triangles taken out, z {FORE_Z} to {AFT_Z}, both sides')


if __name__ == '__main__':
    main()
