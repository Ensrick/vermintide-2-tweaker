"""Print the render contract of an imported Laurel/Encarmine scene."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


def vector(values):
    return [round(value, 6) for value in values]


def transform_contract(obj):
    return {
        "name": obj.name,
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "parent_type": obj.parent_type,
        "parent_bone": obj.parent_bone,
        "location": vector(obj.location),
        "rotation_euler": vector(obj.rotation_euler),
        "scale": vector(obj.scale),
        "matrix_world": [vector(row) for row in obj.matrix_world],
        "hide_render": obj.hide_render,
        "hide_viewport": obj.hide_viewport,
    }


def bone_contract(bone):
    return {
        "name": bone.name,
        "parent": bone.parent.name if bone.parent else None,
        "head_local": vector(bone.head_local),
        "tail_local": vector(bone.tail_local),
        "matrix_local": [vector(row) for row in bone.matrix_local],
        "use_deform": bone.use_deform,
    }


def mesh_contract(obj):
    mesh = obj.data
    material_indices = {}
    for polygon in mesh.polygons:
        material_indices[polygon.material_index] = material_indices.get(polygon.material_index, 0) + 1
    return {
        "name": obj.name,
        "mesh": mesh.name,
        "polygons": len(mesh.polygons),
        "vertices": len(mesh.vertices),
        "materials": [slot.material.name if slot.material else None for slot in obj.material_slots],
        "material_indices": material_indices,
        "vertex_groups": sorted(group.name for group in obj.vertex_groups),
        "hide_render": obj.hide_render,
        "hide_viewport": obj.hide_viewport,
        "visible_camera": getattr(obj, "visible_camera", None),
        "display_type": obj.display_type,
        "dimensions": vector(obj.dimensions),
        "scale": vector(obj.scale),
        "matrix_world": [vector(row) for row in obj.matrix_world],
        "parent": obj.parent.name if obj.parent else None,
        "modifiers": [modifier.type for modifier in obj.modifiers],
        "uv_layers": [layer.name for layer in mesh.uv_layers],
    }


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 1:
        raise SystemExit("expected .blend or .fbx input")
    source = Path(args[0])

    if source.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source))
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=str(source))

    contract = {
        "source": str(source),
        "meshes": [
            mesh_contract(obj)
            for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name)
            if obj.type == "MESH"
        ],
        "armatures": [
            {
                "name": obj.name,
                "bones": [bone_contract(bone) for bone in sorted(obj.data.bones, key=lambda item: item.name)],
                "hide_render": obj.hide_render,
                "scale": vector(obj.scale),
                "dimensions": vector(obj.dimensions),
                "matrix_world": [vector(row) for row in obj.matrix_world],
            }
            for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name)
            if obj.type == "ARMATURE"
        ],
        "objects": [
            transform_contract(obj)
            for obj in sorted(bpy.context.scene.objects, key=lambda item: item.name)
        ],
    }
    print("ENCARMINE_SCENE_CONTRACT=" + json.dumps(contract, sort_keys=True))


if __name__ == "__main__":
    main()
