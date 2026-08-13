# Verminious Dreams Lighting — Changelog

## v1.0.19-dev - 2026-08-13 - #1287 clean artifact reconciliation

- Rebuilt the unchanged lighting implementation from one clean, source-addressable commit so the Lua version, Workshop title, tracked root bundle, BuildOnly receipt, release manifest, and publication receipt identify the same artifact.
- This is provenance-only reconciliation for issue #1287; no lighting profiles, settings, hooks, commands, or gameplay behavior changed.

## v1.0.18-dev - 2026-07-18 - complete stranded ship pipeline

- No source change. The pipeline-state ladder (PROJECT_STANDARDS 11b) flagged this stream stranded: v1.0.14-dev through v1.0.17-dev landed in git (last upload was 2026-07-13, before the shared-lib debug helper and the localization rework) but were never built or uploaded. This build ships all of it. PC-B remote deploy skipped this invocation (-NoRemote): PC-B unreachable.

## v1.0.17-dev - 2026-07-17 - #428 canonical copied debug helper [tooling]

- Replaced the entry file's behavior-identical `_dbg` / `_dbg_alert` definitions
  with the standalone bundled copy of `tools/shared_lib/_lib_debug.lua`.
- Registered VDL dev as an exact-copy consumer and added executable ownership
  tests, preserving gated `mod:debug` and guarded log-only `printf` alerts.

## v1.0.16-dev - 2026-07-13 - #427 _dbg_alert log-only via engine printf [untested]

- `_dbg_alert` rerouted mod:warning -> pcall-guarded engine printf (VMF warning channel posts to chat under default settings; printf survives mod-logging-OFF, never chat; enemy_tweaker issue 240 template). `verminious_dreams_lighting_dev.lua` only.

## v1.0.15-dev - 2026-07-12 - issue 510: mem-probe baseline is now file-local (no bare _G global)

### Why
Issue 510: `_MEM_PROBE_T0_VDL` was assigned as a bare `_G` global (no `local`), leaking a name into the global table for a value read only at the bottom of this same chunk. modded_progression fixed exactly this class in v0.2.14-dev (issue 434 / audit F7); the fix was never propagated to the vdl copy.

### Changed
- `verminious_dreams_lighting_dev.lua:4` - `_MEM_PROBE_T0_VDL` is now `local`, matching `modded_progression.lua:27`. Grep confirmed the only readers are the assignment (line 4) and the boot-footprint log line (line ~1252), both in this same chunk, so no cross-file reader needed updating.
- `MOD_VERSION` `1.0.14-dev` -> `1.0.15-dev`.

### Build
Built via VMBLauncher (compile-only). Not deployed/uploaded per task scope.

## v1.0.14-dev — 2026-07-01 — Menu wording pass: rewrote the mod description and all four option tooltips in plain, player-facing English (no internal level ids or engine jargon), removed em dashes and stray markup.

### Why
The mod description and per-mission tooltips leaned on internal terms (raw level ids like `dlc_termite_1`, `vdl` shorthand, "profile", per-light "override") that mean nothing to a player reading the settings menu.

### Changed
- `verminious_dreams_lighting_dev_localization.lua` — reworded `mod_description` and the four `*_tooltip` strings (`enable_dlc_termite_1/2/3_tooltip`, `enable_cw_curse_adjust_tooltip`) to describe what each toggle does in plain English. No internal ids, no engine terms, no em dashes. Meaning preserved from the prior text; no mechanics invented. Titles/labels unchanged.

### Notes
- No eager-localize conversions were needed: the widgets already use raw-key tooltips (`tooltip = "..."`), and the only `mod:localize` call is the correct top-level `description = mod:localize("mod_description")`.
- Key cross-check clean: all four setting_ids and all four tooltip keys already exist in the loc file; nothing added or renamed.

### Build
Built, deployed, and uploaded with v1.0.18-dev (2026-07-18).

## v1.0.13-dev — 2026-06-28 — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## v1.0.12-dev — 2026-06-24 — The Well of Dreams: brighten amb_top further (+40% more)

User: the +30% wasn't enough. Bumped `amb_top` another +40% → `{91, 91, 109}` (cumulative from the original `{50,50,60}`: ×1.82). Still tune-able live via `/vdl_*`.

## v1.0.11-dev — 2026-06-24 — The Well of Dreams: brighten the dark indoor/shadow ambient (+30%)

User feedback: The Well of Dreams (`dlc_termite_3`) was a bit too dark. Its darkest lighting channel is the upper-hemisphere ambient `amb_top` (`ambient_tint_top`) at `{50,50,60}` — the fill that lifts shadowed/indoor areas. Brightened it ~30% → `{65,65,78}` (×1.3). Other channels unchanged (`amb` {200,200,280}, `sun` {100,100,100}, `fog` {70,85,85}). Tune further live with the `/vdl_*` commands if needed.

## v1.0.10-dev — 2026-06-20 — Brighten Belakor curse a touch (Devious Delvings was too dark)

User feedback: the v1.0.9 CW curse lighting works well, but the **Belakor** curse on **Devious Delvings** (`dlc_termite_2`) was "a little too dark." That mission has the darkest vdl base profile (`fog = {24,24,24}`), and Belakor's vanilla seed `light_probe_tint` is `{0.76, 0.76, 1.0}` (it darkens R+G to 76%), so the multiply over-darkens it.

### Changed
- Seeded `_CURSE_ADJUST.belakor` with a small brightening: all six channels (sky/sun/sun2/amb/amb_top/fog) now use the multiplier `{0.85, 0.85, 1.0}` instead of falling back to the `{0.76, 0.76, 1.0}` vanilla seed. That lifts the R/G darkening from 0.76 → 0.85 (a ~12% relative lift, ~9 points of the multiplier range), leaving blue at 1.0 so Belakor keeps its cold hue. Done entirely in the existing multiply/brightness space — no hardcoded absolute color.
- **Conservative on purpose** — the user said "a little." Only Belakor is touched; the other four deities still fall back to their vanilla `light_probe_tint` seeds. The 0.09 lift is small.

### Fine-tuning (still fully in-game tunable)
- Re-tune live with `/vdl_curse belakor <channel> <r> <g> <b>` (float multipliers on top of vdl's base; channels sky/sun/sun2/amb/amb_top/fog), `/vdl_curse_exp belakor [mul]`, and `/vdl_curse_dump` to print a copy-paste block. `/vdl_curse_clear belakor [channel|all]` reverts to the `{0.76, 0.76, 1.0}` vanilla seed.
- **Caveat:** `_CURSE_ADJUST` keys per-THEME, not per-mission, so this also lightly brightens Belakor on `dlc_termite_1`/`_3`. Those have lighter bases and were reported fine, and the lift only *reduces* darkening (can't over-darken), so it's benign. If you want it scoped to `dlc_termite_2` alone, retune per-mission with the commands above after eyeballing the other two.

### Build
VMBLauncher.exe build verminious_dreams_lighting_dev — verification only. NOT deployed, NOT uploaded.

## v1.0.9-dev — 2026-06-21 — Chaos Wastes application + curse-adjustment framework

vdl now applies its mission lighting when its three missions are injected into a **Chaos Wastes** expedition, and layers a per-curse adjustment on top.

### Why
vdl's profiles previously keyed on an EXACT `level_id` match (`dlc_termite_1/2/3`), so they only fired in Adventure. In Chaos Wastes the same missions carry a permutation `level_id` of the form `<base>_<theme>_path<N>` (e.g. `dlc_termite_1_khorne_path1`, plus the duplicate-alias form `dlc_termite_1_dup1_khorne_path1`), so the exact match missed them and CW players got vanilla lighting. The user also wants the active curse to tint vdl's custom look while in CW.

### Changed — CW application (prefix match)
- Added `_resolve_profile_key(raw_key)`: exact match first (Adventure unchanged, byte-for-byte), then a `^<base>_` prefix scan against the three baked profile keys for the CW permutations. The base mission key is always a literal prefix of the permutation — the same convention `chaos_wastes_tweaker`'s `adventure_base_from_level_key` relies on. **No dependency on chaos_wastes_tweaker** — vdl only reuses the level_id naming pattern; it calls no ct API.
- `local_player_game_starts`, `shading_callback`, `on_setting_changed`, `_profile_for_current_level[_raw]`, and `vdl_level` now resolve the raw engine key down to the base profile key, so the base profile + per-mission VMF toggle apply on the CW permutations too. `_CURRENT_LEVEL_KEY` now caches the **base** key.

### Changed — curse-adjustment layer (framework; values user-tunable)
- New per-frame **Layer 2** in the `shading_callback` hook (consolidated into the existing hook — no new hook registered). When in a Deus expedition with a curse (theme ≠ `wastes`), it multiplies the post-base ShadingEnvironment value (vdl's color, or the baked vanilla where vdl left it alone) by a per-deity tint, composing the curse look on TOP of vdl's lighting instead of replacing it.
- Curse + theme read straight from **vanilla Deus state** (`Managers.mechanism:game_mechanism():get_deus_run_controller():get_current_node().theme` / `.curse`), nil-safe; outside a Deus expedition every reader bails and the layer no-ops (Adventure behaves exactly as before).
- **Seed (no invented colors):** each deity's adjustment defaults to the vanilla engine tint the base game already ships for that theme — `DeusThemeSettings[theme].light_probe_tint` — read live from the engine table, never copied into source. The user tunes the final curse look in-game; nothing fabricated ships as a "curse color".
- New settings + commands: master toggle `enable_cw_curse_adjust` (default ON, no-op outside CW) and `/vdl_curse <theme> <channel> [r g b]`, `/vdl_curse_exp <theme> [mul]`, `/vdl_curse_clear`, `/vdl_curse_dump`, `/vdl_curse_save` (overrides persist under `saved_curse_adjust_v1`, separate from base `saved_profiles_v4`).
- Regression checks added (`/vdl_regression_test`): `cw_permutation_prefix_match`, `curse_seed_is_engine_value_not_invented`, `curse_layer_noop_outside_deus`.

### To tune in-game (curse look is NOT final)
Run a vdl mission inside a cursed CW expedition, then per deity (khorne/nurgle/tzeentch/slaanesh/belakor) adjust `/vdl_curse <theme> <channel> <r> <g> <b>` (float multipliers on top of vdl's base) and `/vdl_curse_exp`. `/vdl_curse_dump` prints a copy-paste block to bake into `_CURSE_ADJUST`. Defaults are the vanilla deity `light_probe_tint` until tuned.

### Open design question (flagged for the user)
The curse tint currently **multiplies** vdl's base color (same idiom ct uses for CW skies). An alternative blend (lerp toward the vanilla curse atmosphere, or additive overlay) is also reasonable; multiply was chosen to keep vdl's tuned hue recognizable under the curse. Easy to switch in Layer 2 if you prefer a different composition.

### Build
VMBLauncher.exe build verminious_dreams_lighting_dev — verification only. NOT deployed, NOT uploaded.

## v1.0.8-dev — 2026-06-19 — Test-status labels on menu entries

Prefixed the three per-mission lighting toggles with `[untested]` so we know what's safe to promote to stable `verminious_dreams_lighting`. Flip to `[confirmed working]` as verified in-game. See `TESTING_STATUS.md`.

## v1.0.7-dev — 2026-05-26

- **FORK POINT**: friends-only dev stream for in-flight vdl work. Parent `verminious_dreams_lighting/` (Workshop ID 3727221800) remains the public stable stream at v1.0.6.
- Mod_id renamed `verminious_dreams_lighting` → `verminious_dreams_lighting_dev`. Scripts dir renamed similarly. itemV2.cfg: visibility friends_only, published_id cleared.
- Client-side only — no cross-stream lobby concerns.

## 1.0.6 (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[vdl] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- verminious_dreams_lighting.lua -- removed the load-time `mod:echo("verminious_dreams_lighting v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[vdl] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("verminious_dreams_lighting v%s loaded", MOD_VERSION)` retained for log-side visibility.
- removed the `if mod:get("enable_debug_logging") then mod:echo(...) end` startup gate too. Even gated on debug, a load-time echo violates the new policy ("never at module load").
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build verminious_dreams_lighting -- verification only. NOT deployed, NOT uploaded.

## v1.0.5 (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- verminious_dreams_lighting_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- verminious_dreams_lighting.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build verminious_dreams_lighting -- verification only. NOT deployed, NOT uploaded.

## v1.0.4 (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[vdl] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `verminious_dreams_lighting.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[vdl] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v1.0.4.

## v1.0.3 (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `verminious_dreams_lighting.lua` — installed `_dbg_alert` helper alongside `_dbg`. Added `_RT_CHECKS` regression scaffold (`/vdl_regression_test`) with `dbg_helpers_two_channel` check.
- `itemV2.cfg` — bumped to v1.0.3.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified — all 45+ `mod:echo` calls are inside `/vdl_*` chat command bodies (user-operational, leave alone).

## v1.0.2 (2026-05-25) — Stable-track: no chat-echo of version on startup

### Why
vdl is the first repo mod to ship as stable (no -dev/-alpha/-beta suffix). User policy: once a mod hits stable, the version line shouldn't pollute chat on startup — the console log is enough. Verbose / chat-echo behaviour returns when the user explicitly enables `enable_debug_logging`.

### Changed
- `verminious_dreams_lighting.lua` lines 3-9 — `mod:info("Verminious Dreams Lighting v%s loaded", ...)` still fires unconditionally (writes to `console_logs/` for crash reports). The companion `mod:echo("Verminious Dreams Lighting v" .. MOD_VERSION)` is now gated on `mod:get("enable_debug_logging")` — silent in chat by default; visible when debug logging is on.

### Compat
- No setting changes. Users who want the old startup chat line should tick `Debug Logging` in the VMF settings menu.

## v1.0.1 (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). vdl previously had no debug toggle — added.

### Changed
- `verminious_dreams_lighting_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of `options.widgets`, top-level (NOT inside any group).
- `verminious_dreams_lighting_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `verminious_dreams_lighting.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[vdl:dbg]`.
- `itemV2.cfg` — title bumped to v1.0.1.

### Notes
- No existing debug key to rename.

## v1.0.0 (2026-05-23)

Graduating to 1.0. Scope is feature-complete: tuned defaults baked for all three Verminious Dreams missions, per-mission VMF toggles, two light groups (torches / general), per-frame ShadingEnvironment overrides via `CameraManager.shading_callback`, live tuning via `/vdl_*` commands.

Chasm-light targeting (dropped at v0.6.0) and particle-FX overrides (deferred at v0.1.0) are now formally out of scope, not deferred TODOs — the engine paths for both have known cost/complexity that isn't justified for a three-mission lighting mod.

No code changes vs. v0.8.0-alpha; this is purely a release-track bump after a week public with no reported issues.

## v0.8.0-alpha (2026-05-16)

**First public release.** Flipped visibility from `friends_only` → `public`. All three Verminious Dreams missions are baked: The Forsaken Temple, Devious Delvings, The Well of Dreams. Subscribers get tuned lighting on `dlc_termite_1/2/3` out of the box; per-mission VMF toggles default ON.

Updated Workshop description to match the rest of the Tweaker family — feature bullets, multiplayer note (client-side only), source link, BMC button.

## v0.8.0-dev (2026-05-16)

**Baked The Well of Dreams defaults** from the first tuning pass:

```
dlc_termite_3 = {
    sun = { 100, 100, 100 },
    amb = { 200, 200, 280 },
    amb_top = { 50, 50, 60 },
    fog = { 70, 85, 85 },
}
```

(sky, sun2, exp, and light overrides left vanilla.)

**All three Verminious Dreams missions are now baked.** Subscribers get tuned lighting on `dlc_termite_1/2/3` out of the box, with the per-mission VMF toggles defaulting to ON. Bumped the localization tooltip to remove the "no-op" caveat from The Well of Dreams.

## v0.7.0-dev (2026-05-16)

**Baked Devious Delvings defaults** from the first tuning pass:

```
dlc_termite_2 = {
    sun = { 160, 120, 80 },
    amb = { 250, 250, 250 },
    amb_top = { 50, 100, 160 },
    fog = { 24, 24, 24 },
}
```

(sky, sun2, exp, and light overrides left vanilla.) Subscribers now get this lighting on `dlc_termite_2` without running any commands. One mission left to tune (`dlc_termite_3` / The Well of Dreams).

Bump localization to remove the "(currently a no-op)" note from the Devious Delvings toggle tooltip.

## v0.6.0-dev (2026-05-16)

Dropped the chasm light group. The position-based detection wasn't catching the lights it was supposed to in actual play — the chasm lights apparently aren't attached to level-static units the way torches are, so `Level.units` / `Unit.world_position` doesn't reach them. Could pursue (e.g. `Light.position`, or a per-light position read off the Light handle), but parking the feature instead.

Removed commands: `vdl_chasm`, `vdl_chasm_int`, `vdl_chasm_y`. Removed profile fields: `light_chasm_color`, `light_chasm_intensity`, `chasm_y_max`. Saved profiles with those fields silently ignore the unknown keys on hydration.

Light groups are now just **torches** and **general**.

## v0.5.0-dev (2026-05-16)

Per-mission VMF toggle. Each of the three Verminious Dreams missions has its own checkbox in the mod's VMF settings menu, defaulting to ON. Switching one OFF returns that mission to vanilla lighting without disabling the whole mod (or losing your tuned values — they stay in `_PROFILES` ready for re-enable).

- `enable_dlc_termite_1` — "The Forsaken Temple" (default ON)
- `enable_dlc_termite_2` — "Devious Delvings" (default ON)
- `enable_dlc_termite_3` — "The Well of Dreams" (default ON)

Mid-mission toggle flip behavior:
- Atmosphere (sky / sun / fog / ambient / exposure) reverts immediately because the shading_callback hook short-circuits when the toggle is off and the engine re-seeds those values from the level template every frame.
- Per-light Light component overrides only fully clear on next level load. The Stingray engine doesn't expose `Light.color` / `Light.intensity` for read-back, so once we've set values on a Light handle there's no path back to the vanilla baked value mid-mission. Flipping the toggle BACK ON via `mod.on_setting_changed` does reapply immediately.

`/vdl_*` commands still work when a toggle is OFF (so you can tune at any time); they print a one-line note reminding you the toggle is off, and your edits queue up — flipping the toggle on applies them.

## v0.4.0-dev (2026-05-16)

**Baked The Forsaken Temple defaults** from the first tuning pass:

```
dlc_termite_1 = {
    sky = { 50, 100, 170 }, sun = { 210, 210, 230 }, sun2 = { 255, 255, 255 },
    amb = { 210, 210, 180 }, amb_top = { 150, 150, 200 }, fog = { 86, 90, 70 },
    exp = 0.045,
}
```

Subscribers now get this lighting on `dlc_termite_1` without running any commands.

### Per-light-group control

Global `vdl_light` paints every Light in the level the same colour, which is too coarse — torches and chasm-floor lights need to look different. Lights now auto-classify into three groups at level start:

- **torches** — parent unit's debug name contains `torch / brazier / candle / lantern / sconce` (case-insensitive). Override the pattern list with `vdl_torch_patterns`.
- **chasm** — parent unit's world Z is below `chasm_y_max`. Disabled until you set a threshold via `vdl_chasm_y <value>`. Stingray engine has Z up — "below the map" means low Z, not low Y.
- **general** — everything else.

Apply precedence per light: specific-group override → global `light_color` / `light_intensity` → vanilla.

### New commands

- `vdl_torch [r g b]` / `vdl_torch_int [val]` — paint torches group
- `vdl_torch_patterns [list|reset]` — override which substrings count as torches
- `vdl_chasm [r g b]` / `vdl_chasm_int [val]` — paint chasm group
- `vdl_chasm_y [val]` — set Z threshold for chasm group
- `vdl_lights` — counts per group + parent Z range (use the range to pick a sensible `vdl_chasm_y`)
- `vdl_lights_list [pattern]` — list cached lights with index / group / Z / unit debug_name; great for spotting which units own which lights

`vdl_light` and `vdl_light_int` still work as the global fallback for ungrouped lights.

### Storage / compat

- Saved-storage key bumped to `saved_profiles_v4` (additive fields on top of v0.3).

## v0.3.0-dev (2026-05-16)

**Interface uses 0-255 byte RGB now** (like web / hex colors), not 0-1 floats.

- `vdl_sun` prints e.g. `vanilla = 243 216 176` — same numbers you'd see in any color picker.
- `vdl_sun 200 255 172` sets sun_color to that byte triple.
- HDR values above 255 are accepted — some engine baselines exceed 1.0 (e.g. sun_color baseline ~380 = engine value 1.49). Type a bigger byte and you get a brighter-than-full light.
- `_PROFILES` literals in the source file are byte triples: `sun = { 200, 255, 172 }`. What `vdl_dump` prints is the exact format you paste into source.
- `exp` and `light_intensity` remain scalars (NOT bytes — exposure is EV-like, light intensity can be 50-5000+ for HDR point lights).
- Saved-storage key bumped to `saved_profiles_v3` so v0.2 float profiles aren't reinterpreted as bytes.

## v0.2.0-dev (2026-05-16)

**Breaking semantics change**: every command now takes ABSOLUTE values, not multipliers.

- `vdl_sun 0.9 0.7 0.5` now sets sun_color to exactly that RGB triple (was: multiplied vanilla by it).
- Every command also works with NO arguments — `vdl_sun` prints both the current vanilla value (sampled live each frame) and the active override, if any. So you can read what the engine is using before deciding what to set.
- Added `vdl_clear <field>` (e.g. `vdl_clear sun`, `vdl_clear all`) to remove an override and return that channel to vanilla.
- `vdl_light_mul` renamed `vdl_light_int` (absolute intensity, not a multiplier).
- Dropped `vdl_light_off / vdl_light_on`; light override is now implicit (presence of `light_color` / `light_intensity` = enabled, absence = vanilla).
- Storage key bumped to `saved_profiles_v2` so v0.1 multipliers don't get reinterpreted as absolutes.

## v0.1.0-dev (2026-05-16)

Initial release. Replaces lighting on the three Verminious Dreams DLC missions whose vanilla lighting reads as too dark / muddy:

- `dlc_termite_1` — The Forsaken Temple
- `dlc_termite_2` — Devious Delvings
- `dlc_termite_3` — The Well of Dreams

### What it does

For these three levels (and ONLY these three), the mod applies tuned multipliers on top of the level's baked lighting:

1. **Sky / sun / fog / ambient / exposure** — via `CameraManager.shading_callback` (per-frame multiplicative on ShadingEnvironment vars). Reverts automatically when leaving the level.
2. **Per-light colour + intensity** — via `Light.set_color` / `Light.set_intensity` on every Light component in `Level.units(level)`, applied once on `GameModeManager.local_player_game_starts`.
3. **Particle FX** — not in v0.1.0. Vanilla torches / glows are particle systems, not Light components; deferred (would require shipping per-effect material overrides).

v0.1.0 ships with all profiles at neutral 1.0 multipliers — same as vanilla — pending the live in-game tuning pass. After tuning, the resolved values get baked into `_PROFILES` in the source as the new default.

### Commands (in-game console, all prefixed `vdl_`)

- `vdl_sky r g b` — skydome_tint_color multiplier
- `vdl_sun r g b` — sun_color multiplier
- `vdl_sun2 r g b` — secondary_sun_color multiplier
- `vdl_amb r g b` — ambient_tint multiplier
- `vdl_amb_top r g b` — ambient_tint_top multiplier
- `vdl_fog r g b` — fog_color multiplier
- `vdl_exp <mul>` — exposure multiplier (scalar, default 1.0)
- `vdl_light r g b` — per-light Light.set_color multiplier (enables override)
- `vdl_light_mul <mul>` — per-light intensity multiplier (enables override)
- `vdl_light_off` / `vdl_light_on` — toggle override
- `vdl_reapply` — re-capture baseline + re-apply current profile
- `vdl_dump` — print current profile
- `vdl_save` — persist all profiles to VMF settings (survives restart)
- `vdl_reset` — reset current level's profile to 1.0
- `vdl_level` — print current level_key + profile status
- `vdl_help` — list commands
