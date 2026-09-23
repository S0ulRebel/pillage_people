r"""Encode a WAV to OGG Vorbis using Blender's libvorbis.

    "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe" --background --factory-startup ^
        --python encode_ogg.py -- loop.wav loop.ogg [kb/s]

This exists because the obvious route is broken. ffmpeg's own vorbis encoder is still marked
experimental, and it earns it: encoding a clean 103 second track with it produced 162 sample
jumps above 0.2 where the source had none - audible as crackling roughly twice a second. The
good encoder is libvorbis, which ships decode-only in the embedded python this project encodes
from, but is present and working inside Blender.

So Blender is used as an audio encoder and nothing else. The cutting, the loop search and the
crossfade all happen in make_loop.py, which writes a lossless WAV; this only changes the
container. That split is deliberate - frame-accurate editing through Blender's sequencer is
fiddly and easy to get subtly wrong, and none of it needs to happen here.
"""
import contextlib
import sys
import wave
from pathlib import Path

import bpy


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    source = Path(argv[0]).resolve()
    out = Path(argv[1]).resolve()
    # kb/s. Used to be called "quality", read into a variable, printed, and then not passed to
    # the encoder at all - so every attempt to turn the setting up did nothing but say so.
    bitrate = int(float(argv[2])) if len(argv) > 2 else 160

    if not source.is_file():
        raise SystemExit(f"no such file: {source}")

    # Encoded at the rate it arrived at. This used to be pinned to 48 kHz, which quietly
    # resampled every 44.1 kHz source - and resampling moves every sample, including the two
    # either side of a loop's seam. The join is chosen on a zero crossing precisely so that it
    # is inaudible, and interpolating through it undid that: a seam measured at a fifth of a
    # typical sample step came out of the encoder at one and a third.
    with contextlib.closing(wave.open(str(source), "rb")) as handle:
        mixrate = handle.getframerate()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.sequence_editor_create()
    strip = scene.sequence_editor.sequences.new_sound("track", str(source), 1, 1)
    # Blender mixes down whole frames, so the scene has to end on the sample the sound does or
    # the encode is padded with silence - which would put a gap in the middle of a loop.
    scene.render.fps = 100
    scene.render.fps_base = 1.0
    scene.frame_start = 1
    scene.frame_end = max(1, int(round(strip.frame_final_duration)))
    scene.render.ffmpeg.audio_codec = "VORBIS"

    bpy.ops.sound.mixdown(filepath=str(out), container="OGG", codec="VORBIS",
                          format="S16", mixrate=mixrate, bitrate=bitrate, accuracy=1024,
                          split_channels=False)
    print(f"encoded -> {out} ({out.stat().st_size / 1048576:.2f} MB)"
          if out.exists() else "MIXDOWN PRODUCED NOTHING")
    print(f"{mixrate} Hz, {bitrate} kb/s")


if __name__ == "__main__":
    main()
