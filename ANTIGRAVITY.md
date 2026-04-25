# Vermintide 2 Tweaker — Antigravity Context

## Project Overview
A modular set of Vermintide 2 VMF mods split from the original monolithic **"Tweaker"**.

| Mod | Internal ID | VMF Console Prefix | Workshop ID | Status |
| :--- | :--- | :--- | :--- | :--- |
| Chaos Wastes Tweaker | `ct` | `ct <command>` | **3712929235** | ✅ Uploaded |
| Weapon Tweaker | `wt` | `wt <command>` | **3712896117** | ✅ Uploaded |
| Career Tweaker | `crt` | `crt <command>` | TBD | Not started |
| ~~Tweaker (legacy)~~ | `t` | `t <command>` | 3704660429 | Deprecated — split into above |

## Directory Structure
```
vermintide-2-tweaker/
├── weapon_tweaker/                 ← Weapon Tweaker mod source
│   ├── wt.mod                      ← VMF entry point (internal ID: "wt")
│   ├── settings.ini
│   ├── resource_packages/
│   │   └── weapon_tweaker.package
│   ├── scripts/mods/weapon_tweaker/
│   │   ├── weapon_tweaker.lua
│   │   ├── weapon_tweaker_data.lua
│   │   └── weapon_tweaker_localization.lua
│   ├── upload/
│   │   ├── item.cfg                ← Workshop upload config (NOT used directly — see Upload section)
│   │   ├── preview.jpg
│   │   └── content/               ← deploy target for built bundles
│   └── .build/OUT/                 ← compiler output (generated)
├── chaos_wastes_tweaker/           ← Chaos Wastes Tweaker mod source (same structure as above)
├── career_tweaker/                 ← Career Tweaker (future)
├── tweaker/                        ← LEGACY — original monolithic mod (deprecated)
├── upload/                         ← LEGACY — original tweaker's upload staging
├── _run_build.bat                  ← primary build script
├── build.bat                       ← alternate build script
├── deploy.ps1                      ← legacy deploy (tweaker only)
├── deploy_all.ps1                  ← deploys all mods to upload/content
├── upload.ps1                      ← legacy upload (tweaker only)
├── upload_all.ps1                  ← uploads all mods to Workshop (NEEDS FIX — see below)
└── install_local.bat               ← local install without Workshop
```

## Workflow: Dev iteration vs Workshop upload

- **Dev iteration:** Build, then deploy directly to the Workshop content folder (`552500/<workshop_id>`) and hot reload in-game. The game loads mods from the real Workshop folder — fake local IDs (e.g. `9000000002` via `install_local.bat`) do NOT work for separately-published Workshop mods.
- **Workshop upload:** When ready to ship to subscribers, use the upload workflow (see below). Requires Steam review before subscribers get the update.

### Adding weapons incrementally
Add one weapon at a time to `weapon_unlock_map` and verify in-game before adding more. Adding all weapons at once risks crashes from animation/model mismatches that are hard to diagnose in bulk.

## Build
```
powershell -Command "& 'C:\Users\danjo\source\repos\vermintide-2-tweaker\_run_build.bat'"
```
Output goes to `<mod>\.build\OUT\`.

## Deploy (upload prep + workshop folder sync)
```
powershell -ExecutionPolicy Bypass -File "C:\Users\danjo\source\repos\vermintide-2-tweaker\deploy_all.ps1"
```
Copies bundles to each mod's `upload\content\` directory (with `.mod_bundle` extension).

## Workshop Upload — THE PROVEN METHOD

> **CRITICAL**: The ugc_tool resolves relative paths from the **config file's parent directory**, but ONLY when the tool's working directory is the SDK's `ugc_uploader` folder. This is the single most important fact about uploading.

### Step-by-step (proven working 2026-04-23):

1. **Stage files** into the SDK's sample_item directory:
   ```powershell
   $sdk = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader\sample_item'
   Remove-Item "$sdk\content\*" -Force
   Copy-Item 'weapon_tweaker\upload\content\*' "$sdk\content\" -Force
   ```

2. **Write the item.cfg** in the SDK's sample_item folder:
   ```ini
   title = "Weapon Tweaker";
   description = "Weapon unlock and runtime experimentation for Vermintide 2. Requires VMF.";
   preview = "preview.jpg";
   content = "content";
   language = "english";
   visibility = "public";
   published_id = 3712896117L;
   apply_for_sanctioned_status = false;
   ```
   - `preview` and `content` are **relative** to the config file location
   - `published_id` uses the `L` suffix (64-bit integer literal)
   - Semicolons required on every line (parsed by `libconfig.dll`)
   - For a **new** item, set `published_id = 0L;` — the tool will populate it after creation

3. **Run the upload** from the SDK directory:
   ```powershell
   Set-Location 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader'
   'Y' | & .\ugc_tool.exe -c sample_item\item.cfg -x
   ```

4. **Verify** on the Workshop page that **File Size is non-zero** (~1.3 MB expected).

### Why this works (and nothing else did)
- The tool loads `libconfig.dll` and `steam_api.dll` from its own directory. It must be run with the SDK folder as its working directory.
- Relative paths in the config are resolved from the config file's parent directory — but only when the above condition is met.
- Absolute paths from other directories fail silently with misleading `0x9` errors.
- Previously-deleted Workshop item IDs become permanently invalid — always use `published_id = 0L;` for new items.
- The tool adds `tags = [ ];` automatically after a successful upload — do NOT add it manually.

### ALWAYS verify after uploading
After every upload, check the Workshop page and confirm the **File Size is non-zero** (~1.3 MB expected). ugc_tool prints "Upload finished" even when content fails to transfer — the only reliable confirmation is the file size shown on the Workshop item page. A 0-byte item means subscribers get nothing.

## Known Errors & Fixes

### Workshop upload: "file not found; invalid workshop item" (0x9)
- **Cause 1:** The `published_id` references a deleted or non-existent Workshop item.
- **Fix:** Set `published_id = 0L;` to create a new item.
- **Cause 2:** Running the tool from any directory other than the SDK's `ugc_uploader` folder.
- **Fix:** Always `Set-Location` to the SDK folder before running. See Upload section.
- **Cause 3:** `preview.jpg` or `content/` directory doesn't exist at the resolved path.
- **Fix:** Verify files exist. Use relative paths from the config file's location inside the SDK `sample_item` folder.

### Workshop upload: "generic failure (probably empty content directory)" (0x2)
- **Cause:** The tool found the config but couldn't resolve the `content` path to an actual directory with files.
- **Fix:** Stage content into `SDK/ugc_uploader/sample_item/content/` and use `content = "content";` (relative).

### Workshop upload: "invalid param" (0x8)
- **Cause:** Game was running while uploading, or Steam session stale.
- **Fix:** Close the game. Run upload from user's own terminal (not automated).

### Workshop upload: "access denied" (0xf) on item creation
- **Cause:** Game was running, blocking the Steam app session.
- **Fix:** Close the game before running ugc_tool.

### Mod shows in launcher but not in VMF F4 menu — "not found in the workshop folder"
- **Cause:** Workshop item is pending Steam's automated review. Steam hasn't synced the download yet, so `mod.bin` and `mod.cer` (EAC certificates required by ModManager) are missing from the Workshop folder. Manually placing bundle files there is not enough.
- **Fix:** Use `install_local.bat` (fake ID `9000000001`, bypasses certificate check via `developer_mode`). Once Steam review clears and the item is downloadable, unsubscribe + re-subscribe to get a clean certified download.

### Game crash: bundle hash not found (e.g. `05a4cebb8c3c93bf.mod_bundle not found`)
- **Cause:** Build output files have no extension, but the game requires `.mod_bundle` extension.
- **Fix:** When copying to Workshop folder or upload/content, rename each bundle file from `{hash}` to `{hash}.mod_bundle`. The `.mod` file is copied as-is.

### VMF hook error: `trying to hook function or method that doesn't exist: [BackendUtils.can_wield_item]`
- **Cause:** `BackendUtils.can_wield_item` is not hookable from separately-loaded Workshop mods. The old monolithic tweaker could hook it due to load-order timing, but split-out mods cannot — regardless of whether the hook is at init time, deferred in `mod.update`, or uses string-form class names.
- **Fix:** Don't hook `BackendUtils.can_wield_item` at all. Instead, modify `ItemMasterList[weapon_key].can_wield` directly (add the career name to the list). This is how AnyWeapon (reference mod) handles it. Use `ItemGridUI._on_category_index_change` for inventory filter patching.

### VMF hook error: `argument 'obj' should have the 'string/table' type, not 'nil'`
- **Cause:** Passing the class directly (e.g. `mod:hook(DeusRunController, ...)`) when the class isn't loaded yet at mod init time.
- **Fix:** Always pass the class name as a string: `mod:hook("DeusRunController", ...)`. VMF resolves it lazily when the hook fires.

### Lua crash: `attempt to call field 'unpack' (a nil value)`
- **Cause:** Vermintide 2 uses Lua 5.1 which has global `unpack()`, not `table.unpack()`.
- **Fix:** Always use `unpack(args)`, never `table.unpack(args)`.

### Coin multiplier not working (wrong argument index)
- **Cause:** `on_soft_currency_picked_up(amount, unit)` — the amount is `args[1]`, not `args[2]`.
- **Fix:** Read and multiply `args[1]`.

### VMF setting slider shows `<x>` / localization failure
- **Cause:** `unit_text = "x"` is treated as a localization key by VMF and fails lookup.
- **Fix:** Remove `unit_text` and `tooltip` fields from widget definitions.

### Wrong package path in .mod file
- **Cause:** Extra subdirectory in package path (`resource_packages/tweaker/tweaker` instead of `resource_packages/tweaker`).
- **Fix:** The package path should match the `.package` filename without extension.

## Key Technical Facts

### Lua / VMF
- Lua 5.1: use `unpack()` not `table.unpack()`
- Commands: `mod:command("win", "description", function() ... end)` — called as `wt win` in VMF console
- Hook with return: `mod:hook(Class, "method", function(func, self, ...) ... return func(self, ...) end)`
- Hook without return: `mod:hook_safe(Class, "method", function(self, ...) ... end)`
- Settings: `mod:get("setting_id")` reads current value
- Logging: `mod:info(...)`, `mod:echo(...)` (echo shows in chat)

### Chaos Wastes Internals
- Chaos Wastes = "deus" mode internally
- Coin system: `DeusRunController:on_soft_currency_picked_up(amount, unit)`
- Boon selection: `DeusPowerUpUtils.generate_random_power_ups(...)` — default count 4 for shrines, 3 for chests
- Curses/mutators: `Mutator:activate()` — name in `self._name`, `self:name()`, or `self.mutator_name`
- Win trigger: `Managers.state.game_mode:complete_level()`
- Run init: `DeusRunController:init()`

### Workshop / Build
- Steam App ID: 552500
- SDK: `C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\`
- ugc_tool: `{SDK}\ugc_uploader\ugc_tool.exe`
- Build compiler: `{SDK}\bin\stingray_win64_dev_x64.exe`
- Upload staging: `{SDK}\ugc_uploader\sample_item\` (the tool's native staging area)
- `apply_for_sanctioned_status = false` is valid and should be kept
- `tags = [ ];` is added automatically by the tool — do NOT add it manually before first upload
- Semicolons are REQUIRED on every line in item.cfg (parsed by libconfig)
- The `L` suffix is REQUIRED on `published_id` (64-bit integer literal)

## Useful Paths
- **Game Logs**: `%APPDATA%\Fatshark\Vermintide 2\console_logs`
- **Workshop Content**: `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\`
- **Local Mod Folder**: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\mods` (used by `install_local.bat`)
