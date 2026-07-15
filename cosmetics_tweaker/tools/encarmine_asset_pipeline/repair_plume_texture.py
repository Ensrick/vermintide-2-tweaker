"""Repair the Encarmine plume's cutout and charcoal brightness.

The recolored source kept the vanilla feather alpha, including thousands of
near-zero coverage texels. Those texels become a translucent rectangular haze
under a general-purpose blended shader and DXT5 mip filtering. The first repair
kept the remaining fractional alpha and then enabled the compiler's 0.5 cut,
which erased the live feather on some render paths. Convert every authored
non-haze texel to an explicit opaque cutout instead, and lift the feather's RGB
by a measured 4x (retained-pixel median 21 -> 84) so it remains charcoal rather than
rendering nearly black in VT2's character lighting.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


ALPHA_HAZE_MAX = 15
RGB_SCALE = 4.0
RETAINED_ALPHA = 255


def pixels(image: Image.Image):
    return image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()


def repair(source: Path, destinations: list[Path]) -> None:
    image = Image.open(source).convert("RGBA")
    repaired = []

    for red, green, blue, alpha in pixels(image):
        if alpha <= ALPHA_HAZE_MAX:
            repaired.append((0, 0, 0, 0))
            continue
        repaired.append(
            (
                min(255, round(red * RGB_SCALE)),
                min(255, round(green * RGB_SCALE)),
                min(255, round(blue * RGB_SCALE)),
                RETAINED_ALPHA,
            )
        )

    image.putdata(repaired)
    for destination in destinations:
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destinations", nargs="+", type=Path)
    args = parser.parse_args()
    repair(args.source, args.destinations)


if __name__ == "__main__":
    main()
