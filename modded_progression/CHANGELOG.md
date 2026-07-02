# Modded Progression — Changelog

## 0.2.12-dev (2026-07-01) — #174 loadout attribution probe (passive, log-only)

### Why
Issue #174: bot loadouts get replaced on startup by base blacksmith items in modded realm, and it is unclear which mod persists/restores them. mp is one of three loadout-adjacent suspects, so it gets a passive attribution probe. No gameplay change.

### Changed
- New `_diag_probe.lua` — rate-limited `printf` emitter for the `[174:loadout]` channel (logs on first-sight + on-change, startup window, hard flood cap). Writes via engine `printf` so it lands in the log with VMF mod logging OFF.
- `_with_eac_off` now maintains `mod._mp_eac_depth`, exposed as `mod.is_eac_window()`. mp itself has no loadout write/restore path (it is a scaffolding stub); its only #174 relevance is that `_with_eac_off` un-gates vanilla progression, so the eac-window flag lets the cosmetics_tweaker chokepoint attribute any loadout write that lands while mp has the realm un-gated. The depth counter mirrors the existing eac-flag set/restore bracket exactly (byte-identical behaviour).
- One load-time `[174:loadout]` line names mp as a non-writer with the eac-window instrumented.

### Notes
- No behaviour change, no new hooks on any loadout path. Not built, deployed, uploaded, or committed.

### Files
- `_diag_probe.lua` (new), `modded_progression.lua` (loader + eac-depth counter + load line; `MOD_VERSION` `0.2.11-dev` -> `0.2.12-dev`).

## 0.2.11-dev (2026-07-01) — Fix double-localized widget fields; rewrite option descriptions for players

### Why
VMF's options module localizes each widget's `title` / `tooltip` / dropdown-option `text` field itself at menu build time (via `mod:localize`). The data tree was calling `mod:localize(...)` a second time on those fields, so the already-resolved string got fed back through `mod:localize`, which returned the value wrapped in angle brackets when treated as a key. Result: the starting-state tooltip and its three dropdown option labels rendered wrapped in `<...>`. The old tooltip/description text also used em dashes, non-ASCII bullet characters, and internal jargon (PlayFab, "local store", "seed").

### Changed
- `modded_progression_data.lua` — converted the 4 widget-level eager localizations to raw loc keys so VMF localizes them once: `tooltip = "starting_state_tooltip"` and the three dropdown option `text` fields (`start_fresh` / `start_level_35` / `start_level_35_unlocked`). The top-level mod `description = mod:localize("mod_description")` is the one correct eager-localize and is unchanged.
- `modded_progression_localization.lua` — rewrote `mod_description`, `starting_state_tooltip`, and `starting_state_description` into short, plain-English player-facing text. Removed em dashes and non-ASCII bullets, dropped backend jargon in favour of "your progress is saved locally on your PC," and pointed users at the `/mp_reset` chat command to re-choose a starting state.

### Notes
- No loc keys were missing; all widget-referenced keys already existed. No keys, setting_ids, widget structure, or defaults were changed.
- Not built, deployed, uploaded, or committed.

## 0.2.10-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.2.9-dev (2026-06-07) — Remove dead reset_progression loc keys (orphan-loc audit)

### Why
Audit 2026-06-07 flagged two localization keys — `reset_progression` and `reset_progression_tooltip` — as defined in `modded_progression_localization.lua` but referenced nowhere in the mod. Re-grep of the whole mod dir confirmed: no `mod:localize("reset_progression")`, no widget `setting_id` named `reset_progression`, no computed/concatenated key construction. The reset *feature* does exist, but only as the `/mp_reset` chat command (`modded_progression.lua:435`), which echoes a plain hardcoded English string — it does not consume these keys, and chat commands have no tooltip/label surface. There is no reset widget in the data tree and PLAN.md describes no planned reset UI. The keys were a label+tooltip pair anticipating a settings-UI button that was never wired. Genuine dead leftover → removed (not wired) since wiring would require inventing an unplanned widget beyond this audit's scope.

### Changed
- `modded_progression_localization.lua:16-20` — removed the `reset_progression` and `reset_progression_tooltip` entries (and the now-stale "Reset" section header), replaced with a comment recording why the keys are gone and the condition under which to reintroduce one.

### Tests
- No new regression check (loc-key dead-removal has no keep-observable behavior to assert; a "key absent" marker test would be brittle). The existing `localization_format_safe` `_rt_register` check iterates the live loc table, so it automatically continues to cover only the remaining keys with no stale reference.

### To verify
- `/mp_regression_test` still reports PASS on `localization_format_safe` (and all other checks).
- No VMF settings UI regression — neither removed key was bound to a widget/tooltip, so the settings panel is unchanged (only `starting_state` dropdown + `enable_debug_logging` checkbox).

## 0.2.8-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Modded Progression v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `modded_progression.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[mp] v<MOD_VERSION> loaded")` runs once. (mp is still unpublished — banner is for local visibility only.)

## 0.2.7-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[mp] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- modded_progression.lua -- removed the load-time `mod:echo("modded_progression v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[mp] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("modded_progression v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build modded_progression -- verification only. NOT deployed, NOT uploaded.

## v0.2.6-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- modded_progression_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- modded_progression.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build modded_progression -- verification only. NOT deployed, NOT uploaded.

## v0.2.5-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[mp] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `modded_progression.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[mp] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.5-dev.

## v0.2.4-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `modded_progression.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added new `_RT_CHECKS` regression scaffold (`/mp_regression_test`) with `dbg_helpers_two_channel` check (mp had no regression command before).
- `itemV2.cfg` — bumped to v0.2.4-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified — `mod:echo` calls are in `/mp_dump` / `/mp_reset` chat command bodies (user-operational, leave alone).

## v0.2.3-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). mp previously had no debug toggle — added.

### Changed
- `modded_progression_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of `options.widgets`, top-level (NOT inside any group).
- `modded_progression_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `modded_progression.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[mp:dbg]`.
- `itemV2.cfg` — title bumped to v0.2.3-dev.

### Notes
- No existing debug key to rename.

## v0.2.2-dev (2026-05-25)

Hardening: nil-hole-safe variadic unpack at 1 call site (lessons from wt v0.12.77/.78 burn).

`_with_eac_off` is the generic flip-flag wrapper applied to nine different vanilla functions (`LevelEndViewBase.init`, `HeroViewStateAchievements._create_entries` / `._handle_claim_all_challenges`, `StoreWindowItemPreview._set_unlock_button_states`, `StoreItemPurchasePopup._create_ui_elements`, `StoreLoginRewardsPopup._create_ui_elements`, `HeroWindowItemCustomization._enable_craft_button` / `._update_state_craft_button`, `AchievementManager.trigger_event`). It used the pattern `local results = { func(self, ...) }` followed by `return unpack(results)` — bare `unpack` uses `#results` as its upper bound, which Lua 5.1 truncates at the first internal nil. Any wrapped function that returns multi-values with an interior nil would silently lose every return after the first nil at the caller.

Switched to `select("#", ...)` capture + `unpack(t, 1, n)` with an explicit length. Same `(n, t = _capture(...))` doctrine that `weapon_tweaker/_safe_hook.lua` already uses. No observed behavior change for the nine hooked functions today, but eliminates the latent corruption path if vanilla ever evolves any of them to return optional multi-values.

## v0.2.1-dev (2026-05-21)

Section A + C P1 release-audit fixes.

- Added `item_preview.png` (copied from VMB template). `itemV2.cfg` already referenced this file as the Workshop preview, but the file was absent from the mod folder — first upload attempt would have failed at the preview-staging step. Unblocks future `vmblauncher upload mp`.
- Added `starting_state_description` localization key. VMF auto-looks up `<setting_id>_description` for every widget's hover description; the dropdown's `setting_id = "starting_state"` was rendering with the raw key string in the description slot.
- Audit-walked every `mod:localize(...)` call in `modded_progression_data.lua`; the four explicit lookups (`mod_description`, `starting_state_tooltip`, `start_fresh`, `start_level_35`, `start_level_35_unlocked`) all already resolve. No additional keys missing per that criterion.

## v0.2.0-dev (2026-05-15)

Build-order step 2 — UI gate overrides + achievement-progress un-gate.

Wraps 10 vanilla functions with a flip-flag wrapper (`script_data["eac-untrusted"] = nil` for the call, restored on exit), so the gated bodies run as if in official realm. Flag stays globally true outside our wrapped calls, preserving commit suppression at `playfab_mirror_base.lua:2826/2839/2857` and the DLC update gate at `unlock_manager.lua:719`.

**Functions hooked:**
- `LevelEndViewBase.init` — runs `_get_level_up_rewards` / `_get_deed_rewards` / `_get_deus_rewards` / `_get_keep_decoration_rewards` / `_get_event_rewards` / `_get_win_track_rewards` / `_get_versus_level_up_rewards` setup branch
- `HeroViewStateAchievements._create_entries` — restores `completed` flag on each Okri's Challenges entry
- `HeroViewStateAchievements._handle_claim_all_challenges` — un-greys claim-all button
- `StoreWindowItemPreview._set_unlock_button_states` — un-greys Lohner's buy button
- `StoreItemPurchasePopup._create_ui_elements` — un-greys purchase popup button
- `StoreLoginRewardsPopup._create_ui_elements` — un-greys daily-rewards claim button
- `HeroWindowItemCustomization._enable_craft_button` / `_update_state_craft_button` — un-greys keep crafting bench
- `IngameUI.not_in_modded` — overridden to always return `true`
- `AchievementManager.trigger_event` — **critical** un-gate: lets every achievement-progress event run, so kill counts / completion timers / etc. actually advance challenge counters

**Intentionally left gated:**
- `AchievementManager.update` (line 294) — Steam-platform achievement push loop. Local progression doesn't need Steam to register them.
- All commit paths in `playfab_mirror_base.lua` — the whole point of writing local.

**Verification:**
- VMB build clean (1.93s incremental, 4 bundles).
- In-game verification deferred to user — should expect: level-end reward popups appear and queue, Okri's Challenges grey claim button no longer greyed, Lohner's buy buttons live, keep crafting bench buttons clickable, kill statistics tick up during a mission.

## v0.1.0-dev (2026-05-14)

Initial scaffold. Internal id `mp`. Workshop unpublished (private visibility).

**Shipped:**
- VMF mod registration, build via VMB, output to `bundleV2/`.
- VMF settings UI with the starting-state dropdown (fresh / level 35 default / level 35 everything unlocked).
- Local persistence stores via VMF settings (`currency`, `unlocks`, `inventory`, `seeded`, `schema_version`).
- Sibling API stubs (`mp.is_unlocked`, `mp.mark_unlocked`, `mp.has_currency`, `mp.spend`, `mp.credit`, `mp.get_currency`, `mp.grant_item`) — all returning sane defaults pre-seed so co-installed CWV / cosmetics_tweaker don't crash.
- Diagnostic commands: `mp_dump` (current state), `mp_reset` (wipe local store).
- Schema versioning hook for future migrations.

**Not yet wired (per `PLAN.md` build order):**
- Step 1.b: mirror-overlay layer (VMF → backend_mirror at boot) and serialization layer (mirror mutation → VMF) — function stubs in place, no hooks.
- Step 2: UI gate overrides (~10 sites) + `AchievementManager.trigger_event` hook.
- Steps 3–7: end-of-mission rewards, loot-chest opening, Okri's Challenges, Lohner's Emporium, crafting bench interceptions.
- Step 8: starting-state seeder.
- Step 9: sibling consumer hooks in CWV / cosmetics_tweaker.

**Blockers for step 7 (crafting bench):**
- Runtime dump of `scripts/settings/crafting/crafting_recipes` table.
- Runtime dump of `CraftingData` table.
- PlayFab title-data inspection at sign-in.
