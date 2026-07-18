# Outrider Launcher Asset Pipeline

This asset-specific recipe implements the repository-wide
[`../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md`](../../docs/CUSTOM_WEAPON_MODEL_PIPELINE.md)
for issue #627. It converts a single user-supplied grenade-launcher model and
applies it to the `cwv_es_outrider_grenade_launcher` variant, replacing the
placeholder vanilla blunderbuss visual.

## Source

The maintainer supplied the archive directly. Unlike the Crowbill (#604) and
Greataxe (#597) assets, it is **not** a Sketchfab download and carries no
author, title, source URL, or license metadata. The only stable identity is the
archive hash; the pipeline verifies it before deriving anything.

| Field | Value |
|---|---|
| Archive | `fa676a4e-4636-40d5-a240-9398ec289edb.zip` |
| Archive SHA-256 | `CC1230D2FEAE0FCBFFA3FE099A3C0ECB2EE58BA4B84A6B716EF341208D3C6A76` |
| Extracted payload | `output.fbx`, `texture_pbr_20250901.png` (albedo), `texture_pbr_20250901_normal.png`, `texture_pbr_20250901_metallic-texture_pbr_20250901_roughness.png` (packed) |

The raw archive and its expanded payload stay OUTSIDE the public repository. The
canonical untracked home is `C:\Users\danjo\source\repos\_cwv_launcher_sources`
(the original archive is preserved unmodified in `Downloads`). The checked-in
wrapper verifies the archive SHA-256 if present before producing derived
resources and will not silently rebuild from a renamed or changed download.

## Rebuild

From the mod root:

```powershell
& .\tools\convert_launcher_assets.ps1
```

Pinned defaults: Blender 4.4 and ImageMagick 7.1.2 Q16-HDRI. The Blender helper
(`convert_launcher_mesh.py`) triangulates, collapse-decimates to a
`-TargetTris` budget (default 12,000; the raw capture is ~500,000), joins and
applies mesh geometry, normalizes the longest dimension to two Blender units,
places the inferred stock/butt at the origin with the barrel along positive X,
collapses the mesh to the short `launcher_mat` slot, and exports FBX using
`axis_forward=-Z` and `axis_up=Y`. The 1P export is duplicated to `_3p`.

The result is 11,999 triangles / 16,838 vertices, a 0.70 MB FBX in line with the
shipped Crowbill (0.15-0.70 MB) and Old Musket (0.58 MB) meshes.

### Texture channels

The source PBR set is albedo, tangent-space normal, and a single packed
metallicRoughness map. Channel statistics (R constant 1.0 pad, G peaked ~0.20, B
spatially varied) plus the Blender-4.2.8 authoring identify glTF
metallicRoughness packing, so the wrapper extracts:

- `roughness` <- packed **G** channel
- `metallic` <- packed **B** channel
- `ao` <- neutral white (the source carries no AO map)
- `albedo`, `normal` <- direct, capped at 2048px

If the metal reads too glossy/matte or too/under metallic in game, the
metallic/roughness channel assignment is the first data-free thing to swap; it is
not baked into geometry.

## Runtime integration

- `scripts/mods/character_weapon_variants/_cwv_launcher_family.lua` is the single
  source of truth for the custom unit path and the vanilla blunderbuss package
  anchors. It mirrors `_cwv_greataxe.lua`, trimmed to one model.
- The variant's `right_hand_unit` (in `_cwv_variant_catalog.lua`) resolves to
  `_om.launcher_family.UNIT`, so the wire/preview aliases always match.
- Package residency: the unit/material/texture globs are in CWV's master
  `character_weapon_variants.package`. Previewers borrow the vanilla blunderbuss
  3P package as a lifetime anchor (`_cwv_mod_unit_preview` provider list).
- Wire safety / missing-mod fallback: the custom 1P/3P paths forward-alias to the
  vanilla blunderbuss index in `NetworkLookup.inventory_packages`, so
  ProfileSynchronizer equip syncs are wire-safe and unmodded peers render the
  blunderbuss (issues #279/#399).

## Verification boundary

Compilation and bundle reachability prove residency, not visual correctness.
Before release, inspect owner 1P, owner 3P, remote husk, inventory and illusion
previews. The starting `right_hand_scale` / `right_hand_rotation` in
`_type_transforms.cwv_es_outrider_grenade_launcher` are placeholders: tune them
in game (WT 3P Hold-Pose tuner) at multiple yaw headings and bake the settled
values here. Stingray's axis frame is not Blender's default, so expect the
imported-FBX rotation to need adjustment.
