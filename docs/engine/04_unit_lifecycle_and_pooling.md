# Engine reference 04 - Unit lifecycle, spawning and pooling

Engine reference for the VT2 unit spawn/despawn/pooling machinery and how our mods sit on it.
Vanilla paths are relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to this monorepo.
Companion docs: `docs/BUG_CLASSES.md` (crash classes cited as `§N`; `#N` is reserved for GitHub issues), `docs/MECHANICS.md`.

---

## 1. Architecture map

| File / class | Single responsibility |
|---|---|
| `scripts/network/unit_spawner.lua` - `UnitSpawner` | The ONE spawn/delete authority for script-spawned units: local spawn (`spawn_local_unit`, :293), networked spawn (`spawn_network_unit`, :336), husk spawn from a game object (`spawn_unit_from_game_object`, :470), deferred deletion queue (`mark_for_deletion`, :185; drained by `remove_units_marked_for_deletion`, :246), corpse death-watch list (:88-183), per-unit destroy listeners (:509-532). |
| `scripts/network/unit_storage.lua` - `NetworkUnitStorage` | unit <-> go_id bimap plus owner-peer map (`add_unit_info` :122, `go_id` :51, `unit` :57). Frozen units move to a separate bimap (`freeze` :33 / `unfreeze` :40) so `go_id(unit)` returns nil while pooled. |
| `scripts/managers/entity/entity_manager2.lua` - `EntityManager2` | Extension add/register/unregister per unit. `unregister_units` (:321) tears down all extensions and nils `POSITION_LOOKUP[unit]` (:334). `freeze_extensions` (:308) trims corpse extensions. `game_object_unit_destroyed` (:399) notifies extensions when the husk's game object dies. |
| `scripts/utils/global_utils.lua` | The global lookup tables. `POSITION_LOOKUP` (:12), `BLACKBOARDS` (:13), `HEALTH_ALIVE` (:14), **`ALIVE = POSITION_LOOKUP` - an alias, not a separate table** (:15), `FROZEN` (:16), `BREED_DIE_LOOKUP` (:21). `UPDATE_POSITION_LOOKUP()` (:29) bulk-refreshes positions via `EngineOptimized.update_position_lookup`. |
| `scripts/entity_system/systems/position_lookup/position_lookup_system.lua` | Seeds `POSITION_LOOKUP[unit]` on extension add (:20) and nils it on remove (:34). Its `update` is a **no-op** (:13) - the per-frame refresh is the engine call above, NOT this system. |
| `scripts/managers/conflict_director/conflict_director.lua` - `ConflictDirector` | Host-side AI population owner: spawn queue (`spawn_queued_unit` :1732, `update_spawn_queue` :1835, `_spawn_unit` :1905, `_post_spawn_unit` :2029), spawned-unit bookkeeping (`_remove_unit_from_spawned` :2188), kill/destroy funnels (`register_unit_killed` :2344, `register_unit_destroyed` :2371, `destroy_unit` :2403, `destroy_all_units` :2418). |
| `scripts/managers/conflict_director/breed_freezer.lua` - `BreedFreezer` | Whole-unit pooling ("freezer") for 13 trash breeds (pool sizes :29-69). Freezes dead trash into an off-map box instead of deleting (`commit_freezes` :300), resurrects them for new spawns (`try_unfreeze_breed` :389 / `unfreeze_unit` :450). Client mirror via `rpc_breed_freeze_units` (:273) / `rpc_breed_unfreeze_breed` (:419); hot-join sync :492. |
| `scripts/unit_extensions/generic/death_reactions.lua` | Per-breed death handling. `ai_default_unit_update` (:386) pushes the corpse to the death watch (:405-406) and, once `data.remove` is set, funnels into `register_unit_destroyed` (:390). |
| `scripts/managers/network/game_network_manager.lua` | Client-side husk creation: `game_object_created` (:560) dispatches to `game_object_created_network_unit` (:583) which calls `UnitSpawner:spawn_unit_from_game_object`. |
| `scripts/network/unit_extension_templates.lua` | Declares which extension classes a unit template gets per role: `self_owned_extensions` (:8), `self_owned_extensions_server` (:38), `husk_extensions` (:70), `husk_extensions_server` (:89), plus `extensions_to_remove_on_death`. Root of BUG_CLASSES §5 (self-owned vs husk class confusion). |
| `scripts/game_state/state_ingame.lua` | The frame driver. Fixes the ORDER of everything above (see section 2.1). |
| `scripts/managers/player/player_bot.lua` / `bulldozer_player.lua` | Player-object despawn: `PlayerBot.despawn` (:88) calls `mark_for_deletion` (:94); `BulldozerPlayer.despawn` (:60) same for humans. |

Two DIFFERENT things are both called "freeze" - do not conflate:

1. **Corpse extension trim**: on death-watch push, `UnitSpawner.freeze_unit_extensions` (unit_spawner.lua:100) strips `extensions_to_remove_on_death` from the ragdoll via `EntityManager2.freeze_extensions` (:308). Unit stays visible as a corpse.
2. **BreedFreezer pooling**: the whole unit is teleported to a hidden box, physics/anim disabled, `FROZEN[unit] = true`, `POSITION_LOOKUP[unit] = nil` (breed_freezer.lua:355-356), go_id parked in the frozen bimap (unit_storage.lua:33). The SAME userdata is later resurrected as a "new" enemy.

---

## 2. Lifecycle and data flow

### 2.1 Frame order (state_ingame.lua) - the load-bearing sequence

```
Managers.mod:update            <- ALL mod.update callbacks + queued chat commands run HERE,
                                  BEFORE the position refresh [memory: reference_vt2_position_lookup_chat_phase_stale]
StateIngame.pre_update
  UPDATE_POSITION_LOOKUP()             state_ingame.lua:808   (bulk refresh of every entry)
  entity_system:commit_and_remove_pending_units   :811        (commit point 1)
  Managers.state.conflict:pre_update   :823  -> breed_freezer:commit_freezes (conflict_director.lua:1701)
  entity_system:commit_and_remove_pending_units   :824        (commit point 2)
StateIngame.update                     (extension systems tick; ConflictDirector.update
                                        -> update_spawn_queue, conflict_director.lua:1654)
StateIngame.post_update
  unit_spawner:spawn_queued_units      state_ingame.lua:1796  (async network spawns)
  unit_spawner:update_death_watch_list :1801                  (ragdoll cap enforcement)
  conflict:post_update                 :1802 -> commit_freezes (conflict_director.lua:1707)
  entity_system:commit_and_remove_pending_units   :1803       (commit point 3)
```

`commit_and_remove_pending_units` (unit_spawner.lua:211) alternates "register pending extensions" and "drain deletion queue" until both are empty, so a `mark_for_deletion` issued anywhere in a frame is fully destroyed by the next commit point, not "one frame later" in general - but code that runs BETWEEN the destruction and its own next tick can still see stale references (section 4.1).

On level exit (`StateIngame.on_exit`), after a final commit (:1918) every remaining stored unit is destroyed DIRECTLY via `World.destroy_unit` (:1924-1928) - destroy listeners and flow events are NOT run on that path.

### 2.2 Host AI spawn

1. Anything that wants an enemy calls `ConflictDirector:spawn_queued_unit(breed, boxed_pos, boxed_rot, category, anim, type, optional_data, group_data, unit_data)` (conflict_director.lua:1732). It requests the breed package (`enemy_package_loader:request_breed`, :1740 - may substitute a replacement breed) and appends to `self.spawn_queue`. Returns a `spawn_queue_id`.
2. `update_spawn_queue` (:1835) pops one entry per tick once `is_breed_loaded_on_all_peers` (:1847). It FIRST tries the freezer (`breed_freezer:try_unfreeze_breed`, :1859); only on a miss does it run the full `_spawn_unit` (:1867).
3. `_spawn_unit` (:1905) builds `extension_init_data` (health with `optional_data.max_health_modifier`, :1948-1954; ai/locomotion/death/etc :1957-2001), calls `optional_data.prepare_func` (:2003), then `Managers.state.unit_spawner:spawn_network_unit` (:2022).
4. `UnitSpawner.spawn_network_unit` (unit_spawner.lua:336): `spawn_local_unit` seeds `POSITION_LOOKUP[unit]` (:302) -> extensions created and registered (:309-324) -> `GameSession.create_game_object` (:346) -> `unit_storage:add_unit_info` (:348). Clients receive the game object and build the husk (2.3).
5. `_post_spawn_unit` (conflict_director.lua:2029) does ALL bookkeeping: spawn_queue_id LUT (:2030), per-side `spawned`/`spawned_lookup` arrays (:2063-2073), breed counters, **event `"ai_unit_spawned"`** (:2090), `locomotion_extension:ready` (:2102), `optional_data.spawned_func` (:2105-2107), flow event `lua_ai_unit_spawned` (:2123).

`spawn_unit_immediate` (:1893) bypasses the queue AND the freezer; vanilla only routes breed-pickups through it (scripts/settings/equipment/pickups.lua:147,179).

### 2.3 Client husk spawn

`GameSession` game-object-created callback -> `GameNetworkManager.game_object_created` (game_network_manager.lua:560) -> template's `game_object_created_func_name` -> `game_object_created_network_unit` (:583) -> `UnitSpawner.spawn_unit_from_game_object` (unit_spawner.lua:470): creates the unit, `NetworkUnit.set_is_husk_unit(unit, true)` (:474), runs the go-type's extractor to build `extension_init_data` (:484), creates HUSK extensions (per `husk_extensions` lists, unit_extension_templates.lua:70-113). Husk teardown: server destroys the game object -> `UnitSpawner.destroy_game_object_unit` (:492) - note it force-unfreezes a frozen unit (:498-502) before `mark_for_deletion`.

Husk gotchas that live at THIS seam: a husk resolves the BASE `item_data`, never a modded instance (BUG_CLASSES §27, cwv issue #392); hot-join husks can tick attachment code before the skeleton is ready - guard `Unit.has_node` [memory: reference_vt2_husk_attachment_skeleton_readiness].

### 2.4 Death -> corpse -> removal

1. Health reaches zero -> `AISimpleExtension.die` (scripts/unit_extensions/human/ai_player_unit/ai_simple_extension.lua:414) -> `ConflictDirector:register_unit_killed` (conflict_director.lua:2344) -> `_remove_unit_from_spawned` (:2188): swap-deletes from all spawned arrays, fires `optional_data.despawned_func` (:2262) and event `"ai_unit_despawned"` (:2291). The unit is now OUT of conflict bookkeeping but the corpse still exists.
2. The authoritative death reaction ticks; `ai_default_unit_update` pushes the corpse onto the death watch (death_reactions.lua:405-406) -> `push_unit_to_death_watch_list` (unit_spawner.lua:88) trims corpse extensions (:100-107). The separate client-husk update (`ai_default_husk_update`, death_reactions.lua:507-522) never pushes a death-watch entry, so client-local `RagdollSettings` alone cannot retain a corpse after the host destroys its game object.
3. `update_death_watch_list` (unit_spawner.lua:141) enforces `RagdollSettings.max_num_ragdolls` (:148) by flagging oldest corpses `data.remove = true` (:178).
4. Next death-reaction tick sees `data.remove` -> `register_unit_destroyed(unit, bb, "death_done")` (death_reactions.lua:387-390 -> conflict_director.lua:2371): fires referenced event `"on_ai_unit_destroyed"` (:2380), `breed.run_on_despawn` (:2382), then EITHER `breed_freezer:try_mark_unit_for_freeze` (:2386) OR `unit_spawner:mark_for_deletion` (:2387), and sets `blackboard.about_to_be_destroyed` (:2390).
5. Force-despawn path (recycler, `destroy_all_units`): `ConflictDirector.destroy_unit` (:2403) checks `ALIVE[unit]` then runs `_remove_unit_from_spawned` + `register_unit_destroyed`.

### 2.5 Deletion drain

`mark_for_deletion` (unit_spawner.lua:185) **fasserts if the unit is already destroyed** (:186) and pulls the unit off the death watch (:189-201). The queue drains one unit per `remove_units_marked_for_deletion` call (:246-291, looped to empty at each commit point): destroy listeners (:265) -> flow `cleanup_before_destroy` (:266) -> event manager unregister (:276) -> `entity_manager:unregister_units` (:277; nils `POSITION_LOOKUP` at entity_manager2.lua:334) -> post-cleanup listeners (:280) -> `world_delete_units` (:283): destroys the game object, `unit_storage:remove`, nils `POSITION_LOOKUP` again (:441/:462), flow `unit_despawned`, `World.destroy_unit` (:443-444/:464-465).

### 2.6 BreedFreezer pooling (freeze-unfreeze)

- **Freeze** (host): `try_mark_unit_for_freeze` (breed_freezer.lua:232) queues the unit if the breed pool has room; the actual freeze is DEFERRED to `commit_freezes` (:300), which runs in conflict pre_update AND post_update (conflict_director.lua:1699-1709). Per unit: event `"on_unit_freeze"` (trigger_referenced, :324), each system's `system:freeze(unit, ext, "reason_unspawn")` in reverse order (:329-333), anim/physics off, teleport into the freezer box (:353), `FROZEN[unit] = true`, `POSITION_LOOKUP[unit] = nil` (:355-356), `Unit.set_frozen` (:362), go_id parked (`unit_storage:freeze`, :378), clients told via `rpc_breed_freeze_units` (:373/:383).
- **Unfreeze** (host): `try_unfreeze_breed` (:389) pops the oldest pooled unit, `unit_storage:unfreeze` (:406), tells clients (:413), then `unfreeze_unit` (:450): un-freeze the engine unit, set position/rotation, **re-seed `POSITION_LOOKUP[unit] = pos`, clear `FROZEN`** (:459-460), re-enable anim/physics/visibility, then each system's `system:unfreeze(unit, ext, data)` (:475-481). The spawn then continues in `_post_spawn_unit` only (conflict_director.lua:1861-1865) - `_spawn_unit`'s `extension_init_data` is **never rebuilt** for a pooled unit.
- Consequence: `HealthSystem.unfreeze` (scripts/entity_system/systems/damage/health_system.lua:124) calls `GenericHealthExtension.unfreeze -> reset` which restores `self.unmodified_max_health` captured at the unit's FIRST spawn (scripts/unit_extensions/generic/generic_health_extension.lua:90-105). Per-spawn `optional_data.max_health_modifier` and mid-session `Breeds[x].max_health` mutations DO NOT reach freezer resurrections.

### 2.7 Player units

- Spawn: `spawn_local_unit` seeds `POSITION_LOOKUP` BEFORE any extension `init` runs (unit_spawner.lua:302 then :331), so respawn has no nil window [memory: reference_vt2_ai_takeover_despawn_poslookup_crash].
- Despawn: `BulldozerPlayer.despawn` (bulldozer_player.lua:60) / `PlayerBot.despawn` (player_bot.lua:88) -> `mark_for_deletion`. `PlayerManager.remove_player` also fires on LEVEL TRANSITIONS, not just disconnects (BUG_CLASSES §24) - never key persistent caches on it.

### 2.8 Global lookup semantics (memorize this table)

| Global | Written by | Nil'd by | Meaning |
|---|---|---|---|
| `POSITION_LOOKUP[unit]` | seed at spawn (unit_spawner.lua:302; position_lookup_system.lua:20), bulk refresh each frame (state_ingame.lua:808) | unregister (entity_manager2.lua:334), delete (unit_spawner.lua:441/462), freeze (breed_freezer.lua:356) | last engine-refreshed position. Entries are FRAME-POOL Vector3 handles - dead in mod-code phases (§21). |
| `ALIVE` | **alias of POSITION_LOOKUP** (global_utils.lua:15) | same | "registered and positioned", NOT "not dead". Corpses on the death watch are still ALIVE; frozen pooled units are not. |
| `HEALTH_ALIVE[unit]` | health extension (`reset` sets true, generic_health_extension.lua:108) | on death | "has health > 0". Use for combat targeting. |
| `BLACKBOARDS[unit]` | ai system on spawn | on unregister | AI blackboard; `blackboard.about_to_be_destroyed` set at conflict_director.lua:2390. |
| `FROZEN[unit]` | breed_freezer.lua:355 | breed_freezer.lua:460, unit_spawner.lua:499 | unit is parked in the freezer box. |

---

## 3. Hookable seams

| Seam | Side | What it is good for | Safe pattern |
|---|---|---|---|
| `ConflictDirector.spawn_queued_unit` | host | Breed substitution / spawn vetoes for EVERY queued AI spawn, upstream of both the freezer and the package loader. | Full `mod:hook`, swap `breed` arg before `func`. Our canon: `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua:1287` (consolidated - merge into it, never add a 2nd hook). |
| event `"ai_unit_spawned"` (conflict_director.lua:2090) / `"ai_unit_despawned"` (:2291) | host | Post-spawn/post-despawn per-unit work without hooking. | `Managers.state.event:register(ctx, "ai_unit_spawned", cb)`; args `(unit, breed_name, side_id, master_event_id)`. |
| `optional_data.prepare_func` / `spawned_func` / `despawned_func` | host | Per-spawn callbacks for spawns WE initiate (conflict_director.lua:2003, 2105, 2262). | Set fields on the `optional_data` you pass to `spawn_queued_unit`. Used by vanilla debug spawns via `breed.debug_spawn_optional_data`. |
| `Managers.state.unit_spawner:add_destroy_listener(unit, id, cb, post_cleanup)` (unit_spawner.lua:509) | both | Per-unit destruction notification (runs at delete drain, :265/:280). | Unique `id` per mod (duplicate id on same unit fasserts, :518). NOT called on level-exit teardown (state_ingame.lua:1924). Remove with `remove_destroy_listener` (:523). |
| `BreedFreezer.try_mark_unit_for_freeze` / event `"on_unit_freeze"` (breed_freezer.lua:324, trigger_referenced) | host / both | Clearing per-unit mod state before the userdata is recycled; freeze-flow guards. | et's double-freeze guard: `enemy_tweaker.lua:1714-1744` (issue #213). Register referenced event per unit for state cleanup. |
| `UnitSpawner.mark_for_deletion` | both | Observing despawn start (last moment the unit is intact). | `hook_safe` is fine; never CALL it yourself on a unit that may already be queued - pre-check `Unit.alive(unit)` and `unit_spawner:is_marked_for_deletion(unit)` (unit_spawner.lua:204) or the fassert at :186 kills the game. |
| Extension `update` guards (`PlayerWhereaboutsExtension`, `AICommanderExtension`, `RoundStartedSystem`...) | crashing peer | Nil-guarding vanilla readers during the 1-frame despawn window. | `mod:hook(Ext, "update", function(func, self, unit, ...) if not (unit and Unit.alive(unit) and POSITION_LOOKUP[unit]) then return end return func(self, unit, ...) end)` - bail the WHOLE tick; a positionless unit has nothing to track. Ours: `general_tweaker_dev/.../general_tweaker_dev.lua:531`, `_gt_hacks.lua:507`, `_gt_hacks.lua:523`. |
| `GearUtils.spawn_inventory_unit` / `create_equipment` | both | Weapon/attachment unit spawning for players INCLUDING husks (the seam that sees remote peers). | Full wrapper; ours: `character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:4741`. Husk resolves BASE item_data - re-key off base+career, not owner state (§27). |
| `ConflictDirector.destroy_all_units` (:2418) | host | Bulk despawn (respects `debug_despawn_immunity`). | CALL it, don't reimplement: `general_tweaker_dev/.../_gt_creature_spawner.lua:531`. |
| `World.spawn_unit` | local | Missing-resource fallback for debug spawning. | `_gt_creature_spawner.lua:1052-1056` gates on `Application.can_get("unit", name)` and substitutes `units/hub_elements/empty` - copy this, a bad path is an uncatchable engine fatal. Never `Managers.package:load` a bare unit path (§28). |

**Seam traps:**
- Extension classes are split self-owned vs husk with NO inheritance (unit_extension_templates.lua:8 vs :70) - hook both or hook a shared global (§5). A guard on a `self_owned` extension only protects the peer RUNNING the patched build; every peer needs the fix [memory: reference_vt2_ai_takeover_despawn_poslookup_crash].
- `spawn_unit_immediate` (conflict_director.lua:1893) bypasses `spawn_queued_unit` hooks (vanilla: pickups only).
- A freezer-satisfied spawn bypasses `_spawn_unit` entirely (conflict_director.lua:1859-1865) - hooks on `_spawn_unit` miss ~all trash respawns mid-mission; hook `spawn_queued_unit` (upstream) or `_post_spawn_unit`/`"ai_unit_spawned"` (downstream) instead.
- RPC receivers (`rpc_breed_freeze_units` etc.) ARE hookable - NetworkEventDelegate dispatch is dynamic [memory: reference_vt2_rpc_dispatch_dynamic_hookable].

---

## 4. Traps and crash classes

### 4.1 One-frame despawn nil deref (POSITION_LOOKUP is nil, unit reference lingers)

Despawn nils `POSITION_LOOKUP[unit]` (entity_manager2.lua:334; unit_spawner.lua:441/462) but side tables (`RoundStartedSystem._units`, commander unit lists, our own caches) can hold the unit for one more tick. Any vanilla extension that derefs the entry unguarded is an ENGINE fatal, not a Lua error. Two shipped hits from gt AI-takeover's `player:despawn()` (`_gt_ai_takeover.lua:182`): `AICommanderExtension._update_units` `__add` on host, `PlayerWhereaboutsExtension` `triangle_from_position` on client [memory: reference_vt2_ai_takeover_despawn_poslookup_crash]. Guard shape in section 3. Related but distinct from §21. Respawn is safe (seed-before-init, unit_spawner.lua:302).

### 4.2 POSITION_LOOKUP dead handle in mod-code phases - BUG_CLASSES §21

`mod.update` and chat commands run before `UPDATE_POSITION_LOOKUP()` (state_ingame.lua:808), so the LOCAL PLAYER's entry is a dead frame-pool Vector3 there (`PositionLookupSystem.update` is a no-op, position_lookup_system.lua:13). READ live: `Unit.world_position(unit, 0)`. CALL-THROUGH into a vanilla reader (e.g. `teleport_to`): seed `POSITION_LOOKUP[unit] = Vector3(dest)` first. Our enforcement: `_gt_debug_highlights.lua:122-126` live reads; `_gt_bot_teleport_lab.lua:1031-1042` `_live_pos`. Inside hooked engine-phase code (BT actions, system updates) raw entries are fresh that frame - the nil-guard (4.1) is the only thing needed there (`_gt_improved_bot_combat.lua:232-236`, `_gt_bot_fixes.lua:264-266`).

### 4.3 `ALIVE` does not mean alive

`ALIVE = POSITION_LOOKUP` (global_utils.lua:15). Corpses on the death watch pass `ALIVE[u]`; frozen pooled units and mid-delete units fail it. For "can I fight it" use `HEALTH_ALIVE[u]` (the aid selector does this in `_gt_bot_aid_owner.lua`). For "can I touch the unit at all" use `Unit.alive(unit)` + `ALIVE[unit]`.

### 4.4 Pooled units are recycled userdata

The freezer resurrects the SAME unit userdata with the same go_id. Any mod table keyed by unit (`[unit] = state`) leaks last-life state into the next spawn unless cleared on `"on_unit_freeze"` (breed_freezer.lua:324) or `"ai_unit_despawned"` (conflict_director.lua:2291). Weak-keyed tables do NOT save you here - the key never dies. Also: health resets to first-spawn `unmodified_max_health` (generic_health_extension.lua:105), so breed-stat mutations and per-spawn health modifiers silently miss freezer respawns (section 2.6).

### 4.5 Double freeze - engine ERROR spam (et issue #213)

Two same-frame `destroy_unit` calls on one unit re-mark it because the actual freeze is deferred to `commit_freezes`; vanilla prints `ERROR: Tried to freeze unit twice` (breed_freezer.lua:253) and falls through to `mark_for_deletion`, conflicting with the queued freeze. Our guard replicates vanilla's own duplicate check and returns true ("handled"): `enemy_tweaker.lua:1714-1744`.

### 4.6 mark_for_deletion fassert / destroy-listener collisions

`mark_for_deletion` on a destroyed unit fasserts (unit_spawner.lua:186); `add_destroy_listener` with a duplicate identifier fasserts (:518); `destroy_game_object_unit` fasserts on unknown go_id (:496). Pre-check `Unit.alive` / `is_marked_for_deletion` / use a namespaced identifier.

### 4.7 Level-exit teardown bypasses everything

`StateIngame.on_exit` destroys remaining units raw (state_ingame.lua:1924-1928): no destroy listeners, no `unit_despawned` flow. Do final cleanup from game-state-change callbacks, not destroy listeners. `CLEAR_ALL_PLAYER_LISTS` (global_utils.lua:72) wipes all globals between rounds.

### 4.8 Related classes elsewhere in the catalog

- §5 self-owned vs husk extension confusion (hooks silently no-op on one side).
- §24 `remove_player` fires on level transitions (peer-keyed caches wiped every map).
- §27 husk resolves BASE item_data (owner-path logic cannot reach a remote player).
- §28 mod-bundled unit path in `Managers.package:load` = async boot fatal.
- Death-watch corpses keep ticking their death reaction (death_reactions.lua:386) - a hook there runs on EVERY corpse every frame; keep it O(1).

---

## 5. Implications for our mods

### 5.1 Where we already sit on the right seams (do not "improve")

- **et breed swap** at `spawn_queued_unit` (`enemy_tweaker.lua:1287`) - upstream of freezer + package loader, host-only, consolidated single hook. Correct choke point.
- **gt creature spawner** spawns via `conflict_director:spawn_queued_unit` with `debug_spawn_optional_data` (`_gt_creature_spawner.lua:493-494`) and despawns via `destroy_all_units` (:531) - 1:1 with vanilla debug flow, no private unit list to desync.
- **gt bot lab** snapshots positions with `Vector3Box` before teleports (`_gt_bot_teleport_lab.lua:421-427`) and live-reads in the draw phase (:1031-1042) - both lifecycle-correct.
- **et double-freeze guard** (`enemy_tweaker.lua:1714`) reads vanilla's own `units_to_freeze` state - no frame guesswork.
- **gt AI-takeover crash guards** (`general_tweaker_dev.lua:531`, `_gt_hacks.lua:507`, `:523`) use the canonical bail-the-tick shape.

### 5.2 Concrete improvement candidates

1. **P1, gt_dev regression test is self-defeating** - `general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua:1832` scans `_gt_debug_highlights.lua` with a plain `txt:find("POSITION_LOOKUP[", 1, true)`, but the ban-rationale comment at `_gt_debug_highlights.lua:325` contains that exact substring, so whenever the source file is readable the test reports a false failure (and when it is not, it silently skips - so it can never pass while the documentation comment exists). Fix: strip `--` comment lines before scanning. [static analysis; confirm with an in-game `/gt` regression run]
2. **P2, cosmetics_tweaker `_tpe` cleanup surface** - `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_tpe.lua:516-528` uses FOUR `hook_safe` registrations (`SimpleInventoryExtension`/`SimpleHuskInventoryExtension` x `destroy_slot`/`destroy`) to reap linked 3P units. Engine-idiomatic: one `Managers.state.unit_spawner:add_destroy_listener(owner_unit, "cos_tpe", cb)` per owner at `spawn_3p` time (unit_spawner.lua:509) fires on every listener-running deletion path with a quarter of the hook surface. Keep the existing weak-set sweep as the level-exit backstop (4.7).
3. **P2, gt AI-takeover guard coverage is enumerative** - `_gt_ai_takeover.lua:182-186` opens the 4.1 window for EVERY extension in the player-unit template lists (unit_extension_templates.lua:8-113); we have guarded exactly three readers found by crashing. An audit pass over the remaining `self_owned(_server)` extensions for unguarded `POSITION_LOOKUP[...]` derefs (grep the decompile) would close the class instead of chasing per-site crashes; remember each guard only protects the patched peer.
4. **P2, et breed-stat mutation pattern vs the freezer** - `enemy_tweaker.lua:1149` mutates `Breeds[skaven_storm_vermin_champion].max_health` in place. Safe today ONLY because the champion is not in `BreedFreezerSettings.breeds` (breed_freezer.lua:29-69); if this pattern is copied to a freezable breed (storm_vermin, chaos_warrior...), pooled units resurrect with stale first-spawn health (generic_health_extension.lua:105) and the retune half-applies. Bake the "not-freezable or accept stale pool" check into any future breed-stat toggle.
5. **P2, et spawn-swap blind spot, document only** - the `spawn_queued_unit` hook does not see `spawn_unit_immediate` (conflict_director.lua:1893). Vanilla routes only breed-pickups there (pickups.lua:147,179) so the gap is benign; a one-line comment at `enemy_tweaker.lua:1287` naming the bypass keeps a future session from "fixing" it with a second hook.
6. **P2, gt bot-fix position helper leaks unguarded fallback** - `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_fixes.lua:292-294` returns `p or POSITION_LOOKUP[target_unit]` raw; the helper itself never checks `ALIVE`/`Unit.alive`, so every caller must nil-check (most sampled do). Moving the repo guard shape (`unit and ALIVE[unit] and POSITION_LOOKUP[unit]`) into the helper makes the despawn window unrepresentable for all callers.
