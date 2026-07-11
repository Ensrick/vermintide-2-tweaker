# Engine reference 01 - Foundation layer and OOP idioms

> Scope: `foundation/scripts/` (class system, utility libs, managers, event/callback
> idioms), the `scripts/settings/` data-table pattern, boot/require order, and how our
> mods do or should mirror these idioms. Vanilla paths are relative to
> `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to the
> monorepo root. Every claim cites file:line or is marked [unverified].
> Companion docs: `docs/VMF_RECIPES.md` (VMF hook mechanics), `docs/BUG_CLASSES.md`
> (crash catalog), `docs/OOP_REFACTOR_PLAN.md` (active refactor workstreams).

## 1. Architecture map

### 1.1 Foundation utility files (loaded by `Boot._require_foundation_scripts`, boot.lua:515-520)

| File | Single responsibility | Key exports |
|---|---|---|
| `foundation/scripts/util/class.lua` | The OOP system: `class()`, `is_class_instance()` | globals `class`, `is_class_instance` (class.lua:16, :62) |
| `foundation/scripts/util/callback.lua` | Closure factory binding an object+method (or fn) with up to 5 pre-bound args | global `callback(...)` (callback.lua:5); arg cap `MAX_ARGS = 5` (callback.lua:3) |
| `foundation/scripts/util/error.lua` | Formatted assert/error: `fassert`, `ferror`, `Application.warning/error` | error.lua:25, :33, :13, :17 |
| `foundation/scripts/util/misc_util.lua` | `printf`/`sprintf`/`cprint`, `NOP`, `IDENTITY`, `TABLE_NEW`, `CONST` | misc_util.lua:29, :33, :3-25. `printf` here is why our diagnostics doctrine says "printf, not mod:info" - it is a raw engine `print` |
| `foundation/scripts/util/table.lua` | Monkey-patches the global `table` lib in place: ~60 helpers | see 1.2 |
| `foundation/scripts/util/math.lua` | Monkey-patches global `math`: clamp/lerp/round/easing/geometry (~80 fns) | math.lua:15-991 |
| `foundation/scripts/util/string.lua` / `array.lua` / `stack.lua` / `circular_queue.lua` / `grow_queue.lua` | String helpers and container classes | [unverified line detail - read on demand] |
| `foundation/scripts/util/frame_table.lua` | `FrameTable` - double-buffered pool of per-frame scratch tables, swap-cleared each frame; zero-GC temp allocation | frame_table.lua:20 `alloc_table`, :39 `swap_and_clear` |
| `foundation/scripts/util/script_unit.lua` | `ScriptUnit` - the unit -> extension registry (`G_Entities` global map); `add_extension` resolves the extension CLASS by global name | script_unit.lua:3-11, :98-111 |
| `foundation/scripts/util/state_machine.lua` | `StateMachine` - generic state machine (`on_enter`/`update`/`on_exit`); state's `update` return value drives transition | state_machine.lua:26, :74-80 |
| `foundation/scripts/util/local_require.lua` | `local_require` - hot-reload-aware require (clears `package.loaded` once per reload cycle) | local_require.lua:5-17 |
| `foundation/scripts/util/user_setting.lua` | `Development.setting`/`set_setting` (user_settings.config `development_settings` block); disabled in release builds | user_setting.lua:58-80, :73-77 |
| `foundation/scripts/util/application_parameter.lua` | `script_data` bootstrap + command-line parameter parsing | application_parameter.lua:5 |

### 1.2 The `table` library extension (foundation/scripts/util/table.lua) - use these, do not reinvent

| Function | Line | Semantics / trap |
|---|---|---|
| `table.clone(t, skip_metatable)` | :31-49 | Deep copy. ASSERTS if any table has a metatable and `skip_metatable` is falsy ("Metatables will be sliced off", :37). Class instances are copied by reference, not descended (:41). NO cycle guard - infinite recursion on self-referencing tables |
| `table.shallow_copy(t, skip_metatable, out_t)` | :51-65 | One level; same metatable assert (:57) |
| `table.merge(dest, source)` / `merge_recursive` | :175, :183 | In-place overlay; recursive variant deep-clones sub-tables via `table.clone` (:190) |
| `table.contains(t, value)` / `find` / `index_of` | :265, :275, :295 | Linear scans |
| `table.pack(...)` | :210-214 | Returns `{...}, select("#", ...)` - the count is a SECOND RETURN, not an `.n` field (differs from Lua 5.2). Pair with `unpack(t, 1, n)` for nil-hole safety (BUG_CLASSES.md class 3, docs/BUG_CLASSES.md:150) |
| `table.clear(t)` | :353-359 | LuaJIT `table.clear` when available, else pairs-loop |
| `table.swap_delete(t, index)` | :831 | O(1) unordered array removal (used by e.g. `scripts/entity_system/systems/weapon/ammo_system.lua:54`) |
| `table.is_empty` / `size` / `keys` / `values` / `mirror_table` / `set` | :5, :9, :698, :743, :664, :654 | Misc; `table.size` is O(n) - do not call per frame on big tables |
| `table.dump(t, ...)` | :406 | Debug pretty-print to log |

`Script.new_array(n)` / `Script.new_map(n)` / `Script.new_table` (table.lua:19-29) pre-size
tables via LuaJIT `table.new` - the engine idiom for hot-path allocation (e.g.
`Boot.flow_return_table = Script.new_map(32)`, scripts/boot.lua:69).

### 1.3 Foundation managers

| File | Responsibility |
|---|---|
| `foundation/scripts/managers/managers.lua` | The `Managers` global: three groups - `global` (lives forever), `venture` (Chaos Wastes expedition scope), `state` (one game state). `__newindex` metatables record creation order (managers.lua:106-195); destruction runs in REVERSE creation order per group (managers.lua:26-44) |
| `foundation/scripts/managers/event/event_manager.lua` | `EventManager` - name -> {object -> method_name} registry; `trigger` calls `object[method_name](object, ...)` (event_manager.lua:37-49); optional passthrough chaining to a parent manager (:46-48, :106-108) |
| `foundation/scripts/managers/package/package_manager.lua`, `time/`, `world/`, `player/`, `localization/`, `token/`, `state/` | Global-group managers created in `Boot._init_managers` (scripts/boot.lua:522-528) and `Boot.setup` [unverified exact list] |

### 1.4 The class system in full (foundation/scripts/util/class.lua - 75 lines, read it once)

```lua
Foo = class(Foo)                    -- root class
Bar = class(Bar, Foo)               -- derived
Bar.init = function(self, ...) Bar.super.init(self, ...) end
local b = Bar:new(1, 2)             -- new() -> setmetatable + optional :init(...) (class.lua:30-40)
b:delete()                          -- delete() -> optional :destroy(...) then poisons the instance (class.lua:42-48)
```

Mechanics, each load-bearing:

1. **`Foo = class(Foo)` is idempotent** - if the first arg is non-nil the existing table
   is reused and only re-populated (class.lua:23-49 only builds `new`/`delete`/`__index`
   when `class_table` is nil). This keeps table identity stable across hot reloads AND
   lets two copies of the same mod code share one class (our
   `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_material_hijack_embedded_anim.lua:28`
   exploits exactly this to coexist with a standalone Material Hijack install).
2. **Instances resolve methods through `__index = class_table`** (class.lua:28), so
   replacing `Foo.method` after instances exist affects all of them - this is what makes
   VMF hooking work at all.
3. **Inheritance is a COPY, not a chain.** `class(Child, Super)` iterates `pairs(super)`
   and copies every non-special key into the child AT DEFINITION TIME (class.lua:51-57;
   `special_functions` = `__index`/`delete`/`new`/`super`, class.lua:9-14). There is no
   `__index` link to the parent. Consequence: patching a base-class method after boot
   NEVER reaches subclasses (see section 3.1).
4. **`self.super` / `Child.super`** stores the parent class table (class.lua:26);
   vanilla calls `Child.super.init(self, ...)` (e.g.
   `scripts/entity_system/systems/weapon/ammo_system.lua:14`) or `self.super.init(self, ...)`
   (`scripts/game_state/game_state_machine.lua:10`).
5. **`delete()` poisons the instance**: after `:delete()`, any field access errors
   "This object has been destroyed" via `destroyed_mt.__index` (class.lua:3-7).
   Holding a deleted instance in any registry = deferred crash on next touch.
6. **`is_class_instance(t)`** checks `___is_class_metatable___` on the metatable
   (class.lua:62-74); `table.clone` uses it to copy instances by reference (table.lua:41).
7. There is no NAME magic in `class()` itself, but vanilla subsystems resolve classes
   FROM GLOBALS BY STRING: `ScriptUnit.add_extension` does `rawget(_G, extension_name)`
   (foundation/scripts/util/script_unit.lua:99); hero-view windows do
   `rawget(_G, window_class_name)` (scripts/ui/views/hero_view/states/hero_view_state_overview.lua:308).
   A class that must be engine-instantiated by name MUST be a global.

### 1.5 Settings/data tables under `scripts/settings/`

The uniform idiom (~100 files): a bare global table assigned idempotently at require time,
consumed by direct global reads at call time.

- Shape: `DifficultySettings = DifficultySettings or {}` then literal blocks per key
  (scripts/settings/difficulty_settings.lua:3-42). Values are plain data plus loc keys
  (`display_name = "difficulty_normal"`, :13).
- Every consumer defensively `require`s the file itself (difficulty_settings is required
  by network_lookup.lua:16, difficulty_manager.lua:3, conflict_settings.lua:5, and 6+
  more) - requires are cached, so this is free and order-independent.
- DLC settings are indirected: `DLCSettings.<dlc>.additional_settings` maps names to
  require paths (scripts/settings/dlc_settings.lua:3-47), pulled in at boot via
  `DLCUtils.require_list("additional_settings")` (scripts/boot.lua:387).
- `script_data` (scripts/boot_init.lua:79-82) = `Application.settings()` + dev flags;
  files localize it (`local script_data = script_data`, scripts/entity_system/systems/damage/health_system.lua:18)
  and treat flags as ambient config. `Development.parameter`/`setting` read
  `user_settings.config` dev blocks and are NOP'd in release builds (foundation/scripts/util/user_setting.lua:73-77).

**Why this matters to us:** settings tables are plain globals with NO strict metatable, so
mods may overlay values in place at load and vanilla picks them up on next read. The ONE
family that is NOT safe is `NetworkLookup.*` - each lookup gets a strict `__index`
metatable that ERRORS on missing keys (scripts/network_lookup/network_lookup.lua:2360-2367)
and a duplicate-entry `ferror` on re-init (:2346-2356). Always `rawget`/`rawset`
(BUG_CLASSES.md class 4, docs/BUG_CLASSES.md:256).

## 2. Lifecycle and data flow

### 2.1 Boot order (scripts/boot.lua) - who exists when

1. `scripts/boot_init.lua` (dofile'd at boot.lua:4): platform globals (`BUILD`,
   `PLATFORM`, `IS_WINDOWS`...), `script_data`, `GlobalResources` package list, release
   builds scrub `io`/`ffi`/`os.execute`/`loadlib` (boot_init.lua:223-250).
2. `require("scripts/settings/dlc_settings")` + dlc_utils (boot.lua:65-66).
3. `Boot.setup` loads startup resource packages incl. `foundation_scripts` and
   `game_scripts` (boot.lua:136-145).
4. Foundation scripts: `class` before `table` (table.lua:3 requires class.lua), then
   managers (boot.lua:516-519). Base managers instantiated (`Managers.time/world/token/state_machine`, boot.lua:522-528);
   `Managers.persistent_event = EventManager:new()` (boot.lua:1541).
5. DLC packages load, then `DLCUtils.require_list("additional_settings")` and
   `DLCUtils.merge("script_data", script_data)` (boot.lua:386-388).
6. `Game:require_game_scripts()` (boot.lua:389, defined :1290-1322): utils, settings,
   `entity_system`, all game states, ~40 managers, helpers, network,
   `network_lookup` (:1320) - i.e. EVERY vanilla class table gets defined here.
7. `init_mods` state: `ModManager:new` is created LAST (boot.lua:399-405) and boot waits
   for `all_mods_loaded` (:406-414).

**Consequence (the single most important lifecycle fact for us):** mods load after every
vanilla `class()` call has already run. All base->derived method copying (class.lua:51-57)
is finished; every settings table is populated; every `NetworkLookup` is frozen behind its
strict metatable. Mod-time patches therefore always operate on the FINAL tables - which is
why hooking a base class is dead code (3.1) and why settings overlays are safe.

### 2.2 Manager groups: create/destroy discipline

- Creation order is recorded by `__newindex` (foundation/scripts/managers/managers.lua:106-195);
  `destroy_manager_group` walks it in reverse and calls each manager's `destroy()`
  (managers.lua:26-44). Group teardown order is state -> venture -> global (managers.lua:76-80).
- `Managers.state.*` is REBUILT on every game-state transition:
  `Managers.state.event = EventManager:new(Managers.persistent_event)` fresh in
  StateLoading (scripts/game_state/state_loading.lua:168) and StateIngame
  (scripts/game_state/state_ingame.lua:2207-2209). Any registration against
  `Managers.state.event` dies at the next transition. `Managers.persistent_event`
  (boot.lua:1541) survives; state-event triggers pass through to it
  (event_manager.lua:46-48).
- Venture group = Chaos Wastes expedition lifetime; `Managers.on_venture_start/end`
  broadcast to all managers implementing those methods (managers.lua:98-104).

### 2.3 Game states

`GameStateMachine = class(GameStateMachine, StateMachine)` (scripts/game_state/game_state_machine.lua:5)
drives StateSplashScreen/StateLoading/StateIngame/StateDemoEnd (required boot.lua:1296).
The foundation `StateMachine` instantiates the next state class (`new_state:new()`),
sets `.parent`, calls `on_enter(params)` (state_machine.lua:40-68); a state's `update`
returning a class table triggers the transition (state_machine.lua:74-80). Related trap:
`PlayerManager.remove_player` fires on LEVEL TRANSITIONS, not just disconnects
(BUG_CLASSES.md class 24, docs/BUG_CLASSES.md:1090) - peer-keyed caches keyed off it are
wiped every map change.

### 2.4 Unit extensions

Systems declare extension NAMES; `ExtensionSystemBase.on_add_extension` calls
`ScriptUnit.add_extension` (scripts/entity_system/systems/extension_system_base.lua:47-50),
which resolves `rawget(_G, extension_name)` and `fassert`s if missing
(foundation/scripts/util/script_unit.lua:99-101), then `extension_class:new(...)` and
registers into `G_Entities[unit]` (:105-108). Read back via `ScriptUnit.extension`
(raises nothing itself but callers deref) vs `ScriptUnit.has_extension` (nil-safe,
script_unit.lua:43-47, :72). Our standing rule: use `has_extension` on hot-join/husk
paths (memory `reference_vt2_husk_attachment_skeleton_readiness`).

### 2.5 Callback and event idioms

- `callback(obj, "method", a1, a2)` returns a closure calling `obj:method(a1, a2, ...)`
  (callback.lua:5-50); function-first form binds a plain function (:51-91). Hard cap of
  5 bound args (`fassert`, callback.lua:14). This is the vanilla currency for async APIs
  (package load callbacks, popup callbacks).
- `EventManager.register(object, event_name, method_name)` stores the METHOD NAME STRING,
  not a function - a function value as 3rd arg dies with "No function found with name"
  (`fassert` event_manager.lua:16; BUG_CLASSES.md class 3b, docs/BUG_CLASSES.md:200).
  `trigger` iterates `object -> name` pairs (event_manager.lua:37-44).
- The registry sets `__mode = "v"` (event_manager.lua:18-20) but values are method-name
  STRINGS, which are not collectable - objects are the KEYS and keys are NOT weak, so
  registration does NOT auto-expire. A registered object that gets `:delete()`d still
  gets triggered and immediately errors via `destroyed_mt` (class.lua:5-7). Explicit
  `unregister` in `destroy()` is mandatory for short-lived objects.

## 3. Hookable seams (and the safe pattern for each)

VMF's `mod:hook`/`hook_safe` replace a method on a global class table; instances see the
replacement through `class_table.__index = class_table` (class.lua:28). VMF source is not
locally readable (Workshop bundle only); VMF-side mechanics below cite `docs/VMF_RECIPES.md`.

| Seam | Safe pattern | Trap |
|---|---|---|
| Vanilla class methods (global class tables) | String-form `mod:hook("ClassName", "method", fn)` - lazy, safe pre-load | ONE hook per `(Class, method)` per mod - second silently dropped (docs/VMF_RECIPES.md section 1; NON-NEGOTIABLE 8, CLAUDE.md) |
| Base class with derived classes | Hook the DERIVED class(es) too - vanilla pairs we already pair-hook: `HeroPreviewer` + `MenuWorldPreviewer` (cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua:5310+5346, :5455-5456, :9417-9418) | class.lua:51-57 copies parent methods at definition time; `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` (scripts/ui/views/menu_world_previewer.lua:7) ran at boot, so a base-only hook NEVER fires on the keep inventory previewer (BUG_CLASSES.md class 1b, docs/BUG_CLASSES.md:71; burned wt v0.12.16) |
| Plain-table dispatchers (`BackendUtils`, `GearUtils`, `DamageUtils`) | Table-form hook with nil guard; for LA-cloned backends hook the post-LA table reference (docs/CROSS_MOD_ARCHITECTURE.md "LA bridge") | String-form misses runtime-reassigned functions; `BackendUtils.can_wield_item` is not hookable at all - mutate `ItemMasterList[key].can_wield` instead (CLAUDE.md "Hooking") |
| `Managers.state.event` events (`on_player_joined_party` etc.) | Register a named method on a long-lived object (`mod`), re-register when the manager pointer changes - gt's dispatcher is the house pattern (general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua:1929-1976) | Manager is rebuilt every state transition (state_ingame.lua:2209); one boot-time register silently dies after first map load. 3rd arg must be a method-name string (class 3b). One `(object, event)` pair per manager - last-writer-wins (gt's three lobby modules collided exactly here, general_tweaker.lua:1920-1927) |
| `Managers.persistent_event` | Same API, survives transitions (boot.lua:1541) - use for whole-session subscriptions | Passthrough means state-event triggers ALSO reach persistent registrations (event_manager.lua:46-48) - do not double-register the same event on both |
| Settings tables (`DifficultySettings`, `Breeds`, `HordeCompositions`...) | Overlay values in place at mod load; vanilla reads at call time | Some tables are captured as upvalues/locals at require time by consumers (e.g. enemy pacing `threat_values` upvalue - enemy_tweaker/DEVELOPMENT.md); mutate BEFORE first consumer read or patch the consumer |
| `NetworkLookup.*` | `rawget`/`rawset` only; append with paired forward+reverse entries | Strict `__index` errors on any miss (network_lookup.lua:2360-2367); modded keys on vanilla RPCs CTD non-modded peers (BUG_CLASSES.md class 31, docs/BUG_CLASSES.md:1307) - sender-side substitution, never toggle-gated |
| New unit extensions | Define a GLOBAL class + register into the system's extension list (vanilla resolves `rawget(_G, name)`, script_unit.lua:99) | Global name = cross-mod collision surface; use the idempotent `Foo = class(Foo)` form so double-load re-assigns methods instead of erroring (our _material_hijack_embedded_anim.lua:28 precedent) |
| New UI windows/view states | Global class + `NAME` field, injected into window/state settings lists (vanilla lookup hero_view_state_overview.lua:308, :301 compares `current_window.NAME`) | Same global-name discipline; gut precedent `gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_state.lua:214-215` |
| RPC receivers | Hookable - `NetworkEventDelegate` dispatch is dynamic (memory `reference_vt2_rpc_dispatch_dynamic_hookable`) | Name EVERY networked param in the wrapper; dropping a trailing sync param re-broadcasts (BUG_CLASSES.md class 19, docs/BUG_CLASSES.md:906) |
| `_G` functions (`Localize`, `callback` itself...) | `mod:hook(_G, "Localize", ...)` (CLAUDE.md "Hooking") | Wrapper multi-return collapse (BUG_CLASSES.md class 2, docs/BUG_CLASSES.md:110) |

## 4. Traps and crash classes (foundation-layer specific)

| # | Trap | Mechanism | BUG_CLASSES / memory ref |
|---|---|---|---|
| 1 | Base-class hook never fires on subclass | class.lua:51-57 definition-time copy, no `__index` chain | class 1b (docs/BUG_CLASSES.md:71) |
| 2 | Use-after-delete | `delete()` swaps metatable to `destroyed_mt` which errors on ANY index (class.lua:3-7, :42-48) | not yet a numbered class; surfaces as "This object has been destroyed" |
| 3 | EventManager does not auto-unregister | `__mode="v"` weakness is on strings, keys (objects) are strong (event_manager.lua:18-20) | interacts with trap 2; unregister in `destroy()` |
| 4 | `event:register` with a function value | 3rd arg must be a method-name string (event_manager.lua:16) | class 3b (docs/BUG_CLASSES.md:200) |
| 5 | `Managers.state.*` lifetime | Rebuilt per game-state transition (state_loading.lua:168, state_ingame.lua:2207-2209); reverse-creation-order destroy (managers.lua:26-44) | gt re-register pattern (general_tweaker.lua:1958-1976) |
| 6 | `table.clone` metatable assert + no cycle guard | table.lua:37 asserts unless `skip_metatable`; recursion at :44 has no visited-set | keep cycle-safe local copies where graphs can self-reference (_gt_creature_spawner.lua:311) |
| 7 | `table.pack` count is a second return | table.lua:210-214, no `.n` field | class 3 nil-hole unpack (docs/BUG_CLASSES.md:150), VMF_RECIPES 2a |
| 8 | `callback` 5-arg cap | fassert at callback.lua:14 | binds fail loudly at creation, not call |
| 9 | Strict `NetworkLookup.__index` | network_lookup.lua:2360-2367; duplicate-entry ferror :2346-2356 | class 4 (docs/BUG_CLASSES.md:256); class 31 wire safety (:1307) |
| 10 | 200 locals per function (Lua 5.1) | hit by monolithic files accumulating top-level locals | class 11 (docs/BUG_CLASSES.md:591); module splits are the fix |
| 11 | Forward-ref closure binds `_G` | file-local split moves definitions; a name referenced before its `local` decl silently resolves global | class 6 (docs/BUG_CLASSES.md:341); mod-lint forward-ref check |
| 12 | `mod:dofile` is NOT a singleton | every call re-executes and returns fresh values | memory `reference_vmf_dofile_not_singleton`; only the entry manifest may dofile modules (event_tweaker/scripts/mods/event_tweaker/event_tweaker.lua:19-23) |
| 13 | VMF file load order: loc -> data -> script | nothing the script sets exists when data/loc evaluate; share pure data via `require()`d modules (cached once) | memory `reference_vmf_mod_file_load_order`; evt catalog precedent (event_tweaker.lua:33-38) |
| 14 | `jit.off()` at boot | boot_init.lua:3-5 - LuaJIT compilation is OFF; per-frame Lua costs what it costs, no JIT rescue | favor FrameTable/pre-sized tables in hot paths |
| 15 | Release builds scrub `io`/`ffi` | boot_init.lua:223-250 | mod file I/O is read-only by design (memory `reference_vt2_mod_file_io`) |

## 5. Implications for our mods - concrete improvements

Our house style (VMF `mod` object + `mod:dofile` manifest + `mod._ns` namespace + a few
`class()` view classes) is compatible with the engine's idioms. The gaps:

### 5.1 Reinvented `table` utilities (P2 - fold into WS4 `_lib_table`)

We call engine `table.clone`/`table.shallow_copy` 99 times across 20+ files, yet ALSO
carry 6+ hand-rolled copies with divergent semantics:

| Ours | Engine-idiomatic replacement |
|---|---|
| `enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker.lua:423` `_deep_copy` | `table.clone(t, true)` (table.lua:31) - identical semantics for plain data |
| `gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_definitions.lua:38` `_deep_copy` (+ gui_tweaker_dev twin) | same |
| `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua:126` `_deepcopy`, `:829` `_shallow_copy` | `table.clone(t, true)` / `table.shallow_copy(t, true)` |
| `general_tweaker/scripts/mods/general_tweaker/_gt_bot_fixes.lua:58` `_gt_deep_copy` (+ dev :81) | `table.clone(t, true)` |
| `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua:2230` `_shallow_copy` | `table.shallow_copy(t, true)` |
| `weapon_tweaker/scripts/mods/weapon_tweaker/wt_dev_anim_picker.lua:1309` `_is_in` | `table.contains` (table.lua:265) |

KEEP `_gt_cs_deepcopy` (`general_tweaker/scripts/mods/general_tweaker/_gt_creature_spawner.lua:311`) -
it carries a `copies` visited-set for cycles, which engine `table.clone` lacks (trap 6).
The right landing spot is the WS4 shared-lib pass (docs/OOP_REFACTOR_PLAN.md:87-93): a
copied `_lib_table.lua` documenting when engine fns suffice vs when the cycle-safe local
is required.

### 5.2 God-file decomposition should produce engine-style classes, not bigger function bags (P1)

WS5 (docs/OOP_REFACTOR_PLAN.md:95-110) has ct_dev at 14,328 lines, cwv 11,808,
cosmetics 10,499, cim_dev 8,173. The evt (event_tweaker) pilot proved the manifest + `mod._evt` namespace
split (event_tweaker/scripts/mods/event_tweaker/event_tweaker.lua:11-64). For STATEFUL
subsystems the next decompositions should go one step further and use `class()` the way
gut already does (`gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_view.lua:23` local
class; `_mod_tweaker_state.lua:214` global class where vanilla instantiates by NAME):
instance state lives on `self`, teardown is `delete()`/`destroy()` (class.lua:42-48),
and the 200-locals ceiling (trap 10) stops being a constraint because state moves off
file-level locals. Rule of thumb: global class ONLY when an engine registry resolves it
by name (script_unit.lua:99, hero_view_state_overview.lua:308); otherwise
`local Foo = class(Foo)` inside the module.

### 5.3 Derived-class hook lint (P2 - new mod-lint rule)

The class-copy trap (3.1) is currently guarded only by prose (CLAUDE.md "HOOK THE DERIVED
CLASS") and by the pair-hooks we already wrote. A mechanical guard is cheap: generate the
base -> derived map once from the decompile (`grep '^\w+ = class(\w+, \w+)'` - the
inheritance is always declared on one line, e.g. menu_world_previewer.lua:7), then have
`tools/mod-lint/lint-mod.ps1` warn when a mod hooks a class that appears as a BASE in
that map without also hooking each derived class. Would have caught wt v0.12.16 before
ship.

### 5.4 State-event registration helper (P2 - WS4 candidate)

gt's pointer-compare re-register dispatcher
(general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua:1958-1976) is the only
fully correct handling of trap 5 + the one-registration-per-(object,event) collision
(general_tweaker.lua:1920-1927) in the repo; ct
(chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua:7282) and
gut (`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_damage_numbers.lua:87`) hand-roll
their own manager-liveness checks. Extract gt's pattern as `_lib_state_event.lua`
(register-named-method + per-frame pointer compare + pcall-isolated handler fan-out) in
the WS4 pass so every mod gets the same lifecycle handling.

### 5.5 Bare `_G` globals (P2 - already tracked, WS6)

`_MEM_PROBE_T0_*` bare globals in 6 mods (docs/OOP_REFACTOR_PLAN.md:114) violate the
engine's own discipline - vanilla guards every intentional global with
`X = X or ...` / `rawget(_G, ...)` (frame_table.lua:3-5, script_unit.lua:5-11). Namespace
under `mod.` per the WS6 item.

### 5.6 Variadic capture: use `table.pack` (P2 - doc-level)

`docs/VMF_RECIPES.md` 2a's nil-hole-safe capture (`select("#", ...)` into `n`) is
hand-rolled at each site; engine `table.pack` (table.lua:210-214) returns exactly the
`(args, n)` pair the recipe needs. New hook wrappers should write
`local args, n = table.pack(...)` + `unpack(args, 1, n)`. Not worth a retrofit sweep -
adopt in new code and in VMF_RECIPES 2a's canonical example.

### 5.7 What we already do right (do not "fix")

- Pair-hooking base + derived previewers (cosmetics_tweaker.lua:5310/5346; cwv
  character_weapon_variants.lua:2922/10719+10727) - keep.
- Idempotent global class for the shared Material Hijack extension
  (_material_hijack_embedded_anim.lua:28) - engine-idiomatic coexistence, keep.
- `require()` for pure-data modules shared with `_data`/`_localization` files
  (event_tweaker.lua:33-38 + `_evt_selection.lua:26-28`) - matches the vanilla settings
  idiom (1.5), keep and replicate in future decompositions.
- `rawget` discipline on `ItemMasterList`/`NetworkLookup` (repo-wide) - keep.
