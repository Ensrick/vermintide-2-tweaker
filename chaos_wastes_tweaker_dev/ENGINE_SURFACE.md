# chaos_wastes_tweaker_dev - engine contact surface

What vanilla VT2/Stingray does at every seam `ct_dev` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `ct` line numbers are in
the named `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/*.lua`
module. `§N` = a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue.

**Dev/stable relationship.** This documents `chaos_wastes_tweaker_dev` (`ct_dev`,
MOD_VERSION `0.7.272-dev`, friends-only Workshop 3733366926), the ACTIVE working
stream. `chaos_wastes_tweaker/` (`ct`, public Workshop 3712929235) is its
read-only public twin; per repo `CLAUDE.md` all in-flight work happens in the dev
dir and promotion is a separate user-triggered action, so this doc cites only
`ct_dev` line numbers. The mod-id gate `get_mod("ct_dev")` means any cross-mod
consumer resolving `get_mod("ct")` will NOT see the dev clone.

**Verification split (honest).** Line-verified against the 2026-07-12 decompile:
the wire-safety core (`buff_system.lua:66-97`/`:302-308`/`:430-454`,
`deus_run_state_spec.lua:60`/`:85`, `deus_spawning.lua:249`/`:277-278`), the
`MutatorHandler.tweak_pack_spawning_settings` arity trap (call site
`main_path_spawning_generator.lua:327` + def `:748`), `initialize_mutators`
(`:48`/`:85`), and every ct hook signature (grep-confirmed in source, 105 sites).
The remaining `[src:]` citations (DeusChestExtension internals, DeusMechanism node
flow, pickup spawner, per-boon `deus_power_up_settings` lines) are carried from the
cited `ct_dev` module comments + `DEVELOPMENT.md` + `CHANGELOG.md`, which cite the
decompile in turn.

`ct` is the **largest** mod in the monorepo (~14.8k lines main file + 5 sibling
modules) and the deepest into the Deus (Chaos Wastes) run layer: it reshapes CW
economy, the boon/power-up pool, curses/mutators, altars/chests, weapon
generation, and injects vanilla Adventure missions into the CW graph. Its engine
contact clusters into the five surfaces below, each with its own subsystem note.

## Hook table

**103 hook sites** (`mod:hook`/`mod:hook_safe`) + **4 VMF RPC channels**
(`mod:network_register`) + a set of engine-**table** contacts (registration/pool
injection, not hooks - see Surface 2/5 notes). Grouped below into rows-of-concern.
`[hook]` = full wrapper (`mod:hook`); `[safe]` = `mod:hook_safe` (post-callback,
no override); `[tbl]` = table-form hook against a plain-table target (nil-guarded);
`[rpc]` = `mod:network_register` (a VMF network event, not a class hook). Where a
`(Class, method)` carries multiple concerns they are **consolidated** into one
hook body and dispatched internally - VMF silently drops a second hook on the same
pair (repo `CLAUDE.md` NON-NEGOTIABLE 8), flagged in the trap column.

### Surface 1a - Deus run controller: run state, power-up grants, blessings (owner: `docs/engine/11`, `/03`; `chaos_wastes_tweaker_dev.lua`)

| Class.method (kind) | Vanilla behavior at the seam | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `DeusRunController.add_power_ups` [hook] `:7814` | Grants a set of power-ups to a player, appends to run-state lists, rides the run-state sync to peers [src: `deus_run_state_spec.lua:60` encode] | CONSOLIDATED grant choke point: issue-211 disable gate + #426 peer-parity filter (drop modded boon names when parity unconfirmed); covers chest/cursed-chest/shop/set-reward/end-of-level/debug + bot-mirror grants | The single grant filter; `_ct_bot_mirror_active` grants bypass the pre-filter so the bot picker carries its OWN parity check (DEVELOPMENT "Sharp edges"); never toggle-gate the wire safety (memory `reference_vt2_wire_safety_never_toggle_gated`) |
| `DeusRunController._add_initial_power_ups` [safe] `:8148` | Materializes the loadout's selected talents, then event boons, for each player at run setup [src: `deus_run_controller.lua:471-495`] | Append configured STARTING boons; #556 excludes an already-materialized same-name talent and resolves preview identity through vanilla career helpers; #426 parity-filters modded names | `hook_safe` means the post-call run-state list is the canonical duplicate set. Talent templates are generic tier/column identities and require profile/career resolution (`deus_power_up_utils.lua:259-322`); modded names ride `deus_run_state_spec.lua:60`/`:85` |
| `DeusRunController._try_buy_blessing` [hook] `:10812` | Player buys a miracle/blessing at the shrine; charges soft currency, calls `has_blessing`/`get_player_soft_currency(buyer, REAL_PLAYER_LOCAL_ID)` | Persistent Miracle of Ulric/Isha; #426 degrades `ct_miracle_*` to the VANILLA blessing under unconfirmed parity (coins buy the vanilla effect, wire-safe); Isha arm/apply parity-gated with pending state | `REAL_PLAYER_LOCAL_ID` is a vanilla file-local (=1), NOT global - MUST re-declare or `get_player_soft_currency(buyer,nil)` returns 0 and every purchase silently rejects (v0.7.88 crash, DEVELOPMENT deep-dive) |
| `DeusSpawning._apply_initial_buffs` [safe] `:10950` | On each mission spawn, re-applies the player's persistent buffs + non-talent power-up buff_names via `buff_system:add_buff` [src: `deus_spawning.lua:277-278`, persistent list built at `:249`] | #426: modded persistent-buff names re-apply every mission = repeated wire exposure; parity strip removes ct names from persistent lists on parity loss | `hook_safe`; persistent reapply is the mid-run re-exposure path the strip must cover, not just the grant |
| `DeusRunController.setup_run` [hook] `:2455` / `rpc_deus_set_initial_soft_currency` [hook] `:2579` | One-time run setup; host broadcasts initial soft currency to clients | Starting-coins grant folded into the full `setup_run` hook (host-side broadcast) | v0.7.95 CONSOLIDATION: a prior `hook_safe("setup_run")` host broadcast was folded into this full hook - two hooks on the pair = VMF drop |
| `DeusRunController.get_run_difficulty` [hook] `:2399` / `StatisticsUtil._register_completed_journey_difficulty` [hook] `:2442` | Reports run difficulty; records completed-journey difficulty into career stats | Progressive difficulty override; clamp the RECORDED difficulty so a ramped run never writes a ceiling the stat array lacks | Journey-stat cataclysm-ceiling CTD (#291, memory `reference_vt2_journey_stat_cataclysm_ceiling_crash`) - clamp before the stat write |
| `DeusRunController.get_own_weapon_pool_excludes` [hook] `:3432` / `get_deus_weapon_chest_type` [hook] `:3647` / `_check_set_completed` [hook] `:8193` / `can_spawn_belakor_locus` [hook] `:7328` | Weapon-pool exclude list / weapon-chest type / weapon-set completion / whether a Belakor locus may spawn | Weapon-generation tuning, set-reward flow, Belakor spawn gating | Read-mostly; per-run state on the controller |
| `BackendInterfaceDeusPlayFab.deus_journey_with_belakor` / `set_loadout_item` / `get_total_power_level` [hook] `:4148`/`:4170`/`:4184` | CW backend: journey-with-Belakor query, loadout write, power-level total | Belakor journey enable, loadout, power-level tuning | Backend interface, host-authoritative; never commit to PlayFab (`docs/engine/11`) |
| `DeusWeaponGeneration.generate_weapon` / `generate_weapon_for_slot` / `generate_item_from_item_key` / `upgrade_item` [hook] `:4107-4122` | Deterministic CW weapon rolls (properties/traits from run_progress+rarity+seed) | Weapon-reroll + trait-ban integration; upgrade altar re-roll (seed-mix per reuse) | `_generate_upgraded_weapon` is DISTINCT from `_generate_stored_weapon` - upgrade altars weren't rerolling until v0.7.240 added a per-go_id use-count seed mix (CHANGELOG :805) |

### Surface 1b - Deus chests / altars / shrine + map UI (owner: `docs/engine/09`, `/07`; `chaos_wastes_tweaker_dev.lua`, `_ct_dup_vote_chips.lua`)

| Class.method (kind) | Vanilla behavior | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `DeusChestExtension.open_chest` [safe] `:8531` | Opens an altar/chest, grants its stored reward | CONSOLIDATED altar-reuse + reward logic (open-chest is the single write point) | The canonical `(DeusChestExtension, open_chest)` singleton: burned v0.7.129/.130 with a 2nd hook on the pair (banner at `:8524`); mod-lint enforces at most `mod:hook`+`mod:hook_safe` split across a pair, never two same-kind |
| `DeusChestExtension.update` / `get_purchase_cost` / `_generate_stored_power_up` / `_generate_stored_weapon` / `_generate_upgraded_weapon` / `update_upgrade_chest_color` / `can_be_unlocked` / `extensions_ready` / `purchase` [hook/safe] `:951-8487` | Per-frame chest tick, cost query, stored-reward generation, upgrade-chest recolor, unlock gate, spawn init, purchase | Altar cost/mix tuning, reward-seed mixing, walk-through collision setup at `extensions_ready`, reuse economy | Walk-through uses `Actor.set_collision_filter(actor,"filter_trigger")` NOT `set_scene_query_enabled(false)` (breaks "press E", DEVELOPMENT "Walk-through pattern"); `Unit.actor` is 1-indexed |
| `DeusCursedChestExtension._set_state` [safe] `:7361` | Cursed-chest state machine (`CURSED_CHEST_STATE_OPEN = 3` server-side; hot-join clients use 4) | Chest-of-Trials revive option + state-driven UI | Hot-join clients see state 4, not 3 (AUDIT_FINDINGS #4) |
| `DeusCursedChestExtension.update` [safe] / `can_interact`, `get_interaction_length`, `get_interaction_action`, `on_client_interact` [hook] `_ct_cot_early_reward.lua` | Server interaction writes RUNNING; the first RUNNING update starts `cursed_chest_prototype`, procs/sound, and only event completion writes OPEN. OPEN records purification, plays the finish jingle, creates the marker, emits cleanse, and enables the native reward view [src: `deus_cursed_chest_extension.lua:66-151,267-316`] | Optional #350 early reward presentation and native reward access while authoritative state remains RUNNING | Never write OPEN early: that would falsely complete counters/revive and stop the RUNNING completion check. Every peer consumes replicated RUNNING plus the host-broadcast effective setting; per-extension actions are one-shot. An early claimant's marker/visual is restored after real completion without suppressing completion side effects |
| `DeusShopView` / `DeusCursedChestView` `.update` + `._create_ui_elements` / `create_ui_elements` / `_on_button_pressed` [hook/safe] `:2857-8204` / `DeusUpgradeWeaponInteractionUI._populate_widget` [safe] `:1229` | Shrine-shop / cursed-chest / upgrade-altar view build + tick + button | Inject ct boon widgets, NaN arc-offset fix, reroll button | NaN widget-offset fix only needed for the 1-widget case (AUDIT_FINDINGS #6); VMF numeric widget has no `step` (memory `reference_vmf_numeric_widget_no_step`) |
| `IngamePlayerListUI._setup_mission_data` [hook] / `_setup_deed_reward_data` + `_draw` [safe] `:8320-8790` | Builds Adventure collectible widgets from `loot_objectives` with 2-per-row measured layout (`ingame_player_list_ui_v2.lua:436-513`); updates the fit-height scenegraph at draw time (`ui_scenegraph.lua:210-297`) | #533 replaces impossible Adventure book counters with live DEUS chest/coin counts during a run; #461 adds queued-run boon preview; #571 reflows CT rows against the live right-banner/safe-rectangle bounds | One consolidated `_draw` hook. Layout cannot be finalized in `_setup_mission_data` because scenegraph transforms have not run yet; recompute only on resolution/UI-scale/safe-rect signature change. Stock Adventure calls vanilla unchanged. |
| `DeusMapDecisionView._update_player_state` [safe] `_ct_dup_vote_chips.lua:255` / `DeusMapScene._clear` [safe] `:421` | CW map-vote screen: places one "token" chip per hero keyed by `profile_index` [src: `deus_map_scene.lua:238-251`, `place_token` `:833-841`] | With gt's `allow_duplicate_careers`, two peers share a `profile_index` and the second `place_token` OVERWRITES the first - spawn a SECOND chip for the extra voter | Post-hook (vanilla runs first, non-duplicate case byte-for-byte vanilla); distinguish by offset+scale, NOT material recolor - token `.unit` tint vars are unverified per-asset and `Material.set_*` silently no-ops on an absent shader var |
| `DeusMapDecisionView._enable_hover` [hook] `:3400` / `DeusMapScene.on_enter` [hook] `:6150` | Node-hover enable / map-scene enter (applies the resolved graph) | Curse-preview on hover; late-arrival graph-snapshot re-apply | `on_enter` is the graph-snapshot late-apply site (see Surface 4 note) |
| `GameModeMapDeus.local_player_game_starts` [hook] `:8375` / `DeusShopView.start` [hook] `:8822` | Sets initial MAP_DECISION and calls `full_sync()` (`game_mode_map_deus.lua:144-159`); SHOP view immediately indexes `DeusShopSettings.shop_types[current_node.level].blessings/power_up_count` without a nil check (`deus_shop_view_v2.lua:179-184`) | #458 Buy Starting Boons: every peer registers and validates `shop_types["dlc_morris_map"]` **before** vanilla startup/full-sync; host publishes SHOP only after validation; the view-start guard rebuilds or returns to MAP_DECISION before vanilla dereferences | These are ct's only hooks on the two exact pairs. Never move peer config creation after `func`: a client can consume replicated SHOP inside vanilla `full_sync()`. `states.MAP_DECISION=1`, `states.SHOP=3` are file-local constants (`:45-49`). Never call `handle_shrine_entered`; vanilla SHOP->WAITING->MAP_DECISION (`:341-349`) returns to the map. Guard diagnostics are capped at four rows per process. |

### Surface 1c - Deus mechanism / node graph / lobby join (owner: `docs/engine/03`, `/08`; `chaos_wastes_tweaker_dev.lua`)

| Class.method (kind) | Vanilla behavior | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `DeusMechanism.get_current_node_curse` / `_transition_next_node` / `start_next_round` / `_setup_run` / `game_round_ended` / `unlock_arena_belakor` [hook/safe] `:3296-4365` | CW run mechanism: current-node curse, node transitions, round start/end, run setup, Belakor arena unlock | Curse filtering, per-mission GLOBAL reset (`_ct_cursed_chest_seq`), finale error-swallow | `game_round_ended` SWALLOWS exceptions (finale vote can throw on ambiguous dominant-god vote) - "host continues, deus state may be inconsistent" marker asserted by `/ct_regression_test` |
| `DeusMechanism.debug_load_deus_level` [direct call, no hook] `_ct_dev_mission.lua` | Vanilla debug entry encodes progress + requested level into a single-node seed, sets up the run, synchronizes it, and transitions (`deus_mechanism.lua:1017-1020`) | #505 Single Mission Loader starts the selected one-node run for targeted testing | Host-only and gated to current level `morris_hub`, the exact target of the keep's `deus_door_transition` (`interactions.lua:2738-2744`). Forced curse determines theme (`deus_generate_graph.lua:67-69`); loader selects the first declared valid path because graph population normally chooses among `level_info.paths` (`deus_populate_graph.lua:342-346,462-465`) |
| `DeusPowerUpUtils.generate_random_power_ups` [hook] `:2627` | Rolls the shrine/chest boon offer from `DeusPowerUpRarityPool` + `existing_power_ups_lut` [src: `deus_power_up_utils.lua:189`] | CONSOLIDATED master boon-roll hook: count override + disabled-boon enforcement + bomb-boon exclusivity + Belakor force-rarity | v0.7.77 CONSOLIDATION (two hooks caused "rehook active hook"); reads `args[6]`=availability_type, `args[8]`=forced_rarity positionally; injected boon rarity MUST be `{event,rare,exotic,unique}` or `existing_power_ups_lut[rarity]` is nil -> crash (DEVELOPMENT "Deus boon rarities") |
| `_G deus_populate_graph` [hook] `:6395` | The deterministic CW node-graph generator; picks levels/curses/themes by INDEX into `LEVEL_AVAILABILITY.*` arrays | Host broadcasts resolved graph; clients overwrite in place (per-peer determinism fix) | Same seed x different arrays (ct's `inject_adventure_maps` mutates the arrays) = divergent picks; can't runtime-resync because array length folds into the lobby hash - hence the snapshot RPC (DEVELOPMENT "Graph-snapshot RPC") |
| `_LobbyAux.create_network_hash` [hook,tbl] `:453` | Computes the lobby `combined_hash`; `num_levels` is the only field a Lua mod affects | ct's `inject_adventure_maps` raises `num_levels` (vanilla 582 -> ~774); shim lets a modded host still admit peers where safe | `LevelSettings` mutations are STICKY - can't be un-registered from Lua, only a game restart reverts `num_levels` (DEVELOPMENT "Lobby combined_hash"); the shim deliberately lets NON-ct peers join, which is exactly why the #426 wire-safety gate exists |
| `GameModeDeus.local_player_game_starts` [safe] `:5638` / `evaluate_end_conditions` [hook] `:10140` / `_get_coins_amount_and_type` [hook] `:7048` | CW game-mode: local start (applies theme light tint), end-condition eval, coin pickup amount/type | Curse light tinting on injected levels, end-condition tuning, coin economy | GameMode hooks need all three modes where relevant (memory `reference_vt2_mission_gamemode_hooks_three_modes`); `local_player_game_starts` iterates `Level.units` for reflection-probe tint [src: `game_mode_deus.lua:358-378`] |
| `BulldozerPlayer.spawn` [safe] `:4211` | Local player spawn | Post-spawn re-apply hook for run-dependent state | `hook_safe`; local player only |

### Surface 2 - Buff system + boon/power-up registration (owner: `docs/engine/10`, `/03`; `chaos_wastes_tweaker_dev.lua`, `_ct_combat_hooks.lua`)

`docs/engine/10` owns the buff-system deep dive; this surface is the CW boon/miracle
registration + the `NetworkLookup.buff_templates` strict-index doctrine.

| Class.method (kind) | Vanilla behavior | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `BuffExtension.add_buff` [hook] `:12617` | Adds a local buff instance from a template name [src: `buff_extension.lua`] | Meta-boon stacking + boon-application observation | Consolidated buff-apply observation; resolve template from `ProcFunctions[name]`, not `BuffFunctionTemplates.functions` for merged CW procs (combat-hooks banner :75) |
| `BuffFunctionTemplates.functions.apply_pockets_full_of_bombs_buff` [hook,tbl] `:12681` / `remove_deus_potion_buff` [hook,tbl] `:12698` | Bomb-boon apply callback / deus-potion buff removal | Endless-bombs cooldown, potion-duration tuning | Table-form on `BuffFunctionTemplates.functions[key]`; the apply-callback category lives in `buff_function_templates` (unlike `chain_lightning`, a merged `proc_functions` entry) |
| `ProcFunctions.chain_lightning` / `lightning_adjecent_enemies` / `mark_of_nurgle_explosion` / `career_ability_apply_dot_to_adjecent_enemies` / `boon_dot_burning_01_spread` [hook,tbl] `_ct_combat_hooks.lua:90-1077` + `drop_item_on_ability_use` / `grenade_explode_buff_area` [hook,tbl] `chaos_wastes_tweaker_dev.lua:9488`/`:9528` | CW boon/trait proc functions: chain lightning, AoE lightning, Nurgle gas explosion, career-ability DoT spread, Wildfire spread, ability-drop, grenade-area | Manann's Tempest 8s cooldown, AoE cap crash-guard (#129), gas-cloud rate cap (#104), Wildfire colour-match by source burn, bomb-boon tweaks | `ProcFunctions` is the GLOBAL merged table (`DLCUtils.merge("proc_functions",...)` at `buff_templates.lua:9533`), NOT `BuffFunctionTemplates.functions` - hooking the latter no-ops (load-time "function doesn't exist", combat-hooks :75-85); weak-keyed cooldown tables so entries die with the unit |
| `GenericAmmoUserExtension._apply_buffs` [safe] `_ct_combat_hooks.lua:1171` / `use_ammo` [hook] `chaos_wastes_tweaker_dev.lua:11471` / `PlayerUnitEnergyExtension.drain` [hook] `:11492` / `PlayerUnitOverchargeExtension.add_charge` [hook] `:11530` | Ammo max/consume, Moonfire energy drain, overcharge add | Larger-clip boon (#34), meta-ammo boons (per-cast reduction) | Consumption-side only - never mutate `_max_*` (memory `feedback_vt2_max_resource_consumption_side`); `max_overcharge` >60 fatals the network bound - use `reduced_overcharge` (DEVELOPMENT "max_overcharge") |
| `ActionChargedProjectileUtility.fire_charged_projectile` [hook] `_ct_combat_hooks.lua:1210` / `PlayerUnitHealthExtension.sync_health_state` [hook] `:7619` / `RespawnHandler._respawn_player` [safe] `:7639` | Charged-projectile fire, health-state sync, player respawn | Projectile boon tuning, health-boon reapply on respawn | Respawn reapply feeds the same persistent-buff path as `DeusSpawning._apply_initial_buffs` |
| **Table contact (NOT hooks):** `DeusPowerUpTemplates` / `DeusPowerUpBuffTemplates` / `_G.BuffTemplates` dual-write; `DeusPowerUpRarityPool` inject/eject; `NetworkLookup.deus_power_up_templates` + `.buff_templates` unconditional append | Boot merges `DeusPowerUpBuffTemplates` -> `BuffTemplates` [src: `morris_buff_settings.lua:7310`]; boons roll from `DeusPowerUpsArrayByRarity`, POOL controls what's offered | Register modded boons/traits/miracles unconditionally (index parity); pool-insert gated by toggle + parity | DORMANT boons need BOTH `DeusPowerUpBuffTemplates` AND `_G.BuffTemplates` or apply crashes (DEVELOPMENT "dormant boons need dual-table writes"); registration is UNCONDITIONAL, pool insert is toggle-gated (the v0.7.67 load-bearing split); all pool writes go through `_add_dormant_to_pool` (the single parity-guarded primitive) |
| **Data contact (NOT hook):** `_data.lua` `BOON_TREE` -> VMF option widgets | Vanilla `deus_power_up_settings.lua` builds power-up tables and rarity arrays but provides no CT menu category. CT generates both Disabled Boons and Starting Boons from one authored catalog. | Catalog the one canonical `ct_kill_heal` power-up under stable `*_mod_boons_group` ids; expose that route as **Modded Boons** (#406). | Structural setting-id ancestry is insufficient verification: the localized category can still misdescribe and hide a boon semantically. Runtime and offline tests lock one widget per surface, immediate parent, realized category label, and player-facing boon name. |

### Surface 3 - Mutators / curses / terror events / breeds (owner: `docs/engine/07`, `/04`; `chaos_wastes_tweaker_dev.lua`, `_ct_combat_hooks.lua`)

| Class.method (kind) | Vanilla behavior | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `MutatorHandler.tweak_pack_spawning_settings` [hook] `:5300` | Applies zone + per-pack mutators' `tweak_pack_spawning_settings` to a pack; `no_roamers` iterates `pack_spawning_settings.difficulty_overrides` with `pairs()` [src: `mutator_no_roamers.lua`] | Strip `no_roamers` on adventure-injected levels where `difficulty_overrides` is nil (else `pairs(nil)` fatals, #41) | **OPEN P0 - arity trap.** Vanilla is a STATIC function (no `self`), called dot-form at [src: `main_path_spawning_generator.lua:327`], def [src: `mutator_handler.lua:748`]. The ct hook signature `function(func, self, zone_mutator_list, ...)` shifts every arg by one: `pack_spawning_settings` is ALWAYS nil (strip runs every call) and the SIGNATURE-zone `zone_mutator_list` - where `no_roamers` actually lives (DEVELOPMENT "adventure mutators") - is the ONE list NOT filtered. Remove `self` from the signature. Verify against `docs/engine/07` before touching |
| `MutatorHandler.initialize_mutators` [safe] `:3264` | Server-only [src: `mutator_handler.lua:48`]; runs after every `template.server.initialize_function` (`:644-645`) lands its data on the breeds | #470 UNCONDITIONAL backfill: set `Breeds.curse_mutator_sorcerer.max_health[8]=150` iff `[7]` exists and `[8]` is nil (vanilla rank-8 hole at cataclysm_3) | Never-crash doctrine, NOT toggle-gated (#371); vanilla's duplicate rank-key bug (`CATACLYSM_2=6`) shifts the band down one rank so rank 8 is empty; entries 6/7 untouched (re-keying changes live values); extend THIS body for any future sparse-rank mutator, never add a 2nd hook |
| `MutatorHandler._activate_mutator` [hook] `:3220` | Activates one mutator by name | Curse enable/disable tuning per-node | Distinct method from `initialize_mutators`/`tweak_pack_spawning_settings` (per-method keying, no dup) |
| `server_tbl.start_function` [hook] `:11036` | A mutator template's SERVER start callback, wrapped into `template.server.start_function` at boot (NOT `template.server_start_function`) | Curse/mutator server-side start tuning | The `server_*_function` fields are DEAD - engine wraps them into `template.server.*` at boot (CLAUDE.md "Mutator template server_*_function is a dead field") |
| `ConflictDirector.start_terror_event` [hook] `_ct_combat_hooks.lua:374` / `TerrorEventMixer.start_event` [hook] `:491` / `TerrorEventMixer.init_functions.spawn_around_origin_unit` [hook,tbl] `:297` | Start a terror event / mixer event / spawn-around-origin init step | Chest-of-Trials enemy-count multiplier (#64), seed uniqueness + force-rotation (#117), Skaven Warlord trial (#324), spawn-composition diagnostic (#471) | Per-mission GLOBALS `_ct_cursed_chest_seq`/`_ct_cot_block_last` shared with main-file setup_run reset - stay globals, never localized (combat-hooks cross-file contract). #471 (v0.7.248): the spawn hook now also emits `[ct:471] cot_spawn` (raw printf: `pre_req`/`built_req`/`placed`) per cursed-chest element; scale reads `element.difficulty_amount` (vanilla `terror_event_mixer.lua:97-131`), actual spawns = `#event.spawn_positions` after the run fn (`:1043`) - a placed<built_req gap = position-finder/budget cap, not a scale miss. `cursed_chest_elites` category is diagnosed but NOT scaled today |
| `TerrorEventUtils.apply_breed_enhancements` [hook,tbl] `:8916` / `EnemyPackageLoader.setup_startup_enemies` [hook] `:5261` | Apply per-difficulty breed enhancements / preload the mission's breed packages | Breed-enhancement tuning, force-load breeds for injected levels | Terror-event files capture `TerrorEventUtils.*` as upvalue at BOOT before mods load - mutate the data it READS at call time, not the captured upvalue (CLAUDE.md upvalue-capture; the v0.7.76 grudge-mark failure) |

### Surface 4 - Adventure-maps-in-CW: levels, flow-state, pickups, camera (owner: `docs/engine/07`, `/08`; `chaos_wastes_tweaker_dev.lua`, `_adventure_pool.lua`)

| Class.method (kind) | Vanilla behavior | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `NetworkedFlowStateManager.clear_object_state` [hook] `:5764` | Nils `_object_states[unit]` on unit destroy but NEVER decrements `_num_states` [src: `networked_flow_state_manager.lua:493-495`] | Count the states being released and subtract BEFORE delegating - fixes the monotonic `_num_states` leak that fatals at 512 (`flow_cb_create_state` asserts `< _max_states`) | Vanilla BUG ct patches; `hook_safe` can't work - vanilla nils the table before the hook fires, leaving nothing to count (DEVELOPMENT "NetworkedFlowStateManager leak"); worst offender is the cursed-chest objective_unit spawn |
| `NetworkedFlowStateManager.flow_cb_create_state` [hook] `:5810` | Creates a networked flow state; asserts `_num_states < _max_states` [src: `:379-406`] | Companion observation / guard for the leak fix | Paired with `clear_object_state` above |
| `PickupSystem.populate_pickups` [hook] / `_spawn_pickup` [hook] / `_spawn_guaranteed_pickup` [hook] / `_can_spawn` [hook] | Level-startup pickup spawner init, spawn one pickup, guaranteed pickup, spawn-eligibility gate [src: `pickup_system.lua:395-633,821-844,1208-1306`] | Spawn CW pickups on adventure-injected levels; campaign-potion weight renorm; tome/grim protection; #351 converts `loot_die`, `lorebook_page`, and `painting_scrap` to coin at the server-only pickup boundary | Pre-flight `_pickup_unit_loadable` via `Application.can_get("unit",name)` before spawn - `holy_hand_grenade` is CW-package-only and fatals `World.spawn_unit` on adventure levels; pickup-sampler total must stay `>=1`; clients cannot own `_spawn_pickup` (`:1209-1214`) |
| `UnitSpawner.spawn_network_unit` [hook] | Owner path creates the local unit/extensions, marks it non-husk, and serializes its game object; clients later build husks from that object [src: `unit_spawner.lua:336-352,470-490`] | #351 catches chest bonus dice, whose server interaction bypasses PickupSystem and calls this seam directly with `pickup_name=loot_die` [src: `interactions.lua:2112-2138`], then rewrites unit/template/init identity to native Pilgrim's Coin | Exact collectible identity + injected-CW + `self.is_server` only; copy the init tables instead of mutating the caller; clients receive the final coin identity and never decide independently |
| `DeusCursedChestExtension.extensions_ready` [safe] `:4734` + delayed pickup census `:4647` | Extension seam fires once for every live cursed chest regardless of spawn path. `_spawn_pickup` synchronously calls `UnitSpawner.spawn_network_unit` -> `create_unit_extensions` -> `EntityManager2.add_unit_extensions` -> `extensions_ready` before returning [src: `deus_cursed_chest_extension.lua:39-51`, `pickup_system.lua:1208-1274`, `unit_spawner.lua:327-352`, `entity_manager2.lua:120-176`] | #132 per-chest ground truth; #349 settled Mission-of-Mercy count classification | Never compare the in-hook pickup census as final: CT's `_spawn_pickup` post-hook has not resumed yet. Classify only from the existing delayed census after the spawn pass; compiled level-unit flags are outside the Lua source dump |
| `GearUtils.create_equipment` [hook] `:6628` | Builds the in-world equipment record + spawns 1p/3p units for a slot [src: `gear_utils.lua`] | Recover `career_name` + pre-resolve `override_item_units` so bots with DLC-career weapons don't crash on missing units on injected levels | Read career from `inventory_system._career_name`, NOT `player:owner()` (nil at mission-spawn timing, CLAUDE.md in-mission caveat); cross-ported from wt's ghost-scythe fix (AUDIT_FINDINGS "ghost-scythe") |
| `CameraManager.shading_callback` [safe] `:6008` / `_gmh get_object_sets` [hook] `:5046` | Per-frame shading-env callback / resolve a level's object sets | Curse light tinting on injected levels (adventure bundles lack per-god sky); object-set substitution | Undefined shading-env VARIATION is an uncatchable AV (§22, memory `reference_vt2_shading_env_variation_blend_av`); a `mod.update`/draw touching a dead `level_world` is an uncatchable AV (§32) |
| **Table contact (NOT hooks):** `_adventure_pool.lua` `inject_pool()` writes `LevelSettings[<key>]` + `LEVEL_AVAILABILITY.*` | `num_levels` = count of `LevelSettings` at join, folds into `combined_hash` | Inject Adventure missions x 6 themes into TRAVEL/SIGNATURE pools with `_dupN` safety aliases | STICKY - can't un-register; toggling OFF mid-session does NOT reduce `num_levels` (restart only); ARENA/SHOP/finale/Belakor node types NEVER touched (`_adventure_pool.lua` header) |

### Surface 5 - Economy / traits / potions / lifecycle + peer-parity beacon (owner: `docs/engine/11`, `/03`; `chaos_wastes_tweaker_dev.lua`, `_lib_peer_parity.lua`)

| Class.method (kind) | Vanilla behavior | Why ct hooks it | Trap / invariant |
|---|---|---|---|
| `DeusRunController.on_soft_currency_picked_up` [hook] `:653` | Awards soft currency (coins) on pickup; server-branch skips counters when 2nd arg is nil | Coin multiplier / economy tuning | Boon-count detection by value-range scan `[1,10]` not fixed arg index (defends signature drift, AUDIT_FINDINGS #3) |
| `_G Localize` [hook] `:5185` | Global loc-key -> string lookup; returns `<key>` for unknown keys | Supply display names/descriptions for `ct_*`/`power_up_ct_*` boon + miracle keys | VMF `_localization.lua` is NOT registered into global `Localize` (memory `reference_vmf_localize_before_registration`); resolve `DeusPowerUpTemplates[name].display_name` through the wrapped call |
| `VMFOptionsView.callback_setting_changed` [hook] `:12866` | VMF settings-menu value-change callback | Mutex-cluster (Miracle of Isha A/B) + re-apply per-boon tweaks + re-sync host-dependent state on edit | `cb_<setting>` takeover pattern (memory `reference_vt2_optionsview_synthesized_cb_takeover`); the sync fan-out (`sync_host_dependent_state`) re-runs pool registration, so it MUST route through the parity-guarded `_add_dormant_to_pool` |
| `PlayerBotBase.update` [safe] `_ct_blessed_bots.lua:99` | Per-tick bot brain update (host-authoritative; bots only exist on host) | Blessed Bots: grant 3 CW survival boons to every bot in ANY game mode (EXPERIMENTAL) | The mod's ONLY `PlayerBotBase.update` hook - throttled, idempotent; additively mirror `DeusPowerUpBuffTemplates`->`BuffTemplates` so boons resolve outside a CW run (`BuffUtils.get_buff_template` reads only `BuffTemplates`, `buff_utils.lua:257`); host-only |
| **Per-boon table tweaks (NOT hooks):** `DeusPowerUpTemplates.<boon>.buff_template.buffs` mutations | Boon buff data (Reckless Swings, movespeed, Ulric pack range, poison-proof, invis potion, Moot Milk, Shard Strike, Anath Raema, Khaine's Fury) | Save-and-restore around boon rolls; per-boon numeric tuning | Reckless Swings uses hard-coded `buffs[1]`/`description_values[1]/[3]` (fragile if Fatshark reorders, AUDIT_FINDINGS #1); save-restore is NOT `pcall`-protected - a wrapped-fn throw persists the mutation (CODE_REVIEW §4) |
| `[rpc]` `ct_peer_parity_present` (via `_lib_peer_parity.lua`) + `ct_graph_snapshot_chunk` `:6395` + `ct_sync_host_settings_chunk` + `ct_altar_uncollect` + `ct_peer_manifest_chunk` [rpc] | - | Peer-parity beacon (#426), graph snapshot, host-settings sync, altar un-collect, `/peers` manifest dump | VMF `network_send` is delivered ONLY to peers with the SAME mod-id + matching handler = presence proof; chunk at <=400 chars (500 engine cap, memory `reference_vmf_rpc_string_cap`); the manifest is a DIAGNOSTIC, the beacon is the live gate; NEVER add a key to a vanilla NetworkLookup or ride a vanilla RPC (wire-safe by construction) |

## Subsystem notes (how the vanilla flow runs end-to-end, for ct's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### The Deus run layer + modded-content wire exposure (owner: `docs/engine/11`, `/03`; the #426 five-gate surface)

A CW run's per-player state (granted power-ups, persistent buffs, career) lives in
`DeusRunController`'s run-state, which syncs to peers by ENCODING each power-up's
`NetworkLookup.deus_power_up_templates[name]` index [src:
`deus_run_state_spec.lua:60` encode / `:85` decode]. Buff application rides a
parallel path: `buff_system:add_buff` server-side broadcasts `rpc_add_buff` with
`NetworkLookup.buff_templates[template_name]` [src:
`buff_system.lua:302-308`], the receiver decodes the index [src: `:430`], and a
joining peer gets every live server-controlled buff re-sent on hot-join [src:
`:66-97`]. `NetworkLookup` uses a STRICT error `__index`, so an index a peer's
table lacks is a fatal decode, not a nil (§31).

ct registers its modded boons (`power_up_ct_boon_*`, `ct_meta_*`, `ct_kill_heal`)
and miracles (`ct_miracle_*`) into those lookups UNCONDITIONALLY - index parity
across ct peers requires it (the v0.7.67 split: registration is unconditional,
POOL insertion is toggle-gated). But ct's `create_network_hash` shim deliberately
admits NON-ct peers, so once a modded boon is GRANTED or a modded buff APPLIED,
the modded index rides the vanilla wire to a peer whose `NetworkLookup` never had
it -> CTD. This is a GAMEPLAY axis (the substitute would change what happens), so
per the issue-371 map it cannot be substituted - the content must go INERT while
any peer lacks ct (`docs/engine/03` §31, project `project_vt2_cross_peer_wire_safety`).

The gate (v0.7.240-dev) is the shared peer-parity beacon (`_lib_peer_parity.lua`,
a verbatim copy of the master; edit the master and re-copy). Five surfaces, all
tagged `[ct:426]`: (1) POOL eject/inject around `DeusPowerUpRarityPool` with a
load-time initial eject; (2) the GRANT filter inside the consolidated
`DeusRunController.add_power_ups` hook; (3) the STARTING-boon filter in
`_add_initial_power_ups`; (4) MIRACLES degrade to the vanilla blessing in
`_try_buy_blessing`; (5) a debounced (15s) PARITY-LOSS strip. The 15s debounce
MUST exceed the beacon's 10s announce cadence: VMF's `network_send` silently skips
peers whose VMF handshake is still in flight, so a ct friend's first announce can
be lost and the retry is the only delivery - a shorter grace would nuke the
lobby's boons on an ack-in-flight transient (DEVELOPMENT "Peer-parity wire safety").

### Boon/power-up pool + dual-table registration (owner: `docs/engine/10`)

`DeusPowerUpBuffTemplates` is merged into the global `BuffTemplates` at boot [src:
`morris_buff_settings.lua:7310`], and `BuffUtils.get_buff_template` reads ONLY
`BuffTemplates` [src: `buff_utils.lua:256`]. So a boon injected at runtime into
`DeusPowerUpBuffTemplates` alone appears in the pool but crashes on first apply
(`buff_extension.lua:177`, "index a nil value") - ct writes BOTH tables. Valid boon
rarities are `{event, rare, exotic, unique}` [src: `deus_power_up_settings.lua`];
`common`/`plentiful` are weapon-drop tiers and crash the boon roller's
`existing_power_ups_lut` (built from `DeusPowerUpRarities`) at
[src: `deus_power_up_utils.lua:189`]. Every pool write funnels through
`_add_dormant_to_pool` because runtime callers keep re-running registration
(`sync_host_dependent_state` on every host-settings receipt, `on_setting_changed`
on every toggle edit), and each would otherwise silently undo the parity eject.

### Mutators, curses, and the sparse-rank breed hole (owner: `docs/engine/07`)

CW curses are `MutatorHandler` mutators. `initialize_mutators` runs server-only
[src: `mutator_handler.lua:48`] and calls each template's server
`initialize_function` [src: `:644-645`], which can reassign a rank-keyed data table
onto a `Breeds.*` entry. `mutator_curse_skulking_sorcerer` reassigns a `MAX_HEALTH`
table spanning ranks 2..7 with NO rank-8 entry (its rank constants carry a
duplicate-key bug), and the base breed's read at [src: `conflict_director.lua:1948`]
has no fallback - so at cataclysm_3 (rank 8, reachable only via ct's progressive
difficulty) `max_health[8]` is nil, `GenericHealthExtension.init` throws mid
extension-add, and the half-built hit_reaction extension nil-derefs on the next
system update = host CTD (#470). ct's fix backfills `[8]=150` in a `hook_safe` on
`initialize_mutators`, unconditionally. The separate
`tweak_pack_spawning_settings` seam is a STATIC function (dot-called at
[src: `main_path_spawning_generator.lua:327`]) - see the arity-trap dead end below.

### Adventure maps in the CW graph + the lobby-hash constraint (owner: `docs/engine/08`, `/03`)

ct injects vanilla Adventure missions into the CW node pools by writing
`LevelSettings[<key>]` + `LEVEL_AVAILABILITY.*`. Two vanilla facts make this hard.
First, `num_levels` (count of `LevelSettings`) folds into the lobby `combined_hash`,
computed BEFORE any peer-to-peer or VMF sync (`LobbyAux.create_network_hash`), so a
host with injection on (~774 levels) and a vanilla joiner (582) mismatch unless the
shim admits them - and `LevelSettings` mutations are STICKY (only a restart reverts
`num_levels`). Second, `deus_populate_graph` picks levels/curses/themes by INDEX
into the availability arrays ct mutated, so the same seed produces DIVERGENT
per-node picks across peers with different toggle state. That can't be settings-
resynced (the array length is already sealed into the hash), so the host broadcasts
its RESOLVED graph and clients overwrite in place (`ct_graph_snapshot_chunk`), with
a late-arrival re-apply at `DeusMapScene.on_enter` (DEVELOPMENT "Graph-snapshot RPC").
Separately, the long-run `NetworkedFlowStateManager` `_num_states` leak (vanilla
never decrements on unit destroy) fatals at 512 - ct counts and subtracts in
`clear_object_state`; `docs/engine/08` owns the state-count model.

## What the engine will NOT let us do (dead ends, already paid for)

Distilled from `DEVELOPMENT.md`, `AUDIT_FINDINGS.md`, `CODE_REVIEW.md`, and
`docs/BUG_CLASSES.md` - do not re-discover these.

- **RESOLVED v0.7.241-dev (#356) - the `tweak_pack_spawning_settings` static-hook
  arity trap.** Vanilla `MutatorHandler.tweak_pack_spawning_settings` takes NO `self`
  (called dot-form at `main_path_spawning_generator.lua:327`, def
  `mutator_handler.lua:748`). Until v0.7.240-dev ct's hook `:5300` declared a spurious
  leading `self`, so VMF's arg pass shifted every parameter by one: `pack_spawning_settings`
  was ALWAYS nil (the strip's `missing_field` guard fired on EVERY call, not just the
  crash predicate), and the SIGNATURE-zone `zone_mutator_list` - the list `no_roamers`
  actually rides on CW signature zones (DEVELOPMENT "adventure mutators") - was the one
  list the filter never touched, because in the re-dispatch it landed as the leading
  (dropped-`self`) positional. Net: the `pairs(nil)` crash-guard (guid 4c84c68a) did not
  cover the zone it most needed to. FIX (v0.7.241-dev): dropped `self`, bound the 4 real
  params in vanilla order, filter BOTH lists. Behavioral arity lock in `/ct_regression_test`
  `no_roamers_strip_arity_356` (drives the real hooked fn with 4 positional sentinels;
  a self-shift regression leaks no_roamers -> `pairs(nil)` caught by pcall). Marker
  `CT_NO_ROAMERS_ARITY_FIX_MARKER`.
- **A modded index on a vanilla wire cannot be substituted, only gated.** A gameplay
  boon/buff/miracle whose effect depends on the modded template can't be swapped for
  a vanilla index without changing what happens - so under unconfirmed peer parity
  the content must go INERT, not substitute (§31, #426). Cosmetic axes (cwv skin
  ids) substitute; gameplay axes gate. This is the whole reason the five-surface
  beacon exists.
- **`LevelSettings` / `num_levels` cannot be host-synced or un-mutated in-session.**
  The lobby `combined_hash` is sealed before mod communication, and `LevelSettings`
  entries can't be cleanly un-registered from Lua (other systems hold references).
  You CANNOT make a `LevelSettings`-mutating feature "always sync to host"; the only
  patterns are lazy-inject-on-host, a clear toggle warning, or refactoring off
  `LevelSettings` entirely (DEVELOPMENT "Lobby combined_hash").
- **A boon rarity outside `{event, rare, exotic, unique}` crashes the roller far
  from the injection site.** `existing_power_ups_lut` is keyed by `DeusPowerUpRarities`;
  a `common`/`plentiful` boon indexes nil at `deus_power_up_utils.lua:189` only once
  it's actually rolled - many shrines later. Map any "tier 1" mental model to `rare`
  (DEVELOPMENT "Deus boon rarities").
- **A dormant boon in `DeusPowerUpBuffTemplates` alone crashes on first apply.**
  `BuffUtils.get_buff_template` reads only `BuffTemplates`; runtime injection must
  write both tables (DEVELOPMENT "dormant boons need dual-table writes").
- **`max_overcharge` above ~60 is an uncatchable network-bound fatal.** The bound
  lives in the compiled `.network_config`, not widenable from Lua; a capacity boon
  must use `reduced_overcharge` (per-cast, local) instead (DEVELOPMENT "max_overcharge").
- **Walk-through interactables need `filter_trigger`, NOT `scene_query_enabled=false`.**
  Disabling scene query breaks "press E" discovery (which uses an interaction-filter
  overlap query); reclassify actors as `filter_trigger` and leave scene query on.
  `Unit.actor` is 1-indexed (DEVELOPMENT "Walk-through pattern").
- **`hook_safe` cannot count a state vanilla already nilled.** The
  `NetworkedFlowStateManager` leak fix MUST be a full `mod:hook` - vanilla clears the
  object-state table before returning, so a post-callback sees nothing to subtract
  (DEVELOPMENT "NetworkedFlowStateManager leak").
- **Terror-event `TerrorEventUtils`/`BossGrudgeMarks` are captured as upvalues at
  boot.** By mod-load time the upvalue is stale; mutate the DATA the function reads
  at call time (`_G.BossGrudgeMarks`), not the captured function (v0.7.76 failure,
  CODE_REVIEW v0.7.89).
- **Save-and-restore around boon rolls is not exception-safe.** ~10 sites: if the
  wrapped vanilla fn throws before the restore line, the `DeusPowerUpTemplates`
  mutation persists for the session. No production crash cited; `pcall` would harden
  it (CODE_REVIEW §4, AUDIT_FINDINGS #9).

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a ct hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. Line numbers are against the 2026-07-12 decompile and `ct_dev`
module source - match crash logs by function name, not line. This documents
`chaos_wastes_tweaker_dev` (the active dev stream); never cite stable
`chaos_wastes_tweaker/` line numbers - promotion is user-triggered and the two
streams drift. `AUDIT_FINDINGS.md` (2026-05-13) and `CODE_REVIEW.md` (2026-05-23)
are SUPERSEDED snapshots whose line ranges predate the file-size refactor; their
FINDINGS (dead ends above) stand, their line numbers do not. Structural template is
`character_weapon_variants/ENGINE_SURFACE.md`; keep the section shape (hook table ->
subsystem notes -> dead ends) stable.
