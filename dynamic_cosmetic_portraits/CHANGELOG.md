# Changelog — Dynamic Cosmetic Portraits

## 0.1.16-dev (2026-07-01) -- Localization audit (no bugs found; mod has no settings page)

### Why
Repo-wide sweep for the VMF double-localize bug class: VMF's options module localizes each widget's `title`/`tooltip`/dropdown-option `text`/`unit_text` itself at menu build time, so a widget value written as `tooltip = mod:localize("key")` gets localized twice and renders wrapped in angle brackets. This mod was audited for that pattern and for stale/missing loc keys.

Nothing needed fixing. This mod removed its VMF settings page in v0.1.15-dev, so there are no widgets, no tooltips, no dropdowns, and no `setting_id` fields to double-localize. The only remaining loc key is `mod_description`, referenced once as `description = mod:localize("mod_description")` in `_data.lua` — this is the top-level mod-list description, the one place VMF does NOT auto-localize, so the explicit `mod:localize` is correct and stays. The description value already reads as plain human English (2 sentences, ASCII only, no em dashes, no percent signs, no angle brackets), so it was reviewed and left unchanged.

### Changed
- `dynamic_cosmetic_portraits.lua:4` — `MOD_VERSION` `0.1.15-dev` -> `0.1.16-dev`.
- No source/localization behavior changes: the audit found no widget-level double-localize, no missing loc keys, and no description rewrites were warranted.

### Tests
Not built/deployed per task scope. `/dcp_regression_test` scaffold unaffected (`localization_format_safe` still guards literal `%` in loc strings; the sole loc value has none).

### To verify
- In-game: this mod still shows no VMF settings page (unchanged from v0.1.15-dev); its mod-list entry description reads correctly with no stray angle brackets.

## 0.1.15-dev (2026-06-22) -- Remove the VMF settings page entirely (no options, no toggles)

### Why
User directive: "this mod doesn't really need any options or toggles. It simply does what it does." The mod's two settings — `dynamic_portraits` (portrait-swap on/off) and `enable_debug_logging` — were the only user-facing surface, and neither earns its keep: portrait swapping is the entire point of the mod, and the debug toggle gated a tiny amount of diagnostic output. Both are now hard-on, and VMF shows no settings page for this mod.

Portrait-swapping functionality is COMPLETELY UNCHANGED — only the options/menu surface was removed. The load-bearing `custom_gui_textures` registration in `_data.lua` (texture/material injection into the UI renderers) is untouched; it is not an "option," it's how the portraits reach the screen.

### Changed
- `dynamic_cosmetic_portraits.lua:4` — `MOD_VERSION` `0.1.14-dev` -> `0.1.15-dev`.
- `dynamic_cosmetic_portraits_data.lua` — removed the entire `options.widgets` tree (the `dynamic_portraits` checkbox + the `enable_debug_logging` checkbox) and set `is_togglable = false`, so VMF renders no settings page and no enable/disable toggle. Kept `name`, `description`, and the load-bearing `custom_gui_textures` block.
- `dynamic_cosmetic_portraits.lua` — `_dbg` / `_dbg_alert` no longer gate on `mod:get("enable_debug_logging")`; debug logging is always on (the mod has few debug features, so the volume is negligible).
- `dynamic_cosmetic_portraits.lua` — `_sync_portrait_settings()` no longer gates on `mod:get("dynamic_portraits")`; portrait swapping is always on.
- `dynamic_cosmetic_portraits.lua` — removed the now-dead `mod.on_setting_changed` handler (it only reacted to `dynamic_portraits`).
- `dynamic_cosmetic_portraits.lua` — `/portrait_diag` now reports `dynamic_portraits=always-on`; the `dbg_helpers_two_channel` regression check no longer flips the removed setting, it just verifies the helpers don't raise.
- `dynamic_cosmetic_portraits_localization.lua` — removed the orphaned `dynamic_portraits` / `dynamic_portraits_tooltip` / `enable_debug_logging` / `enable_debug_logging_tooltip` strings; kept `mod_description` (still referenced by `_data.lua`).

### Tests
Not built/deployed per task scope. `/dcp_regression_test` scaffold preserved (`dbg_helpers_two_channel` updated, `localization_format_safe` unaffected).

### To verify
- In-game: this mod no longer appears with a settings page in the VMF mod options menu (and has no enable/disable toggle there).
- Portraits still swap to match equipped Kruber Mercenary hats/outfits exactly as before.
- `/portrait_diag` reports `dynamic_portraits=always-on` and the same material-readiness/career state as before.

## 0.1.14-dev (2026-06-07) -- Back-fill: Workshop preview swap (item_preview.png -> preview.jpg) + version bump

### Why
Back-filled during the 2026-06-07 audit (`check_versions` flagged that MOD_VERSION `0.1.14-dev` had no matching CHANGELOG entry). The version was bumped to `0.1.14-dev` on 2026-05-26 but the CHANGELOG was never updated.

Best-effort attribution from source/asset timestamps and git working-tree state (no git commit isolates this version, and there is no in-source feature/behavior marker for it):
- The main lua was last touched 2026-05-26 13:23:44 -- AFTER v0.1.13 was finalized (2026-05-25 18:59). The only version-bearing delta in it is the `MOD_VERSION` constant `0.1.13` -> `0.1.14-dev`; no new hooks, commands, or behavioral markers were introduced.
- `itemV2.cfg` was touched 2026-05-26 13:24:26 (title suffix rewritten to ` v0.1.14-dev` by the launcher) and its `preview` field points at `preview.jpg`.
- The Workshop preview image was swapped: `item_preview.png` was deleted and replaced by a new `preview.jpg` (created 2026-05-26 13:23). This is the substantive change behind the bump -- a Workshop presentation refresh, not a code change.

**Uncertainty:** attribution is reconstructed from file timestamps + working-tree diff, not from a per-version commit. If v0.1.14-dev carried any additional unreviewed code change it is not visible in the source as a dated marker. The `itemV2.cfg` description body still reads "v0.1.13" (prose was not revised for this bump), consistent with a preview-asset/version-only change.

### Changed
- `dynamic_cosmetic_portraits.lua:3` -- `MOD_VERSION` bumped `0.1.13` -> `0.1.14-dev`.
- `itemV2.cfg:1,3` -- title suffix `v0.1.14-dev`; `preview = "preview.jpg"`.
- `item_preview.png` (removed) / `preview.jpg` (added) -- Workshop preview image swapped to JPG.

### Tests
None -- documentation-only back-fill. No code change, so no new regression check. Existing `/dcp_regression_test` scaffold (`dbg_helpers_two_channel`, `localization_format_safe`) is unaffected.

### To verify
- Workshop item page shows the new `preview.jpg` thumbnail (not the old `item_preview.png`).
- In-game load banner / `/dcp_regression_test` header reports `v0.1.14-dev`.

## 0.1.13 (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Dynamic Cosmetic Portraits v" .. MOD_VERSION)` startup line from every mod. dcp is still 0.x (no track suffix, but version starts with `0.`) so it counts as in-flight: the user can't tell at a glance which patch is running. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable (>=1.0.0) versions stay silent.

### Changed
- `dynamic_cosmetic_portraits.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. The `^0%.` branch is what fires for dcp (no suffix). When any branch fires, `mod:echo("[dcp] v<MOD_VERSION> loaded")` runs once.

## 0.1.12 (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[dcp] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- dynamic_cosmetic_portraits.lua -- removed the load-time `mod:echo("dynamic_cosmetic_portraits v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[dcp] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("dynamic_cosmetic_portraits v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build dynamic_cosmetic_portraits -- verification only. NOT deployed, NOT uploaded.

This mod was split out of `cosmetics_tweaker` on 2026-05-06. The full
pre-split development history of the portrait system (v0.7.37–v0.7.102 and
the v0.8.0–v0.8.4-dev cosmetics_tweaker line) lives in
[../cosmetics_tweaker/CHANGELOG.md](../cosmetics_tweaker/CHANGELOG.md) — keep it as the
authoritative archive of how the system was researched and stabilised.

## 0.1.11 (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- dynamic_cosmetic_portraits_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- dynamic_cosmetic_portraits.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build dynamic_cosmetic_portraits -- verification only. NOT deployed, NOT uploaded.

## [2026-05-25 v0.1.10] — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[dcp] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `dynamic_cosmetic_portraits.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[dcp] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.1.10.

## [2026-05-25 v0.1.9] — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `dynamic_cosmetic_portraits.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added new `_RT_CHECKS` regression scaffold (`/dcp_regression_test`) with `dbg_helpers_two_channel` check (dcp had no regression command before).
- `itemV2.cfg` — bumped to v0.1.9.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified.

## [2026-05-25 v0.1.8] — Standardize Debug Logging toggle (universal convention)
### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). dcp previously had no debug toggle — added.

### Changed
- `dynamic_cosmetic_portraits_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of `options.widgets`, top-level (NOT inside any group).
- `dynamic_cosmetic_portraits_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `dynamic_cosmetic_portraits.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[dcp:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.1.8.

### Notes
- No existing debug key to rename (dcp had none).

## [2026-05-20 v0.1.7] — Add Sellsword's Twinplume portrait
### Added
- Kruber Mercenary hat `mercenary_hat_0005` (Sellsword's Twinplume). Generated via `tools/add_portrait.ps1` from the 110x130 source PNG; alpha mask borrowed from the canonical `mercenary_hat_0001` reference.

## [2026-05-08 v0.1.6] — Fix Spoils of War crash + cover all known portrait-bearing views
### Fixed
- **Crash on Spoils of War loot menu** with same error shape as v0.1.5 (`Material 'portrait_kruber_mercenary_hat_1002' not found in Gui` at `ui_passes.lua:134`). Root cause clarification: Lua 5.1's **tail-call elimination** strips the inner-factory frames (`view_settings.ui_renderer_function` → `IngameUI:create_ui_renderer`) from the call stack. So when `hero_view_state_loot.lua:271` calls `self.ingame_ui:create_ui_renderer(world)`, VMF's frame-4 traceback parser lands on `hero_view_state_loot.lua`, NOT on `ingame_ui_settings.lua`. The v0.1.5 fix happened to mask the pause-menu case for a different reason (HeroView's caller chain may not have been fully tail-called), but did not generalize.
- Added every portrait-bearing entry-point file we could identify from the VT2 source's `create_ui_renderer` call sites: `hero_view`, `hero_view_state_loot` (Spoils of War), `hero_view_state_store` (Emporium), `hero_view_state_weave_forge` (Athanor), `start_game_state_settings_overview`, `store_item_purchase_popup`, `store_welcome_popup`, `game_mode_map_deus` (Chaos Wastes map), and `ui_manager`. Plus the existing `ingame_ui`, `ingame_ui_settings`, `level_end_view_base`, `level_end_view_versus`.

## [2026-05-08 v0.1.5] — Fix pause-menu crash (inject into ingame_ui_settings + level_end)
### Fixed
- **Crash on clicking any pause-menu button** with `Material 'portrait_kruber_mercenary_hat_0009' not found in Gui` at `ui_passes.lua:134`. Root cause: VMF's `inject_materials` keys off the basename of the lua file that called `UIRenderer.create`, and we only registered `"ingame_ui"`. The pause menu's HeroView / OptionsView / CharacterSelection / StartMenu / StartGame all get their renderer from `scripts/ui/views/ingame_ui_settings.lua` (lines 648, 650, 726, 728), so those views' Gui handles never received our portrait materials and crashed the moment they tried to draw a unit frame referencing one. Same shape would have hit at end-of-mission via `level_end_view_base` / `level_end_view_versus`.
- Refactored `dynamic_cosmetic_portraits_data.lua` to derive `ui_renderer_injections` from a single `_texture_names` list and a `_renderer_creators` list, instead of two parallel hand-maintained 33-line literals. Now adding a portrait only requires touching one list (after running `tools/add_portrait.ps1`).

### Renderer creators now covered
- `ingame_ui`
- `ingame_ui_settings` ← **the missing one that caused the crash**
- `level_end_view_base`
- `level_end_view_versus`

## [2026-05-07 v0.1.4] — Codify the workflow against future mistakes
### Added
- **`tools/add_portrait.ps1`** — single-command portrait asset generator.
  Encodes the only correct workflow: medium = source verbatim 110×130, HUD
  and small = bicubic-resize RGB + alpha channel borrowed from the
  `mercenary_hat_0001` reference variants. Generates `.png` / `.texture` /
  `.material` files, verifies output alpha at corners, prints next manual
  steps. Re-running it on Plumed Horseshoe produces functionally identical
  output to v0.1.3 (verified).
- **`CLAUDE.md` at the mod root** — workflow guardrails for AI agents,
  recurring failure modes table, in-game diagnostic command list.
- **DEVELOPMENT.md prominent banner** at the top — points at the script,
  enumerates the failure modes from v0.1.0 / v0.1.1 / v0.1.2 / v0.1.3.
- **Tripwire comments in `dynamic_cosmetic_portraits.lua`** above
  `_PORTRAIT_MATERIALS`, `_hat_portrait_map`, and `_skin_portrait_map`,
  warning that adding entries without running the script first crashes
  in-game with "Material not found in Gui".
- **Tripwire comment in `dynamic_cosmetic_portraits_data.lua`** above
  `custom_gui_textures`.
- **Repo-root `CLAUDE.md`** Key Reference Files updated with the new
  script and child CLAUDE.md.

### Why
Three shipped versions broke the same way (different specific guesses,
same root cause: free-handing the asset pipeline instead of borrowing
the alpha mask from a working portrait). Encoding the workflow in a
script + tripwires + a child CLAUDE.md should make accidental regression
much harder.

## [2026-05-07 v0.1.3] — Plumed Horseshoe alpha-mask fix + correct workflow doc
### Fixed
- **`mercenary_hat_0003` (Plumed Horseshoe) HUD/small overflow.** Both
  v0.1.1 (bicubic resize, no alpha) and v0.1.2 (110×130 verbatim under all
  three names, also no alpha) shipped HUD and small variants without the
  hex/shield-shaped alpha mask that defines the visible silhouette inside
  the in-game frame widget's hex cutout. Without the mask, RGB content at
  the canvas corners pokes past the frame's cutout edge — observed as
  "overflow" in-game. Fix: HUD (86×108) and small (60×70) now use the RGB
  content bicubic-downscaled from the 110×130 source PLUS the alpha channel
  copied verbatim from the corresponding `mercenary_hat_0001` (Estalia)
  reference variant. The medium (110×130) stays as a verbatim copy of the
  source — no mask needed at hero-select size.

### Documentation
- **DEVELOPMENT.md workflow rewritten** with the correct three-step asset
  generation (medium = source verbatim; HUD = resize 86×108 + alpha from
  reference; small = resize 60×70 + alpha from reference). Includes the
  PowerShell snippet that produces all three variants from a single source.
- Earlier doc revisions in v0.1.1 and v0.1.2 had the workflow wrong in
  different ways — neither acknowledged that HUD/small need shaped alpha
  borrowed from a reference portrait.

## [2026-05-06 v0.1.2] — Plumed Horseshoe (still broken — superseded by v0.1.3)
### Added/changed
- Replaced v0.1.1's bicubic-resized HUD/small with verbatim 110×130 copies.
  Still wrong: HUD/small at 110×130 still lack the hex-shaped alpha mask,
  and the engine's scale-down to widget size doesn't add a mask. Overflow
  persisted; fixed in v0.1.3.

## [2026-05-06 v0.1.1] — Plumed Horseshoe portrait (broken — superseded by v0.1.2)
### Added
- `mercenary_hat_0003` ("Plumed Horseshoe") with bicubic-downscaled HUD
  and small variants but no alpha mask. Caused visible content to extend
  past the in-game frame's hex cutout.

## [2026-05-06 v0.1.0] — Initial split from cosmetics_tweaker
### Added
- New standalone mod (Workshop ID `3721036701`, private). Wraps the dynamic
  portrait system that previously shipped inside `cosmetics_tweaker`.
- Includes 10 portrait sets (8 Kruber Mercenary hats + 2 outfits — Felix
  and VT1 Champion of Ubersreik).
- `dynamic_portraits` toggle (default ON).
- `portrait_diag`, `portrait_dump`, `test_portrait` console commands.
- `CHARACTER_COSMETIC_CATALOG.md` moved here (it's exclusively a
  portrait-authoring reference).

### Architecture
Identical to the pre-split design (see ../cosmetics_tweaker/CHANGELOG.md
v0.7.62 entry):
- Single source-of-truth swap of `SPProfiles[5].careers[1].portrait_image`
  and `.picking_image` — every UI surface that builds portrait textures from
  career_settings updates automatically (HUD, hero selection, ESC menu, tab
  overlay, end-of-round, matchmaking).
- `_check_portrait_materials_ready()` probes `Gui.material()` directly,
  since VMF bypasses the `UIRenderer.create` hook used pre-v0.7.52.
- Skin/outfit portraits override hat portraits because outfits replace
  Kruber's head model regardless of equipped hat.

### Carried-over from pre-split
- `_gui_has_material()` and `_flush_log()` are duplicated as locals here
  rather than imported, so this mod has no runtime dependency on
  cosmetics_tweaker.
- `NewsFeedUI:draw` hot-reload safety hook stayed in cosmetics_tweaker —
  it protects illusion/LA atlases, not portrait materials.
- `_get_hat_item_key_for_unit` was deleted (was an orphan).

### Known limitations (post-split)
- Only Kruber Mercenary is covered. Other characters/careers need new
  Photoshop portraits + new entries in `_hat_portrait_map` / `_skin_portrait_map`.
- Hot-reload (Ctrl+Shift+R) is unsafe — engine-level resource locks on
  loaded materials/textures. Always restart VT2 after redeploying.
