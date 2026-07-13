# Enemy Tweaker — Development Notes

Architecture, breed-adding checklist, and active feature inventory for
`enemy_tweaker`. Read alongside `CHANGELOG.md` (history),
`CODE_REVIEW.md` (current health), `EXPANSION_PLAN.md` (Spawn-Parity
roadmap), `SKELETON_HORDES.md` (skeleton-breed design), and
`REGRESSION_CHECKLIST.md` (pre-release gates).

---

## Overview

Workshop ID: `3716780252`, internal ID: `enemy_tweaker`. VMB mod.

Shipped features (as of v0.5.5-dev):

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

## Module map (v0.7.31-dev OOP split)

`enemy_tweaker.lua` is an 83-line entry: MOD_VERSION, ET_RPC_SCHEMA, the load
banner, and the dofile manifest. Every `_et_*` module is dofile'd EXACTLY ONCE,
in manifest order (VMF `mod:dofile` is NOT a singleton - each call re-executes
the file - so modules never dofile each other; shared helpers publish into
`mod._et`, the #479 protective factories additionally as `mod._et479_*`).

| Module | Owns |
|---|---|
| `_et_regression` | `/et_regression_test` harness + generic checks (loads FIRST) |
| `_et_log` | dbg/alert/chat/spawn log channels + printf probe |
| `_et_protect` | `_safe`/`_hook_wrap`/`_make_tick_guard` (#479: skip tick on inner error, NEVER re-run vanilla) + `_call_with_override` + multiplier math |
| `_et_fingerprint` | BR + settings fingerprints, `et_br_fingerprint` RPC, dormant-BR stub |
| `_et_settings_queue` | Engine-free next-frame coalescer for VMF/Mod Tweaker setting bursts (#560) |
| `_et_horde_presets` | horde preset catalog + composition backup/apply + CHS horde size |
| `_et_swaps` | breed/faction substitution + HordeSpawner hooks |
| `_et_mimic` | per-system difficulty mimic |
| `_et_roaming` | roaming size (SIP + recycler guard + ambient density + clone shim) |
| `_et_skaven_warlord_breed` | #324 mod-added breed (MUST precede `_et_champion_warlord`) |
| `_et_champion_warlord` | champion/warlord pools + consolidated spawn hook + crash guards |
| `_et_director_hooks` | ConflictDirector init/refresh re-apply chain |
| `_et_event_size` | terror-event horde size scaling |
| `_et_pacing` | spawn pacing (CD tick #479 guard, freq/caps), #213 freeze guard, #449 rush-intervention freeze gate |
| `_et_banner` | beastman banner toggles |
| `_et_patrol` | patrol formation size |
| `_et_specials` | per-difficulty special spawns |
| `_et_lifecycle` | queued on_setting_changed / batch completion / update drain + on_enabled / on_disabled + BR bootstrap |
| `_et_commands` | chat commands (`/et_status`, `/verify_*`, dumps, `/et_reset`) |
| `_et_boss_tweaks`, `_et_nurgloth_probe` | pre-existing modules (fly-disable duration; issue 275 probe) |
| `_et_boss_balance` | #450 per-boss balance toggles (health/armor/warp-lightning; pure data mutation, no hooks) |
| `_et_boss_grudge` | #531 grudge-mark behavioral knobs (Skarrik Berserk / Bodvarr Crippling on Cata+ Adventure); single `hook_safe` on `ConflictDirector._post_spawn_unit`, applies vanilla CW grudge-mark buff templates host-side |

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
versions of boot-time / hit-time crashes from missing entries). Walk
every step before shipping a mod that calls `Breeds[name] = ...`.

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

### Pattern: eager direct-table writes at the breed-registration site

For each table, find the file-level write path and call it directly
(or write into the global table directly) immediately after adding to
`Breeds`:

```lua
-- threat_values: ConflictDirector.set_threat_value ignores `self`
local CD = rawget(_G, "ConflictDirector")
if CD and CD.set_threat_value then
    CD.set_threat_value(nil, breed_name, breed.threat_value or 0)
end

-- StatisticsDefinitions: direct table write; _create_stat re-reads lazily
-- CRITICAL: every emitted entry MUST have a `name` field, even when the
-- source decompile shows vanilla without it. _init_backend_stat at
-- statistics_database.lua line 102 (live) uses `if definition.name`
-- as its leaf marker; without it, recursion walks into `database_name`
-- string children and crashes on pairs(string). The decompile in our repo
-- is stale on this; live vanilla entries DO include `name`.
local sd = rawget(_G, "StatisticsDefinitions") and StatisticsDefinitions.player
if sd and sd.damage_dealt_per_breed then
    sd.damage_dealt_per_breed[breed_name] = { value = 0, name = breed_name }
    sd.kills_per_breed_persistent[breed_name] = {
        source = "player_data", value = 0, name = breed_name,
        database_name = "kills_per_breed_persistent_" .. breed_name,
    }
    -- and the per-difficulty children: name = breed_name .. "_" .. difficulty
    -- mirror the FULL vanilla loop: kills_per_breed{,_persistent,_difficulty},
    -- kill_assists_per_breed{,_difficulty}, kills_per_race[breed.race]
end

-- PerformanceManager._activated_per_breed: hook PerformanceManager.init
-- to seed our breeds when the manager is constructed (per-mission, so a
-- direct table write at mod load doesn't help — the table is replaced).
```

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

**The right pattern:** register threat values **directly via the
static method** in the same place the breed is added to `Breeds`.
`ConflictDirector.set_threat_value(self, name, value)` doesn't use
`self`; it just writes to the file-local upvalue. Call it as:

```lua
local CD = rawget(_G, "ConflictDirector")
if CD and CD.set_threat_value then
    CD.set_threat_value(nil, breed_name, breed.threat_value or 0)
end
```

This runs at module load (alongside the breed registration) and is
impervious to hook-disable.

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

### Full checklist for any new breed-adding mod

Before shipping a mod that calls `Breeds[name] = ...`:

1. `ConflictDirector.set_threat_value(nil, name, threat_value)` —
   threat_values upvalue.
2. `StatisticsDefinitions.player.*_per_breed[name] = { ... }` (and
   per-difficulty subtables) — vanilla loop is
   statistics_definitions.lua:615.
3. `PerformanceManager.init` hook to extend
   `self._activated_per_breed[name] = 0` — table is rebuilt per
   mission, so seed in init.
4. `NetworkLookup.breeds` (forward + reverse, with `rawget` for the
   existence check — strict `__index` metatable will crash on
   missing-key GET).
5. `BreedActions[name]` — usually a deep_copy of a similar breed's
   actions.

Then audit `grep -n 'pairs(Breeds)'` in the source decompile for any
other file-load snapshots — there may be more not yet hit.

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
