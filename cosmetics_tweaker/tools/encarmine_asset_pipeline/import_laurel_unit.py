"""Import the original Foot Knight Laurel helmet with its feather rig.

Run with Blender 3.6/4.x in background mode. The script intentionally imports
the compiled vanilla unit without materials, preserving geometry, skin weights,
the feather armature, and the state-machine animation list for inspection.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import bpy


class Reporter:
    def report(self, levels, message):
        print(f"[bitsquid:{','.join(sorted(levels))}] {message}")


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1 :]
    if len(args) != 4:
        raise SystemExit(
            "expected bitsquid_tools_dir extracted_root unit_relative_path output.blend"
        )
    tools = Path(args[0]).resolve()
    extracted = Path(args[1]).resolve()
    unit = extracted / args[2]
    out_blend = Path(args[3]).resolve()

    os.environ["IS_CI_PIPELINE"] = "1"
    sys.path.insert(0, str(tools))

    import bitsquid
    from bitsquid import resource_manager, utils
    from bitsquid.unit.import_compiled import UnitImporterVT2

    bitsquid.register()
    resource_manager.get_extract_dir_vt2 = lambda: str(extracted)
    utils.get_extract_dir_vt2 = lambda: str(extracted)
    utils.is_level_editor_enabled = lambda: False

    settings = bpy.context.scene.bitsquid_import_settings
    settings.lookup_idstrings = True
    settings.import_meshes = True
    settings.skip_low_lod = False
    settings.remove_invisible_meshes = False
    settings.import_custom_normals = True
    settings.import_blend_weights = True
    settings.import_vertex_colors = True
    settings.flip_uvs = True
    settings.import_texcoords = True
    settings.import_empties = True
    settings.import_joints = True
    settings.fallback_bones = False
    settings.node_parenting = True
    settings.import_simpleanims = False
    settings.import_materials = False
    settings.import_textures = False

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    importer = UnitImporterVT2(Reporter(), bpy.context, path=str(unit))
    importer.load()

    out_blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(out_blend))

    for obj in bpy.context.scene.objects:
        groups = sorted(group.name for group in obj.vertex_groups)
        print(
            f"[laurel-audit] name={obj.name} type={obj.type} "
            f"parent={obj.parent.name if obj.parent else '-'} groups={groups}"
        )
    print(f"[laurel-audit] saved={out_blend}")


if __name__ == "__main__":
    main()
