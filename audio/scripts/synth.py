"""A tiny software synthesiser, standard library only.

Why synthesise rather than download CC0 samples
-----------------------------------------------
Four reasons, and the licensing one is not even the strongest:

1. **It matches the project.** Every other asset here is generated from a script.
   A folder of downloaded WAVs would be the one part of the game nobody could
   regenerate or adjust.
2. **Tuning.** A footstep can be made to sit exactly under the gait, and the drone
   hum can be pitched to not fight the music, because both are a few numbers in a
   file rather than fixed recordings.
3. **Size.** The whole soundtrack and effect set comes to a few hundred kilobytes
   of mono 22 kHz WAV. This is a browser game where the WASM is already 39 MB.
4. **Licensing is simply not a question.** Original output, no attribution chain to
   track, nothing to get wrong.

No numpy: `array` and `math` are enough at these lengths, and a dependency-free
script is one that still runs in two years.

Everything works on plain Python lists of floats in -1..1, converted to 16-bit PCM
only at write time.
"""

from __future__ import annotations

import array
import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
"""22.05 kHz. Half the size of 44.1 for no audible loss on short, mostly
low-bandwidth effects — and this is a browser game."""


# ---------------------------------------------------------------------------
# generators
# ---------------------------------------------------------------------------


def silence(duration: float) -> list[float]:
    return [0.0] * int(duration * SAMPLE_RATE)


def noise(duration: float, seed: int | None = None) -> list[float]:
    rng = random.Random(seed)
    return [rng.uniform(-1.0, 1.0) for _ in range(int(duration * SAMPLE_RATE))]


def sine(duration: float, freq: float, phase: float = 0.0) -> list[float]:
    n = int(duration * SAMPLE_RATE)
    step = 2.0 * math.pi * freq / SAMPLE_RATE
    return [math.sin(phase + step * i) for i in range(n)]


def saw(duration: float, freq: float) -> list[float]:
    n = int(duration * SAMPLE_RATE)
    period = SAMPLE_RATE / freq
    return [2.0 * ((i % period) / period) - 1.0 for i in range(n)]


def triangle(duration: float, freq: float) -> list[float]:
    n = int(duration * SAMPLE_RATE)
    period = SAMPLE_RATE / freq
    out = []
    for i in range(n):
        t = (i % period) / period
        out.append(4.0 * abs(t - 0.5) - 1.0)
    return out


def sweep(
    duration: float,
    start_freq: float,
    end_freq: float,
    curve: float = 1.0,
    wave_fn=math.sin,
) -> list[float]:
    """A frequency sweep. `curve` below 1.0 front-loads the movement."""
    n = int(duration * SAMPLE_RATE)
    out = []
    phase = 0.0
    for i in range(n):
        t = (i / max(1, n - 1)) ** curve
        freq = start_freq + (end_freq - start_freq) * t
        phase += 2.0 * math.pi * freq / SAMPLE_RATE
        out.append(wave_fn(phase))
    return out


# ---------------------------------------------------------------------------
# envelopes and shaping
# ---------------------------------------------------------------------------


def envelope(
    signal: list[float],
    attack: float,
    decay: float,
    sustain_level: float = 0.0,
    release: float = 0.0,
) -> list[float]:
    """Applies an AD(S)R contour in seconds."""
    n = len(signal)
    a = max(1, int(attack * SAMPLE_RATE))
    d = max(1, int(decay * SAMPLE_RATE))
    r = int(release * SAMPLE_RATE)
    s = max(0, n - a - d - r)

    out = []
    for i in range(n):
        if i < a:
            gain = i / a
        elif i < a + d:
            t = (i - a) / d
            gain = 1.0 - (1.0 - sustain_level) * t
        elif i < a + d + s:
            gain = sustain_level
        elif r > 0:
            t = (i - a - d - s) / r
            gain = sustain_level * (1.0 - t)
        else:
            gain = 0.0
        out.append(signal[i] * gain)
    return out


def fade(signal: list[float], attack: float = 0.005, release: float = 0.02) -> list[float]:
    """Short fades at both ends. Prevents the click that any non-zero start or end
    sample produces — the single most common flaw in synthesised effects."""
    n = len(signal)
    a = max(1, int(attack * SAMPLE_RATE))
    r = max(1, int(release * SAMPLE_RATE))
    out = list(signal)
    for i in range(min(a, n)):
        out[i] *= i / a
    for i in range(min(r, n)):
        out[n - 1 - i] *= i / r
    return out


def lowpass(signal: list[float], cutoff: float, resonance: float = 0.0) -> list[float]:
    """Two-pole lowpass. Enough character for percussive material without the cost
    or complexity of a proper ladder filter."""
    dt = 1.0 / SAMPLE_RATE
    rc = 1.0 / (2.0 * math.pi * max(20.0, cutoff))
    alpha = dt / (rc + dt)
    out = []
    y1 = 0.0
    y2 = 0.0
    for x in signal:
        y1 += alpha * (x - y1 + resonance * (y1 - y2))
        y2 += alpha * (y1 - y2)
        out.append(y2)
    return out


def highpass(signal: list[float], cutoff: float) -> list[float]:
    dt = 1.0 / SAMPLE_RATE
    rc = 1.0 / (2.0 * math.pi * max(20.0, cutoff))
    alpha = rc / (rc + dt)
    out = []
    prev_x = 0.0
    prev_y = 0.0
    for x in signal:
        y = alpha * (prev_y + x - prev_x)
        out.append(y)
        prev_x = x
        prev_y = y
    return out


def moving_lowpass(
    signal: list[float], start_cutoff: float, end_cutoff: float
) -> list[float]:
    """Lowpass with a cutoff that travels. This is what makes a slide sound like a
    slide — a static filter on noise is just noise."""
    n = len(signal)
    out = []
    y = 0.0
    dt = 1.0 / SAMPLE_RATE
    for i, x in enumerate(signal):
        t = i / max(1, n - 1)
        cutoff = start_cutoff + (end_cutoff - start_cutoff) * t
        rc = 1.0 / (2.0 * math.pi * max(20.0, cutoff))
        alpha = dt / (rc + dt)
        y += alpha * (x - y)
        out.append(y)
    return out


# ---------------------------------------------------------------------------
# mixing
# ---------------------------------------------------------------------------


def mix(*layers: list[float], gains: list[float] | None = None) -> list[float]:
    length = max((len(layer) for layer in layers), default=0)
    out = [0.0] * length
    for index, layer in enumerate(layers):
        gain = gains[index] if gains and index < len(gains) else 1.0
        for i, value in enumerate(layer):
            out[i] += value * gain
    return out


def concat(*parts: list[float]) -> list[float]:
    out: list[float] = []
    for part in parts:
        out.extend(part)
    return out


def gain(signal: list[float], amount: float) -> list[float]:
    return [s * amount for s in signal]


def normalise(signal: list[float], peak: float = 0.92) -> list[float]:
    """Scales to a target peak. Levels are then set once, in the game's audio
    director, rather than being baked unevenly into each file — which is what makes
    a synthesised set easy to balance."""
    highest = max((abs(s) for s in signal), default=0.0)
    if highest < 1e-9:
        return signal
    factor = peak / highest
    return [s * factor for s in signal]


def soft_clip(signal: list[float]) -> list[float]:
    """Gentle saturation. Adds a little warmth and guarantees nothing exceeds
    full scale after mixing."""
    return [math.tanh(s * 1.3) / math.tanh(1.3) for s in signal]


def reverb(signal: list[float], room: float = 0.35, wet: float = 0.25) -> list[float]:
    """A small Schroeder-style reverb: three comb filters into two allpasses.

    Crude by studio standards, but it is what places a footstep on a rooftop instead
    of in a vacuum, and rooftop space is most of this game's atmosphere.
    """
    out = list(signal)

    for delay_ms, feedback in ((29.0, 0.78), (37.0, 0.74), (43.0, 0.70)):
        delay = int(delay_ms * 0.001 * SAMPLE_RATE)
        buf = [0.0] * delay
        pos = 0
        for i in range(len(out)):
            delayed = buf[pos]
            buf[pos] = out[i] + delayed * feedback * room
            out[i] += delayed * wet
            pos = (pos + 1) % delay

    for delay_ms in (5.0, 1.7):
        delay = int(delay_ms * 0.001 * SAMPLE_RATE)
        buf = [0.0] * delay
        pos = 0
        for i in range(len(out)):
            delayed = buf[pos]
            value = out[i] + delayed * -0.6
            buf[pos] = value
            out[i] = delayed + value * 0.6
            pos = (pos + 1) % delay

    return out


def loopable(signal: list[float], crossfade: float = 0.25) -> list[float]:
    """Crossfades the tail over the head so the file loops without a seam.

    Necessary for ambience and music: an audible click every few seconds is far more
    noticeable than anything else in the mix.
    """
    n = len(signal)
    fade_samples = min(int(crossfade * SAMPLE_RATE), n // 3)
    out = signal[: n - fade_samples]
    for i in range(fade_samples):
        t = i / fade_samples
        tail = signal[n - fade_samples + i]
        head = out[i] if i < len(out) else 0.0
        out[i] = head * t + tail * (1.0 - t)
    return out


# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------


def decimate(signal: list[float], factor: int) -> list[float]:
    """Halves (or quarters) the sample rate by averaging neighbours.

    Used for ambience. Wind and city rumble are filtered noise with nothing above a
    couple of kHz, so a lower rate is inaudible and the file shrinks proportionally.
    This exists because the bundled ffmpeg in this environment has no Vorbis encoder,
    so source reduction is the available lever rather than compression.

    Averaging rather than dropping samples: plain decimation aliases, and on noise
    that aliasing is audible as a metallic edge.
    """
    if factor <= 1:
        return signal
    out = []
    for i in range(0, len(signal) - factor + 1, factor):
        out.append(sum(signal[i : i + factor]) / factor)
    return out


def write_wav(
    path: str,
    signal: list[float],
    stereo_spread: float = 0.0,
    rate_divisor: int = 1,
) -> int:
    """Writes 16-bit PCM.

    `stereo_spread` above zero produces a wide stereo file by delaying and
    attenuating one side; used only for music. `rate_divisor` writes at a fraction of
    the project sample rate, for material with no high-frequency content.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if rate_divisor > 1:
        signal = decimate(signal, rate_divisor)
    clipped = [max(-1.0, min(1.0, s)) for s in signal]

    if stereo_spread <= 0.0:
        data = array.array("h", (int(s * 32767) for s in clipped))
        channels = 1
        payload = data.tobytes()
    else:
        offset = int(stereo_spread * 0.001 * SAMPLE_RATE)
        frames = bytearray()
        for i, left in enumerate(clipped):
            right = clipped[i - offset] if i >= offset else 0.0
            frames += struct.pack("<hh", int(left * 32767), int(right * 0.94 * 32767))
        channels = 2
        payload = bytes(frames)

    with wave.open(path, "wb") as handle:
        handle.setnchannels(channels)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE // max(1, rate_divisor))
        handle.writeframes(payload)

    return os.path.getsize(path)
