"""Validate the exact Encarmine unit imported from a built mod bundle.

This is deliberately a post-compiler gate. Run it through Blender after the
standalone BD55DCA31255AAEC bundle has been extracted and imported with
``import_laurel_unit.py``. Source-FBX checks alone cannot see Stingray's final
object hierarchy or compiled render bounds.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy


PLUME = "862683C6"
ARMOR = "A1828E0D"


def basis_lengths(obj):
    return [
        math.sqrt(sum(obj.matrix_world[row][column] ** 2 for row in range(3)))
        for column in range(3)
    ]


def assert_vector(actual, expected, label, tolerance):
    if len(actual) != len(expected):
        raise RuntimeError(f"{label}: length mismatch")
    for axis, (value, wanted) in enumerate(zip(actual, expected)):
        if abs(value - wanted) > tolerance:
            raise RuntimeError(
                f"{label}[{axis}]: expected {wanted} +/- {tolerance}, got {value}"
            )


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("expected compiled-unit .blend")
    source = Path(args[0])
    bpy.ops.wm.open_mainfile(filepath=str(source))

    plume = bpy.data.objects.get(PLUME)
    armor = bpy.data.objects.get(ARMOR)
    if not plume or plume.type != "MESH":
        raise RuntimeError("compiled plume mesh 862683C6 missing")
    if not armor or armor.type != "MESH":
        raise RuntimeError("compiled armor mesh A1828E0D missing")

    assert_vector(plume.scale, (1.0, 1.0, 1.0), "plume local scale", 1e-5)
    assert_vector(armor.scale, (1.0, 1.0, 1.0), "armor local scale", 1e-5)
    # The importer exposes Stingray's metre/centimetre root conversion as a
    # common 100x world basis. What matters is that the plume has no additional
    # relative 100x transform: its basis must equal the armor's basis.
    assert_vector(basis_lengths(plume), basis_lengths(armor), "relative world basis", 1e-3)
    assert_vector(plume.dimensions, (0.1006, 0.2503, 0.3188), "plume dimensions", 0.002)
    assert_vector(armor.dimensions, (0.2306, 0.2890, 0.3234), "armor dimensions", 0.002)
    if len(plume.data.polygons) != 744:
        raise RuntimeError(f"compiled plume faces: expected 744, got {len(plume.data.polygons)}")

    expected_groups = {f"j_feather_{index:02d}_dynamic" for index in range(1, 7)}
    actual_groups = {group.name for group in plume.vertex_groups}
    if not expected_groups.issubset(actual_groups):
        raise RuntimeError(f"compiled plume groups missing: {sorted(expected_groups - actual_groups)}")

    print(
        "ENCARMINE_COMPILED_CONTRACT=OK "
        f"plume_dimensions={[round(v, 6) for v in plume.dimensions]} "
        f"armor_dimensions={[round(v, 6) for v in armor.dimensions]} "
        f"basis={[round(v, 6) for v in basis_lengths(plume)]} faces=744 groups=6"
    )


if __name__ == "__main__":
    main()
