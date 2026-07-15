"""Export the Encarmine helmet while preserving Laurel's feather skeleton.

Input is the deterministic compiled-unit import produced by
``import_laurel_unit.py``. Only the highest armor and feather LODs are retained;
the feather faces are duplicated/reversed for two-sided rendering while keeping
their six dynamic-bone vertex groups.
"""

from __future__ import annotations

import shutil
import sys
from pathlib import Path

import bmesh
import bpy


ARMOR_OBJECT = "C051D3AB"
PLUME_OBJECT = "AD1E2AED"
ARMATURE_OBJECT = "armature object"


def _assert_near(actual: float, expected: float, label: str, tolerance: float = 1e-5) -> None:
    if abs(actual - expected) > tolerance:
        raise RuntimeError(f"{label}: expected {expected}, got {actual}")


def validate_round_trip(path: Path) -> None:
    """Reject FBX unit-conversion drift before Stingray can compile it.

    The FBX exporter can hide a 100x unit conversion on a skinned mesh while
    preserving its apparent Blender dimensions. Stingray bakes that transform
    a second time. Re-importing the actual artifact is therefore mandatory;
    inspecting the source .blend alone cannot detect this failure.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(path))

    armor = bpy.data.objects.get("encarmine_armored")
    plume = bpy.data.objects.get("encarmine_cloth")
    armature = bpy.data.objects.get("encarmine_hat_armature")
    if not armor or armor.type != "MESH":
        raise RuntimeError("round-trip armor mesh missing")
    if not plume or plume.type != "MESH":
        raise RuntimeError("round-trip plume mesh missing")
    if not armature or armature.type != "ARMATURE":
        raise RuntimeError("round-trip armature missing")

    for obj in (armor, plume, armature):
        for axis, value in zip("xyz", obj.scale):
            _assert_near(value, 1.0, f"{obj.name} local scale {axis}")
    for obj in (armor, plume):
        for row in range(3):
            basis_length = sum(obj.matrix_world[col][row] ** 2 for col in range(3)) ** 0.5
            _assert_near(basis_length, 1.0, f"{obj.name} world basis {row}")

    if len(armor.data.polygons) != 7960:
        raise RuntimeError(f"round-trip armor faces: expected 7960, got {len(armor.data.polygons)}")
    if len(plume.data.polygons) != 744:
        raise RuntimeError(f"round-trip plume faces: expected 744, got {len(plume.data.polygons)}")
    if len(armature.data.bones) != 13:
        raise RuntimeError(f"round-trip bones: expected 13, got {len(armature.data.bones)}")
    expected_groups = {f"j_feather_{index:02d}_dynamic" for index in range(1, 7)}
    actual_groups = {group.name for group in plume.vertex_groups}
    if not expected_groups.issubset(actual_groups):
        raise RuntimeError(f"round-trip feather groups missing: {sorted(expected_groups - actual_groups)}")

    print("Encarmine FBX round-trip: local/world scale=1, armor=7960, plume=744, bones=13")


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) < 2:
        raise SystemExit("expected input.blend destination.fbx [mirror.fbx ...]")

    source = Path(args[0])
    destinations = [Path(value) for value in args[1:]]
    bpy.ops.wm.open_mainfile(filepath=str(source))

    keep = {ARMOR_OBJECT, PLUME_OBJECT, ARMATURE_OBJECT}
    for obj in list(bpy.context.scene.objects):
        if obj.name not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)

    armor = bpy.data.objects[ARMOR_OBJECT]
    plume = bpy.data.objects[PLUME_OBJECT]
    armature = bpy.data.objects[ARMATURE_OBJECT]
    armor.name = "encarmine_armored"
    armor.data.name = "encarmine_armored"
    plume.name = "encarmine_cloth"
    plume.data.name = "encarmine_cloth"
    armature.name = "encarmine_hat_armature"

    armor_material = bpy.data.materials.new("encarmine_armored")
    plume_material = bpy.data.materials.new("encarmine_cloth")
    armor.data.materials.clear()
    armor.data.materials.append(armor_material)
    plume.data.materials.clear()
    plume.data.materials.append(plume_material)

    source_faces = len(plume.data.polygons)
    mesh = bmesh.new()
    mesh.from_mesh(plume.data)
    result = bmesh.ops.duplicate(mesh, geom=list(mesh.faces))
    reverse_faces = [
        element for element in result["geom"] if isinstance(element, bmesh.types.BMFace)
    ]
    if len(reverse_faces) != source_faces:
        raise RuntimeError(f"expected {source_faces} duplicate faces, got {len(reverse_faces)}")
    bmesh.ops.reverse_faces(mesh, faces=reverse_faces)
    mesh.to_mesh(plume.data)
    mesh.free()
    plume.data.update()

    expected_groups = {f"j_feather_{index:02d}_dynamic" for index in range(1, 7)}
    actual_groups = {group.name for group in plume.vertex_groups}
    if not expected_groups.issubset(actual_groups):
        raise RuntimeError(f"missing feather vertex groups: {sorted(expected_groups - actual_groups)}")

    primary = destinations[0]
    primary.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in (armor, plume, armature):
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.fbx(
        filepath=str(primary),
        use_selection=True,
        object_types={"MESH", "ARMATURE"},
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        # Preserve the donor's local scale-1 skinned-mesh contract. Blender's
        # default FBX_SCALE_NONE bakes metre-to-centimetre conversion into the
        # plume object's local transform (100x); Stingray then bakes that
        # transform again when compiling the unit.
        apply_scale_options="FBX_SCALE_UNITS",
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="AUTO",
    )

    armor_faces = len(armor.data.polygons)
    plume_faces = len(plume.data.polygons)
    bone_count = len(armature.data.bones)
    validate_round_trip(primary)

    for mirror in destinations[1:]:
        mirror.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(primary, mirror)

    print(
        f"Encarmine rig export: armor_faces={armor_faces} "
        f"plume_faces={source_faces}->{plume_faces} "
        f"bones={bone_count} outputs={len(destinations)}"
    )


if __name__ == "__main__":
    main()
