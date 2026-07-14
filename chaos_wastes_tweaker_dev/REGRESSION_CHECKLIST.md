# Regression Checklist — chaos_wastes_tweaker

Subset of the monorepo [REGRESSION_CHECKLIST.md](../REGRESSION_CHECKLIST.md) — entries that apply to chaos_wastes_tweaker.

Walk every entry below before any release that touches the relevant subsystem. Pair with the repo-root `tools/lint/regression-lint.ps1` (STATIC items at build time) and the `/regression_test` chat command (UNIT/INTEGRATION items at runtime).

Last updated: 2026-07-13.

### parry-cooldown-deferred-contract - issue #342

| Field | Value |
|---|---|
| Symptom | Consecutive timed blocks retain the vanilla proc cooldown even though CT intends both parry boons to proc every time. |
| Root cause | The boon-roll hook referenced a function local to another Lua chunk as a bare global; `pcall(nil)` swallowed the scope failure. |
| Fix version(s) | ct_dev 0.7.269-dev |
| Category | SOLO |
| Repro | Acquire `static_blade` or `boon_skulls_03`, then make consecutive successful timed blocks. |
| Expected post-fix | The target template's `cooldown_buff` field is absent and each timed block may proc. |
| Detection | `/ct_regression_test` passes `parry_cooldowns_stripped_post_load`; contract failures emit bounded `[ct:342]` warnings. |

### anath-raema-registry-retry - issue #288

| Field | Value |
|---|---|
| Symptom | Permanent-reload rework remains the vanilla ammo-pickup event or has no active reload stat. |
| Root cause | Startup mutation could see only one Morris registry, mark the work complete, and never patch the later runtime `BuffTemplates` registry; both saved originals also collided under one key. |
| Fix version(s) | ct_dev 0.7.268-dev |
| Category | SOLO |
| Repro | Enable the rework, wield an Anath Raema ranged weapon, and reload without collecting ammo. |
| Expected post-fix | The equipped trait instantiates `deus_ammo_pickup_reload_speed_permanent` with `reload_speed=-0.5`; reload hold time is approximately half the toggle-off baseline. |
| Detection | `/ct_verify_anath_raema` reports the permanent template and one active parent; `[ct:288]` confirms exact-boundary enforcement. `/ct_regression_test` passes `anath_raema_registry_retry_288`. |

### start-shrine-client-config-ordering - client receives SHOP before synthetic config

| Field | Value |
|---|---|
| Symptom | Co-op client crashes in `DeusShopView.start` when Buy Starting Boons opens on the `dlc_morris_map` start node; `_shop_config` is nil at vanilla lines 182-184. |
| Root cause | CT built the synthetic shop entry only after `GameModeMapDeus.local_player_game_starts` returned, but vanilla calls `full_sync()` inside that function and the client could consume the host's SHOP state first. |
| Mod(s) | chaos_wastes_tweaker_dev + shared peer-parity consumers |
| Fix version(s) | ct_dev 0.7.266-dev; parity copies crt 0.3.63-dev, cwv 0.1.399-dev, et 0.4.31-dev, wt 0.12.231-dev |
| Category | COOP |
| Repro | Host enables Buy Starting Boons, Rain joins with matching dev mods, start a new CW run and enter `dlc_morris_map`. |
| Expected post-fix | Both peers open the same start shrine, can buy and Ready back to MAP_DECISION, and neither log contains `_shop_config` nil. No four-mod parity disable/re-enable chat cycle occurs during the transition. |
| Detection | `/ct_regression_test` passes `issue458_start_shrine_config`; guard diagnostics `[ct:458] start shrine view blocked` are bounded to 4 and indicate fail-closed containment, not a successful verification. Offline Lua tests prove the 15-second same-peer ack retention boundary and that new/expired peers remain disabled. |

---
## Startup and network lookup bounds

### issue590-level-key-budget - Duplicate pool aliases exceed weight_array capacity

**[CRASH / STATIC + INTEGRATION]**

| Field | Value |
|-------|-------|
| Symptom | Game crashes during `StateLoadingRestartNetwork` with `Too many levels in LevelSettings, global.network_config value weight_array needs to be raised.` |
| Root cause | The 582-key vanilla prefix plus 35 adventure missions x 6 themes (210) plus 39 pool-floor aliases x 6 cloned permutations (234) reached 1,026 keys, exceeding the engine's 1,024-entry array. |
| Mod(s) | chaos_wastes_tweaker_dev |
| Fix version(s) | ct_dev v0.7.265-dev (#590) |
| Expected post-fix | Duplicate graph choices resolve through `LEVEL_ALIAS` and add zero network keys. The static catalog is 792/1,024 with 232 entries of headroom. |
| Automatic detection | Blocking `qa/check_level_lookup_budget.ps1`, wired into Quick/full QA and `publish-release.ps1`; `/ct_regression_test` additionally checks the six-theme alias mapping. |
| Runtime-only verification | With one Adventure mission enabled and the CW pools filtered enough to create 39 aliases, restart the game, reach the Pilgrimage Chamber, and launch a run that repeats the enabled mission. Confirm no network-constants assert and confirm the repeated mission keeps its rolled theme/path. After a VT2 update, compare the logged vanilla lookup prefix with the gate's pinned 582 baseline. |

---
## UI layout

### kill-heal-modded-boon-catalog - Khaine's Communion absent from expected Starting Boons category

**[INTEGRATION]**

| Field | Value |
|-------|-------|
| Symptom | Khaine's Communion cannot be found under Modded Boons when configuring Starting Boons for Single Mission Loader, despite the log reporting `start_boon_ct_kill_heal get=0`. |
| Root cause | v0.7.264 corrected the invisible BOON_TREE ancestry from Defensive > Health to `mod_boons`, but that category's player-facing label remained the obsolete **New Scaling Boons** name from v0.7.30. Khaine's Communion is not a scaling boon, so structural presence did not make its navigation route discoverable. |
| Mod(s) | chaos_wastes_tweaker_dev |
| Fix version(s) | ct_dev v0.7.264-dev (catalog ancestry); v0.7.267-dev (realized navigation contract) |
| Category | INTEGRATION / MENU CATALOG |
| Repro | In the Pilgrimage Chamber, open Mod Tweaker > Tweaker: Chaos Wastes > Starting Boons > Modded Boons before launching Single Mission Loader. |
| Expected post-fix | `(Mod Boon) Khaine's Communion` appears exactly once under the visibly named Modded Boons category on both Disabled Boons and Starting Boons surfaces, and nowhere under a vanilla family. Selecting it grants the existing `ct_kill_heal` power-up; no duplicate definition exists. |
| Detection | `/ct_regression_test`: `issue406_kill_heal_mod_boon_catalog` checks realized labels plus ancestry. Offline `test_ct_boon_catalog` executes both builders. Then a client kill with the boon must not crash with `Only server can heal`. |

### cw-tab-collectible-safe-reflow - Injected DEUS counters cross the Tab overlay edge

**[INTEGRATION]**

| Field | Value |
|-------|-------|
| Symptom | Chests-of-Trials / Pilgrim's-Coin rows injected into the Chaos Wastes hold-Tab pane extend beyond the screen or safe rectangle. |
| Root cause | The #533 copy of vanilla's widget forced 0.6 icon scale at pre-scenegraph build time while retaining unscaled text and offsets; it did not measure localized labels or consume resolution, UI scale, banner bounds, or the safe rectangle. |
| Mod(s) | chaos_wastes_tweaker_dev |
| Fix version(s) | ct_dev v0.7.262-dev (#571) |
| Category | INTEGRATION |
| Repro | Enter an injected Adventure mission in a CW run; hold Tab at 16:9 and ultrawide, then repeat with non-default HUD/UI scale and safe rectangle. Collect enough coins/chests to change both counts. |
| Expected post-fix | The native right-banner bound is preserved. Two measured cells share a row when they fit and wrap to one column otherwise; lower safe inset and Collectibles divider are respected. Counts remain live. Vanilla CW content and stock Adventure collectible widgets are unchanged. |
| Detection | `[ct:571] collectible layout` reports the active contract. `/ct_regression_test`: `issue533_cw_tab_collectibles_wired` and `issue571_cw_tab_collectibles_safe_reflow` pass. |

---
## Localization

### generated-localization-percent-format - Builder emits an unescaped literal percent

**[UNIT]**

| Field | Value |
|-------|-------|
| Symptom | Startup emits one Crashify `string.format` exception per affected generated dropdown label. |
| Root cause | A localization builder returns a raw `%`; VMF formats localized option text and rejects it as an invalid format directive. Static checks limited to `*_localization.lua` do not see strings generated in another module. |
| Mod(s) | chaos_wastes_tweaker_dev |
| Fix version(s) | ct_dev v0.7.260-dev (#564) |
| Category | UNIT |
| Repro | Open Mod Options with CT dev enabled and inspect the Single Mission Loader's Run Progress dropdown. |
| Expected post-fix | All five labels render with one literal `%`; startup contains no `Invalid string format` exception for `ctdm_p_1` through `ctdm_p_5`. |
| Detection | `/ct_regression_test`: `localization_format_safe` and `mission_catalog_localization_format_safe_564` both pass. |

### single-mission-loader-context-and-composition - Loader exposes invalid controls or launches outside the chamber

**[INTEGRATION]**

| Field | Value |
|-------|-------|
| Symptom | Loader can replace an active run, offers invalid path/theme combinations, omits Adventure missions, or applies only one obsolete blessing instead of the configured Starting Boons. |
| Root cause | The original debug UI exposed graph-internal Travel/Signature, theme, and path fields independently and gated on any active Deus mechanism rather than the keep's physical Pilgrimage Chamber. |
| Mod(s) | chaos_wastes_tweaker_dev |
| Fix version(s) | ct_dev v0.7.261-dev (#505) |
| Category | INTEGRATION |
| Repro | In Mod Options inspect Single Mission Loader, then try its hotkey (1) in the ordinary keep, (2) in `morris_hub`, and (3) inside a CW mission. Repeat in the chamber with a Helmgart, DLC, Event, and normal CW selection, with and without a curse and with several Starting Boons selected. |
| Expected post-fix | Only case 2 launches. Mission filters use user-facing families. There are no Theme, Path Variant, or Starting Blessing selectors. Curse chooses its matching theme, None uses Wastes, a valid vanilla path is selected, Run Progress stays independent, and all selected Starting Boons are granted at run setup. |
| Detection | `/ct_regression_test`: `single_mission_loader_redesign_505` and `mission_catalog_localization_format_safe_564` pass. Runtime emits `[ct:505] single_mission_load ... starting_boons=N`; rejected locations show the Pilgrimage Chamber message and do not transition. |


---
## Multiplayer / Network Sync

### gated-registration-divergence — Toggle-gated mod-load registration produces different network indices across peers

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client crash `network_lookup.lua:2514: Table buff_templates/inventory_packages/level_keys does not contain key: <N>` when host fires `rpc_add_buff` or sets a shared state from a feature the host toggled but the client didn't. |
| Root cause | Mod-load registration into `_G.BuffTemplates` / `DeusPowerUpBuffTemplates` / `DeusPowerUpTemplates` / `NetworkLookup.*` / `LevelSettings` gated on a per-user setting → different subsets registered per peer → indices drift. |
| Mod(s) | chaos_wastes_tweaker, cosmetics_tweaker, weapon_tweaker, character_weapon_variants, buff_tweaker, enemy_tweaker, career_tweaker |
| Fix version(s) | ct v0.7.60 (dormants), ct v0.7.61 (trait boons), ct v0.7.62 (adventure levels), cosmetics_tweaker v0.8.66 (LA shields), crt v0.3.3-dev (22 talent-rework buffs), bt v0.1.1-alpha |
| Category | INTEGRATION |
| Repro | 1. Player A enables a setting-gated feature that injects new buffs/boons/levels (e.g. ct's `activate_dormant_*` or `inject_adventure_maps`). 2. Player B installs the same mod with the feature OFF. 3. Player A hosts a CW run / adventure. 4. Player B joins and plays until host applies the gated buff (or until an injected level loads). |
| Expected post-fix | All four players' indices match. No `does not contain key` crash on the client. Host's rpc_add_buff resolves to the correct buff name on every client. |
| Detection | Console log on client side. Search for `Table .* does not contain key:` or any `network_lookup.lua:2514`. Should be absent. |


---

### vmf-network-send-recipients — `"server"` recipient is silently dropped

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Client emit log fires, host receive log never fires. No error, no warning. |
| Root cause | VMF's `convert_names_to_numbers` accepts only `"all"`, `"others"`, `"local"`, or a literal peer_id. `"server"` / `"host"` / `"clients"` fall into else branch and are treated as a literal peer_id; `_vmf_users[peer_id]` lookup fails; `send_rpc_vmf_data` returns silently. |
| Mod(s) | cosmetics_tweaker, chaos_wastes_tweaker, any mod with client→host RPCs |
| Fix version(s) | cosmetics_tweaker v0.9.0.15-hotfix |
| Category | INTEGRATION |
| Repro | 1. Friend hosts a lobby. 2. You join as CLIENT. 3. Perform an action that should send an RPC to the host (e.g. cosmetics_tweaker LA cosmetic apply). |
| Expected post-fix | Host receives the RPC; you see the action reflected on the host's screen (and on other clients via host re-broadcast). |
| Detection | Add `mod:info("[emit] CLIENT->req")` before the send and `mod:info("[recv]")` at the receiver. Recv must fire when the test runs with you as client. |


---

### ct-graph-snapshot-rpc — Different peers generate different CW maps when load-time toggle mutates LevelSettings

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Host and client see different per-node levels / curses / themes on the CW map despite using same seed. |
| Root cause | `inject_adventure_maps` mutates `LEVEL_AVAILABILITY.TRAVEL/SIGNATURE/ARENA` at module-load. Vanilla `deus_populate_graph` indexes into those arrays. Same seed × different arrays = different per-node picks. Toggle can't be runtime-resynced because `#NetworkLookup.level_keys` folds into lobby `combined_hash`. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.64 |
| Category | INTEGRATION |
| Repro | 1. Host enables `inject_adventure_maps`. 2. Client installs ct without that toggle. 3. Host starts a CW run. 4. Compare each peer's map view. |
| Expected post-fix | Client's map snapshot is overwritten by host's broadcast; node levels/themes/curses agree. Late-arrival re-apply happens at `DeusMapScene.on_enter`. |
| Detection | Each player runs `/ct_dump_graph` (or visually inspects the map nodes). Maps must match. |


---

### vt2-lobby-combined-hash — Mods that grow LevelSettings break lobby join

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Joiner gets `Join failed - Game version mismatch` popup; chat shows `[ChatManager][1]System` mismatch. |
| Root cause | Lobby `combined_hash` includes `num_levels` (count of LevelSettings entries). Mods that register new levels post-boot raise `num_levels` per-peer; if one side has the feature on and the other off, hashes differ. LevelSettings entries cannot be cleanly un-registered — game restart required to revert. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | Documented; mitigation = restart game after toggling. |
| Category | MANUAL |
| Repro | 1. Player A enables ct `inject_adventure_maps`. 2. Player B has ct disabled or feature off. 3. Either tries to join the other's lobby. |
| Expected post-fix | If host warning surfaces in UI, friends can avoid the mismatch by restarting after toggling. Console `Making combined_hash:` lines should print same num_levels on both peers. |
| Detection | `console-*.log` grep for `Making combined_hash:`; compare `num_levels=` between host and client. |


---

### vt2-mutator-template-server-wrap — Dead-field hook silently no-ops

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Mutator-template hook compiles and registers without error but never affects gameplay. |
| Root cause | `mutator_templates.lua:236-269` wraps each `server_start_function`/`server_stop_function`/etc. into `template.server.start_function`/`template.server.stop_function` closures at boot. The flat `server_start_function` field is dead after wrap; hooking it silently no-ops. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.66 (pre-deploy QA catch) |
| Category | STATIC |
| Repro | (No live repro — caught by code audit before deploy.) |
| Expected post-fix | Mutator lifecycle hooks target `template.server.start_function` (etc.), not `template.server_start_function`. |
| Detection | Grep mod sources for `mod:hook.*server_start_function`. Should be absent (use `template.server.start_function` instead). |


---

### vt2-networked-flow-state-leak — Vanilla bug fatals at 512 networked flow states

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Engine fatal `[NetworkedFlowStateManager] Too many object states(512).` after a long session, most often CW with multiple cursed chests. |
| Root cause | Vanilla `NetworkedFlowStateManager.clear_object_state` nils `_object_states[unit]` but never decrements `_num_states`. Counter is monotonic. Worst offender: CW cursed_chest_objective_unit buff applied to every cursed-chest enemy. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.3-alpha |
| Category | INTEGRATION |
| Repro | 1. Enable ct + `inject_adventure_maps`, `cursed_chest_count > 1`. 2. Play a long CW run (~30-60 min) with many cursed-chest enemy spawns. 3. Watch for crash near `_num_states` cap. |
| Expected post-fix | ct's hook on `clear_object_state` decrements `_num_states` by the count of states being released. Run completes without the 512 fatal. |
| Detection | `/regression_test` in ct checks the patch is wired. In long sessions, dump `_num_states` via `/ct_flow_states` (if available). |


---

### cross-mod-br-registration-sync — Subset divergence across BR-aware mods

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Player A (wt+ct+et installed) gets different NetworkLookup buff indices than Player B (only ct installed). Host's rpc_add_buff resolves to wrong buff on client. |
| Root cause | wt/ct/et each pre-register Big Rebalance templates at mod load. If their lists differ (subset vs full union), peer indices drift. |
| Mod(s) | weapon_tweaker, chaos_wastes_tweaker, enemy_tweaker, buff_tweaker |
| Fix version(s) | buff_tweaker v0.0.1+ (consolidated registration via single bt master); also see byte-identical canonical lists shipped 2026-05-21. |
| Category | STATIC |
| Repro | (Lint-checkable via diff of `*_big_rebalance_registrations.lua`.) |
| Expected post-fix | Each BR-aware mod ships byte-identical sorted canonical list, OR all peers consume bt for BR registration. |
| Detection | Diff `wt/scripts/.../weapon_tweaker_big_rebalance_registrations.lua` against ct/et equivalents — only filename comment and `local mod = get_mod(...)` should differ. |


---

### vt2-dormant-buff-template-dual-register — Runtime-injected boons crash on apply

**[MULTIPLAYER]**

| Field | Value |
|-------|-------|
| Symptom | Crash `buff_extension.lua:177 attempt to index local 'buff_template' (a nil value)` the first time an injected boon is rolled and applied. |
| Root cause | Vanilla merges `DeusPowerUpBuffTemplates` → `_G.BuffTemplates` once at boot (via DLCUtils). Mods load AFTER that merge. Writing only to `DeusPowerUpBuffTemplates` at runtime leaves `BuffTemplates` un-aware; `BuffUtils.get_buff_template(name)` returns nil. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.32 |
| Category | INTEGRATION |
| Repro | 1. Toggle an `activate_dormant_*` boon in ct settings. 2. Start CW run. 3. Trigger a shrine/altar that can roll the newly-activated boon. 4. Apply it. |
| Expected post-fix | Mod writes to BOTH `DeusPowerUpBuffTemplates[name]` AND `_G.BuffTemplates[name]`. Boon applies without crash. |
| Detection | `/regression_test` in ct includes a dual-table buff-write check. |


---

### vt2-deus-power-up-rarities — Common-rarity boons crash CW shrine roll

| Field | Value |
|-------|-------|
| Symptom | Crash `deus_power_up_utils.lua:208 (live :189) attempt to index a nil value` during `generate_random_power_up`. Locals show offending `power_up.rarity = "common"`. |
| Root cause | `DeusPowerUpRarities = {"event","rare","exotic","unique"}` only. `common`/`plentiful` are weapon-drop rarities; injecting a boon at common rarity fails the LUT build at file load. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.37 (remapped squats, deus_larger_clip to rare) |
| Category | STATIC |
| Repro | 1. Inject any custom boon at `rarity = "common"` or `"plentiful"`. 2. Start CW run. 3. Roll the boon at a chest/shrine. |
| Expected post-fix | All mod-injected boons use only `event`/`rare`/`exotic`/`unique`. No crash on roll. |
| Detection | Lint: grep mod source for `rarity = "common"` / `rarity = "plentiful"` inside ct boon injection blocks. |


---

### vt2-adventure-pack-spawning-compat — `no_roamers` mutator crashes on adventure-injected levels

| Field | Value |
|-------|-------|
| Symptom | Crash `mutator_no_roamers.lua:6 bad argument #1 to 'pairs' (table expected, got nil)` on first SIGNATURE-zone load of a CW run that landed on an adventure-injected level. |
| Root cause | CW pacing mutator `no_roamers` does `pairs(pack_spawning_settings.difficulty_overrides)`. Vanilla `chaos_light` PackSpawningSettings entry lacks that field — fine on its native campaign use, but on CW adventure-injected nodes it surfaces. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.41 |
| Category | INTEGRATION |
| Repro | 1. Enable `inject_adventure_maps`. 2. Start a CW run, navigate to a SIGNATURE node (the modifier zone). 3. Land on an adventure-injected level (any campaign mission added to the pool). |
| Expected post-fix | Mod hooks `MutatorHandler.tweak_pack_spawning_settings` and strips `no_roamers` from zone-mutator lists when the level is adventure-injected. Vanilla CW levels stay untouched. |
| Detection | `/regression_test` in ct verifies the strip hook is wired. |


---

## Cosmetics / LA / CWV / Engine Bugs

### vt2-lua-200-locals — Lua 5.1 main-chunk 200-local limit hit on large files

| Field | Value |
|-------|-------|
| Symptom | Stingray compile error `main function has more than 200 local variables`. |
| Root cause | Lua 5.1/LuaJIT 200-local-per-function cap, including top-level chunk. Large mod files accumulate past this. |
| Mod(s) | character_weapon_variants, chaos_wastes_tweaker |
| Fix version(s) | CWV v0.1.304 |
| Category | STATIC |
| Repro | 1. Add many top-level `local function`/`local var =` declarations until file has 200+. 2. Build. |
| Expected post-fix | Wrap helper-function groups in `do ... end` scopes so their locals release back to the main chunk. |
| Detection | Build the mod with `vmblauncher build`. If "main function has more than 200 local variables" appears, wrap groups in do/end. |


---

### vt2-jewelry-traits-become-cw-boons — Necklace/charm/trinket traits ARE CW boons

| Field | Value |
|-------|-------|
| Symptom | Confusion about whether Decanter / Home Brewer / Barkskin / etc. are "weapon traits" or "boons" — they're boons in CW. |
| Root cause | All necklace/charm/trinket traits register as boons in `DeusPowerUpTemplates`. Weapon traits stay weapon traits in both modes. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | 1. Open ct disable-boon menu. 2. Look at boon list. 3. Note Decanter et al. live there. |
| Expected post-fix | Mod descriptions / UI label them as boons in CW context. |
| Detection | `/dump_boon_loc` in ct should show jewelry traits in the boon list. |


---

### vt2-unit-actor-one-indexed — Unit.actor iteration must start at 1

| Field | Value |
|-------|-------|
| Symptom | Collision/scene-query disable silently no-ops; players still bumped by altar/chest collider on injected adventure levels. |
| Root cause | `Unit.actor(unit, i)` is 1-indexed. Iterating `for i = 0, num_actors - 1` returns nil at index 0 and skips the final actor. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.6.19 |
| Category | STATIC |
| Repro | 1. Iterate `for i = 0, Unit.num_actors(unit) - 1 do ... end`. 2. Walk into the altar. 3. Get blocked. |
| Expected post-fix | `for i = 1, Unit.num_actors(unit) do ... end`. |
| Detection | Lint: grep mod sources for `for i = 0,` followed by `Unit.actor(`. |


---

### vt2-max-overheat-modifier-unified — `max_overcharge` (not `max_overheat_modifier`) is the stat_buff key

| Field | Value |
|-------|-------|
| Symptom | Boon advertising "+5% max overheat" has no effect, OR Sienna staff/Bardin drakefire crashes at `_calculate_and_set_buffed_max_overcharge_values` with `Max overcharge outside value bounds allowed by network variable!`. |
| Root cause | Wrong stat_buff key won't fire. Correct key is `max_overcharge`. Also: bound is ~60 (engine .network_config) — exceeding crashes. Use `reduced_overcharge` instead for "more comfortable casting" semantics. |
| Mod(s) | chaos_wastes_tweaker |
| Fix version(s) | ct v0.7.80-alpha |
| Category | INTEGRATION |
| Repro | 1. Add `{ stat_buff = "max_overcharge", multiplier = 0.05 }` and stack to 12 boons. 2. Equip Sienna staff. 3. Watch crash at 64/60 cap. |
| Expected post-fix | Use `reduced_overcharge` with negative multiplier for safe stacking. |
| Detection | `/regression_test` in ct checks the buff key. |


---

## Localization / UI

### vmf-dropdown-options-mutated — Multi-angle-bracket cascades from shared options table

| Field | Value |
|-------|-------|
| Symptom | VMF dropdown shows `<<key>>` or `<<<key>>>` cascades on second/third dropdown sharing an options table. |
| Root cause | VMF's `localize_dropdown_data` mutates `option.text` in place. Two dropdowns referencing the same options table get the first localized; the second tries to localize the already-localized string. |
| Mod(s) | enemy_tweaker, career_tweaker, any mod with multiple dropdowns of the same option set |
| Fix version(s) | enemy_tweaker v0.4.2-dev, crt v0.2.18-dev (talent-swap dropdown cascade) |
| Category | STATIC |
| Repro | 1. Define `local _SHARED = { { text = "off", value = "off" }, ... }`. 2. Use `options = _SHARED` on two different dropdown widgets. 3. Open settings. |
| Expected post-fix | Each dropdown gets its own options table (inline literal or factory function `_build_options()`). No bracket cascade. |
| Detection | Open mod's VMF settings UI; look for `<<...>>` text in any dropdown. Should be absent. |


---

### vmf-widget-id-unique — Duplicate setting_id breaks settings page

| Field | Value |
|-------|-------|
| Symptom | Mod's ENTIRE settings page disappears in VMF UI. Boot log: `Widgets N and M have the same setting_id`. |
| Root cause | VMF requires every widget's `setting_id` to be globally unique across the settings tree. Can't have one setting appear in two different category groups. |
| Mod(s) | chaos_wastes_tweaker, others |
| Fix version(s) | ct v0.7.26-test |
| Category | STATIC |
| Repro | 1. Duplicate any widget under two different groups (same setting_id). 2. Open settings. |
| Expected post-fix | Unique setting_ids only; use display-name prefixes for cross-cutting categorization. |
| Detection | Boot log grep for `same setting_id`. Should be absent. |


---

### vt2-localize-string-format-pipeline — Hand-written tooltip strings get `%%` formatted

| Field | Value |
|-------|-------|
| Symptom | Boon/talent/property tooltip shows `[Invalid String Format]` placeholder. |
| Root cause | `UIUtils.format_localized_description` runs `string.format` on every description. Literal `%` (e.g. `+25%`) is invalid format spec. |
| Mod(s) | chaos_wastes_tweaker, weapon_tweaker, general_tweaker, career_tweaker, lobby_tweaker |
| Fix version(s) | ct v0.5.2-dev, wt v0.12.63-dev, gt v0.2.35, crt v0.2.17-dev, crt v0.2.36-dev (34 crashify exceptions), lobby_tweaker v0.1.1-dev |
| Category | STATIC |
| Repro | 1. Add a description override with `25%` literal. 2. Open the tooltip in-game. |
| Expected post-fix | Escape literal `%` as `%%` in Localize hook overrides AND in `_localization.lua` strings (VMF's `safe_string_format` also routes through string.format). |
| Detection | Lint: grep mod localization files and Localize hooks for single `%` not followed by `s`/`d`/etc. format chars. |


---

### vt2-chat-command-syntax — Commands are `/<name>` directly, not `/<modid> <name>`

| Field | Value |
|-------|-------|
| Symptom | Documentation / Workshop description shows commands as `/wt dump` / `/cos probe_hat` — wrong; misinforms players. |
| Root cause | `mod:command("name", ...)` registers `/name` directly. Mod-id is internal identifier, not chat prefix. |
| Mod(s) | all |
| Fix version(s) | doc rule (audit 2026-05-19) |
| Category | STATIC |
| Repro | n/a |
| Expected post-fix | Every doc / cfg description / CHANGELOG references commands as `/<name>` directly. |
| Detection | Lint: grep `CHANGELOG.md` / `itemV2.cfg` / `*.md` for `/wt `, `/ct `, `/cos ` etc. before each command. Should be absent. |


---

### vt2-mod-command-inventory — Audit command name collisions

| Field | Value |
|-------|-------|
| Symptom | Two mods register the same `/name`; one shadows the other. |
| Root cause | Chat-command namespace is global. |
| Mod(s) | all |
| Fix version(s) | inventory snapshot 2026-05-19 |
| Category | STATIC |
| Repro | n/a |
| Expected post-fix | Cross-check every new `mod:command("name", ...)` against the monorepo inventory. Rename if collision. |
| Detection | Lint pass over all mod sources comparing `mod:command(` first args. |


---

## Build / Deploy / Workshop

### lua-forward-reference — Functions called before definition crash at runtime

| Field | Value |
|-------|-------|
| Symptom | Game crashes on first frame with `attempt to call global 'NAME' (a nil value)` from a function defined later in the file. |
| Root cause | Lua 5.1 does NOT hoist `local function` definitions. Shipped 6+ times in cosmetics_tweaker (v0.7.1, v0.7.37, v0.7.39, v0.7.51, v0.7.53, v0.8.39). |
| Mod(s) | cosmetics_tweaker, others |
| Fix version(s) | cosmetics_tweaker v0.8.40 (defensive `M.fn = function()` pattern) |
| Category | STATIC |
| Repro | (Static rule — any forward reference will crash on first use.) |
| Expected post-fix | All `local function NAME` definitions appear ABOVE every call site. For helpers that logically belong in a different section, hoist as `M.NAME = function()` on a module table. |
| Detection | `tools/lint/regression-lint.ps1` walks each mod's Lua and reports forward refs. |


---

### feedback-pre-deploy-checklist — Forgetting checklist costs ~2 min/restart per skipped check

| Field | Value |
|-------|-------|
| Symptom | (Same as lua-forward-reference.) Burned 5+ times in v0.7.x portrait work. |
| Root cause | No mandatory pre-deploy gate. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | (Process.) |
| Expected post-fix | Before EVERY build+deploy: (1) forward-reference audit, (2) MOD_VERSION bump, (3) changelog update, (4) bundle verification, (5) hash verification. |
| Detection | VMBLauncher build gate integrates lint suite. |


---

### ugc-tool-forward-slashes — `tags = [];` causes 0x2 first-upload failure

| Field | Value |
|-------|-------|
| Symptom | First upload of a new mod fails with `generic failure (probably empty content directory) (0x2)` even though staging is otherwise correct. |
| Root cause | `tags = [];` line in `itemV2.cfg`. ugc_tool adds that line itself after a successful first upload — pre-writing it causes the 0x2. |
| Mod(s) | every newly-created mod's first upload |
| Fix version(s) | vmb-launcher v0.2.8 |
| Category | STATIC |
| Repro | 1. Hand-write `itemV2.cfg` with `tags = [ ];`. 2. Run `vmblauncher upload <mod>` for first time. 3. Watch failure. |
| Expected post-fix | Don't include `tags = [];` in the staged cfg for first upload. (Also: disable Zapret if present.) |
| Detection | Audit cfg before first upload; ensure no `tags` line. |


---

### ps5-getcontent-utf8 — PS 5.1 Get-Content -Raw mangles UTF-8

| Field | Value |
|-------|-------|
| Symptom | Workshop description shows `â€¢` instead of `•` (and similar garbled multi-byte chars). |
| Root cause | PowerShell 5.1's `Get-Content -Raw` uses system code page (Windows-1252), not UTF-8. Multi-byte UTF-8 silently mangled. |
| Mod(s) | any mod whose cfg contains bullets / em-dashes / accented chars |
| Fix version(s) | _upload_helper.ps1 fix 2026-05-14 |
| Category | STATIC |
| Repro | 1. Put `•` in description in source cfg. 2. Run an upload via a tool using `Get-Content -Raw`. 3. Workshop page shows `â€¢`. |
| Expected post-fix | Use `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)` and `WriteAllText(... , [System.Text.UTF8Encoding]::new($false))` (no BOM). |
| Detection | After upload, verify Workshop page shows correct chars; or compute `xxd -p source.cfg | grep -o 'e280a2' | wc -l` and match against staged. |


---

### feedback-workshop-upload-verify — `Upload finished` lies; check workshop_log.txt + file size

| Field | Value |
|-------|-------|
| Symptom | User reports the mod hasn't changed despite multiple "successful" uploads. |
| Root cause | ugc_tool prints `Upload finished` on no-op. Steam logs `No content change detected` in `workshop_log.txt`. Workshop page `time_updated` doesn't bump on no-op. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | 1. Upload a mod whose bundle is byte-identical to Workshop. 2. Read "Upload finished" message. 3. Notice page didn't change. |
| Expected post-fix | After every upload, grep `C:\Program Files (x86)\Steam\logs\workshop_log.txt` for `Uploaded new content` (not `No content change detected`). For friends_only items, eyeball Workshop page file size. |
| Detection | Manual log check OR Workshop page file-size check after every upload. |


---

### feedback-workshop-upload-without-deploy — Author's local install stays stale

| Field | Value |
|-------|-------|
| Symptom | After uploading a new version, you restart VT2 and console still echoes the OLD version. |
| Root cause | Steam doesn't reliably re-download Workshop items the same Steam account authored. |
| Mod(s) | all |
| Fix version(s) | n/a — use `vmblauncher all` |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher upload <mod>`. 2. Restart VT2. 3. Watch console show old version. |
| Expected post-fix | Use `vmblauncher all <mod>` (build + deploy + upload) during iterative dev. |
| Detection | After every upload, restart VT2; console version matches bumped MOD_VERSION. |


---

### feedback-deploy-vs-upload-distinction — Local deploy doesn't reach subscribers

| Field | Value |
|-------|-------|
| Symptom | Friend / subscriber still reports old behavior; only the author's local install is updated. |
| Root cause | `deploy_all.ps1` only copies to LOCAL workshop folder. Subscribers get the version on Steam, which needs `upload`. |
| Mod(s) | all |
| Fix version(s) | n/a — use `vmblauncher all` |
| Category | MANUAL |
| Repro | 1. Run `vmblauncher deploy <mod>` only. 2. Friend reports no change. |
| Expected post-fix | Use `vmblauncher all <mod>` for changes intended to reach subscribers. |
| Detection | After every iterative fix, verify both the local file AND the Workshop page changed. |


---

### ugc-tool-pushes-all-cfg-fields — Every upload overwrites title/desc/preview/visibility

| Field | Value |
|-------|-------|
| Symptom | Workshop page title/description/preview reverts to whatever the local cfg says. |
| Root cause | ugc_tool reads `itemV2.cfg` and pushes EVERY field on every upload. Direct edits to the live Workshop page are reverted. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | 1. Edit live Workshop page directly. 2. Upload from local cfg. 3. Live page reverts. |
| Expected post-fix | Cross-check cfg vs live Workshop page BEFORE every upload. Ensure cfg's title/desc/preview/visibility reflect the desired live state. |
| Detection | Manual pre-upload audit. |


---

### vmblauncher-handscaffold-first-upload — Missing `item_preview.png` creates orphan Workshop items

| Field | Value |
|-------|-------|
| Symptom | First upload of a hand-scaffolded mod fails with `0x9` invalid preview file, but ugc_tool still created a Workshop item. |
| Root cause | vmblauncher does NOT synthesize a placeholder preview. ugc_tool creates the Workshop item BEFORE validating preview/content. On failure, item exists but isn't written back to cfg. |
| Mod(s) | every newly-scaffolded mod |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | 1. Hand-scaffold a new mod (skip `vmb create`). 2. Run `vmblauncher upload <mod>` without copying `item_preview.png`. 3. Watch failure. |
| Expected post-fix | Copy `vmb/.template-vmf/item_preview.png` into mod root BEFORE first upload. If failure occurs, capture orphan publisher_id from stdout, convert signed→unsigned, write `published_id = <N>L;` to cfg manually, then retry. |
| Detection | Verify `item_preview.png` exists in mod root before any first upload. |


---

### feedback-mod-version-format — Release-track suffix only (alpha/beta/dev)

| Field | Value |
|-------|-------|
| Symptom | Workshop title shows weird suffixes like `v0.9.9.1-revert` / `v0.9.8.7-revert` / `v0.7.81-hotfix`. |
| Root cause | Suffix should be track-only (`alpha`/`beta`/`dev`/`rc`). Change-descriptors belong in changelog, not version. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | STATIC |
| Repro | 1. Set `MOD_VERSION = "0.9.9.1-revert"`. 2. Run `vmblauncher all <mod>`. 3. See Workshop title carry the descriptor. |
| Expected post-fix | `MOD_VERSION = "X.Y.Z[.W][-alpha|beta|dev|rc]"`. No change descriptors. |
| Detection | Lint: grep each mod's `MOD_VERSION` for suffix tokens outside the allowed set. |


---

### feedback-redundant-safeguards-ok — Belt-and-suspenders dual-table writes are OK

| Field | Value |
|-------|-------|
| Symptom | (Not a bug — process note.) |
| Root cause | When redundancy is cheap and missed-path failure is silent, write to multiple tables / install multiple gates. Examples: dual buff registration (DeusPowerUpBuffTemplates + _G.BuffTemplates), late-arrival re-apply paths, idempotent registration. |
| Mod(s) | all |
| Fix version(s) | n/a — process rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Don't strip "redundant" safeguards without confirming the missed-path failure has actually been eliminated. |
| Detection | Code review process. |


---

### feedback-search-changelog-for-known-crashes — Grep CHANGELOG before theorizing

| Field | Value |
|-------|-------|
| Symptom | (Process rule.) |
| Root cause | Most surprising VT2 crashes have a documented prior fix. Searching memory + CHANGELOG.md before theorizing saves 1-2 wasted versions per crash. |
| Mod(s) | all |
| Fix version(s) | n/a |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Before theorizing about a crash, grep all `CHANGELOG.md` + `memory/` for the literal crash signature. |
| Detection | Process. |


---

### vt2-hash-reverse-lookup — Decipher `Resource '#ID[hash]' not found!` via murmur hash

**[GAME-PATCH-WATCH]**

| Field | Value |
|-------|-------|
| Symptom | `[Engine Error]: Resource '#ID[xxx]' was not found!` with no path. |
| Root cause | Hash is murmur64 of a Stingray resource path. Need to brute-hash candidate paths and match. |
| Mod(s) | all |
| Fix version(s) | doc rule |
| Category | MANUAL |
| Repro | n/a |
| Expected post-fix | Use `C:/Tools/vt2_bundle_unpacker/target/release/unpacker.exe murmur hash <path>` to find the missing resource. Don't speculate. |
| Detection | When crash occurs, run hash candidates before authoring a fix. |


---

## Slugs

- cross-mod-br-registration-sync
- ct-graph-snapshot-rpc
- feedback-deploy-vs-upload-distinction
- feedback-mod-version-format
- feedback-pre-deploy-checklist
- feedback-redundant-safeguards-ok
- feedback-search-changelog-for-known-crashes
- feedback-workshop-upload-verify
- feedback-workshop-upload-without-deploy
- gated-registration-divergence
- lua-forward-reference
- ps5-getcontent-utf8
- ugc-tool-forward-slashes
- ugc-tool-pushes-all-cfg-fields
- vmblauncher-handscaffold-first-upload
- vmf-dropdown-options-mutated
- vmf-network-send-recipients
- vmf-widget-id-unique
- vt2-adventure-pack-spawning-compat
- vt2-chat-command-syntax
- vt2-deus-power-up-rarities
- vt2-dormant-buff-template-dual-register
- vt2-hash-reverse-lookup
- vt2-jewelry-traits-become-cw-boons
- vt2-lobby-combined-hash
- vt2-localize-string-format-pipeline
- vt2-lua-200-locals
- vt2-max-overheat-modifier-unified
- vt2-mod-command-inventory
- vt2-mutator-template-server-wrap
- vt2-networked-flow-state-leak
- vt2-unit-actor-one-indexed
