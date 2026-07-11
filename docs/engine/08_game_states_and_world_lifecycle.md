# Engine reference 08 - Game states, managers and world lifecycle

Engine-reference doc for the VT2 monorepo. Every claim cites a file:line. Vanilla
paths are relative to `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our
paths are relative to this monorepo. Unverified statements are tagged `[unverified]`.

The single most important fact in this doc: **mods tick OUTSIDE the game-state
machine.** `Boot.game_update` calls `Managers.mod:update(dt)` first thing every
frame (`scripts/boot.lua:748-750`), before the state machine (`:772`, `:786`) and
before `Managers.world:update` (`:788`). Your `mod.update` therefore runs on every
frame of every state - splash, title, loading, ingame, AND the frames between
states where the level world does not exist. Every per-frame consumer must be
written for that reality.

---

## 1. Architecture map

| File (vanilla) | Class / global | Single responsibility |
|---|---|---|
| `scripts/boot.lua` | `Boot`, `Game` | Engine entry points `init`/`update`/`render`/`shutdown` (`:557-592`); boot package loading + `ModManager` creation (`:399-414`); the master per-frame update loop `Boot.game_update` (`:744-915`); render loop `Boot.game_render` (`:530-543`); global manager creation `Game._init_managers` (`:1538-1631`) |
| `foundation/scripts/util/state_machine.lua` | `StateMachine` | Minimal FSM: `_change_state` runs old `on_exit` then `new_state:new()` then `on_enter` synchronously (`:40-68`); `update` swaps state when a state's `update` returns a class (`:74-80`) |
| `scripts/game_state/game_state_machine.lua` | `GameStateMachine` | `StateMachine` subclass that notifies `Managers.mod:on_game_state_changed("exit"/"enter", NAME, state)` around every transition (`:13-28`) and on destroy (`:60-68`) |
| `foundation/scripts/managers/managers.lua` | `Managers` | Global registry with three lifecycle groups `global`/`venture`/`state` (`:10-14`); creation order recorded via `__newindex` metatables (`:106-195`); group destroy runs in reverse creation order (`:26-44`); `Managers.state.destroy` / `Managers.venture.destroy` group wipes (`:82-88`); `on_round_start/end`, `on_venture_start/end` broadcasts (`:90-104`) |
| `foundation/scripts/managers/world/world_manager.lua` | `WorldManager` (`Managers.world`) | Owns every `World` handle by name. `create_world` (`:18-58`), `destroy_world` (`:64-105`), `has_world` (`:107-109`), `world` - **fasserts on missing name** (`:111-115`), layered update queue (`:117-131`), render (`:133-137`), deferred destroy while `locked` (`:64-69`, `:126-130`) |
| `scripts/game_state/state_ingame.lua` | `StateIngame` | The playable state (keep AND missions - the keep is just a `hub_level`, `:133-135`). Builds the whole `Managers.state.*` context (`:2178-2424`), per-player `StateInGameRunning` sub-machines (`:388`), tears everything down in `on_exit` (`:1847-2120`) |
| `scripts/game_state/state_ingame_running.lua` | `StateInGameRunning` | Per-local-player sub-state inside StateIngame (`state_ingame.lua:388`); owns `ingame_ui` and player-facing flow. NAME at `state_ingame_running.lua:26` |
| `scripts/game_state/state_loading.lua` | `StateLoading` | Level-transition state: loads packages, spawns the next `level_world` asynchronously (`:1396-1419`), runs sub-state machine (`_setup_state_machine`, `:644`) with variants `StateLoadingRunning` / `StateLoadingRestartNetwork` / `StateLoadingMigrateHost` / `StateLoadingVersusMigration` (`scripts/game_state/loading_sub_states/win32/*.lua`); hands the spawned world/level to StateIngame through `loading_context` (`:1680-1681`) |
| `scripts/game_state/components/level_transition_handler.lua` | `LevelTransitionHandler` (`Managers.level_transition_handler`) | GLOBAL manager (created `boot.lua:1614`) that owns which level is current/next, level package load/unload (`:181-246`, `:518-591`), level seed/difficulty/mechanism data (`:379-433`), and the four synced package loaders (`:33-36`) |
| `scripts/utils/async_level_spawner.lua` | `AsyncLevelSpawner` | Creates the `level_world` (deactivated) and time-sliced-spawns the level into it (`:5-8`, `:63-65`) |
| `scripts/managers/mod/mod_manager.lua` | `ModManager` (`Managers.mod`) | Loads Workshop mods at boot; in state `done` relays per-frame `update` (`:130-137`) and `on_game_state_changed` (`:491-503`) to every enabled mod's callback table |
| `scripts/game_state/state_title_screen.lua`, `state_splash_screen.lua`, `state_demo_end.lua`, `state_dedicated_server*.lua` | title/splash/demo/dedicated states | Pre-game states. NAMEs: `StateSplashScreen` (`state_splash_screen.lua:12`), `StateTitleScreen` (`state_title_screen.lua:16`), `StateDemoEnd`, `StateDedicatedServer*` |
| `scripts/managers/transition/transition_manager.lua` | `TransitionManager` (`Managers.transition`) | Owns the persistent `top_ingame_view` overlay world (`:37-39`, `:66-74`) and fade in/out |

### State graph (PC client)

`StateSplashScreen` -> `StateTitleScreen` -> `StateLoading` -> `StateIngame` (keep) -> `StateLoading` -> `StateIngame` (mission) -> ... (starting state selected at `boot.lua:1744-1801`). Every keep<->mission move passes through StateLoading. There is no separate "keep state" - keep = StateIngame with `LevelSettings[level_key].hub_level` (`state_ingame.lua:133-135`).

### World inventory (name -> creator -> lifetime)

| World name | Created | Destroyed | Lifetime |
|---|---|---|---|
| `boot_world` | `boot.lua:594-609` | `boot.lua:656-664` at boot end | boot only |
| `top_ingame_view` | `transition_manager.lua:66-74` (TransitionManager, global) | app shutdown | **whole session** - safe to cache |
| `music_world` | `music_manager.lua:36` (MusicManager, global) | app shutdown | **whole session** - safe to cache |
| `level_world` (`LevelHelper.INGAME_WORLD_NAME`, `scripts/helpers/level_helper.lua:4`) | `AsyncLevelSpawner` during StateLoading (`state_loading.lua:1408`, `async_level_spawner.lua:63`) | `StateIngame._teardown_world` -> `Managers.world:destroy_world` (`state_ingame.lua:719`); or by StateLoading itself on abort/reload (`state_loading.lua:1756-1760`, `:1933-1937`) | one venture leg; **a new same-named world is a DIFFERENT handle every mission** |
| `loading_world` | `StateLoading._setup_world` (`state_loading.lua:226-231`) | `state_loading.lua:1803-1804` on_exit | StateLoading only |
| `dice_simulation`, `loot_world`, `character_preview`, `armory_preview`, etc. | per-feature UI/system worlds (`dice_roller.lua:157`, `hero_view_state_loot.lua:265`; preview worlds created by UI views) | with their owning view | transient - always probe |

### Manager lifecycle groups

- **global** (`Managers.X`): created in `Boot._init_managers` (`boot.lua:522-528`: time, world, token, state_machine, url_loader) and `Game._init_managers` (`boot.lua:1538-1631`: backend, music, transition, player, party, mechanism, lobby, level_transition_handler, ui, matchmaking is created later in StateIngame, etc.). Live for the whole session.
- **venture** (`Managers.venture.X`): venture = one keep-plus-missions play session. Started via `Managers.mechanism:check_venture_start` at StateIngame enter (`state_ingame.lua:103`), ended via `check_venture_end` at exit (`state_ingame.lua:2119`). `Managers.venture.statistics` is read at `state_ingame.lua:156`; group destroy = `managers.lua:86-88` [unverified exactly which mechanism call destroys the group].
- **state** (`Managers.state.X`): rebuilt EVERY state. StateIngame builds ~25 of them in `_setup_state_context` (`state_ingame.lua:2178-2424`); StateLoading builds only `Managers.state.event` (`state_loading.lua:167-169`). Wiped by `Managers.state:destroy()` at StateIngame on_exit `:1937` and StateLoading on_exit `:1788` - reverse creation order (`managers.lua:26-44`).

---

## 2. Lifecycle and data flow

### 2.1 The per-frame loop (Boot.game_update, boot.lua:744-915)

Order within one frame (client, Windows):

1. `Managers.mod:update(dt)` - **all mod.update callbacks** (`:748-750`, dispatch at `mod_manager.lua:130-137`)
2. `UPDATE_RESOLUTION_LOOKUP`, perfhud, updator, `Managers.time:update` (`:752-758`)
3. DLC manager `pre_update`s (`:762-770`)
4. `machine:pre_update` -> `StateIngame.pre_update` (`:772`; POSITION_LOOKUP refresh + network receive at `state_ingame.lua:804-829`)
5. `Managers.package:update`, `token:update` (`:773-774`)
6. `machine:update` -> `StateIngame.update` - **state transitions happen inside this call** (`:786`, `state_machine.lua:74-80`)
7. `Managers.state_machine:update`, **`Managers.world:update`** (ScriptWorld/physics/anim step, `:787-788`)
8. Platform managers, weave/news/transition/telemetry/etc. (`:797-866`)
9. `machine:post_update` -> `StateIngame.post_update` (unit spawn queue flush, RPC transmit, `:898`, `state_ingame.lua:1783-1809`)
10. `FrameTable.swap_and_clear()` (`:899`)

Render is separate: `Boot.game_render` runs `machine:pre_render`, `Managers.world:render`, `machine:render`, `machine:post_render` (`boot.lua:530-543`).

Consequences:
- A mod.update tick sees the world in LAST frame's state; the state machine and world update run after you.
- A "Leave Game" transition runs the ENTIRE StateIngame.on_exit teardown synchronously inside step 6. The very next frame's `Managers.mod:update` (step 1) runs with `level_world` destroyed, `Managers.state.*` wiped, `Managers.input == nil`. This gap lasts many frames (all of StateLoading's early life).

### 2.2 State transition mechanics

`GameStateMachine._change_state` (`game_state_machine.lua:13-28`):

1. `Managers.mod:on_game_state_changed("exit", old.NAME, old_state)` - **fires BEFORE `old_state:on_exit()`**, so the level world and state managers are still alive here (`:16-19`)
2. `old_state:on_exit()` then `new_state:new()` then `new_state:on_enter(params)` - all synchronous (`state_machine.lua:40-68`)
3. `Managers.mod:on_game_state_changed("enter", new.NAME, new_state)` (`:23-27`)

So VMF's `mod.on_game_state_changed(status, state_name)`:
- `("exit", "StateIngame")` = last moment the dying level world is guaranteed valid. **This is the engine-idiomatic release point for world-tied resources.**
- `("enter", "StateIngame")` = world, level and all `Managers.state.*` fully built (on_enter completed).
- ModManager silently drops the notification while mods are still loading (`mod_manager.lua:500-502`).

### 2.3 Level world handover (StateLoading -> StateIngame)

1. StateLoading waits for `_packages_loaded()` (level packages + backend profiles + enemy/pickup/synced/transient loaders + loadout resync, `state_loading.lua:1839-1900`)
2. `AsyncLevelSpawner` creates `level_world` DEACTIVATED and time-slice-spawns the level (`state_loading.lua:1396-1419`, `async_level_spawner.lua:63-65`)
3. On exit, StateLoading stashes `ingame_world_object`/`ingame_level_object` into `parent.loading_context` (`state_loading.lua:1680-1681`)
4. `StateIngame.on_enter` fasserts they exist and takes them (`state_ingame.lua:75-80`), registers the `"game"` timer (`:101`), clears POSITION_LOOKUP (`:102`), builds input (`:105-123`), builds `Managers.state.*` (`:277`, `:2178-2424`), then `_create_level`: `Level.finish_spawn_time_sliced` + `ScriptWorld.activate(world)` (`:743-747`)

So `Managers.world:has_world("level_world")` turns TRUE while still deep inside StateLoading - the world exists but is deactivated, empty of gameplay systems, and `Managers.state.entity`/`network`/etc. do not exist yet. World existence is NOT ingame-ness. Gate gameplay logic on state name or `Managers.state.network` presence, not on the world.

### 2.4 StateIngame.on_exit teardown order (the #459 timeline)

`state_ingame.lua:1847-2120`, key ordered steps:

| Line | Step |
|---|---|
| 1849 | `Managers:on_round_end()` broadcast (reverse group order, `managers.lua:94-96`) |
| 1896-1899 | `Managers.player:remove_player(...)` for every local player + per-player machine destroy - **fires on EVERY level transition, not just disconnects** (BUG_CLASSES 24) |
| 1911-1918 | game mode units cleaned, mutators deactivated, unit spawner unlocked+flushed |
| 1924-1929 | every stored network unit `World.destroy_unit`'d |
| 1931-1933 | entity system destroy, level shutdown flow event |
| 1934 | `Managers.player:exit_ingame()` - nils `player.network_manager`, `self.is_server` (`scripts/managers/player/player_manager.lua:170-181`; `is_server = nil` at `:180`) |
| 1935 | `_teardown_level` - level destroyed from world (`:704-706`) |
| 1937 | `Managers.state:destroy()` - ALL `Managers.state.*` = nil (reverse creation order) |
| 1939 | `_teardown_world` -> `Managers.world:destroy_world("level_world")` -> `Application.release_world` (`:708-720`, `world_manager.lua:95`) - **the C world is freed here** |
| 1950 | `Managers.time:unregister_timer("game")` - `Managers.time:time("game")` now errors |
| 1982-2062 | if leaving the lobby: matchmaking/game_server/network server-client/lobby destroyed |
| 2101-2104 | input manager destroyed; **`Managers.input = nil`** until StateLoading.on_enter recreates it (`state_loading.lua:181-202`) |

Everything above happens in ONE `machine:update` call. Mods never observe a half-torn state mid-frame, but the very next mod.update tick observes ALL of it gone at once.

### 2.5 What each state leaves alive for mods

| Alive during -> | Boot/mod-load | StateTitleScreen | StateLoading | StateIngame | between exit and next enter (same frame gap) |
|---|---|---|---|---|---|
| `Managers.time` `"main"` timer | yes (`boot.lua:523`) | yes | yes | yes | yes |
| `Managers.time` `"game"` timer | no | no | no | yes (`state_ingame.lua:101`/`1950`) | no |
| `Managers.world` / `top_ingame_view` / `music_world` | yes (after `Game._init_managers`) | yes | yes | yes | yes |
| `level_world` | no | no | late + deactivated (`state_loading.lua:1408-1419`) | yes | NO |
| `Managers.state.event` | no | [unverified] | yes (`state_loading.lua:167-169`) | yes | no |
| `Managers.state.network/entity/game_mode/conflict/...` | no | no | no | yes (`state_ingame.lua:2178-2424`) | no |
| `Managers.player` (manager object) | yes (`boot.lua:1604`) | yes | yes | yes | yes - but players removed, `is_server` nil (`player_manager.lua:170-181`) |
| `Managers.input` | nil | state-owned | yes (`state_loading.lua:184`) | yes (`state_ingame.lua:108`) | NIL (`state_ingame.lua:2104`) |
| `Managers.backend`, `Managers.mechanism`, `Managers.level_transition_handler`, `Managers.lobby`, `Managers.party`, `Managers.ui` | yes (global, `boot.lua:1538-1631`) | yes | yes | yes | yes |
| POSITION_LOOKUP freshness | n/a | stale | stale | fresh (`state_ingame.lua:808`) | stale (BUG_CLASSES 21) |

---

## 3. Hookable seams

| Seam | Fires | Safe pattern | Traps |
|---|---|---|---|
| `mod.update(dt)` (VMF callback; dispatched `mod_manager.lua:130-137` from `boot.lua:748-750`) | every frame, EVERY state, including between states | Treat as stateless poll. Probe everything: `Managers.world:has_world(name)` before `:world(name)`; nil-check `Managers.state.X`, `Managers.input`, `Managers.player:local_player()`. Use ONE registry per mod (see section 5) | runs before state machine + world update; `Managers.time:time("game")` errors outside StateIngame; POSITION_LOOKUP stale (BUG_CLASSES 21) |
| `mod.on_game_state_changed(status, state_name)` (VMF; engine relay `game_state_machine.lua:13-28` + `mod_manager.lua:491-503`) | "exit" BEFORE old state's on_exit; "enter" AFTER new state's on_enter | Release world-tied resources (LineObjects, screen GUIs, spawned units, cached handles) on `("exit", "StateIngame")` - world still alive. Arm/initialize on `("enter", "StateIngame")` - full context exists | do NOT do world work on `("enter", "StateLoading")` - no level world; notification skipped while mods still loading (`mod_manager.lua:500-502`) |
| `StateIngame.on_enter` / `on_exit` hook (`state_ingame.lua:75`, `:1847`) | once per venture leg | `mod:hook_safe("StateIngame", "on_enter", ...)` post-fires with everything built. For on_exit, a PRE-wrapper (`mod:hook`) sees the live world; a `hook_safe` post-callback sees it destroyed | grep for existing hooks first (NON-NEGOTIABLE 8); prefer the VMF state-changed callback - it already gives you both edges without hooking |
| `GameModeManager` / round events: `Managers:on_round_start/on_round_end` (`managers.lua:90-96`, called `state_ingame.lua:1849`) | round boundaries | define `on_round_end` on your own manager-like object only if you register it into a Managers group [not recommended for mods]; otherwise hook a consumer | round_end fires before ANY teardown - good early-warning if you already hook something with that name |
| `PlayerManager.exit_ingame` (`player_manager.lua:170`) | every StateIngame exit | `hook_safe` = "players are gone now" signal | peer-keyed caches wiped every map change, not just disconnect (BUG_CLASSES 24) |
| `LevelTransitionHandler.load_current_level` (`level_transition_handler.lua:181`) | when the next level's packages start loading | `hook_safe` to observe upcoming `level_key` via `:get_current_level_key()` (`:379-381`) | client vs server data source differ (`_network_state` vs `_offline_level_data`, `:379-433`); next-level getters fassert on clients (`:331-377`) |
| `WorldManager.create_world` / `destroy_world` (`world_manager.lua:18`, `:64`) | any world birth/death | `hook_safe` to invalidate cached handles by name | `destroy_world` may be called with a world OBJECT or a NAME (`:71-77`); during `WorldManager.update` destruction is deferred via `locked` (`:64-69`, `:126-130`) so death can lag one call |
| `StateLoading.on_enter` (`state_loading.lua:54`) | every transition | `hook_safe` for "we are now between levels" | several StateLoading sub-states exist (`loading_sub_states/win32/`); don't assume plain StateLoadingRunning |

**Reading state without hooking:** current level = `Managers.level_transition_handler:get_current_level_key()` (`level_transition_handler.lua:379`); hub check = `:in_hub_level()` (`:708-716`); ingame-ness = `Managers.state.network ~= nil` [pattern; any `Managers.state.*` works since the group is wiped at `state_ingame.lua:1937`].

---

## 4. Traps and crash classes

1. **Dead-world dispatch (issue #459; the class this doc exists for).** `LineObject.dispatch(world, lo)`, `World.destroy_unit(world, u)`, `Gui.*` on a gui of a destroyed world, or ANY C-side call through a freed world pointer is a 0xc0000005 access violation that **pcall cannot catch** (the AV is on the crashing C stack). Timeline: StateIngame.on_exit destroys `level_world` (`state_ingame.lua:1939` -> `world_manager.lua:95`) while mod.update keeps ticking (`boot.lua:748-750`). Two required gates, both shipped in gt-dev:
   - existence: `wm:has_world("level_world")` before `wm:world(...)` - `world()` fasserts on a missing name (`world_manager.lua:112`) (`general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_debug_highlights.lua:214-221`);
   - **identity**: the cached handle must be `==` the currently-live world - a NEW same-named world next mission passes `has_world` but does not validate the OLD handle (`general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_teleport_lab.lua:995-1022`, `_gt_debug_highlights.lua:234-259`).
   Candidate for a BUG_CLASSES entry of its own; nearest existing entries are 22/23 (docs/BUG_CLASSES.md).
2. **`WorldManager.world()` fassert** (`world_manager.lua:111-115`). `Managers.world and Managers.world:world("level_world")` is NOT a guard - the `and` chain never reaches your nil-check because `world()` raises first. Only `has_world` (`:107-109`) is a probe.
3. **World exists != ingame.** `level_world` is created mid-StateLoading, deactivated and empty (`state_loading.lua:1408`, `async_level_spawner.lua:65`). Gate on state, not world.
4. **`Managers.input` is nil between StateIngame exit (`state_ingame.lua:2104`) and StateLoading enter (`state_loading.lua:184`).** Per-frame `Managers.input:get_service(...)` without a nil-check dies exactly on Leave Game. Cross-ref BUG_CLASSES 20 (input-device re-route).
5. **`Managers.time:time("game")` errors outside StateIngame** (registered `state_ingame.lua:101`, unregistered `:1950`). Use `Managers.time:time("main")` for wall-clock needs in mod.update.
6. **POSITION_LOOKUP is chat/state-phase stale** - only refreshed in `StateIngame.pre_update` (`state_ingame.lua:808`) and cleared at enter (`:102`). BUG_CLASSES 21: read `Unit.world_position` live.
7. **`PlayerManager.remove_player` on every transition** (`state_ingame.lua:1896-1899`): BUG_CLASSES 24 - peer-keyed caches keyed off remove_player get wiped every map change.
8. **Keep-only Gui materials drawn mid-mission** = draw fatal, and mission-substituted UI worlds AV in `ShadingEnvironment.blend`: BUG_CLASSES 23 and 22. Both are "world/state changed under a cached UI resource" cousins of #459.
9. **`Managers.state.event` is rebuilt per state** (`state_loading.lua:167-169`, `state_ingame.lua:2207-2209`) and the whole state group dies at `state_ingame.lua:1937` / `state_loading.lua:1788`. Event registrations do not survive transitions; re-register on `("enter", ...)`. Also note BUG_CLASSES 3b (`event:register` 3rd-arg form).
10. **Mod "exit" notification order.** `on_game_state_changed("exit", ...)` fires BEFORE teardown (`game_state_machine.lua:16-21`) - resources released there need no dead-world dance. But anything you KEEP past that callback must survive the full teardown ordering in section 2.4.
11. **`Boot.flow_return_table` cleared every frame** (`boot.lua:886`) and `FrameTable.swap_and_clear` (`boot.lua:899`) - never retain engine frame-table values across frames (same family as the Vector3 stack-temporary rule, BUG_CLASSES 12).
12. **Application shutdown path** = `GameStateMachine.destroy(true)` -> `on_exit(application_shutdown=true)` (`boot.lua:917-919`, `state_machine.lua:82-86`): mods get an "exit" notification with NO "enter" ever following (`game_state_machine.lua:60-68`). Do not assume enter/exit pairing.

---

## 5. Implications for our mods

### State-safety checklist for every per-frame consumer (mod.update)

1. Register through the mod's ONE update registry (gt-dev pattern: `general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua:336-352` - ordered, per-consumer pcall, error LOGGED). Never rewrap `mod.update` ad hoc (BUG_CLASSES 8).
2. First line: cheap enable-flag bail (`mod:get(...)` cached or read directly).
3. World access: `local wm = Managers.world; if not (wm and wm:has_world("level_world")) then <release cached handles>; return end` (`world_manager.lua:107-115`).
4. Cached world-tied resources (LineObject, Gui, spawned units): keep the WORLD HANDLE you created them in; before touching them require `cached_world == wm:world("level_world")` (identity, not just existence - #459).
5. Primary release point = `mod.on_game_state_changed("exit", "StateIngame")` while the world is still alive (`game_state_machine.lua:16-21`); the update-time identity gate is the fallback, not the design.
6. Ingame-only logic gates on state (`Managers.state.network`/`Managers.state.game_mode` nil-checks), not on world existence (section 2.3).
7. `Managers.input`, `Managers.player:local_player()`, `player.player_unit` are all nil-able between states - guard each hop; `player_unit` additionally via `ALIVE[unit]`/`Unit.alive`.
8. Time: `Managers.time:time("main")` in mod.update; `time("game")` only behind an ingame gate (trap 5).
9. Never store raw `Vector3`/`Quaternion` across ticks (BUG_CLASSES 12); never trust POSITION_LOOKUP for the local player (BUG_CLASSES 21).
10. Peer-keyed caches: decide explicitly whether they survive level transitions; `remove_player` fires on every transition (BUG_CLASSES 24).

### Concrete improvement candidates (our file:line -> engine-idiomatic alternative)

| Pri | Mod | Site | Current -> idiomatic |
|---|---|---|---|
| P1 | cosmetics_tweaker | `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_tpe.lua:219-221` | `get_world()` returns `Managers.world:world("level_world")` with no `has_world` probe - fasserts (`world_manager.lua:112`) when TPE cleanup (`destroy_unit`, `:223-230`) runs after teardown. The SAME mod already has the correct helper `_level_world()` at `cosmetics_tweaker.lua:6789-6796` - reuse it, and release TPE units on `("exit","StateIngame")` |
| P1 | gui_tweaker_dev | `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_freecam.lua:135` (also `:252`) | `_drive_free_cam` calls `Managers.world:world(data.viewport_world_name)` per frame; the `if not world then return end` on `:136` is dead code because `world()` fasserts first. Probe `has_world` and force-exit freecam on `("exit","StateIngame")` |
| P1 | general_tweaker (STABLE - surface only, dev-first doctrine) | `general_tweaker/scripts/mods/general_tweaker/_gt_bot_teleport_lab.lua:868`, `_gt_solo_qol.lua:326` | Stable still has the pre-#459 ungated `world("level_world")` lookups that gt-dev fixed with has_world + identity gates. Promote the fix-459 work (in flight, fix-459-gtdev) with the next gt promotion |
| P2 | general_tweaker_dev (+stable) | `general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_creature_spawner.lua:342` | `_gt_cs_position_at_cursor` does ungated `Managers.world:world("level_world")` then `World.get_data` - a spawn command issued outside StateIngame fasserts. Add the has_world probe + friendly echo |
| P2 | character_weapon_variants + tools/shared_lib | `character_weapon_variants/scripts/mods/character_weapon_variants/_lib_peer_parity.lua:287-293` (copy: `tools/shared_lib/_lib_peer_parity.lua:289`) | capture-prev `mod.update` rewrap whose `pcall(prev, dt)` SWALLOWS the previous chain's errors silently - BUG_CLASSES 8 plus invisible failure. Adopt the gt-dev registry (log the error like `general_tweaker_dev.lua:347-350`) or require hosts to call `inst:tick(dt)` from their registry |
| P2 | character_weapon_variants | `character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:6254`, `:11101`, `:11205` | three more ungated `Managers.world:world("level_world")` (`6254` in a unit-spawn hook where `self.world` fallback makes it rare; `11101`/`11205` in chat commands). Standardize one `mod._cwv_level_world()` has_world helper |
| P2 | gui_tweaker_dev | `gui_tweaker_dev/scripts/mods/gui_tweaker_dev/hb/mod_events.lua:92-97` | `mod.hb_update` iterates `update_funcs` with NO per-consumer isolation - one HB feature error kills all later ones (contrast gt-dev registry). Wrap each `update_func()` in pcall + `mod:error` log |
| P2 | repo-wide doctrine | (multiple mods' on_game_state_changed) | Most mods use `("enter", "StateIngame")` (arming) but almost none use `("exit", "StateIngame")` as the primary world-resource release point even though it fires BEFORE teardown (`game_state_machine.lua:16-21`). Adopting exit-release removes whole #459-class defensive code from update paths |
