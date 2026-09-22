#!/usr/bin/env python3
"""Measures the value structure of a rendered frame.

Visual critique kept stalling on guesswork — "the deck looks too dark" is not
actionable, and reasoning about albedo times N-dot-L through a tonemapper to
predict a screen value is slow and unreliable. This reports what actually
reached the framebuffer.

Two readings, because they answer different questions:

  bands     mean luminance of horizontal slices, top to bottom. Shows the
            composition's value structure: sky, backdrop, play surface, the
            mass below it. A side-view game lives or dies on that ramp.

  darkest   the darkest and lightest regions present, and the overall
            histogram spread. The runner must be the darkest thing on screen;
            if level geometry is competing with it, the silhouette is at risk.

Usage:
    python3 scripts/analyse_frame.py <image.png> [more.png ...]
    python3 scripts/analyse_frame.py --bands 16 shot.png

Pure standard library: PNG decoding via zlib, so there is no Pillow dependency
to install in CI.
"""

import argparse
import struct
import sys
import zlib
from pathlib import Path

# Rec. 709 luma coefficients — perceptual weighting, so a blue sky and a grey
# roof of the same "brightness" compare the way an eye would compare them.
LUMA = (0.2126, 0.7152, 0.0722)


def read_png(path: Path):
    """Returns (width, height, rows) where each row is a list of (r, g, b) 0-255."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")

    pos = 8
    width = height = bit_depth = colour_type = None
    idat = bytearray()
    palette = b""

    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length  # 4 len + 4 type + data + 4 crc

        if ctype == b"IHDR":
            width, height, bit_depth, colour_type = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"PLTE":
            palette = chunk
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break

    if bit_depth != 8:
        raise ValueError(f"{path}: only 8-bit PNGs are supported (got {bit_depth})")

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(colour_type)
    if channels is None:
        raise ValueError(f"{path}: unsupported colour type {colour_type}")

    raw = zlib.decompress(bytes(idat))
    stride = width * channels

    # Undo PNG's per-scanline filters. Each row is prefixed with a filter byte and
    # predicted from the row above and the pixel to the left.
    out = bytearray()
    prev = bytearray(stride)
    p = 0
    for _ in range(height):
        filter_type = raw[p]
        p += 1
        line = bytearray(raw[p : p + stride])
        p += stride

        if filter_type == 1:  # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif filter_type == 2:  # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif filter_type == 3:  # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif filter_type == 4:  # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif filter_type != 0:
            raise ValueError(f"{path}: bad filter type {filter_type}")

        out += line
        prev = line

    rows = []
    for y in range(height):
        base = y * stride
        row = []
        for x in range(width):
            i = base + x * channels
            if colour_type in (2, 6):
                row.append((out[i], out[i + 1], out[i + 2]))
            elif colour_type in (0, 4):
                g = out[i]
                row.append((g, g, g))
            else:  # palette
                idx = out[i] * 3
                row.append((palette[idx], palette[idx + 1], palette[idx + 2]))
        rows.append(row)

    return width, height, rows


def luminance(pixel):
    return (
        LUMA[0] * pixel[0] + LUMA[1] * pixel[1] + LUMA[2] * pixel[2]
    ) / 255.0


def analyse(path: Path, band_count: int, sample_step: int):
    width, height, rows = read_png(path)

    band_height = max(1, height // band_count)
    bands = []
    for b in range(band_count):
        y0 = b * band_height
        y1 = min(height, y0 + band_height)
        total = 0.0
        count = 0
        for y in range(y0, y1, sample_step):
            row = rows[y]
            for x in range(0, width, sample_step):
                total += luminance(row[x])
                count += 1
        bands.append(total / count if count else 0.0)

    # Histogram over 10 buckets, for spread.
    buckets = [0] * 10
    darkest = 1.0
    lightest = 0.0
    total_pixels = 0
    for y in range(0, height, sample_step):
        row = rows[y]
        for x in range(0, width, sample_step):
            lum = luminance(row[x])
            buckets[min(9, int(lum * 10))] += 1
            darkest = min(darkest, lum)
            lightest = max(lightest, lum)
            total_pixels += 1

    print(f"\n=== {path.name}  ({width}x{height}) ===")
    print("horizontal bands, top to bottom:")
    for i, value in enumerate(bands):
        bar = "#" * int(value * 52)
        print(f"  {i:2d}  {value:0.3f}  {bar}")

    print(f"\ndarkest {darkest:0.3f}   lightest {lightest:0.3f}   range {lightest - darkest:0.3f}")
    print("histogram (0.0 -> 1.0):")
    for i, n in enumerate(buckets):
        share = n / total_pixels if total_pixels else 0
        bar = "#" * int(share * 52)
        print(f"  {i / 10:0.1f}-{(i + 1) / 10:0.1f}  {share * 100:5.1f}%  {bar}")

    # The one relationship that must hold: the runner is the darkest thing in the
    # frame. If the level's own geometry reaches down into the same bucket, the
    # silhouette is competing with the set.
    very_dark_share = buckets[0] / total_pixels if total_pixels else 0
    if very_dark_share > 0.22:
        print(
            f"\n  WARNING: {very_dark_share * 100:.0f}% of the frame is below 0.1 luminance."
            "\n  Large near-black areas leave the runner nothing to read against."
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--bands", type=int, default=12)
    parser.add_argument(
        "--step",
        type=int,
        default=3,
        help="pixel sampling stride; higher is faster and coarser",
    )
    args = parser.parse_args()

    for image in args.images:
        if not image.exists():
            print(f"missing: {image}", file=sys.stderr)
            continue
        analyse(image, args.bands, args.step)


if __name__ == "__main__":
    main()
