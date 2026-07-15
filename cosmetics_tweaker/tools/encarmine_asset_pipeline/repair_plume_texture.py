"""Combine authored Encarmine color with Laurel's exact feather alpha.

The Encarmine plume changes RGB only. Alpha is geometry-adjacent behavior: its
fractional coverage and mip chain are part of Laurel's native cutout material
contract. Binarizing coverage produced tape-like cards and later made the plume
disappear, so this tool rejects size drift and copies donor alpha byte-for-byte.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def restore_alpha(color_source: Path, donor_source: Path, destinations: list[Path]) -> None:
    color = Image.open(color_source).convert("RGBA")
    donor = Image.open(donor_source).convert("RGBA")
    if color.size != donor.size:
        raise ValueError(f"size mismatch: color={color.size}, donor={donor.size}")

    restored = color.copy()
    restored.putalpha(donor.getchannel("A"))
    if restored.getchannel("A").tobytes() != donor.getchannel("A").tobytes():
        raise RuntimeError("donor alpha copy failed")

    for destination in destinations:
        destination.parent.mkdir(parents=True, exist_ok=True)
        restored.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("color_source", type=Path)
    parser.add_argument("donor_source", type=Path)
    parser.add_argument("destinations", nargs="+", type=Path)
    args = parser.parse_args()
    restore_alpha(args.color_source, args.donor_source, args.destinations)


if __name__ == "__main__":
    main()
