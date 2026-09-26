#!/bin/sh
# Runs addons/biome_painter_live_check inside a headless editor: it drives the real,
# permanently-enabled addons/biome_painter through a paint stroke. See editor_live_check.sh,
# which this copies exactly - the editor reads its plugin list from project.godot and nothing
# else (override.cfg is ignored in editor mode), so the test-runner plugin is added there for
# this run alone: project.godot is backed up first and put back exactly as it was, whatever
# happens. biome_painter itself is not touched here - it is already in project.godot to stay.
cd "$(dirname "$0")/.." || exit 1
cp project.godot project.godot.live_check_backup || exit 1
restore() { cp project.godot.live_check_backup project.godot; rm -f project.godot.live_check_backup; }
trap restore EXIT INT TERM
python - <<'PY'
import re
p = "project.godot"
s = open(p, encoding="utf-8", newline="").read()
me = '"res://addons/biome_painter_live_check/plugin.cfg"'
m = re.search(r'\[editor_plugins\]\s*\n\s*enabled=PackedStringArray\(([^)]*)\)', s)
if m:
    inner = m.group(1).strip()
    new = inner + (", " if inner else "") + me
    s = s[:m.start(1)] + new + s[m.end(1):]
else:
    s = s.rstrip("\r\n") + "\n\n[editor_plugins]\n\nenabled=PackedStringArray(" + me + ")\n"
open(p, "w", encoding="utf-8", newline="").write(s)
PY
timeout 300 "${GODOT:-D:/Godot/Godot_v4.7.2-stable_win64_console.exe}" --headless --editor
