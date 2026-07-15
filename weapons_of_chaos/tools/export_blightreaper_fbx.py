import json
import math
import os
import sys
from pathlib import Path

os.environ["IS_CI_PIPELINE"] = "1"

import bpy
from mathutils import Matrix, Vector

PYDEPS = Path(os.environ["WOC_BITSQUID_PYDEPS"])
EXTRACT_ROOT = Path(os.environ["WOC_EXTRACT_ROOT"])
ADDON_MODULE = "bl_ext.user_default.bitsquid"
SOURCE_OBJECT = "6692D5DA"


def world_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return Vector(map(min, zip(*points))), Vector(map(max, zip(*points)))


def main():
    sys.path.insert(0, str(PYDEPS))
    bpy.ops.preferences.addon_enable(module=ADDON_MODULE)
    bpy.context.preferences.addons[ADDON_MODULE].preferences.extracted_files_dir_vt2 = str(EXTRACT_ROOT)
    settings = bpy.context.scene.bitsquid_import_settings
    settings.import_materials = False
    settings.import_textures = False
    settings.import_joints = False
    settings.import_empties = False
    settings.node_parenting = False
    settings.skip_low_lod = False
    settings.remove_invisible_meshes = False

    argv = sys.argv[sys.argv.index("--") + 1 :]
    unit_path = Path(argv[0]).resolve()
    output_path = Path(argv[1]).resolve()

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.unit_vt2(filepath=str(unit_path))
    source = bpy.data.objects.get(SOURCE_OBJECT)
    if source is None or source.type != "MESH":
        raise RuntimeError(f"expected Blightreaper high-LOD mesh {SOURCE_OBJECT}")

    bpy.ops.object.select_all(action="DESELECT")
    source.select_set(True)
    bpy.context.view_layer.objects.active = source
    source.name = "blightreaper"
    source.data.name = "blightreaper"
    source.data.materials.clear()
    source.data.materials.append(bpy.data.materials.new("blightreaper_mat"))

    # Native trophy geometry is Z-long. Player weapon units are X-long with the
    # pommel at the origin, so rotate and translate without rescaling the
    # original 1.515 m trophy proportions.
    source.data.transform(Matrix.Rotation(math.radians(90), 4, "Y"))
    low, high = world_bounds(source)
    source.data.transform(Matrix.Translation(Vector((-low.x, -(low.y + high.y) * 0.5, -(low.z + high.z) * 0.5))))
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    low, high = world_bounds(source)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=str(output_path),
        use_selection=True,
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="STRIP",
    )
    print("WOC_BLIGHTREAPER_EXPORT=" + json.dumps({
        "source": str(unit_path),
        "source_object": SOURCE_OBJECT,
        "output": str(output_path),
        "vertices": len(source.data.vertices),
        "polygons": len(source.data.polygons),
        "bounds": [list(low), list(high)],
    }, sort_keys=True))


if __name__ == "__main__":
    main()
