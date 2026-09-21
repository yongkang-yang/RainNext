#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns from Resources/AppIcon.png.

macOS 26 and later draw app icons inside a container shape of their own. Art
that bakes in its own rounded square therefore renders as a squircle nested in
a squircle, sitting on a grey plate where the transparent margins were — which
is what both the original art and a grid-padded version of it did here.

So the master is rebuilt full-bleed: the glyph is lifted off its background,
the background gradient is reproduced across the whole canvas, and the corners
are left to the system.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources" / "AppIcon.png"
ICNS = ROOT / "Resources" / "AppIcon.icns"

CANVAS = 1024
# Share of the canvas height the glyph occupies. The source fills 66% of its
# own rounded square, which is too tight once that square becomes the canvas.
GLYPH_HEIGHT = 0.60

SOLID = 200          # alpha above this is the artwork, not its shadow
BACKGROUND = 245.0   # luminance of the field the glyph sits on
INK = 35.0           # luminance of the glyph itself

SIZES = [16, 32, 64, 128, 256, 512, 1024]


def glyph_layer(image: Image.Image) -> Image.Image:
    """Lift the glyph off its background as a standalone RGBA layer.

    Alpha comes from how far each pixel is driven toward the ink, which keeps
    the antialiasing that a hard threshold would throw away.
    """
    pixels = np.array(image).astype(np.float32)
    opaque = pixels[:, :, 3] > SOLID
    luminance = pixels[:, :, :3].mean(axis=2)

    alpha = np.clip((BACKGROUND - luminance) / (BACKGROUND - INK), 0, 1)
    alpha[~opaque] = 0

    ys, xs = np.where(alpha > 0.5)
    if not len(xs):
        raise SystemExit("no glyph found in source")

    layer = np.zeros((*alpha.shape, 4), dtype=np.uint8)
    layer[:, :, :3] = 26  # the glyph's own near-black
    layer[:, :, 3] = (alpha * 255).astype(np.uint8)

    return Image.fromarray(layer, "RGBA").crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def gradient_background(top: tuple, bottom: tuple) -> Image.Image:
    ramp = np.linspace(0, 1, CANVAS)[:, None]
    channels = [np.full((CANVAS, CANVAS), 255, dtype=np.uint8)]
    rgb = [(np.array(top[i]) * (1 - ramp) + np.array(bottom[i]) * ramp)
           .repeat(CANVAS, axis=1).astype(np.uint8) for i in range(3)]
    return Image.fromarray(np.dstack(rgb + channels), "RGBA")


def build_master(image: Image.Image) -> Image.Image:
    glyph = glyph_layer(image)

    height = round(CANVAS * GLYPH_HEIGHT)
    width = round(glyph.width * height / glyph.height)
    glyph = glyph.resize((width, height), Image.LANCZOS)

    master = gradient_background((250, 250, 251), (239, 241, 243))
    master.alpha_composite(glyph, ((CANVAS - width) // 2, (CANVAS - height) // 2))
    print(f"glyph {width}x{height} on a full-bleed {CANVAS} canvas")
    return master


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"missing {SOURCE}")

    master = build_master(Image.open(SOURCE).convert("RGBA"))

    iconset = ROOT / "build" / "AppIcon.iconset"
    if iconset.exists():
        for stale in iconset.iterdir():
            stale.unlink()
    iconset.mkdir(parents=True, exist_ok=True)

    # Every size is resampled from the full-resolution master: 16 and 32 decide
    # whether the icon survives a Finder list and a notification banner.
    for size in SIZES:
        scaled = master.resize((size, size), Image.LANCZOS)
        if size in (16, 32, 128, 256, 512):
            scaled.save(iconset / f"icon_{size}x{size}.png")
        if size in (32, 64, 256, 512, 1024):
            scaled.save(iconset / f"icon_{size // 2}x{size // 2}@2x.png")

    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)
    print(f"wrote {ICNS.relative_to(ROOT)} ({ICNS.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    sys.exit(main())
