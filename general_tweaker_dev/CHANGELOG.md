# General Tweaker Changelog

## v0.2.88-dev (2026-06-17) -- Solo & QoL: port of True Solo QoL Tweaks (error-free)

### Why
Reimplement the useful features of the third-party "True Solo QoL Tweaks" (workshop 1384087820, last updated 2021) as native gt toggles, so it can be dropped. Bonus: the original logs a CareerSettings error every launch (it indexes `career.activated_ability.ability_class` with no nil-check; VT2's Versus entries `vs_undecided`/`spectator` have no `activated_ability`). This port fixes that with a proper nil-guard. New file `_gt_solo_qol.lua`; new "Solo & QoL (from True Solo)" group, all toggles default OFF; Penlight dependency dropped (plain string fns).

### Added (toggles)
- **Auto-restart mission on team wipe** (`gt_solo_auto_restart_on_wipe`) — on a "lost" end-condition, return `"reload"` instead of going to the keep. `/gt_inn` bails to the keep manually.
- **Assassin / Packmaster spawn text warnings** (`gt_solo_assassin_text_warning`, `gt_solo_packmaster_text_warning`) — colored ASS!/PACK! count callout in the area-indicator banner. The spawn detector is **merged into the existing `ConflictDirector.spawn_queued_unit` hook** (no duplicate) via `mod._gt_solo_on_spawn_queued`; also hooks `Localize` / `PlayerHud.set_current_location` / `AreaIndicatorUI.update`.
- **Assassin/Packmaster hero voice callout** (`gt_solo_assassin_hero_vo`) — forces the hero's "I hear a Gutter Runner" / "I see a Skaven slaver" line on spawn.
- **Disable ult voice line** (`gt_solo_disable_ult_vo`) — the crash-fixed feature. Loops `CareerSettings` with `local aa = career.activated_ability; if aa and aa.ability_class …` (the nil-guard), de-dupes shared ability classes, skips `empire_soldier_tutorial`.
- **Disable mutator death explosions** (`gt_solo_disable_mutator_explosions`), **disable level intro audio** (`gt_solo_disable_intro_audio`), **disable fog** (`gt_solo_disable_fog`), **disable sun shadows** (`gt_solo_disable_sun_shadows`).
- **Draw boss-event spheres** (`gt_solo_draw_boss_spheres`) + **boss path progress** (`gt_solo_boss_path_progress`, StreamingInfo-guarded) — share one `EnemyRecycler.update` hook; sphere LineObject recreated on world change (no stale handle, no `on_game_state_changed` clobber).

### Not ported
- **AUTO_KILL_BOTS** — gt already has "Disable Bots (Solo)" (`gt_no_bots`).

### Notes
Pre-flight confirmed the only existing-hook collision was `ConflictDirector.spawn_queued_unit` (merged). All other hooks are fresh `(Class, method)` pairs. All feature bodies are pcall-guarded and gate on their toggle (no cost when off).

## v0.2.87-dev (2026-06-17) -- Fly-disable tweak corrected to cover BOTH bosses + both attack paths

Correction to the v0.2.86 fly tweak after deeper source review (user report: Halescourge also has a fly disable). The earlier version only scaled Nurgloth's melee swarm and wrongly claimed Halescourge had no fly attack.

- **Replaced** `gt_nurgloth_fly_stun_sec` (Nurgloth-only seconds slider) with **`gt_fly_disable_mult`** (multiplier, default 1.00 = vanilla) that scales BOTH "cloud of flies" disable paths used by Burblespue Halescourge AND Nurgloth the Eternal:
  - Nurgloth's close-range fly-swarm BT action — `BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration` (vanilla 8s; bt_swarm_action.lua:73).
  - The rare seeking **insect-swarm bomb missile** both bosses fire (`seeking_bomb_missile` -> projectile `insect_swarm_missile_01` -> explosion `chaos_slow_bomb_missile` / `_new` "fly_bomb") — `TrueFlightTemplates.sorcerer_slow_bomb_missile.attached_life_time` (vanilla 10s; true_flight_templates.lua:121, ai_breed_snippets.lua:1091, penny_ai_breed_snippets.lua:178, explosion_templates.lua:1325/1355).
  - A multiplier (not seconds) because the two paths have different vanilla durations (8 vs 10); 1.00 reproduces vanilla exactly. Both fly-blobs keep health 5, so the disable can still be ended early by killing the cloud — this only scales the max length.

## v0.2.86-dev (2026-06-17) -- Five new bot options + Nurgloth fly-swarm tweak

Five new bot toggles + one boss-mechanic slider, all default OFF, host-side only (bots/wipe checks run on the host), no network registration. New per-frame bot logic is consolidated into the SINGLE existing `PlayerBotBase.update` hook in `_gt_bot_fixes.lua` (no duplicate hook); new standalone hooks are on distinct `(Class, method)` pairs. All source citations verified against the decompiled vanilla source 2026-06-17.

### Bot Options (added to the existing group)
- **Don't fail the mission while a bot is alive** (`gt_bot_mission_fail_prevention`) — vanilla's wipe check `GameModeHelper.side_is_dead("heroes", ignore_bots=true)` (game_mode_adventure.lua:92) ignores bots, so the run ends when all *humans* are down. Hook forces `ignore_bots=false` for the heroes side so a living bot keeps the run going. Pairs with rescue-awaiting. Experimental.
- **Bots auto pull-up from ledges** (`gt_bot_ledge_pullup` + delay) — no vanilla self-rescue exists (player_character_state_ledge_hanging.lua:91-111); after the delay we call `StatusUtils.set_pulled_up_network(bot, true, helper)` (status_utils.lua:84), crediting the nearest living ally as helper.
- **Bots unstick from ladders** (`gt_bot_ladder_unstick` + delay) — detects a stuck ladder transition (`PlayerBotNavigation._current_transition.type == "ladder"`, player_bot_navigation.lua:276-339) and teleports the bot to the followed teammate via the vanilla teleport primitives (bt_bot_teleport_to_ally_action.lua:82-98).
- **Tighter bot follow distance** (`gt_bot_follow_distance_enabled` + meters) — vanilla snaps a bot back only at >=40 m (`FOLLOW_TELEPORT_DISTANCE_SQ=1600`, bt_bot_conditions.lua:1206). Faithful re-implementation of `BTConditions.should_teleport` with a configurable distance (default 40, set 10 to keep bots close); preserves the go-for-revive exception.
- **Bots instantly grab targeted items** (`gt_bot_instant_pickup`) — points `interaction_unit`/`forced_pickup_unit` at the bot's live pickup candidate so vanilla's `is_forced_pickup` path in `BTConditions.can_loot` (bt_bot_conditions.lua:877-890) bypasses the 3.2 m walk-up gate. Skipped while aiding. Experimental.

### Boss Mechanic Tweaks (new group)
- **Nurgloth fly-swarm disable (seconds)** (`gt_nurgloth_fly_stun_sec`) — slider, default = vanilla 8 s. Mutates `BreedActions.chaos_exalted_sorcerer_drachenfels.swarm_players.duration` (breed_chaos_exalted_sorcerer_drachenfels.lua:2018; the disable is the overpowering-blob "cloud of flies", bt_swarm_action.lua:71-77, breakable by killing the blob). Nurgloth-only — Halescourge's signature attack is the vortex, not flies. New module `_gt_boss_tweaks.lua`.

## v0.2.85-dev (2026-06-17) -- Settings logging + bot-rescue diagnostics

Diagnostics only, no gameplay change; all logging debug-gated. (Same change promoted to stable gt v0.2.71-alpha.)
- **Settings snapshot at load** (`[gt:settings@load] …`) + `/gt_dump_settings` — logs every `setting_id = value` so toggle states (incl. bot toggles) are visible in the console log.
- **Per-change setting log** (`[gt:setting-changed] <id> = <value>`) in `on_setting_changed`.
- **Bot-rescue scan diagnostics** (`_gt_bot_fixes.lua`): per-candidate `ready / health_alive / aid_path` + throttled summary (`awaiting=N picked=… not_health_alive=N path_blocked=N`) to pinpoint why a rescue doesn't fire. Verified CW uses `is_ready_for_assisted_respawn` (`deus_spawning.lua:203`, `respawn_handler.lua:502`) and awaiting allies are `HEALTH_ALIVE` (`side_manager.lua:363`), so the repro log reveals which gate fails.
- **Ironbreaker fix log** when it releases the ult-hold to revive.

## v0.2.84-dev (2026-06-16) -- Bot Options: three AI-teammate behavior fixes

### Why
Three long-standing bot AI gaps, requested as toggles. All default OFF, host-side only (bots only exist on the host), and none registers a network event or sends an RPC, so none can affect non-modded lobby members. New code in `_gt_bot_fixes.lua`, grouped under a new "Bot Options (AI Teammates)" settings group. Source citations are into the decompiled vanilla source (verified 2026-06-16).

### Fixes
- **Necromancer bots can hand off potions** (`gt_bot_necro_potion_handoff`). Her career skull (`bw_necromancer_career_utility_weapon`, `is_not_droppable`, `slot_type="potion"`) becomes the PRIMARY item in `slot_potion` at spawn (`simple_inventory_extension.lua:143-154`), so a picked-up potion lands in ADDITIONAL storage. Every handoff check reads only the primary (scoring `player_bot_base.lua:881-888`; give interaction `interactions.lua:1640-1705`), and the skull has no `can_give_other` -> bot never offers. A human swaps past the skull by tapping the potion key; the bot can't. Fix: a throttled `PlayerBotBase.update` hook promotes a stored giveable potion to primary (`swap_equipment_from_storage`, `simple_inventory_extension.lua:2434`) for Necromancer bots, so all vanilla logic works. Gated to real potions (`can_give_other`) so grimoires aren't promoted.
- **Ironbreaker bots revive during their ult** (`gt_bot_ironbreaker_revive_in_ult`). The IB bot ult holds a `wait_action` (block) for the buff's whole duration (`player_bots_settings.lua` dr_ironbreaker), and `BTConditions.can_activate_ability` short-circuits on `is_using_ability` (`bt_bot_conditions.lua:628`), parking the BT selector on the ability node so the higher-priority revive node (`bt_bot.lua:14-32`) never runs. Fix: hook `can_activate_ability` to return false for an Ironbreaker mid-ult when an ally needs aid, so the bot yields to revive. The ult is a timed buff and keeps running -- not wasted; ability is on cooldown so it won't re-pop.
- **Bots rescue allies awaiting respawn** (`gt_bot_rescue_awaiting`). `PlayerBotBase._select_ally_by_utility:903` excludes `is_ready_for_assisted_respawn` allies from aid entirely, with no branch to handle them. Fix: wrap the picker; when it finds nothing more urgent, scan for a reachable awaiting-respawn ally and return it relabeled `"knocked_down"`. The revive bot-action has no forced `input` (`player_bots_settings.lua` revive), so the interact fires the CONTEXTUAL interaction, which the engine resolves to `assisted_respawn` (`interactions.lua:562`). The wrapper calls the original first, so it composes with other bot mods. Experimental -- verify in-game.

### To verify
- **Necromancer:** play/spectate a Necromancer bot, let it pick up a potion; confirm it can hand it to a player who needs one (and isn't permanently holding the skull).
- **Ironbreaker:** down a teammate while an IB bot's ult is active; the bot should break off to revive instead of standing and blocking.
- **Rescue:** die and reach the awaiting-respawn state with bots free; a bot should path over and perform the assist-respawn.

## v0.2.83-dev (2026-06-14) -- Floating Damage Numbers (client-side; replaces the crash-prone third-party damage mod)

### Why
The third-party floating-damage-numbers mod crashed any lobby that contained a player who didn't have it — the classic signature of a mod that registers a VMF network event / sends RPCs to peers with no matching handler. Rather than decompile and patch it, the capability is rebuilt inside gt, networking-free, so it can't crash non-modded lobby members.

### How it works (all engine-native, no custom GUI)
- **Display:** reuses `DamageNumbersUI` (`scripts/ui/hud_ui/damage_numbers_ui.lua`), which already does world→screen projection + float/crit/fade animation. It's already in the **Adventure** HUD component list, but its `validation_function` only activates it in a mission when `script_data.debug_show_damage_numbers` is set — so we set that flag.
- **Feed:** reuses `DamageUtils.add_unit_floating_damage_numbers` (`damage_utils.lua:3942`) for color/crit/dot/size + the `add_damage_number` event.
- **Capture:** merged into the **existing** godmode `DamageUtils.add_damage_network` / `add_damage_network_player` hooks (the no-duplicate-hook rule forbids a second hook on the same `Class.method`), filtered to the local player as attacker.
- **Why it's crash-proof:** `add_damage_network_player` computes `damage_amount` locally (via `calculate_damage` + `apply_buffs_to_damage`, *before* the `is_server` branch) on host AND client, so accurate numbers need no host round-trip. Feature registers **no** network handlers and sends **no** RPCs.

### Added
- New module `_gt_damage_numbers.lua` (activation-flag sync + `mod._gt_dn_show` trigger; wraps `on_setting_changed` / `on_game_state_changed` via the chain pattern).
- Settings group **Floating Damage Numbers**: `gt_damage_numbers_enabled` (default off) with sub-toggle `gt_damage_numbers_include_dots` (default on — also shows DoT ticks & explosions via the `add_damage_network` path).

### Changed
- The two godmode `DamageUtils` hooks are now consolidated (godmode + damage-number feed) and capture the function's single return `damage_amount`. Behavior-identical for godmode.

### To verify (in-game)
- Enable the setting, **load a mission** (activation is evaluated at HUD build, so it takes effect on the next map), and confirm numbers float over enemies you hit (crit/headshot emphasized, DoT/explosion numbers grey when the sub-toggle is on).
- Join/host a lobby with a player who does **not** have gt and confirm no crash (this is the whole point — there is no network traffic from this feature).
- Toggle the sub-toggle off and confirm only direct weapon hits show numbers.

## v0.2.82-dev (2026-06-13) -- Fix keep-menu-hotkey mid-mission crash (Issue #62) + table-form hook nil-guards (Issue #70.1)

### Why
Multi-agent audit 2026-06-13.

**Issue #62 (crash) — "Keep Menus in Mission hotkeys causes crash".** The "Keep Menus in Missions" feature used three patches; patch (2) hooked `IngameUI.handle_menu_hotkeys` and unconditionally force-flipped the hotkeys-enabled arg to `true` whenever `mission_inventory_enabled` was on. That enabled EVERY keep hotkey mid-mission, not just inventory — Hero Select / Map / Achievements / Weave Forge / Store each transition to a view that spawns a dedicated `levels/ui_*/world` preview level which is NOT in a mission's package set, so pressing those keys fataled with "Level not loaded" + the `c_api_world.cpp:691` assert (confirmed against the attached crash log; same bug class as the closed cim Issue #50). The flip never reliably opened the inventory either (vanilla `can_interact`/transition gates still blocked it) — the working in-mission inventory path is the separate `/gt_inv` command + `gt_open_inv_hotkey` keybind (direct `handle_transition("hero_view_force")`), which does not depend on this hook.

**Issue #70.1 (hygiene).** Four table-form hooks were registered without an existence guard, inconsistent with the rest of the repo (cf. `career_tweaker_balance.lua:2472`). The targets are boot-loaded vanilla class globals so the unguarded form works in practice; the guard is latent load-order safety only.

### Changed
- **Removed** the `IngameUI.handle_menu_hotkeys` hotkey-flip hook (Issue #62). `mission_inventory_enabled` still drives the `InventorySettings` game-mode patch (1) and the ESC-menu "Open Inventory" entry (3) — only the crash-causing patch (2) is gone. The feature-overview comment block was updated accordingly.
- **Nil-guarded** four table-form hooks (Issue #70.1): `CareerExtension.update` (`:3272`), `GenericStatusExtension.add_fatigue_points` (`:3385`), `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed` (`:3456-3457`) now wrap in `if X and X.method then ... end`. Behavior-identical (targets always loaded).

### Tests
- New `/gt_regression_test` check `gt_no_mission_hotkey_flip` — source-pattern guard that FAILS if the `IngameUI.handle_menu_hotkeys` hook is reintroduced (needle split across two string literals to avoid self-match; degrades to no-op when source introspection is unavailable).

### To verify (in-game — behavior-changing)
- Mid-mission, press each keep-menu hotkey (Hero Select / Map / Achievements / Weave Forge / Store) and confirm **no crash** (they now no-op, as in vanilla).
- Confirm `/gt_inv` (and the `gt_open_inv_hotkey` keybind) still opens the inventory mid-mission, and the ESC-menu "Open Inventory" entry still works.

## v0.2.81-dev (2026-06-08) -- Failnotify hardening (Issue #72): leaving_game guard, unknown-result teardown, ungated F17 warning, test backfill

### Why
The 2026-06-08 post-ship re-review of v0.2.80 verified all four lobby fixes correct but flagged hardening gaps (filed as Issue #72). This closes them.

### Changed (`_gt_lobby_failed_join_reveal.lua`)
- **leaving_game guard:** the `create_popup` hook now defers to vanilla when `Managers.account:leaving_game()` — vanilla's own create_popup is a no-op in that window (state_loading.lua:2448-2450), so the mod no longer queues an enriched popup against a dying state object.
- **Unknown popup result:** `_consume_results` (factored out of the update callback, parameterized on popup_mgr for testability) grew an `else` branch — an unrecognized result logs via **ungated `mod:warning`** and still drives the restart_as_server teardown so the user is never stranded on the loading screen. Mirrors vanilla's logging of unknown results (state_loading.lua:1588). Unreachable today (only two button actions exist); defensive.
- **F17 warning ungated:** the popup-already-up soft-defer now logs via `mod:warning` (was debug-gated `_dbg_alert`); decision routed through exported `M._should_defer_for_existing_popup`.

### Tests (Issue #72 backfill)
- `gt_lobby_failnotify_unknown_result_drives_teardown` — injects a synthetic pending popup, drives the real consumer with a stub manager returning an unknown action, asserts the entry is consumed AND teardown fields are set.
- `gt_lobby_failnotify_popup_up_soft_defers` — pins the F17 guard's truth table; raises (instead of soft-deferring) fail the test.
- `gt_lobby_failnotify_unpack_preserves_leading_nils` — replica of the `3 + select("#", ...)` forward idiom under all-nil leading args + trailing format varargs (the state_loading.lua:1084 shape).
- Test exports: `mod._gt_failnotify_consume_results`, `mod._gt_failnotify_pending_popups`, `mod._gt_failnotify_should_defer`.

## v0.2.80-dev (2026-06-07) -- Lobby join-event clobber + failed-join popup race fixes

### Why
Audit 2026-06-07 found four correctness bugs in the `gt_lobby_*` modules:

- **F3 (HIGH) -- event-registration clobber.** `slot_reservations`, `session_ignore`, and `motd` each registered the SAME `(mod, "on_player_joined_party")` pair on `Managers.state.event`. Stingray's `EventManager` keys callbacks by `(object, event_name)` (`foundation/.../event_manager.lua:18-21`), so registering the same pair is last-writer-wins -- only ONE of the three handlers ever fired on a player join; the other two silently never ran. (Separately, every handler was mis-threaded: `EventManager.trigger` calls `object[name](object, ...)` at `event_manager.lua:42`, prepending `mod` as the first arg, so the handlers' `peer_id` param was actually `mod` -- meaning even the surviving handler was operating on the wrong value.)
- **F4 (HIGH) -- double consume-once popup race.** The enriched failed-join popup id was assigned to `state_loading_self._popup_id` AND polled by the mod's own update consumer, while vanilla `StateLoading._try_next_state` -> `_handle_popup` (`state_loading.lua:1308-1310`/`1565-1566`) ALSO polls/consumes the same id. `query_result` is consume-once, so one poller gets the result and the other sees `nil` -- if the mod won the read, vanilla never ran its `restart_as_server` teardown and the loading screen could hang.
- **F17 (LOW) -- hard assert in hook.** `assert(self._popup_id == nil, ...)` inside the `create_popup` hook could hard-crash if a popup was already up at intercept time.
- **unpack-safety.** The vanilla-fallback built `args = { header, action, right_button, ... }` (leading three often nil, trailing format varargs present) and `unpack(args)`'d it -- a bare `#args` boundary search over an array with nil holes truncates non-deterministically (VMF_RECIPES § 2a), silently dropping vanilla's `string.format` args.

### Changed
- `general_tweaker_dev.lua:6191-6249` -- NEW shared `on_player_joined_party` dispatcher. Defines `mod._gt_lobby_join_handlers`, `mod._gt_lobby_register_join_handler(name, fn)`, and the single registered method `mod.gt_lobby_on_player_joined_party` (swallows the EventManager-prepended `self`, then pcall-invokes every appended handler in order). Owns the ONE `(mod, "on_player_joined_party")` registration plus the per-state-transition re-register via `_gt_register_update`. (F3)
- `_gt_lobby_session_ignore.lua:111-120` -- dropped the module's own `em:register` + `on_game_state_changed` wrap; now `mod._gt_lobby_register_join_handler("session_ignore", _on_player_joined_party)`. Exposed `M.on_player_joined_party`. (F3)
- `_gt_lobby_slot_reservations.lua:202-217` -- dropped the module's own `_update_register` + boot register; now `mod._gt_lobby_register_join_handler("slot_reservations", ...)`. (F3)
- `_gt_lobby_motd.lua:213-226` -- dropped the module's own `_update_register` + boot register; now `mod._gt_lobby_register_join_handler("motd", ...)`. Exposed `M.on_player_joined_party`. (F3)
- `_gt_lobby_failed_join_reveal.lua:240-266` -- `_queue_enriched_popup` no longer assigns `state_loading_self._popup_id`; the enriched popup lives ONLY in `_pending_popups` (now also stashing the StateLoading instance as `entry.sl`). (F4)
- `_gt_lobby_failed_join_reveal.lua:277-315` -- new `_drive_restart_as_server_teardown(sl)` mirrors vanilla `_handle_popup`'s `restart_as_server` branch (`state_loading.lua:1570-1577`); the mod poller is now the SOLE owner of both popup actions and drives the teardown itself. Exposed as `mod._gt_failnotify_drive_teardown` (line 408) for the regression test. (F4)
- `_gt_lobby_failed_join_reveal.lua:365-368` -- replaced `assert(self._popup_id == nil, ...)` with a soft guard: `_dbg_alert` + fall through to vanilla. Added a local `_dbg_alert` (line 43) deferring to `mod._gt_dbg_alert`. (F17)
- `_gt_lobby_failed_join_reveal.lua:323-334` -- captured true arity via `local n = 3 + select("#", ...)` and pass `unpack(args, 1, n)` in the vanilla fallback. (unpack-safety)

### Tests
- `general_tweaker_dev.lua` `/gt_regression_test` adds:
  - `gt_lobby_join_dispatch_consolidated` -- all three join-handlers (`session_ignore`, `slot_reservations`, `motd`) are reachable from the single `mod._gt_lobby_join_handlers` list and the single registered method exists. FAILS if any module reverts to self-registration.
  - `gt_lobby_join_dispatch_pcall_isolated` -- drives the dispatcher with two synthetic handlers (first raises, second records); asserts the second still runs (pcall isolation) and receives the true `peer_id` (object-prepend stripped).
  - `gt_lobby_failnotify_teardown_driver` -- runs the F4 teardown driver against a synthetic StateLoading and asserts it sets `_teardown_network=true`, `_permission_to_go_to_next_state=true`, and `force_done()`s the first-time view; tolerates a nil sl.

### To verify
- Host a modded lobby with `slot_reservations`, `session_ignore`, AND `motd` all enabled; have a non-reserved/ignored peer join -- all three behaviors should now fire (kick-if-reserved / kick-if-ignored / MOTD send) rather than only one.
- Attempt to join a modded host with a missing/mismatched mod set: the enriched failed-join popup appears; clicking "Open Workshop" opens the URL AND leaves the loading screen cleanly; clicking "Close" (restart_as_server) returns to title without a hang.
- `/gt_regression_test` -- all three new checks PASS.

## v0.2.79-dev (2026-06-06) -- Memory Watchdog rides Debug Logging (drop redundant toggle)

The Lua Memory Watchdog (v0.2.77) had its own `memwatch_enabled` checkbox, separate from the universal `enable_debug_logging` toggle. That was the wrong call — the heap curve is a debug diagnostic like every other, and a separate switch to remember just meant a leak session got missed (the watchdog defaulted off, so the 2026-06-06 OOM logs had zero `[memwatch]` lines despite the mod being installed).

**Fix:** the watchdog now gates on `enable_debug_logging` — it runs automatically whenever Debug Logging is on (which is already on during any data-gathering session). Removed the `memwatch_enabled` checkbox + its loc keys; kept `memwatch_interval`. The `[memwatch]` log prefix stays greppable, so it's trivially separated from the rest of the debug stream when reading the log. `/gt_mem` on-demand snapshot unchanged.

## v0.2.78-dev (2026-06-06) -- GC mitigation to survive long sessions despite the leak

### Why
A Chaos Wastes expedition runs ~1 hour, but the Lua heap OOM'd at 26 minutes (v0.2.77 investigation). "Restart between missions" loses the run — not viable. This adds runtime GC mitigation so a full run can complete while the leaking mod is still being isolated + fixed.

### What this adds (two settings, under the watchdog toggles)
- **`gc_mitigation_enabled`** (checkbox, default off): tightens Lua's incremental GC — `setpause` 200→110 and `setstepmul` 200→400. Lua's default waits until the heap doubles before collecting; under heavy churn the collector falls behind and the heap climbs even though much of it is COLLECTABLE. Tightening keeps the heap near the true live set. On disable, restores the 200/200 defaults.
- **`gc_full_collect_sec`** (numeric 0-120, default 0=off): when aggressive GC is on, force a complete `collectgarbage("collect")` this often. Reclaims everything the incremental collector hasn't between cycles. Each collect is a brief frame hitch (bigger heap = longer) — but a short stutter beats a hard crash. Logs `[gc_mit] full collect: X KB -> Y KB (freed Z KB)` so you can see how much it reclaims (large freed = collectable garbage that was piling up = mitigation working; near-zero freed = true reference leak, only fixable in the offending mod).

### Honest caveat
If the growth is a TRUE reference leak (objects stay reachable), neither lever reclaims them — only fixing the offending mod does. These buy time when the growth is collectable garbage / GC-falling-behind, which the thrashing-GC signature in the crash log suggests is at least part of it. Pair with the Memory Watchdog (v0.2.77) to confirm the heap actually stays lower — and the `freed` number on each full collect tells you directly whether it's helping.

### Recommended for a long run tonight
1. Turn ON "Aggressive GC", set "Force Full GC Every" to 45-60s.
2. Turn ON "Lua Memory Watchdog" (interval 10s) to capture the curve.
3. Turn OFF Debug Logging on all -dev mods (cim_dev, cosmetics_tweaker, wt, ct_dev, gt_dev) — removes a large allocation source.

## v0.2.77-dev (2026-06-06) -- Lua Memory Watchdog (leak-hunt instrumentation)

### Why
User hit a hard Lua heap OOM crash on 2026-06-06 (`cemetery_belakor_path1`, GUID 2b762ad3): `Not enough memory reserved for heap lua_heap` — the 1 GB Lua scripting heap filled in 26 minutes with the GC thrashing (repeated 286-692ms full collections that couldn't reclaim enough = ~1 GB of LIVE Lua objects = a true reference leak). Static audit of the weapon-spawn-path mods (ct / wt / cosmetics_tweaker / Loremaster's Armoury) found them all independently leak-clean: cosmetics uses weak-keyed (`__mode="k"`) per-unit tables, wt's safe/traced_hook only allocates transient garbage, LA flushes its queue every frame, ct isn't in the per-frame path. The leak is in a not-yet-audited mod and can't be pinned by reading logs alone — it needs runtime memory instrumentation.

### What this adds
A **Lua Memory Watchdog**: logs the live Lua heap size every N seconds so a leak session shows the growth curve directly.

- **Settings** (under the debug toggles, top-level): `memwatch_enabled` (checkbox, default off) + `memwatch_interval` (numeric 2-60s, default 10). Independent of `enable_debug_logging` on purpose — a leak hunt wants the memory curve WITHOUT the rest of gt's per-event debug spam (which is itself allocation churn that muddies the signal).
- **Per-frame consumer** registered via the existing `_register_update` registry (pcall-isolated like every other gt update consumer). Accumulates `dt`; every interval logs:
  ```
  [memwatch] lua_kb=487213 (475.8 MB, 46.5% of 1GB cap) delta=+8420 peak_kb=487213 level=cemetery_belakor_path1 units=1842 t=600s
  ```
  `collectgarbage("count")` is the KB ground-truth for the same `lua_heap` the engine caps at 1 GB. `delta` per window is the leak rate; the window where `delta` spikes pins the trigger (which level, after which action). `pct` shows proximity to the OOM ceiling. Reading the counter does NOT force a collection — it's cheap.
- **`/gt_mem` command** — on-demand snapshot to chat regardless of the toggle, for quick before/after marks around a suspected leaky action.

### How to use it (next session)
1. Enable "Lua Memory Watchdog" in gt settings (leave Debug Logging OFF for a clean signal).
2. Play until the leak manifests (or just play a full session).
3. Read the `[memwatch]` lines in the console log. Monotonic `lua_kb` climb with a positive `delta` every window = leak confirmed; the level/timeframe where `delta` jumps is the trigger.
4. Bisect the modlist across runs (disable half, repeat) to isolate the single offending mod, then audit + fix THAT mod so it's independently leak-clean.

### Cost
Enabled: one `collectgarbage("count")` (counter read, no collection) + one log line per interval — negligible. Disabled: a single dt-accumulate + early return — free.

## v0.2.76-dev (2026-06-02) -- Add "Disable Bots (Solo)" toggle; fix that bots weren't removed mid-mission

### Why
User report: the existing "no bots" path didn't remove bots mid-mission, and there was no way to start a mission bot-free (wanted for true solo runs / speedruns). The only bot-off control was the `/gt_bottoggle` chat command, which flips `level_settings.no_bots_allowed` — a load-time gate with **no despawn path**, so existing bots stayed in the party and it isn't re-read per server tick. Confirmed against `GameModeAdventure._handle_bots` (game_mode_adventure.lua:371): the per-tick gate the engine actually honors is `script_data.ai_bots_disabled`, not `no_bots_allowed`.

### Mechanic
`script_data.ai_bots_disabled` is checked inside `_handle_bots` on every `server_update` across all three mission modes:
- `GameModeAdventure._handle_bots` (game_mode_adventure.lua:371)
- `GameModeDeus._handle_bots` (game_mode_deus.lua:527)
- `GameModeWeave._handle_bots` (game_mode_weave.lua:462)

When the flag is true and bots exist, vanilla runs `self:_clear_bots(true)` then returns early — so:
- Flipping it **ON mid-mission** despawns the current bots on the next tick AND blocks the delta-fill that would re-add them.
- Leaving it **ON** keeps the party bot-free from the first frame of every subsequent mission.
- Flipping it **OFF** lets the normal top-up logic refill on the next tick.

### Changed
- **`general_tweaker_dev_data.lua`**: new `gt_no_bots` checkbox appended to `gameplay_group` (after `gt_bots_in_keep`).
- **`general_tweaker_dev_localization.lua`**: `gt_no_bots` ("Disable Bots (Solo)") + tooltip.
- **`general_tweaker_dev.lua`**:
  - New "Disable Bots (Solo)" section with `_gt_apply_no_bots(enabled)` → sets `script_data.ai_bots_disabled = enabled and true or nil`. Forward-declared near the top (both `on_setting_changed` and `on_game_state_changed` reference it before its definition).
  - `on_setting_changed("gt_no_bots")` → apply immediately (instant mid-mission despawn / re-enable).
  - `on_game_state_changed` StateIngame-enter → re-apply so "no bots from mission start" survives level transitions and the game's own `ai_bots_disabled` resets.
  - Applied once at load so a persisted ON survives a mod reload.
  - Chat alias `/gt_no_bots`.

### Compatibility
- Host-only effective: bots are server-managed and `script_data` is local, so the flag only does anything on the host. Tooltip says so. Set locally on clients too (harmless).
- Independent of `gt_bots_in_keep` (keep-fill) — that feature calls `_add_bot_to_party` directly in inn modes, which don't run `_handle_bots`, so the two don't fight. Running both ON means bots in the keep for preview, none in missions.
- The old `/gt_bottoggle` (level `no_bots_allowed` flip) is left in place for its keep-spawn use; the new toggle is the correct mission-facing control.

### Regression tests (`/gt_regression_test`)
- `no_bots_setting_registered` — `gt_no_bots` widget exists in the data tree.
- `no_bots_apply_sets_ai_bots_disabled` — `_gt_apply_no_bots(true)` sets `script_data.ai_bots_disabled = true`, `(false)` clears it. Pins the correct engine flag so a future refactor can't silently regress to the no-despawn `no_bots_allowed` path. Saves/restores the live flag value around the probe.

## v0.2.75-dev (2026-05-30) -- Self-refreshing vanilla-name localization dump (feeds tools/gen-name-map)

### Why
`tools/gen-name-map/gen-name-map.ps1` resolves every mod-created display name from repo data but leaves ~3,010 VANILLA names `unresolved`: their English strings live in undumped `.package` bundles, not in the decompiled source. The only place those strings exist resolved is the running game (`Localize(loc_key)`). The maintainer wanted the vanilla half captured the same way the boon dump already is -- but **automatically, with no command to remember**.

### What
New sibling module `_gt_name_dump.lua`:
- On **keep/inn entry** (`StateIngame` enter), **once per game build** (gated on `Application.build_identifier()` stored in VMF settings; re-fires only after a game patch -- exactly when vanilla names could change), **silently** walks the in-memory `ItemMasterList` (`display_name` + `description`), `SPProfiles` (careers/heroes), and `Breeds`, calls `Localize()` on each loc key, and emits `[gt:name_dump] <loc_key>\t<English>` lines (same tab-separated shape as `dumps/boon_loc_dump.txt`) to the console log.
- **Output is the console log, not a file.** PHASE-0 FINDING (confirmed against the existing `/dump_level` code): VMF mods cannot write arbitrary files -- `io.open(...,"w")`, `mod:get_temp_data_directory`, and `Application.save_user_settings_to_file` are all unavailable from sandboxed mod code. The console-log + repo-side-grep route is the established gt dump doctrine.
- New VMF setting `gt_auto_name_dump` (checkbox, **default ON**) gates the auto-fire; new `/gt_dump_names` command forces a re-dump on demand (bypasses the build gate).
- Logging per PROJECT_STANDARDS § 3.6: payload via `mod:info` (operational telemetry, always logged); the "dump complete" confirmation is `_dbg` (log only); a dump FAILURE is `_dbg_alert` (chat+log, gated on debug logging). Applied marker untouched.

The generator side (`tools/gen-name-map/gen-name-map.ps1`) now auto-discovers and ingests the freshest dump with no flags (repo `dumps/name_loc_dump.txt` -> Fatshark user-dir file -> newest `console_logs/*.log` with `[gt:name_dump]` lines), fills any still-`unresolved` vanilla entry whose loc_key the dump knows (`display_name_source = "game_dump"`), and records the dump path/build/counts in the generated headers. No dump -> vanilla stays unresolved (never fabricated). Loop documented in `docs/generated/README.md`.

### Verify
Fixture (`dumps/name_loc_dump.SAMPLE.txt`, real vanilla loc_keys) flips 5 entries unresolved->resolved with `display_name_source = game_dump`; no-dump baseline returns to all-vanilla-unresolved. Requires a ship signal before Workshop upload.

## v0.2.73-dev (2026-05-27) -- Fix Issue #60: Host AI Takeover crashes `LocomotionSystem.update_animation_lods` next frame

### Why
User crash 2026-05-27 15:31:22 (session `7409d362-369e-43aa-a8e7-35b789b3b79d`). Crashify-tagged with "AI takeover crash". Engine reported `locomotion_system.lua:242: attempt to index local 'player' (a nil value)` in `update_animation_lods`. Stack contains no gt frames — vanilla `LocomotionSystem.update` called directly from `entity_system_bag.lua:62`. Lua locals at frame [1] show `player = nil`.

### Mechanic
Vanilla `LocomotionSystem.update_animation_lods` (in our decompile around line 227, in the shipped binary at the line the engine reports):

```lua
local player = self._override_player or Managers.player:local_player()
local viewport_name = player.viewport_name  -- crash here
```

Gt's host AI Takeover path (`_ai_swap_human_to_bot`) destroys the host's local Player object as part of the swap (line 2401: `pm:remove_player(peer_id, local_player_id)`). After that:
- `Managers.player:local_player()` returns nil (no local human exists).
- `self._override_player` is nil (gt never set it).
- `nil or nil` = nil → next frame crashes on `player.viewport_name`.

The crash fires ~0.6 s after the swap (`15:31:22.239 [ai_toggle:host] human->bot: ok` → `15:31:22.858` Lua Error). Confirmed reproducible — any host using `/ai` or the AI Takeover checkbox while in a mission will hit this.

Vanilla has a parallel case in benchmark mode where the human is replaced by a bot. The fix lives at `scripts/utils/benchmark/benchmark_handler.lua:423`:
```lua
locomotion_system:set_override_player(bot_player)
```

We mirror it.

### Changed
- **`general_tweaker_dev.lua`** `_ai_swap_human_to_bot`:
  - Captured the bot Player from `game_mode:_add_bot_to_party(...)` return value.
  - For host self-toggle (`not player.remote`), looks up `Managers.state.entity:system("locomotion_system")` and calls `set_override_player(bot_player)`. Bot reuses the host's slot, so `bot_player.viewport_name` is `"player_1"` (same as the host had). Vanilla's `update_animation_lods` now finds a valid viewport.
- **`general_tweaker_dev.lua`** `_ai_swap_bot_to_human`:
  - Before re-adding the human Player (or, in the remote-toggle case, returning to caller), clears the override: `locomotion_system:set_override_player(nil)`. Otherwise the override would dangle on the now-removed bot Player object and `update_animation_lods` would read `viewport_name` from a destroyed instance.
- **New marker** `CT_GT_AI_LOCOMOTION_OVERRIDE_MARKER_v0_2_73 = "gt-ai-locomotion-override-on-host-swap"` near the top of the file alongside the other AI Takeover markers.

### Regression tests (`/gt_regression_test`)
Two new checks:
- `ai_locomotion_override_marker_present` — marker constant unchanged. Belt-and-suspenders for refactors that drop the source-pattern check.
- `ai_locomotion_override_set_and_cleared` — reads the on-disk file via `debug.getinfo` source introspection and asserts the swap path contains `locomotion_system:set_override_player(bot_player)` AND the swap-back path contains `locomotion_system:set_override_player(nil)`. Catches partial reverts that keep the marker but drop one of the two calls. Degrades gracefully (no failure) when the install path doesn't expose the source for introspection.

### Stable status
The same bug exists in public `general_tweaker/` v0.2.69-alpha — host AI Takeover was added there in v0.2.52 and has the same `pm:remove_player` call with no `set_override_player` follow-up. Any host on stable using `/ai` mid-mission will crash. Per the dev-stream rule, we hold the merge until the user signs off, but flag it as a crash-class candidate for fast-tracking alongside the Issue #59 prefix-match fix.

## v0.2.72-dev (2026-05-26) -- Fix Issue #59: Drachenfels boss BT crash on CW dlc_castle_*_path1 (bt_conditions.lua:309)

### Why
Host crash 2026-05-26 in a CW Drachenfels run on level `dlc_castle_slaanesh_path1` (host running stable gt v0.2.69-alpha, same `_gt_cs_is_in_level` code as dev). `<<Script Error>> bt_conditions.lua:309: attempt to compare nil with number`. The crashed BT condition was `at_one_fifth_health`, called from the chaos_exalted_sorcerer_drachenfels `final offense phase` selector. Stack frame [6] = `general_tweaker.lua:4127` (the `AISystem.update_brains` hook) — gt was on the stack because every BT update routes through that pass-through gate, but the bug was downstream of it.

### Mechanic
1. gt hooks `BTConditions.transitioned_one_third_health` and biases the return to `true` when **outside** `dlc_castle` (the comment says "so the boss skips its arena-specific defensive phase outside its arena"). The hook body is `(_gt_cs_is_in_level("dlc_castle") and func(...)) or true`.
2. `_gt_cs_is_in_level(level_name)` previously did **exact-match**: `return level_key == level_name`. In CW, the Drachenfels arena loads under the level key `dlc_castle_slaanesh_path1` (or `_khorne_path1` / `_chaos_boss_path1` / etc. depending on the CW path). Exact-match against `"dlc_castle"` returned **false**.
3. With the gate false, the hook returned `true` without calling vanilla. The BT believed the boss had transitioned to one-third-health and entered the `final offense phase` branch.
4. Phase-init for that branch normally runs as part of vanilla `transitioned_one_third_health` — which we skipped. So `blackboard.current_health_percent` was never populated.
5. The first child condition in the offense-phase branch is `at_one_fifth_health` at bt_conditions.lua:309: `return blackboard.current_health_percent <= 0.2`. nil <= 0.2 → fatal compare. Host drops, everyone disconnects.

The bug existed on every CW variant of dlc_castle for as long as the exact-match gate has been in place. Bookmark Issue #59.

### Changed
- **`general_tweaker_dev.lua`**: `_gt_cs_is_in_level` now matches `level_key == level_name` OR `string.sub(level_key, 1, #level_name + 1) == (level_name .. "_")`. The underscore-boundary check prevents false positives against hypothetical levels with a shared word stem (e.g. a `dlc_castled_*` map). Three other gt_cs hooks call this helper (run_on_spawn arena init, level_analysis skip, the BT condition itself) — all benefit identically from the prefix match.

### Regression test (`/gt_regression_test`)
- `gt_cs_is_in_level_prefix_match` — table-driven assertion over seven cases: exact match, vanilla path variant, **Issue #59 CW theme variant**, CW boss variant, unrelated level, shared-prefix-without-underscore, keep level. Stubs `Managers.state.game_mode:level_key()` to drive each case, restores state on exit. Catches a refactor that reverts the prefix-match OR changes the underscore-boundary semantics.

### Stable status
The same bug exists in the public `general_tweaker/` v0.2.69-alpha (`_gt_cs_is_in_level` at line 3767 — identical exact-match code). Any host on stable will keep crashing on CW dlc_castle_*_path1 runs until we merge this fix down. Per the dev-stream rule we hold here until the user signs off on a stable release.

## v0.2.71-dev (2026-05-26) -- Add "Allow Bots in Keep" toggle (gameplay_group)

### Why
User direction 2026-05-26: vanilla VT2 doesn't spawn bots in the keep / Chaos Wastes hub / Versus inn, so the party visually reads as one-player even when the host has reserved an empty 4-slot lobby. Friends use the lobby state to preview party composition before launching a mission — empty slots make this confusing. Reproducing the adventure-mode bot-fill against the inn party gives the host a populated lobby for testing and visual continuity. Dev-stream first; merges to stable after a stability cycle.

### Mechanic
- **Why vanilla skips it.** `GameModeInn` / `GameModeInnDeus` / `GameModeInnVs` are distinct game-mode classes (not `GameModeAdventure`); their `server_update` deliberately omits the `_handle_bots()` call adventure mode runs. But `_add_bot_to_party` and `_remove_bot_instant` are defined on `GameModeBase` and inherited — they're callable on every inn mode, just never invoked.
- **What we do.** Register a 1Hz `mod.update` consumer (`_register_update("bots_in_keep", ...)`) that, while the toggle is on AND host AND `DamageUtils.is_in_inn`, tops party 1 up to its `num_slots`. Profile picking mirrors `GameModeAdventure._get_first_available_bot_profile` exactly: walk `PROFILES_BY_AFFILIATION.heroes`, filter by `profile_synchronizer:is_profile_in_use`, sort by `PlayerData.bot_spawn_priority` (or `ProfileIndexToPriorityIndex` as the vanilla fallback), then read `bot_career_index` off `hero_attributes`. No engine-internal field reads — every input is a global.
- **Bookkeeping.** `_bik_spawned` (Player table → true) tracks the bots we added so toggle-off / leave-keep can clear only ours without disturbing anything vanilla logic might have left behind. State-shutdown destroys bot units; `on_game_state_changed` calls `_bik_reset_bookkeeping()` (table-only reset, no engine calls on torn-down references).

### Changed
- **`general_tweaker_dev_data.lua`**: new `gt_bots_in_keep` checkbox appended to `gameplay_group` (alongside `ai_takeover_enabled`).
- **`general_tweaker_dev_localization.lua`**: `gt_bots_in_keep` ("Allow Bots in Keep") + `gt_bots_in_keep_tooltip` entries.
- **`general_tweaker_dev.lua`**:
  - New "Bots in Keep" section after the AI Toggle block. Provides `_bik_in_inn` / `_bik_is_host` / `_bik_game_mode` / `_bik_active` gates, `_bik_pick_next_bot` (priority-aware profile selector), `_bik_fill` (top up party 1), `_bik_clear` (remove our bots), `_bik_reset_bookkeeping` (drop tracking table). Exposed as `mod._bik_*` so the early `on_setting_changed` / `on_game_state_changed` closures can drive them (table-field reads resolve at call time, no forward-decl needed).
  - `on_setting_changed("gt_bots_in_keep")` → immediate fill on ON / clear on OFF (responsive UX; the 1Hz tick is the steady-state backstop).
  - `on_game_state_changed` → `_bik_reset_bookkeeping` on every state transition (prevents dangling Player references from the previous session).
  - Chat alias `/gt_bots_in_keep`.

### Compatibility
- Host-only behavior; clients see whatever bots the host spawned via the standard `_add_bot_to_party` path. No new RPC.
- Doesn't interact with `ai_takeover_enabled` directly — they target different game-mode contexts (`gt_bots_in_keep` requires `is_in_inn`; `ai_takeover_enabled` is refused in inn modes).
- DLC gate: `_add_bot_to_party` itself doesn't enforce DLC ownership, but `is_profile_in_use` covers any human-reserved profile and the bot profile list comes from `PROFILES_BY_AFFILIATION.heroes` which already respects which careers vanilla considers playable. No additional gate needed.

### Regression tests (`/gt_regression_test`)
Four new checks pin the feature's invariants — surfaced by post-deploy log scour 2026-05-26:
- `bots_in_keep_helpers_exposed` — `mod._bik_fill` / `_clear` / `_active` / `_reset_bookkeeping` are all functions. Catches a refactor that drops the `mod._bik_*` exposure (would silently no-op `on_setting_changed` and `on_game_state_changed`).
- `bots_in_keep_active_default_false` — `_bik_active()` returns false with the toggle off (default install state). Catches inverted gates and raises from missing dependencies.
- `bots_in_keep_reset_bookkeeping_safe` — `_bik_reset_bookkeeping` is idempotent and never raises (it fires on every state transition).
- `bots_in_keep_setting_registered` — walks the data widget tree and asserts `gt_bots_in_keep` exists. Catches a refactor that drops the checkbox from `gameplay_group` without updating the feature module.

## v0.2.70-dev — 2026-05-26

- **FORK POINT**: friends-only dev stream for in-flight gt work. Parent `general_tweaker/` (Workshop ID 3713619122) remains the public stable stream.
- Mod_id renamed `gt` → `gt_dev`. Scripts dir renamed `general_tweaker` → `general_tweaker_dev`. itemV2.cfg: visibility friends_only, published_id cleared.
- **RPC schema caveat**: `GT_LOBBY_RPC_SCHEMA` is per-mod-id; gt_dev clients can't sync lobby state with gt-stable clients (different mod_id, different network channel). Dev cohort should pin to one stream.

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
