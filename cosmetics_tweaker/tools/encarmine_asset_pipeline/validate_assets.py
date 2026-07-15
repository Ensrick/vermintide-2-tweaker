"""Offline quantitative gate for the compiled-source Encarmine maps."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from PIL import Image


EXPECTED_VISIBLE_PIXELS = 198_940
EXPECTED_ROUGHNESS = {110: 502_897, 166: 545_679}
CUT_THRESHOLD = 128
MAX_MIP_COVERAGE_DRIFT = 0.035


def pixels(image: Image.Image):
    return image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()


def alpha_coverage(alpha: Image.Image) -> float:
    values = pixels(alpha)
    return sum(value >= CUT_THRESHOLD for value in values) / (alpha.width * alpha.height)


def validate(texture_root: Path) -> None:
    plume = Image.open(texture_root / "encarmine_cloth_diffuse.png").convert("RGBA")
    alpha = plume.getchannel("A")
    histogram = Counter(pixels(alpha))
    if set(histogram) != {0, 255}:
        raise AssertionError(f"plume alpha must be binary, got {sorted(histogram)}")
    if histogram[255] != EXPECTED_VISIBLE_PIXELS:
        raise AssertionError(
            f"plume silhouette drifted: {histogram[255]} != {EXPECTED_VISIBLE_PIXELS}"
        )

    visible_luminance = sorted(
        round(0.2126 * red + 0.7152 * green + 0.0722 * blue)
        for red, green, blue, value in pixels(plume)
        if value == 255
    )
    median = visible_luminance[len(visible_luminance) // 2]
    if median != 84:
        raise AssertionError(f"plume median luminance drifted: {median} != 84")

    # Approximate the compiler's Kaiser mip cascade with high-quality Lanczos,
    # then apply the same 0.5 cut. Coverage must stay close to the authored
    # silhouette through ordinary character-view distances.
    base_coverage = alpha_coverage(alpha)
    mip = alpha
    for level in range(1, 7):
        mip = mip.resize(
            (max(1, mip.width // 2), max(1, mip.height // 2)),
            Image.Resampling.LANCZOS,
        )
        drift = abs(alpha_coverage(mip) - base_coverage)
        if drift > MAX_MIP_COVERAGE_DRIFT:
            raise AssertionError(
                f"plume mip {level} alpha coverage drift {drift:.4f} exceeds "
                f"{MAX_MIP_COVERAGE_DRIFT:.4f}"
            )

    roughness = Image.open(texture_root / "encarmine_armored_roughness.png").convert("L")
    roughness_histogram = Counter(pixels(roughness))
    if dict(roughness_histogram) != EXPECTED_ROUGHNESS:
        raise AssertionError(
            f"armor roughness drifted: {dict(roughness_histogram)} != {EXPECTED_ROUGHNESS}"
        )

    print(
        "Encarmine assets OK: "
        f"visible={histogram[255]} median_luma={median} "
        f"coverage={base_coverage:.5f} roughness={dict(roughness_histogram)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("texture_root", type=Path)
    args = parser.parse_args()
    validate(args.texture_root)


if __name__ == "__main__":
    main()
