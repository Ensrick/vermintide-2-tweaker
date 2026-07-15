# Encarmine helmet asset pipeline

This directory is the clean-clone, build-proven recipe for the authored
Encarmine Helmet. Keep the editable image project and extracted Fatshark source
resources outside Git; keep every transformation script and final VMB source
asset in this repository.

## Inputs

- the unpacked Laurel Helm resources rooted at
  `units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07`;
- Bitsquid Blender Tools capable of importing compiled VT2 units;
- the user-authored Encarmine armor and plume diffuse maps.

The vanilla resources are reference inputs only and are not redistributed.

## Rebuild

1. Import the compiled Laurel unit into a Blender working file:

   ```powershell
   blender --background --python import_laurel_unit.py -- `
     <bitsquid-tools> <unpacked-root> `
     units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07.unit `
     <working>/laurel_rigged_reference.blend
   ```

2. Export the high-detail armor and plume while retaining the 13-bone Laurel
   armature, all six weighted dynamic feather joints, and reversed plume faces:

   ```powershell
   blender --background --python export_rigged_encarmine.py -- `
     <working>/laurel_rigged_reference.blend `
     <repo>/cosmetics_tweaker/units/cosmetics_tweaker/encarmine_hat/encarmine_hat.fbx
   ```

3. Repair the authored plume texture. This removes alpha values 0-15, promotes
   every retained feather texel to an explicit 255-alpha cutout, and lifts its
   RGB by 4x (retained-pixel median 21 to 84). Do not combine fractional source alpha
   with the compiler cut threshold; that v0.9.116 combination made the live
   plume disappear:

   ```powershell
   python repair_plume_texture.py <authored-plume.png> `
     <repo>/cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_diffuse.png
   ```

4. Apply the bounded armor-response correction to the v0.9.115 roughness map:

   ```powershell
   python tune_armor_response.py <v0.9.115-roughness.png> `
     <repo>/cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_roughness.png
   ```

5. Keep `encarmine_hat.bones` byte-reviewed with the exported armature. The SDK
   compiler requires a same-name textual `.bones` resource; it no longer accepts
   an inline `animation_blender_bones` list.

6. Run the package and Lua gates, then build only through VMBLauncher:

   ```powershell
   ./qa/check_custom_unit_bundle_reachability.ps1
   py -3 ./cosmetics_tweaker/tools/encarmine_asset_pipeline/validate_assets.py `
     ./cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat
   ./qa/check_lua_unit_tests.ps1
   ./tools/vmb-launcher/bin/Release/net9.0-windows/win-x64/publish/VMBLauncher.exe build cosmetics_tweaker --clean
   ```

The game-side Laurel animation controller source is not included in the Mod
Tools. `_cos_custom_hats.lua` therefore installs the already-resident compiled
controller once after each custom-unit spawn. Package-facing item data stays on
the Laurel unit, which both preloads that controller and provides the safe
fallback for peers without Cosmetics.

## Pinned output contract

- 372 authored plume faces, 744 exported render faces;
- 13 bones, including six `j_feather_*_dynamic` joints;
- alpha haze cutoff 15/255, retained alpha exactly 255, and texture-compiler
  cut alpha enabled;
- 4x plume RGB lift;
- v0.9.115 armor roughness multiplied by 0.90 (184 -> 166 paint,
  122 -> 110 metallic detail);
- no external sibling folder required by QA or CI.
