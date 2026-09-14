# Boss Idea Feasibility (#451)

Issue #451 proposes six boss concepts. None of the vanilla lord breeds should be inserted directly into ordinary monster spawns. Their models are reusable candidates, but their behavior/action sets carry authored-arena assumptions.

## Source boundary

| Concept | Source finding | Safe implementation boundary |
|---|---|---|
| Chosen Chaos Warrior with shield | Bodvarr is registered as `chaos_exalted_champion_warcamp`; the armored regular Chaos Warrior donor is `chaos_warrior`. | Create a new breed from regular Chaos Warrior AI, then validate the Bodvarr model plus shield/sword inventory. Do not clone Bodvarr behavior. |
| Chosen Chaos Warrior with greataxe | Same Bodvarr/regular-warrior split. | First portable prototype: regular Chaos Warrior AI, 2,000-health data, monster stagger policy, and a model/inventory compatibility probe. |
| Stormfiend with ratling guns | Deathrattler's generated selector consumes intro and mount state (`bt_selector_stormfiend_boss.lua:53-122`); its actions define `mount_unit` and `dual_shoot_intro` (`breed_skaven_stormfiend_boss.lua:404,1131`). | Build a portable action/behavior subset before using the boss model. |
| Skaven Warlock | The Grey Seer selector dereferences `blackboard.mounted_data.mount_unit` (`bt_selector_grey_seer.lua:117-118,252`); its actions also use named Grey Seer spawners (`breed_skaven_grey_seer.lua:285-314`). | New non-mounted behavior tree and portable spawn policy are required. |
| Chaos Sorcerer | Halescourge actions use named `sorcerer_boss` spawners (`breed_chaos_exalted_sorcerer.lua:302-360,560-564`). | Replace arena teleport/spawn queries before a general-map spawn option exists. |
| Troll Chieftain | Its downed phases spawn oil sockets/barrels, query boss spawners, disable active objectives, and fire `boss_arena_alcove_*` flow events (`breed_chaos_troll_chief.lua:1175-1524`). | Clone the breed/action data and remove or replace every arena phase event. Never mutate vanilla tables in place. |

The Troll Chieftain is globally registered (`breeds.lua:56`) but dynamically loaded as `level_specific` (`enemy_package_loader_settings.lua:38-48`). Registration alone does not make its arena behavior portable.

## Diagnostics contract

`_et_boss_ideas.lua` performs a read-only audit once at mod load. It checks each
source/model breed, action table, behavior tree, AI inventory, breed wire id,
base-unit path, and current unit residency, plus the four arena-coupled action
shapes. Output is bounded to seven engine-log lines under `[et:451]`; no setting,
hook, spawn, or shared game table is changed.

`/et_boss_idea_audit` permits one second capture after entering a representative
mission. Comparing `model_resident` between boot and mission identifies which
level-specific lord packages are available without trying to spawn them. A false
`actions`, `behavior`, `inventory`, or `wire` field is a structural blocker;
residency alone is a package/preload task. The command prints only one summary to
chat and leaves the six detail rows in the log.

`/et_regression_test` locks the six-candidate list, requires all six source
contracts, and forces a new source audit if a game update removes one of the
known arena-risk markers. Run `/et_boss_idea_audit` in a mission to collect the
optional residency evidence.

## Implemented: greataxe Chosen prototype (first slice)

`_et_boss_ideas.lua` eagerly registers `et_chosen_greataxe`, a deep copy of
the regular `chaos_warrior` breed with the engine-free override policy in
`_et_boss_ideas_core.lua` (`Core.apply_chosen_overrides`): 2000 HP in all nine
vanilla health slots, monster stagger gate `boss_staggers` (damage_utils.lua:791-793 -
staggers below explosion resolve to none), display name "Chaos Chosen", and the
source breed's own `warrior_axe` inventory - which already carries the
two-handed chaos greataxe (ai_inventory_templates.lua:1499-1502), so no new
asset residency is introduced. #451B classifies it exclusively as a boss
(`boss=true`, no `elite`/`ELITES` membership), enables its health bar and
far-off despawn immunity, sets threat 32 and boss infighting, then recomputes
the engine category mask. Its spawn/death/despawn wrappers preserve every donor
callback while attempting boss-list and angry-counter registration/removal once
per unit across both terminal callbacks, including throwing paths. The v5
registrar fingerprint (2026-09-13) makes this contract an exact reload boundary.

### Chosen contract: boss, not elite (decided 2026-09-13)

Decision: `et_chosen_greataxe` is a boss. Every surface below is what the
engine reads for `breed.boss` units; each is set on the clone, tested offline
(`test_et_boss_ideas`, `test_et_custom_breed_registrar_contract`), and checked
in-game by `issue451_chosen_greataxe_prototype`. The donor `chaos_warrior` is
never mutated (`breed_chaos_warrior.lua:50` keeps `elite = true`).

| Surface | Chosen value | Engine consumer (decompile) | Why |
|---|---|---|---|
| `boss = true` | set | `breed_utils.lua:20` Boss category bit; `proximity_system.lua:652` nearest-boss health bar; `conflict_director.lua:2113` spawn dialogue and forced boss UI; `:2282` alive-boss ledger removal at destroy; `damage_utils.lua:350,802,2273`; `ai_bot_group_system.lua:1491`; `nav_graph_system.lua:554`; `door_system.lua:127` | Every system keyed on `breed.boss` must treat the unit as a monster. |
| `elite = nil` | cleared | `breeds.lua:348` builds `ELITES` from the flag (the registrar keeps membership consistent); `enemy_package_loader.lua:233-237` patrol replacement pools; `damage_utils.lua:2273` | A breed is one class; boss wins. |
| `category_mask` | recomputed after both flags | `breed_utils.lua:12-35`: Boss bit plus the Armored bit because `armor_category == 2` (`breed_chaos_warrior.lua:31`) | Bot conditions read the mask, not the flags. |
| `show_health_bar = true` | set (troll `breed_chaos_troll.lua:117`) | `ping_system.lua:504`, `weapon_system.lua:196` register the boss bar on ping and on damage | The bar appears on first hit or ping, not only by proximity. |
| `far_off_despawn_immunity = true` | set (troll `:79`) | `ai_simple_extension.lua:222-224,252-254` copies it to the blackboard; `enemy_recycler.lua:1098,1132` skip the far-away destroy | A boss must survive players outrunning it. |
| `boss_staggers = true` | set (troll `:61`) | `damage_utils.lua:791,918` | Monster stagger policy. |
| `threat_value = 32` | set (troll `:127`, champion `breed_skaven_storm_vermin_champion.lua:57`) | `conflict_director.lua:2297-2323` threat upvalue via the exact setter | Monster pacing intensity. |
| `infighting = InfightingSettings.boss` | set (troll `:137`, champion `:62`) | `infighting_settings.lua:12` | Boss slot and crowding policy. |
| `max_health` | nine slots of 2000 | `breed_tweaks.lua:138-149` builds nine `health_steps`; `conflict_director.lua:1947-1948` indexes by rank, and ranks run 2..9 with `versus_base = 9` (`difficulty_settings.lua`); the registrar proves every step below `damage_hotjoin_sync.max` (`network_constants.lua:20,76-86`) | Vanilla shape; 2000 sits under the troll's 4800 at Cataclysm 3 (`breed_tweaks.lua:117-127,182`), which the boot assert already admits. |
| Alive-boss ledger and angry counter | `run_on_spawn` adds once (`add_unit_to_bosses`, `add_angry_boss(1, bb)`); `run_on_death` and `run_on_despawn` remove once | Engine call sites `ai_simple_extension.lua:226-228,256-258`, `death_system.lua:148-150` (server only), `conflict_director.lua:2382-2384`; the vanilla troll pattern `ai_breed_snippets.lua:330-359,510-536`; `add_unit_to_bosses` is only ever called from breed snippets, and `remove_element_from_array` (`conflict_director.lua:249-261`) tolerates the engine's own `:2282` removal | Boss music (`music_manager.lua:491,522,553`), bot boss awareness (`ai_bot_group_system.lua:1405`), and target selection (`target_selection_utils.lua:1798`) read `alive_bosses()`. |
| Not adopted from the troll pattern | no `freeze_intensity_decay`, no `reward_boss_kill_loot`; `slot_template` stays the donor's `chaos_large_elite` | `ai_breed_snippets.lua:357-358,513-522`; `breed_chaos_troll.lua:118` versus `breed_chaos_warrior.lua:85` | Loot dice and pacing freeze are encounter design, not classification; the slot template follows the body, not the class. |
| File-load boss lists the Chosen cannot join | absent | `achievement_templates_lake.lua:44-55` `boss_breeds`, `achievement_templates_cog.lua:950-962`, `spawner_system.lua:258-266` are file-local arrays built once at boot | Benign: Chosen kills do not count toward those DLC challenges, and the Chosen never enters horde exchange order. |

The full DEVELOPMENT.md breed-adding checklist is walked, including per-breed
statistics, all three `NetworkLookup` axes (`breeds`, `damage_sources`, and
`statistics_path_names`), package alias to `chaos_warrior`, and the
dismemberment/hit-zone/race-set mirrors.

`_et_custom_breed_identity.lua` fingerprints both ET custom breed names, their
registrar fingerprints, and exact symmetric ids on all three axes. The
manifest-managed canonical peer-parity transport installs after both registrar
transactions and before hot-join/spawn hooks. An unproven join may synchronize
normally when no custom breed is live or queued; parity remains non-exact, so
every later custom emission uses a vanilla donor. A queued row is already
committed because the director drains its stored breed without re-entering the
sender hook. If custom AI is live or queued, the first pending challenge holds
outside `GameSession` without kicking, a delayed exact ack admits, and only
definitive proof revocation or the bounded deadline starts one kick. Disconnect
clears the hold and retires proof.
`/et_spawn_chosen` refuses while that floor is
closed. The final consolidated queued floor and the immediate-spawn floor also
recognize direct/General-Tweaker calls by custom breed name: unsafe calls receive
the validated vanilla donor, while exact peers may receive the canonical custom
breed. A missing/throwing floor or invalid donor holds the custom request rather
than entering the generic vanilla fallback. Diagnostics are hard-capped.

There is still no automatic Chosen monster-pool or trial integration. Offline
tests prove the transaction and sender policy; live solo/co-op behavior remains
unverified until an authorized integration/deployment pass. Runtime contracts:
`issue451_chosen_greataxe_prototype` and `issue451_exact_custom_breed_parity`.

## Recommended implementation order

1. Chosen Chaos Warrior with greataxe: smallest portable regular-AI prototype.
2. Chosen Chaos Warrior with shield: add shield inventory and shield animation validation.
3. Troll Chieftain: cloned action set with all arena phase side effects removed.
4. Halescourge, Deathrattler, and Rasknitt concepts only after portable behavior trees are designed and covered by two-player package/network tests.
