# Modded Progression — Changelog

## 0.2.22-dev (2026-07-13) - #573 isolate the complete modded quest surface [not deployed]

- Fixed official weekly/event rows leaking into the Modded Progression challenge surface. The old hook replaced only `quests.daily`, so an official row such as `weekly_collect_dice_2` remained visible but was correctly rejected by the local claim boundary. Modded play now returns exactly three slices: MP-owned local dailies, an empty weekly slice, and an empty event slice. Official play returns the original backend table unchanged.
- Closed the corresponding refresh leak. Vanilla `BackendInterfaceQuestsPlayfab.update_quests` polls daily, weekly, and event backend timers and can enqueue CloudScript `getQuests`; the modded route now rotates the local UTC roster and invokes `QuestManager`'s update callback without calling the backend method. Official refresh remains native.
- Official quest-key lookup, quest-by-key lookup, and reward-poll fallback now fail closed in modded play. Only current MP-owned identities and locally created reward poll ids are resolved; defense-in-depth claim hooks remain unchanged.
- Added pure realm-routing coverage for zero official reads in modded play, empty weekly/event slices, exact official pass-through, local callback refresh, and native official refresh. Added runtime check `mp573_quest_surface_is_owned_and_backend_free`.

**Source audit:** `backend_interface_quests_playfab.lua:25-44` builds daily, weekly, and event slices from the backend mirror; `:60-100` shows `update_quests` can enqueue `FunctionName = "getQuests"` from any expired official timer; `quest_manager.lua:36-50` dispatches all three returned slices into progress evaluation, and `:599-615` builds event mappings from the returned event slice. Empty tables preserve those source contracts without exposing official identities.

**Log evidence:** `console-2026-07-14-00.01.43-0cdea076-5ef6-46e0-a122-c344f0c93c0c.log` recorded `blocked non-MP quest claim id=weekly_collect_dice_2 backend=none`, proving the official weekly row reached the modded UI while the backend-free claim guard correctly refused it.

**Test:** In modded play, open Okri's Challenges and refresh/reopen it. Only three `mp_daily_v2_*` daily rows may appear; no official daily, weekly, or event quest may be visible. Claim a completed local row and run `/mp_regression_test`; expect `mp573_quest_surface_is_owned_and_backend_free` to pass and no `getQuests`, `generateQuestRewards`, EAC challenge, backend 511, `-1`, or forced exit. In official play, confirm native daily/weekly/event rows and claims remain unchanged.

## 0.2.21-dev (2026-07-13) - #589 block store login reward PlayFab claims [verify-fix]

- Fixed the critical modded-realm exit caused by the daily login reward popup. The native path is `StoreLoginRewardsPopup._claim_rewards` -> `BackendInterfacePeddlerPlayFab.claim_login_rewards` -> authenticated `claimStoreRewards`; the request triggers an EAC challenge, backend 511, and the fatal `-1` popup.
- The login-reward claim button now remains disabled in modded play, and the UI action is independently intercepted before it can change into the claiming/waiting state. Official-realm popup behavior is unchanged.
- Added defense in depth at `BackendInterfacePeddlerPlayFab.claim_login_rewards`: every modded-realm caller is rejected before `request_queue:enqueue`, while official calls and return values pass through unchanged. The done flag remains true so no caller waits for a suppressed callback.
- Login rewards are intentionally fail-closed until MP owns a durable local transaction for their mixed item/currency payload; no reward is silently duplicated, lost, or written to the real account.
- Added `/mp_regression_test` checks `mp589_store_login_claim_request_boundary` and `mp589_store_login_claim_ui_disabled`, plus repository textual locks on both interception hooks.

**Source audit:** `store_login_rewards_popup.lua:181-216` changes UI state then invokes `claim_login_rewards`; `backend_interface_peddler_playfab.lua:811-828` creates `FunctionName = "claimStoreRewards"` and enqueues it as a write; `_claim_store_rewards_cb` mutates items, currencies, chest inventory, telemetry, and save data from the PlayFab result, so fabricating that callback without an atomic local ledger is unsafe.

**Log evidence:** `console-2026-07-14-00.16.57-1b7e5c2d-a05a-4242-af33-33801883bc40.log` loaded MP `0.2.20-dev` and completed the #581 startup path without a synthetic `StatisticsDatabase` failure. At `00:20:37.395` it enqueued `claimStoreRewards`; the EAC challenge was disabled, backend reason `511` followed, and the `-1` dialog forced exit. This is the exact #589 path, not a recurrence of #581.

**Test:** In the modded realm, open Lohner's Emporium and the daily login reward popup. The claim button must be disabled. Attempt mouse/gamepad activation and run `/mp_regression_test`; expect both #589 checks to pass and no `claimStoreRewards`, EAC challenge, backend 511, `-1`, or forced exit in the log. Then enter the official realm and confirm the same reward button and native claim still work normally.

## 0.2.20-dev (2026-07-13) - #581 bypass synthetic StatisticsDatabase daily evaluation [verify-fix]

- Fixed the startup crash `Failed fetching statistic using parameters: quest_statistics, mp_daily_v2_20647_slot_3_progress` (GUID `affd4123-ce2e-4d15-82fa-a972e65ade2c`).
- MP-owned daily IDs now bypass vanilla `QuestManager.get_data_by_id` evaluation and build their UI row from the source template plus MP's local persisted progress/claim ledger. Vanilla's daily `completed`/`progress` callbacks are never called for synthetic IDs.
- Removed synthetic `QuestSettings.stat_mappings` entries; MP daily counters remain backend-free and StatisticsDatabase-free.
- Added `/mp_regression_test` check `mp581_owned_daily_bypasses_statistics_db`.

### Test method
1. Start the game with Modded Progression enabled and enter the keep.
2. Expected: startup completes, the challenge board can inspect the three local dailies, and the log has no `StatisticsDatabase` lookup for an `mp_daily_v2_*` key.

## 0.2.19-dev (2026-07-13) - #573 persistent local dailies and isolated shillings [untested]

### Changed
- Replaced the #568 server-roster snapshot with an MP-owned v2 state record. Three vanilla daily objective templates are selected deterministically per UTC day without using official quest identities.
- Persisted roster, objective counters, claim markers, and the MP Silver Shilling ledger in one namespaced setting. A claim marks completion and credits shillings in one copy-on-write save with read-back verification.
- Added monotonic reset handling: missed days rotate directly to the current period, while backwards clock changes retain the high-water roster and cannot mint another reward set.
- Routed daily event mappings into local counters instead of vanilla `StatisticsDB` quest slots. Native quest presentation is retained, with progress/completion replaced from MP state.
- Routed modded-realm `get_chips("SM")` reads to the local ledger. Official realm reads and all non-SM currencies remain vanilla. Official SM purchases are blocked in modded play until the backend-free item-grant transaction is implemented in follow-up #577; visibly distinct UI labeling/refresh is tracked in #578.
- Retired legacy `simulated_dailies` and `_mp_daily_claims` state without importing the generic `currency.SM` value, preventing accidental official/local balance merging.

### Source evidence
- `quest_manager.lua:79-116,289-396` defines event mapping and quest presentation; `quest_settings.lua:56-70,272-289` supplies the daily targets and per-quest stat slots.
- `backend_interface_quests_playfab.lua:25-44,81-166` shows that roster selection and reset timestamps arrive from CloudScript rather than local Lua.
- `backend_interface_peddler_playfab.lua:61-62,240-260,661-707` is the native SM read/write/purchase seam; native purchase success depends on PlayFab-returned item instances, so it is not safe to fake as a currency-only debit.

### To verify
- In modded play, note the three dailies, make objective progress, restart, and confirm the same roster/progress returns.
- Complete and claim a daily twice; expect one local five-shilling credit and no `generateQuestRewards` request. Claim-all must remain atomic.
- Change the clock backwards and restart; expect the existing roster. Advance across one or more UTC days; expect exactly one current roster reset.
- Compare the Emporium shilling number between official and modded realms. The balances must remain independent; modded SM purchase currently fails closed pending #577.
- Run `/mp_regression_test`; expect zero failures.

## 0.2.18-dev (2026-07-13) - #568 backend-free simulated daily claims [untested]

### Changed
- Replaced the modded-realm daily quest surface with three locally namespaced `mp_daily_*` simulations. The day's vanilla templates may seed the presentation/progress mapping, but their backend quest identities are discarded.
- Intercepted the exact single and claim-all UI methods before `QuestManager` can enqueue `generateQuestRewards`. Unknown or official ids are rejected in modded play; official-realm behavior remains vanilla.
- Added an atomic claim ledger inside the local currency record. Reward balance and per-id idempotency markers persist in one write, with read-back verification; a failed write grants nothing.
- Returned synthetic local poll rewards through the native reward presentation path, so claimed entries refresh immediately without a PlayFab poll.
- Added defense-in-depth backend claim guards and four `/mp_regression_test` checks for atomicity, persistence failure, namespace/realm ownership, and duplicate rejection.

### Source evidence
- `hero_view_state_achievements.lua:1273-1349` routes individual/claim-all quest clicks into `QuestManager`.
- `quest_manager.lua:448-493` resolves backend keys and requests rewards.
- `backend_interface_quests_playfab.lua:285-302, 500-522` enqueues `generateQuestRewards`.

### To verify
- Complete and claim one simulated daily, then use claim-all on two completed dailies. Expect immediate reward/removal and no `generateQuestRewards`, EAC request, error 511, or forced exit in the log.
- Restart and confirm claimed dailies cannot grant again and the local shilling balance persists.
- Run `/mp_regression_test`; expect zero failures.

## 0.2.17-dev (2026-07-12) - issue 509: regression-harness backfill (_with_eac_off contract + sibling API) [untested]

### Why
Issue 509: `/mp_regression_test` already locked the issue-434 eac-restore-after-throw guard, but not the rest of the `_with_eac_off` contract (multi-return nil-hole preservation, at-rest window state) or the sibling-API surface CWV / cosmetics_tweaker consume.

### Changed
- `modded_progression.lua` - added three `_rt_register` checks beside `_with_eac_off`:
  - `eac_off_preserves_multi_return_nil_holes` - runtime: a `1, nil, 3` return survives `_with_eac_off` unchanged. Locks the `select("#")`/`unpack` machinery against the wt v0.12.77/.78 multi-return-collapse class.
  - `eac_window_closed_at_rest` - runtime: outside any wrapped call `mod._mp_eac_depth == 0` and `mod.is_eac_window() == false`. The baseline the cosmetics issue-174 chokepoint depends on.
  - `sibling_api_surface_present` - runtime: `is_unlocked` / `mark_unlocked` / `has_currency` / `spend` / `credit` / `get_currency` / `grant_item` / `is_eac_window` are all functions, and `spend` returns false (not raise) on insufficient funds.
- `MOD_VERSION` `0.2.16-dev` -> `0.2.17-dev`.

### Tests
Built via VMBLauncher (compile-only); lint clean. Not deployed/uploaded per task scope. All three checks are pure runtime (assert on a deployed install).

### To verify
- In-game (keep): run `/mp_regression_test`. Expect every line `PASS` and a `N passed, 0 failed` tail.

### Refs
Issue 509 (parent), issue 434 (eac-restore guard), issue 174 (cosmetics chokepoint).

## 0.2.16-dev (2026-07-12) - #500 remove the stale #174 loadout-attribution probe (closed issue) [untested]

### Changed
- **#500: removed `_diag_probe.lua`** (issue 174, `[174:loadout]`, CLOSED). mp's copy served ONLY the closed #174 channel. Deleted the file (`git rm`), removed the `local PROBE = mod:dofile(".../_diag_probe")` import (its comment block too), and removed the single standalone `if PROBE then PROBE.emit("174:loadout", ...) end` load-time attribution line.
- **No load-bearing behavior removed.** The emit was pure observation ("mp no-loadout-writer scaffold stub"). `mod.is_eac_window()` (modded_progression.lua:399) is a SEPARATE load-bearing function (the `_with_eac_off` EAC-window accessor, still covered by its regression check at ~line 444) and was left untouched. `PROBE` had no other references. The import line was the dofile-manifest entry; `.package` uses a `scripts/mods/modded_progression/*` glob, so no manifest edit was needed.

## 0.2.15-dev (2026-07-12) - issue 427: _dbg_alert routes to log-only printf

### Why
Issue 427/240: `_dbg_alert` routed through `mod:warning`, which VMF `logging.lua` posts to in-game CHAT under default settings (warning mode >= 2) - a "log-only" alert (e.g. the `_with_eac_off` throw path at ~line 413) would spam chat rather than just the console log.

### Changed
- `modded_progression.lua` - `_dbg_alert` now routes through pcall-guarded engine `printf` (log-only, survives mod-logging-OFF), matching enemy_tweaker v0.7.25-dev (BUG_CLASSES section 17 Variant B). `_dbg` (mod:debug) unchanged; the `_with_eac_off` re-raise semantics are untouched.
- `MOD_VERSION` `0.2.14-dev` -> `0.2.15-dev`.

### Refs
Issue 427 (parent), 240. Check: `qa/check_logging.ps1` warn-chat.

## 0.2.14-dev (2026-07-07) - pcall-protect the EAC un-gate restore (issue 434)

### Why
Audit finding F1 (issue 434, P1): `_with_eac_off` restored `script_data["eac-untrusted"]` and its depth counter only on the success path. A throw in any of the 10 wrapped vanilla functions (notably the hot `AchievementManager.trigger_event`) skipped the restore, leaving the realm un-gated globally, which re-enables the exact real-account PlayFab commits mp exists to prevent (the suppression sites gate on that flag at `playfab_mirror_base.lua:2826/2839/2857`).

### Changed
- `modded_progression.lua:~390` - `_with_eac_off` now pcall-wraps the inner call, restores the flag AND decrements the depth counter on ALL paths (finally style), then re-raises the original error (`error(msg, 0)`) so callers behave as vanilla would; `_dbg_alert` logs the throw. Multi-return nil-holes still preserved (`_capture` over `pcall`; returns start at index 2).
- `modded_progression.lua` - new `_rt_register("eac_flag_restored_after_throw", ...)` regression check: drives a throwing function through `_with_eac_off` and asserts the flag is restored, the depth counter is balanced, `is_eac_window()` is false, and the error re-raised. Registered directly after `_with_eac_off` to avoid a forward-ref on the file-local.
- `modded_progression.lua:24` - `_MEM_PROBE_T0_MP` changed from a bare `_G` global to a file-local (audit F7); only read at the bottom of the same chunk.
- `MOD_VERSION` `0.2.13-dev` -> `0.2.14-dev`.

### Notes
- Behavior-preserving on the success path (byte-identical returns); only the throw path changes (now restores before propagating). Not built, deployed, uploaded, or committed.

## 0.2.13-dev (2026-07-04) - Localization: applied dev status-tag doctrine (#301)

### Changed
- `modded_progression_localization.lua` - applied the #301 dev status-tag doctrine to option titles. 1 widget title tagged: `starting_state` -> `[untested]` (mp is a scaffolding stub whose progression paths are not yet confirmed working in-game; flagged as a working-vs-untested judgment call). Tooltips, descriptions, and dropdown value labels untouched.
- `MOD_VERSION` `0.2.12-dev` -> `0.2.13-dev`.

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
