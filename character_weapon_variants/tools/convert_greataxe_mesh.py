"""Convert one licensed source mesh to CWV's Stingray-friendly FBX shape.

Run through Blender, not CPython.  The wrapper script
``convert_greataxe_assets.ps1`` supplies all arguments after ``--``.

The conversion deliberately makes only technical changes: it joins mesh
objects, removes non-mesh scene data, uses one short material slot, normalizes
the longest dimension to two Blender units, aligns the handle from origin to
positive X, and places the handle butt at the origin. Final grip offsets,
rotations, and scale remain live-tuning work.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector


def _args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--mesh-name", required=True)
    parser.add_argument("--material-name", default="axe_mat")
    parser.add_argument("--report", required=True)
    return parser.parse_args(argv)


def _reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures):
        for block in list(datablocks):
            datablocks.remove(block)


def _import_mesh(path: str) -> None:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=path)
    else:
        raise ValueError(f"Unsupported source mesh: {path}")


def _join_meshes(mesh_name: str) -> bpy.types.Object:
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("Source contains no mesh objects")

    for obj in meshes:
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()

    joined = bpy.context.view_layer.objects.active
    joined.name = mesh_name
    joined.data.name = mesh_name
    return joined


def _world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    corners = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return (
        Vector(tuple(min(c[i] for c in corners) for i in range(3))),
        Vector(tuple(max(c[i] for c in corners) for i in range(3))),
    )


def _normalize(obj: bpy.types.Object) -> dict[str, object]:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    before_min, before_max = _world_bounds(obj)
    before_size = before_max - before_min
    long_axis = max(range(3), key=lambda i: before_size[i])
    longest = before_size[long_axis]
    if not math.isfinite(longest) or longest <= 0:
        raise RuntimeError(f"Invalid source bounds: {tuple(before_size)}")

    coordinates = [vertex.co.copy() for vertex in obj.data.vertices]
    mean_long = sum(co[long_axis] for co in coordinates) / len(coordinates)
    midpoint = (before_min[long_axis] + before_max[long_axis]) * 0.5
    head_at_max = mean_long >= midpoint
    butt_value = before_min[long_axis] if head_at_max else before_max[long_axis]
    grip = (before_min + before_max) * 0.5
    grip[long_axis] = butt_value

    source_direction = Vector((0.0, 0.0, 0.0))
    source_direction[long_axis] = 1.0 if head_at_max else -1.0
    rotation = source_direction.rotation_difference(Vector((1.0, 0.0, 0.0)))
    scale = 2.0 / longest
    for vertex in obj.data.vertices:
        vertex.co = rotation @ ((vertex.co - grip) * scale)
    obj.data.update()
    final_min, final_max = _world_bounds(obj)

    return {
        "source_bounds_min": list(before_min),
        "source_bounds_max": list(before_max),
        "source_dimensions": list(before_size),
        "normalization_scale": scale,
        "source_long_axis": "XYZ"[long_axis],
        "source_head_at_max": head_at_max,
        "output_bounds_min": list(final_min),
        "output_bounds_max": list(final_max),
        "output_dimensions": list(final_max - final_min),
    }


def _single_material(obj: bpy.types.Object, material_name: str) -> None:
    material = bpy.data.materials.get(material_name) or bpy.data.materials.new(material_name)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def main() -> None:
    args = _args()
    input_path = os.path.abspath(args.input)
    output_path = os.path.abspath(args.output)
    report_path = os.path.abspath(args.report)

    _reset_scene()
    _import_mesh(input_path)
    obj = _join_meshes(args.mesh_name)
    bounds = _normalize(obj)
    _single_material(obj, args.material_name)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=output_path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        bake_space_transform=False,
        add_leaf_bones=False,
        path_mode="STRIP",
        axis_forward="-Z",
        axis_up="Y",
    )

    report = {
        "input": input_path,
        "output": output_path,
        "mesh_name": args.mesh_name,
        "material_name": args.material_name,
        "vertex_count": len(obj.data.vertices),
        "polygon_count": len(obj.data.polygons),
        **bounds,
    }
    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    main()
