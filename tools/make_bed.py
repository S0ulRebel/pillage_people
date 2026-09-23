r"""Pick the best ambience take and cut it into a seamless loop.

    python make_bed.py "outputs/models/surf_*.flac" --out ".../art/audio/beds/surf.ogg"

The opposite job to trim_sfx.py, and it wants the opposite measurements. A sound effect should
be loud, brief and quiet either side. A bed should be none of those: it has to hold a level,
sound the same at the end as at the beginning, and contain nothing memorable - because whatever
is memorable in it is what you will notice repeating, and once noticed it cannot be unnoticed.

So the takes are ranked on:

  steady  how little the level wanders about its own average
  event   the loudest moment against a typical one; one distinctive crash ruins a loop
  drift   whether the end still sounds like the beginning, compared across frequency bands
  seam    how cleanly the chosen loop actually joins

The last one is the point. The first three can all be read off a take before anything is cut,
and none of them tells you whether a good loop exists inside it - so every take is put through
the loop finder and the join is measured, and the winner is the take that produced the best
loop rather than the one that looked most promising beforehand.

Levelled to a target RMS rather than to a peak. A bed peak-normalised the way an effect is
arrives at the same loudness as a sword landing, which is not where ambience belongs.
"""
import argparse
import glob
import os
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from make_loop import envelope, find_loop, read_wav, write_ogg  # noqa: E402

# The encoder that ships here writes ogg vorbis that crackles - measurably, 162 sample jumps
# into a clean track - so the file is written losslessly and encoded by the one on this machine
# that works. Set BED_ENCODER to point elsewhere if it moves.
ENCODER = os.environ.get(
    "BED_ENCODER", r"C:\Program Files\Blender Foundation\Blender 4.3\blender.exe")


def bands(block, count=16):
    windowed = block * np.hanning(len(block))
    magnitude = np.abs(np.fft.rfft(windowed))
    energy = np.array([b.mean() for b in np.array_split(magnitude[:len(magnitude) // 2], count)])
    return energy / (np.linalg.norm(energy) + 1e-9)


def measure(samples, rate):
    """The three things about a take that can be known before trying to loop it."""
    mono = samples.mean(axis=1)
    level, _ = envelope(mono, rate, bucket=0.25)
    if level.max() <= 0.0:
        return None
    steady = float(level.std() / max(level.mean(), 1e-9))
    event = float(level.max() / max(np.median(level), 1e-9))
    third = len(mono) // 3
    drift = float(np.abs(bands(mono[:third]) - bands(mono[-third:])).sum())
    return {"steady": steady, "event": event, "drift": drift,
            "rms": float(np.sqrt((mono ** 2).mean()))}


def spread(values):
    """Each value's position between the smallest and largest, so measures on wildly different
    scales can be weighed against each other by importance rather than by magnitude."""
    low, high = min(values), max(values)
    if high - low < 1e-9:
        return [0.0] * len(values)
    return [(v - low) / (high - low) for v in values]


def level_to(body, rms_target, ceiling=0.94):
    mono = body.mean(axis=1)
    rms = float(np.sqrt((mono ** 2).mean()))
    if rms <= 0.0:
        return body
    gain = rms_target / rms
    peak = float(np.abs(body).max())
    # A bed with an unusually loud moment in it would clip before it reached the target; back
    # off rather than let the encoder square it off.
    if peak * gain > ceiling:
        gain = ceiling / max(peak, 1e-9)
    return body * gain


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pattern", help="quoted glob, e.g. 'outputs/models/surf_*.flac'")
    ap.add_argument("--out", required=True, help="written as .ogg")
    ap.add_argument("--min", type=float, default=25.0,
                    help="shortest acceptable loop, seconds. Ambience needs less than music: "
                         "there is no melody to give the repeat away, and a shorter loop is a "
                         "smaller file")
    ap.add_argument("--fade", type=float, default=0.25,
                    help="crossfade at the seam. Longer than music's, because a bed has no "
                         "downbeat for a long fade to blur")
    ap.add_argument("--rms", type=float, default=0.075, help="target loudness, 0-1")
    ap.add_argument("--bitrate", type=int, default=128)
    ap.add_argument("--max-seam", type=float, default=2.0,
                    help="seam size, as a multiple of a typical sample step, above which a take "
                         "is treated as not joining at all")
    args = ap.parse_args()

    files = sorted(glob.glob(args.pattern))
    if not files:
        raise SystemExit(f"nothing matches {args.pattern}")

    takes = []
    for path in files:
        samples, rate = read_wav(path)
        reading = measure(samples, rate)
        if reading is None:
            print(f"  {Path(path).name}: silent, skipped")
            continue
        print(f"{Path(path).name}: {len(samples) / rate:.1f}s")
        try:
            body, loop = find_loop(samples, rate, args.min, args.fade, say=lambda m: print(m))
        except SystemExit as reason:
            print(f"  no loop: {reason}")
            continue
        reading.update(loop)
        takes.append((body, rate, Path(path).name, reading))

    if not takes:
        raise SystemExit("no take produced a loop")

    # Positions within the observed range, so the weights below mean importance and not scale.
    ranked = []
    worst = [spread([t[3][key] for t in takes]) for key in ("steady", "event", "drift", "ratio")]
    for index, (body, rate, name, reading) in enumerate(takes):
        cost = (worst[0][index] * 0.5 + worst[1][index] * 0.9
                + worst[2][index] * 1.0 + worst[3][index] * 1.0)
        # A bad seam is disqualifying rather than expensive, and the difference matters.
        #
        # Traded off against the others, a take once won on drift while carrying a seam three
        # times a typical sample step - and levelled up to playing volume that join became a
        # step of 0.19, which is a click, on every repeat, forever. Drift is a quality you may
        # never consciously notice. A click is a defect you cannot stop noticing. So anything
        # above the limit sorts below everything under it, whatever else it has going for it.
        clicks = reading["ratio"] > args.max_seam
        ranked.append((1 if clicks else 0, cost, index))
    ranked.sort()
    if ranked[0][0] == 1:
        print(f"  (no take joins cleanly - every seam is over {args.max_seam:.1f}x a typical "
              f"sample step, so this is the least bad rather than a good one)")

    print()
    print("%-22s %7s %7s %7s %8s %7s %s" % ("take", "steady", "event", "drift", "seam", "loop", ""))
    for place, (clicks, cost, index) in enumerate(ranked):
        _, _, name, reading = takes[index]
        print("%-22s %7.2f %7.2f %7.3f %7.1fx %6.1fs  cost %.2f%s%s"
              % (name, reading["steady"], reading["event"], reading["drift"],
                 reading["ratio"], reading["length"], cost,
                 "  CLICKS" if clicks else "", "  <- chosen" if place == 0 else ""))

    body, rate, name, reading = takes[ranked[0][2]]
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    levelled = level_to(body, args.rms)

    if out.suffix.lower() == ".wav":
        write_ogg(out, levelled, rate, args.bitrate)
    else:
        # Lossless first, then handed to a working encoder. Doing it in one command rather than
        # leaving a WAV and an instruction, because a half-finished asset in the game folder is
        # one that eventually ships.
        staged = out.with_suffix(".staged.wav")
        write_ogg(staged, levelled, rate, args.bitrate)
        encoder = Path(ENCODER)
        if not encoder.exists():
            raise SystemExit(f"no encoder at {encoder}; the loop is written as {staged}.\n"
                             f"Set BED_ENCODER to a working one and run again.")
        result = subprocess.run(
            [str(encoder), "--background", "--factory-startup",
             "--python", str(Path(__file__).parent / "encode_ogg.py"),
             "--", str(staged), str(out), str(args.bitrate)],
            capture_output=True, text=True)
        if not out.exists():
            raise SystemExit(f"encoding failed, the loop is still at {staged}\n"
                             + result.stdout[-800:] + result.stderr[-800:])
        staged.unlink()

    print(f"\n  -> {out}  ({out.stat().st_size / 1048576:.2f} MB, {reading['length']:.1f}s loop "
          f"from {name})")


if __name__ == "__main__":
    main()
