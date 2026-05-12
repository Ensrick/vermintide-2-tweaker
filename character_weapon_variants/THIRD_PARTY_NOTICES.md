# Third-Party Notices

The Character Weapon Variants mod for Vermintide 2 incorporates third-party
assets that are governed by their own licenses. The mod's own code is MIT
licensed (see the repository root `LICENSE` file); the notices below cover the
assets the MIT license does not extend to.

## "Old Musket" 3D model

Used as the visual mesh for the `cwv_es_musket_old` weapon variant. Files
shipped under this attribution:

- `units/cwv_es_musket_custom/cwv_es_musket_custom.fbx`
- `units/cwv_es_musket_custom/cwv_es_musket_custom_3p.fbx`
- `units/cwv_es_musket_custom/cwv_es_musket_custom.unit`
- `units/cwv_es_musket_custom/cwv_es_musket_custom_3p.unit`
- `textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo.{png,texture}`
- `textures/cwv_es_musket_custom/cwv_es_musket_custom_ao.{png,texture}`
- `textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic.{png,texture}`
- `textures/cwv_es_musket_custom/cwv_es_musket_custom_normal.{png,texture}`
- `textures/cwv_es_musket_custom/cwv_es_musket_custom_roughness.{png,texture}`

| Field | Value |
|-------|-------|
| Title | Old Musket |
| Author | Lathander |
| Author profile | https://sketchfab.com/Lathander |
| Source | https://sketchfab.com/3d-models/old-musket-48f60e8cc54f4e64961f2e3ebcac5432 |
| License | Creative Commons Attribution 4.0 International (CC-BY 4.0) |
| License URL | https://creativecommons.org/licenses/by/4.0/ |

### Changes made to the original

To embed the model in the Vermintide 2 Stingray engine, the following purely
technical conversions were applied. No artistic changes were made.

- Geometry converted from Collada `.dae` to Autodesk `.fbx` via Blender 4.4.
- All material slots renamed to a single short name (`rifle_mat`) so the
  Stingray `.unit` file can bind the engine's vanilla rifle material.
- A duplicate of the mesh was exported as `_3p.fbx` for use as the third-person
  variant alongside `_1p`.
- Source PBR textures (`01 - Default_albedo.jpg`, etc.) converted to PNG and
  renamed to `cwv_es_musket_custom_<channel>.png` to match the engine's
  texture-import naming convention. No color, normal, or roughness data was
  re-authored.

### License text

Creative Commons Attribution 4.0 International (CC-BY 4.0). The full license
is available at https://creativecommons.org/licenses/by/4.0/legalcode.

In short, you are free to share and adapt this asset for any purpose, including
commercially, provided you give appropriate credit, provide a link to the
license, and indicate if changes were made. This file fulfills those
obligations for the redistribution of the asset within this mod.
