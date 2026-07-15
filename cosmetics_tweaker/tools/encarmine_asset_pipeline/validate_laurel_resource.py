"""Validate the compiled Laurel donor used by the Encarmine material override.

Run this script through Blender because Bitsquid Blender Tools imports ``bpy``.
It parses the compiled ``.unit`` directly and compares mesh objects, material
slots, render flags, skin indices, and LOD membership to the reviewed contract.
This is intentionally not a source-file-existence check.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import bpy


def text(value) -> str:
    return str(value)


class Reporter:
    def report(self, levels, message):
        if "ERROR" in levels:
            raise RuntimeError(message)


def close(actual: float, expected: float, tolerance: float = 1e-5) -> bool:
    return abs(actual - expected) <= tolerance


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 3:
        raise SystemExit("expected <bitsquid-tools> <compiled-root> <contract.json>")
    tools_root, compiled_root, contract_path = map(Path, args)
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    unit_path = compiled_root / (contract["resource"].replace("/", os.sep) + ".unit")
    if not unit_path.is_file():
        raise FileNotFoundError(unit_path)

    os.environ["IS_CI_PIPELINE"] = "1"
    sys.path.insert(0, str(tools_root))
    import bitsquid
    from bitsquid import resource_manager, utils
    from bitsquid.unit.import_compiled import UnitImporterVT2

    bitsquid.register()
    resource_manager.get_extract_dir_vt2 = lambda: str(compiled_root)
    utils.get_extract_dir_vt2 = lambda: str(compiled_root)
    utils.is_level_editor_enabled = lambda: False
    unit = UnitImporterVT2(Reporter(), bpy.context, path=str(unit_path)).resource

    actual_materials = [[text(slot), resource.lookup() or text(resource)] for slot, resource in unit.materials]
    if sorted(actual_materials) != sorted(contract["materials"]):
        raise RuntimeError(f"material contract drift: {actual_materials}")

    actual_meshes = [[
        text(mesh.name), mesh.node_index, mesh.geometry_index, mesh.skin_index, mesh.flags,
    ] for mesh in unit.meshes]
    if actual_meshes != contract["mesh_objects"]:
        raise RuntimeError(f"mesh object contract drift: {actual_meshes}")

    actual_slots = [[text(slot) for slot in geometry.materials] for geometry in unit.mesh_geometries]
    if actual_slots != contract["geometry_material_slots"]:
        raise RuntimeError(f"geometry material contract drift: {actual_slots}")

    role_by_slot = {
        "1903313B": "armor",
        "BD15BFF9": "plume",
        "5ED8F236": "shadow",
    }
    runtime_mesh_materials = []
    for mesh_index, mesh in enumerate(unit.meshes):
        geometry_index = mesh.geometry_index
        slots = actual_slots[geometry_index - 1]
        if len(slots) != 1 or slots[0] not in role_by_slot:
            raise RuntimeError(
                f"mesh {mesh_index} geometry {geometry_index} has unknown donor slots {slots}"
            )
        slot = slots[0]
        runtime_mesh_materials.append([
            mesh_index, geometry_index, slot, role_by_slot[slot],
        ])
    if runtime_mesh_materials != contract["runtime_mesh_materials"]:
        raise RuntimeError(f"runtime mesh/material role drift: {runtime_mesh_materials}")

    if len(unit.lod_objects) != len(contract["lod_objects"]):
        raise RuntimeError("LOD object count drift")
    for actual, expected in zip(unit.lod_objects, contract["lod_objects"]):
        if [text(actual.name), actual.node_index, actual.flags] != [
            expected["name"], expected["node_index"], expected["flags"],
        ]:
            raise RuntimeError("LOD owner contract drift")
        if len(actual.steps) != len(expected["steps"]):
            raise RuntimeError("LOD step count drift")
        for actual_step, expected_step in zip(actual.steps, expected["steps"]):
            if list(actual_step.meshes) != expected_step["meshes"]:
                raise RuntimeError("LOD mesh membership drift")
            if not all(close(a, e) for a, e in zip(
                actual_step.visible_height_range, expected_step["range"],
            )):
                raise RuntimeError("LOD visible-height range drift")

    print("ENCARMINE_LAUREL_COMPILED_CONTRACT=OK meshes=8 lod_steps=3 materials=3")


if __name__ == "__main__":
    main()
