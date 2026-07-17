# Engine reference 05 - Package manager and residency

Scope: the Stingray/VT2 package system - reference-counted load/unload, sync vs async loading,
level-transition package flow, the four networked component loaders, and how wt / cosmetics_tweaker /
cwv / crt / gut use (and misuse) it. Vanilla paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to the monorepo root.
Every claim cites file:line or is marked [unverified].

Related docs: `docs/BUG_CLASSES.md` classes 22, 27, 28; memories
`reference_vt2_la_package_force_load_crash`, `reference_vt2_package_load_needs_package_not_unit_path`,
`reference_vt2_mutator_packages_deus_only`, `reference_vt2_lua_heap_1gib_crash`.

---

## 1. Architecture map

| File / class | Single responsibility |
|---|---|
| `foundation/scripts/managers/package/package_manager.lua` - `PackageManager` (plain global table, `Managers.package`) | The one reference-counted registry of resource packages. Owns `_packages` (fully resident handles), `_asynch_packages` (in-flight), `_queued_async_packages` + `_queue_order` (waiting), `_references` (per-package `{reference_name -> count}`), `_delayed_packages_to_remove` (init at :11-18). Everything else in the game calls into this. |
| `scripts/boot_init.lua` - `GlobalResources` | Platform-selected list of packages that stay resident for the whole process (`boot_init.lua:84-160`), loaded under reference `"global"` with a has_loaded/is_loading gate (`boot_init.lua:195-202`). |
| `scripts/boot.lua:1759-1781` | Boot-time `"global"` loads of `menu_assets_common`, `ingame`, `inventory`, `careers`, `pickups`, `decals`. `"global"` is the ENGINE's own session-lifetime reference name - mods must not borrow it (see section 5). |
| `scripts/game_state/components/level_transition_handler.lua` - `LevelTransitionHandler` | Per-level package churn. Loads `LevelSettings[level_key].packages` + `hero_specific_packages` + `extra_packages` under reference `= level_key`, unloads them on transition. Owns the four component loaders below (`level_transition_handler.lua:33-36`). |
| `scripts/game_state/components/enemy_package_loader.lua` - `EnemyPackageLoader` | Server-decided, network-synced breed package residency. Single reference name `"EnemyPackageLoader"` (`enemy_package_loader.lua:9`). Server marks a session breed map, every peer diffs it against local state and loads/unloads (`:344-395`). Lock/unlock counting protects in-use breeds (`:274-308`). |
| `scripts/game_state/components/pickup_package_loader.lua` - `PickupPackageLoader` | Same server-map/peer-diff pattern for dynamic pickups. Per-pickup reference `"PickupPackageLoader_<name>"` (`pickup_package_loader.lua:101-111`). Loads the pickup unit path plus the temporary weapon template's hand units and their `_3p` forms (`:185-215`), unloads symmetrically (`:217-243`), and drains at shutdown (`:325-342`). |
| `scripts/game_state/components/transient_package_loader.lua` - `TransientPackageLoader` | Short-lived synced packages under reference `"TransientPackageLoader"` (loads `:119`, unloads `:94,133,137`). |
| `scripts/game_state/components/general_synced_package_loader.lua` - `GeneralSyncedPackageLoader` | Fourth component loader created at `level_transition_handler.lua:36` [unverified beyond instantiation - same family]. |
| `scripts/game_state/state_ingame_running.lua:783-787` | End-of-round chest package loaded under `"global"`; readiness gated on `has_loaded(pkg, "global")` (`:870`). |
| `ResourcePackage.*` / `Application.resource_package` (C API) | The actual engine load/flush/unload. `PackageManager` is only bookkeeping around these calls (`package_manager.lua:81-98, 214-215`). Failures here are C-level fatals that bypass pcall. |

Key mental model: a package is unloaded only when EVERY reference name's count reaches zero
(`package_manager.lua:196-238`). Reference names are namespaces, not owners - any code can decrement
any name, and unload with an unknown name is an assert (`:199`); unload of a never-loaded package is
a nil-index Lua error (`:197`).

---

## 2. Lifecycle and data flow

### 2.1 `PackageManager.load(package_name, reference_name, callback, asynchronous, prioritize)`

The 4th arg is `asynchronous`, NOT "force"/"persistent" - persistence comes from holding the
reference (`package_manager.lua:20`; burned in memory `reference_vt2_la_package_force_load_crash`).

| State of package | What load() does |
|---|---|
| Already referenced (any name) | Pure refcount bump: `_references[pkg][ref] = (n or 0) + 1` (`:26-27`). If fully resident, `callback` fires synchronously (`:56-58`). EVERY call increments - there is no idempotence. |
| In-flight async, you ask sync | `force_load` - blocking flush right now, then callbacks (`:29-34, 103-130`). |
| Queued async, you ask sync | `force_load_queued_package` - blocking load+flush (`:35-40, 132-158`). |
| In-flight/queued async, you ask async | Your callback appended; `prioritize` moves it to queue front (`:41-55`). |
| First reference, sync | `Application.resource_package` + `ResourcePackage.load` + `ResourcePackage.flush` inline - blocks the frame (`:80-86`). |
| First reference, async, another async in flight | Queued (`:68-79`); popped one at a time by `_pop_queue` (`:160-194`). |
| First reference, async, nothing in flight | `ResourcePackage.load` started; completion detected in `update` (`:87-98, 306-316`). |

`update(dt)` pumps one finished async package per frame into `force_load` (`:306-316`) and retries
delayed unloads (`:318-326`). It returns true when nothing is loading (`:328`) - loading screens
poll this.

### 2.2 Unload

`unload(package_name, reference_name)` decrements that name's count; when the whole `_references[pkg]`
table empties, the engine unloads - immediately if `ResourcePackage.can_unload` (`:209-219`), else
parked in `_delayed_packages_to_remove` and retried each update (`:220-226, 318-326`). If other
references remain it only debug-prints `"Package still referenced, NOT unloaded"` (`:236`).

`destroy()` (shutdown) loops every package and calls `unload` once per remaining refcount
(`:254-273`) - this is why a leaked refcount of N produces N-1 shutdown log lines of
"still referenced" plus the engine's `'#ID[...]' not unloaded, this can potentially cause an
deadlock!` when a delayed package survives (`:275-279`). That exact signature is our issue #282.

### 2.3 Queries

- `has_loaded(pkg, ref?)` - fully resident (in `_packages`, not async/queued); with `ref` it is
  reference-scoped: true only if THAT name holds it (`:286-294`).
- `is_loading(pkg, ref?)` - async or queued (`:282-284`).
- `reference_count(pkg, ref)` / `num_references(pkg)` (`:296-304, 331-342`).
- `dump_reference_counter(ref)` - prints every package a reference name holds (`:396-408`); useful
  for leak forensics.

### 2.4 Level transition flow (who loads what, in order)

1. Server picks the next level; `set_next_level` builds `_next_level_data` and appends live-event
   mutator packages into `extra_packages` (`level_transition_handler.lua:444-465, 468-516`;
   mutator `packages` fields consumed at `:502-515` - Deus-only trap, memory
   `reference_vt2_mutator_packages_deus_only`).
2. On the transition, the handler releases the previous level's extra packages and level packages
   (`:193-197`), then loads the new set (`:202-205`), marking `loading_packages[level_key]`
   (`:214`).
3. `_load_level_packages` loads `LevelSettings[level_key].packages` and the local hero's
   `hero_specific_packages`, all async, all under reference `= level_key` (`:518-560`).
4. `update` polls until every package `has_loaded`, then flips `loaded_levels[level_name]`
   (`:141-147`).
5. `_unload_level_packages` unloads in reverse order, guarded by
   `has_loaded(pkg, ref) or is_loading(pkg)` so a half-loaded transition doesn't assert
   (`:562-591`).

### 2.5 EnemyPackageLoader flow (the networked model)

Server-only writes: `request_breed` -> `_load_package` marks `_session_breed_map[breed] = true` and
pushes the map to peers (`enemy_package_loader.lua:310-321`). Every peer (server included) runs
`_update_package_diffs`: anything in the local loaded map but not the session map is unloaded
(`:360`); anything in the session map not yet loaded is loaded ONLY after a
`has_loaded`/`is_loading` gate (`:372-375`). Unload is fenced by startup-breed and lock asserts
(`:326-332`); locks are counted, with an over-unlock fassert (`:274-300`). Shutdown drains
everything under the one reference name (`:916-928`). This is the engine's canonical
"load once, gate on has_loaded, unload symmetric, drain at shutdown" idiom.

PickupPackageLoader mirrors it with per-pickup reference names and the unit-path convention: it
loads UNIT paths (`AllPickups[name].unit_name`, weapon hand units, `_3p` siblings) directly through
`Managers.package:load` (`pickup_package_loader.lua:185-215`) - proof that vanilla per-unit
"synthetic packages" are loadable, which is what our force-loads imitate.

---

## 3. Hookable seams (and the callable seams that replace hooks)

Mods rarely need to HOOK this subsystem - the supported seam is CALLING it with your own reference
name. Ranked by safety:

| Seam | Safe pattern | Traps |
|---|---|---|
| `Managers.package:load(pkg, "<mod>_<purpose>", cb, true, prioritize)` | Own, mod-prefixed reference name; gate with `if not pm:has_loaded(pkg, ref) and not pm:is_loading(pkg, ref) then pm:load(...) end` (vanilla form: `enemy_package_loader.lua:372-375`, `boot_init.lua:195-198`). pcall the call (`pcall(pm.load, pm, ...)`). | pcall only covers the ENQUEUE; a bad async load fatals later in `_pop_queue`/`force_load` outside any Lua frame (BUG_CLASSES 28; memory `reference_vt2_package_load_needs_package_not_unit_path`). Every ungated call is +1 refcount forever. |
| Keep-alive pin of a THIRD-PARTY package | Only bump when already resident: `if pm:has_loaded(PKG) then pcall(pm.load, pm, PKG, REF, nil, true) end` - then load() is a pure refcount increment, no re-materialize. Canonical impl: `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_la_atlas_keepalive.lua:38-78`. | Force-loading a non-resident package whose bundle you don't control (LA's is missing a member) = uncatchable C fatal every keep entry (memory `reference_vt2_la_package_force_load_crash`, crash GUID ca939793). |
| On-demand load with completion callback | Ref-scoped `has_loaded(pkg, ref)` fast path, an in-flight latch + `is_loading(pkg, ref)` re-press guard, then async load with the open/act callback. Canonical impl: `_gut_mission_hero_select.lua:279-321`. | Each extra load() call adds a refcount AND another callback = double-fire (`_gut_mission_hero_select.lua:288-293`). Callbacks fire synchronously if already resident (`package_manager.lua:56-58`) - your callback must tolerate running inside the load() call. |
| `Managers.package:unload(pkg, ref)` | Only unload names you own, exactly as many times as you loaded, and only when `has_loaded(pkg, ref) or is_loading(pkg)` (vanilla guard: `level_transition_handler.lua:573,586`). | Unknown ref = assert (`package_manager.lua:199`); never-loaded package = nil-index error (`:197`). Interleaving unloads with a vanilla loader's own cycle on the same package is fragile - gut deliberately retains instead (`_gut_mission_hero_select.lua:89-97`). |
| Hooking `PackageManager.load`/`unload` for diagnostics | Observe-and-delegate only (log then `return func(...)`) - viable for the issue-282 ref ledger. `PackageManager` is a plain global table (`package_manager.lua:9`), so table-form hook works. | Never divert flow (memory `reference_vt2_guard_that_delegates_still_crashes`). Grep for existing hooks first (NON-NEGOTIABLE 8). No mod in this repo currently hooks it [verified by the repo-wide grep for `package:load` 2026-07-11]. |
| `LevelTransitionHandler` `extra_packages` / mutator `packages` | Let the engine load event content by registering mutator `packages` - but ONLY for Deus flows. | The `packages` field on mutator templates crashes Adventure levels (memory `reference_vt2_mutator_packages_deus_only`; et learned this). |
| `script_data.package_debug = true` | Turns on `[PackageManager]` load/unload prints (`package_manager.lua:3-7`) - cheapest residency tracing there is. | Verbose. |

What counts as loadable:
- `resource_packages/...` package paths - always (they are real packages).
- Vanilla weapon unit paths under `units/weapons/player/...` (+ `_3p` siblings) - yes, per the
  pickup-loader convention (`pickup_package_loader.lua:191-211`; proven across cwv sessions).
- MOD-BUNDLED unit paths (`units/<mod>_...`) - NEVER: queuing one is an uncatchable async boot
  fatal (BUG_CLASSES 28, issue 403). Filter: `u:find("units/weapons/player/", 1, true) == 1`
  (`character_weapon_variants.lua:4529`).
- Paths in `NetworkLookup.inventory_packages` load even when `Application.can_get("package", p)`
  is false (`cosmetics_tweaker.lua:2048-2067`) - so a can_get pre-gate must special-case that list.

---

## 4. Traps and crash classes

| # | Trap | Detail / citation |
|---|---|---|
| 1 | pcall cannot catch package fatals | `load()` returns after enqueue; the fatal fires in `PackageManager.update -> _pop_queue -> force_load` from `boot.lua`'s frame. Crash log shows `package_manager.lua:194/137`, no mod file. BUG_CLASSES 28 (`docs/BUG_CLASSES.md:1225`), same uncatchable family as class 22 (`:1015`). |
| 2 | Refcounts are not idempotent | Every `load()` is +1 (`package_manager.lua:26-27`). Any per-spawn / per-frame / per-toggle call site leaks. Issue #282 is this class (see 5.1). |
| 3 | `"global"` is the engine's reference name | Boot and end-of-round content live under it (`boot.lua:1759-1781`, `state_ingame_running.lua:787`). A mod leaking under `"global"` is indistinguishable from engine state in `dump_reference_counter`, and its leak spam at shutdown looks like an engine bug. |
| 4 | Sync load blocks the frame | First-reference sync = load+flush inline (`package_manager.lua:80-86`); sync on an in-flight async = force_load blocking flush (`:29-34`). 74 sync loads at boot is a boot stall (see 5.4). |
| 5 | Unload asserts / errors | Unknown ref asserts (`:199`); never-loaded package nil-indexes (`:197`); a still-in-use package parks in delayed removal and warns `Locking a resource that is about to be unloaded!` if raced [log signature per issue #282]. |
| 6 | Non-resident unit spawn is a C assert | `World.spawn_unit` on a non-resident unit fatals at `c_api_world.cpp:67`, bypassing pcall - residency is the crash floor for husk/preview spawns (BUG_CLASSES 27, `docs/BUG_CLASSES.md:1183`; cosmetics' guard at `_material_hijack_embedded.lua:354-373`). |
| 7 | Force-loading a broken third-party bundle | Missing internal member = C fatal on materialize. Only refcount-bump when already resident (memory `reference_vt2_la_package_force_load_crash`; fix shipped in gut `_la_atlas_keepalive.lua`). |
| 8 | DLC packages on non-owners | A non-owner may not even have the bundle installed; force-load = async crash. Gate on ownership, with boot-package residency (`resource_packages/dlcs/<id>`) as the timing-safe owner proxy because `is_dlc_unlocked` can be unresolved at mod-init (`weapon_tweaker.lua:3958-3997`). |
| 9 | Package memory is NOT the Lua heap | Force-loaded packages are C++ resource-pool memory; `collectgarbage("count")` never sees them (`cosmetics_tweaker.lua:3249-3254`). Blanket mission-load force-loads still contributed to the 1 GiB Lua-heap crash via bookkeeping + retention (memory `reference_vt2_lua_heap_1gib_crash`). Bounded boot-time sets are the pattern (`character_weapon_variants.lua:4494-4498`). |
| 10 | Mutator `packages` field is Deus-only | Registering it on Adventure mutators crashes level load (memory `reference_vt2_mutator_packages_deus_only`). |
| 11 | Session retention is legitimate - shutdown leaks are not | Keeping a bounded set resident for the session with ONE ref each is fine and sometimes required (gut rationale `_gut_mission_hero_select.lua:89-97`). Unbounded per-event refcount growth is the bug. `mod.on_unload` fires on VMF reload, not game exit [unverified], so "unload in on_unload" is not a shutdown fix - not leaking per-event is. |

---

## 5. Implications for our mods - concrete improvements

### 5.1 P0 - cosmetics_tweaker MH embed: the issue #282 `"global"` reference leak (VERIFIED)

`cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded.lua:161` -
`_safe_load_package` calls `manager_package:load(path, "global")` with NO has_loaded gate and NO
unload anywhere in the file (grep-verified 2026-07-11: zero `unload` calls). `replace_textures`
calls it once per spawned unit carrying `mat_to_use` data (`:167-184`), and `replace_textures` runs
from the `UnitSpawner.spawn_local_unit` hook (`:354-393`, call at `:384`) plus cosmetics_tweaker's
own `GearUtils.create_equipment` and `_spawn_item_unit` hooks via the module exports (`:341-348,
395-402, 414-418`). Net effect: `_references[pkg]["global"]` grows by 1 per spawn for the whole
session (`package_manager.lua:26-27`), which at `destroy()` produces exactly issue #282's thousands
of `Unload: ... global -> Package still referenced, NOT unloaded` lines plus the
`not unloaded ... deadlock` engine error (`package_manager.lua:254-279`).

Engine-idiomatic fix (two independent parts):
1. Own reference name, never `"global"` - e.g. `"cosmetics_tweaker_mh"` - so leaks are attributable
   via `dump_reference_counter` and never collide with boot state (trap 4.3).
2. Load-once gate, exactly like the file's sibling `_preload_one` already does with
   `_preloaded_offhand_packages` (`cosmetics_tweaker.lua:2044, 2086`):
   `if loaded_set[path] then return end; loaded_set[path] = true;` before the load - or the vanilla
   form `if not pm:has_loaded(path, REF) and not pm:is_loading(path, REF) then pm:load(...) end`
   (`enemy_package_loader.lua:372-375`). Session retention of each package ONCE is correct here
   (the textures stay in use); the per-spawn increment is the whole bug.

### 5.2 P1 - career_tweaker BR toggle loads under `"global"`, restore is a no-op

`career_tweaker/scripts/mods/career_tweaker/career_tweaker_big_rebalance.lua:594` loads seven DLC /
mutator / level packages with reference `"global"`, ungated; `restore` deliberately leaves them
loaded but also forgets them (`:599-602`). Every apply cycle (toggle off/on, `on_enabled` re-apply)
adds +1 per package under the engine's ref name - a slow, session-bounded copy of 5.1, plus
BUG_CLASSES 7 (`on_disabled` not unwinding). Fix: ref `"crt_br_dlc_packages"` + the
has_loaded/is_loading gate; keep the "never unload mid-mission" stance (it is correct - see trap
4.11) but make apply idempotent so re-applies are no-ops.

### 5.3 P1 - cwv `/cwv_give_javelin` re-loads per invocation

`character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:6992-6993`
loads `_TJB_HELD_UNIT` and its `_3p` under ref `"cwv_javelin_bomb"` inside the command body, ungated -
+2 refs per command use. Fix: same has_loaded gate, or hoist to a `do ... end` one-shot with a local
`_loaded` latch like the axe-shield block (`:4441-4444`).

### 5.4 Resolved P2 - cosmetics offhand preload lifecycle (#565)

The pre-fix bulk path performed 74 Cosmetics-owned synchronous loads at startup and produced a
repeatable ~1.58 s `Application::update` stall. The current path queues each load with
`asynchronous=true, prioritize=false` (`cosmetics_tweaker.lua:1488-1502`), while the render gate
requires both the 1P and 3P unit resources to pass `Application.can_get` before exposing an override
(`:1625-1636`). An unfinished load therefore falls back to the base mesh instead of blocking startup
or reaching `World.spawn_unit` early.

Ownership is bounded rather than session-retained: the pure generation ledger deduplicates each
package path, and each accepted acquisition takes one private `cosmetics_tweaker_offhand` reference
(`:1427-1433`, `:1491-1502`). `mod.on_unload` calls `_release_offhand_packages`; release invalidates
the generation first, then unloads the exact sorted ownership snapshot and drains any duplicate
private references (`:1512-1573`). This ordering matters because vanilla can retain our callback on
a shared in-flight handle after our reference is removed (`package_manager.lua:41-48,196-237`): a
late callback must fail its generation token rather than resurrect cleared state. The contract is
locked by `offhand_preload_async_bounded_565` and
`qa/lua/tests/test_cos_offhand_preload_lifecycle.lua`.

### 5.5 P2 - wt / cwv one-shot boot force-loads: correct, keep as the template

These are the GOOD examples to copy: bounded set, one load each, mod-prefixed unique ref names,
pcall'd, async+prioritized, residency re-verified via `has_loaded` -
`weapon_tweaker.lua:3829, 3866, 3920, 3987` (with the DLC ownership + idempotence gate at
`:3961-3985`) and `character_weapon_variants.lua:4338, 4367, 4444, 4547, 5782` (with the
vanilla-path / mod-bundle filter at `:4518-4532` and dedupe sets at `:4441, 4534`). They never
unload, which is acceptable session residency (one ref each, trap 4.11) - do NOT "fix" them by
adding unloads; the husk crash floor needs them resident all session (BUG_CLASSES 27).

### 5.6 P2 - issue #282 diagnostics: use the engine's own tools first

Before building the proposed custom ref ledger, arm what already exists: `script_data.package_debug`
(`package_manager.lua:3-7`) and `Managers.package:dump_reference_counter("global")` /
`("cosmetics_tweaker")` (`:396-408`) dumped at `game_round_ended` show per-ref counts directly. A
diagnostics hook on `PackageManager.load`/`unload` (observe-and-delegate, table-form) is the
escalation, not the first step.

### 5.7 Correct load/unload pairing idiom (the doctrine, in one block)

```lua
local REF = "<mod>_<purpose>"            -- unique, mod-prefixed; NEVER "global"
local pm = Managers.package

-- LOAD (idempotent):
if pm and not pm:has_loaded(pkg, REF) and not pm:is_loading(pkg, REF) then
    local ok, err = pcall(pm.load, pm, pkg, REF, cb, true, prioritize)  -- async
    -- pcall covers the enqueue only; pre-filter pkg (vanilla weapon path or real
    -- resource_packages/ path, can_get/inventory_packages check) BEFORE loading.
end

-- UNLOAD (only if you genuinely stop needing it before session end; skip for
-- session-resident sets):
if pm and (pm:has_loaded(pkg, REF) or pm:is_loading(pkg)) then
    pcall(pm.unload, pm, pkg, REF)       -- exactly one unload per successful load
end
```

Vanilla exemplars: gate `enemy_package_loader.lua:372-375`; symmetric pairs
`pickup_package_loader.lua:185-243`; guarded unload `level_transition_handler.lua:562-591`;
shutdown drain `pickup_package_loader.lua:325-342`. Our exemplars: pin-when-resident
`gui_tweaker_dev/.../_la_atlas_keepalive.lua:38-78`; callback + in-flight latch
`gui_tweaker_dev/.../_gut_mission_hero_select.lua:279-321`.
