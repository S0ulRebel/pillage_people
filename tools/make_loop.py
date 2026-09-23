r"""Cut a generated music track into a seamless loop and encode it for the game.

    python make_loop.py "Sun-Faded Island.wav" --out theme.ogg --min 45

Suno and the rest write songs, not loops: an intro that only happens once, a fade at the end,
and no guarantee the last bar leads back into the first. Played on repeat in a game that is a
gap, a lurch, or both, every couple of minutes.

So this finds the pair of points that actually join. It looks for a start after any intro and
an end far enough past it, and scores every candidate by how closely the audio around the two
matches - sample differences for the shape of the waveform, plus a coarse spectrum comparison
so two passages that merely share a volume are not mistaken for the same music. The best pair
is then nudged onto a shared zero crossing, because splicing mid-wave puts a click on every
repeat that no amount of matching will hide.

A short crossfade covers what is left. It is deliberately brief - long fades blur the downbeat
and make the seam audible as a swell rather than a join.

The loop is checked rather than assumed: the discontinuity at the splice is reported against
the discontinuity of an average frame in the same track, so "seamless" is a measurement.
"""
import argparse
import contextlib
import wave
from fractions import Fraction
from pathlib import Path

import av
import numpy as np


def read_wav(path):
    """Samples as (frame, channel), in -1..1. Any format av can open, not only WAV.

    It started WAV-only because the source was always a Suno export. The generated ambience
    arrives as FLAC, and converting it first only to convert it back was a step that existed
    to satisfy the reader rather than the work.
    """
    suffix = Path(path).suffix.lower()
    if suffix == ".wav":
        with contextlib.closing(wave.open(str(path), "rb")) as handle:
            if handle.getsampwidth() == 2:
                rate = handle.getframerate()
                channels = handle.getnchannels()
                raw = handle.readframes(handle.getnframes())
                return (np.frombuffer(raw, dtype="<i2").reshape(-1, channels)
                        .astype(np.float32) / 32768.0), rate
    with av.open(str(path)) as container:
        rate = container.streams.audio[0].codec_context.rate
        frames = [f.to_ndarray() for f in container.decode(audio=0)]
    if not frames:
        raise SystemExit(f"no audio in {path}")
    samples = np.concatenate(frames, axis=1).astype(np.float32)
    if np.abs(samples).max() > 2.0:
        samples = samples / 32768.0
    return np.ascontiguousarray(samples.T), rate


def envelope(mono, rate, bucket=0.05):
    step = max(1, int(rate * bucket))
    usable = len(mono) - len(mono) % step
    return np.sqrt((mono[:usable].reshape(-1, step) ** 2).mean(axis=1)), step


def spectrum(block):
    """A coarse picture of the tone, so two passages are not matched on loudness alone."""
    windowed = block * np.hanning(len(block))
    magnitude = np.abs(np.fft.rfft(windowed))
    bands = np.array_split(magnitude[:len(magnitude) // 2], 24)
    energy = np.array([b.mean() for b in bands])
    return energy / (np.linalg.norm(energy) + 1e-9)


def zero_crossing(mono, index, search):
    """Nearest point where the waveform crosses zero going the same way it does at index."""
    best = index
    for offset in range(search):
        for candidate in (index + offset, index - offset):
            if candidate <= 0 or candidate >= len(mono) - 1:
                continue
            if mono[candidate - 1] <= 0.0 < mono[candidate]:
                return candidate
    return best


def find_loop(samples, rate, min_seconds, fade_seconds, say=print):
    """The best seamless loop in this audio, and how good the join is.

    Returns (body, detail) where body is the looping audio and detail carries the seam
    measurement, so a caller comparing several takes can rank them by how well each one
    actually joins rather than by how it looks on paper.
    """
    mono = samples.mean(axis=1)
    level, step = envelope(mono, rate)
    loud = float(np.percentile(level, 60))
    # Where the track stops being the track: a tail that never comes back above a fraction of
    # its own typical level is a fade-out, and looping into it drops the floor out.
    tail = len(level)
    while tail > 1 and level[tail - 1] < loud * 0.35:
        tail -= 1
    # And the mirror of that at the front, for an intro that begins from nothing.
    head = 0
    while head < len(level) - 1 and level[head] < loud * 0.35:
        head += 1
    body_start, body_end = head * step, tail * step
    say(f"  usable body {body_start / rate:.1f}s to {body_end / rate:.1f}s "
        f"(trimmed {body_start / rate:.1f}s of intro, "
        f"{(len(mono) - body_end) / rate:.1f}s of tail)")

    window = int(rate * 0.5)
    if body_end - body_start < window * 4 + int(min_seconds * rate):
        raise SystemExit("not enough usable audio for a loop that long; lower --min")

    # Every candidate end point is scored against every candidate start, but there are only as
    # many distinct end points as there are positions - so their spectra are computed once here
    # rather than once per pair. Recomputing them inside the loop meant ninety-odd thousand
    # transforms where twelve hundred do, and turned a two minute wait into a two second one.
    ends = list(range(body_start, body_end - window, step * 2))
    end_blocks = np.stack([mono[e:e + window] for e in ends])
    end_tones = np.stack([spectrum(block) for block in end_blocks])

    starts = range(body_start, body_start + int(rate * 8), step * 2)
    best = None
    for start in starts:
        reference = mono[start:start + window]
        reference_tone = spectrum(reference)
        earliest = start + int(min_seconds * rate)
        usable = np.searchsorted(ends, earliest)
        if usable >= len(ends):
            continue
        shape = ((end_blocks[usable:] - reference) ** 2).mean(axis=1)
        tone = ((end_tones[usable:] - reference_tone) ** 2).mean(axis=1)
        scores = shape + tone * 0.5
        pick = int(np.argmin(scores))
        if best is None or scores[pick] < best[0]:
            best = (float(scores[pick]), start, ends[usable + pick])
    if best is None:
        raise SystemExit("not enough usable audio for a loop that long; lower --min")
    _, start, end = best

    start = zero_crossing(mono, start, int(rate * 0.02))
    end = zero_crossing(mono, end, int(rate * 0.02))
    length = (end - start) / rate
    say(f"  loop {start / rate:.2f}s -> {end / rate:.2f}s  ({length:.1f}s)")

    fade = int(rate * fade_seconds)
    body = samples[start:end].copy()
    incoming = samples[end:end + fade]
    if len(incoming) == fade and fade > 0:
        ramp = np.linspace(0.0, 1.0, fade, dtype=np.float32)[:, None]
        body[:fade] = body[:fade] * ramp + incoming * (1.0 - ramp)

    seam = float(np.abs(body[0] - body[-1]).mean())
    typical = float(np.abs(np.diff(body[:, 0])).mean())
    ratio = seam / max(typical, 1e-9)
    say(f"  seam step {seam:.5f} against a typical sample step of {typical:.5f} "
        f"({ratio:.1f}x)")
    return body, {"seam": seam, "typical": typical, "ratio": ratio, "length": length,
                  "start": start / rate, "end": end / rate}


def write_ogg(out, body, rate, bitrate=160):
    """Writes the loop. Despite the name it honours a .wav suffix, for the case below."""
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    planar = np.ascontiguousarray((body.T * 32767.0).astype(np.int16))

    if out.suffix.lower() == ".wav":
        # Lossless out, for something else to encode. Worth having its own path: ffmpeg's
        # native vorbis encoder is experimental and it shows - it put 162 sample jumps above
        # 0.2 into a track whose source had none, which is audible as crackling about twice a
        # second. Blender ships a real libvorbis; convert this with tools/encode_ogg.py.
        with contextlib.closing(wave.open(str(out), "wb")) as handle:
            handle.setnchannels(body.shape[1])
            handle.setsampwidth(2)
            handle.setframerate(rate)
            handle.writeframes(np.ascontiguousarray(planar.T).tobytes())
    else:
        # libvorbis is the better encoder but ships decode-only in some builds, including the one
        # in ComfyUI's embedded python. ffmpeg's own vorbis encoder is the fallback: it wants
        # strict -2 because it is still marked experimental, and Godot cannot tell which made the
        # file - both produce ordinary OGG Vorbis.
        encoder = "libvorbis"
        try:
            av.Codec("libvorbis", "w")
        except Exception:
            encoder = "vorbis"
        with av.open(str(out), "w") as container:
            stream = container.add_stream(encoder, rate=rate,
                                          options={"strict": "-2"} if encoder == "vorbis" else {})
            stream.layout = "stereo" if body.shape[1] == 2 else "mono"
            stream.bit_rate = int(bitrate * 1000)
            # Fed in ordinary frames, not one enormous one. Handing the encoder every sample in a
            # single frame produced a playable file whose Ogg granule positions were nonsense:
            # ffmpeg could still decode it by reading every packet, and reported the right 103s,
            # while Godot read the container's own duration and believed it was 6.5s long.
            planar = np.ascontiguousarray((body.T * 32767.0).astype(np.int16))
            chunk = 4096
            pts = 0
            for offset in range(0, planar.shape[1], chunk):
                piece = np.ascontiguousarray(planar[:, offset:offset + chunk])
                frame = av.AudioFrame.from_ndarray(piece.reshape(1, -1), format="s16",
                                                   layout=stream.layout)
                frame.sample_rate = rate
                frame.pts = pts
                frame.time_base = Fraction(1, rate)
                pts += piece.shape[1]
                for packet in stream.encode(frame):
                    container.mux(packet)
            for packet in stream.encode(None):
                container.mux(packet)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("--out", required=True, help="written as .ogg")
    ap.add_argument("--min", type=float, default=40.0, help="shortest acceptable loop, seconds")
    ap.add_argument("--fade", type=float, default=0.12, help="crossfade at the seam, seconds")
    ap.add_argument("--bitrate", type=int, default=160, help="kbps")
    args = ap.parse_args()

    source = Path(args.source)
    samples, rate = read_wav(source)
    print(f"{source.name}: {len(samples) / rate:.1f}s, {rate} Hz, {samples.shape[1]} ch")
    body, _ = find_loop(samples, rate, args.min, args.fade)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    write_ogg(out, body, rate, args.bitrate)
    print(f"  -> {out}  ({out.stat().st_size / 1048576:.2f} MB, was "
          f"{source.stat().st_size / 1048576:.1f} MB)")


if __name__ == "__main__":
    main()
