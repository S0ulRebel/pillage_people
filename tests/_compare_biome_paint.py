"""Runs tests/biome_paint_view.gd once unpainted and once painted, and checks that painting
moved the two measured pixels, in the right direction. Called by run_biome_paint_view.sh, not
run directly - it needs GODOT and OUT_DIR set.

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


def distance(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def greyness(c):
    r, g, b = c
    return 1.0 - (abs(r - g) + abs(g - b) + abs(r - b)) / 3.0


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

    moved_rock = distance(base["rock"], paint["rock"])
    moved_grass = distance(base["grass"], paint["grass"])
    print("rock point:  auto %s -> painted 'no rock'   %s  (moved %.3f)" % (base["rock"], paint["rock"], moved_rock))
    print("grass point: auto %s -> painted 'full rock' %s  (moved %.3f)" % (base["grass"], paint["grass"], moved_grass))
    check(moved_rock > 0.08, "painting 'no rock' onto the cliff barely changed its colour (%.3f)" % moved_rock)
    check(moved_grass > 0.08, "painting 'full rock' onto the grass barely changed its colour (%.3f)" % moved_grass)

    grey_rock_before, grey_rock_after = greyness(base["rock"]), greyness(paint["rock"])
    grey_grass_before, grey_grass_after = greyness(base["grass"]), greyness(paint["grass"])
    print("greyness: rock point %.3f -> %.3f (should fall); grass point %.3f -> %.3f (should rise)"
          % (grey_rock_before, grey_rock_after, grey_grass_before, grey_grass_after))
    check(grey_rock_after < grey_rock_before,
          "removing rock from the cliff should make it less grey, not more (%.3f -> %.3f)"
          % (grey_rock_before, grey_rock_after))
    check(grey_grass_after > grey_grass_before,
          "forcing rock onto the grass should make it more grey, not less (%.3f -> %.3f)"
          % (grey_grass_before, grey_grass_after))

    print("biome_paint_view: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
