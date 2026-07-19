# Tweaker: Events — Changelog

## 0.4.36-dev (2026-07-18) - issue #626 fix: narrowed mission visibility gate [untested]

- Fixed the "toggle on, nothing shows" defect: the mission visibility contract fail-closed on four `NetworkLookup` tables (`level_keys`, `mission_ids`, `act_keys`, `unlockable_level_keys`) that the Own Game menus never read, so any lookup mismatch silently blocked all four menu hooks with only a `[event-missions:626] blocked:` printf. `validate_contract` now requires ONLY the tables the menus actually read: `AreaSettings.celebrate` with `act_celebrate` in its acts (`start_game_window_area_selection.lua:91-95`), `ActSettings.act_celebrate` with numeric `sorting` (`start_game_window_mission_selection.lua:156-160`), and each allowlisted `LevelSettings` entry with matching `level_id`/`act` and a non-empty package list.
- Added an idempotent load-time campaign registration fallback: if vanilla's boot pass (`level_unlock_settings.lua:100-135`) genuinely missed an allowlisted level, `ensure_campaign_registration` appends it to the local `UnlockableLevels` / `GameActs.act_celebrate` / `MapPresentationActs` tables in the vanilla shape. It runs unconditionally at mod load (never toggle-gated) so every Event Tweaker peer applies the identical append, is a no-op on a healthy install, and never registers a malformed level.
- Wire safety unchanged: no `NetworkLookup` table is consulted, appended to, or reordered. The vanilla wire tables already carry both levels from boot (`network_lookup.lua:1239-1259`, built from `LevelSettings` before any mod loads), and modded `NetworkLookup` keys on vanilla RPCs CTD non-mod peers (issue 278, issue 371).
- `/event_mission_probe` now also reports `campaign=vanilla` (boot registration was complete) or `campaign=<appended entries>`; `contract=` reflects the narrowed gate. The `issue626_event_mission_allowlist_contract` regression check additionally verifies both levels sit in `UnlockableLevels` and `GameActs.act_celebrate` post-fallback.
- Offline suite updated: contract tests drop the NetworkLookup fixture, add fail-closed coverage for each menu-read table, and add three fallback tests (vanilla no-op, idempotent append, malformed-level refusal). 1032/1032 pass under Lua 5.1.
- `MOD_VERSION` `0.4.35-dev` -> `0.4.36-dev`.

Verify with two players: host enables both Dormant Event Missions, opens Own Game, selects the event area, and starts each mission once with a client connected. Expected: both The Feast of Grimnir and A Quiet Drink appear and load for both peers; a normal Helmgart act is unchanged. Run `/event_mission_probe`: chat shows `contract=OK` with the selected IDs plus `campaign=vanilla` (or the appended entries if boot registration was incomplete). Console log shows `[event-missions:626] menu applied: area=celebrate act=act_celebrate missions=[dlc_dwarf_fest,dlc_celebrate_crawl] unrelated_acts=untouched`. Do not mark fixed until this passes in-game.

## 0.4.35-dev (2026-07-16) - issue #430 hot-join crash containment [verify-fix-coop]

- Closed the residual Cursed Adventure hot-join crash. The v0.4.29 peer-parity floor saw only `PlayerManager:human_players()`, but vanilla starts game-object replication at `GameSession.add_peer` (`peer_states.lua:393`) and adds the remote player to `PlayerManager` only after sync (`peer_states.lua:450`). A package-bearing curse could therefore already have replicated a custom unit before the roster beacon noticed the joining peer.
- Added a pre-replication session contract: selecting or activating a managed package-bearing curse locks `GameModeBase.is_joinable`. Vanilla checks this at `PeerStates.Connecting` (`peer_states.lua:114-120`) before it sends `rpc_notify_connected`, so a new peer cannot advance to `GameSession.add_peer` while unsafe curse units exist. The lock preserves vanilla's `false` result and reopens only after no curse is selected or active. Existing peers still require positive Event Tweaker parity.
- Added a second fail-closed preflight over `NetworkServer.peer_state_machines`: a peer known to the server but not yet represented in `PlayerManager` blocks curse injection. Missing server/roster evidence also blocks injection. This closes the connection-arrived-before-lock race.
- Did not attempt synchronous curse teardown. Source inspection found managed curse templates without a general `server_stop_function`, so deactivation cannot prove every package-owned game object has been destroyed before replication. The safe fallback is to block new joins for the bounded cursed session, not to warn and continue.
- Added pure `event_tweaker_curse_join_policy.lua`, four offline regression cases, runtime check `issue430_hotjoin_session_contract`, updated UI text, and engine-facing documentation. `MOD_VERSION` `0.4.34-dev` -> `0.4.35-dev`.

Verify with two players. Assemble the lobby first with Event Tweaker active on both peers, select Blood Storm, and start an Adventure mission. A third tester without Event Tweaker attempts to hot-join. Expected: the third tester is not admitted to the active cursed session and does not crash; the two existing players continue normally. After returning to the keep and unchecking all Cursed Adventure curses, the third tester can join. Also start with a non-Event-Tweaker peer already present: the curse must be skipped and the host log must show `[et:430] dropped`. Run `/event_tweaker_regression_test`; all four issue-430 checks must pass. Do not mark fixed until both paths pass in-game.

## 0.4.34-dev (2026-07-16) - issue 626 build + status-tag correction [untested]

- First build of the issue 626 dormant-event-mission feature (the 0.4.33-dev source pass authored the code but did not build the bundle). No logic change: the closed two-entry allowlist (`dlc_dwarf_fest` / `dlc_celebrate_crawl`), the temporary `AreaSettings.celebrate` exposure, the view-local `act_celebrate` mission-list replacement, the fail-closed contract validator, `/event_mission_probe`, `[event-missions:626]` logging, and the `issue626_event_mission_allowlist_contract` regression check are unchanged from 0.4.33-dev.
- Corrected the two mission option titles from `[Issue 626]` to `[untested]` (The Feast of Grimnir, A Quiet Drink) so the dev status tag follows LOCALIZATION_STANDARD § 13.1 and matches every sibling entry in this mod (the issue-532 preview toggle and the Cursed Adventure entries). A built-but-not-yet-in-game-verified feature is `[untested]`; it escalates to `[working]` only after the user confirms both missions load in a lobby. The prior `[Issue 626]` tag was placeholder text from before the build.
- Decompile citations for the engine contract (current VT2 source): `LevelSettings.dlc_dwarf_fest` (`levels/honduras_dlcs/dwarf_fest/level_settings_dwarf_fest.lua:3`, `act = "act_celebrate"`, non-empty `packages`, no `required_dlc`) and `LevelSettings.dlc_celebrate_crawl` (`levels/honduras_dlcs/celebrate/level_settings_celebrate.lua:3`, same shape); `level_id` is set to the key at boot for every entry with a `display_name` (`scripts/settings/level_settings.lua:1883-1885`); `AreaSettings.celebrate` + `ActSettings.act_celebrate` (`levels/honduras_dlcs/celebrate/level_unlock_settings_celebrate.lua:3-25`, `exclude_from_area_selection = true`, `acts = { "act_celebrate" }`); the `celebrate` DLC is `AlwaysUnlocked` free content (`scripts/settings/dlcs/celebrate/celebrate_common_settings.lua:5-9`), which is why no DLC ownership gate is required for these two missions.
- `MOD_VERSION` `0.4.33-dev` -> `0.4.34-dev`.

Verify with two players: host enables both Dormant Event Missions, opens Own Game, selects the built-in event area, and starts each mission once with a client connected. Expected: both The Feast of Grimnir and A Quiet Drink load for both peers; a normal Helmgart control mission (act 1-4) remains present and unchanged. Run `/event_mission_probe`; the host chat should show `contract=OK` with the two selected IDs, and the console log should carry `[event-missions:626] menu applied: area=celebrate act=act_celebrate missions=[dlc_dwarf_fest,dlc_celebrate_crawl] ...`. Do not mark fixed until this passes in-game.

## 0.4.33-dev (2026-07-15) - issue #626 allowlisted dormant event missions [not deployed]

- Added opt-in Own Game entries for the two source-audited dormant event levels: The Feast of Grimnir (`dlc_dwarf_fest`) and A Quiet Drink (`dlc_celebrate_crawl`). The runtime adapter temporarily exposes the stock `celebrate` area only while vanilla builds the area widgets, and replaces only the view-local `act_celebrate` mission list. It does not mutate `GameActs`, `UnlockableLevels`, `UnlockableLevelsByGameMode`, `MapPresentationActs`, or `NetworkLookup`, and a future mission sharing the act remains excluded until explicitly audited and allowlisted.
- Fail-closed contract checks require both stock `LevelSettings` entries, non-empty level package lists, the stock area/act, and the existing level/mission/act/unlockable network lookups before either mission is advertised. `/event_mission_probe` and `[event-missions:626]` engine log lines report the selected allowlist and any missing boundary. Vanilla `LevelTransitionHandler._load_level_packages` remains the sole level-package owner.
- Added desktop and controller mission-menu hooks with automatic VMF disable/re-enable behavior, temporary-area restoration on Lua errors, an in-game regression check, and five offline Lua 5.1 tests covering both enabled missions, an untouched control act, individual selection, complete contract acceptance, and fail-closed missing-lookup behavior.
- Clean-room provenance: behavioral inspection used The Feast of Grimnir Workshop item `3557074106` / public source commit `b30f9a3a7db98c10719ef612b86c37e544258bb2` only to identify the menu boundary. That repository declares no license, so no Feast Lua or custom video/material asset was copied. The implementation is independently derived from the current VT2 decompile.
- `MOD_VERSION` `0.4.32-dev` -> `0.4.33-dev`. Not built/deployed in this pass because the canonical event_tweaker output bundle was pre-existing foreign/shared-tree work and could not be overwritten safely.

Verify with two players: host enables both Dormant Event Missions, opens Own Game, and starts each once with a client connected. Both missions must load for both peers; a normal Helmgart control mission must remain present and unchanged. Run `/event_mission_probe`; the host log should show `contract=OK` and `[event-missions:626] menu applied` with exactly the two selected IDs. Do not mark fixed until this passes in-game.

## 0.4.32-dev (2026-07-14) - issue #393 settled high-intensity diagnostics [not deployed]

- Moved the issue-393 snapshot from the ambiguous `ConflictDirector.init` post-hook to the first `Pacing.update`, after all cross-mod init wrappers have returned. The bounded probe emits one log-only line per mission and now classifies the result as `intact` or `settings_stomp`, including both live globals and the director's cached horde/special/mini-patrol thresholds.
- Added a pure `_evt_issue393_probe.lua` classifier and in-game regression coverage for intact settings, a stomped intensity field, and a stale/stomped director cache. The probe makes no gameplay changes while evidence is still outstanding.
- Source audit clarified vanilla behavior: `high_intensity` indirectly changes pacing through decay, damage gain, and delay thresholds; `GenericStatusExtension` caps player pacing intensity at 100, so the mutator's `max_intensity=200` write does not raise the observable ceiling. A settled `intact` result therefore rules out hook ordering and points to the vanilla mutator's indirect/subtle semantics rather than a failed injection.

## 0.4.31-dev (2026-07-13) - #458 transition-safe shared peer parity [not deployed]

- The shared parity beacon preserves a positive same-peer acknowledgement across a bounded 15-second PlayerManager roster absence during level transitions and delays missing-peer chat for 10 seconds. New, expired, or never-confirmed peers remain fail-closed immediately; this removes the observed false disable/re-enable chat cycle without relaxing wire safety.

## 0.4.30-dev (2026-07-12) - issue #532: preview active mutators on the Tab-hold panel [untested]

### Why
Issue #532 (feature, 2-moderate): issue 461 asked the Tab-hold player-list panel to preview "active mutators and starting boons set from the host". ct_dev shipped the Starting-Boons half (0.7.251-dev, `CT_BOON_PREVIEW_461_MARKER`); this ships the ACTIVE-MUTATORS half on the SAME right-hand panel. Before this, the host had no in-keep confirmation of which mutators their preset + checkbox picks would actually turn on.

### Changed
- New `_evt_preview.lua` (manifest position between `_evt_selection` and `_evt_backend_hooks`). Two hooks on DISTINCT `IngamePlayerListUI` methods (singleton-clean; et had NO hook on this class): `_setup_deed_reward_data` [safe] = build point (fires once on panel activation, keep-only via `self._is_in_inn`, gated on the new `preview_active_mutators` toggle; builds the widget list onto the instance so `_draw` only draws - zero per-frame allocation), and `_draw` [safe] = the guarded draw pass. Crash-proof shape mirrors ct's #461 block exactly: our OWN `begin_pass`/`end_pass` layered on vanilla's, every `draw_widget` individually pcall-wrapped, and icon + name as SEPARATE widgets per row so a mutator whose icon atlas is not resident in the keep degrades to name-only instead of asserting. Adds `mod._evt_mutator_display` / `mod._evt_mutator_icon` (name from the template's own `display_name` loc key, guarding the `<key>` miss-sentinel) and `mod._evt_ct_boon_block_present` (ct-coordination probe). New `/event_preview_mutators` chat command = the robust textual fallback + `/verify` surface. Regression check `issue532_mutator_preview_wired` (marker `EVT_MUTATOR_PREVIEW_532_MARKER` + `preview_selection` + display resolver + toggle).
- `_evt_selection.lua` - new side-effect-free `preview_selection()` (exported `mod._evt.preview_selection`): returns the active list (preset + individual + floor-passing curses, deduped) plus the issue-430 parity-DROPPED curse names, WITHOUT `gather_mutators()`'s injection-time side effects (the `notify_weave_drop` chat line and the `_et455` template wrap). Weave-only names are dropped exactly as `gather_mutators` drops them, so the preview never advertises a mutator that will not activate.
- `event_tweaker_data.lua` - `preview_active_mutators` checkbox (top-level, default ON).
- `event_tweaker_localization.lua` - `preview_active_mutators` (+ tooltip; `[untested]` option-title tag) and the runtime panel strings `evt_mutator_preview_header` / `evt_mutator_preview_client_caveat` (untagged per LOCALIZATION §13).
- `MOD_VERSION` `0.4.29-dev` -> `0.4.30-dev`.

### Notes
- **Placement coordination with ct.** Both blocks anchor to the `reward_divider` node on `banner_right` (ct's Starting-Boons header sits at Y=-700, growing DOWN). When ct's boon preview is active (`ct_dev` or `ct` loaded, enabled, `preview_starting_boons` on) we STACK our block ABOVE it (a positive Y offset on the same node, capped rows) so both render together; when ct is absent our block takes ct's reward-slot position (offset 0, growing down). ct files were read-only reference; no ct file was touched.
- **Issue 430 parity state.** A curse the parity floor will drop (checkbox on + DLC owned + registered, but a lobby peer lacks event_tweaker) renders greyed and flagged "(skipped: a peer lacks the mod)" - never as an active mutator. Solo/all-modded lobbies show no skipped rows (the floor passes). The active list already excludes floor-dropped curses because `selected_curse_mutators()` returns `{}` when unsafe.
- **Client caveat.** et never syncs the host's mutator picks to clients, so on a CLIENT (`not self._local_player.is_server`) the panel shows the client's OWN selection with a caveat sub-line "Your selection - the host's config decides". That is exactly, and only, what et knows client-side.
- Keep-only, local display only (never networked). Tagged [untested] per dev status-tag doctrine; needs an in-game confirm of the panel layout (and a coop confirm that both et + ct blocks render together, and that the skipped-curse row shows with a non-ET peer).

### Refs
Issue #532 (primary), issue 461 (ct sibling half + pattern/marker), issue 430 (curse parity gate the preview reflects). Sources: ingame_player_list_ui_v2_definitions.lua (`reward_divider`/`reward_item`/`banner_right` scenegraph), ingame_player_list_ui_v2.lua:46 (`_is_in_inn`), mutator template `display_name`/`icon` fields. Check: `issue532_mutator_preview_wired`.

## 0.4.29-dev (2026-07-12) - issue #430: Cursed Adventure curse wire-safety floor (peer-parity) [untested]

### Why
Issue #430 (crash, 1-major): enabling a package-bearing Cursed Adventure curse with a non-event_tweaker peer in the lobby hard-CTDs that peer. The only prior safeguard was the checkbox label warning. Wire path: `selected_curse_mutators()` -> `gather_mutators()`/`add()` -> the injected special_event's `mutators` list -> `GameModeBase.append_live_event_mutators` (game_mode_base.lua:264) -> `MutatorHandler` activates each curse and broadcasts it to every peer via `rpc_activate_mutator_client`. The mutator NAME resolves on a vanilla client (`NetworkLookup.mutator_templates` is boot-built from the full template table, network_lookup.lua:266), so the RPC does not crash; the RESOURCE PACKAGE does. The curse spawns a network-replicated husk (`spawn_network_unit`) whose unit lives in `resource_packages/mutators/<name>`, and that package is preloaded ONLY by `_evt_cursed_adventure.lua`'s hooks — which exist only on a peer running event_tweaker. A non-ET peer activates the curse, the husk spawns from the unloaded package, and the engine hard-CTDs it ("Resource not found").

This is a GAMEPLAY axis (the curse spawns real units), so substitution to a vanilla-safe value is not applicable (issue 371 / BUG_CLASSES 31). Per the issue 413 lesson, a host-only mod cannot make an injected package-bearing curse safe on a vanilla client — it can only REFUSE to inject it while any lobby peer lacks the mod.

### Changed
- New `_evt_guard430_curse_parity.lua` (manifest position between `_evt_guard455_boss_events` and `_evt_selection`). Builds + installs the shared peer-parity beacon (`_lib_peer_parity`, issue 371 framework; channel `et_peer_parity_present`, schema 1) and exports `mod._evt.curse_wire_safe`. Registers one gated feature (`et_cursed_adventure_curses`) so the beacon's debounced chat notice names which peer lacks the mod. Adds NO engine hooks; the beacon polls the player roster and drives itself off `mod.update` (event_tweaker had none of its own). Regression checks `issue430_peer_parity_beacon_installed`, `issue430_curse_floor_failsafe`, `issue430_curse_floor_classify`.
- `_lib_peer_parity.lua` copied verbatim from `tools/shared_lib/_lib_peer_parity.lua` (COPIED single-source per the standalone invariant; auto-bundled by the `scripts/mods/event_tweaker/*` package glob).
- `_evt_selection.lua` - `selected_curse_mutators()` now drops ALL curses whenever `curse_wire_safe()` is false. UNCONDITIONAL: the checkbox being on is necessary but the parity check is a hard AND the user cannot override (never toggle-gated). Positive-evidence + fail-safe (false when the beacon is missing/erroring or any peer is unacked); read live so a peer joining just before the mission still blocks. Log-only `[et:430]` drop printf mirrors the issue 413 trail.
- `event_tweaker_localization.lua` - `peer_parity_curse_feature_label` = "Cursed Adventure curses" (used inside the peer-parity chat notice; not a settings-UI option title, so no dev status tag).
- `MOD_VERSION` `0.4.28-dev` -> `0.4.29-dev`.

### Notes
The floor blocks injection at every level-load AND declines to re-inject on the next mission while a non-ET peer remains. The one irreducible residual — a non-ET peer HOT-JOINING mid-mission into an already-cursed run, where the curse units are already spawned and game-object sync replicates the husks — cannot be closed by a host-only mod (identical boundary to the issue 413 weave guard; `hot_join_sync` re-broadcasts to late joiners). The beacon's continuous poll + notice surfaces that case so the host can have the joiner install the mod. Checkboxes stay visible (visibility is user-dictated; VMF widgets build once); the effective auto-disable is the injection-time floor + the peer-naming notice, matching the issue 413 precedent. Needs 2+ people (one WITHOUT event_tweaker) to verify - tagged [untested], verify-fix-coop.

### Refs
Issue #430 (primary). Framework: issue 371 (peer-parity umbrella), issue 413 (sibling weave gate), issue 424/425/426 (beacon consumers crt/ct). Sources: game_mode_base.lua:264, network_lookup.lua:266, mutator_handler.lua (activate/hot_join_sync), deus_run_state.lua:438-453. Checks: `issue430_peer_parity_beacon_installed`, `issue430_curse_floor_failsafe`, `issue430_curse_floor_classify`.

## 0.4.28-dev (2026-07-12) - issue #413: host-visible notice for the deliberate Winds-mutator drop [untested]

### Why
Issue #413 reopened ("not fixed, no crash, but the mutator simply isn't active or working"). The v0.4.24-dev unconditional drop of the seven weave-only Winds-of-Magic mutators is the CORRECT wire-safe behavior: activating one CTDs vanilla Adventure clients (the stock `mutator_shadow.lua` client_update spawns the non-resident `wpn_shadow_gargoyle_head` then `Unit.light` engine-fatals, mutator_shadow.lua:186-187), it runs on every peer with a local client (mutator_handler.lua:210), and `hot_join_sync` re-broadcasts the activation to late joiners (mutator_handler.lua:148-159). But from the host's chair the drop read as "the checkbox does nothing" -- the `[et:413]` drop printf is console-only and invisible with mod-logging OFF.

Recorded finding (in `_evt_guard413_weave.lua`): the units cannot simply be preloaded. Unlike the package-bearing Chaos Wastes curses (loadable `resource_packages/mutators/<name>`), the weave winds carry no packages field and no standalone package; `wpn_shadow_gargoyle_head` / `vfx_static_shadow_01` live only in the weave LEVEL bundles (`dlc_scorpion_*_shadow`), which Adventure never loads. Making shadow RUN in Adventure would need event_tweaker to ship those units in its own package (modded peers only) PLUS a server-side light_radius fallback (server_update does `radius*radius` with radius=nil outside a weave -- the same crash that already blacklists the identical `curse_belakors_shadows`, event_tweaker_curses.lua:38), and would still CTD any vanilla joiner. That is a product decision, not a silent fix -- see the issue #413 comment.

### Changed
- `_evt_selection.lua` - when the injection chokepoint (`gather_mutators`/`add()`) drops a weave-only mutator that the HOST explicitly enabled (`mod:get("mut_"..name)`), it echoes a one-line host-visible skip notice. Preset-injected drops stay silent; the unconditional drop and the `[et:413]` printf are unchanged.
- `_evt_guard413_weave.lua` - added `notify_weave_drop` (session-deduped, host-only `mod:echo` -- never networked, zero vanilla-peer exposure; session-level dedup avoids a 2nd `StateIngame.on_exit` hook, owned by `_evt_cursed_adventure`). New regression check `issue413_weave_drop_notice_dedups`. Docstring now records the no-loadable-package finding so the "just preload it" dead end is not re-walked.
- `MOD_VERSION` `0.4.27-dev` -> `0.4.28-dev`.

### Notes
This does NOT make the Winds mutators run in Adventure; it makes the deliberate wire-safe drop visible and explained. Full functionality needs a user go-ahead + in-game verify on one of: (a) ship the units in event_tweaker's package + server light_radius fallback, gated all-peers-modded like the Cursed Adventure group (same vanilla-joiner exposure), or (b) a host-side gameplay-only reimplementation of the shadow buff (wire-safe, but no light/fade visual). Tagged [untested] per dev status-tag doctrine.

### Refs
Issue #413 (primary). Related: issue 386 (scalar pacing sanitizer, sibling injection guard), issue 455. Sources: mutator_shadow.lua:80/87/186-187, mutator_handler.lua:148-159/210, item_master_list_local.lua:318, event_tweaker_curses.lua:38. Check: `issue413_weave_drop_notice_dedups`.

## 0.4.27-dev (2026-07-12) - issue 427: _dbg_alert routes to log-only printf

### Why
Issue 427/240: `_evt_log.lua`'s `_dbg_alert` routed through `mod:warning`, which VMF `logging.lua` posts to in-game CHAT under default settings (warning mode >= 2). Callsites like the `_evt_cursed_adventure.lua` curse-preload-failure would surface in chat rather than the console log.

### Changed
- `_evt_log.lua` - `_dbg_alert` now routes through pcall-guarded engine `printf` (log-only, survives mod-logging-OFF), matching enemy_tweaker v0.7.25-dev (BUG_CLASSES section 17 Variant B). `_dbg` (mod:debug) and the exported `ET.dbg_alert` surface unchanged; callsites unaffected.
- `MOD_VERSION` `0.4.26-dev` -> `0.4.27-dev`.

### Notes
The curse-preload-failure alert (`_evt_cursed_adventure.lua`) is a genuine anomaly a host may want visible; it now logs to console only. If chat visibility is wanted there, add an explicit `_chat_alert` (out of scope for #427).

### Refs
Issue 427 (parent), 240. Check: `qa/check_logging.ps1` warn-chat.

## 0.4.26-dev (2026-07-11) -- Structural refactor: split the monolith into single-responsibility modules; consolidate the hand-synced catalogs (no behavior change)

### Why
OOP-professionalization pass (docs/OOP_REFACTOR_PLAN.md; user directive: single-responsibility files, human-readable code). The 1,433-line `event_tweaker.lua` mixed twelve concerns in one chunk, and the 2026-07-07 audit scored the mod 2/5 on Duplication because the mutator catalog and the DLC-gate maps each lived as TWO hand-synced copies (script + data file) guarded only by "keep in sync" comments. Pure structural change: every function, hook, command, guard, and log/printf string is verbatim-identical; three independent adversarial review agents diffed the split against the monolith (semantic equivalence, orphaned-upvalue/load-order/duplicate-hook sweep, guard-integrity sweep) and returned zero behavior findings.

### Changed -- file layout only
- `event_tweaker.lua` is now a 65-line entry point: MOD_VERSION, the load banner/echo lines, the `mod._evt` shared namespace, and an ordered `mod:dofile` manifest. Module prefix is `_evt_` (`_et_` already belongs to enemy_tweaker's modules).
- New single-responsibility modules, each with a PROJECT_STANDARDS § 2.2 docstring header: `_evt_log` (dbg helpers + settings fingerprint), `_evt_regression` (harness + generic checks), `_evt_dlc` (fail-closed ownership gate), `_evt_guard413_weave` (issue 413 gate), `_evt_guard455_boss_events` (issue 455 guard), `_evt_selection` (preset/discovery/gather chokepoint), `_evt_backend_hooks` (the three live-event hooks), `_evt_guard386_pacing` (issue 386 sanitizer), `_evt_diagnostics` (probe/active/clear commands + issue 393 snapshot), `_evt_apply` (mid-game reload + on_setting_changed), `_evt_cursed_adventure` (curse package preload + cursed-sky lighting).
- New shared require'd module `event_tweaker_catalog.lua` (same pattern as `event_tweaker_curses.lua`): single copies of CATEGORIES, EVENT_PRESETS, DLC_BY_MUTATOR, DLC_BY_PRESET. `event_tweaker_data.lua` and `_evt_dlc.lua`/`_evt_selection.lua` now read the SAME tables -- the duplicated-catalog failure mode is retired, not just documented. The deliberate fail-open (UI) vs fail-closed (injection) split of the two ownership predicates survives and is now documented at both sites.
- `_MEM_PROBE_T0_EVT` bare `_G` global became a local in the entry file (mem-probe semantics unchanged: still brackets the whole load).
- All issue guards, their `[et:413]`/`[et:455]`/`[event-inject:386]`/`[event-inject:393]` printf tags, the seven `/event_tweaker_regression_test` check names AND their registration order, the five chat commands, and all 10 hooks (each (class, method) pair still registered exactly once) are unchanged.
- Docs (first-class deliverable, same version): DEVELOPMENT.md gained per-module "Module contracts" (responsibility, public surface, manifest position for every file) plus a "Where new code goes" placement recipe, and lost the "keep these two tables in sync" instructions; stale claims purged (header said Visibility private while itemV2.cfg says public; retired `mod._ET_CURSE_BROKEN` reference). REGRESSION_CHECKLIST.md detection pointers updated to the new file names. New thin `event_tweaker/CLAUDE.md` (guardrails + router, no duplication), routed from the monorepo hub CLAUDE.md. The reusable split conventions are codified repo-wide in PROJECT_STANDARDS section 2.2a; per-decomposition doc deliverables tracked as OOP_REFACTOR_PLAN WS8.

### Not changed
- Zero gameplay/injection/UI behavior. No settings added, removed, or re-defaulted; widget tree and localization byte-identical; log line order at load identical. `MOD_VERSION` `0.4.25-dev` -> `0.4.26-dev`.

### In-game verify
Full Steam restart, then: chat shows `[event_tweaker] v0.4.26-dev loaded` and the log shows `[event_tweaker:LOAD] v0.4.26-dev enabled fp=... OK`; `/event_tweaker_regression_test` prints all 7 checks PASS in the usual order; mod options menu opens with the same groups/checkboxes as 0.4.25-dev; `/event_probe` still dumps state.

## 0.4.25-dev (2026-07-10) -- Fix host fatal from Multiple Bosses on fixed-boss levels (#455): guard CurrentBossSettings.boss_events

### Why
Hosting fixed-end-boss levels (crash evidence: level key `warcamp` = The War Camp, user log `console-2026-07-09-04.06.24`) with the "Multiple Bosses" mutator checked crashed the HOST with `mutator_multiple_bosses.lua:8: attempt to index field 'boss_events' (a nil value)`. Mechanism: `CurrentBossSettings` is rebuilt per level from the conflict director's `boss` block (`conflict_director.lua:879`), and some levels' boss blocks carry NO `boss_events` table; the vanilla mutator indexes `CurrentBossSettings.boss_events.event_lookup.event_boss` unguarded in both `server_initialize_function` and `update_conflict_settings` (`mutator_multiple_bosses.lua:8/:13`), dispatched at `mutator_handler.lua:644-645` / `:578-579`. Source sweep of `scripts/settings/mutators/` found two siblings with the same unguarded index in `server_start_function`: `blessing_of_grimnir` (`mutator_blessing_of_grimnir.lua:60`) and `deus_pacing_tweak` (`mutator_deus_pacing_tweak.lua:482/:498`) -- not currently in our catalog, but guarded too in case discovery ever surfaces them. Distinct crash class from the weave-only gate (issue 413): these mutators are Adventure-legal, they just cannot run on levels without roaming boss events.

### Fixed -- `event_tweaker.lua`
- New `BOSS_EVENT_GUARDS` map + `mod._et455_guard_boss_event_mutator(name)`: on injection, wraps the template's live dispatch fields (`template.server.initialize_function` / `template.server.start_function` / `template.update_conflict_settings`) with a check that no-ops -- with one guarded `[et:455] skipped ...` printf -- when the current level's `CurrentBossSettings.boss_events` is absent. Dispatch-time check, so the mutator still works on every level that has boss events; wrap is idempotent (`__et455_guarded` marker) and host-side only.
- `gather_mutators()`'s `add()` chokepoint installs the guard for every injected name, covering preset, checkbox, discovered, and curse routes.
- New regression check `issue455_boss_event_mutators_guarded`: predicate fails closed on a boss block without `boss_events` (the warcamp shape), passes with it, and the installed guard marks the template.

### Verify
Host The War Camp in Adventure with "Multiple Bosses" checked: mission must load with no crash and the host log must show `[et:455] skipped multiple_bosses.server.initialize_function ...`. Then host a roaming-boss level (e.g. Screaming Bell) with it checked: no `[et:455]` skip line, dual boss events still fire.

## 0.4.24-dev (2026-07-08) -- Fix Adventure-client CTD from injected weave-only mutators (#413): gate cat_winds at the injection chokepoint

### Why
Activating the "shadow" Winds-of-Magic mutator on an Adventure mission crashed CLIENTS with an engine fatal in `Unit.light` (crash locals: `is_server=false`, `wind_settings=nil`, shipped `mutator_shadow.lua:175`). Mechanism: the mutator's `client_update_function` spawns `units/weapons/player/wpn_shadow_gargoyle_head` and calls `Unit.light(unit, "light")` (decompiled `mutator_shadow.lua:186-187`); that unit is resident only in the Weave context, so on an Adventure peer the spawn is invalid and `Unit.light` raises an engine-level fatal that bypasses pcall. The client update runs on every peer with a local client (`mutator_handler.lua:210` keys on `_has_local_client`, host included), and vanilla clients cannot be preloaded by a host-only mod, so exclusion at injection is the only safe fix. Verification of the whole `cat_winds` group against the decompiled source found six siblings that are also unsafe outside a weave (`Managers.weave:get_active_wind_settings()` returns nil unless a weave template is active, `weave_manager.lua:423-432`): `heavens` / `light` / `death` / `beasts` nil-index `wind_settings` in `server_start_function` (`mutator_heavens.lua:38`, `mutator_light.lua:182`, `mutator_death.lua:210`, `mutator_beasts.lua:122`); `fire` nil-indexes it in `client_start_function` on every peer (`mutator_fire.lua:39`); `life` network-spawns the weave-package unit `units/weave/life/life_thorn_bushes_mutator` (`mutator_life.lua:19-24`), the same non-resident-resource fatal class as shadow. `metal` is safe (`get_wind_strength()` falls back to 1, `weave_manager.lua:679-683`; no `wind_settings` index, no unit spawns) and stays injectable. Sibling of the known "mutator packages are Deus-only" class from issue 386's mod-family (see `docs/BUG_CLASSES.md` / memory `reference_vt2_mutator_packages_deus_only`), but package-FREE, so the existing `packages` filter could not catch it.

### Fixed -- `event_tweaker.lua`
- New `WEAVE_ONLY_MUTATORS` blocklist (7 of the 8 `cat_winds` entries; `metal` excluded on purpose) plus `_weave_wind_active()` (pcall-guarded read of `Managers.weave:get_active_wind_settings()`; any error fails closed as "no weave context").
- `gather_mutators()`'s `add()` -- the single chokepoint every injection route funnels through (preset, checkbox, discovered, curse) -- now drops blocklisted names whenever no weave wind is active, BEFORE they reach `append_live_event_mutators` and broadcast to peers via `rpc_activate_mutator_client`. Each drop prints one guarded `[et:413] dropped weave-only mutator [...]` line via engine `printf`.
- New regression check `issue413_weave_only_mutators_gated`: the 7 crashers must be blocklisted, `metal` must not be, and outside a weave the gate must read "no wind active".

### Not changed
- Real Weave missions get their wind mutators from the weave template via `Managers.weave:mutators()` (`game_mode_weave.lua:134-138`), not from the live-event injection path, so Weave / Deus / vanilla behavior is untouched. Checkboxes stay visible; the drop is injection-time only. Presets, DLC gate, the three live-event hooks, and the issue 386 sanitizer untouched. `MOD_VERSION` `0.4.23-dev` -> `0.4.24-dev`.

### In-game verify
Host an Adventure mission with the Shadow (Winds of Magic) checkbox on and a client connected: the mission must load with NO client CTD, the host log must show the `[et:413] dropped weave-only mutator [shadow]` line, and `initialized_mutator_map` must NOT contain `shadow`. Other checked non-wind mutators must still activate normally.

## 0.4.23-dev (2026-07-06) -- Post-init conflict-settings snapshot (issue 393 diagnostics-armed; no behavior change)

### Why
Issue 386 (v0.4.22-dev) stopped the injected `high_intensity` mutator from CRASHING `ConflictDirector.init`, but the mutator reportedly has little observable in-mission effect. Hypothesis [unverified]: `enemy_tweaker`'s own conflict-director patch re-application runs on the SAME `refresh_conflict_director_patches` chain (`conflict_director.lua:886`, dispatched from `ConflictDirector.init` line 94) and overwrites the mutator's `CurrentIntensitySettings` / `CurrentPacing` writes (`mutator_high_intensity.lua:8-14` sets `max_intensity=200`, `decay_per_second=10`, `decay_delay=0.5`, `intensity_add_per_percent_dmg_taken=0.1`, and the three `delay_*_threat_value=200`) after they land but before they take effect. This build adds a read-only probe to settle that either way; it changes NO behavior.

### Added -- `event_tweaker.lua`
- New `hook_safe` on `ConflictDirector.init` (fires AFTER init completes; event_tweaker had no prior `ConflictDirector` hook). Prints ONE guarded `printf` line per mission init: `[event-inject:393] post-init snapshot | injected=[<names or none>] max_intensity=%s decay_per_second=%s decay_delay=%s add_per_pct_dmg=%s delay_horde=%s delay_specials=%s delay_mini_patrol=%s (self.delay_horde=%s)`. It reads the four `CurrentIntensitySettings` fields, the three `CurrentPacing.delay_*_threat_value` fields (per-difficulty tables after the #386 sanitizer, summarized as `table:normal=<v>`), and the converted `self.delay_horde_threat_value` the director instance will pace against (`conflict_director.lua:219`). The injected list is event_tweaker's own `gather_mutators()` -- the same builder the `[event-inject]` special_events line uses.

### What the line proves
- `high_intensity` in the injected list but `max_intensity` reads a vanilla default (not 200) and/or the delays are NOT `table:normal=200` -> the mutator's writes were STOMPED after landing (confirms the hypothesis; next step is ordering enemy_tweaker's re-application vs the mutator's).
- `max_intensity=200` and delays `table:normal=200` with `high_intensity` injected -> the writes SURVIVED intact, so the "little effect" report is not a stomped-settings problem and the search moves to how the pacing/intensity values are consumed.

### Not changed
- No behavior change. Injection, presets, mutator catalog, DLC gate, the three live-event hooks, and the #386 sanitizer are untouched -- this only adds a read-only `printf` snapshot. printf only (user runs mod-logging OFF), always-on in dev per the diagnostics doctrine. `MOD_VERSION` `0.4.22-dev` -> `0.4.23-dev`.

## 0.4.22-dev (2026-07-06) -- Fix ConflictDirector.init death from injected mutators writing scalar pacing values (issue 386)

### Why
Injecting a mutator whose `update_conflict_settings` writes plain numbers into `CurrentPacing` (canonical case `mutator_high_intensity.lua:12-14`: `delay_horde_threat_value` / `delay_specials_threat_value` / `delay_mini_patrol_threat_value = 200`) killed `ConflictDirector.init` and left the whole mission with zero AI (host reported no spawns, no boss, no terror events for an entire Adventure run).

Mechanism: `MutatorHandler.conflict_director_updated_settings` (`mutator_handler.lua:567`) runs every INITIALIZED mutator's `update_conflict_settings`, and is dispatched by `ConflictDirector.refresh_conflict_director_patches` (`conflict_director.lua:886`), which `ConflictDirector.init` calls at line 94 -- BEFORE init reads those same three fields at lines 219-221 and passes each to `DifficultyTweak.converters.tweaked_delay_threat_value`. That converter ALWAYS indexes its argument as a per-difficulty table (`difficulty_tweak.lua` `get_value_for_difficulty`: `value_table[Difficulties[i]]`), so a scalar there is an uncatchable "attempt to index a number value" fatal. In plain vanilla Adventure these mutators aren't in the list, so the fields keep their table-shaped base values (`conflict_settings.lua`, keys `normal`..`versus_base`); event_tweaker's live-event injection is what puts a scalar-writing mutator into the set on a normal map.

### Fixed -- `event_tweaker.lua`
- Added a `hook_safe` on `MutatorHandler.conflict_director_updated_settings` that runs after the vanilla dispatch writes the scalars (still synchronously inside `refresh_conflict_director_patches`, so before init's line 219 read) and converts any scalar left in the three pacing fields into `{ normal = v, [current_difficulty] = v }`. `get_value_for_difficulty` walks DOWN the `Difficulties` list to index 1 == `normal`, so the floor key covers every difficulty; init then reads a table and resolves the intended magnitude (200) instead of crashing. Host-only in effect (`conflict_director_updated_settings` early-returns on clients) and a strict no-op whenever the fields are already tables -- i.e. whenever nothing is injected. Emits `[event-inject:386] sanitized update_conflict_settings for [<mutators>] (fields: ...)` via `printf` only when it actually converts a scalar.
- New regression check `issue386_sanitize_pacing_scalar_to_table`: a stub scalar `delay_horde_threat_value = 200` must convert to an indexable table (floor `normal` + current-difficulty key both 200), and an already-tabular field must be left untouched (no-op).

### Not changed
- Injection timing, presets, mutator catalog, DLC gate, and the three live-event hooks untouched -- this only reshapes the scalar CurrentPacing writes into what `ConflictDirector.init` expects. `MOD_VERSION` `0.4.21-dev` -> `0.4.22-dev`.

### In-game verify
Host any Adventure mission with an event_tweaker preset (or checkbox) that injects `high_intensity`: enemies must spawn normally, the log shows the `[event-inject:386]` line and NO `difficulty_tweak.lua` "index a number value" error, and the run must reach and spawn a boss / terror events.

## 0.4.21-dev (2026-07-04) -- Localization: applied dev status-tag doctrine (#301)

Prefixed every option-title loc string with a dev status tag per `LOCALIZATION_STANDARD.md` § 13. 61 widget titles tagged: 56 [working] (the established mutator catalog + event_preset + suppress_live_event, all predating 0.4.14-dev), 5 [untested] (the Cursed Adventure feature added 0.4.14-dev: the `cat_cursed` group, `cursed_lighting`, the `cat_other` group, plus the two runtime title-generation sites for the discovered "Other Mutators" and the package-bearing curses). 0 issue-tagged: event_tweaker has no dedicated GitHub issue label (the `et` label maps to enemy_tweaker, not this mod) and no open issue maps to the mutator picker. Titles only; no `*_tooltip`, `preset_*` dropdown value labels, or `mod_description` touched. `MOD_VERSION` `0.4.20-dev` -> `0.4.21-dev`.

## 0.4.20-dev (2026-07-02) -- #222 loc sweep: removed leading option-title restatement from 8 option tooltips so the popup body no longer repeats the orange header

### Why
VMF draws each option's title as the popup's orange header automatically. The eight Winds of Magic tooltips (`mut_life` through `mut_beasts`) opened by restating that title ("The Wind of Life. ...", "The Wind of Metal. ...", etc.), so the option name showed twice. Removed the leading restatement so each body opens with the behavior.

### Changed -- `event_tweaker_localization.lua`
- `mut_life_tooltip`: "The Wind of Life. A healing-themed modifier." -> "A healing-themed modifier."
- `mut_metal_tooltip`: "The Wind of Metal. A damage-resistance modifier." -> "A damage-resistance modifier."
- `mut_heavens_tooltip`: "The Wind of Heavens. Adds lightning effects." -> "Adds lightning effects."
- `mut_light_tooltip`: "The Wind of Light. Adds truesight effects." -> "Adds truesight effects."
- `mut_shadow_tooltip`: "The Wind of Shadow. Adds stealth effects." -> "Adds stealth effects."
- `mut_fire_tooltip`: "The Wind of Fire. Adds burning effects." -> "Adds burning effects."
- `mut_death_tooltip`: "The Wind of Death. Adds necromantic effects." -> "Adds necromantic effects."
- `mut_beasts_tooltip`: "The Wind of Beasts. A Beastmen-themed modifier." -> "A Beastmen-themed modifier."

### Not changed
- No title entries touched; only tooltip bodies. All other tooltips already open with a behavior verb, so nothing else qualified. `MOD_VERSION` `0.4.19-dev` -> `0.4.20-dev`.

## 0.4.19-dev (2026-07-01) -- Rewrote every option description for players; stripped internal mutator ids and non-ASCII/em-dash characters from menu text

### Why
Every mutator tooltip led with its raw internal id in brackets (e.g. `[no_ammo] ...`), several carried developer shorthand ("DLC batch 02", "conflict director"), and a handful of strings used non-ASCII arrows / em dashes. None of that is useful to a player reading the VMF settings menu.

### Changed -- `event_tweaker_localization.lua`
- Rewrote `mod_description`, `event_preset_tooltip`, `suppress_live_event_tooltip`, `cursed_lighting_tooltip`, and all 47 curated `mut_*_tooltip` values into plain player-facing English (max 2-3 sentences each). Dropped the leading `[internal_id]` prefix and internal jargon from every one; meaning preserved from the prior text, nothing invented.
- Removed em dashes and non-ASCII characters from menu-facing strings: `cat_cursed` label (em dash -> colon), `preset_skulls_2023` label (non-ASCII arrow removed; `hordes_galore` -> "Hordes Galore"), `preset_skulls_2026` label (em dash -> semicolon), and the generated Cursed Adventure curse tooltip (em dash -> period).
- Simplified the three Geheimnisnacht preset labels to drop internal level keys (`dlc_portals`, `dlc_castle`, etc.) that a player can't read; they now say "ritual sites on that year's maps".
- Retitled the `suppress_live_event` label to "Suppress the game's live event" (was "Fatshark's live event").

### Not changed
- No `mod:localize(...)` widget-level calls needed converting (there were none; the only eager localize is the top-level `mod_description` in `_data.lua`, which is correct).
- No missing loc keys: every static widget-referenced key already resolved; the dynamic "Other Mutators" / "Cursed Adventure" groups still register their labels/tooltips from the game's own localized strings at runtime.
- Setting ids, keys, widget structure, and defaults untouched. `MOD_VERSION` `0.4.18-dev` -> `0.4.19-dev`.

## 0.4.18-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.4.17-dev (2026-06-26) -- revert #135 weekly-god diagnostic (added to the wrong mod)

Revert the #135 weekly-god diagnostic. The weekly god / cursed-sky theme is a **chaos_wastes_tweaker** feature, not event_tweaker — the probe was added to the wrong mod. Removed both `[et-probe:weekly]` emit points (`get_special_events` after `gather_mutators()`, and `_refresh_active_curse_god`) plus the now-unused `local _printf` helper and its comment block (0 remaining uses). Surrounding vanilla logic restored exactly as it was before the probe. No behavior change. `MOD_VERSION` `0.4.16-dev` → `0.4.17-dev`.

## 0.4.16-dev (2026-06-26) -- #135 DIAGNOSTIC: weekly god/curse override mismatch (instrument, NOT a fix)

### Why
User report: selected **Tzeentch** but the run themed/resolved to **Slaanesh** — a god/curse mapping mismatch in the Cursed Adventure feature. This build adds a printf diagnostic so the next session can read `selected` vs `applied` straight from the log. **No behavior change — diagnostic only.**

### Added — `[et-probe:weekly]` (raw `printf`, bypasses the mod-logging toggle)
- `event_tweaker.lua` — new guarded `local _printf = rawget(_G, "printf") or function() end`. Two emit points, both tagged `[et-probe:weekly]`:
  1. **In `get_special_events`** (right after `gather_mutators()`, the apply point that runs on mission/keep load): logs `preset=…`, `selected_curses=[curse:god,…]` (from the `mut_<id>` settings, each tagged with the god it is *meant* to theme), `injected_mutators=[…]` (what actually reaches the lobby), `applied_theme_god=…`, and `alpha_first_curse=…`.
  2. **In `_refresh_active_curse_god`** (the runtime resolution point): logs the live active curse set + the resolved `applied_god` + `alpha_first`.
- This surfaces the likely culprit: the cursed-sky/theme god resolves as the **alphabetically-first** active curse's god (a deterministic tie-break in `_refresh_active_curse_god`), so when curses of different gods are enabled at once, the alpha-first curse — not necessarily the one the user "meant" — wins the theme. `selected=tzeentch applied=slaanesh` will be readable from one line. **No mapping change made yet** (that's the follow-up once the log confirms the divergence).

### Files
- `event_tweaker.lua` — `MOD_VERSION` `0.4.15-dev` → `0.4.16-dev`; `_printf` helper; 2 `[et-probe:weekly]` emit points. No hooks added (lint-confirmed: 8 hooks, 0 duplicate).

## 0.4.15-dev (2026-06-20) -- Active-mutator logging + clarify night_mode's confusing in-game name

### Why
User report: with Event Tweaker on (no preset/event/curse selected), TAB's active-mutator list showed "Geheimnisnacht Night Mode" and the mission darkened — looked like the mod was forcing the Geheimnisnacht event. Root cause from the log (`[event-inject] ... injecting 1 mutator(s): [night_mode]`) + the saved setting (`mut_night_mode = true`): the user had the **Night Mode** checkbox (Atmosphere group) on, and the vanilla `night_mode` mutator's in-game display name *is* "Geheimnisnacht Night Mode" (it's that event's signature darkening mutator). Not a bug — `night_mode` is a standalone mutator, not the event — but the naming is confusing, and the log didn't make the full active set obvious.

### Changed
- `event_tweaker.lua` — `get_special_events` now logs the **"injecting NOTHING"** case (with Fatshark's pass-through list) under `enable_debug_logging`, so the log unambiguously shows when ET injects nothing vs. when a real live event is active. The `MutatorHandler._activate_mutator` hook now `_dbg`-logs **every** mutator the handler activates (`[mutator-active] '<name>'`) — ours OR vanilla — so the log shows the full active set; cross-reference with `[event-inject]` to tell them apart.
- `event_tweaker_localization.lua` — `mut_night_mode` tooltip now warns it shows as "Geheimnisnacht Night Mode" in-game and does NOT activate the event.
- MOD_VERSION `0.4.14-dev` → `0.4.15-dev`.

### Fix for the user
Uncheck **Night Mode** in the Atmosphere group (or run `/event_clear` to clear all individual mutators). The preset dropdown is separate and was already Off.

## 0.4.14-dev (2026-06-19) -- Incorporate "Deed Mutators Selector" + "Cursed Adventure" (CW/Be'lakor curses on standard maps, with themed lighting)

### Why
Two related additions, both consolidated into event_tweaker (the mutator picker's natural home — it already activates mutators via the `get_special_events` live-event hook).

1. **Deed Mutators Selector port** — that mod (Workshop `3579882542`) dynamically surfaces every engine-flagged player-facing mutator (`display_name`+`description`) instead of a curated list. event_tweaker already had every *deed* mutator; the delta was the Chaos Wastes / Be'lakor / Deus set.
2. **Cursed Adventure** — make the package-bearing CW/Be'lakor *curses* actually run on a standard adventure mission (they normally crash there — `[VT2 mutator packages are Deus-realm only]`). A 4-agent adversarial source audit (2026-06-19) proved the curse *mechanics* use only standard mission managers and that every DLC entity system they need is registered into every mission at boot (`entity_system.lua:176` + `:424-435`); the *only* blocker is the resource package, which `DeusRunState.set_event_mutators` loads only in the Deus realm. So we preload it ourselves.

### Added — dynamic discovery ("Other Mutators" group)
- `event_tweaker.lua` — `_is_adventure_safe_mutator(name, tmpl)` (display_name+description, not `hide_from_player_ui`, no `packages`, not in `_CURSE_BROKEN_IN_ADVENTURE`) + cached `displayable_registered_mutators()`. `selected_individual_mutators()` / `/event_clear` union curated + discovered. New `dynamic_mutator_discovery` regression check.
- `event_tweaker_data.lua` — dynamic `cat_other` group. `event_tweaker_localization.lua` — labels pulled from the game's own `Localize` (no fabrication), `%`-escaped.

### Added — Cursed Adventure ("Cursed Adventure" group)
- `event_tweaker.lua` — `MANAGED_CURSES` (11 package-bearing curses → Chaos god + DLC), `_CURSE_TO_GOD`, `selected_curse_mutators()` (injected via `gather_mutators`), and a do-block of hooks:
  - **`MutatorHandler._activate_mutator`** (the chokepoint hit on the HOST via `activate_mutators` AND every CLIENT via `rpc_activate_mutator_client` → `_activate_mutator`, `mutator_handler.lua:782`) — SYNC-preloads the curse's `packages` on that peer (`Managers.package:load(pkg, ref, nil, false)`) *before* the mutator's `start_function`, exactly like `DeusRunState.set_event_mutators` does per-peer. Clients need it too (`spawn_network_unit` replicates a husk).
  - **`StateIngame.on_exit`** — ref-balanced `unload` + cache clear.
  - **`CameraManager.shading_callback`** — per-god multiplicative ShadingEnvironment-var tint (profiles copied from `chaos_wastes_tweaker.lua:3247`); blends on the level's baked atmosphere and reverts for free every frame. `cursed_lighting` toggle (default on).
  - All gated to `Managers.mechanism:current_mechanism_name() == "adventure"` so a real Chaos Wastes run (where Deus already loads the package and ct already tints) is untouched.
- `event_tweaker_data.lua` — `cat_cursed` group from `mod._ET_MANAGED_CURSES` + the `cursed_lighting` toggle. `event_tweaker_localization.lua` — curse labels from the game's own strings + a per-curse tooltip noting the god, the all-players-need-the-mod requirement, and the experimental flag.

### Excluded (verified hard-crashers — never surfaced anywhere)
- `curse_bolt_of_change` — spawn path calls `Managers.mechanism:game_mechanism():get_deus_run_controller()`, a `DeusMechanism`-only method (`deus_mechanism.lua:523`) → nil-method crash on every bolt.
- `curse_belakors_shadows` — actually a *weave* mutator; `server_update` does `radius*radius` with `radius=nil` outside a weave → nil-arithmetic crash. (Package-free, so it's in `_CURSE_BROKEN_IN_ADVENTURE` — the package filter alone wouldn't catch it.)
- `curse_empathy` — package-free, no Deus deps, but a latent server-side nil-index (`data.hero_side` unset on the server). Excluded until verified in-game.

### Multiplayer constraint (new for the curse group only)
The package-bearing curses require **every player in the lobby to run event_tweaker** — clients load the curse package locally to instantiate the replicated curse units. The rest of the mod (presets, vanilla mutators, the "Other Mutators" group) stays host-only.

### Hardening (post-verification — a 4-lens adversarial pass caught two blockers + edges)
- **Load-order blocker (fixed):** VMF loads a mod's files `localization → data → script`, so the script runs LAST — the first cut set `mod._ET_MANAGED_CURSES` in the script and read it in `_data.lua`/`_localization.lua`, where it was nil, so the whole Cursed Adventure UI group never built and the package-free broken curses leaked into "Other Mutators". Fixed by moving the catalog into a new shared module **`event_tweaker_curses.lua`** that all three files `require` (the `enemy_tweaker_breeds` pattern; bundled automatically via the `scripts/.../*` wildcard). The loc file also had no `local mod`, so its `mod._ET_*` reads would have nil-indexed at runtime — the `require` removes that too.
- **Hot-join crash (fixed):** a client joining MID-mission instantiates already-spawned curse husks during game-object sync, which the engine does BEFORE the mutator-activate RPC — so the `_activate_mutator` load arrived too late and `World.spawn_unit` on the unloaded package crashed the joiner. Added a `MutatorHandler.init` `hook_safe` that preloads from the network-synced `_initialized_mutator_map` (populated at handler construction, before game objects) on every peer. Normal-join + host were already safe via `_activate_mutator`; this closes the hot-join window.
- **`self._world == world` guard** added to the shading hook (vanilla's mandatory precondition — don't tint UI/preview/end-screen worlds).
- **Deterministic multi-god tint:** when curses of different gods are active, the alphabetically-lowest curse name wins (was `pairs()`-order, which diverges host vs client).
- **Package ref-leak:** `on_exit` now only drops a package entry whose `unload` pcall actually succeeded.

### Status
`build event_tweaker` compiles clean (4 files, 4 bundles). mod-lint: PASS (8 hooks, 0 duplicate/forward-ref/late-local). Hook points + all 11 curse names + the load order source-verified; adversarial 4-lens verification run and its two blockers + edges fixed. NOT yet uploaded — event_tweaker is a **public** mod; needs in-game testing + explicit per-build ship approval before a public Workshop push.

## 0.4.13-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `event_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[ewt] v<MOD_VERSION> loaded")` runs once. The short id `ewt` is used in the chat banner per the canonical short-id list in CLAUDE.md (the applied-marker line above still uses `[event_tweaker]` for log-grep continuity).

## 0.4.12-dev (2026-05-25) -- Fix applied-marker prefix typo (`[ewt]` -> `[event_tweaker]`)

### Why
The applied-marker line at `event_tweaker.lua:69` printed `[ewt] enabled v%s settings_fp=%s`. `ewt` is not this mod's id -- per the Mod Directory + the 0.4.9-dev CHANGELOG entry, the canonical prefix is `[event_tweaker]` (the directory name + VMF mod id), matching how the file's `_dbg` / `_dbg_alert` helpers use `[event_tweaker:dbg]` / `[event_tweaker]`. The typo silently broke log greps of the form `\[event_tweaker\] enabled v` that the Fix 3 audit (2026-05-25 EOD) was running across all 16 mods.

### Changed
- `event_tweaker.lua` -- applied-marker line now reads `[event_tweaker] enabled v%s settings_fp=%s`. Format unchanged (the bracketed id is the only edit) so existing log-parsing regexes still match.

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.11-dev (2026-05-25) -- Add Geheimnisnacht 2026 + Khorne's Skulls 2026 presets

### Why
Source `scripts/settings/dlcs/geheimnisnacht_2026/` and `dlcs/skulls_2026/` are present in decompiled VT2 (FEATURE flags `FEATURE_geheimnisnacht_2026` + `FEATURE_skulls_2026` both TRUE in 2026-05-25 game log). The 2026 DLCs only add cosmetics + portraits -- gameplay still rides the existing `mutator_geheimnisnacht_2021` (ritual sites) and `mutator_skulls_2023` (skull pickups). Adding preset entries lets the host select the 2026 year cleanly.

### Changed
- `event_tweaker.lua` -- `EVENT_PRESETS` gained `geheimnisnacht_2026` and `skulls_2026` entries. Geheimnisnacht 2026 maps verified in `dlcs/geheimnisnacht_2025/geheimnisnacht_utils.lua:43-49` (`maps_by_year[2026] = { "farmlands", "dlc_wizards_tower", "catacombs", "bell", "ussingen" }`); `mutator_geheimnisnacht_2021.lua:103`'s `string.find(live_event, "geheimnisnacht_%d+")` matches `"geheimnisnacht_2026"` and resolves via `_cached_maps_by_event` to that map list. Skulls 2026 reuses `mutator_skulls_2023` since no `mutator_skulls_2026.lua` exists in source.
- `event_tweaker.lua` -- `DLC_BY_PRESET` gained `geheimnisnacht_2026 = "geheimnisnacht_2026"` and `skulls_2026 = "skulls_2026"`. DLC IDs verified in `dlc_settings.lua:597, :606`.
- `event_tweaker_data.lua` -- `PRESET_OPTIONS` + `DLC_BY_PRESET_UI` mirror the new entries so the dropdown surfaces 2026 picks and hides them for hosts who don't own the DLC.
- `event_tweaker_localization.lua` -- `preset_geheimnisnacht_2026` and `preset_skulls_2026` strings (Geheimnisnacht's mentions the 5-map list; Skulls' notes the cosmetic-only nature of the 2026 DLC).

### Build
VMBLauncher.exe build event_tweaker -- verification only.

## 0.4.10-dev (2026-05-25) -- Add "Suppress Fatshark's live event" toggle (preset=off no longer leaks live event through)

### Why
User report 2026-05-25: with `event_preset = "off"` and only `mut_night_mode = true` checked, ran a mission while Fatshark had Skulls 2026 + Geheimnisnacht 2026 live. Result: keep loaded as `inn_level_skulls`, Geheimnisnacht skull pickup spawned on the map, mission lighting flipped to event-mode, tab menu showed the live event + event modifiers active. User mental model: "off should disable the current event." Mod behavior: all three hooks were additive-only -- `get_special_events`, `get_active_events`, `get_level_variation_data` each returned Fatshark's `original` untouched when there was no preset or injection. So whatever Fatshark was serving still reached `append_live_event_mutators` / `mutator_geheimnisnacht_2021`'s ritual-site `string.find(live_event, "geheimnisnacht_%d+")` / `AdventureMechanism.get_starting_level`.

### Changed
- `event_tweaker.lua` -- new file-local `suppress_live_event()` helper reading the new setting. The three hooks now treat `original` as nil/empty when suppress is on:
  - `get_special_events` -- drops Fatshark's entries before merging our injection. Also short-circuits the `DialogueSystem.on_add_extension` read path (`dialogue_system.lua:196-212`) so no live-event ambient dialogue fires.
  - `get_active_events` -- drops Fatshark's strings so `mutator_geheimnisnacht_2021`'s `string.find` finds no `"geheimnisnacht_%d+"` match and the ritual-site engine stays dormant on missions.
  - `get_level_variation_data` -- when suppress is on AND no preset, force `merged.hub_level = "inn_level"` so `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:627`) returns the plain inn instead of Fatshark's seasonal hub.
- `event_tweaker.lua` -- `target_hub_level()` returns `"inn_level"` when suppress is on with no preset, so toggling suppress on while standing in `inn_level_skulls` / `inn_level_halloween` triggers a keep swap back via `set_next_level + promote_next_level_data`.
- `event_tweaker.lua` -- `on_setting_changed` now also calls `apply_now("suppress_live_event changed")` when the toggle flips. Matches preset-change behavior.
- `event_tweaker.lua` -- `/event_probe` now prints the suppress state next to the preset.
- `event_tweaker.lua` -- `[event-inject]` log line now includes `suppress=true|false` so leak-through is verifiable from console_logs.
- `event_tweaker.lua` -- added `_rt_register("suppress_live_event_default_off", ...)` to confirm the default value never accidentally ships as `true`.
- `event_tweaker_data.lua` -- new top-level checkbox `suppress_live_event` directly under the `event_preset` dropdown. `default_value = false`.
- `event_tweaker_localization.lua` -- `suppress_live_event` + `suppress_live_event_tooltip` strings.

### Notes
- **Default off by design.** Existing users see no behavior change. The data file's `default_value = false` is the source of truth; the regression check confirms it.
- **Skulls 2026 / Geheimnisnacht 2026 do not need new mutator catalog entries.** Decompiled source `scripts/settings/dlcs/skulls_2026/` and `dlcs/geheimnisnacht_2026/` ship only `item_master_list_*` + `weapon_skins_*` + portrait frames. The canonical mutators are still `mutator_skulls_2023` and `mutator_geheimnisnacht_2021`, both already in `MUTATOR_CATALOG`. The new `skulls_2026` / `geheimnisnacht_2026` *preset* entries (active_events string + hub_level) are still TODO -- they'd be additive to the dropdown.
- **Why not piggyback on `event_preset = "off"`?** Considered but rejected -- it would silently change behavior for anyone who has preset=off today and *wants* Fatshark's live event to pass through. New opt-in toggle = no breakage.

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.9-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[event_tweaker] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- event_tweaker.lua -- removed the load-time `mod:echo("event_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[event_tweaker] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("event_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.8-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- event_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- event_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build event_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.4.7-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[ewt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging).

### Changed
- `event_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[ewt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.4.7-dev.

### Notes
- Marker prefix `[ewt]` matches the user's mod-list short-ID convention; the legacy `_dbg` prefix `[event_tweaker:dbg]` stays unchanged this pass (existing call sites; renaming is out of scope).

## 0.4.6-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `event_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added new `_RT_CHECKS` regression scaffold (`/event_tweaker_regression_test`) with `dbg_helpers_two_channel` check (event_tweaker had no regression command before).
- `itemV2.cfg` — bumped to v0.4.6-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified.

## 0.4.5-dev (2026-05-25) — Tighten localization strings to vanilla style (3 entries rewritten)

### Why

The Event Preset tooltip and the Geheimnisnacht raw-mutator tooltips were the only verbose strings in this mod — the rest were already terse `[mut_name] one-line description` form. This pass aligns et with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed

- `event_preset_tooltip`: dropped the "(1) the mutator list, (2) the active_events string..." enumeration paragraph; kept the keep-level rename (inn_level_halloween / inn_level_skulls), the host-only gate, and the "Off = hand-pick" hint.
- `mut_geheimnisnacht_2021_tooltip`, `mut_geheimnisnacht_2021_hard_mode_tooltip`: trimmed; kept the canonical-5-maps cross-reference and the side-objective auto-enable behavior.

### Not touched

- Every other `mut_*_tooltip` — already at vanilla style.
- The category headers — already ≤4 words.

### Build

VMBLauncher.exe build event_tweaker — verification only.

## 0.4.4-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). event_tweaker previously had no debug toggle at all — added.

### Changed
- `event_tweaker_data.lua` — appended `enable_debug_logging` checkbox (default `false`) at the bottom of the widgets list, top-level (NOT inside any group).
- `event_tweaker_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `event_tweaker.lua` — added file-local `_dbg(fmt, ...)` helper at top. Output prefix `[event_tweaker:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.4.3-dev.

### Notes
- No existing debug key to rename.

## 0.4.2-dev (2026-05-23) — Diagnostic logging on injection hook

### Why
Surface the per-call injection state of `get_special_events` so unexpected
mutator interactions (e.g. "Horn of Magnus had no pickups — was a special_event
inject accidentally appending an incompatible mutator?") are diagnosable from
the console log without re-running with extra instrumentation.

### Changed
- `event_tweaker.lua:264-270` — added `mod:info("[event-inject] preset=%s injecting %d mutator(s): [%s]", ...)` inside the `BackendInterfaceLiveEventsPlayfab.get_special_events` hook. Fires once per call (mission load + keep transitions), prints the resolved preset name and the comma-joined mutator list. Level chosen per PROJECT_STANDARDS §3.2 — this is a normal-flow event, not a guard.

### Notes
- No behavior change; observation only.

## 0.4.1-dev (2026-05-18) — DLC paywall gate (soft-bypass fix)

- Fixed: the canonical-event preset dropdown and the per-mutator checkbox grid exposed DLC-gated content with no ownership check. Picking Geheimnisnacht / Skulls without owning the corresponding DLC caused the three injection hooks (`BackendInterfaceLiveEventsPlayfab.get_special_events`, `get_active_events`, `BackendManagerPlayFab.get_level_variation_data`) to push the DLC mutator + active_events string + decorated keep level into the lobby anyway. The vanilla level-load path then refused to load the map, surfacing a confusing failure instead of clean "not owned" behavior. Soft bypass — no actual DLC content played, but the mod offered broken choices and the lobby state was wrong.
- Fix (load-bearing — at the injection hooks in `event_tweaker.lua`): new `DLC_BY_MUTATOR` / `DLC_BY_PRESET` maps citing the canonical DLC IDs from `scripts/settings/dlc_settings.lua` — `geheimnisnacht_2021` (line 274), `geheimnisnacht_2025` (line 576), `skulls_2023` (line 287). `active_preset()` now returns nil for un-owned preset DLCs (treating them as "off"), and `selected_individual_mutators()` filters DLC-gated mutators the host doesn't own. `gather_mutators()` re-checks preset.mutators as defense-in-depth in case a future preset bundles a mutator from a different DLC. All gates use `Managers.unlock:is_dlc_unlocked(dlc_id)` with a `dlc_exists` pre-check to avoid the fassert in `unlock_manager.lua:527`. Fails closed if `Managers.unlock` isn't constructed yet — the hooks rerun on every level load so the gate evaluates normally once it's up. Modded mods can unlock vanilla progression but never paid DLC paywalls.
- Fix (UI polish — in `event_tweaker_data.lua`): preset dropdown options and per-mutator checkboxes for un-owned DLCs are now skipped at widget-build time. Fails open if `Managers.unlock` isn't ready (mod-data evaluates very early in VMF init); the hook-side gate is still load-bearing.
- DLC mapping: `geheimnisnacht_2021` mutator + `geheimnisnacht_2021_hard_mode` mutator → `geheimnisnacht_2021` DLC. `skulls_2023` mutator → `skulls_2023` DLC. 2025 preset is gated on the `geheimnisnacht_2025` DLC (its own ritual-site engine keys off the `geheimnisnacht_2025` active_events string).

## 0.4.0-dev (2026-05-16) — Mid-game preset apply + dropdown localization fix

- Fixed: dropdown options (`Off`, `Geheimnisnacht 2021/2025`, `Khorne's Skulls 2023`) and all widget tooltips now localize correctly. `event_tweaker_data.lua` was calling `mod:localize(...)` at file-load time, but VMF's `new_mod` evaluates `mod_data` before `mod_localization`, so every call returned the raw key string ("preset_off", "event_preset_tooltip", "mut_no_ammo_tooltip", etc.) — VMF rendered those literals in the UI. Switched to passing localization keys as plain strings and letting VMF resolve them at render time, matching the working pattern in `enemy_tweaker_data.lua`.
- Added: `mod.on_setting_changed` auto-reloads the level when `event_preset` changes mid-game (host only). Three cases:
  - In the keep, preset's `hub_level` differs from current keep level → `level_transition_handler:set_next_level(new_hub_level) + promote_next_level_data()`. State-machine's update loop detects `needs_level_load()` and triggers a `load_next_level` transition (`state_ingame.lua:1291`), swapping `inn_level` ↔ `inn_level_halloween` ↔ `inn_level_skulls`.
  - In the keep, same `hub_level` (or no preset) → `Managers.state.game_mode:retry_level()`. Reloads the current keep; on the way back in, `DialogueSystem` re-reads the hooked `get_special_events`.
  - In a mission → `retry_level()`. Re-runs `GameModeBase.append_live_event_mutators` against the new mutator list, rebuilding `_mutator_handler` and broadcasting via the vanilla mutator-activate RPC to all clients.
- Added: `event_apply` console command — manual trigger for the same reload flow. Use after toggling individual mutator checkboxes (those don't auto-reload — a quick pass through 5 checkboxes would otherwise trigger 5 keep reloads).
- Auto-reload is preset-change-only by design. Individual mutator toggles are dormant until `event_apply` or the next natural level transition.

## 0.3.0-dev (2026-05-07) — Keep decoration via `hub_level` swap

- Added: third hook on `BackendManagerPlayFab.get_level_variation_data`. When a preset is active, merges `hub_level = "inn_level_halloween"` (Geheimnisnacht 2021/2025) or `"inn_level_skulls"` (Skulls 2023) into the returned table. `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:625`) reads this and loads the pre-decorated keep level instead of the default `inn_level`.
- Why mutators alone can't decorate the keep: `GameModeBase.append_live_event_mutators` skips hub levels (`game_mode_base.lua:260-262`), so the mutator's `server_start_function` never runs there. Vanilla VT2 sidesteps this by shipping entire pre-decorated keep level files — `inn_level_halloween`, `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill` — defined in `scripts/settings/level_settings.lua:152-196`. Decorations are baked geometry, not runtime spawns.
- Updated: `event_preset` tooltip describes all three things the preset drives (mutators, active_events string, keep level) plus the keep-restart caveat.
- Caveat: changing the preset while standing in the keep does NOT re-trigger keep load. Restart the game OR start a mission and return to swap variants.

## 0.2.1-dev (2026-05-07) — Fix DialogueSystem startup crash

- Fixed: game crashed at every level load (including the keep) with `dialogue_system.lua:180: table index is nil`. Root cause: `DialogueSystem.on_add_extension` (`dialogue_system.lua:196-212`) iterates `BackendInterfaceLiveEventsPlayfab:get_special_events()` and reads `event_data.name` on every entry, then uses it as a key in `self._global_context`. Our injected entry had only `weekly_event` and `mutators` — no `name`. `self._global_context[nil] = true` blew up.
- Fix: every injected special-event entry now includes `name = <preset_pick or "event_tweaker_custom">`. The preset key (e.g. `"geheimnisnacht_2021"`) is used when a preset is active; otherwise a synthetic identifier so per-mutator selections without a preset still pass.
- Why this hit at startup, not on missions: `GameModeBase.append_live_event_mutators` skips hub levels, but `DialogueSystem` does not — it reads `special_events` on every level load including the keep.

## 0.2.0-dev (2026-05-06) — Rename, scope-expand to full mutator catalog

- Renamed: `seasonal_tweaker` → `event_tweaker`. Workshop title changed from "Seasonal Tweaker" to "Tweaker: Events" to match the sibling mod naming convention. Internal mod ID, folder, .mod file, .package file, lua filenames, and resource_packages directory all renamed.
- Scope: was 3 event presets only. Now ships a checkbox-per-mutator catalog across 7 categories — Difficulty Modifiers (9), Special / Elite Spawns (12), Hordes & Waves (6), Atmosphere & Hazards (6), Objective Modifiers (3), Winds of Magic (8), Live-Event Mutators raw (3). Plus the existing Event Preset dropdown for canonical events that need the active_events-string magic. Total ~50 mutators selectable, all confirmed registered year-round in `NetworkLookup.mutator_templates` via `DLCUtils.append("mutators", ...)`.
- `gather_mutators()` accumulates preset.mutators ∪ checkbox-selected mutators (deduped) and injects them into a single `{name, weekly_event = "append", mutators}` entry returned from the hooked `get_special_events`.
- Added commands: `event_probe` (dump live-event state from hooked backend interface + show what would be injected), `event_active` (list mutators the engine actually activated), `event_clear` (uncheck every individual mutator without touching the preset).
- Localization: every mutator gets `mut_<id>` and `mut_<id>_tooltip`. Tooltips lead with `[<id>]` so the literal mutator name being injected is verifiable from the UI.
- Catalog list duplicated between `event_tweaker.lua` and `event_tweaker_data.lua` — VMF's mod-script vs mod-data load order isn't documented, and no sibling tweaker mod shares state across files. Both files carry comments flagging the sync requirement when mutators are added.

## 0.1.0-dev (2026-05-06) — Scaffolded

- Scaffolded via VMB as `seasonal_tweaker` (renamed same day in 0.2.0). Initial scope: three event presets (Geheimnisnacht 2021, Geheimnisnacht 2025, Khorne's Skulls 2023) with two hooks on `BackendInterfaceLiveEventsPlayfab` — `get_special_events` and `get_active_events`.
- Hook target chosen because `BackendInterfaceLiveEventsPlayfab` has no derived classes (string-form `mod:hook` patches the prototype that all instances see through `__index`), and it's the single chokepoint that `GameModeBase.append_live_event_mutators` reads through. Activates the chosen event's mutators via the vanilla mutator handler — `rpc_activate_mutator_client` then broadcasts to all clients, so vanilla clients work without any modded sync.
