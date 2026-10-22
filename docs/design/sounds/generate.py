#!/usr/bin/env python3
"""Original ChessMe Walnut sound set. Python standard library only.

No reference recordings are read, sampled, stretched or transformed.
Run from any directory. Output is mono 48 kHz, 16-bit PCM.
"""

import array
import base64
import json
import math
from pathlib import Path
import random
import wave

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "ios/ChessMe/Sounds"
RATE = 48_000


def impact(duration=0.16, pitch=1.0, weight=1.0, seed=11):
    rng = random.Random(seed)
    out = []
    smooth = 0.0
    # Inharmonic damped modes model a small wooden piece on a felted board.
    modes = [(386, 1.0, .013), (691, .52, .009), (1187, .21, .006), (2081, .09, .003)]
    for i in range(round(duration * RATE)):
        t = i / RATE
        attack = 1 - math.exp(-t / .0007)
        body = sum(amp * math.sin(2 * math.pi * hz * pitch * t) * math.exp(-t / decay)
                   for hz, amp, decay in modes)
        smooth += .24 * (rng.uniform(-1, 1) - smooth)
        contact = smooth * .55 * math.exp(-t / .0045)
        felt = .14 * math.sin(2 * math.pi * 173 * pitch * t) * math.exp(-t / .019)
        out.append(weight * attack * (body + contact + felt))
    return out


def add(base, layer, delay=0, gain=1):
    offset = round(delay * RATE)
    if len(base) < offset + len(layer):
        base += [0.0] * (offset + len(layer) - len(base))
    for i, value in enumerate(layer):
        base[offset + i] += gain * value
    return base


def capture(pitch=1, seed=40):
    # A light contact then a heavier landing, perceived as one compact action.
    out = impact(.18, pitch * 1.19, .36, seed)
    add(out, impact(.18, pitch * .82, .88, seed + 1), .014)
    return out


def check_accent():
    out = []
    for i in range(round(.23 * RATE)):
        t = i / RATE
        envelope = (1 - math.exp(-t / .003)) * math.exp(-t / .034)
        # A muted harmonic fifth. Short enough to remain a board cue.
        out.append(envelope * (.29 * math.sin(2 * math.pi * 784 * t)
                               + .105 * math.sin(2 * math.pi * 1176 * t)
                               + .028 * math.sin(2 * math.pi * 2352 * t)))
    return out


def finish(values, gain):
    values = [math.tanh(v * .82) * gain for v in values]
    # Remove DC and taper both boundaries to avoid playback clicks.
    mean = sum(values) / len(values)
    values = [v - mean for v in values]
    fade = round(.004 * RATE)
    for i in range(fade):
        values[-1 - i] *= i / fade
    values[0] = values[-1] = 0
    return values


def write(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = array.array("h", (round(max(-1, min(1, v)) * 32767) for v in values))
    import sys
    if sys.byteorder != "little":
        pcm.byteswap()
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(pcm.tobytes())


def main():
    sounds = {}
    for i, pitch in enumerate([1.0, .975, 1.025], 1):
        sounds[f"walnut-move-{i}"] = finish(impact(pitch=pitch, seed=10+i), .48)
    for i, pitch in enumerate([1.0, .975], 1):
        sounds[f"walnut-capture-{i}"] = finish(capture(pitch, seed=40+i), .52)
    sounds["walnut-check"] = finish(add(impact(), check_accent(), .018), .48)
    sounds["walnut-capture-check"] = finish(add(capture(), check_accent(), .022), .52)
    manifest = {}
    for name, values in sounds.items():
        write(OUTPUT / (name + ".wav"), values)
        manifest[name] = {"duration": round(len(values) / RATE, 3),
                          "peakDBFS": round(20 * math.log10(max(map(abs, values))), 2)}

    # Review reel: three moves, two captures, check, capture with check,
    # then a short mixed sequence at ordinary playing speed.
    reel = [0.0] * round(.35 * RATE)
    cue_order = ["move-1", "move-2", "move-3", "capture-1", "capture-2", "check", "capture-check"]
    for name in cue_order:
        reel += sounds["walnut-" + name] + [0.0] * round(.52 * RATE)
    reel += [0.0] * round(.45 * RATE)
    for name in ["move-1", "move-2", "capture-1", "move-3", "check"]:
        reel += sounds["walnut-" + name] + [0.0] * round(.32 * RATE)
    write(Path(__file__).parent / "walnut-preview.wav", reel)
    (Path(__file__).parent / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    template = (Path(__file__).parent / "player.template.html").read_text()
    encoded = {name.removeprefix("walnut-"): base64.b64encode((OUTPUT / (name + ".wav")).read_bytes()).decode()
               for name in sounds}
    (Path(__file__).parent / "walnut-player.html").write_text(template.replace("__AUDIO_DATA__", json.dumps(encoded)))
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
