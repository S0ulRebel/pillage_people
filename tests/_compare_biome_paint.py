"""Runs tests/biome_paint_view.gd once unpainted and once painted with a custom magenta biome,
and checks that painting moved the two measured pixels visibly towards magenta - low green,
high red and blue - which no automatic rule ever draws. Called by biome_painter tests, not run
directly - it needs GODOT and BIOME_VIEW_OUT set.

Kept as a small script rather than more GDScript because the check itself (parse two RESULT
lines, compare six numbers) needs no rendering context, and Python's assert-and-print is a lot
less code than a third Godot process just to do arithmetic.
"""
import os
import re
import subprocess
import sys

GODOT = os.environ["GODOT"]
OUT_DIR = os.environ.get("BIOME_VIEW_OUT", "")
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PATTERN = re.compile(
    r"RESULT rock_slope=([-\d.]+) grass_slope=([-\d.]+) "
    r"rock_pixel=([-\d.]+),([-\d.]+),([-\d.]+) "
    r"grass_pixel=([-\d.]+),([-\d.]+),([-\d.]+)"
)


def run(paint: bool):
    env = dict(os.environ)
    env["BIOME_PAINT"] = "1" if paint else "0"
    proc = subprocess.run(
        [GODOT, "--path", PROJECT, "--resolution", "1280x720",
         "--script", "res://tests/biome_paint_view.gd"],
        capture_output=True, text=True, timeout=180, env=env,
    )
    out = proc.stdout + proc.stderr
    for line in out.splitlines():
        if "SCRIPT ERROR" in line:
            print(line)
    match = PATTERN.search(out)
    if match is None:
        print(out[-4000:])
        sys.exit("no RESULT line from the %s render" % ("painted" if paint else "baseline"))
    values = [float(v) for v in match.groups()]
    return {
        "rock_slope": values[0], "grass_slope": values[1],
        "rock": values[2:5], "grass": values[5:8],
    }


def magenta_ness(c):
    """High when green sits well below both red and blue - the one thing every automatic
    colour (green grass, grey rock, warm sand, dark jungle) never does, and the painted colour
    (0.95, 0.05, 0.85) always does, whatever the lighting scales it by."""
    r, g, b = c
    return min(r, b) - g


def main():
    failures = 0

    def check(condition, message):
        nonlocal failures
        if not condition:
            failures += 1
            print("FAIL: " + message)

    base = run(False)
    paint = run(True)

    check(base["rock_slope"] > 0.5, "the rock point was not steep automatically (%.2f)" % base["rock_slope"])
    check(base["grass_slope"] < 0.3, "the grass point was not flat automatically (%.2f)" % base["grass_slope"])

    rock_before, rock_after = magenta_ness(base["rock"]), magenta_ness(paint["rock"])
    grass_before, grass_after = magenta_ness(base["grass"]), magenta_ness(paint["grass"])
    print("rock point:  auto %s -> painted magenta %s  (magenta-ness %.3f -> %.3f)"
          % (base["rock"], paint["rock"], rock_before, rock_after))
    print("grass point: auto %s -> painted magenta %s  (magenta-ness %.3f -> %.3f)"
          % (base["grass"], paint["grass"], grass_before, grass_after))

    check(rock_before < 0.05, "the unpainted cliff already reads as magenta-ish (%.3f) - the check proves nothing" % rock_before)
    check(grass_before < 0.05, "the unpainted grass already reads as magenta-ish (%.3f) - the check proves nothing" % grass_before)
    check(rock_after > 0.15, "painting magenta onto the cliff barely shows (magenta-ness %.3f)" % rock_after)
    check(grass_after > 0.15, "painting magenta onto the grass barely shows (magenta-ness %.3f)" % grass_after)

    print("biome_paint_view: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
