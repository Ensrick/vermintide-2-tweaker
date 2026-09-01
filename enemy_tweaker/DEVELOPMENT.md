# Enemy Tweaker — Development Notes

Architecture, breed-adding checklist, and active feature inventory for
`enemy_tweaker`. Read alongside `CHANGELOG.md` (history),
`CODE_REVIEW.md` (current health), `EXPANSION_PLAN.md` (Spawn-Parity
roadmap), `SKELETON_HORDES.md` (skeleton-breed design), and
`REGRESSION_CHECKLIST.md` (pre-release gates).

---

## Overview

Workshop ID: `3716780252`, internal ID: `enemy_tweaker`. VMB mod.

Current core features:

- **Horde presets** (`HORDE_PRESETS`): All Elites, Skaven Only, Chaos
  Only, Beastmen Invasion, Mixed Factions. Patches
  `HordeCompositionsPacing` keys
  (`small`/`medium`/`large`/`huge`/`huge_*`/`mini_patrol`, plus
  `chaos_*` and `beastmen_*` parallels). Paced hordes only — does NOT
  touch `HordeCompositions` event entries.
- **Faction substitution** (3 dropdowns: Replace Skaven / Chaos /
  Beastmen Hordes With ...). Hooks
  `ConflictDirector.refresh_conflict_director_patches` to rewrite
  `CurrentHordeSettings.{ambush,vector,vector_blob,mini_patrol}_composition`
  per the user's map. Re-applies on every per-zone CD switch. Same
  caveat — paced hordes only.
- **Per-difficulty Specials control** — Max Active, Max Same Type,
  per-special spawn weight, per-special disable. Per-difficulty
  (Recruit / Veteran / Champion / Legend / Cataclysm 1/2/3). Three
  `SpecialsPacing` hooks.
- **Breed substitution** — one-to-one breed name swap, applied at
  `HordeSpawner.spawn_unit` and `compose_blob_horde_spawn_list`.
- **Horde size multiplier** — scalar (25-300%) over all
  `HordeCompositionsPacing` entries' breed counts.

## Module map (post-v0.7.31 OOP split)

`enemy_tweaker.lua` is a compact entry: MOD_VERSION, ET_RPC_SCHEMA, the load
banner, and the dofile manifest. Every `_et_*` module is dofile'd EXACTLY ONCE,
in manifest order (VMF `mod:dofile` is NOT a singleton - each call re-executes
the file - so modules never dofile each other; shared helpers publish into
`mod._et`, the #479 protective factories additionally as `mod._et479_*`).

| Module | Owns |
|---|---|
| `_et_regression` | `/et_regression_test` harness + generic checks (loads FIRST) |
| `_et_log` | dbg/alert/chat/spawn log channels + printf probe |
| `_et_protect` | `_safe`/`_hook_wrap`/`_make_tick_guard` (#479: skip tick on inner error, NEVER re-run vanilla) + `_call_with_override` + multiplier math |
| `_et_fingerprint` | Deterministic whole-mod settings fingerprint used by diagnostics and parity checks |
| `_et_settings_queue` | Engine-free next-frame coalescer for VMF/Mod Tweaker setting bursts (#560) |
| `_et_health_multiplier_core` | Engine-free bounds, hostile-breed policy, and health-percentage rescale math (#369) |
| `_et_boss_behavior_core` | Engine-free #450 Halescourge gate, Skarrik ranged multiplier, and Deathrattler tracking policy |
| `_et_horde_presets` | horde preset catalog + composition backup/apply + CHS horde size |
| `_et_swaps` | breed/faction substitution + HordeSpawner hooks |
| `_et_mimic` | per-system difficulty mimic |
| `_et_roaming` | roaming size (SIP + recycler guard + ambient density + clone shim) |
| `_et_custom_breed_registrar` | #1413 Enemy-local declarative transaction owner for every custom breed: off-table clone/side-surface plan, three strict wire axes planned on shadows through `_lib_network_lookup`, source-authoritative damage/statistics-path capacities, exact reload fingerprint with bounded engine-owned difficulty overlays, detached table presentations, reversible raw-table commit, `Breeds` publication last, and fail-closed terminal handling for the engine's opaque threat upvalue |
| `_et_custom_breed_identity` | #451B engine-free exact identity over both ET breed names, registrar schema/fingerprints, and symmetric ids on `NetworkLookup.{breeds,damage_sources,statistics_path_names}`; also owns the canonical-custom/validated-vanilla-donor decision used by both spawn surfaces |
| `_et_skaven_warlord_breed` | #324 Warlord policy/spec consumed by `_et_custom_breed_registrar` (MUST precede `_et_champion_warlord`) + bounded `[et:324]` spawn diagnostics: AI/BT/target/nav/locomotion snapshot at spawn/+5s/+15s for up to 4 Warlord spawns per session, dispatched from the `_post_spawn_unit` seam and the lifecycle update owner |
| `_et_custom_breed_parity` | #451B canonical exact peer-parity instance, installed after both breed registrations and before hot-join/spawn hooks; revalidates registrar + identity at emission; excludes the listen-server owner at both real pre-roster ingress hooks and delegates its native chain exactly once; treats boot-time absence of the optional parity owner as absence rather than failed cleanup; permits donor-safe native sync only when both live and queued counters for both ET breeds are proven zero; holds a live/queued-state remote join's pending challenge outside `GameSession` without kicking, admits delayed exact proof, and kicks once only after timeout or definitive proof revocation; forgets disconnect epochs and owns bounded donor/hot-join logs |
| `_et_champion_warlord` | champion/warlord pools + SINGLE consolidated `spawn_queued_unit` hook extended with the custom-breed sender floor + sole `spawn_unit_immediate` floor + existing #324 crash guards |
| `_et_director_hooks` | ConflictDirector init/refresh re-apply chain |
| `_et_event_size` | terror-event horde size scaling |
| `_et_pacing` | spawn pacing (CD tick #479 guard, freq/caps), #213 freeze guard, #449 rush-intervention freeze gate |
| `_et_banner` | beastman banner toggles |
| `_et_patrol` | patrol formation size |
| `_et_specials` | per-difficulty special spawns |
| `_et_health_multiplier` | #369 host-authoritative final-spawn health scaling + bounded live rescale/replication |
| `_et_lifecycle` | queued on_setting_changed / batch completion / update drain + on_enabled / on_disabled + BR bootstrap; final `mod.update` owner preserves the earlier canonical parity wrapper and also dispatches the bounded #450 boss monitor and #324 Warlord samples |
| `_et_commands` | chat commands (`/et_status`, `/verify_*`, dumps, `/et_reset`) |
| `_et_boss_tweaks` | fly-disable duration; issue 275 probe |
| `_et_boss_balance` | #450 reversible boss data toggles (health/armor/warp-lightning and Deathrattler's dual-gun rotation window; no hooks). Bodvarr is runtime breed `chaos_exalted_champion_warcamp`, never the unsuffixed source-family stem. |
| `_et_boss_grudge` | #531 grudge-mark behavioral knobs (Skarrik Berserk / Bodvarr Crippling on Cata+ Adventure); single `hook_safe` on `ConflictDirector._post_spawn_unit`, applies vanilla CW grudge-mark buff templates host-side. Bodvarr maps to `chaos_exalted_champion_warcamp`; `_norsca` is the Skittergate champion. |
| `_et_boss_behavior` | #450 runtime behavior adapter: Halescourge uses existing post-spawn/update owners for one package-aware Troll/Spawn; Skarrik composes the existing damage owner; one exact `BTStormfiendShootAction._fire_from_position_direction` hook halves Deathrattler-only ratling tracking. |
| `_et_boss_ideas` | #451 feasibility audit + greataxe Chosen policy/spec consumed by `_et_custom_breed_registrar`: honest boss-only classification, health bar/far-despawn immunity/threat 32/boss infighting/recomputed category mask, donor-preserving exactly-once boss+angry lifecycle, 2000 HP and resident `warrior_axe`; host command requires package residency and exact peer identity. Owns no spawn hook and never injects arena-coupled lord breeds. |
| `_lib_network_lookup` | Byte-exact copy of `tools/shared_lib/_lib_network_lookup.lua` (#428 guard patterns); loaded exactly once, then injected into `_et_custom_breed_registrar`. The registrar plans all three custom-breed lookup axes against shadows before any real write. Never edit here - edit the canonical copy and re-sync. |
| `_lib_peer_parity` | Byte-exact manifest-managed copy of `tools/shared_lib/_lib_peer_parity.lua`; exact challenge/epoch/replay transport for the custom-breed owner. Never edit the consumer copy. |

Where new code goes: the module whose "Owns" row it extends; a new subsystem gets a
new `_et_<name>.lua` + one manifest line + a row here (same discipline as
`event_tweaker/CLAUDE.md`). One hook per (Class, method) repo rule applies ACROSS
modules - grep the whole mod dir before hooking.

---

## Architecture (key files in source)

- `scripts/settings/conflict_settings.lua` — `ConflictDirectors[name]`
  bundles `pacing`, `horde`, `boss`, `specials`, `roaming`, `factions`.
  ~9 vanilla directors (`default`, `default_light`,
  `skaven{,_light}`, `chaos{,_light}`, `marauders_and_warriors`,
  `beastmen{,_light}`).
- `level_settings.lua` — per-level `conflict_settings = "<director_name>"`
  picks the starting CD.
- `main_path_spawning_generator.lua` (~line 312) — per-zone
  `override_conflict_setting` switches the active CD mid-mission. This
  is how Athel Yenlui / Hunger in the Dark / etc. transition from
  Skaven (early zones) to Chaos (later zones).
- `conflict_director.lua:881` — `refresh_conflict_director_patches`
  rebuilds `CurrentHordeSettings = table.clone(director.horde)` whenever
  the CD switches. Our hook fires after this to re-apply faction-swap.
- `HordeCompositionsPacing`
  (`scripts/settings/horde_compositions_pacing.lua`) — ~25 keys,
  paced/blob hordes. Patched by our preset system.
- `HordeCompositions` (`scripts/settings/horde_compositions.lua`) —
  **194 keys**, `event_medium`, `event_large_beastmen`,
  `chaos_raiders_small`, `storm_vermin_medium`, etc. **Used by
  terror-event hordes**, which is the majority of visible hordes in
  adventure missions. NOT currently patched by us.
- `PerformanceManager._activated_per_breed`
  (`performance_manager.lua:84`) — built from `pairs(Breeds)` at level
  start, seeds per-breed counters.

---

## Breed-adding checklist

This is the single most-burned-by class of crash in this mod (5+
versions of boot-time / hit-time crashes from missing entries). Enemy Tweaker
code must not call `Breeds[name] = ...` directly. Add a declarative spec to
`_et_custom_breed_registrar`; its transaction is the executable checklist.

### `pairs(Breeds)` is walked at file-load — mod-added breeds miss the snapshot

VT2 has at least **three** game-systems that iterate `pairs(Breeds)` at
file-load time to build per-breed lookup tables, then never re-scan:

| File | Line | Table | Crash surface |
|---|---|---|---|
| `scripts/managers/conflict_director/conflict_director.lua` | ~2295 | local `threat_values = {}` | `calculate_threat_value` → `nil * amount` arithmetic crash at live line 2479 |
| `scripts/managers/performance/performance_manager.lua` | ~84 | `self._activated_per_breed` (in `init`) | `event_ai_unit_activated` → `nil + 1` on first activate |
| `scripts/managers/backend/statistics_definitions.lua` | ~615 | `StatisticsDefinitions.player.{kills,damage_dealt,...}_per_breed[name]` | `StatisticsDatabase._create_stat` → ferror "No statistics definition found with path" on first damage/kill |

Each table is keyed by breed name. Mods that add breeds to `Breeds`
after game-boot miss all three snapshots. **Hooks alone don't fix it**
— if the user has the mod toggled off in VMF settings, the script
still loads and mutates `Breeds` but the hooks don't fire.

### Pattern: one eager, declarative transaction

`_et_custom_breed_registrar` performs every fallible operation before commit:
it clones breed/actions, builds statistics definitions, copies the reverse
package-alias array off-table, validates faction/elite/hit-zone/presentation
surfaces, and runs the canonical strict lookup helper against shadow copies of
`NetworkLookup.breeds`, `.damage_sources`, and `.statistics_path_names`. New
damage-source and statistics-path rows are accepted only when their planned
indices fit guarded runtime authorities:
`NetworkConstants.damage_source_id.max`, falling back to
`Network.type_info("damage_source_id").max`, and
`Network.type_info("statistics_path_lookup").max`, respectively. No guessed
capacity is allowed. The statistics-path row is mandatory because the emitted
`sync_on_hot_join` leaf includes the custom breed name in its encoded path. A
same-name statistics path segment already present as an exact symmetric pair is
global reusable identity, not breed-owned residue; the registrar pins that
index without allocating or reading capacity.

After complete preflight, the exact `ConflictDirector.set_threat_value` setter
runs first, followed only by raw table writes. Any structural failure restores
the precise prior key values; the source alias array is never mutated in place.
Readiness is staged while it is still rollback-covered, and `Breeds[name]` is
the final raw write. Exact hot reload requires the registrar fingerprint and
every mandatory side surface to agree; a partial or foreign row is rejected
without repair-by-guessing.

`SET_BREED_DIFFICULTY` legitimately changes only declared action outputs. On
reload, damage, blocked damage, diminishing damage, and bot-threat delay may
differ from the detached marker only when the canonical action declares the
matching difficulty table; the live value must equal the already engine-baked
vanilla source action. Declarations, durations, topology, and all other fields
remain immutable. All permitted outputs are copied into one detached expected
graph before full topology comparison, preserving cross-output cycles, sharing,
and separation while forbidding aliases into the donor or declarations.
The donor declaration/duration graph has its own detached marker authority:
this pins donor sharing independently because Foundation `table.clone` can
legitimately split one shared vanilla declaration across multiple custom
actions.
Table-valued presentation declarations are copied into live graphs disjoint
from every declaration and every other selected row, so mutation of a
published table cannot mutate any validation authority or sibling
presentation. Fresh action clones and reload donors likewise must remain fully
graph-disjoint from the detached action marker. Every detached authority uses
primitive keys and nil metatables; richer mutable identity shapes fail before
the opaque threat setter or any structural write.

The threat table is a hidden file-local upvalue and has no getter. Therefore a
setter that throws after mutating it cannot be rolled back honestly. That path
leaves all structural state unpublished, records an indeterminate terminal
failure for the current module load, and forbids blind retry. Production must
not depend on `debug.getupvalue` to manufacture rollback authority.

### threat_values is an upvalue built ONCE at game-boot

`scripts/managers/conflict_director/conflict_director.lua` declares
`local threat_values = {}` at file scope (~source line 2295) and
immediately fills it with one entry per breed by iterating `Breeds`.
That loop runs ONCE at game-boot, before any mod has loaded.

Any breed added to `Breeds` afterward — VMF mod custom breeds,
mid-session registrations, anything — is missing from `threat_values`.
When such a breed appears in
`Managers.state.performance:activated_per_breed()` (which itself seeds
entries by walking `pairs(Breeds)` at level start),
`ConflictDirector.calculate_threat_value` does
`threat_values[breed_name] * amount` and crashes:

```
[Script Error]: scripts/managers/conflict_director/conflict_director.lua:2479:
attempt to perform arithmetic on a nil value
```

(Live game line 2479 = source-decompile line 2323.) Note: `amount = 0`
is fine for triggering the crash — `nil * 0` still errors.

**A defensive hook is NOT sufficient.** The obvious fix —
`mod:hook("ConflictDirector", "calculate_threat_value", ...)` to
pre-flight `set_threat_value` for every breed — fails when **the user
has the mod disabled in VMF settings**. VMF still loads the mod's
script (so any module-level `Breeds[name] = ...` runs and sticks), but
skips all hook registrations. PerformanceManager later seeds
`activated_per_breed` from the now-mutated `Breeds`, and
`calculate_threat_value` crashes with no hook in sight.

**The right pattern:** let the eager registrar call the static setter as the
first operation of its already-preflighted commit.
`ConflictDirector.set_threat_value(self, name, value)` doesn't use
`self`; it just writes to the file-local upvalue. Call it as:

```lua
local CD = rawget(_G, "ConflictDirector")
if CD and CD.set_threat_value then
    CD.set_threat_value(nil, breed_name, breed.threat_value or 0)
end
```

This runs at module load and is impervious to hook-disable; a failed seed keeps
the breed and readiness unpublished.

### Lessons

- **VMF "disabled" mods still execute module-level code.** Any side
  effect on global tables (`Breeds`, `BreedActions`,
  `NetworkLookup.breeds`, etc.) persists even when the user toggles
  the mod off. Either make module-level mutations idempotent +
  safe-when-disabled, or move them inside `mod.on_enabled`.
- **Hooks are conditional, direct method calls aren't.** When a fix
  needs to apply unconditionally (game won't survive without it),
  don't put it in a hook.
- **`ConflictDirector.set_threat_value` is callable as a static method**
  (`CD.set_threat_value(nil, name, value)`). Same trick may work for
  other vanilla "method that doesn't use self" patches.
- **A hidden upvalue is not transactionally readable.** Never claim exact
  rollback after a throwing setter and never add a production debug-upvalue
  dependency. Retire that breed for the module load with structural state
  unpublished.

### Full checklist for any new breed-adding mod

Before shipping any new Enemy Tweaker custom breed, its registrar spec and
adversarial tests must cover:

1. source breed and deep-cloned `BreedActions` without source mutation; all
   fallible owner callbacks receive detached source/candidate views;
2. the hidden threat value via the exact static setter, seeded only from the
   canonical marker value rather than a presently live breed field;
3. all six `StatisticsDefinitions.player.*_per_breed` families, including
   named per-difficulty leaves;
4. an already-live `PerformanceManager._activated_per_breed` row whose dynamic
   value remains a finite, nonnegative integer (future managers see the breed
   because `PerformanceManager.init` scans `Breeds`);
5. all three strict, dense, bidirectional wire axes planned together on shadows and
   their first committed numeric identities pinned for reload;
6. the runtime-authoritative damage-source and statistics-path capacity
   boundaries, with exact existing rows revalidated without inventing capacity;
7. forward package alias and an off-table replacement reverse-alias array;
8. canonical dismemberment identity/content, faction, elite/category, and
   hit-zone identity/content;
9. declared presentation rows (table values detached and graph-disjoint) and
   public readiness;
10. a schema-3 registrar marker with detached cycle/topology-safe breed/action
    snapshots, a separate detached donor declaration/duration snapshot,
    canonical threat/elite, all three wire identities, dismemberment, and
    hit-zone state; owner specs add policy checks rather than duplicate it;
11. readiness remains rollback-covered and `Breeds` is the final raw write,
    with exact structural rollback at every injected failure and terminal
    handling for opaque threat-setter failure.

Then re-audit `grep -n 'pairs(Breeds)'` in the current source decompile for any
new file-load snapshots. New surfaces extend the single registrar; they do not
create a second registration path.

This source lane deliberately does not version, build, bundle, deploy, or
publish. The serialized integration owner must regenerate the exact Enemy root
bundle and current receipt from the reviewed commit before any release claim.

### Source incidents

- enemy_tweaker v0.3.3 → v0.3.5: threat_values crash (live line 2479)
  — defensive hook insufficient when mod disabled, eager
  `CD.set_threat_value(nil, ...)` fix.
- enemy_tweaker v0.3.6: per-breed statistics crash
  (`damage_dealt_per_breed.et_ghost_skeleton_hammer`) — mirror the
  full vanilla seed loop directly on `StatisticsDefinitions.player`.

---

## Deferred / removed features

### Skeleton breed clones (removed in v0.4.0-dev)

v0.2.x → v0.3.8 prototyped 6 cloned skeleton breeds
(`et_necro_skeleton{,_armored,_dual_wield,_shield}`,
`et_ghost_skeleton_{hammer,shield}`) deep-copied from `chaos_skeleton`
with model base_units from `pet_skeleton` / `ethereal_skeleton_*`.
Three horde presets (Necromancer / Ghost / All Skeletons Mixed)
referenced them.

**Why removed:** the user "rarely saw them" because horde presets only
patch `HordeCompositionsPacing` — most adventure-mission hordes are
terror-event-driven (`HordeCompositions`) and bypassed our patches.
Adding the clones also paid a high crash tax (5 versions of boot-time
/ hit-time crashes from missing entries in `threat_values`,
`StatisticsDefinitions.player.*_per_breed`, `BreedHitZonesLookup`).

**To revive:** patch `HordeCompositions` event entries when a skeleton
preset is selected, fan out across the 194 keys. Then the clones
become visible.

**Sharp edges to remember:**

- See the **Breed-adding checklist** above — every vanilla file
  walking `pairs(Breeds)` at file-load freezes a snapshot; mod-added
  breeds crash each one.
- The `hit_zones` overlay (use `source.hit_zones` not
  `chaos_skeleton.hit_zones`) — actor names must match the actual
  unit.
- All breed-registration must run eagerly at script load (VMF-disabled
  mods still execute module code; hooks alone fail).

---

## Planned features (requested 2026-05-16)

1. **Per-breed horde composition fine-tuning** — UI for picking which
   enemies appear in hordes and weighting them 1-50. Implementation:
   dynamic widget list per faction (Skaven/Chaos/Beastmen) with weight
   sliders per breed; convert to `HordeCompositionsPacing` overrides
   at runtime.
2. **Difficulty-mimic mode** — let the user play on Champion but use
   Cataclysm-1's horde sizes / composition / special frequency /
   roaming. Implementation: hook `refresh_conflict_director_patches`
   to override the difficulty key used by `patch_settings_with_difficulty`
   for specific systems (horde / specials / roaming / pack_spawning)
   while leaving enemy-stat difficulty untouched. Likely needs
   separate "mimic source" dropdowns per system: horde-size mimic,
   special-frequency mimic, roaming-density mimic, etc.
3. **Terror-event composition patcher** — fan presets / faction-swap
   across `HordeCompositions` event keys so they actually dominate
   adventure missions. Prerequisite for re-enabling skeleton presets.

See `EXPANSION_PLAN.md` for the full Spawn-Parity expansion roadmap.

---

## How to apply

When implementing any of the above, check `enemy_tweaker.lua` for the
existing hook pattern. The faction-swap mechanism
(`_apply_faction_swap_to_current_horde_settings` + the
`refresh_conflict_director_patches` hook) is the canonical pattern for
"rewrite live director settings on every switch." Reuse it for the
difficulty-mimic feature.

Use `et_status` in-game to inspect what
`CurrentHordeSettings.*_composition` actually is after any patch —
invaluable for verifying overrides land.
