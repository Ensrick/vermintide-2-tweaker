"""Duplicate and reverse the Encarmine plume faces for two-sided rendering.

Run through Blender, not CPython:
  blender -b --factory-startup --python double_side_plume.py -- input.fbx output.fbx

The source plume is an open alpha-cut surface. Stingray's standard material
culls its reverse face, so exporting a reversed duplicate is the deterministic
mesh-side counterpart to the alpha-aware cloth material.
"""

from pathlib import Path
import sys

import bmesh
import bpy


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 2:
        raise SystemExit("expected input.fbx output.fbx")

    source, destination = map(Path, args)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source))

    plume = bpy.data.objects.get("encarmine_cloth")
    if plume is None or plume.type != "MESH":
        raise RuntimeError("encarmine_cloth mesh not found")

    original_faces = len(plume.data.polygons)
    mesh = bmesh.new()
    mesh.from_mesh(plume.data)
    result = bmesh.ops.duplicate(mesh, geom=list(mesh.faces))
    reverse_faces = [
        element
        for element in result["geom"]
        if isinstance(element, bmesh.types.BMFace)
    ]
    if len(reverse_faces) != original_faces:
        raise RuntimeError(
            f"expected {original_faces} duplicated faces, got {len(reverse_faces)}"
        )
    bmesh.ops.reverse_faces(mesh, faces=reverse_faces)
    mesh.to_mesh(plume.data)
    mesh.free()
    plume.data.update()

    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    bpy.context.view_layer.objects.active = plume
    bpy.ops.export_scene.fbx(
        filepath=str(destination),
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="AUTO",
    )
    print(
        f"Encarmine plume: {original_faces} -> {len(plume.data.polygons)} faces; "
        f"wrote {destination}"
    )


if __name__ == "__main__":
    main()

