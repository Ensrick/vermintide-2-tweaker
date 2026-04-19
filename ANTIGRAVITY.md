# Vermintide 2 Tweaker — Antigravity Context

## Project Overview
A Vermintide 2 VMF mod named **"Tweaker"** with internal mod ID `t` (so VMF commands are `t <command>`).
Steam Workshop ID: **3704660429** (private, for personal use/sharing).
The mod targets Chaos Wastes ("deus" mode internally) gameplay tweaks.

## Directory Structure
```
vermintide-2-tweaker/
├── tweaker/                        ← mod source (build input)
│   ├── tweaker.mod                 ← VMF entry point
│   ├── settings.ini                ← boot_package reference
│   ├── resource_packages/
│   │   └── tweaker.package         ← lists lua files to bundle
│   └── scripts/mods/tweaker/
│       ├── tweaker.lua             ← hooks + commands
│       ├── tweaker_data.lua        ← VMF settings definitions
│       └── tweaker_localization.lua
├── upload/
│   ├── item.cfg                    ← Workshop upload config
│   ├── preview.jpg
│   ├── steam_appid.txt             ← copy of SDK's steam_appid.txt (552500)
│   └── content/                   ← files to upload to Workshop
├── _run_build.bat                  ← primary build script
├── build.bat                       ← alternate build script
├── deploy.ps1                      ← copies build output to upload/content and workshop
├── upload.ps1                      ← runs ugc_tool to push to Workshop
├── install_local.bat               ← local install without Workshop
└── TODO.md                         ← feature backlog
```

## Workflow: Local (dev) vs Workshop (main)

- **Local install = dev branch** — fast iteration, no Steam review, no certificates required.
- **Workshop = main branch** — requires Steam review to complete before subscribers get the update.

Always develop and test via local install. When ready to ship, deploy + upload to Workshop.

## Build
```
powershell -Command "& 'C:\Users\danjo\source\repos\vermintide-2-tweaker\_run_build.bat'"
```
Output goes to `tweaker\.build\OUT\`.

## Deploy (upload prep + workshop folder sync)
```
powershell -ExecutionPolicy Bypass -File "C:\Users\danjo\source\repos\vermintide-2-tweaker\deploy.ps1"
```
Copies bundles to `upload\content\` (with `.mod_bundle` extension) and to the Workshop folder (`552500\3704660429\`).

## Dev Install (build + deploy for in-game testing)

**The game loads from the real Workshop folder (`3704660429`), not the fake local ID.**
`user_settings.config` references `id = "3704660429"`, so always deploy there for dev testing.
`install_local.bat` / the `9000000001` folder are unused — do not use them.

Build then copy to the Workshop folder:
```bash
powershell -Command "& 'C:\Users\danjo\source\repos\vermintide-2-tweaker\_run_build.bat'"

OUT="c/Users/danjo/source/repos/vermintide-2-tweaker/tweaker/.build/OUT"
DEST="c/Program Files (x86)/Steam/steamapps/workshop/content/552500/3704660429"
for f in "$OUT"/*; do
    fname=$(basename "$f"); ext="${fname##*.}"
    if [ "$ext" = "mod" ]; then cp -f "$f" "$DEST/$fname"
    elif [ "$fname" = "${fname%.*}" ]; then cp -f "$f" "$DEST/${fname}.mod_bundle"; fi
done
```

Steam will not overwrite these files unless you push a new Workshop upload.

## Workshop Upload
**Must be run interactively by the user** — the Steam API refuses writes from background/automated processes.
Game must be **closed** when uploading.

```
cd "C:\Users\danjo\source\repos\vermintide-2-tweaker\upload"
"C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader\ugc_tool.exe" -c item.cfg
```

Type `Y` at the EULA prompt.

### ALWAYS verify after uploading
After every upload, check the Workshop page and confirm the **File Size is non-zero** (~1.3 MB expected). ugc_tool prints "Upload finished" even when content fails to transfer — the only reliable confirmation is the file size shown on the Workshop item page. A 0-byte item means subscribers get nothing and the mod will show `installed = false` in user_settings.config, causing it to silently skip loading.

### item.cfg — Critical: use absolute paths
Relative paths for `preview` and `content` fail silently with misleading errors.
**Always use absolute paths with forward slashes:**
```
preview = "C:/Users/danjo/source/repos/vermintide-2-tweaker/upload/preview.jpg";
content = "C:/Users/danjo/source/repos/vermintide-2-tweaker/upload/content";
```

## Known Errors & Fixes

### Workshop upload: "generic failure (probably empty content directory)" (0x2)
- **Cause:** `preview` or `content` in item.cfg were relative paths. The tool resolves them relative to its own exe location, not the cfg file location — despite what the README claims.
- **Fix:** Use absolute paths with forward slashes for both `preview` and `content`.

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
- Commands: `mod:command("win", "description", function() ... end)` — called as `t win` in VMF console
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
- Workshop content dir: `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3704660429\`
- SDK: `C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\`
- ugc_tool: `{SDK}\ugc_uploader\ugc_tool.exe`
- Build compiler: `{SDK}\bin\stingray_win64_dev_x64.exe`
- `tags` field is NOT valid in item.cfg — omit it entirely
- `apply_for_sanctioned_status = false` is valid and should be kept

## Currently Implemented Features
- Coin pickup multiplier (0.10x – 5.00x)
- Starting coins (0 – 3000)
- Shrine boon options count (1–5, default 4)
- Chest boon options count (1–5, default 3)
- Disable individual curses (9 curses)
- `t win` command — completes the current map
