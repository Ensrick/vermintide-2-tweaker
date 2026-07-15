# Engine reference 02 - Entity and extension system

Audience: maintainers and AI agents modding VT2 in this monorepo. Goal: act
correctly on entity/extension work WITHOUT re-reading the engine. Vanilla
paths are relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`;
our paths are relative to this monorepo. Every claim cites `file:line` or is
tagged [unverified].

Related docs: `docs/BUG_CLASSES.md` (crash classes cross-referenced in §4),
`docs/MECHANICS.md`, `DEVELOPMENT.md` (hooking rules), `docs/VMF_RECIPES.md`.

---

## 1. Architecture map

| File / class | Single responsibility |
|---|---|
| `scripts/managers/entity/entity_manager2.lua` - `EntityManager2` (= `Managers.state.entity`) | Owns the unit -> extensions bookkeeping: two-phase add (`add_unit_extensions` :72-176), per-extension-name registries (`get_entities` :56-58), system registration (`register_system` :33-44), unregister/teardown (:321-397), freeze (:308-319), game-object sync (:178-198). |
| `foundation/scripts/util/script_unit.lua` - `ScriptUnit` (global, backed by `_G.G_Entities`) | The per-unit extension lookup table. `Entities[unit][system_name] = extension` (:32-41). Fetch APIs :43-78; add/destroy/remove :98-157; `extension_definitions` reads `Unit.get_data(unit, "extensions", i)` for template-less level units (:161-173). |
| `scripts/network/unit_extension_templates.lua` - `unit_templates` | Data: per-template extension CLASS lists in four variants (`self_owned_extensions`, `self_owned_extensions_server`, `husk_extensions`, `husk_extensions_server`) (:2746-2751), single-level `base_template` inheritance flattened at require time (:2754-2813, assert at :2766), DLC template merge (:2742-2744), selector `get_extensions(name, is_husk, is_server)` (:2815-2832), death-time removal lists (:2834-2855). |
| `scripts/game_state/state_ingame.lua` - extractor + frame driver | Installs the `extension_extractor_function` (:2259-2277): template name -> template list, else `ScriptUnit.extension_definitions` from unit data. Drives the frame: commit windows and system update calls (§2.4). Registers all level units at level load via `add_and_register_units(world, World.units(world))` (:765) and flow-spawned units via `register_unit` (:729). |
| `scripts/network/unit_spawner.lua` - `UnitSpawner` (= `Managers.state.unit_spawner`) | Unit creation/destruction choreography: `spawn_local_unit_with_extensions` (:326-334), `spawn_network_unit` (:336-352), husk path `spawn_unit_from_game_object` (:470-490), deferred deletion queue (`mark_for_deletion` :185-202, processed :246-291), pending system registration while `locked` (:309-324), per-unit destroy listeners (:509-527). |
| `scripts/entity_system/entity_system.lua` - `EntitySystem` | Requires every system+extension file (:3-176), instantiates ~90 systems in a FIXED order (`_init_systems` :210-436), forwards `pre_update`/`update`/`post_update`/`unsafe_entity_update`/`physics_async_update` into the bag (:474-510; paused-world early-out :505-507), unlock/commit/relock the spawner (`commit_and_remove_pending_units` :512-520). |
| `scripts/entity_system/entity_system_bag.lua` - `EntitySystemBag` | Ordered array of systems per update phase; a system lands in a phase list only if it defines that method and isn't blocked (:33-55). `update` iterates the phase list in registration order (:65-75). |
| `scripts/entity_system/systems/extension_system_base.lua` - `ExtensionSystemBase` | Default system implementation: creates extensions via `ScriptUnit.add_extension` with alias = the SYSTEM name (:47-50), maintains per-extension-class `pre_update`/`update`/`post_update` unit maps (:54-64), iterates them each phase (:87-135), removal (:69-79), `hot_join_sync` via `entity_manager:get_entities` (:161-175). Many gameplay systems subclass or replace pieces of this. |
| `scripts/unit_extensions/**` - extension classes | One class per behavior (e.g. `GenericHealthExtension`, `GenericHitReactionExtension`). Global class names; `ScriptUnit.add_extension` resolves them via `rawget(_G, extension_name)` (`script_unit.lua:99`). |
| `scripts/managers/conflict_director/breed_freezer.lua` | Pools AI units: freezes/unfreezes extensions instead of destroy/respawn; requires participating systems to implement `freeze`/`unfreeze` (:177, :478-479). |

Key indirection to internalize: **extensions are stored and fetched by SYSTEM
name, not extension class name.** `ExtensionSystemBase.on_add_extension` passes
`extension_alias = self.NAME` (`extension_system_base.lua:48`), so
`ScriptUnit.extension(unit, "health_system")` returns whichever health-family
class (`GenericHealthExtension`, `PlayerUnitHealthExtension`, ...) that unit's
template selected. One extension per system per unit
(`script_unit.lua:107` fassert).

---

## 2. Lifecycle and data flow

### 2.1 Which extension list a unit gets

`extension_extractor_function` (`state_ingame.lua:2259-2277`):

1. No template name -> `ScriptUnit.extension_definitions(unit)` reads the
   `extensions` array baked into the unit's data (level-placed units).
2. Template name -> `unit_templates.get_extensions(template, is_husk, is_server)`
   (`unit_extension_templates.lua:2815-2832`). Husk = `NetworkUnit.is_husk_unit(unit)`
   (`state_ingame.lua:2266-2267`). Four-way matrix:

| | client | host/server |
|---|---|---|
| **unit you own** | `self_owned_extensions` | `self_owned_extensions_server` |
| **remote peer's unit (husk)** | `husk_extensions` | `husk_extensions_server` |

This matrix is why the same "one unit" runs DIFFERENT classes per machine
(e.g. `player_unit_base`: `SimpleInventoryExtension` self-owned at
`unit_extension_templates.lua:13` vs `SimpleHuskInventoryExtension` husk at
:71) - the root of BUG_CLASSES §5.

### 2.2 Two-phase add (the load-bearing invariant)

`EntityManager2.add_unit_extensions` (`entity_manager2.lua:72-176`):

- **Phase 1 - construct** (:116-146): for each extension name in template order,
  `system:on_add_extension(world, unit, name, init_data)` -> for base systems this
  runs `ExtensionClass:new(...)` (the class `init`) and writes the instance into
  `ScriptUnit` under the system alias AND into the system's update lists
  (`extension_system_base.lua:47-67`). After phase 1 the extension is already
  visible to `ScriptUnit.extension` and already scheduled for per-frame update.
- **Phase 2 - cross-wire** (:150-171): for each extension in the same order,
  `extension:extensions_ready(world, unit)` then
  `system:extensions_ready(world, unit, name)` if defined. This is where
  extensions fetch their siblings (e.g. `GenericHitReactionExtension.extensions_ready`
  caches `ScriptUnit.extension(unit, "health_system")`,
  `generic_hit_reaction_extension.lua:155-160`).
- Then `Unit.flow_event(unit, "unit_registered")` (:173).

Contract: during phase 1 (`init`) a unit's OTHER extensions may not exist yet;
sibling fetches belong in `extensions_ready`. Anything that runs between the
phases (or that aborts phase 2 - see §4.1) observes a half-initialized unit.

- **Phase 3 - registry commit**: `register_units_extensions` (:256-276) copies
  each extension into the per-extension-name registry that
  `get_entities(extension_name)` serves. When the spawner is `locked` (true for
  the whole system-update span, `entity_system.lua:512-520`), this step is
  DEFERRED into `pending_extension_adds` and flushed at the next commit window
  (`unit_spawner.lua:309-324`, :220-244). Phase 1+2 are NOT deferred - a unit
  spawned mid-update has live, updating extensions but is invisible to
  `get_entities` enumeration until the commit.

### 2.3 Spawn paths

| Path | Sequence | Citation |
|---|---|---|
| Local-only unit with extensions | `World.spawn_unit` -> `POSITION_LOOKUP[unit] = pos` -> `create_unit_extensions` (phase 1+2, maybe-deferred phase 3) | `unit_spawner.lua:293-334` |
| Networked, self-owned | same as above, THEN `GameSession.create_game_object` -> `sync_unit_extensions` fires `extension:game_object_initialized(unit, go_id)` per extension | `unit_spawner.lua:336-352`, `entity_manager2.lua:178-198` |
| Husk (remote-owned) | game object arrives -> spawn unit from GO -> extract `unit_template_name` + init data from GO fields -> `create_unit_extensions` with `is_husk = true` | `unit_spawner.lua:470-490` |
| Level units | at level load, ALL world units batched through `add_and_register_units` (template from `Unit.get_data(unit, "unit_template")`, else unit-data extension list; zero-extension units still get `unit_registered` flow event) | `state_ingame.lua:765`, `entity_manager2.lua:235-254`, :108-114 |
| Flow-spawned | flow callback -> `Managers.state.entity:register_unit(world, unit, ...)` | `state_ingame.lua:729`, `entity_manager2.lua:216-233` |

Ordering consequence: `extensions_ready` runs BEFORE the game object exists on
the owning machine. Network ids (`unit_game_object_id`) are nil during
`extensions_ready`; the seam for "go_id now exists" is
`game_object_initialized` (`entity_manager2.lua:185-195`).

### 2.4 Frame order (who updates when)

`StateIngame` frame (all in `state_ingame.lua`):

1. `pre_update`: `UPDATE_POSITION_LOOKUP()` -> network receive -> **commit window** (:811) -> spawn/game-mode/conflict pre_updates -> **commit window** (:824) -> `entity_system:pre_update` (:827, gated by `_safe_to_do_entity_update` :676-688 - false when out of game session or game mode ended).
2. `update`: state machines (:960-962) -> `entity_system:update` (:975) or, when unsafe, `entity_system:unsafe_entity_update` (:977).
3. physics step: `entity_system:physics_async_update` (:663, :690-696).
4. `post_update`: `entity_system:post_update` (:1786) -> **commit window** (:1803).

Inside each phase, systems run in `_init_systems` registration order
(`entity_system.lua:210-436`; bag arrays `entity_system_bag.lua:33-55,65-75`).
Practical anchors from that order: input (:225) -> position_lookup (:230) ->
inventory (:240) -> weapon (:261) -> buff (:287) -> health (:294) -> status
(:295) -> hit_reaction (:299) -> ai_slot (:312) -> death (:315) -> locomotion
post_update (:359) -> animation (:360) -> first_person (:368) -> camera
post_update (:379) -> game_object_system (:408) -> dialogue post_update (:413).
WITHIN a system, unit iteration is `pairs`-ordered, i.e. non-deterministic
(`extension_system_base.lua:114-120`). Never depend on unit order inside one
system; you MAY depend on system-vs-system order.

Commit windows are the only points where (a) pending registry adds flush and
(b) `mark_for_deletion` units actually die - the repeat loop drains both to a
fixed point (`unit_spawner.lua:211-218`). System update code therefore never
sees a unit disappear mid-iteration; but a unit KILLED this frame still updates
until the next commit window.

### 2.5 Destruction

`UnitSpawner.mark_for_deletion(unit)` (:185-202) queues; the commit window pops
ONE unit per `remove_units_marked_for_deletion` pass (:246-291, looped to
exhaustion by :211-218). Per unit, in order (:262-283):

1. destroy listeners (`add_destroy_listener` callbacks, :265)
2. `Unit.flow_event(unit, "cleanup_before_destroy")` (:266)
3. event manager unregister (:276)
4. `entity_manager:unregister_units` (:277): `POSITION_LOOKUP[unit] = nil`
   (`entity_manager2.lua:334`), then `extension:destroy()` in REVERSE template
   order (:350-361), then `system:on_remove_extension` per entry which clears
   ScriptUnit + update lists (:363-388, `extension_system_base.lua:69-79`),
   then `ScriptUnit.remove_unit` (:391)
5. post-cleanup listeners (:280), then `World.destroy_unit` (:283)

Death is not destruction: on kill, templates may strip a SUBSET of extensions
via `remove_when_killed` lists (`unit_spawner.lua:101-102`,
`unit_extension_templates.lua:2834-2855`, `entity_manager2.remove_extensions_from_unit`
:278-306) - a corpse keeps e.g. hit-reaction/death extensions while losing AI
ones. Frozen breeds (breed_freezer) additionally bypass destroy entirely:
`freeze_extensions` (:308-319) calls `system:on_freeze_extension`, the unit is
pooled, and later unfrozen with `system:unfreeze` (`breed_freezer.lua:450-479`).
Unit-keyed mod caches must expect all three exits: unregister, partial
death-strip, freeze/unfreeze reuse.

---

## 3. Hookable seams

| Seam | When it fires | Safe pattern | Traps |
|---|---|---|---|
| `<ExtensionClass>.init` (phase 1) | during `add_unit_extensions` construct loop | `mod:hook_safe("ClassName", "init", ...)`; touch ONLY `self` and init args | Sibling extensions may not exist; `ScriptUnit.extension(unit, other)` may be nil; game object doesn't exist. A raise here aborts phase 2 for the whole unit (§4.1). |
| `<ExtensionClass>.extensions_ready` (phase 2) | after ALL of the unit's extensions constructed | `mod:hook_safe("ClassName", "extensions_ready", function(self, world, unit) ...)` - the canonical per-unit-spawn seam. Ours: `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua:256`, `general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua:312`, `character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:6322-6324` | (a) `Managers.player:owner(unit)` / `local_player().player_unit` are NOT yet wired at this instant - defer one frame (our canonical queue: `_la_persistence.lua:261-273`; gt's reapply timer: `general_tweaker.lua:290-312`). (b) Not every class defines it - hooking a missing method is BUG_CLASSES §1b (cosmetics issue #35: `SimpleHuskInventoryExtension` has no `extensions_ready`). (c) Husk twin class needs its own hook (§5 / BUG_CLASSES §5). |
| `extension:game_object_initialized(unit, go_id)` | owner machine, right after GO creation | hook the class method; only seam where go_id is guaranteed | Husks never get this (they extract FROM the GO instead); `sync_unit_extensions` only runs on the owner path (`unit_spawner.lua:349`). |
| System `update`/`pre_update`/`post_update` | per frame per phase | `mod:hook("SomeSystem", "update", ...)` for system-wide behavior; cheaper than per-extension hooks | Skipped entirely when world paused (`entity_system.lua:505-507`) or unsafe (`state_ingame.lua:974-978`); `unsafe_entity_update` runs instead after session loss - a system without that method silently stops. |
| `UnitSpawner.add_destroy_listener(unit, id, cb, post_cleanup)` | per-unit, at real deletion, BEFORE extension teardown (post_cleanup variant: after) | `Managers.state.unit_spawner:add_destroy_listener(unit, "my_mod_id", cb)` (`unit_spawner.lua:509-521`) | Engine-provided per-unit cleanup - the idiomatic way to drop unit-keyed mod caches. No active mod uses it today (grep 2026-07-11: zero hits). |
| `Unit.flow_event` markers | `unit_registered` (`entity_manager2.lua:173`), `cleanup_before_destroy` (`unit_spawner.lua:266`), `unit_despawned` (:464), `lua_unfreeze_unit` (`breed_freezer.lua:464`) | flow-side only | Not hookable from Lua directly; listed for log/flow forensics. |
| `EntityManager2.get_entities(extension_name)` | pull, not push | enumerate all units carrying an extension CLASS (note: keyed by extension class name, not system alias) | Returns a READ-ONLY shared empty table when none (`entity_manager2.lua:3-13,56-58`) - writing to it errors. Excludes units added mid-update until the next commit window (§2.2 phase 3). |
| `ScriptUnit.extension` / `has_extension` fetch | anywhere | `local ext = ScriptUnit.has_extension(unit, "x_system"); if ext then ...` | In this build BOTH return nil silently (`script_unit.lua:43-47,61-66,72`) - `extension` does not assert. The crash always happens at YOUR call site (`nil:method()`). Treat every fetch as fallible unless you are inside a vanilla code path that already proved it. `ScriptUnit.extension_input` DOES hard-deref (:55-59). |

Hook-mechanics traps that apply to every seam above (owner docs cited):

- Derived classes COPY methods at class-definition time - hook the runtime class
  (`MenuWorldPreviewer`, not `HeroPreviewer`), `CLAUDE.md` § "HOOK THE DERIVED
  CLASS", `foundation/scripts/util/class.lua:51-57` [per CLAUDE.md citation].
- One hook per (Class, method) per mod - VMF drops the second silently
  (BUG_CLASSES §1). Grep first; consolidate (the `_la_persistence.lua:265-272`
  fan-out comment is the canonical in-repo example).
- Self-owned vs husk class pairs (BUG_CLASSES §5): audit
  `unit_extension_templates.lua` for BOTH lists before claiming MP coverage.
- Upvalue capture bypasses table-entry hooks (`CLAUDE.md` § "Hooks that
  silently no-op").

---

## 4. Traps and crash classes

### 4.1 Half-initialized extension exposure (the issue 470 class)

**Mechanism.** Phase 1 already registered extension N into ScriptUnit AND into
its system's per-frame update list (`extension_system_base.lua:54-64`). If
extension N+1's `init` raises, `add_unit_extensions` unwinds and **phase 2
(`extensions_ready`) never runs for ANY extension of that unit**
(`entity_manager2.lua:116-171` - the two loops are sequential, no pcall).
Extension N keeps updating every frame with its `extensions_ready`-populated
fields still nil.

**Concrete instance (issue 470, ct).** `ai_unit_base` orders
`GenericHitReactionExtension` immediately before `GenericHealthExtension`
(`unit_extension_templates.lua:403-419`). A vanilla data hole
(`mutator_curse_skulking_sorcerer.lua` duplicate rank constants) leaves
`Breeds.curse_mutator_sorcerer.max_health[8] = nil`; ct's progressive
difficulty reaches cataclysm_3, `conflict_director.lua:1948` resolves nil
health, and `GenericHealthExtension.init` throws
(`generic_health_extension.lua:49,66` - `set_max_health` on nil). The
already-updating hit-reaction extension then nil-derefs
`self.health_extension` (`generic_hit_reaction_extension.lua:217-218`; the
field is only set in `extensions_ready` :155-160) = host CTD. Full chain +
fix (data backfill, NOT a guard) in
`chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua:3227-3270`.

**Doctrine.**
1. Never let mod code raise inside a phase-1 seam (`init` hooks, or data an
   `init` reads, e.g. breed fields, `extension_init_data`) - the blast radius
   is every OTHER extension on the unit, and the symptom surfaces frames later
   in unrelated vanilla code.
2. When a mod feature widens vanilla's input domain (extra difficulty ranks,
   extra breeds, extra items), sweep every rank-/key-indexed table that domain
   reaches and backfill holes at the DATA level, as the 470 fix does.
3. Diagnostic signature: `attempt to index ... (a nil value)` inside a vanilla
   extension `update` on a field that grep shows is assigned only in
   `extensions_ready` -> suspect a phase-1 abort on that unit's spawn, and look
   EARLIER in the log for the init-time error.

No BUG_CLASSES entry exists for this class yet (checked 2026-07-11; catalog
ends at §31) - see §5 candidate list.

### 4.2 Foreign `ScriptUnit.set_extension` keys crash unit teardown

`ScriptUnit.set_extension(unit, "my_mod_system", ext)` (`script_unit.lua:94-96`)
happily stores anything. But for template-spawned units,
`unregister_units` iterates `pairs(unit_extensions)` over ALL ScriptUnit keys
and does `self._systems[system_name]:on_remove_extension(...)`
(`entity_manager2.lua:363-374`) - a key with no registered system indexes nil
-> crash at despawn, far from the write. If you must attach extension-shaped
state to an engine-managed unit, either (a) keep it in your own
unit-keyed table + `add_destroy_listener` for cleanup, or (b) remove your
ScriptUnit entry before the unit can die. No active mod currently calls
`set_extension` (grep 2026-07-11: zero hits) - keep it that way for (a).

### 4.3 Known adjacent classes (existing catalog entries)

| Trap | Where documented |
|---|---|
| Self-owned vs husk extension class confusion (feature works SP, dead in MP) | BUG_CLASSES §5; matrix in §2.1 above |
| Hooking a method the class doesn't have (silent dead hook, e.g. husk class lacks `extensions_ready`) | BUG_CLASSES §1b |
| Husk resolves BASE item_data, owner-path logic unreachable for remote players | BUG_CLASSES §27; memory `reference_vt2_husk_resolves_base_item_data` |
| Husk attachment before skeleton ready (hot-join) - guard `Unit.has_node` | memory `reference_vt2_husk_attachment_skeleton_readiness` |
| `POSITION_LOOKUP` nil'd at unregister (`entity_manager2.lua:334`) + stale for local player in chat phase | BUG_CLASSES §21; memory `reference_vt2_ai_takeover_despawn_poslookup_crash` |
| `PlayerManager.remove_player` fires on level transitions (peer caches wiped) | BUG_CLASSES §24 |
| `hud_ui` class hook fails at keep (extension classes load per-level) | memory `reference_vmf_hud_ui_class_hook_fails_at_keep` |

### 4.4 Smaller sharp edges

- `add_unit_extensions` asserts if a unit already has extensions
  (`entity_manager2.lua:104`) - you cannot re-run the template pipeline on a
  live unit; extension addition post-spawn goes through
  `remove_extensions_from_unit`-style system calls, not a second add.
- The extractor's template lists are SHARED tables cached per template
  (`entity_manager2.lua:80-100` keys a reverse-lookup by the list table
  identity). Never mutate the list returned by
  `unit_templates.get_extensions` - you would retroactively change every
  future spawn of that template and desync the cached reverse lookup.
- `EntitySystem.destroy` unregisters every remaining world unit
  (`entity_system.lua:526-530`); state transitions therefore run your destroy
  listeners and `extension:destroy()` - do not assume "level end" skips
  teardown paths.
- Zero-extension template units still emit `unit_registered` and occupy
  `_unit_extensions_list` (`entity_manager2.lua:106-114`).

---

## 5. Implications for our mods

Survey basis (2026-07-11): 49 `ScriptUnit.extension(` sites in 21 files vs 260
`ScriptUnit.has_extension(` sites in 60 files across `**/scripts/mods/**`.
Most `extension()` sites are guarded or vanilla-parity ports; the items below
are where we fight the engine or leave a lifecycle edge open.

1. **[FIXED wt v0.12.208-dev] wt BR cone counter derefs health ext unguarded.**
   `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance.lua:2444`
   did `ScriptUnit.extension(hit_unit, "health_system"):is_alive()` on
   broadphase-listed AI units; a unit whose extensions were just unregistered
   (or a foreign side unit without health) returned nil -> crash inside a
   BR toggle. Fixed with the engine-idiomatic `has_extension` fetch + nil-test
   (sibling pattern `enemy_tweaker_big_rebalance.lua:473-474`); missing-ext
   enemies are skipped for the num_hit cap with a `[wt:br_hooks]` printf.
   Note the BR module is ON ICE (`weapon_tweaker.lua:88-89`, issue 433), so
   the guard is dormant until a BR revival.
   The active `weapon_tweaker_dev` mirror now receives this guard through the
   blocking WT stream-parity gate (`qa/check_wt_stream_parity.ps1`).

2. **[P2] et BR stagger-heal proc derefs inventory ext unguarded.**
   `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_big_rebalance.lua:478-479`
   (`ScriptUnit.extension(owner_unit, "inventory_system"):equipment()`), inside
   a buff proc. Buff procs can fire on the frame a player unit despawns
   (proc queue vs commit-window timing, §2.4-2.5). Guard like the
   `death_system` fetch four lines up.

3. **[P2] gt creature spawner permanently flips player invincibility with an
   unguarded fetch.**
   `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua:835-836`
   sets `health_ext.is_invincible = true` on every `PLAYER_AND_BOT_UNITS` via a
   bare `ScriptUnit.extension` (vanilla-port `run_on_spawn` of the Drachenfels
   sorcerer). Outside dlc_castle there is no arena flow to restore it and a
   mid-spawn hot-join unit can nil here. Guard the fetch and mirror an
   `is_invincible = false` restore in the `run_on_death` hook (:849).

4. **[P1] Add the §4.1 crash class to BUG_CLASSES.md.**
   `docs/BUG_CLASSES.md` has no entry for "phase-1 init raise -> extensions_ready
   skipped -> half-initialized extension updates" even though issue 470 is
   fixed in
   `chaos_wastes_tweaker_dev/.../chaos_wastes_tweaker_dev.lua:3227-3270`. The
   diagnostic signature (§4.1.3) is greppable and will repeat for any
   data-domain-widening mod (et breeds, ct difficulty, WOC items). Also ensure
   the 470 backfill rides the next ct dev->stable promotion
   (`tools/promote/promotion-status.ps1` per `CLAUDE.md` § Promotion tracking).

5. **[P2] Adopt `UnitSpawner.add_destroy_listener` for unit-keyed caches.**
   Zero uses in the repo today; instead we poll `Unit.alive` or pcall-wrap
   `mark_for_deletion` cleanups (e.g. cwv bayonet/proxy teardown,
   `character_weapon_variants/.../character_weapon_variants.lua:4735,5428,6301`).
   The engine hands us a per-unit destruction callback that fires BEFORE
   extension teardown (`unit_spawner.lua:509-521`, invoked :265). Any mod table
   keyed by unit (wt per-unit anim state, cwv ammo-ext registry
   `character_weapon_variants.lua:4835`) should register one listener at
   insert time instead of leak-or-poll. Caveat: identifier is per-unit-unique;
   prefix with mod id.

6. **[P2] mod-lint rule for single-expression extension derefs.**
   The repeated shape `ScriptUnit.extension(u, "x_system"):method()` (items 1-3;
   historic burns in §4.3) is mechanically detectable. Add a
   `tools/mod-lint` warning for `ScriptUnit\.extension\([^)]*\)\s*[:.]` with no
   intervening nil check, mirroring the existing forward-ref check. Warning,
   not error: vanilla-parity ports inside method replacements legitimately
   inherit vanilla's own unguarded fetches (e.g.
   `career_tweaker/scripts/mods/career_tweaker/career_tweaker_big_rebalance.lua:2343`,
   line-for-line from `sienna_changes.lua:780` per its header comment).

7. **[P2] Keep (and reuse) the two canonical timing patterns instead of
   inventing new ones.**
   (a) extensions_ready + next-frame queue when player wiring is needed:
   `cosmetics_tweaker/.../_la_persistence.lua:256-273`;
   (b) extensions_ready + bounded reapply timer for local-player systems:
   `general_tweaker/.../general_tweaker.lua:290-312`. Both exist BECAUSE
   `Managers.player:owner(unit)` is not established at `extensions_ready`
   time (§3 row 2). New per-spawn features should call into these queues, not
   add fresh `mod.update` pollers (BUG_CLASSES §8 rewrap risk).

What we already do RIGHT (keep doing): career recovery via
`inventory_system._career_name` set in phase 1 before our hooks run
(`weapon_tweaker/.../weapon_tweaker.lua:3715-3720`, memory
`feedback_vt2_mission_spawn_career_lookup`); pcall-guarded husk career fetch
(`character_weapon_variants/.../character_weapon_variants.lua:10136-10145`);
guarded health reads (`general_tweaker_dev/.../_gt_melee_warning.lua:195-206`).
