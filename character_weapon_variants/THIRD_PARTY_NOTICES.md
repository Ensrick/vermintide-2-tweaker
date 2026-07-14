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

## Greataxe illusion 3D models

Issue #597 uses five independently licensed Sketchfab models as placeholder
illusions for the CWV Kruber Greataxe. The original download archives and
source-authoring files are not redistributed in this repository. The derived
FBX geometry and processed textures are shipped under these paths:

- `units/cwv_es_greataxe/axe_01/*` and `textures/cwv_es_greataxe/axe_01/*`
- `units/cwv_es_greataxe/axe_02/*` and `textures/cwv_es_greataxe/axe_02/*`
- `units/cwv_es_greataxe/axe_03/*` and `textures/cwv_es_greataxe/axe_03/*`
- `units/cwv_es_greataxe/axe_04/*` and `textures/cwv_es_greataxe/axe_04/*`
- `units/cwv_es_greataxe/axe_05/*` and `textures/cwv_es_greataxe/axe_05/*`

| Asset | Title | Author | Author profile | Source |
|-------|-------|--------|----------------|--------|
| `axe_01` | Battle Axe | Vlasov Daniil | https://sketchfab.com/dan741vlasov | https://sketchfab.com/3d-models/battle-axe-a6d3f8a9816e427d95648dfafe77714f |
| `axe_02` | Viking War Axe | Daniel Rodriguez | https://sketchfab.com/derodriguez | https://sketchfab.com/3d-models/viking-war-axe-220e559cd70a4cb9b73e4e19df23377e |
| `axe_03` | Viking Axe | wilhelmvonc | https://sketchfab.com/wilhelmvonc | https://sketchfab.com/3d-models/viking-axe-54992b8b04bd41d29476fe77bd2b6a8c |
| `axe_04` | Viking Axe | abbyrobb1417 | https://sketchfab.com/abbyrobb1417 | https://sketchfab.com/3d-models/viking-axe-5e2c48044a9045a2b24014fa59db3d8b |
| `axe_05` | Axe | Taylor | https://sketchfab.com/r.taylor | https://sketchfab.com/3d-models/axe-ae71823d5dc8451c96c7ca0f56d83a07 |

Each model is licensed under Creative Commons Attribution 4.0 International
(CC-BY 4.0): https://creativecommons.org/licenses/by/4.0/. Sketchfab's API
reported that exact license for each model UID on 2026-07-14.

### Changes made to the originals

- Source FBX, OBJ, or Collada geometry was imported and re-exported as FBX with
  Blender 4.4.
- Multi-object geometry was joined, all material slots were collapsed to the
  short Stingray-safe name `axe_mat`, the longest dimension was normalized to
  two Blender units, and the inferred handle butt was placed at the origin with
  the handle directed along positive X.
- Identical 1P and `_3p` FBX copies were emitted. Perspective-specific
  rotations, offsets, and scale remain user-tuned CWV/WT data rather than mesh
  edits.
- Source texture maps were converted to PNG and capped at 2048 pixels. Legacy
  gloss maps were inverted into roughness; legacy specular maps were converted
  to grayscale metallic approximations; absent AO maps use a neutral white
  fallback. No new artistic texture content was added.

The reproducible conversion scripts and source manifest live in
`tools/GREATAXE_ASSET_PIPELINE.md` and `tools/convert_greataxe_assets.ps1`.
