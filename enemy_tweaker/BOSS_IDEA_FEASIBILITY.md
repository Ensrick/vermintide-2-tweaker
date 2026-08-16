# Boss Idea Feasibility (#451)

Issue #451 proposes six boss concepts. None of the vanilla lord breeds should be inserted directly into ordinary monster spawns. Their models are reusable candidates, but their behavior/action sets carry authored-arena assumptions.

## Source boundary

| Concept | Source finding | Safe implementation boundary |
|---|---|---|
| Chosen Chaos Warrior with shield | Bodvarr is registered as `chaos_exalted_champion_warcamp`; a regular Chaos Warrior is `chaos_raider`. | Create a new breed from regular Chaos Warrior AI, then validate the Bodvarr model plus shield/sword inventory. Do not clone Bodvarr behavior. |
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

`_et_boss_ideas.lua` now eagerly registers `et_chosen_greataxe`, a deep copy of
the regular `chaos_warrior` breed with the engine-free override policy in
`_et_boss_ideas_core.lua` (`Core.apply_chosen_overrides`): 2000 HP on every
difficulty, monster stagger gate `boss_staggers` (damage_utils.lua:791-793 -
staggers below explosion resolve to none), display name "Chaos Chosen", and the
source breed's own `warrior_axe` inventory - which already carries the
two-handed chaos greataxe (ai_inventory_templates.lua:1499-1502), so no new
asset residency is introduced. The full DEVELOPMENT.md breed-adding checklist
is walked (threat value, per-breed statistics, NetworkLookup breeds +
damage_sources via the shared `_lib_network_lookup` guards, package alias to
chaos_warrior, dismemberment/hit-zone/race-set mirrors).

Spawn surfaces: the host-only, residency-gated test command `/et_spawn_chosen`
(refuses when the chaos_warrior package is not already resident on the
mission) and gt's dynamic Creature Spawner. No monster-pool or trial
integration; that waits on co-op verification. Constraint: every peer must
have enemy_tweaker installed (NetworkLookup registration), same as the Skaven
Warlord. Runtime contract: `issue451_chosen_greataxe_prototype`.

## Recommended implementation order

1. Chosen Chaos Warrior with greataxe: smallest portable regular-AI prototype.
2. Chosen Chaos Warrior with shield: add shield inventory and shield animation validation.
3. Troll Chieftain: cloned action set with all arena phase side effects removed.
4. Halescourge, Deathrattler, and Rasknitt concepts only after portable behavior trees are designed and covered by two-player package/network tests.
