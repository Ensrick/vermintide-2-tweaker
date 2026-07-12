# Engine reference set - index

Eleven subsystem references for the VT2/Stingray engine as our mods actually use it,
grep-verified 2026-07-11 against the decompiled source at
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`. Each doc follows the same shape:
architecture map, lifecycle/data flow, hookable seams, traps and crash classes, and
"implications for our mods" (the per-lane improvement candidates, now merged and
prioritized in `IMPROVEMENT_BACKLOG.md`).

Companion repo docs: `docs/BUG_CLASSES.md` (crash catalog), `docs/MECHANICS.md`,
`docs/VMF_RECIPES.md`, `docs/OOP_REFACTOR_PLAN.md`, `docs/WEAPON_APPEARANCE_STANDARD.md`,
`docs/CROSS_MOD_ARCHITECTURE.md`.

## Index

| Doc | Scope (one line) | Read when... |
|---|---|---|
| [01_foundation_and_oop.md](01_foundation_and_oop.md) | `class()` copy-inheritance, foundation utils (`table`/`callback`/`FrameTable`), Managers groups, EventManager, settings-table idiom, boot order | Writing/decomposing a class, hooking a base class, registering state events, reaching for a table helper, or asking "what exists when mods load" |
| [02_entity_extension_system.md](02_entity_extension_system.md) | EntityManager2 two-phase add, ScriptUnit, extension templates (self-owned/husk x server), frame order, commit windows, extension teardown | Adding per-unit behavior, hooking `init`/`extensions_ready`, fetching extensions, diagnosing half-initialized-unit crashes (issue #470 class) |
| [03_network_and_rpc.md](03_network_and_rpc.md) | NetworkLookup build/seal, RPC dispatch/relay, game-object codec, ProfileSynchronizer, wire-safety doctrine (injection / substitution / parity gate) | Registering any networked name, hooking an RPC sender/receiver, or touching anything that rides `rpc_*` (BUG_CLASSES §31 territory) |
| [04_unit_lifecycle_and_pooling.md](04_unit_lifecycle_and_pooling.md) | UnitSpawner spawn/delete paths, death watch, BreedFreezer pooling, POSITION_LOOKUP/ALIVE/HEALTH_ALIVE semantics, destroy listeners | Spawning/despawning units, keying caches by unit, breed swaps, or any POSITION_LOOKUP nil/stale symptom |
| [05_packages_and_residency.md](05_packages_and_residency.md) | PackageManager refcounting, sync vs async loads, reference-name discipline, level-transition package flow, force-load doctrine | Calling `Managers.package:load/unload`, chasing a residency crash or a "Package still referenced" shutdown leak (issue #282 class) |
| [06_items_gear_and_husk_inventory.md](06_items_gear_and_husk_inventory.md) | ItemMasterList/WeaponSkins, `BackendUtils.get_item_units` (the one mesh seam), GearUtils spawn paths, owner vs husk inventory, preview surfaces | Any weapon/cosmetic display feature - the four-render-path coverage matrix and the husk identity degrade (issues #392/#474) live here |
| [07_conflict_director_and_mutators.md](07_conflict_director_and_mutators.md) | ConflictDirector spawn funnel, pacing/hordes/specials, mutator template folding, difficulty rank vs name keying, Deus specifics | Touching spawns/pacing/mutators/difficulty, or diagnosing rank-hole (issue #470) and scalar-pacing (issue #386) crash classes |
| [08_game_states_and_world_lifecycle.md](08_game_states_and_world_lifecycle.md) | Boot frame loop, GameStateMachine, StateIngame teardown order, world inventory/handles, manager lifetime table | Writing any `mod.update` consumer, caching world handles, or chasing a Leave-Game / dead-world AV (issue #459 class) |
| [09_ui_views_and_widgets.md](09_ui_views_and_widgets.md) | IngameUI views/transitions, UIWidget/UIRenderer, material residency (create vs draw time), hero windows, input services | Building/attaching a view or overlay, augmenting widgets, or any `Material not found in Gui` / create_screen_gui fatal |
| [10_damage_buffs_and_talents.md](10_damage_buffs_and_talents.md) | Damage pipeline order, buff templates/procs/stat buffs, three networked-buff mechanisms, talent application, heal/THP semantics | Registering buffs, hooking damage/heal paths, talent reworks, or peer-parity questions on buff RPCs (issues #425/#426) |
| [11_backend_and_loadouts.md](11_backend_and_loadouts.md) | PlayFab mirror, commit/diff engine, EAC gating asymmetry, item bid->key->wire degrade, native saved loadouts, statistics round trip | Touching loadouts/backend items/persistence, modded-realm isolation (issue #402), or crafted-item identity (issue #474 mechanism 3) |

Merged, prioritized cross-lane work list: **[IMPROVEMENT_BACKLOG.md](IMPROVEMENT_BACKLOG.md)**
(feeds the OOP professionalization program, `docs/OOP_REFACTOR_PLAN.md`).

## Conventions used across this set

- **Citations:** vanilla paths are relative to
  `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to the
  monorepo root. Line numbers are against the decompile as of 2026-07-11; decompiled lines
  can drift from shipped runtime lines (doc 09 header) - match crash logs by function
  name, not line.
- **`§N`** = a `docs/BUG_CLASSES.md` class; **`#N` / "issue #N"** = a GitHub issue. Do not
  mix the two notations.
- **Mod abbreviations:** `et` = enemy_tweaker, `evt` = event_tweaker (doc 07 defines
  both; the whole set follows it). Note: some older memory-store entries use "et" for
  event_tweaker - inside `docs/engine/` the convention above wins.

## Maintenance rules (binding)

1. **Docs update in the same commit as the code that invalidates them.** If a change to a
   mod or tool makes any claim in these docs stale (a hook moved, a guard added, a file
   renamed, a candidate in `IMPROVEMENT_BACKLOG.md` implemented), the SAME commit edits the
   affected doc/backlog row. Shipped-but-stale reference docs are treated as bugs, exactly
   like shipped-but-uncommitted code (user rule 2026-07-01; repo `CLAUDE.md`
   NON-NEGOTIABLE 5's same-response doctrine applies to this set).
2. **Every claim cites `file:line` or is tagged `[unverified]`.** No exceptions - a
   mechanic statement without a citation into the decompile (or our source) must carry
   `[unverified]`, per repo `CLAUDE.md` NON-NEGOTIABLE 12 and the `docs/MECHANICS.md`
   provenance doctrine. When you verify a previously `[unverified]` claim, replace the tag
   with the citation in the same commit.
3. **Backlog rows are removed (or re-cited), never left stale.** When a backlog item
   ships, delete its row and cite the fixing commit/issue in the relevant doc's
   "implications" section; when an item is rejected, note why in the owning GitHub issue,
   then delete the row.
4. **After a game patch, re-verify line numbers before trusting them** (doc 10 header
   rule). Spot-check the load-bearing citations of any doc you are about to act on.

## Per-mod surface docs (the reverse index)

Each high-contact mod carries an `ENGINE_SURFACE.md` - the per-mod companion to this
set: every seam the mod touches, the vanilla behavior there (cited), and why the mod
is there. The template is `character_weapon_variants/ENGINE_SURFACE.md`; all seven
follow its structure. This table is the single view of which mods exercise which
subsystem docs.

| Mod | Doc | Sites | Links into docs/engine |
|---|---|---|---|
| character_weapon_variants | `character_weapon_variants/ENGINE_SURFACE.md` | 53 | 02 03 05 06 09 10 11 |
| cosmetics_tweaker | `cosmetics_tweaker/ENGINE_SURFACE.md` | ~70 | 02 03 05 06 09 11 |
| weapon_tweaker | `weapon_tweaker/ENGINE_SURFACE.md` | 30 (25 live + 5 dormant BR) | 01 02 03 05 06 09 11 |
| general_tweaker_dev | `general_tweaker_dev/ENGINE_SURFACE.md` | ~110 | 01 02 03 04 07 08 09 10 11 |
| gui_tweaker_dev | `gui_tweaker_dev/ENGINE_SURFACE.md` | ~135 | 06 08 09 11 |
| chaos_wastes_tweaker_dev | `chaos_wastes_tweaker_dev/ENGINE_SURFACE.md` | 102 + 4 RPC channels | 03 07 08 09 10 11 |
| crafting_in_modded_dev | `crafting_in_modded_dev/ENGINE_SURFACE.md` | 106 + 1 RPC channel | 03 06 09 11 |
| career_tweaker | `career_tweaker/ENGINE_SURFACE.md` | 24 | 01 03 09 10 11 |
| event_tweaker | `event_tweaker/ENGINE_SURFACE.md` | 10 | 03 05 07 08 11 |
| enemy_tweaker | `enemy_tweaker/ENGINE_SURFACE.md` | 25 (+3 dormant BR) | 01 03 04 07 10 |
| modded_progression | `modded_progression/ENGINE_SURFACE.md` | 10 (+ sibling API) | 09 11 |
| weapons_of_chaos | `weapons_of_chaos/ENGINE_SURFACE.md` | 3 (+ direct IML/NetworkLookup append) | 03 05 06 08 |
| dynamic_cosmetic_portraits | `dynamic_cosmetic_portraits/ENGINE_SURFACE.md` | 1 (+ career_settings swap + VMF material inject) | 06 09 11 |
| verminious_dreams_lighting_dev | `verminious_dreams_lighting_dev/ENGINE_SURFACE.md` | 2 (+ Light/ShadingEnvironment C-API) | 07 08 09 |

Maintenance (extends rule 1): when a mod's ENGINE_SURFACE changes its docs/engine
link set or its site count materially, update this table in the same commit. No
per-doc version stickers (they drift; PROJECT_STANDARDS section 7.1 doctrine).
