"""Normalize an approved Crowbill source mesh for CWV's Stingray pipeline.

This Blender-only helper performs technical conversion, not artistic edits. It
can atlas several source materials horizontally before collapsing them to one
short Stingray-safe material slot. Final in-game grip transforms remain data.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Vector


def arguments() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--mesh-name", required=True)
    parser.add_argument("--material-name", default="crowbill_mat")
    parser.add_argument("--report", required=True)
    parser.add_argument(
        "--atlas-material-order",
        default="",
        help="Comma-separated source material names in left-to-right atlas order",
    )
    return parser.parse_args(argv)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures):
        for block in list(datablocks):
            datablocks.remove(block)


def import_mesh(path: str) -> None:
    extension = os.path.splitext(path)[1].lower()
    if extension == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif extension == ".dae":
        bpy.ops.wm.collada_import(filepath=path)
    else:
        raise ValueError(f"Unsupported Crowbill source mesh: {path}")


def join_meshes(mesh_name: str) -> bpy.types.Object:
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
    result = bpy.context.view_layer.objects.active
    result.name = mesh_name
    result.data.name = mesh_name
    return result


def atlas_uvs(obj: bpy.types.Object, order: list[str]) -> dict[str, object]:
    if not order:
        return {"atlas_material_order": [], "atlas_polygons": 0}
    if not obj.data.uv_layers.active:
        raise RuntimeError("Atlas source has no active UV layer")
    material_names = [slot.name if slot else "" for slot in obj.data.materials]
    missing = [name for name in order if name not in material_names]
    if missing:
        raise RuntimeError(f"Atlas materials missing from source: {missing}; found={material_names}")
    atlas_index = {name: index for index, name in enumerate(order)}
    width = float(len(order))
    uv_data = obj.data.uv_layers.active.data
    touched = 0
    for polygon in obj.data.polygons:
        material_name = material_names[polygon.material_index]
        if material_name not in atlas_index:
            raise RuntimeError(f"Polygon uses unplanned material: {material_name}")
        offset = atlas_index[material_name]
        for loop_index in polygon.loop_indices:
            uv = uv_data[loop_index].uv
            uv.x = (uv.x + offset) / width
        touched += 1
    return {"atlas_material_order": order, "atlas_polygons": touched}


def world_bounds(obj: bpy.types.Object) -> tuple[Vector, Vector]:
    vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return (
        Vector(tuple(min(vertex[i] for vertex in vertices) for i in range(3))),
        Vector(tuple(max(vertex[i] for vertex in vertices) for i in range(3))),
    )


def normalize(obj: bpy.types.Object) -> dict[str, object]:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    minimum, maximum = world_bounds(obj)
    dimensions = maximum - minimum
    long_axis = max(range(3), key=lambda index: dimensions[index])
    longest = dimensions[long_axis]
    if not math.isfinite(longest) or longest <= 0:
        raise RuntimeError(f"Invalid source bounds: {tuple(dimensions)}")

    coordinates = [vertex.co.copy() for vertex in obj.data.vertices]
    mean = sum(coordinate[long_axis] for coordinate in coordinates) / len(coordinates)
    midpoint = (minimum[long_axis] + maximum[long_axis]) * 0.5
    head_at_maximum = mean >= midpoint
    butt = minimum[long_axis] if head_at_maximum else maximum[long_axis]
    grip = (minimum + maximum) * 0.5
    grip[long_axis] = butt
    direction = Vector((0.0, 0.0, 0.0))
    direction[long_axis] = 1.0 if head_at_maximum else -1.0
    rotation = direction.rotation_difference(Vector((1.0, 0.0, 0.0)))
    scale = 2.0 / longest
    for vertex in obj.data.vertices:
        vertex.co = rotation @ ((vertex.co - grip) * scale)
    obj.data.update()
    final_minimum, final_maximum = world_bounds(obj)
    return {
        "source_bounds_min": list(minimum),
        "source_bounds_max": list(maximum),
        "source_dimensions": list(dimensions),
        "normalization_scale": scale,
        "source_long_axis": "XYZ"[long_axis],
        "source_head_at_max": head_at_maximum,
        "output_bounds_min": list(final_minimum),
        "output_bounds_max": list(final_maximum),
        "output_dimensions": list(final_maximum - final_minimum),
    }


def collapse_materials(obj: bpy.types.Object, material_name: str) -> None:
    material = bpy.data.materials.get(material_name) or bpy.data.materials.new(material_name)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def main() -> None:
    args = arguments()
    input_path = os.path.abspath(args.input)
    output_path = os.path.abspath(args.output)
    report_path = os.path.abspath(args.report)
    atlas_order = [name for name in args.atlas_material_order.split(",") if name]

    reset_scene()
    import_mesh(input_path)
    obj = join_meshes(args.mesh_name)
    atlas = atlas_uvs(obj, atlas_order)
    bounds = normalize(obj)
    collapse_materials(obj, args.material_name)

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
        **atlas,
        **bounds,
    }
    os.makedirs(os.path.dirname(report_path), exist_ok=True)
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")


if __name__ == "__main__":
    main()
