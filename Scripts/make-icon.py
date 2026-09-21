#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns from Resources/AppIcon.png.

The master art draws its rounded square nearly edge to edge. macOS expects the
shape to sit on a grid — 824pt of artwork centred in a 1024pt canvas — so an
icon drawn any larger stands out from every other app in the Finder.

The whole image is scaled rather than cropped to the shape: the art carries a
soft shadow outside its solid bounds, and cropping would cut it off. The solid
shape is only measured, to work out the scale factor and where the centre is.
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
ARTWORK = 824
# Alpha above this is the shape itself; the shadow and any soft halo sit below.
SOLID = 200
SIZES = [16, 32, 64, 128, 256, 512, 1024]


def seated_on_grid(image: Image.Image) -> Image.Image:
    alpha = np.array(image)[:, :, 3]
    ys, xs = np.where(alpha > SOLID)
    if not len(xs):
        raise SystemExit("source image has no solid shape")

    shape_w, shape_h = xs.max() - xs.min() + 1, ys.max() - ys.min() + 1
    centre = ((xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2)
    scale = ARTWORK / max(shape_w, shape_h)

    scaled = image.resize(
        (round(image.width * scale), round(image.height * scale)), Image.LANCZOS
    )
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(
        scaled,
        (round(CANVAS / 2 - centre[0] * scale), round(CANVAS / 2 - centre[1] * scale)),
    )
    print(f"art {shape_w}x{shape_h} -> {ARTWORK}, scale {scale:.4f}")
    return canvas


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"missing {SOURCE}")

    master = seated_on_grid(Image.open(SOURCE).convert("RGBA"))

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
