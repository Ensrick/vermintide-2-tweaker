"""Normalize the licensed Old Musket into VT2's native handgun frame.

Run with Blender 4.4 through ``convert_old_musket_assets.ps1``.  The source
Sketchfab DAE is a single unparented mesh whose object origin is halfway down
the barrel and whose longitudinal axis is +X.  VT2's compiled Empire Handgun
uses an identity root, +Y forward, +Z up, and +X across the lock.  This helper
bakes that exact cyclic basis into the geometry and moves a reviewed,
topology-pinned trigger-pivot landmark onto the native handgun root convention.

The result deliberately contains no character-hand inverse and no
surface-specific pose.  Rifle attachment recipes can consume the normalized
asset at identity; the polearm parent remains a separate runtime adapter.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


SOURCE_SHA256 = "A20C6161C9B6302FF424BFC801D036BEE2C8D793D3A027BE309140C04B791550"
SOURCE_VERTEX_COUNT = 10014
SOURCE_POLYGON_COUNT = 16483
SOURCE_EDGE_COUNT = 26411
SOURCE_COMPONENT_COUNT = 110
SOURCE_COMPONENT_SIGNATURE = "B9F7DBB4EFCAC3C09F44B136C5AAAC03FA172F9060EE67ACF9544B133C6835B6"

# The unique 366-vertex component is the actual trigger lever. Its upper 2 mm
# cap is a stable semantic pivot proxy, unlike the mesh AABB center or a
# nearest-surface guess. The cap is matched to the first-party compiled Empire
# Handgun's ``j_trigger`` node. Every count, bound, and centroid below is pinned
# so revised/reordered art fails closed instead of moving the weapon root.
TRIGGER_COMPONENT_VERTEX_COUNT = 366
EXPECTED_TRIGGER_MINIMUM = Vector(
    (-0.5330659747123718, -0.11042799800634384, 0.010503008030354977)
)
EXPECTED_TRIGGER_MAXIMUM = Vector(
    (-0.4969390034675598, -0.061839401721954346, 0.022775905206799507)
)
TRIGGER_CAP_THICKNESS = 0.002
TRIGGER_CAP_VERTEX_COUNT = 42
EXPECTED_TRIGGER_ANCHOR = Vector(
    (-0.5211421251, -0.0625922084, 0.0174090192)
)
NATIVE_HANDGUN_J_TRIGGER = Vector(
    (0.0, -0.0037636400666087866, 0.039862796664237976)
)

# Source coordinates are +X forward, +Y up, +Z across the lock.  Native
# handgun coordinates are +Y forward, +Z up, +X across the lock.
SOURCE_TO_HANDGUN = Matrix(
    (
        (0.0, 0.0, 1.0),
        (1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
    )
)


def arguments() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output-1p", type=Path, required=True)
    parser.add_argument("--output-3p", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    return parser.parse_args(argv)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
    ):
        for block in list(blocks):
            blocks.remove(block)


def connected_components(mesh: bpy.types.Mesh) -> list[list[int]]:
    adjacency = [[] for _ in mesh.vertices]
    for edge in mesh.edges:
        first, second = edge.vertices
        adjacency[first].append(second)
        adjacency[second].append(first)
    seen: set[int] = set()
    groups: list[list[int]] = []
    for start in range(len(mesh.vertices)):
        if start in seen:
            continue
        stack = [start]
        seen.add(start)
        group: list[int] = []
        while stack:
            index = stack.pop()
            group.append(index)
            for neighbour in adjacency[index]:
                if neighbour not in seen:
                    seen.add(neighbour)
                    stack.append(neighbour)
        groups.append(group)
    return sorted(groups, key=len, reverse=True)


def component_signature(groups: list[list[int]]) -> str:
    payload = ",".join(str(len(group)) for group in groups).encode("ascii")
    return hashlib.sha256(payload).hexdigest().upper()


def centroid(mesh: bpy.types.Mesh, indices: list[int]) -> Vector:
    return sum((mesh.vertices[index].co for index in indices), Vector()) / len(indices)


def bounds(mesh: bpy.types.Mesh) -> tuple[Vector, Vector]:
    return (
        Vector(tuple(min(vertex.co[axis] for vertex in mesh.vertices) for axis in range(3))),
        Vector(tuple(max(vertex.co[axis] for vertex in mesh.vertices) for axis in range(3))),
    )


def near_vector(actual: Vector, expected: Vector, tolerance: float = 0.000001) -> bool:
    return all(abs(actual[index] - expected[index]) <= tolerance for index in range(3))


def require_source(path: Path) -> bpy.types.Object:
    path = path.resolve()
    if not path.is_file() or sha256(path) != SOURCE_SHA256:
        raise RuntimeError(
            "Old Musket source changed; expected DAE SHA-256 " + SOURCE_SHA256
        )
    reset_scene()
    bpy.ops.wm.collada_import(filepath=str(path))
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"expected one Old Musket mesh, got {len(meshes)}")
    obj = meshes[0]
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mesh = obj.data
    if (
        len(mesh.vertices) != SOURCE_VERTEX_COUNT
        or len(mesh.polygons) != SOURCE_POLYGON_COUNT
        or len(mesh.edges) != SOURCE_EDGE_COUNT
        or len(mesh.uv_layers) != 1
    ):
        raise RuntimeError(
            "Old Musket topology/UV contract changed: "
            f"vertices={len(mesh.vertices)} polygons={len(mesh.polygons)} "
            f"edges={len(mesh.edges)} uv_layers={len(mesh.uv_layers)}"
        )
    groups = connected_components(mesh)
    signature = component_signature(groups)
    if len(groups) != SOURCE_COMPONENT_COUNT or signature != SOURCE_COMPONENT_SIGNATURE:
        raise RuntimeError(
            "Old Musket disconnected-component contract changed: "
            f"count={len(groups)} signature={signature}"
        )
    trigger_groups = [
        group for group in groups if len(group) == TRIGGER_COMPONENT_VERTEX_COUNT
    ]
    if len(trigger_groups) != 1:
        raise RuntimeError(
            f"expected one reviewed trigger component, got {len(trigger_groups)}"
        )
    trigger_points = [mesh.vertices[index].co for index in trigger_groups[0]]
    trigger_minimum = Vector(
        tuple(min(point[axis] for point in trigger_points) for axis in range(3))
    )
    trigger_maximum = Vector(
        tuple(max(point[axis] for point in trigger_points) for axis in range(3))
    )
    if not near_vector(trigger_minimum, EXPECTED_TRIGGER_MINIMUM) or not near_vector(
        trigger_maximum, EXPECTED_TRIGGER_MAXIMUM
    ):
        raise RuntimeError(
            "Old Musket trigger bounds moved: "
            f"actual={tuple(trigger_minimum)}->{tuple(trigger_maximum)}"
        )
    cap = [
        index
        for index in trigger_groups[0]
        if mesh.vertices[index].co.y >= trigger_maximum.y - TRIGGER_CAP_THICKNESS
    ]
    trigger_anchor = centroid(mesh, cap)
    if len(cap) != TRIGGER_CAP_VERTEX_COUNT or not near_vector(
        trigger_anchor, EXPECTED_TRIGGER_ANCHOR
    ):
        raise RuntimeError(
            "Old Musket trigger pivot landmark moved: "
            f"count={len(cap)} actual={tuple(trigger_anchor)} "
            f"expected={tuple(EXPECTED_TRIGGER_ANCHOR)}"
        )
    return obj


def normalize(obj: bpy.types.Object) -> dict[str, object]:
    mesh = obj.data
    source_minimum, source_maximum = bounds(mesh)
    groups = connected_components(mesh)
    trigger_group = next(
        group for group in groups if len(group) == TRIGGER_COMPONENT_VERTEX_COUNT
    )
    trigger_maximum_y = max(mesh.vertices[index].co.y for index in trigger_group)
    trigger_cap = [
        index
        for index in trigger_group
        if mesh.vertices[index].co.y
        >= trigger_maximum_y - TRIGGER_CAP_THICKNESS
    ]
    trigger_anchor = centroid(mesh, trigger_cap)
    native_trigger_in_source_basis = Vector(
        (
            NATIVE_HANDGUN_J_TRIGGER.y,
            NATIVE_HANDGUN_J_TRIGGER.z,
            NATIVE_HANDGUN_J_TRIGGER.x,
        )
    )
    source_root = trigger_anchor - native_trigger_in_source_basis
    if not all(math.isfinite(value) for value in source_root):
        raise RuntimeError(f"invalid semantic weapon root {tuple(source_root)}")
    for vertex in mesh.vertices:
        vertex.co = SOURCE_TO_HANDGUN @ (vertex.co - source_root)
    mesh.update()

    obj.name = "rifle"
    mesh.name = "rifle"
    material = bpy.data.materials.get("rifle_mat") or bpy.data.materials.new("rifle_mat")
    mesh.materials.clear()
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.material_index = 0
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    output_minimum, output_maximum = bounds(mesh)
    output_trigger = SOURCE_TO_HANDGUN @ (trigger_anchor - source_root)
    if not near_vector(output_trigger, NATIVE_HANDGUN_J_TRIGGER):
        raise RuntimeError(
            "normalized trigger/root relationship changed: "
            f"actual={tuple(output_trigger)} "
            f"expected={tuple(NATIVE_HANDGUN_J_TRIGGER)}"
        )
    dimensions = output_maximum - output_minimum
    if dimensions.y <= dimensions.z * 5 or dimensions.y <= dimensions.x * 20:
        raise RuntimeError(f"Old Musket no longer points along native +Y: {tuple(dimensions)}")
    if output_minimum.y >= 0 or output_maximum.y <= 0:
        raise RuntimeError("semantic root no longer lies between stock and muzzle")
    return {
        "source_bounds_min": list(source_minimum),
        "source_bounds_max": list(source_maximum),
        "source_root": list(source_root),
        "trigger_anchor": list(trigger_anchor),
        "native_handgun_j_trigger": list(NATIVE_HANDGUN_J_TRIGGER),
        "output_bounds_min": list(output_minimum),
        "output_bounds_max": list(output_maximum),
        "output_dimensions": list(dimensions),
        "output_trigger_anchor": list(output_trigger),
    }


def export_fbx(path: Path, obj: bpy.types.Object) -> None:
    path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        bake_space_transform=False,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="STRIP",
        axis_forward="Y",
        axis_up="Z",
    )


def verify_reimport(path: Path, expected: dict[str, object]) -> None:
    reset_scene()
    bpy.ops.import_scene.fbx(filepath=str(path.resolve()), use_anim=False)
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"{path.name}: expected one reimported mesh, got {len(meshes)}")
    obj = meshes[0]
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    minimum = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    maximum = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    if (
        obj.name != "rifle"
        or len(obj.data.vertices) != SOURCE_VERTEX_COUNT
        or len(obj.data.polygons) != SOURCE_POLYGON_COUNT
        or len(obj.data.uv_layers) != 1
        or [material.name for material in obj.data.materials] != ["rifle_mat"]
    ):
        raise RuntimeError(
            f"{path.name}: renderer/topology contract changed "
            f"name={obj.name} vertices={len(obj.data.vertices)} "
            f"polygons={len(obj.data.polygons)} uv={len(obj.data.uv_layers)} "
            f"materials={[material.name for material in obj.data.materials]}"
        )
    expected_minimum = Vector(expected["output_bounds_min"])
    expected_maximum = Vector(expected["output_bounds_max"])
    if not near_vector(minimum, expected_minimum, 0.00001) or not near_vector(
        maximum, expected_maximum, 0.00001
    ):
        raise RuntimeError(
            f"{path.name}: FBX round trip changed canonical bounds "
            f"min={tuple(minimum)} max={tuple(maximum)}"
        )


def main() -> None:
    args = arguments()
    source = args.input.resolve()
    obj = require_source(source)
    report = normalize(obj)
    output_1p = args.output_1p.resolve()
    output_3p = args.output_3p.resolve()
    export_fbx(output_1p, obj)
    verify_reimport(output_1p, report)
    output_3p.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(output_1p, output_3p)
    verify_reimport(output_3p, report)
    report.update(
        {
            "contract": "cwv_old_musket_native_frame_v1",
            "source_sha256": SOURCE_SHA256,
            "source_component_signature": SOURCE_COMPONENT_SIGNATURE,
            "source_vertex_count": SOURCE_VERTEX_COUNT,
            "source_polygon_count": SOURCE_POLYGON_COUNT,
            "basis": {"source": "+X forward/+Y up/+Z side", "output": "+Y forward/+Z up/+X side"},
            "output_1p_sha256": sha256(output_1p),
            "output_3p_sha256": sha256(output_3p),
        }
    )
    report_path = args.report.resolve()
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        "[old-musket-export] "
        f"source={SOURCE_SHA256} root={tuple(report['source_root'])} "
        f"bounds={tuple(report['output_bounds_min'])}->{tuple(report['output_bounds_max'])}"
    )
    print(f"[old-musket-export] 1p={output_1p} sha256={report['output_1p_sha256']}")
    print(f"[old-musket-export] 3p={output_3p} sha256={report['output_3p_sha256']}")


if __name__ == "__main__":
    main()
