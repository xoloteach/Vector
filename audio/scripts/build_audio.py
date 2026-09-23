"""Generates every sound in the game.

    python3 audio/scripts/build_audio.py --out game/assets/audio

All original, all synthesised, all reproducible. See `synth.py` for why this is
generated rather than sourced.

Mix philosophy
--------------
The sounds exist to **reinforce movement timing**, not to fill space. Concretely:

* Footsteps are short, dry and quiet. They are the metronome the player feels the
  gait through, and at any real volume they become the loudest thing in the game.
* Impacts carry the information. A soft landing and a hard landing differ in weight
  and length, not just loudness, so the player can hear a mistake before the HUD or
  the camera shake tell them.
* Traversal sounds are cloth and scuff, deliberately unmusical, so they sit under
  the music without needing to duck it.
* Ambience is wide and quiet. The chase cue is the only sound allowed to become
  attention-grabbing, and it earns that by being the thing that can kill you.

Levels here are only rough; final balance lives in the game's audio director so it
can be tuned in one place.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from synth import (  # noqa: E402
    SAMPLE_RATE,
    concat,
    envelope,
    fade,
    gain,
    highpass,
    loopable,
    lowpass,
    mix,
    moving_lowpass,
    noise,
    normalise,
    reverb,
    saw,
    silence,
    sine,
    soft_clip,
    sweep,
    triangle,
    write_wav,
)

# --------------------------------------------------------------------------
# movement
# --------------------------------------------------------------------------


def footstep(seed: int, brightness: float) -> list[float]:
    """A single footfall on concrete.

    Built from a filtered noise transient plus a very short low thump — the thump is
    what makes it read as body weight landing rather than a hand tap. Variants differ
    in brightness and seed so a run cycle does not sound like a machine.
    """
    transient = envelope(
        highpass(lowpass(noise(0.07, seed), 2600 * brightness), 320),
        attack=0.001,
        decay=0.055,
    )
    body = envelope(sine(0.07, 88.0), attack=0.001, decay=0.06)
    grit = envelope(gain(noise(0.035, seed + 99), 0.5), attack=0.001, decay=0.03)
    out = mix(transient, body, grit, gains=[1.0, 0.55, 0.35])
    return normalise(fade(reverb(out, room=0.2, wet=0.1)), 0.55)


def jump() -> list[float]:
    """Cloth effort plus a rising whoosh: the sound of pushing off."""
    cloth = envelope(
        moving_lowpass(noise(0.16, 11), 900.0, 4200.0), attack=0.004, decay=0.15
    )
    whoosh = envelope(sweep(0.2, 160.0, 420.0, curve=0.6), attack=0.01, decay=0.19)
    thud = envelope(sine(0.09, 120.0), attack=0.001, decay=0.085)
    out = mix(cloth, whoosh, thud, gains=[0.7, 0.3, 0.5])
    return normalise(fade(reverb(out, room=0.25, wet=0.12)), 0.7)


def land_soft() -> list[float]:
    impact = envelope(lowpass(noise(0.12, 21), 1500.0), attack=0.001, decay=0.11)
    body = envelope(sine(0.13, 74.0), attack=0.001, decay=0.12)
    out = mix(impact, body, gains=[0.75, 0.9])
    return normalise(fade(reverb(out, room=0.28, wet=0.16)), 0.68)


def land_hard() -> list[float]:
    """Longer, lower and grittier than a soft landing.

    The difference is deliberately structural rather than just louder: a hard landing
    costs the player most of their speed, and they should be able to hear which kind
    of landing they got without looking at anything.
    """
    impact = envelope(lowpass(noise(0.3, 31), 1100.0), attack=0.001, decay=0.28)
    body = envelope(sweep(0.34, 95.0, 48.0, curve=0.5), attack=0.001, decay=0.33)
    crunch = envelope(highpass(noise(0.1, 32), 900.0), attack=0.001, decay=0.09)
    out = mix(impact, body, crunch, gains=[0.8, 1.0, 0.3])
    return normalise(fade(soft_clip(reverb(out, room=0.4, wet=0.24))), 0.95)


def slide() -> list[float]:
    """Sustained grit with a falling filter, matching the slide's decay in speed."""
    body = moving_lowpass(noise(0.95, 41), 5200.0, 700.0)
    shaped = envelope(body, attack=0.02, decay=0.12, sustain_level=0.75, release=0.5)
    rumble = envelope(
        sine(0.95, 62.0), attack=0.03, decay=0.15, sustain_level=0.5, release=0.5
    )
    out = mix(shaped, rumble, gains=[0.9, 0.3])
    return normalise(fade(reverb(out, room=0.3, wet=0.14), 0.02, 0.1), 0.62)


def vault(high: bool) -> list[float]:
    """Hand or foot on metal, plus cloth. The high vault gets a harder plant."""
    plant = envelope(
        highpass(lowpass(noise(0.1, 51 if high else 52), 3800.0), 600.0),
        attack=0.001,
        decay=0.09,
    )
    ring = envelope(
        triangle(0.16, 430.0 if high else 620.0), attack=0.002, decay=0.15
    )
    cloth = envelope(moving_lowpass(noise(0.18, 53), 1200.0, 3600.0), 0.005, 0.17)
    out = mix(plant, ring, cloth, gains=[0.9, 0.22 if high else 0.14, 0.5])
    return normalise(fade(reverb(out, room=0.24, wet=0.12)), 0.72)


def roll() -> list[float]:
    """Three quick body contacts, because a roll is not one impact."""
    parts = []
    for index, seed in enumerate((61, 62, 63)):
        hit = envelope(lowpass(noise(0.1, seed), 1300.0 - index * 180.0), 0.001, 0.09)
        low = envelope(sine(0.1, 80.0 - index * 8.0), 0.001, 0.095)
        parts.append(mix(hit, low, gains=[0.7, 0.8]))
        parts.append(silence(0.055))
    out = concat(*parts)
    return normalise(fade(reverb(out, room=0.32, wet=0.18)), 0.8)


def wall_scuff() -> list[float]:
    body = envelope(moving_lowpass(noise(0.3, 71), 4200.0, 1100.0), 0.004, 0.28)
    scrape = envelope(highpass(noise(0.3, 72), 1800.0), 0.01, 0.28)
    out = mix(body, scrape, gains=[0.85, 0.4])
    return normalise(fade(reverb(out, room=0.3, wet=0.15)), 0.62)


def ledge_grab() -> list[float]:
    """A sharp catch: hands arresting a fall."""
    grab = envelope(highpass(lowpass(noise(0.09, 81), 4000.0), 900.0), 0.001, 0.085)
    creak = envelope(sine(0.14, 190.0), 0.003, 0.13)
    out = mix(grab, creak, gains=[0.9, 0.25])
    return normalise(fade(reverb(out, room=0.22, wet=0.12)), 0.7)


def death() -> list[float]:
    """Falling pitch into a dull impact. Reads as failure without being a jump-scare."""
    descent = envelope(sweep(0.55, 340.0, 60.0, curve=1.4), 0.01, 0.5)
    hit = concat(silence(0.5), envelope(lowpass(noise(0.35, 91), 800.0), 0.001, 0.34))
    low = concat(silence(0.5), envelope(sine(0.4, 52.0), 0.002, 0.38))
    out = mix(descent, hit, low, gains=[0.4, 0.85, 0.9])
    return normalise(fade(soft_clip(reverb(out, room=0.5, wet=0.3))), 0.9)


def finish() -> list[float]:
    """A short rising three-note figure. The only unambiguously positive sound."""
    parts = []
    for index, freq in enumerate((392.0, 523.25, 659.25)):
        tone = mix(
            envelope(sine(0.3, freq), 0.005, 0.28),
            envelope(triangle(0.3, freq * 2.0), 0.005, 0.2),
            gains=[0.8, 0.18],
        )
        parts.append(tone if index < 2 else envelope(sine(0.6, freq), 0.005, 0.55))
        if index < 2:
            parts.append(silence(0.02))
    out = concat(*parts)
    return normalise(fade(reverb(out, room=0.45, wet=0.3)), 0.8)


# --------------------------------------------------------------------------
# the pursuer
# --------------------------------------------------------------------------


def drone_hum() -> list[float]:
    """Seamless rotor loop.

    Two detuned saws plus a beating amplitude modulation. The beat is what makes it
    sound like rotors rather than a tone, and it is the cue the player tracks without
    looking.
    """
    length = 2.4
    base = mix(
        lowpass(saw(length, 116.0), 1400.0),
        lowpass(saw(length, 119.5), 1200.0),
        lowpass(saw(length, 58.0), 700.0),
        gains=[0.5, 0.42, 0.55],
    )
    blade = sine(length, 27.0)
    modulated = [s * (0.72 + 0.28 * b) for s, b in zip(base, blade)]
    air = gain(highpass(noise(length, 101), 2200.0), 0.1)
    out = mix(modulated, air, gains=[1.0, 0.5])
    return normalise(loopable(out, 0.3), 0.5)


def drone_alert() -> list[float]:
    """Two-tone rising alarm, for when the pursuer closes into the danger band."""
    parts = []
    for freq in (520.0, 700.0):
        tone = mix(
            envelope(sine(0.18, freq), 0.006, 0.16),
            envelope(saw(0.18, freq * 0.5), 0.006, 0.16),
            gains=[0.8, 0.2],
        )
        parts.append(lowpass(tone, 2600.0))
        parts.append(silence(0.035))
    out = concat(*parts)
    return normalise(fade(reverb(out, room=0.3, wet=0.2)), 0.72)


# --------------------------------------------------------------------------
# ambience and music
# --------------------------------------------------------------------------


def wind() -> list[float]:
    """Rooftop wind: slowly swelling filtered noise, wide and quiet."""
    length = 6.0
    base = noise(length, 111)
    filtered = lowpass(highpass(base, 180.0), 1500.0)
    # Two slow swells at incommensurate rates, so the loop never sounds periodic.
    out = []
    for i, sample in enumerate(filtered):
        t = i / SAMPLE_RATE
        swell = 0.5 + 0.28 * (
            0.6 * __import__("math").sin(t * 0.52) + 0.4 * __import__("math").sin(t * 0.19)
        )
        out.append(sample * swell)
    return normalise(loopable(out, 0.9), 0.42)


def city() -> list[float]:
    """Distant city: low rumble with sparse traffic-like swells."""
    length = 8.0
    rumble = lowpass(noise(length, 121), 260.0)
    mid = gain(lowpass(highpass(noise(length, 122), 300.0), 900.0), 0.3)
    out = mix(rumble, mid, gains=[1.0, 0.5])
    return normalise(loopable(out, 1.0), 0.34)


def music_loop() -> list[float]:
    """A dark, sparse loop meant to be barely noticed.

    D minor at 104 BPM. A pulsing root, a slow pad, and an off-beat tick. There is no
    melody on purpose: a tune competes with the movement sounds the player is actually
    steering by, and this has to survive being heard a hundred times per session.
    """
    import math as _math

    bpm = 104.0
    beat = 60.0 / bpm
    bars = 4
    length = beat * 4 * bars

    # --- bass pulse: root on every beat, dropping a fifth in the last bar -------
    bass_parts: list[list[float]] = []
    roots = [73.42] * 12 + [55.0] * 4  # D2 ... G1
    for step in range(16):
        freq = roots[step]
        note = mix(
            envelope(sine(beat, freq), 0.006, beat * 0.55),
            envelope(saw(beat, freq * 0.5), 0.008, beat * 0.4),
            gains=[0.85, 0.2],
        )
        bass_parts.append(lowpass(note, 420.0))
    bass = concat(*bass_parts)

    # --- pad: sustained minor triad, slowly filtered -------------------------
    pad_layers = [
        lowpass(saw(length, freq), 900.0)
        for freq in (146.83, 174.61, 220.0)  # D3 F3 A3
    ]
    pad = mix(*pad_layers, gains=[0.4, 0.34, 0.3])
    pad = moving_lowpass(pad, 700.0, 1500.0)
    pad_env = []
    for i, sample in enumerate(pad):
        t = i / SAMPLE_RATE
        swell = 0.45 + 0.3 * _math.sin(t * 0.34 * _math.tau / 2.0)
        pad_env.append(sample * swell)

    # --- tick: a dry off-beat accent that carries the pulse -------------------
    tick_parts: list[list[float]] = []
    for step in range(16):
        if step % 4 == 2:
            hit = envelope(highpass(noise(0.05, 130 + step), 3200.0), 0.001, 0.045)
            tick_parts.append(gain(hit, 0.28))
            tick_parts.append(silence(beat - 0.05))
        else:
            tick_parts.append(silence(beat))
    tick = concat(*tick_parts)

    out = mix(bass, pad_env, tick, gains=[0.55, 0.5, 0.7])
    out = reverb(out, room=0.5, wet=0.22)
    return normalise(loopable(out, 0.5), 0.6)


# --------------------------------------------------------------------------
# UI
# --------------------------------------------------------------------------


def ui_click() -> list[float]:
    out = mix(
        envelope(sine(0.05, 880.0), 0.001, 0.045),
        envelope(highpass(noise(0.03, 141), 3000.0), 0.001, 0.028),
        gains=[0.7, 0.2],
    )
    return normalise(fade(out), 0.45)


def ui_confirm() -> list[float]:
    parts = [
        envelope(sine(0.09, 587.33), 0.003, 0.08),
        envelope(sine(0.16, 880.0), 0.003, 0.15),
    ]
    out = concat(parts[0], parts[1])
    return normalise(fade(reverb(out, room=0.25, wet=0.15)), 0.55)


# --------------------------------------------------------------------------

SOUNDS = {
    # movement
    "footstep_01": lambda: footstep(1, 1.0),
    "footstep_02": lambda: footstep(2, 0.86),
    "footstep_03": lambda: footstep(3, 1.12),
    "footstep_04": lambda: footstep(4, 0.94),
    "jump": jump,
    "land_soft": land_soft,
    "land_hard": land_hard,
    "slide": slide,
    "vault_low": lambda: vault(False),
    "vault_high": lambda: vault(True),
    "roll": roll,
    "wall_scuff": wall_scuff,
    "ledge_grab": ledge_grab,
    # outcomes
    "death": death,
    "finish": finish,
    # pursuer
    "drone_hum": drone_hum,
    "drone_alert": drone_alert,
    # ambience
    "amb_wind": wind,
    "amb_city": city,
    # music
    "music_pursuit": music_loop,
    # ui
    "ui_click": ui_click,
    "ui_confirm": ui_confirm,
}

## Only music gets a stereo image. Ambience is wide by nature and mono halves it;
## everything else is placed by the game, and a baked stereo image would fight that.
STEREO = {"music_pursuit"}

## Written at a reduced sample rate. All of these are low-bandwidth by construction —
## filtered noise, pads and a rotor hum — so the top octaves carry nothing. This is
## the size lever available here: the bundled ffmpeg has no Vorbis encoder, so the
## long files cannot simply be compressed.
REDUCED_RATE = {
    "amb_wind": 4,
    "amb_city": 4,
    "drone_hum": 2,
    "music_pursuit": 2,
}


def parse_out_dir(default: str) -> str:
    argv = sys.argv[1:]
    for i, arg in enumerate(argv):
        if arg == "--out" and i + 1 < len(argv):
            return argv[i + 1]
    return default


def to_ogg(wav_path: str, quality: int = 3) -> str | None:
    """Re-encodes a WAV as Ogg Vorbis and removes the WAV.

    Applied only to the long looping files. Uncompressed, the three ambience and
    music loops came to 1.75 MB of the 2.1 MB total — most of the audio budget spent
    on the three quietest things in the mix. Vorbis takes that to around a tenth,
    with no audible cost on material that is mostly filtered noise and pads.
    Short effects stay as WAV: they need to start instantly and are already tiny,
    and decoding overhead on a one-shot is not worth trading for a few kilobytes.
    """
    import shutil
    import subprocess

    if shutil.which("ffmpeg") is None:
        return None
    ogg_path = wav_path[:-4] + ".ogg"
    result = subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error",
            "-i", wav_path,
            "-c:a", "libvorbis", "-q:a", str(quality),
            ogg_path,
        ],
        capture_output=True,
    )
    if result.returncode != 0 or not os.path.exists(ogg_path):
        print(f"[build_audio] ogg encode failed for {os.path.basename(wav_path)}")
        return None
    os.remove(wav_path)
    return ogg_path


def main() -> None:
    out_dir = os.path.abspath(parse_out_dir("game/assets/audio"))
    print(f"[build_audio] output -> {out_dir}")
    print(f"[build_audio] sample rate {SAMPLE_RATE} Hz")

    total = 0
    for name, factory in SOUNDS.items():
        signal = factory()
        spread = 14.0 if name in STEREO else 0.0
        divisor = REDUCED_RATE.get(name, 1)
        path = os.path.join(out_dir, f"{name}.wav")
        size = write_wav(path, signal, stereo_spread=spread, rate_divisor=divisor)
        seconds = len(signal) / SAMPLE_RATE

        # Vorbis when the toolchain has it; source reduction is the fallback and is
        # what this environment actually uses.
        suffix = f"wav {SAMPLE_RATE // divisor // 1000}k"
        if name in STEREO:
            ogg = to_ogg(path)
            if ogg is not None:
                size = os.path.getsize(ogg)
                suffix = "ogg"

        total += size
        print(f"[build_audio] {name:<16} {seconds:5.2f}s  {size / 1024:7.1f} KiB  {suffix}")

    print(f"[build_audio] {len(SOUNDS)} files, {total / 1024:.1f} KiB total")
    print("BUILD_AUDIO: DONE")


if __name__ == "__main__":
    main()
