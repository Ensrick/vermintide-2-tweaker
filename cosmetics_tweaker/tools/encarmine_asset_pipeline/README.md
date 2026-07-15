# Encarmine helmet asset pipeline

Issue #612 uses the vanilla Laurel Helm as the rendered unit. It does **not**
re-export its geometry. This is the required architecture, not a fallback.

The donor unit already contains the behavior that previous custom-unit builds
lost:

- eight meshes: three armor LODs, three skinned plume LODs, and two shadow
  proxies;
- the original normals, tangents, UVs, bounds, and render flags;
- one three-step LOD object;
- the 13-bone Laurel hierarchy and six dynamic plume joints;
- the native plume controller/jiggle behavior and camera FadeSystem contract;
- the native armor and alpha-feather material graphs.

`_cos_custom_hats.lua` changes only the six texture bindings on the spawned
Laurel material instances. Ordinary Laurel hats share the resource path but are
not changed because the override is applied only to `cos_encarmine_hat` spawn
surfaces.

## Authored inputs

Only the armor and plume diffuse RGB are authored. The committed diffuse files
are byte-identical copies of the user's `_encarmine` PNGs:

- armor: `1E3A23798DF61BDC940C9E1D3CD42607078118A487420E02345D4C59B30912E7`;
- plume: `B5925708AB95BEFF7B800FCAD717F308BCFB173E8069343D3AADE83FC282954D`.

The authored plume PNG already carries the donor's fractional alpha byte for
byte. The following non-color inputs remain byte-identical to Laurel:

- armor normal and combined/packed maps;
- plume normal and combined/packed maps;
- plume diffuse alpha.

Both native materials expose the same slots:

| Role | Slot |
|---|---|
| diffuse | `texture_map_c0ba2942` |
| normal | `texture_map_59cd86b9` |
| combined | `texture_map_b788717c` |

The compiled geometry array is shadow, plume x3, armor x3, shadow, but
`Unit.mesh` does not expose that array order: every mesh record carries a
one-based `geometry_index`, and Laurel references the geometry array in reverse.
Following those references gives runtime meshes 1-3 -> armor material
`1903313B`, meshes 4-6 -> plume material `BD15BFF9`, and meshes 0/7 -> shadow
material `5ED8F236`. The validator derives and compares this semantic mapping;
never infer paint roles from the geometry array position alone.

## Rebuild plume diffuse

Merge the reviewed charcoal RGB with Laurel's exact coverage alpha:

```powershell
py -3 repair_plume_texture.py <encarmine-color.png> <laurel-diffuse.png> `
  <repo>/cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_diffuse.png
```

The output `.texture` must retain DXT5 alpha with
`enable_cut_alpha_threshold = false`. Do not threshold or duplicate plume
faces; those two workarounds produced the tape-like card and invisible feather.

## Compiled donor proof

`laurel_scene_contract.json` records the reviewed compiled structure. Validate
the extracted donor through Blender + Bitsquid Blender Tools:

```powershell
blender --background --python validate_laurel_resource.py -- `
  <bitsquid-blender-tools> <compiled-resource-root> laurel_scene_contract.json
```

The required result is:

```text
ENCARMINE_LAUREL_COMPILED_CONTRACT=OK meshes=8 lod_steps=3 materials=3
```

This parses the compiled `.unit` and compares material mappings, mesh object
metadata, skin indices, render flags, LOD ranges, and LOD membership. A mere
file-existence check is insufficient.

## Repository gates

```powershell
pwsh -NoProfile -File qa/check_custom_unit_bundle_reachability.ps1
qa/lua/vendor/lua-5.1.5-win64/lua5.1.exe -e `
  "package.path='qa/lua/?.lua;qa/lua/tests/?.lua;'..package.path; local H=require('harness'); require('test_cos_custom_hats')(H,'.'); assert(H.run())"
```

The old FBX/custom-material scripts remain historical diagnostics only. They
must never be selected by runtime item or preview paths.

## Lessons learned and default rule for future recolors

The completed Encarmine work establishes the default architecture for any
future cosmetic that keeps a vanilla shape:

1. **Treat the compiled donor as behavior, not merely geometry.** Keep its
   skeleton, cloth controller, LOD graph, bounds, shadow meshes, material
   graphs, attachment links, and camera-fade participation by retaining the
   exact donor unit.
2. **Author only the channels that actually need to change.** For a recolor,
   replace diffuse RGB on the spawned material instances. Preserve donor alpha,
   normals, tangents, and packed material maps unless the new design has a
   reviewed reason to change one of them.
3. **Resolve material ownership semantically.** Compiled geometry-array order
   is not runtime `Unit.mesh` order. Follow each mesh's `geometry_index` and
   material reference, then validate the expected armor/plume role. Numeric
   position guesses caused the helmet and feather textures to be reversed.
4. **Never mutate the shared material resource.** Bind textures only on the
   exact spawned item instance so the ordinary Laurel Helm and other wearers
   remain unchanged.
5. **Do not repair alpha cards with thresholding or duplicated faces.** Preserve
   the donor's fractional coverage alpha and alpha-aware material. Those
   workarounds produced the invisible feather and tape-like rectangle.
6. **Keep package-facing identity vanilla-safe.** Inventory, preview, and peer
   synchronization records point at the resident donor. A custom resource must
   not be submitted to `PackageManager` merely because Lua can name it.
7. **Prove structure offline, then verify every renderer.** The gates above
   must pass before build. In game, inspect inventory/hero preview, owner 3P,
   remote husk, hot join, lobby/score, plume motion, near-camera fade, and an
   unmodified donor control.

If a future cosmetic changes geometry rather than color alone, that is a new
rig-preservation project. It must prove every donor contract item explicitly;
the recolor path must not be generalized into an FBX replacement path.
