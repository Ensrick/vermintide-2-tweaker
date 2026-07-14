# General Tweaker Changelog

## v0.2.176 (2026-07-13) -- Stable world-liveness hardening (#490)

- Ported the #459 native-world safety class to stable: cached debug draw handles are never dispatched through a destroyed/replaced world, all level-world lookups use `has_world`, and screen GUI creation uses resident `materials/fonts/gw_fonts` rather than the text-only Arial material.
- The boss-sphere debug path now fails closed while `level_world` is unavailable during transitions.

## v0.2.175 (2026-07-03) -- Promotion refresh: Bot Teleport Lab settings removed before the public release

Refresh of the (not-yet-uploaded) v0.2.173 promotion, syncing the dev line at v0.2.175-dev. Absorbs dev v0.2.174-dev (#222 tooltip re-sweep round 2: action-hotkey and enable/disable tooltip bodies) and dev v0.2.175-dev:

- **Bot Teleport Lab settings section removed entirely** (master + 10 diagnostic toggles + 10 fix-candidate toggles + numeric params, and all localization). New diagnostics doctrine: data-collecting probes are never menu toggles - they run implicitly in the DEV stream only. In this stable build the probes are fully inert (the `IS_DEV_STREAM` gate evaluates false), and the retired F1-F10 fix candidates are dormant regardless of any previously saved settings, so nothing from the old lab can activate here. The proven bot-teleport fixes (#139) in `_gt_bot_fixes.lua` and the Bots menu are unaffected.
- **"Dev Tools" section** (bot behavior HUD, leash lines) exists only in the dev clone; its widget group is not built in this stable mod.
## v0.2.173 (2026-07-03) -- STABLE PROMOTION: full sync of the public item to the dev line at v0.2.173-dev

First full dev->stable promotion since the dev/stable split. The public item jumps from v0.2.73-alpha (a late-May build plus two cherry-picks) to a direct port of `general_tweaker_dev` v0.2.173-dev: mod id renamed `gt_dev` -> `gt`, dev status labels ("[untested]" / "[confirmed working]") stripped from all menu strings, MOD_VERSION normalized to clean semver. Highlights over the outgoing stable build:

- **Architecture**: the single 246 KB monolith was split into ~25 `_gt_*.lua` feature modules (dev refactor phases 1-4, no behavior change).
- **Bots suite (new to stable)**: Bot Behavior Improvements + Improved Bot Combat, faster reactions, bots drink potions / rescue players awaiting rescue, bot follow mode + snap-back distance, #139 bot-teleport fixes (both cases) plus the Bot Teleport Lab (10 diagnostics, 10 fixes), Allow Bots in Keep revived incl. necromancer skeletons (#65), Disable Bots fixed (#194), Bot Takeover /ai + AFK takeover with RPC schema versioning (#44), guard-break announcements, Prioritize Specials (Deepwood / Soulstealer / tagging sub-toggles).
- **Spawners & cheats (new to stable)**: Creature Spawner (/spawncreature family), Item Spawner (/spawnitem), Level Control (/win /fail /restart /die /respawn /fix_sound), Time & Pause (/pause /time_faster /time_slower), Buffs & Stats (base crit chance, /gigapower, /infinite_ammo, /stamina, /ultreset), fall-damage multiplier, weave unlock, Max Ragdolls slider + fog / sun-shadow / mutator-explosion / ult-VO toggles.
- **QoL**: /catchup alias of /unstuck, /cloak, /unkillable, /inndmg, /inn, auto-restart on team wipe (now also works in Chaos Wastes + Weaves), Info readouts (assassin / packmaster / boss path progress).
- **Chat commands de-prefixed** (dev v0.2.164): every /gt_* command dropped the prefix - e.g. /gt_lobby_reserve is now /lobby_reserve.
- **Migrated OUT to Tweaker: GUI (gut)**: in-mission inventory / keep menus (#62), skip cutscenes + loading-screen monologues (#106 / #192), 3rd-person camera (#191), floating damage numbers (#190), level-intro audio; per-mod debug toggle removed, diagnostics route through VMF logging (#169).
- **Menu & loc**: full settings reorg (A->Z groups, master toggles, nested fine-tunes), #222 tooltip de-duplication sweeps, em dashes removed from menu strings, plain-English option descriptions.

Per-version history for everything between v0.2.74-dev and v0.2.173-dev lives in `general_tweaker_dev/CHANGELOG.md`.

## v0.2.73-alpha (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## v0.2.72-alpha (2026-06-24) -- Remove in-mission inventory / Keep Menus (migrated to GUI Tweaker); resolves #62

### Why
The in-mission inventory / "Keep Menus in Missions" feature force-flipped `IngameUI.handle_menu_hotkeys`' `hotkeys_enabled` arg to true mid-mission, which let the keep view hotkeys (Hero Select / Map / etc.) spawn unloaded `ui_*` preview worlds and crash (Issue #62). The whole feature has been migrated to the **GUI Tweaker** (`gut`) mod, so it is removed here entirely rather than patched. This resolves #62 for public subscribers.

### Removed
- **In-mission inventory opener** — `mod.gt_open_mission_inventory` field and the `/gt_inv` chat command.
- **Keep-menus access patch** — the `InventorySettings.inventory_loadout_access_supported_game_modes` adventure/survival/deus patch, the ESC-menu "Open Inventory" entry injector (`_patch_in_game_menu` / `_INVENTORY_BUTTON_ENTRY` / layout helpers), and the `_patch_inventory_access` re-apply from `on_game_state_changed`.
- **The `IngameUI.handle_menu_hotkeys` hotkey-flip hook** — the direct cause of Issue #62.
- **The `HeroWindowLoadoutConsole._customize_item` cim crash-gate** — only reachable from the in-mission loadout panel, so it goes with the feature.
- **The `mission_inventory_enabled` branch** from `on_setting_changed`.
- **The "Keep Menus in Missions" settings group** (`mission_inventory_enabled` / `gt_open_inv_hotkey`) from `_data.lua` and its loc keys (incl. tooltips) from `_localization.lua`.
- itemV2.cfg description: dropped the "Keep Menus in Missions" feature block + the summary-line mention; added a note that the feature moved to the GUI Tweaker mod.

### Added
- New `/gt_regression_test` check `gt_no_mission_hotkey_flip` — source-pattern guard (anchored on the `mod.on_setting_changed` main-file field) that FAILS if the `IngameUI.handle_menu_hotkeys` hook is ever reintroduced. The needle is assembled from two string literals so the test's own source does not self-match; degrades to a no-op when source introspection is unavailable.

### Notes
No other gt feature touched — camera/noclip/freecam/godmode, lobby controls, debug dumps, friendly-fire, etc. are intact. Mirrors the removal already done in `general_tweaker_dev`.

## v0.2.71-alpha (2026-06-17) -- Settings logging + bot-rescue diagnostics

### Why
The "Bots rescue allies awaiting respawn" toggle didn't work on a host that had it ON with debug logging on, and the log had no way to confirm the toggle state or see why the rescue path bailed. This adds the missing instrumentation (per the debug-as-data-harness doctrine) so the next repro is conclusive. No gameplay behavior change — diagnostics only; all logging is debug-gated.

### Added
- **Settings snapshot at load** (`[gt:settings@load] …`) — walks the data widget tree and logs every `setting_id = value` so active toggle states (incl. the bot toggles) are visible in the console log. Also exposed as `/gt_dump_settings`. Debug-gated.
- **Per-change setting log** (`[gt:setting-changed] <id> = <value>`) at the top of `on_setting_changed`, so the log shows exactly when a toggle flips and to what. Debug-gated.
- **Bot-rescue scan diagnostics** (`_gt_bot_fixes.lua`): for every ally the rescue scan sees in `is_ready_for_assisted_respawn`, logs `ready / health_alive / aid_path`, plus a throttled per-bot summary (`awaiting=N picked=yes/no not_health_alive=N path_blocked=N`). This pinpoints the failure: `awaiting=0` ⇒ CW respawn never sets the flag (need a different hook); `health_alive=false` ⇒ the HEALTH_ALIVE gate is wrong for this state; `aid_path=false` ⇒ the bot can't path to the respawn spot. Verified in source that CW *does* use `is_ready_for_assisted_respawn` (`deus_spawning.lua:203`, `respawn_handler.lua:502`) and that such allies are `HEALTH_ALIVE` (`side_manager.lua:363`), so the repro log will show which gate actually fails.
- **Ironbreaker fix log** (`[gt:bot-ib] yielding … ult-hold to aid ally`) when it releases the ult-hold to revive.

### How to use
Enable **Debug Logging** + the bot toggles on the **host**, reproduce the downed/awaiting-rescue situation, and read the `[gt:bot-rescue]` lines in the host's console log.

## v0.2.70-alpha (2026-06-17) -- Bot Options: three AI-teammate behavior fixes (promoted from dev)

Cherry-picked the "Bot Options (AI Teammates)" group from general_tweaker_dev v0.2.84-dev into public stable. Three default-OFF, host-side fixes (bots only exist on the host; no network registration, so non-modded peers are unaffected). New code in `_gt_bot_fixes.lua`. Full mechanics + source citations in the dev changelog entry; summary:

- **Necromancer bots can hand off potions** (`gt_bot_necro_potion_handoff`). Her career skull sits permanently in `slot_potion` as the primary item, so picked-up potions land in additional storage and every handoff check (which reads the primary) fails. A throttled `PlayerBotBase.update` hook promotes a stored real potion to primary for Necromancer bots (the bot-equivalent of a human tapping the potion key), so vanilla give/drink logic works. Gated to real potions so grimoires aren't promoted.
- **Ironbreaker bots revive during their ult** (`gt_bot_ironbreaker_revive_in_ult`). The IB bot holds a block `wait_action` for its ult's whole duration and `can_activate_ability` short-circuits on `is_using_ability`, parking the BT selector so the higher-priority revive node never runs. Hook returns false for an IB mid-ult when an ally needs aid, yielding to revive. The ult is a timed buff -- it keeps running, so it isn't wasted.
- **Bots rescue allies awaiting respawn** (`gt_bot_rescue_awaiting`). `_select_ally_by_utility` excludes awaiting-rescue allies entirely. A wrapper hook (calls original first; composes with other bot mods) adds a reachable awaiting-respawn ally relabeled `knocked_down`; the revive action fires the contextual interaction, which resolves to `assisted_respawn`. Experimental -- verify in-game.

All three default OFF. Enable under Mod Options -> Tweaker: General -> Bot Options (AI Teammates).

## v0.2.66-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("General Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `general_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[gt] v<MOD_VERSION> loaded")` runs once.

## v0.2.62-dev (2026-05-25) -- Add /gt_lobby_motd_set + /gt_lobby_motd_clear chat commands (replaces the invalid VMF text_input widget removed in v0.2.61)

### Why
v0.2.61-dev inlined a fix to `general_tweaker_data.lua` that REMOVED the `gt_lobby_motd_text` widget — it had `type = "text_input"`, which is not a valid VMF widget type, and caused widget#103 to fail VMF validation and break gt options init entirely on 2026-05-25. Removing the widget eliminated the only authoring surface for the MOTD body, so this version restores host authoring via chat commands instead.

### Changed
- **`_gt_lobby_motd.lua`:** Added two chat commands.
  - `/gt_lobby_motd_set <text>` — writes `mod:set("gt_lobby_motd_text", text)`. With no arg, prints the currently-stored MOTD (or `(empty)`) and a usage hint. Echoes a confirmation and logs an info line on set.
  - `/gt_lobby_motd_clear` — clears the stored MOTD (sets to empty string).
- **`general_tweaker.lua`:** `MOD_VERSION` bumped `0.2.60-dev` -> `0.2.62-dev` (skips `0.2.61-dev`, which was the inline widget-removal fix landed without a CHANGELOG entry; see "Notes" below).
- **`itemV2.cfg`:** Title suffix refreshed to `v0.2.62-dev` (will be re-stamped on next upload by VMBLauncher anyway).

### Compatibility
The send/receive RPC path is unchanged — `_on_player_joined_party` still reads `mod:get("gt_lobby_motd_text")` and `_send_motd_to_peer` still chunks + sends with the same schema. Whether the text got there via the old widget (pre-0.2.61) or the new chat command (0.2.62+), the read path is identical. No bump to `mod.GT_LOBBY_RPC_SCHEMA` required.

### Notes
v0.2.61-dev was an inline fix to `general_tweaker_data.lua` removing the broken `gt_lobby_motd_text` widget; the MOD_VERSION constant in `general_tweaker.lua` was not bumped at the time. This 0.2.62 bump reconciles MOD_VERSION with the on-disk widget state.

The orphaned `gt_lobby_motd_text` / `gt_lobby_motd_text_tooltip` localization keys (general_tweaker_localization.lua:529-530) are harmless — VMF resolves them only when a widget references the setting_id, which no longer happens. Left in place against the possibility of a future custom widget type or HeroView authoring UI.

## 0.2.60-dev (2026-05-25) -- Absorb lobby_tweaker (slot reservations, session ignore, kick-idle, MOTD, failed-join mod-list reveal); add GT_LOBBY_RPC_SCHEMA versioning (closes Issue #43)

### Why
User direction 2026-05-25: "I deleted lobby tweaker, merge its features into general tweaker." Following the same archive-not-delete pattern used for `la_prefix_patch` earlier the same day. Issue #43 -- "Propagate RPC schema_version pattern to lobby_tweaker (lt_motd_show)" -- becomes gt's responsibility on absorption and is closed simultaneously.

### Changed
- **New files:** Seven `_gt_lobby_*.lua` modules under `general_tweaker/scripts/mods/general_tweaker/` migrated 1:1 from lt v0.1.7-dev:
  - `_gt_lobby_slot_reservations.lua` (was `lobby_tweaker/_slot_reservations.lua`)
  - `_gt_lobby_session_ignore.lua` (was `_session_ignore.lua`)
  - `_gt_lobby_kick_idle.lua` (was `_kick_idle.lua`; warn-lead-time hardcoded constant promoted to live read of `gt_lobby_ki_warn_seconds` setting)
  - `_gt_lobby_motd.lua` (was `_motd.lua`; RPC renamed `lt_motd_show` -> `gt_lobby_motd_show`; **NEW:** schema-versioned per VMF_RECIPES § 10)
  - `_gt_lobby_modded_manifest.lua` (was `_modded_manifest.lua`; lobby-data key prefix `ltw_` RETAINED for cross-mod compat with peers still on lt)
  - `_gt_lobby_failed_join_reveal.lua` (was `_failed_join_reveal.lua`; popup action key `lt_open_workshop` -> `gt_lobby_open_workshop`)
  - `_gt_lobby_known_mods.lua` (was `_known_mods.lua`; dropped retired `lobby_tweaker` and `la_prefix_patch` entries; `gt` retagged "C")
- **`general_tweaker.lua`:**
  - `MOD_VERSION = "0.2.60-dev"` (bumped from `0.2.59-dev`).
  - **NEW:** `mod.MOD_VERSION` exposed as a public field on the gt mod table (mirroring lt convention; consumed by bt's `/bug_report` walker and the new gt_lobby manifest broadcaster).
  - **NEW:** `mod.GT_LOBBY_RPC_SCHEMA = 1` declared near MOD_VERSION per VMF_RECIPES § 10. First positional arg of every `mod:network_send` on `gt_lobby_motd_show`; receiver gates on the value and drops with `_dbg_alert` on mismatch.
  - **NEW:** `mod._gt_register_update` exposed so `_gt_lobby_*` modules can plug into gt's central per-frame tick (gt Issue #16's update-consumer registry) instead of using the old `_prev_update = mod.update; mod.update = function(dt) ... end` chain.
  - **NEW:** `mod._gt_dbg` / `mod._gt_dbg_alert` exposed for sibling-file consistency.
  - Six `mod:dofile` calls at the bottom load the new `_gt_lobby_*` modules.
  - **NEW:** `_rt_register("gt_lobby_rpc_schema_present", ...)` regression test verifies `mod.GT_LOBBY_RPC_SCHEMA` is a number >= 1 (matches the ct pattern from v0.7.114-dev).
- **`general_tweaker_data.lua`:** New top-level group `gt_lobby_controls_group` with 12 sub-widgets (slot-reservations / session-ignore / 3x kick-idle / 5x MOTD / 2x manifest), inserted above the universal `enable_debug_logging` toggle.
- **`general_tweaker_localization.lua`:** ~30 new keys for the new group + sub-widget tooltips + the failed-join popup body strings.
- **`itemV2.cfg`:** Updated title (auto-managed via MOD_VERSION suffix) and description (mention "now includes Tweaker: Lobby's host-side controls").

### Chat-command rename
| Old (`lt`) | New (`gt`) |
|---|---|
| `/lt_reserve` / `/lt_unreserve` / `/lt_reservations` | `/gt_lobby_reserve` / `/gt_lobby_unreserve` / `/gt_lobby_reservations` |
| `/lt_ignore` / `/lt_ignore_persist` / `/lt_unignore` / `/lt_ignored` / `/lt_ignore_last` | `/gt_lobby_ignore` / `/gt_lobby_ignore_persist` / `/gt_lobby_unignore` / `/gt_lobby_ignored` / `/gt_lobby_ignore_last` |
| `/lt_idle_whitelist` / `/lt_idle_unwhitelist` / `/lt_idle_status` | `/gt_lobby_idle_whitelist` / `/gt_lobby_idle_unwhitelist` / `/gt_lobby_idle_status` |
| `/lt_motd_test` | `/gt_lobby_motd_test` |
| `/lt_manifest_dump` / `/lt_manifest_probe` | `/gt_lobby_manifest_dump` / `/gt_lobby_manifest_probe` |

### Settings migration note
Settings carry NEW keys (`gt_lobby_*`) under the gt mod-id, NOT under lt's mod-id. Previously-saved lt settings (`%APPDATA%\Fatshark\Vermintide 2\user_settings.config` -> lobby_tweaker entries) are NOT carried over -- users will see defaults on first load and need to re-enable any features they were using. The user_settings.config lt block becomes inert; it can be hand-deleted but is otherwise harmless.

### Archive
- `lobby_tweaker/` moved to `_archive/lobby_tweaker_v0.1.7-dev/` via `Move-Item` (per the global "no recursive-delete" rule + la_prefix_patch precedent).
- `_archive/lobby_tweaker_v0.1.7-dev/_ARCHIVED.md` documents the merge with full feature-inventory mapping table.
- Workshop item `3729845515` left in place on Steam (user can mark private / hidden via Steam web when convenient).
- GitHub release `mods-2026-05-24` still ships `lobby_tweaker.zip` -- left intentionally so existing vt2-mod-updater consumers don't break. Will fall out of next release tag (lt entry removed from `tools/publish-release/publish-release.ps1`).

### Dereferenced
- `CLAUDE.md` -- removed the lobby_tweaker row from the Mod Directory; gt row expanded to list the absorbed features. Mod count: 17 -> 15 active (la_prefix_patch + lobby_tweaker both retired today).
- `MOD_OWNERSHIP.md` -- removed lt row; added the second NOTE at the bottom (alongside the la_prefix_patch one).
- `tools/publish-release/publish-release.ps1` -- removed lt entry from `$mods`.
- `COMMANDS.md` -- gt section expanded with the 14 new `/gt_lobby_*` commands; snapshot-date note updated.

### Build
`VMBLauncher.exe build general_tweaker` -- OK, 4 bundles, 1.72s. NOT deployed, NOT uploaded (per 2026-05-25 EOD doctrine: no Workshop pushes without per-build user approval).

### Closes
- GitHub Issue #43 (Propagate RPC schema_version pattern to lobby_tweaker (lt_motd_show)) -- resolved by merge.

## 0.2.59-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[gt] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- general_tweaker.lua -- removed the load-time `mod:echo("general_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[gt] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("general_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build general_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.58-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- general_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- general_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build general_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.2.57-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[gt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `general_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[gt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.2.57-dev.

## 0.2.56-dev (2026-05-25) — Three-issue audit bundle (Issues #13 / #15 / #16)

### Why
Three open audit issues against `general_tweaker.lua` resolved in a single version bump to avoid churn.

### Issue #13 — `_pause_active` forward-ref bug (one-line fix)
`on_game_state_changed` at line ~688 writes `_pause_active = false`, but the file-local `local _pause_active = false` lived at line ~2153 — well below the closure's compile point. Lua name resolution happens at function compile time, so the assignment was binding to a **global** `_pause_active` instead of the file-local that the pause/time-scale toggle (`gt_pause_toggle` / `gt_time_apply`) reads. After a level transition while paused, the next `/gt_pause` toggle desynced from the engine's actual pause state (off-by-one).

**Fix:** added `local _pause_active` forward declaration alongside the existing `_apply_godmode` / `_ai_handle_toggle_change` forward-decls near the top of the file. Changed the line ~2153 declaration from `local _pause_active = false` to `_pause_active = false` (no `local`) so it reuses the forward-decl slot instead of shadowing it.

### Issue #15 — `on_disabled` leaves global mutations behind
The mod has `is_togglable = true` but `on_disabled` previously only restored the camera offset. Every other mutation (script_data flags, RagdollSettings, BuffTemplates.power_level_unbalance, CareerSettings[*].attributes.base_critical_strike_chance, PlayerUnitMovementSettings.move_speed + closed-upvalue per-unit copy, InventorySettings, DamageUtils.is_in_inn, GameSettingsDevelopment.disable_free_flight, ESC-menu inventory entry) persisted after disable.

**Choice:** documented the limitation rather than authoring a snapshot-on-enable + restore-on-disable refactor across every mutated table. Cheap and honest; full unwind deferred as a larger refactor.

**Fix:**
- `on_disabled` now `mod:echo`s a one-line warning: *"Disable does not fully unwind active mutations. Restart the game for a clean vanilla state."*
- `itemV2.cfg` description's **Compatibility** section gained the same caveat as a bullet so users see it before subscribing / disabling.

### Issue #16 — Layered `mod.update` chain (5 rewraps, no registry)
`general_tweaker.lua` previously rewrapped `mod.update` five separate times using the `local _orig = mod.update; mod.update = function(dt) _orig(dt); ... end` chain idiom (lines 287/522/2486/2693/3027). No central registry, no inline `-- consumer #N: <feature>` header, no per-consumer error isolation. A single accidental edit `mod.update = function(dt) ... end` without preserving `_orig` would silently drop every earlier consumer — invisible until the dropped feature stopped working.

**Fix:** added a `_update_consumers` registry near the top of the file (after the `mod:echo` load banner). Single `mod.update = function(dt)` body iterates the consumer list and pcalls each consumer. Converted all 5 sites to `_register_update("<feature>", function(dt) ... end)` with these feature names (registration order preserved so dependencies still run in the original order):
1. `tp_camera` — `_tp_reapply_timer` countdown
2. `post_spawn_reapply` — `_post_spawn_reapply_timer` countdown + noclip locomotion heartbeat
3. `infinite_ammo_and_ai_pending` — 1Hz infinite-ammo refresh + AI takeover queue consumers
4. `cutscene_auto_skip` — deferred auto-skip processor
5. `hide_ui` — per-frame HUD mode enforcement

**Bonus:** pcall isolation per-consumer — one consumer error no longer kills the others. Errors surface as `mod:error("[gt:update] consumer '<name>' raised: ...")`.

### Changed
- `scripts/mods/general_tweaker/general_tweaker.lua`:
  - `MOD_VERSION` → `0.2.56-dev`.
  - Added `local _pause_active` forward declaration (Issue #13).
  - Dropped `local` from the line ~2153 `_pause_active = false` assignment (Issue #13).
  - Added `mod:echo` warning to `on_disabled` (Issue #15).
  - Added `_update_consumers` registry + single `mod.update` dispatcher near top of file (Issue #16).
  - Converted 5 `mod.update = function(dt) ...` rewrap sites to `_register_update("<feature>", function(dt) ...)` (Issue #16).
- `itemV2.cfg` — title bumped to v0.2.56-dev; description gained the disable-caveat bullet (Issue #15).

## 0.2.55-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `general_tweaker.lua` — installed `_dbg_alert` helper alongside both existing `_dbg` definitions (the top-of-file one at line ~9 and the second observation-hooks one at line ~773 which lexically shadows the first). Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing six gt regression checks.
- `itemV2.cfg` — bumped to v0.2.55-dev.

### Notes
- 0 of the existing 7 `_dbg(...)` call sites reclassified to `_dbg_alert` — all are state/transition tracking (e.g. `[state] X | ctx | cim=Y`, `[hero_view] on_enter | ctx`, `[transition] X | ctx`). None match the alert signature words.
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/gt_*` / `/dump_*` chat command bodies (user-operational, leave alone) or the unconditional load banner.

## 0.2.54-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). gt previously had `gt_debug_mode` nested in `gt_debug_group` — renamed and un-nested.

### Changed
- `general_tweaker_data.lua` — removed `gt_debug_group` wrapper; `gt_debug_mode` renamed to `enable_debug_logging` at top-level bottom of `options.widgets`.
- `general_tweaker_localization.lua` — removed `gt_debug_group` / `gt_debug_mode` / `gt_debug_mode_tooltip`; added `enable_debug_logging` + `enable_debug_logging_tooltip`.
- `general_tweaker.lua`:
  - `_dbg_on()` now reads `mod:get("enable_debug_logging")` (was `gt_debug_mode`). All existing call sites untouched (they go through the helper).
  - Added file-local `_dbg(fmt, ...)` helper at top of file for new call sites. Output prefix `[gt:dbg]`.
- `itemV2.cfg` — title bumped to v0.2.54-dev.

### Notes
- **Migration**: the saved value of `gt_debug_mode` is not auto-carried into `enable_debug_logging`. Users who had the old toggle on must re-tick the new `Debug Logging` checkbox after first load. VMF defaults the new key to `false`.

## 0.2.53-dev (2026-05-25) — Stop `_ctx_str` from ERRORing on boot/title state transitions (Network backend has not been set)

### Why
Every session logged 4 ERROR-level entries during boot and title-screen transitions:

```
[Lua] Error: scripts/managers/player/player_manager.lua:559: Network backend has not been set
  [3] @scripts/managers/player/player_manager.lua:559: in function local_player
  [4] @scripts/mods/general_tweaker/general_tweaker.lua:784: in function _ctx_str
  [5] @scripts/mods/general_tweaker/general_tweaker.lua:812: in function <810>
  ...
  event_name = "on_game_state_changed"; _ = "gt"
[MOD][gt][ERROR] (event) on_game_state_changed: scripts/managers/player/player_manager.lua:559: Network backend has not been set
```

Not crash-causing, but log noise that hides real warnings.

Root cause: vanilla `PlayerManager:local_player()` (`player_manager.lua:559`) calls `self.network_manager.peer_id()` and asserts when `network_manager` is nil. `_ctx_str`'s existing guard only checked that the `local_player` method EXISTS on `Managers.player`, not that the network backend had been wired up via `PlayerManager.set_is_server(...)`. During the boot transition through `StateTitleScreen` and the 3 follow-on state-machine churns, the manager exists but `network_manager` is still nil.

### Changed
- `general_tweaker.lua` `_ctx_str` — added a precise pre-check for `Managers.player.network_manager ~= nil` alongside the existing method-presence check before calling `Managers.player:local_player()`. When the backend isn't up yet, `profile`/`career` fall back to `<pre-backend>` so the calling `_dbg("[state] ...")` debug log still gets a complete formatted string. Picked the structural pre-check (Option C in the task brief) over `pcall` because it handles future state additions automatically without depending on the engine-level assert being catchable from Lua, and over the state-name skip (Option B) because that would only fix the 4 documented firings.

### Verification
- Boot the game and watch the log: zero `[MOD][gt][ERROR] (event) on_game_state_changed: ... Network backend has not been set` lines.
- `[MOD][gt][DEBUG] [state] exit StateTitleScreen | mech=? level=? in_keep=false view=? profile=<pre-backend> career=<pre-backend> | cim=...` is the expected pre-backend shape; once the network manager is wired the fields populate normally.

## 0.2.52-dev (2026-05-24) — Force VMF re-handshake before AI Takeover client send (vmf_users bot-churn drop)

### Why
v0.2.50 used the correct API path to resolve the host peer_id but the send still silently dropped. Diffing PC-A's `console-2026-05-24-23.07.16*.log` against PC-B's `console-2026-05-24-23.08.54*.log` revealed the actual mechanic:

```
PC-B 23:10:11.110 [MOD][VMF][INFO] Added 11000010ef3befb to the VMF users list.
PC-B 23:10:11.112 [MOD][VMF][INFO] Removed 11000010ef3befb from the VMF users list.
PC-B 23:10:58.511 [MOD][gt][INFO] [ai_toggle emit] CLIENT->req host=11000010ef3befb want_bot=true
PC-A 23:07:53 +   (no [ai_toggle recv] line ever)
```

VMF's `PlayerManager.remove_player` hook (upstream `vmf/scripts/mods/vmf/modules/core/network.lua:375-404`) has a logic bug: when ANY player owned by peer_id is removed AND that peer still has a human_player on the same peer_id, it removes the WHOLE peer from `_vmf_users`. Host bot churn at mission load fires `remove_player(host_peer, bot_local_id)`; the host's own human player matches the "still has human_player" loop check, so VMF drops the host. Once dropped, `convert_names_to_numbers` returns nil and every `mod:network_send(..., host_peer, ...)` silently no-ops.

### Changed
- `general_tweaker.lua` — client toggle path now calls `get_mod("VMF").ping_vmf_users()` to force a VMF re-handshake before each send (pong round-trip ~50–300 ms on Steam P2P repopulates `_vmf_users[host_peer]`).
- Replaced inline send with `_ai_pending_client_send` queue + `_ai_consume_pending_client_send` drainer wired into the existing mod.update chain. Queue retries the send up to `_AI_CLIENT_SEND_MAX_RETRIES = 3` times with `_AI_CLIENT_SEND_DELAY_RETRY = 0.4 s` between attempts, re-pinging VMF each time. Idempotent — the host's RPC handler no-ops if state already matches.

### Regression tests (run `/gt_regression_test` in game)
- `ai_takeover_vmf_ping_api_available` — pins `get_mod("VMF").ping_vmf_users` as a callable function. If VMF ever renames or removes this entry point, our workaround silently no-ops via the pcall and every client toggle would silently drop again. Both the mod presence and the function shape are asserted.
- `ai_takeover_client_send_queue_wired` — synthetic enqueue with an already-elapsed `next_at`, then drives one mod.update tick and asserts the queue drained. Catches "consumer not wired into mod.update" regressions.

### Verification
1. Host on PC-A, client PC-B, mid-mission.
2. PC-B toggles AI Takeover (`/ai` or checkbox).
3. PC-B chat shows "AI ON (requested from host)." and PC-B log shows `[ai_toggle queue] CLIENT host=<pca> want_bot=true retries=3` followed by `[ai_toggle emit] CLIENT->req ... (attempt 1 of 3)`.
4. PC-A log shows `[ai_toggle recv] HOST<-req sender=<pcb> payload=table` followed by `[ai_toggle] human->bot for <pcb>: ok`.
5. PC-B character is bot-controlled. Toggle off → bot removed, human restored.
6. `/gt_regression_test` reports `PASS: ai_takeover_vmf_ping_api_available` and `PASS: ai_takeover_client_send_queue_wired`.

## 0.2.50-dev (2026-05-24) — Fix wrong server_peer_id path in v0.2.49 AI Takeover fix

### Why
v0.2.49-dev resolved the host peer_id via `Managers.state.network.server_peer_id`. That field doesn't exist on `GameNetworkManager` (which IS `Managers.state.network`, set in `state_ingame.lua:2194`). The lookup always returned nil, so every client toggle refused with "AI toggle: host peer_id not yet known (session still loading?)". PC-B log `console-2026-05-24-15.58.17*.log` lines 7570/7609/7612 — three rejected attempts at 16:00:43–16:00:51, well after the session-join handshake at 15:59:57.

### Changed
- `general_tweaker.lua` `_ai_handle_toggle_change` — resolve via the canonical `Managers.mechanism:server_peer_id()` (verified in vanilla at `imgui_career_debug.lua:153` + `versus_mechanism.lua:1845`). Falls back to `Managers.state.network.network_client.server_peer_id` (client) / `.network_server.server_peer_id` (host) for the brief window where mechanism hasn't published yet.
- `VMF_RECIPES.md` § 3 — fixed the (wrong) recipe that v0.2.49 followed. The published recipe now uses `Managers.mechanism:server_peer_id()` with the same fallback chain.

### Verification
1. Host on PC-A, client PC-B, mid-mission.
2. PC-B toggles AI Takeover. PC-B's chat shows "AI ON (requested from host).".
3. PC-B's log has `[ai_toggle emit] CLIENT->req host=<pca-peer> want_bot=true`.
4. PC-A's log has `[ai_toggle recv] HOST<-req sender=<pcb-peer> payload=table` followed by `[ai_toggle] human->bot for <pcb-peer>: ok`.
5. PC-B is now bot-controlled. Toggle off restores the human Player.

## 0.2.49-dev (2026-05-24) — Fix AI Takeover from client (RPC was silently dropped)

### Why
PC-B (client) toggled "AI Takeover" mid-mission. The chat echo printed ("AI ON (requested from host).") but PC-A (host) never received the RPC — the client's character stayed under player control, no bot ever spawned. PC-A's `console-2026-05-24-15.13.52*.log` shows zero `[ai_toggle]` lines; PC-B's `console-2026-05-24-15.09.09*.log` shows the local echo at 15:29:13/25/30 but no corresponding host-side receipt.

Root cause: `_ai_handle_toggle_change` called `mod:network_send(_AI_RPC, "server", ...)`. VMF's `convert_names_to_numbers` accepts exactly four recipient forms — `"all"`, `"others"`, `"local"`, or a literal peer_id. `"server"` falls through the lookup, is treated as a literal peer_id, fails `_vmf_users[peer_id]`, and returns silently with no error and no wire activity. Documented in `VMF_RECIPES.md` § 3 — same gotcha that burned `cosmetics_tweaker` v0.8.67 → v0.9.0.15.

### Changed
- `general_tweaker.lua` `_ai_handle_toggle_change` — resolve the host's real peer_id from `Managers.state.network.server_peer_id` before sending. If the field is nil (transient during host migration / level transition), return `(false, "host peer_id not yet known...")` so the checkbox auto-reverts via the existing failure-revert path.
- Added emit/recv diagnostic `mod:info("[ai_toggle emit] CLIENT->req ...")` at the client send site and `mod:info("[ai_toggle recv] HOST<-req ...")` at the top of the `network_register` handler. Per the VMF_RECIPES detection recipe — if recv ever stops firing again, the asymmetry is now visible in a single grep.

### Verification
1. Host VT2 on PC-A with General Tweaker v0.2.49-dev. Join from PC-B as client.
2. Start any adventure / weave / deus mission.
3. On PC-B, toggle "AI Takeover" in Mod Settings → General Tweaker (or `/ai`).
4. PC-B chat shows "AI ON (requested from host).".
5. PC-A's console log gets a fresh `[ai_toggle recv] HOST<-req sender=<pc-b peer> payload=table` line followed by `[ai_toggle] human->bot for <pc-b peer>: ok`.
6. PC-B's player is now controlled by a bot. Toggle off → bot is removed and the human Player is re-added.

## 0.2.48-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.2.47 rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 2: the v0.2.47 `NetworkLookup.pickup_names` rawget conversion was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked an in-mod `_rt_register` runtime check. Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test.

### Added
- Source-pattern marker constant `CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = "gt-pickup-lookup-rawget-hardened"` near the top of `general_tweaker.lua`.
- `_rt_register("gt_pickup_lookup_uses_rawget", ...)` at the bottom of `general_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value.
  2. `rawget(NetworkLookup.pickup_names, <known-bad-key>)` returns `nil` without raising.

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/gt_regression_test` in chat. Expect `PASS: gt_pickup_lookup_uses_rawget` alongside the pre-existing checks.

## 0.2.47-dev (2026-05-23) — Convert 1 NetworkLookup lookup to rawget (latent strict-__index crash fix)

### Why
`NetworkLookup.*` subtables install a strict `__index = error()` metatable at boot. Plain `NetworkLookup.foo[key]` on a missing key throws — see memory `reference_vt2_strict_lookup_rawget.md`. The lint pass on 2026-05-23 flagged the `/spawn`-pickup site as latent: the key currently comes from the curated `_gt_is_pickup_names` list (all vanilla-registered), so it never misses today, but is a latent bomb if anything changes the surrounding data flow.

### Changed
- `general_tweaker.lua` (`_gt_is_spawn`) — converted `NetworkLookup.pickup_names[pickup_name]` to `rawget(NetworkLookup.pickup_names, pickup_name)` with a guard that echoes "Unknown pickup name" and returns instead of crashing the strict-lookup path.

### Verification
1. `tools/mod-lint/lint-mod.ps1` — passes.
2. `tools/lint/regression-lint.ps1 -Quiet` — site no longer appears in `strict-table-lookup` findings.

## 0.2.46-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `general_tweaker.lua` — renamed `regression_test` → `gt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/gt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.2.32-alpha (2026-05-19)

### Fixed: Command-name collisions with Janoti's "Hacks" mod

The v0.2.26 → v0.2.31 port copied 11 command names verbatim from Hacks (Helpers 2). VMF only allows one global registration per command name; the first mod to load wins the slot and the other's registration is silently dropped with an error in console. Gt was loading before Hacks (alphabetical), so Hacks lost `/pause`, `/win`, `/fail`, `/restart`, `/kill_bots`, `/die`, `/ult_reset`, `/infinite_stamina`, `/giga_power`, `/inn_dmg`, and `/unkillable` entirely. Renaming gt's claims here releases all 11 slots back to Hacks.

| Old gt name | New gt name |
|---|---|
| `/pause` | `/gt_pause` |
| `/win` | `/gt_win` |
| `/fail` | `/gt_fail` |
| `/restart` | `/gt_restart` |
| `/kill_bots` | `/gt_killbots` |
| `/die` | `/gt_die` |
| `/ult_reset` | `/gt_ultreset` |
| `/infinite_stamina` | `/gt_stamina` |
| `/giga_power` | `/gt_gigapower` |
| `/inn_dmg` | `/gt_inndmg` |
| `/unkillable` | `/gt_unkillable` |

Hotkey widgets unchanged (they bind to `mod.gt_*` functions which were always gt-namespaced). Settings UI labels unchanged. Tooltips updated to reference the new command names.

`/win` had been a gt command since before the port too (renamed alongside the others — same collision).

## 0.2.31-alpha (2026-05-19)

### Changed: Disable Enemy Spawns now also flips the `script_data.ai_*` flag set
### Added: Engine-error nil-guards from Janoti's "Hacks" (Group F — final port batch)

**Broadened `/no_enemies` toggle:** the two `ConflictDirector` hooks still catch every spawn call, but the toggle now ALSO flips the same `script_data.ai_*_disabled` flag set Hacks uses (mini_patrol, critter, horde, roaming, boss, rush_intervention, specials, pacing, outside_navmesh_intervention). The script_data path aborts spawns earlier in the pacing/intervention pipelines so the spawner doesn't even queue work. Per `feedback_redundant_safeguards_ok` redundancy is welcome here — cost is nine boolean writes per toggle, missed-path failure (an enemy slipping through) is silent. `_apply_script_data_no_enemies` is forward-declared at the top of the file because `on_setting_changed` (which lives above the no_enemies section) needs to call it.

**Engine-error nil-guards (passive):** two `mod:hook` wrappers that no-op the call when the target unit is dead/nil, copied from Hacks:

- `VolumetricsFlowCallbacks.unregister_fog_volume(params, ...)` — bails if `params.unit` is nil or `not Unit.alive(params.unit)`. Suppresses the red `[Engine Error]` spam that occasionally shows up when a fog volume's owner unit was already collected.
- `Unit.get_data(unit, ...)` — bails if `unit` is nil. Suppresses error spam from systems that hand stale unit handles back to the engine during cleanup.

Both guards are pure pre-checks — the original function runs unchanged when inputs are valid.

This concludes the Janoti "Hacks" feature port (Groups A–F across v0.2.26 → v0.2.31). All 17 missing features ported plus 2 expansions to existing gt features.

## 0.2.30-alpha (2026-05-19)

### Added: Player State Toggles group — port from Janoti's "Hacks" (Group E)

Three small toggles kept distinct from gt's existing `god` umbrella:

- **`/inn_dmg`** — host-only flip of `DamageUtils.is_in_inn`. When the inn flag is off, the keep behaves like a mission (damage taken normally). Useful for sparring with bots in the keep without flipping all of godmode.
- **`/cloak`** + hotkey — visual invisibility (model hidden + invisible to AI). Uses `set_invisible(true, false, "gt_cloak")` with its own reason namespace so toggling cloak doesn't clobber godmode's invisibility (which uses `"gt_godmode"`) and vice versa.
- **`/unkillable`** — flips `script_data.player_unkillable`. You take damage normally, you can be grabbed by disablers, but the engine refuses to drop you below 1 HP. Different intent from `god` — this is "I want to feel hits while testing".

Only `cloak` gets a hotkey widget; the other two are command-only since they're niche toggles.

## 0.2.29-alpha (2026-05-19)

### Added: Buffs & Stats group — port from Janoti's "Hacks" (Group D)

New "Buffs & Stats" settings group + three chat commands + two sliders:

- **`/infinite_ammo`** — toggle infinite ammo + zero overheat. Applies the vanilla `twitch_no_overcharge_no_ammo_reloads` buff to the local player; if you're the host, also pushes it to every other player. Periodic re-apply every 1 second via the shared `mod.update` chain keeps the buff refreshed if anything tries to strip it.
- **`/infinite_stamina`** — toggle infinite stamina. Hooks `GenericStatusExtension.add_fatigue_points` and short-circuits the call when the flag is on, so stamina-cost actions (block, push, dodge-cost) never deplete the bar.
- **`/giga_power`** — multiply the Enhanced Power talent buff by 1000x. Snapshots the original `BuffTemplates.power_level_unbalance.buffs[1].multiplier` on first activation and restores it on toggle-off. Requires re-equipping the talent for the buff to refresh.
- **Base Crit Chance slider (0–100%)** — rewrites the current career's `CareerSettings[name].attributes.base_critical_strike_chance`. Auto-snaps back to that career's vanilla value when you switch careers (hooks `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed`). Per-session — game restart restores defaults.
- **Movement Speed slider (0–30 m/s)** — rewrites `PlayerUnitMovementSettings.move_speed` plus every per-unit override already snapshotted by the engine (reached via `debug.getupvalue(unregister_unit, 1)` since the per-unit table is a closure local). Per-session.

The infinite-stamina hook is always-registered (toggling on/off flips a flag inside the closure) to avoid VMF's duplicate-registration error.

## 0.2.28-alpha (2026-05-19)

### Added: Ult Controls group — port from Janoti's "Hacks" (Group C)

New "Ult" settings group with three features, all driven through `CareerExtension`:

- **`/ult_reset`** + hotkey — one-shot reset. Walks `_num_abilities` and calls `:reduce_activated_ability_cooldown_percent(i, 1)` on each, dropping every charge to 0 cooldown. Same primitive ThePageMan's "No Ult Cooldown" mod uses.
- **Cap Player Ult Cooldown** (toggle + 0–120s slider) — clamps every player-controlled career ability's remaining cooldown to at most the configured value, every `CareerExtension.update` tick. Effectively a configurable "short ult" without burning a talent slot.
- **Cap Bot Ult Cooldown** (toggle + 0–120s slider) — same idea but for AI-controlled units. Useful in solo-with-bots to see bots ult more aggressively.

Both caps share `mod._gt_clamp_cooldowns` which walks the ability's `cooldowns` array from the decaying-charge index downward, trims each entry, then re-runs the engine's `cooldown_paused` / `set_activated_ability_cooldown_unpaused` housekeeping so the ability HUD overlay stays in sync. This is the iteration pattern the engine expects — replicating it any other way desyncs the UI.

## 0.2.27-alpha (2026-05-19)

### Added: Time & Pause group — port from Janoti's "Hacks" (Group B)

New "Time & Pause" settings group with five widgets + three chat commands. Both features use the same engine primitive: `Managers.state.debug:set_time_scale(index)` where `index` selects an entry in `debug_manager.lua`'s `time_scale_list` (24 multipliers, index 13 = 1.0x).

- **Time Scale slider (1–24)** — change live; the new value is applied immediately and re-applied on every `StateIngame` entry (vanilla wipes the engine time scale on level transitions).
- **`/time_faster` / `/time_slower`** + bindable hotkeys — step the slider up/down by 1.
- **`/pause`** + hotkey + Pause Speed slider (1–24, default 1) — host-only toggle between the configured pause speed and normal. VT2 has no true freeze primitive; `set_time_scale(1)` is the closest thing (UI still updates). Clients see the change since time scale is server-driven.

The pause feature and the time slider share the same engine setter; if both are touched in the same session, the last write wins. We keep them as separate widgets matching Hacks's UX. Setting the slider while paused updates the post-unpause target but doesn't override the active pause speed.

## 0.2.26-alpha (2026-05-19)

### Added: Level Control group — port from Janoti's "Hacks" (Group A)

New "Level Control" settings group + six chat commands + six bindable hotkeys, sourced from the corresponding features in Janoti's [Hacks](https://steamcommunity.com/sharedfiles/filedetails/?id=3266071368) (uploaded as "Helpers 2"):

- **`/fail`** + hotkey — fail the current mission (`Managers.state.game_mode:fail_level()`).
- **`/restart`** + hotkey — retry the current mission (`Managers.state.game_mode:retry_level()`).
- **`/kill_bots`** + hotkey — kill every bot in the party. On EAC-secure realm only allowed pre-round (vanilla anti-cheat would flag mid-round bot kills); unrestricted on modded realm.
- **`/die`** + hotkey — kill your local character (`death_system:kill_unit`).
- **`/fix_sound`** + hotkey — stop the looping vortex SFX that gets stuck after restarting mid-storm. Fires `sfx_player_in_vortex_false` on the local first-person extension, same trick Craven's script uses.
- **`/win`** also gets a hotkey (the command itself already existed in v0.2.25).

All five level-flow commands no-op in the keep with a friendly echo so a mis-press while sorting loadout doesn't yank you out of the inn state machine. The `mod.gt_*` functions are exposed as named members (not just locals) so VMF's `keybind_type = "function_call"` resolver can find them via the `function_name` string.

## 0.2.24-alpha (2026-05-17)

### Added: Skip Intro Splash Screens toggle

New "Startup" group with a single checkbox: **Skip Intro Splash Screens**. Same end result as bIbIbI's [Skip Intro mod](https://steamcommunity.com/sharedfiles/filedetails/?id=1395453301) — skips the Fatshark/engine logo splash sequence at game launch.

Implementation uses the canonical vanilla bypass: `StateSplashScreen.on_enter` (state_splash_screen.lua:92-110) checks a set of `Development.parameter` flags including `"skip_splash"` — if any are set, `self._skip_splash = true` and the splash sequence is bypassed. Same mechanism as the `-skip-splash` command-line argument.

`Development.set_parameter()` is a no-op in release builds, so we write directly to `Development._hardcoded_dev_params.skip_splash` (same trick the third-person camera section uses for `third_person_mode`). Done at mod load time, which runs before `StateSplashScreen.on_enter`, so the flag is in place when the check fires.

**Note:** changing the setting mid-session shows no immediate change — the splash for the current boot has already run. The flag is still updated so the next launch reflects the new setting.

## 0.2.23-alpha (2026-05-17)

### Added: AI Takeover VMF widget

The `/ai` command from v0.2.22 is now also exposed as a checkbox in the Gameplay group ("AI Takeover (bot controls your character)"). Chat command and checkbox stay in lockstep — the command just flips the setting, and `on_setting_changed` runs the same RPC pipeline. Auto-resets to off on game state change (level transition / leaving a mission) so the checkbox never persists a stale "on" across runs that didn't actually swap.

Same v1 scope as v0.2.22: client-only, refused on host self-toggle, refused in versus and the keep.

## 0.2.22-alpha (2026-05-17)

### Added: AI Toggle (`/ai`) — hand off control to a bot mid-mission

New chat command `/ai` lets a **client** hand their character over to bot AI (and toggle back). Useful for multiplayer testing where the mod author hosts on one machine and wants the second machine's player to behave as a bot, and as a general "stepping away" utility for clients who need to leave mid-run.

VT2 has no hot-swap path between human and bot units — they use different `go_type`s with incompatible extension stacks. So toggling means despawn-human + add-bot (and the reverse). Both halves of the dance exist in vanilla (see `GameModeBase._add_bot_to_party` / `_remove_bot_instant` and `GameModeAdventure.player_entered_game_session`); we compose them and wire them to a player-driven trigger.

Server-driven by necessity — `ProfileSynchronizer` and `PartyManager` mutation APIs all assert `is_server`. Client sends a VMF network request (`gt_ai_toggle_request`) and the host runs the swap. Host saves the original peer/profile metadata; toggling again recreates the human Player object via `add_remote_player`, re-claims the slot via `assign_peer_to_party`, and re-assigns the profile via `assign_full_profile(..., is_bot=false)`. Spawning system picks them up next tick.

**v1 scope:**
- Client (remote peer) self-toggle: supported.
- Host self-toggle: refused with a message — destroying the host's local Player object mid-mission would tear down camera/HUD/input bindings that aren't trivial to recreate.
- Versus: refused (heroes have no bot AI in versus).
- Keep / inn: refused (no spawning system running).

**Known rough edges (acceptable for v1, will iterate based on testing):**
- Inventory / current ammo / temporary buffs don't persist across the swap — the bot inherits the profile's default loadout from the spawning system.
- Client-side camera transition when their unit despawns is whatever vanilla does for "your player_unit just got removed" (likely spectator-style); untested.

## 0.2.21-alpha (2026-05-16)

### Added: Disable Enemy Spawns toggle

New checkbox in the Gameplay group + `/no_enemies` chat command. When on, every enemy spawn — hordes, specials, bosses, patrols, and pre-placed level-load enemies — is refused. Every enemy in VT2 funnels through `ConflictDirector`'s two public entry points (`spawn_queued_unit` for the pacing-system queue, `spawn_unit_immediate` for terror events / scripted triggers); hooks on both refuse the call when the setting is on.

Existing enemies are NOT despawned — the toggle affects future spawns only. Combine with `/god` to walk past anything already alive when toggling mid-mission.

Tooltip + Workshop description updated. Chat-command bullet line in the Workshop description extended with `/no_enemies`.

## 0.2.20-alpha (2026-05-15)

### Changed: Godmode now also makes the player invisible to enemy AI

Uses the engine's own canonical signal — `GenericStatusExtension:set_invisible(true, false, "gt_godmode")` — which AI perception explicitly skips (`perception_utils.lua:381`). Same primitive Shade's Shadowfall ult uses, just with a `reason = "gt_godmode"` namespace so it doesn't clobber other invisibility sources.

`skip_third_person=false` so the 3P body fades as a visual cue that godmode is on. First-person view (1P weapon arms) is unaffected since those are a separate unit.

Belt-and-suspenders re-apply on each `GenericStatusExtension.extensions_ready` — `self.invisible` is reset to `{}` on extension init, so a level transition while godmode is on would otherwise leave the new player unit visible to AI.

Tooltip + Workshop description updated. Forward-declared `_apply_godmode` at the top of the file so `on_setting_changed` (defined before the godmode section) can bind to the local instead of a nil global — see `feedback_lua_forward_reference.md`.

## 0.2.19-alpha (2026-05-15)

### Changed: Godmode now also blocks disablers

The two `DamageUtils` hooks (add_damage_network, add_damage_network_player) stop hp damage but disablers (gutter runner / assassin pounce, packmaster hook, chaos-spawn / corruptor / tentacle grabs, hanging cage) bypass the damage pipeline entirely — they push the character state machine directly into the disabler state.

Hook `GenericStateMachine.change_state` (the chokepoint every `csm:change_state(state_name, params)` call funnels through) and drop the transition when (a) godmode is on AND (b) the unit is the local player AND (c) the requested state is one of: `pounced_down`, `grabbed_by_pack_master`, `grabbed_by_chaos_spawn`, `grabbed_by_corruptor`, `grabbed_by_tentacle`, `in_hanging_cage`. Normal gameplay states (`stunned`, `ledge_hanging`, `overpowered`, `knocked_down`, `dead`) are NOT touched.

Godmode tooltip + Workshop description updated to advertise the broader behaviour.

## 0.2.18-alpha (2026-05-14)

### Fixed: Free camera now actually freezes the player

The free camera (`/freecam`) was supposed to detach the camera while leaving the character in place — but WASD was still moving the character alongside the camera. The engine's `_enter_free_flight` calls `input_manager:block_device_except_service("FreeFlight", "keyboard", ...)` which is meant to stop the Player input service from receiving keyboard input, but empirically that block doesn't reliably stop the character state machine from reading movement.

Belt-and-suspenders fix: while freecam is active, also call `loco:set_disabled(true)` on the local player's locomotion extension. That yanks the unit out of the locomotion update list entirely — character state machine still ticks (animation pose, etc.) but no movement can be applied regardless of what the Player input service produces. On freecam exit (toggle off, F8 press, or level transition via the `_exit_free_flight` hook), `loco:set_disabled(false)` re-enables the character cleanly. `pcall`-wrapped to survive engine API drift.

## 0.2.17-dev — first public Workshop release (2026-05-14)

### Changed: Workshop visibility flipped private → public

gt was uploaded as `friends_only` from its inception. After the noclip feature landed and verified working in 0.2.17-dev, the user flagged the mod ready for a public release. `itemV2.cfg`:

- `visibility`: `"friends_only"` → `"public"`
- `title`: `"Tweaker: General (WIP)"` → `"Tweaker: General"`
- `description`: replaced the one-liner with a sectioned feature description matching ct/cim/the rest of the Tweaker series — Third-Person Camera, Noclip, Keep Menus in Missions, Gameplay toggles, Chat commands, Compatibility — plus the canonical BMC block.
- `preview.jpg`: replaced with the Tweaker General artwork (1024×1024, JPG q=85, 215 KB).

`upload_gt.ps1`'s visibility guard updated `friends_only` → `public` and `--allow-public` added so the launcher's safety gate is satisfied. Upload pushed via `vmblauncher upload general_tweaker --allow-public`; verified live via `ISteamRemoteStorage/GetPublishedFileDetails`: `visibility=0`, `file_size=1346271` (matches `bundleV2/` byte-for-byte).

## 0.2.17-dev (2026-05-14)

### Fixed: Noclip chat command now applies immediately

`/noclip` previously relied on `mod.on_setting_changed` firing after `mod:set("noclip_enabled", ...)` to actually flip the locomotion state. That worked from the VMF settings menu but was unreliable when toggled from the chat command. Added an explicit `_apply_noclip(new_val)` call after the `mod:set`, mirroring the same belt-and-suspenders pattern `/tp` already uses.

Also added `mod:info` diagnostic lines in `_apply_noclip` — every toggle now logs `[noclip] ON — loco.state now '...'` or `[noclip] no locomotion extension yet ...` so post-mortem debugging of "didn't work" reports is one log-grep instead of a re-build cycle.

## 0.2.16-dev (2026-05-14)

### Added: Noclip (player flies through walls)

New "Noclip" toggle in the Gameplay group plus a `/noclip` chat command. Unlike the existing detached freecam, noclip moves the **player body** through walls — WASD flies in look direction, Space/Ctrl for up/down, Left Shift for a speed boost. Two new numeric sliders (`noclip_speed` default 15 m/s, `noclip_boost_multiplier` default 3.0x) tune the base and boost speed.

Built on the engine's `script_driven_no_mover` locomotion state (used by chaos-spawn-grab and tentacle-grab), which teleports the unit by `velocity_wanted * dt` each tick without touching the mover — so static geometry, props, and enemies are all bypassed. The dead-simple `Mover.set_collision_disabled` / `set_mover_disable_reason("noclip", true)` paths don't work for players: the locomotion templates and `PlayerUnitLocomotionExtension` call `Mover.flying_frames(mover)` and `Mover.move(mover, ...)` without nil-guarding the mover, so nuking it fatals immediately. The no-mover *state* path bypasses both calls without touching the mover handle.

Three hooks make it stick:

1. **`PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`** — when noclip is on for the local player, ignore whatever velocity the character state machine wrote (walking writes ground-plane velocity, falling writes gravity) and compute our own from W/A/S/D + Space/Ctrl projected through the first-person camera rotation.
2. **`mod.update` heartbeat** — re-asserts `loco.state = "script_driven_no_mover"` each tick. Basic states (standing/walking/jumping/falling) don't touch `locomotion.state`, but transitions into ledge-hang / ladder / knockdown call `enable_script_driven_movement()` which would hand us back to the wall-respecting mover update.
3. **`PlayerUnitLocomotionExtension.extensions_ready`** — re-arms noclip on each player spawn (mission entry, respawn) if the persisted VMF setting is on. Without this, the setting stays "on" while the actual locomotion state is whatever the engine initialised it to (usually `script_driven`).

On toggle-off, the mover is snapped to the player's current position before handing control back, otherwise the mover stays at the entry point and the next `Mover.move()` yanks the player back there.

Caveats baked into the tooltip: toggling off mid-air drops you, and special states (ledge-hang/ladder/career-ability/knockdown) may briefly fight the mode.

## 0.2.10-dev (2026-05-01)

### Changed: Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`gt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`general_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3713619122` and internal mod ID `"gt"` preserved — existing user settings are unaffected.

`itemV2.cfg` set to `visibility = "private"` (overriding the prior local `upload/item.cfg` which had `"public"` — never re-asserted on Workshop because no upload was performed during the migration).
