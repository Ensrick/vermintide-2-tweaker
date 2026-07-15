"""Apply the measured Encarmine helmet gloss correction.

The v0.9.115 response repair intentionally moved the helmet far away from the
mirror-like v0.9.114 result. Live comparison with the Knights Encarmine outfit
then showed that the helmet overshot slightly toward matte. Preserve the two
authored paint/detail regions and lower roughness by ten percent; this is a
bounded response-map change, not a diffuse brightness or metallic rewrite.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


ROUGHNESS_SCALE = 0.90


def tune(source: Path, destinations: list[Path]) -> None:
    image = Image.open(source).convert("L")
    image = image.point(lambda value: round(value * ROUGHNESS_SCALE))

    for destination in destinations:
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destinations", nargs="+", type=Path)
    args = parser.parse_args()
    tune(args.source, args.destinations)


if __name__ == "__main__":
    main()
