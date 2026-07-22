# Tweaker: Events — Development Notes

Internal id: `event_tweaker`. Workshop id: `3721290755`. Visibility: `public` per `itemV2.cfg`, so every upload/ship needs `-AllowPublic`. Visibility is user-dictated — do NOT change it without explicit user direction (`feedback_workshop_metadata_user_dictates`).

## What this mod does

Lets the host pick any combination of vanilla / DLC mutators for the lobby — including dormant live-event mutators (Geheimnisnacht ritual sites, Khorne skull pickups) — without waiting for Fatshark to push the event live. Vanilla clients work; only the host needs the mod. Mutator activation broadcasts to clients via `rpc_activate_mutator_client`.

Two flavors of selection sit on top of each other:

1. **Event Preset** dropdown (Off / Geheimnisnacht 2021 / 2025 / 2026 / Skulls 2023 / 2026). Drives three things at once: the mutator list, the `active_events` string list (so `mutator_geheimnisnacht_2021`'s `server_start_function` finds its ritual-site map list), and the keep level (so the keep gets pre-baked Geheimnisnacht/Skulls decorations).
2. **Per-category checkboxes** for any individual mutator, organized into 7 groups. Stacks additively on top of whatever the preset already pulls in; deduped before injection.

Plus one orthogonal switch:

3. **`suppress_live_event`** (v0.4.10-dev+, default off). When on, the three hooks below drop Fatshark's `original` response *before* merging our own. Lets the host neutralize whatever event Fatshark is currently serving (Skulls 2026 keep + Geheimnisnacht 2026 ritual sites + event lighting + tab-menu modifier list, etc.) without waiting for the live event to roll over. The preset and per-mutator checkboxes still stack on top.

And one bounded mission-menu feature:

4. **Dormant Event Missions** (issues 626 and 802, opt-in). Shows only `dlc_dwarf_fest`
   and `dlc_celebrate_crawl` in Own Game. It temporarily substitutes a shallow
   presentation copy of the stock `celebrate` area while vanilla builds the area
   widgets, then replaces only the
   selected event-area menu instance's `act_celebrate` level list from a closed
   two-entry allowlist. Normal campaign/DLC menu instances remain identical to
   vanilla; the event area is not injected into their mission lists. The copy
   sorts after every visible vanilla area and uses the resident 168x168 Feast
   level image. This is load-bearing: stock `celebrate` has
   `sort_order=0` and Bogenhafen presentation fields, so simply unhiding it takes
   the controller's first/special Campaign widget and labels the event route like
   Bogenhafen. The stock descriptor is restored by identity after every build,
   including the error path; the visible title/description are changed only on
   the two view instances and read **Events** through Event Tweaker localization.
   The visibility gate requires only the tables the menus read (AreaSettings /
   ActSettings / LevelSettings). A load-time idempotent fallback appends a level
   vanilla's boot pass genuinely missed to the local `UnlockableLevels` /
   `GameActs` / `MapPresentationActs` tables (vanilla shape,
   `level_unlock_settings.lua:100-135`); on a healthy install it appends
   nothing. It does not add either level to Quick Play and NEVER touches
   `NetworkLookup` (wire tables are boot-built from `LevelSettings`,
   `network_lookup.lua:1239-1259`; modded keys on vanilla RPCs CTD non-mod
   peers, issue 278 / issue 371).

## "Other Mutators" — dynamic discovery (ported from Deed Mutators Selector)

`v0.4.14-dev` absorbed the one worthwhile feature of **Deed Mutators Selector** (Workshop `3579882542`): iterate the live `MutatorTemplates` global and surface every mutator the engine flags player-facing (`display_name`+`description`), instead of a hand-curated list. The "Other Mutators" group auto-includes the package-free Chaos Wastes / Deus mutators not in a curated category. Three exclusions keep it adventure-safe (`_is_adventure_safe_mutator(name, tmpl)`): `hide_from_player_ui` (Fatshark-hidden Deus pacing knobs), a non-empty `packages` field (those go to Cursed Adventure), and `_CURSE_BROKEN_IN_ADVENTURE` (weave/deus-only crashers). Labels are pulled from the game's own `Localize` (no fabrication), registered dynamically in the loc file. Wired across all three files; `Curses.BROKEN_IN_ADVENTURE` (`event_tweaker_curses.lua`) is the shared blacklist.

## Cursed Adventure — CW/Be'lakor curses on standard maps (`v0.4.14-dev`)

Lets the host attempt package-bearing Chaos Wastes / Be'lakor **curses** (`MANAGED_CURSES`) on a plain adventure mission, with themed lighting. Normally those crash in adventure (`[memory: reference_vt2_mutator_packages_deus_only]`) because their unit/decal resource package is loaded only by `DeusRunState.set_event_mutators` (`deus_run_state.lua:438-453`). Package residency is a proven blocker, but it is **not proven to be the only blocker**. The current source contains no direct Deus-run-controller dependency in nine managed templates, while Egg of Tzeentch and Greed Pinata have additional objective/economy contracts. Source compatibility is only a candidate classification; each curse remains runtime-unproven in Adventure until its own observable effect and transition/peer paths pass.

| Piece | How |
| :--- | :--- |
| **Selection / preview** | `selected_curse_candidates()` is the read-only checkbox/DLC/registration collector. The injection-only `selected_curse_mutators()` consumes it, owns the issue-430 session lock, and feeds `gather_mutators()` → the existing `get_special_events` hook → the lobby mutator handler → `rpc_activate_mutator_client`. `preview_selection()` consumes the read-only collector and mirrors the parity decision without changing joinability. |
| **Package preload (normal join + host)** | Hook `MutatorHandler._activate_mutator` — the chokepoint hit on the HOST (via `activate_mutators`) AND every CLIENT (via `rpc_activate_mutator_client` → `_activate_mutator`, `mutator_handler.lua:782`). SYNC-load (`Managers.package:load(pkg, "event_tweaker_curse_package", nil, false)`) each `packages` entry *before* `func` runs `start_function`. Idempotent (`has_loaded` + `_loaded_curse_packages` set). |
| **Package preload (transition/normal join)** | Hook `MutatorHandler.init` (`hook_safe`) so an Event-Tweaker peer preloads initialized curse packages before activation. This is defense in depth, not permission to hot-join: a peer without the mod has no hook, and vanilla game-object sync begins before PlayerManager exposes that peer to the ordinary parity roster. |
| **Unload** | `StateIngame.on_exit` (`state_ingame.lua:1847`) — ref-balanced `unload` per peer. |
| **Lighting** | Hook `CameraManager.shading_callback`; multiply per-god ShadingEnvironment vars (`_CURSE_SKY_PROFILES`, copied from `chaos_wastes_tweaker.lua:3247`). `_active_curse_god` cached on activate/deactivate. Reverts for free (engine re-seeds the shading_env every frame). `cursed_lighting` toggle (default on). |
| **Mechanism gate** | All four hooks no-op unless `Managers.mechanism:current_mechanism_name() == "adventure"`, so a real CW run (Deus loads the package, ct tints) is untouched. |

**Multiplayer (issue 430 wire-safety floor, `v0.4.29-dev`, hot-join closure `v0.4.35-dev`):** unlike the host-only rest of the mod, the curse group needs **every current player** to run event_tweaker because each client must load the package used by replicated curse units. A non-ET peer hard-CTDs when the engine instantiates such a unit from an unloaded package. `selected_curse_mutators()` therefore drops all curses unless the shared peer-parity beacon positively confirms every represented human peer. It also rejects an already-pending server peer not yet represented in `PlayerManager`.

The roster gate alone cannot protect hot join. Vanilla checks `GameModeBase.is_joinable` in `PeerStates.Connecting` (`peer_states.lua:114-120`), adds an admitted peer to `GameSession` at `:393` (beginning game-object replication), and only creates the remote `PlayerManager` entry at `:450`. Event Tweaker therefore locks `GameModeBase.is_joinable` while any managed curse is selected or active. The lock is established before injection and again before the mutator start function, so no new peer can reach game-object replication during a cursed session. It blocks ET and non-ET hot joins alike; uncheck the package-bearing curses to reopen the lobby. This is deliberate: source inspection found no general synchronous teardown contract across the managed curse templates, so warning or deactivating at the late roster boundary is not proof of safety. Checks: `issue430_peer_parity_beacon_installed` / `issue430_curse_floor_failsafe` / `issue430_curse_floor_classify` / `issue430_hotjoin_session_contract`; offline `test_event_curse_join_policy`.

**Managed-curse source census (2026-07-22).** “Structural candidate” means only that the decompiled template has no direct `get_deus_run_controller`/Deus-run-state read. It does not mean functional, crash-free, or verified in Adventure.

| Curse(s) | Decompiled execution contract | Source classification / required evidence |
| :--- | :--- | :--- |
| Blood Storm | Package-owned decals plus queued vortex breed; standard conflict, nav, player, buff, and difficulty managers (`mutator_curse_blood_storm_v2.lua`). | Structural candidate. Prove storm spawn, bleed, cleanup, mission transition, and all-peer presentation. |
| Skulls of Fury | Package-owned network skull spawned from AI-killed callback; seeded through the mechanism's generic level seed (`mutator_curse_skulls_of_fury.lua`). | Structural candidate. Prove kill-triggered skull spawn/explosion and peer replication. |
| Khorne Champions; Corrupted Flesh | Shared marked-enemy base uses difficulty data, AI spawn/kill callbacks, buff system, and network unit IDs (`mutator_base_curse_marked_enemies.lua`). | Structural candidates. Prove marks, effects, removal, and every supported difficulty. |
| Rotten Miasma | Requires main-path/nav data and network-spawns a `deus_relic_01` level-event pickup plus safe-area objective unit (`mutator_curse_rotten_miasma.lua`). | Structural candidate with a special pickup/inventory contract. Prove carrier acquisition/drop/respawn, safe area, and cleanup. |
| Grey Wings | Starts the named generic terror event `grey_wings_spawns` from pacing/main-path state (`mutator_curse_grey_wings.lua`; event is declared in `deus_generic_terror_events.lua`). | Structural candidate. Prove event registration is live in Adventure and the event actually spawns. |
| Be'lakor Totems | Queues `Breeds.shadow_totem`, reads its `deus_belakor_totem_system` extension, and uses main-path/nav/bot traversal (`mutator_curse_belakor_totems.lua`). | Structural candidate. Prove breed/extension lifecycle, relocation, destroy, and peer replication. |
| Shadow Daggers | Network-spawns package unit `blk_curse_shadow_dagger_spawner_01` with `shadow_dagger_spawner` extension (`mutator_curse_shadow_daggers.lua`). | Structural candidate. Prove spawner/attack behavior, cleanup, and peer replication. |
| Shadow Homing Skulls | Uses `BelakorBalancing`, visible-position queries, and pickup-system spawn of `deus_04` (`mutator_curse_shadow_homing_skulls.lua`). | Structural candidate with a special-pickup contract. Prove skull acquisition/targeting/damage and peer replication. |
| Egg of Tzeentch | Requests mission `egg_of_tzeentch`, reads `Missions.egg_of_tzeentch`, disables boss settings, registers `spawned_timed_breed`, and network-spawns an objective/timed-spawner unit (`mutator_curse_egg_of_tzeentch.lua`). | Extra mission/objective contract; runtime-blocked until mission registration, peaks, egg destruction/hatch, boss restoration, and transition cleanup are observed. |
| Greed Pinata | Marked-enemy base applies a death-spawn buff, queues `Breeds.chaos_greed_pinata`, and sets all ordinary/deus pickup multipliers to zero (`mutator_curse_greed_pinata.lua`; `morris_buff_settings.lua`). | Extra economy/pickup contract; runtime-blocked until pinata spawn/drop behavior and ordinary pickup suppression/recovery are observed. |

**Excluded crashers** (`_CURSE_BROKEN_IN_ADVENTURE`, never surfaced): `curse_bolt_of_change` (Deus-mechanism-only `get_deus_run_controller`), `curse_belakors_shadows` (weave mutator, nil-arithmetic crash — package-free so the package filter can't catch it), `curse_empathy` (server-side `data.hero_side` nil-index). Egg of Tzeentch and Greed Pinata remain explicitly experimental and must not be described as crash-free or working without runtime evidence.

**Catalog lives in `event_tweaker_curses.lua`, a shared `require`'d module** (`MANAGED_CURSES` / `BROKEN_IN_ADVENTURE` / `CURSE_TO_GOD`), NOT a `mod._field` set in the script. VMF loads files `localization → data → script` (script LAST), so a script-set field is nil when `_data.lua` / `_localization.lua` evaluate. A `require`'d module is evaluated once (by the first requiring file) and cached — all three files see it. This mirrors `enemy_tweaker_breeds.lua`. **Burned once** (v0.4.14-dev first cut): the entire Cursed Adventure UI group silently never built. Rule: anything `_data.lua` / `_localization.lua` need from the script must go through a shared `require`'d module, never a script-assigned `mod._field`.

## File map (v0.4.26-dev module split)

`event_tweaker.lua` is a ~65-line entry point: MOD_VERSION, load banner/echo, the
`mod._evt` shared namespace, and an ordered `mod:dofile` manifest. Every module is
dofile'd exactly once from that manifest (VMF `mod:dofile` is NOT a singleton — never
dofile a module from another module) and publishes its exports into `mod._evt`.
Module prefix is `_evt_` because `_et_` already belongs to enemy_tweaker's modules.
Manifest order is load-bearing: dependencies flow strictly downward (each module
localizes earlier modules' `mod._evt` exports at its top), and regression checks
print in registration order, so reordering the manifest reorders
`/event_tweaker_regression_test` output.

### Module contracts

One block per file: what it owns, its public surface (everything other files may
touch), and its manifest position. Anything not listed as public surface is a
file-local — do not reach into it from another file; export it via `mod._evt` in
the owning module instead.

**`event_tweaker.lua` — entry point (loads everything else).**
Owns MOD_VERSION (the launcher parses it from THIS file — never move it), the
banner/`[event_tweaker:LOAD]`/chat-echo lines, `mod._evt` creation, the dofile
manifest, and the mem-probe bracket around the whole load.
Public surface: `mod._evt.version`.

**`event_tweaker_catalog.lua` — shared require'd DATA (no manifest position; cached by `require`).**
Single source of truth for `CATEGORIES` (curated mutator catalog), `EVENT_PRESETS`,
`DLC_BY_MUTATOR`, `DLC_BY_PRESET`. require'd by `_evt_dlc` / `_evt_selection` /
`_evt_diagnostics` AND `event_tweaker_data.lua` — it must stay pure data (no `mod`
access) because the data file evaluates before the script.

**`event_tweaker_curses.lua` — shared require'd DATA (same rules as the catalog).**
Cursed Adventure curse catalog: `MANAGED_CURSES`, `BROKEN_IN_ADVENTURE`,
`CURSE_TO_GOD`. require'd by `_evt_selection` / `_evt_diagnostics` /
`_evt_cursed_adventure` AND `_data.lua` / `_localization.lua`.

**`event_tweaker_missions.lua` — shared require'd LOGIC (same early-load rules).**
Issue 626's closed mission allowlist, engine-contract validator, and pure
view-local `act_celebrate` filter. require'd by `_evt_missions.lua` and
`event_tweaker_data.lua`, so it has no `get_mod`, manager/global reads, or writes.

**`_evt_log.lua` — manifest position 1.**
Two-channel debug helpers (PROJECT_STANDARDS § 3.6) + the settings fingerprint the
entry's LOAD line prints. Public surface: `mod._evt.dbg`, `mod._evt.dbg_alert`,
`mod._evt.settings_fingerprint`.

**`_evt_regression.lua` — manifest position 2.**
The `/event_tweaker_regression_test` harness and the generic checks
(`dbg_helpers_two_channel`, `localization_format_safe`,
`suppress_live_event_default_off`). Issue-specific checks live with the code they
check, in later modules. Public surface: `mod._evt.rt_register(name, fn)`.

**`_evt_dlc.lua` — manifest position 3.**
Injection-side DLC ownership gate; fails CLOSED when `Managers.unlock` isn't up.
(The data file's `ui_owns_dlc` twin fails OPEN — deliberate divergence, documented
at both sites.) Public surface: `mod._evt.owns_dlc`, `mod._evt.mutator_allowed`,
`mod._evt.preset_allowed`.

**`_evt_guard413_weave.lua` — manifest position 4.**
Issue 413 unsafe-stock-path data: the weave-only mutator blocklist + the
fail-closed `_weave_wind_active()` probe. Shadow remains classified here even
though the later adapter can admit it after capability proof. Registers check
`issue413_weave_only_mutators_gated`.

**`_evt_shadow_adventure.lua` — after peer parity, before selection.**
Capability-gated Adventure implementation of Shadow. It keeps the native
six-metre reveal / 90% damage-reduction mechanics using the resident fade system
and vanilla buff identity, but never spawns the Weave-only gargoyle light or
shadow VFX. A dedicated parity channel rejects older Event Tweaker versions as
well as modless peers; the shared pre-session fence closes hot joins. Public
surface: `shadow_adventure_plan`, `shadow_adventure_wire_safe`,
`shadow_adventure_adapter_ready`. Pure policy:
`event_tweaker_shadow_policy.lua`. Runtime check:
`issue413_shadow_adventure_adapter`.
Public surface: `mod._evt.WEAVE_ONLY_MUTATORS`, `mod._evt.weave_wind_active`.

**`_evt_guard455_boss_events.lua` — manifest position 5.**
Issue 455 guard: wraps boss-event mutators' dispatch fields so boss_events-less
levels no-op instead of a host fatal. Registers check
`issue455_boss_event_mutators_guarded`. Public surface (mod fields, resolved at
call time by `add()`): `mod._et455_guard_boss_event_mutator(name)`,
`mod._et455_boss_events_present(cbs)`.

**`_evt_guard430_curse_parity.lua` — manifest position 6.**
Issue 430 Cursed Adventure curse wire-safety floor. Builds + installs the shared
peer-parity beacon (`_lib_peer_parity`, issue 371 framework; channel
`et_peer_parity_present`, schema 1) and registers one gated feature
(`et_cursed_adventure_curses`) whose label drives the beacon's peer-naming chat
notice. It owns the singleton `GameModeBase.is_joinable` hook: selected/active
managed curses return false before vanilla can admit a peer to `GameSession`.
The beacon still owns `mod.update` via the lib's `install()`; nothing else in the
mod may set `mod.update`. Registers checks `issue430_peer_parity_beacon_installed`,
`issue430_curse_floor_failsafe`, `issue430_curse_floor_classify`, and
`issue430_hotjoin_session_contract`. Public surface: `mod._evt.curse_wire_safe`,
the curse-session request/active setters + lock accessor, and
`mod._et_peer_parity` (the beacon instance, for the regression suite).

**`_evt_selection.lua` — manifest position 7.**
Selection core: `active_preset`, dynamic discovery (Deed Mutators Selector port),
curse/checkbox readers, and `gather_mutators()` whose inner `add()` is the SINGLE
injection chokepoint (issues 413 + 455 are enforced there; every new injection
route must funnel through it). `selected_curse_mutators()` applies the issue 430
floor (drops all curses when `curse_wire_safe()` is false) before the curses reach
`add()` — it removes from the route rather than adding one, so no guard is
bypassed. Registers check `dynamic_mutator_discovery`.
Public surface: `mod._evt.active_preset`, `mod._evt.displayable_registered_mutators`,
`mod._evt.gather_mutators`, `mod._evt.preview_selection`,
`mod._evt.gather_active_events`, `mod._evt.suppress_live_event`,
`mod._evt.merge_lists`. `preview_selection()` (issue 532) is the SIDE-EFFECT-FREE
twin of `gather_mutators()`: it returns the same active mutator list (weave-only
names dropped identically) plus the issue-430 parity-dropped curse names, but WITHOUT
`gather_mutators`'s injection-time side effects (`notify_weave_drop` chat line,
`_et455` template wrap) so the Tab preview can call it on every panel open. It is the
ONLY sanctioned preview data source — the panel must never call `gather_mutators`.

**`_evt_preview.lua` — manifest position 8 (issue 532 Tab-hold mutator preview).**
Two `hook_safe` on DISTINCT `IngamePlayerListUI` methods (`_setup_deed_reward_data`
build point, `_draw` guarded own-pass) that render an "Active Mutators (N)" block on
the player-list panel's right side, keep-only, gated on `preview_active_mutators`.
Sibling of ct_dev's Starting-Boons preview (`CT_BOON_PREVIEW_461_MARKER`); mirrors its
crash-proof shape (own `begin_pass`/`end_pass`, per-`draw_widget` pcall, icon + name as
separate widgets). Consumes `mod._evt.preview_selection`. No exports; adds the helpers
`mod._evt_mutator_display` / `mod._evt_mutator_icon` / `mod._evt_ct_boon_block_present`
and the `/event_preview_mutators` command. Registers `issue532_mutator_preview_wired`.
Placement coordinates with ct: both anchor to the `reward_divider` node on
`banner_right`; when ct's boon block is active we stack ABOVE it (positive Y offset,
capped rows), else we take ct's reward-slot position. Floor-dropped curses render
greyed "(skipped: a peer lacks the mod)"; on a client the header carries a
"host decides" caveat (et never syncs the host's picks). ct files are read-only
reference; no ct file is touched.

**`_evt_missions.lua` — manifest position 9 (issues 626/802 dormant event missions).**
Four menu hooks cover desktop/controller area and mission-selection views. The
area wrapper temporarily clears only `AreaSettings.celebrate.exclude_from_area_selection`
and restores it even when vanilla raises. The mission wrapper first reads the
selected area from the source-verified desktop/console parent, then replaces
only the celebrate view instance's `_levels_by_act.act_celebrate` list from the
two-entry allowlist. Every non-celebrate view retains its entire map by identity;
unrelated act tables in the celebrate view also retain identity. The visibility gate validates only the
menu-read tables (area/act/level settings, NOT NetworkLookup - the old
NetworkLookup preconditions were the issue 626 "toggle on, nothing shows"
defect). At mod load it unconditionally runs the idempotent
`ensure_campaign_registration` fallback for `UnlockableLevels` / `GameActs` /
`MapPresentationActs`, logs `[event-missions:626]`, exposes
`/event_mission_probe` (contract= plus campaign=), and registers
`issue626_event_mission_allowlist_contract` plus
`issue802_event_mission_area_scope`. VMF owns hook disable/re-enable, and
each view rebuilds from vanilla state on re-entry, so there is no persistent
mission state or lifecycle callback to restore.

**`_evt_backend_hooks.lua` — manifest position 10.**
The three live-event backend hooks (see Architecture below). No exports; consumes
the selection surface.

**`_evt_guard386_pacing.lua` — manifest position 11.**
Issue 386 scalar-pacing sanitizer: `hook_safe` on
`MutatorHandler.conflict_director_updated_settings`. Registers check
`issue386_sanitize_pacing_scalar_to_table`. Public surface:
`mod._et386_sanitize_pacing_scalars(pacing, difficulty)`.

**`_evt_diagnostics.lua` — manifest position 12.**
Read-only surfaces: `/event_probe`, `/event_active`, `/event_clear`, and the issue
393 diagnostics-armed first-`Pacing.update` settled snapshot. No exports.

**`_evt_apply.lua` — manifest position 13.**
Mid-game preset application (level reload plumbing), `/event_apply`, and
`mod.on_setting_changed` — VMF allows exactly ONE assignment mod-wide and it lives
here; never assign it in another file. No `mod._evt` exports.

**`_evt_cursed_adventure.lua` — manifest position 14 (last).**
Curse package preload hooks (`MutatorHandler._activate_mutator`/`_deactivate_mutator`/
`init`, `StateIngame.on_exit`) + the per-frame `CameraManager.shading_callback` sky
tint. All runtime state is file-local; the per-frame hook must never read
`mod._evt` or any cross-file indirection. No exports.

### Where new code goes (read BEFORE adding anything)

The monolith was split on purpose — new code goes in the owning module, not the
entry file. Every path below ends with: bump MOD_VERSION in `event_tweaker.lua`,
CHANGELOG entry in the same response, doc updates (this file + REGRESSION_CHECKLIST.md
if applicable) in the same commit.

- **New mutator or preset** → `event_tweaker_catalog.lua` + loc keys; see the two
  "Adding a new ..." sections below. Never re-introduce a second copy of the
  catalog in another file.
- **New issue guard (crash class on injected mutators)** → its own
  `_evt_guardNNN_<name>.lua` file, manifest-ordered BEFORE `_evt_selection` if the
  guard is applied at injection time. Wire it from `add()` in `_evt_selection.lua`
  (the chokepoint), register its `rt_register` check IN the guard file, and add a
  REGRESSION_CHECKLIST.md entry + slug. Guards are load-bearing: never remove one,
  never gate one behind a menu toggle.
- **New diagnostic command or probe** → `_evt_diagnostics.lua`. Engine `printf`
  (users run with mod logs OFF), `pcall(printf, ...)` inside engine dispatch paths.
  Before hooking anything, grep ALL `_evt_*` files for an existing hook on that
  `(Class, method)` — VMF silently drops the second (NON-NEGOTIABLE 8).
- **New cross-module value** → export it onto `mod._evt` in the module that owns
  it; consumers localize it at their top (`local x = ET.x`). That only works if the
  owner is earlier in the manifest — if you must add a manifest entry, update the
  order comment in `event_tweaker.lua` and remember regression-check print order
  follows it. Modules never `mod:dofile` each other.
- **Data needed by `_data.lua` / `_localization.lua`** → a require'd module
  (catalog/curses pattern). Script-set `mod._fields` are nil when those files
  evaluate (VMF loads localization → data → script) — this burned v0.4.14-dev.
- **Per-frame work** → keep every read a file-local upvalue (see
  `_evt_cursed_adventure.lua`); zero table allocations per frame.

## Architecture

The three live-event hooks in `_evt_backend_hooks.lua` remain the single
chokepoint for mutator injection. Issue 626's four menu hooks form a separate,
presentation-only path and never feed the live-event backend.

| Hook | Purpose | Why this entry point | suppress_live_event behavior |
| :--- | :--- | :--- | :--- |
| `BackendInterfaceLiveEventsPlayfab:get_special_events` | Inject `{name, weekly_event = "append", mutators}` so `GameModeBase.append_live_event_mutators` (`game_mode_base.lua:264`) picks up our mutators on every mission load. | Single class, no derived classes — string-form `mod:hook` patches the prototype that all instances see via `__index`. `GameModeBase.append_live_event_mutators` is the canonical mutator-activation path; mutator IDs flow from there into `mutator_handler.lua:85` `initialize_mutators` and out via `rpc_activate_mutator_client` to clients. | Drops Fatshark's entries before merge → also short-circuits the `DialogueSystem.on_add_extension` read at `dialogue_system.lua:196-212` so live-event ambient dialogue stops. |
| `BackendInterfaceLiveEventsPlayfab:get_active_events` | Inject the preset's event-name string (e.g. `"geheimnisnacht_2021"`). | `mutator_geheimnisnacht_2021.lua:58-86` calls `live_events_interface:get_active_events()` and does `string.find(live_event, "geheimnisnacht_%d+")` on each entry to decide which 5 maps spawn ritual sites (year-specific lists in `geheimnisnacht_utils.lua:5-41`). Without this hook, the mutator activates but spawns nothing. Skulls does NOT inspect this list — its mutator's `server_start_function` is self-contained. | Drops Fatshark's strings → `string.find` finds no `"geheimnisnacht_%d+"` match → ritual-site engine stays dormant on missions. |
| `BackendManagerPlayFab:get_level_variation_data` | Merge `hub_level = "inn_level_halloween"` / `"inn_level_skulls"` into the returned table. | `AdventureMechanism.get_starting_level` (`adventure_mechanism.lua:625`) reads `Managers.backend:get_level_variation_data().hub_level` and loads that level. Vanilla seasonal events ship pre-decorated keep level files — `inn_level_halloween`, `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill` — defined in `scripts/settings/level_settings.lua:152-196`. Decorations are baked geometry, not runtime spawns. Mutators can't do this because `GameModeBase` skips hubs. | When suppress is on AND no preset hub_level, forces `merged.hub_level = "inn_level"` (matches `adventure_mechanism.lua:7 HUB_LEVEL_NAME`) so the keep reverts to plain inn. |

### Dormant event mission boundary (issue 626)

Current decompile `c5e4968b1fbb00c49884e56d640ef990a9c04dd0` already owns
both missions end to end. `DLCSettings.celebrate` and `.dwarf_fest` declare their
boot packages/additional settings (`scripts/settings/dlc_settings.lua:58-68,
533-540`), and `Boot:setup` loads every DLC `package_name` then requires those
settings (`scripts/boot.lua:358-369,387`). The level definitions name
`act_celebrate`, are unlockable/not-quickplayable, and own the actual level package
lists (`levels/honduras_dlcs/celebrate/level_settings_celebrate.lua:3-26`;
`levels/honduras_dlcs/dwarf_fest/level_settings_dwarf_fest.lua:3-25`).

Vanilla's level-unlock pass derives `GameActs`, `UnlockableLevels`,
`UnlockableLevelsByGameMode`, and `MapPresentationActs` from valid level settings
(`scripts/settings/level_unlock_settings.lua:101-129`), and network boot derives
level/mission/act/unlockable lookups (`scripts/network_lookup/network_lookup.lua:
1239-1259`). The missing boundary is presentation: both event areas are hidden;
the stock `celebrate` area already points at `act_celebrate`, but it is not a
usable Events tile. Its `sort_order=0` precedes Helmgart's `sort_order=1` and its
display name, description, icon, video, and sound are copied from Bogenhafen
(`levels/honduras_dlcs/celebrate/level_unlock_settings_celebrate.lua:3-16`).
The controller assigns the first sorted area to its special Campaign widget
(`start_game_window_area_selection_console_v2.lua:100-137`), which is why the
previous unhide-only adapter replaced Campaign with the event route. Event
Tweaker now substitutes a shallow `celebrate` presentation only during the
vanilla build, sorts it after all visible areas, and uses the resident
`level_image_dlc_dwarf_fest` atlas entry
(`scripts/ui/atlas_settings/gui_level_images_atlas.lua:914-925`).
It then restores the stock table by identity and changes the Event title and
description only in the selected view's widget content. Desktop/controller area
views skip `exclude_from_area_selection` areas (`start_game_window_area_selection.lua:
91-95`; console V2 `:100-105`), and mission views build their instance-local
`_levels_by_act` from `UnlockableLevels` (`start_game_window_mission_selection.lua:
108-129`; console `:98-125`). Desktop reads the current area through
`self.parent:get_selected_area_name()` (`:46`), while console uses
`self._parent:get_selected_area_name()` (`:45`); Event Tweaker therefore scopes
its celebrate replacement to that exact selected area. Once a selected level starts,
`LevelTransitionHandler._load_level_packages` loads its stock `LevelSettings.packages`
and unloads them by the same level-key reference (`level_transition_handler.lua:
518-572`). Event Tweaker therefore changes only the temporary/view-local menu
boundary and leaves package loading and network ownership to vanilla. The one
campaign-side concession (v0.4.36-dev): if vanilla's boot registration pass
genuinely missed an allowlisted level, the load-time idempotent fallback appends
it to `UnlockableLevels` / `GameActs.act_celebrate` / `MapPresentationActs` in
the exact vanilla shape - local tables only, appended after the boot-time
`NetworkLookup` builds, so the wire tables are provably untouched.

If the top-level presentation still fails in-game, use these ordered empirical
fallbacks rather than widening global mutation:

1. Compare the `[event-missions:626] area observed` order with
   `campaign_index=1` and exactly one later `event_index`. If the indices are
   wrong, replace the transient sort calculation with a post-build view-local
   widget reorder; do not modify `AreaSettings.helmgart`.
2. If indices are correct but the wrong title/icon is visible, dump the selected
   widget's `area_name`, icon, and view-local title after
   `_set_area_presentation_info`. Adapt that view-local consumer only; do not
   add a global `Localize` hook or persistent area descriptor.
3. If the Events tile is correct but its mission list is not, compare the parent
   selected-area key and `_levels_by_act` identity before/after
   `_setup_level_acts`. Keep the exact `celebrate` gate and move the filter to
   the earlier view-entry seam only if runtime proves the current post-build
   assignment is overwritten later.

### Feast comparison and clean-room provenance

Behavioral reference: Workshop item `3557074106`, “The Feast of Grimnir” by
ChadMasodin; public source repository `ChadMasodin/Vermintide-2-Mods`, inspected at
commit `b30f9a3a7db98c10719ef612b86c37e544258bb2` (v1.0). The repository has no
declared license (`LICENSE`/`COPYING` absent and GitHub license metadata null), so
it was used only to identify behavior. No Lua, video/material asset, identifiers
invented by that mod, or implementation structure was copied.

The reference permanently edits `AreaSettings`/`ActSettings`/`LevelSettings`,
adds legacy fallbacks to `GameActs`, `UnlockableLevels`,
`UnlockableLevelsByGameMode`, `MapPresentationActs`, and `NetworkLookup`, loads a
custom menu-video package, and guards its one-time writes with persistent state.
The independent Event Tweaker implementation instead follows the current
decompile contract above: a closed allowlist, a transient presentation copy around
vanilla widget construction, a view-local act list, fail-closed menu-read contract
diagnostics, no custom assets/packages, no network mutation, and a bounded
idempotent campaign fallback (three local tables, vanilla shape, no-op on a
healthy install) instead of the reference mod's persistent broad writes.

The curated catalog and presets live in the shared require'd module `event_tweaker_catalog.lua` (v0.4.26-dev; previously two hand-synced copies with a "keep in sync" warning):

- `Catalog.CATEGORIES` — read by `_evt_selection.lua` (`selected_individual_mutators()`), `_evt_diagnostics.lua` (`event_clear`), and `event_tweaker_data.lua` (widget-tree build).
- `Catalog.EVENT_PRESETS` — read by `_evt_selection.lua` (`active_preset()`). The presets dropdown in `event_tweaker_data.lua` references the keys directly (the dropdown's `value` strings are themselves the preset keys).
- `Catalog.DLC_BY_MUTATOR` / `Catalog.DLC_BY_PRESET` — read by `_evt_dlc.lua` (fail-closed injection gate) and `event_tweaker_data.lua` (fail-open UI gate).

## Adding a new mutator

The mutator name must be a string that's already registered in `NetworkLookup.mutator_templates`. To verify before adding: check that `scripts/settings/mutators/mutator_<name>.lua` exists in the unpacked source (Vermintide-2-Source-Code). All vanilla + DLC batch_01/02/04 + Geheimnisnacht_2021 + Skulls_2023 mutators qualify; see `mutator_settings.lua:5-38` and the various DLC `_common_settings.lua` files for the full list.

1. Add the name to the matching category's `mutators` array in `event_tweaker_catalog.lua` (`CATEGORIES`) — the single shared copy the script modules and the data file both read.
2. Add `mut_<id>` and `mut_<id>_tooltip` keys to `event_tweaker_localization.lua`. Convention: tooltip leads with `[<mutator_id>]` so the literal name being injected is verifiable from the UI.
3. Bump `MOD_VERSION` in `event_tweaker.lua` per the always-bump rule.
4. Build (`& $exe build event_tweaker`), deploy (`& $exe deploy event_tweaker`) where `$exe` is `tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe`, restart, test.

## Adding a new event preset

When a mutator inspects `active_events` internally (Geheimnisnacht does, Skulls does NOT), it needs a preset entry to work — checking the box alone won't trigger its set pieces. Same applies to events that ship a baked keep variant.

1. Add the preset to `EVENT_PRESETS` in `event_tweaker_catalog.lua`. Required fields:
   - `active_events` (table of strings) — what `get_active_events` will return
   - `mutators` (table of strings) — what `get_special_events` will return as the `mutators` field
   - `hub_level` (string, optional) — keep level variant to load. Use one of `inn_level_halloween` / `inn_level_skulls` / `inn_level_celebrate` / `inn_level_sonnstill`.
2. Add an option entry to the `event_preset` dropdown's `options` list in `event_tweaker_data.lua`.
3. Add `preset_<key>` localization key in `event_tweaker_localization.lua`.

## Confirmed mutator catalog (all year-round in NetworkLookup)

- **Vanilla** (`scripts/settings/mutator_settings.lua:5-38`): no_ammo,
  no_pickups, player_dot, instant_death, whiterun, no_respawn, elite_run,
  specials_frequency, more_specials, same_specials, big_specials,
  elite_specials, gutter_runner_mayhem, chaos_warriors_trickle,
  mixed_horde, multiple_bosses, hordes_galore, powerful_elites,
  shared_health_pool, high_intensity, wave_of_plague_monks,
  wave_of_berzerkers, night_mode, life, metal, heavens, light, shadow,
  fire, death, beasts, twitch_darkness (excluded — Twitch-only).
- **DLC mutators_batch_01**
  (`scripts/settings/dlcs/mutators_batch_01/mutators_batch_01_common_settings.lua:5-10`):
  splitting_enemies, darkness, ticking_bomb, realism.
- **DLC mutators_batch_02**
  (`mutators_batch_02_common_settings.lua:5-12`): escort, slayer_curse,
  explosive_loot_rats, leash, bloodlust, skulking_sorcerer.
- **DLC mutators_batch_04**
  (`mutators_batch_04_common_settings.lua:5-9`): flames,
  lightning_strike, chasing_spirits.
- **Live-event** (`geheimnisnacht_2021_common_settings.lua:52`,
  `skulls_2023_common_settings.lua:27`): geheimnisnacht_2021,
  geheimnisnacht_2021_hard_mode, skulls_2023.
- **No mutators_batch_03** in current source (probably retired or skipped numbering).

## Known mutator behaviors that affect the mod

- `mutator_geheimnisnacht_2021.lua:58-86` calls
  `live_events_interface:get_active_events()` and does
  `string.find(live_event, "geheimnisnacht_%d+")` to determine which 5
  maps spawn ritual sites — the year picked decides which canonical map
  list activates (see `geheimnisnacht_utils.lua:5-41` for the per-year
  lists). **Hence the preset dropdown is required for Geheimnisnacht to
  do anything visible.**
- `mutator_skulls_2023.lua` does NOT inspect `active_events` — its
  `server_start_function` spawns skull pickups on every
  `pickup_system.primary/secondary_pickup_spawners` unconditionally. The
  mutator alone is enough; preset is cosmetic for Skulls.
- `GameModeBase.append_live_event_mutators`
  (`game_mode_base.lua:257-288`) skips hub levels and tutorial levels.
- `level_keys = nil` on a special-event entry means "applies to all
  levels" (line 275 condition).
- **Keep decoration is NOT mutator-driven.** Vanilla
  Geheimnisnacht/Skulls/Anniversary swap the entire keep level file
  (decorations are baked geometry). `AdventureMechanism.get_starting_level`
  (`adventure_mechanism.lua:625`) reads
  `Managers.backend:get_level_variation_data().hub_level` and returns
  it. Variant level keys defined in
  `scripts/settings/level_settings.lua:152-196`: `inn_level_halloween`,
  `inn_level_skulls`, `inn_level_celebrate`, `inn_level_sonnstill`. Each
  loads its own world file and decoration packages. Hooked in v0.3.0-dev
  via `BackendManagerPlayFab.get_level_variation_data` — single entry
  point, all callers (state_ingame, interactions, carousel) get the
  override. Caveat: changing the preset after the keep is already loaded
  does NOT swap the keep — user must restart or run a mission and return.

## Sharp edges

### `get_special_events` entries MUST have a `name` field

When hooking `BackendInterfaceLiveEventsPlayfab:get_special_events` (or
otherwise fabricating live-event data), every entry MUST include a
non-nil string `name` in addition to `weekly_event` and `mutators`.

```lua
-- WRONG — crashes on startup with "table index is nil"
{ weekly_event = "append", mutators = { "geheimnisnacht_2021" } }

-- CORRECT
{ name = "geheimnisnacht_2021", weekly_event = "append", mutators = {...} }
```

**Why:** `scripts/entity_system/systems/dialogues/dialogue_system.lua:198-200`
does:

```lua
local event_name = event_data.name
self._global_context[event_name] = true   -- nil here = "table index is nil" crash
```

This runs on every level load **including the keep/hub**, so the crash
hits at startup — NOT only on missions.
`GameModeBase.append_live_event_mutators` skips hub levels, but
`DialogueSystem` does not. **Caused the v0.2.0-dev → v0.2.1-dev fix.**

**How to apply:** When any future tweaker-class mod injects fake events
into the live-events backend interface:

- Always set `entry.name` to a non-nil string. Use the canonical event
  name if it matches (e.g. `"geheimnisnacht_2021"`, `"skulls_2023"`), or
  a synthetic identifier (e.g. `"event_tweaker_custom"`) for
  hand-rolled selections.
- The dialogue system also iterates `entry.mutators` and calls
  `_load_special_event_dialogues(mutator_name, ...)` — that path uses
  `Application.can_get` first so missing dialogue files don't crash.

### Hub levels skip the mutator path

`GameModeBase.append_live_event_mutators` (`game_mode_base.lua:260-262`) explicitly returns early on `level_settings.hub_level` or `level_settings.tutorial_level`. Anything that needs to run on the keep — visual decorations, ambient audio, NPC swaps — has to use a different mechanism. Currently we only handle keep decoration (`hub_level` swap). Other keep-level changes (mission board reskin, NPC dialogue) would need additional hooks.

### Preset changes auto-reload the level (v0.4.0+)

All three hooked queries (`get_special_events`, `get_active_events`, `get_level_variation_data`) are consulted at level-load time only. So a preset change between loads is dormant until the next level swap. Worked around via `mod.on_setting_changed` (host only):
- In the keep, target `hub_level` differs from current → `level_transition_handler:set_next_level(new_hub_level) + promote_next_level_data()`. State-machine's update loop picks it up via `needs_level_load()` and triggers a `load_next_level` transition (`state_ingame.lua:1291`).
- In the keep, same `hub_level` (or no preset selected) → `Managers.state.game_mode:retry_level()`. Reloads current keep; `DialogueSystem` re-reads hooked `get_special_events` on the way back in.
- In a mission → `retry_level()`. Re-runs `append_live_event_mutators` against the new mutator list, rebuilds `_mutator_handler`, broadcasts via the vanilla mutator-activate RPC to all clients. Clients don't need the mod.

Individual mutator checkboxes do NOT auto-reload (5 toggles would = 5 keep reloads). Use `/event_apply` to apply checkbox changes manually.

### Vanilla mutator name strings are the literal IDs from the source files

E.g. `geheimnisnacht_2021` (NOT `mutator_geheimnisnacht_2021`). The `mutator_` prefix is the filename convention, but the registered name (the one in `NetworkLookup.mutator_templates`) is just the suffix.

### Weave (cat_winds) mutators are unsafe outside a real Weave (issue 413, v0.4.24-dev)

The eight Winds-of-Magic mutators assume the Weave context. Outside one, `Managers.weave:get_active_wind_settings()` returns nil (`weave_manager.lua:423-432`) and the weave resource packages are not resident, so activating them in Adventure (or Deus) crashes:

- `shadow` — `client_update_function` spawns `units/weapons/player/wpn_shadow_gargoyle_head` and calls `Unit.light` on it (`mutator_shadow.lua:186-187`); non-resident unit = engine fatal (bypasses pcall) on every peer with a local client (`mutator_handler.lua:210` keys on `_has_local_client`, host included). The issue 413 client CTD.
- `heavens` / `light` / `death` / `beasts` — `server_start_function` nil-indexes `wind_settings` (`mutator_heavens.lua:38`, `mutator_light.lua:182`, `mutator_death.lua:210`, `mutator_beasts.lua:122`). Host crash.
- `fire` — `client_start_function` nil-indexes `wind_settings` (`mutator_fire.lua:39`). Every-peer crash.
- `life` — nil-safe reads, but `spawn_bush` network-spawns the weave-package unit `units/weave/life/life_thorn_bushes_mutator` (`mutator_life.lua:19-24`); same non-resident-resource class, replicated to every peer.
- `metal` — the one SAFE wind: `get_wind_strength()` falls back to 1 (`weave_manager.lua:679-683`), no `wind_settings` index, no spawns.

**Fix (do not remove):** `WEAVE_ONLY_MUTATORS` + `_weave_wind_active()` in `_evt_guard413_weave.lua` preserve the stock-path floor. `gather_mutators()` drops six unsafe winds unconditionally outside a Weave. Shadow is the bounded exception: `_evt_shadow_adventure.lua` replaces its non-resident presentation with an asset-free radius/fade/buff adapter, and selection admits it only when a capability-specific all-peer roster plus closed pre-session set are proven. Otherwise it is dropped before `rpc_activate_mutator_client`, including for modless and older-ET peers. Real Weave missions delegate to Fatshark's untouched native functions. Checks: `issue413_weave_only_mutators_gated`, `issue413_shadow_adventure_adapter`; checklist slug `et-weave-only-mutator-gate`.

### Boss-event mutators fatal on fixed-end-boss levels (issue 455, v0.4.25-dev)

Three vanilla mutators index `CurrentBossSettings.boss_events` with no nil check: `multiple_bosses` (`server_initialize_function` + `update_conflict_settings`, `mutator_multiple_bosses.lua:8/:13`), `blessing_of_grimnir` (`server_start_function`, `mutator_blessing_of_grimnir.lua:60`), `deus_pacing_tweak` (`server_start_function`, `mutator_deus_pacing_tweak.lua:482/:498`). `CurrentBossSettings` is rebuilt per level from the conflict director's `boss` block (`conflict_director.lua:879`); fixed-end-boss levels (crash evidence: `warcamp` = The War Camp) ship a boss block with NO `boss_events` table, so injecting one of these is an instant host fatal at the dispatch sites (`mutator_handler.lua:644-645` / `:578-579`). Distinct class from issue 413: these are Adventure-legal, just level-dependent.

**Fix (do not remove):** `BOSS_EVENT_GUARDS` + `mod._et455_guard_boss_event_mutator(name)` in `_evt_guard455_boss_events.lua`, installed from `add()` (`_evt_selection.lua`) on injection: wraps the template's live dispatch fields (`template.server.initialize_function` / `.start_function` / `template.update_conflict_settings` — the engine folds `server_*_function` into `template.server.*` at boot, so wrapping the raw `server_*_function` field would be a dead write) with a dispatch-time check that no-ops with an `[et:455]` printf when `boss_events` is absent. Idempotent via `__et455_guarded` marker. Regression check: `issue455_boss_event_mutators_guarded`; checklist slug `et-boss-event-mutator-guard`.

### Injected mutators that write scalar pacing values crash `ConflictDirector.init` (issue 386, v0.4.22-dev)

Some mutators' `update_conflict_settings` write PLAIN NUMBERS into `CurrentPacing`. The canonical case is `mutator_high_intensity.lua:12-14`:

```lua
CurrentPacing.delay_horde_threat_value       = 200
CurrentPacing.delay_specials_threat_value    = 200
CurrentPacing.delay_mini_patrol_threat_value = 200
```

`MutatorHandler.conflict_director_updated_settings` (`mutator_handler.lua:567`) runs every INITIALIZED mutator's `update_conflict_settings` and is dispatched from `ConflictDirector.refresh_conflict_director_patches` (`conflict_director.lua:886`), which `ConflictDirector.init` calls at line 94 — **before** init reads those three fields at lines 219-221 and passes each to `DifficultyTweak.converters.tweaked_delay_threat_value`. That converter **always** indexes its argument as a per-difficulty table (`difficulty_tweak.lua` `get_value_for_difficulty`: `value_table[Difficulties[i]]`), so a scalar there is an uncatchable "attempt to index a number value" fatal that kills the director → zero AI for the whole mission. Vanilla Adventure never lists these mutators, so the fields keep their table-shaped base values (`conflict_settings.lua`, keys `normal`..`versus_base`); **our injection is what triggers it**.

**Fix (do not remove):** a `hook_safe` on `MutatorHandler.conflict_director_updated_settings` (`_evt_guard386_pacing.lua`) runs after the vanilla dispatch writes the scalars (still inside `refresh_conflict_director_patches`, so before init's line 219 read) and converts any scalar left in those three fields into `{ normal = v, [current_difficulty] = v }`. `get_value_for_difficulty` walks DOWN to `Difficulties[1] == "normal"`, so the floor key covers every difficulty. Host-only in effect (`conflict_director_updated_settings` early-returns on clients) and a strict no-op when the fields are already tables. Regression check: `issue386_sanitize_pacing_scalar_to_table`.

**If you add a mutator to the catalog:** if its source `update_conflict_settings` assigns a plain number to any field ConflictDirector reads as a per-difficulty table, this sanitizer already covers the three known pacing fields — extend `PACING_TABLE_FIELDS` if a new field surfaces.

## Diagnostic commands

- `/event_probe` — dump `active_events`, `special_events`, `weekly_events` from the hooked backend interface (you'll see your injected entries reflected back) plus what the mod would currently inject given the active settings.
- `/event_active` — list mutators the engine actually activated in the current level (read from `Managers.state.game_mode._mutator_handler:activated_mutators()`). Use this to confirm the host-side hook + mutator handler picked up our injection.
- `/event_clear` — uncheck every individual mutator checkbox. The Event Preset dropdown is untouched.
- `/event_apply` — reload the current level so any pending preset or mutator changes take effect. Auto-fires on `event_preset` change; for individual mutator toggles you have to invoke this command (or wait for the next natural level transition).

## Build & deploy (matches sibling tweaker mods)

```powershell
$exe = "C:\Users\danjo\source\repos\vermintide-2-tweaker\tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe"
& $exe build  event_tweaker
& $exe deploy event_tweaker
```

Those commands are nonpublishing iteration only. Workshop publication follows
the merge-first canonical transaction in `PROJECT_STANDARDS.md` section 6.6.
Direct launcher `all`/`upload`, GUI publication, and the removed legacy wrappers
are prohibited.

## Known limitations

- Anniversary 2025 / 2026 and Sonnstill keep variants exist in `level_settings.lua:152-196` (`inn_level_celebrate`, `inn_level_sonnstill`) but no presets yet. Trivial to add — see "Adding a new event preset". (Geheimnisnacht 2026 and Skulls 2026 presets were added in v0.4.11-dev once Fatshark shipped the 2026 DLC content; gameplay still rides `mutator_geheimnisnacht_2021` / `mutator_skulls_2023` since no new mutator files were shipped.)
- Drachenfels event mutators and Karak Aspect winter event aren't surfaced because they're tangled with game mode selection (Deus / Chaos Wastes mechanism), not the standard mutator pipeline.
- Modded mutators from other workshop mods would need to be registered in `NetworkLookup.mutator_templates` independently — this mod only exposes mutators that ship in vanilla / first-party DLC.
- Backend-only event consequences — portrait frames, contracts, achievements — won't come back. The mod ships *gameplay* (mutators + keep decoration), not *loot*.
