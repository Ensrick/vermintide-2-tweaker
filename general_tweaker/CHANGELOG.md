# General Tweaker Changelog

## 0.2.32-alpha (2026-05-19)

### Fixed: Command-name collisions with Janoti's "Hacks" mod

The v0.2.26 → v0.2.31 port copied 11 command names verbatim from Hacks (Helpers 2). VMF only allows one global registration per command name; the first mod to load wins the slot and the other's registration is silently dropped with an error in console. Gt was loading before Hacks (alphabetical), so Hacks lost `/pause`, `/win`, `/fail`, `/restart`, `/kill_bots`, `/die`, `/ult_reset`, `/infinite_stamina`, `/giga_power`, `/inn_dmg`, and `/unkillable` entirely. Renaming gt's claims here releases all 11 slots back to Hacks.

| Old gt name | New gt name |
|---|---|
| `/pause` | `/gt_pause` |
| `/win` | `/gt_win` |
| `/fail` | `/gt_fail` |
| `/restart` | `/gt_restart` |
| `/kill_bots` | `/gt_killbots` |
| `/die` | `/gt_die` |
| `/ult_reset` | `/gt_ultreset` |
| `/infinite_stamina` | `/gt_stamina` |
| `/giga_power` | `/gt_gigapower` |
| `/inn_dmg` | `/gt_inndmg` |
| `/unkillable` | `/gt_unkillable` |

Hotkey widgets unchanged (they bind to `mod.gt_*` functions which were always gt-namespaced). Settings UI labels unchanged. Tooltips updated to reference the new command names.

`/win` had been a gt command since before the port too (renamed alongside the others — same collision).

## 0.2.31-alpha (2026-05-19)

### Changed: Disable Enemy Spawns now also flips the `script_data.ai_*` flag set
### Added: Engine-error nil-guards from Janoti's "Hacks" (Group F — final port batch)

**Broadened `/no_enemies` toggle:** the two `ConflictDirector` hooks still catch every spawn call, but the toggle now ALSO flips the same `script_data.ai_*_disabled` flag set Hacks uses (mini_patrol, critter, horde, roaming, boss, rush_intervention, specials, pacing, outside_navmesh_intervention). The script_data path aborts spawns earlier in the pacing/intervention pipelines so the spawner doesn't even queue work. Per `feedback_redundant_safeguards_ok` redundancy is welcome here — cost is nine boolean writes per toggle, missed-path failure (an enemy slipping through) is silent. `_apply_script_data_no_enemies` is forward-declared at the top of the file because `on_setting_changed` (which lives above the no_enemies section) needs to call it.

**Engine-error nil-guards (passive):** two `mod:hook` wrappers that no-op the call when the target unit is dead/nil, copied from Hacks:

- `VolumetricsFlowCallbacks.unregister_fog_volume(params, ...)` — bails if `params.unit` is nil or `not Unit.alive(params.unit)`. Suppresses the red `[Engine Error]` spam that occasionally shows up when a fog volume's owner unit was already collected.
- `Unit.get_data(unit, ...)` — bails if `unit` is nil. Suppresses error spam from systems that hand stale unit handles back to the engine during cleanup.

Both guards are pure pre-checks — the original function runs unchanged when inputs are valid.

This concludes the Janoti "Hacks" feature port (Groups A–F across v0.2.26 → v0.2.31). All 17 missing features ported plus 2 expansions to existing gt features.

## 0.2.30-alpha (2026-05-19)

### Added: Player State Toggles group — port from Janoti's "Hacks" (Group E)

Three small toggles kept distinct from gt's existing `god` umbrella:

- **`/inn_dmg`** — host-only flip of `DamageUtils.is_in_inn`. When the inn flag is off, the keep behaves like a mission (damage taken normally). Useful for sparring with bots in the keep without flipping all of godmode.
- **`/cloak`** + hotkey — visual invisibility (model hidden + invisible to AI). Uses `set_invisible(true, false, "gt_cloak")` with its own reason namespace so toggling cloak doesn't clobber godmode's invisibility (which uses `"gt_godmode"`) and vice versa.
- **`/unkillable`** — flips `script_data.player_unkillable`. You take damage normally, you can be grabbed by disablers, but the engine refuses to drop you below 1 HP. Different intent from `god` — this is "I want to feel hits while testing".

Only `cloak` gets a hotkey widget; the other two are command-only since they're niche toggles.

## 0.2.29-alpha (2026-05-19)

### Added: Buffs & Stats group — port from Janoti's "Hacks" (Group D)

New "Buffs & Stats" settings group + three chat commands + two sliders:

- **`/infinite_ammo`** — toggle infinite ammo + zero overheat. Applies the vanilla `twitch_no_overcharge_no_ammo_reloads` buff to the local player; if you're the host, also pushes it to every other player. Periodic re-apply every 1 second via the shared `mod.update` chain keeps the buff refreshed if anything tries to strip it.
- **`/infinite_stamina`** — toggle infinite stamina. Hooks `GenericStatusExtension.add_fatigue_points` and short-circuits the call when the flag is on, so stamina-cost actions (block, push, dodge-cost) never deplete the bar.
- **`/giga_power`** — multiply the Enhanced Power talent buff by 1000x. Snapshots the original `BuffTemplates.power_level_unbalance.buffs[1].multiplier` on first activation and restores it on toggle-off. Requires re-equipping the talent for the buff to refresh.
- **Base Crit Chance slider (0–100%)** — rewrites the current career's `CareerSettings[name].attributes.base_critical_strike_chance`. Auto-snaps back to that career's vanilla value when you switch careers (hooks `ProfileRequester.request_profile` + `GameModeInn._cb_start_menu_closed`). Per-session — game restart restores defaults.
- **Movement Speed slider (0–30 m/s)** — rewrites `PlayerUnitMovementSettings.move_speed` plus every per-unit override already snapshotted by the engine (reached via `debug.getupvalue(unregister_unit, 1)` since the per-unit table is a closure local). Per-session.

The infinite-stamina hook is always-registered (toggling on/off flips a flag inside the closure) to avoid VMF's duplicate-registration error.

## 0.2.28-alpha (2026-05-19)

### Added: Ult Controls group — port from Janoti's "Hacks" (Group C)

New "Ult" settings group with three features, all driven through `CareerExtension`:

- **`/ult_reset`** + hotkey — one-shot reset. Walks `_num_abilities` and calls `:reduce_activated_ability_cooldown_percent(i, 1)` on each, dropping every charge to 0 cooldown. Same primitive ThePageMan's "No Ult Cooldown" mod uses.
- **Cap Player Ult Cooldown** (toggle + 0–120s slider) — clamps every player-controlled career ability's remaining cooldown to at most the configured value, every `CareerExtension.update` tick. Effectively a configurable "short ult" without burning a talent slot.
- **Cap Bot Ult Cooldown** (toggle + 0–120s slider) — same idea but for AI-controlled units. Useful in solo-with-bots to see bots ult more aggressively.

Both caps share `mod._gt_clamp_cooldowns` which walks the ability's `cooldowns` array from the decaying-charge index downward, trims each entry, then re-runs the engine's `cooldown_paused` / `set_activated_ability_cooldown_unpaused` housekeeping so the ability HUD overlay stays in sync. This is the iteration pattern the engine expects — replicating it any other way desyncs the UI.

## 0.2.27-alpha (2026-05-19)

### Added: Time & Pause group — port from Janoti's "Hacks" (Group B)

New "Time & Pause" settings group with five widgets + three chat commands. Both features use the same engine primitive: `Managers.state.debug:set_time_scale(index)` where `index` selects an entry in `debug_manager.lua`'s `time_scale_list` (24 multipliers, index 13 = 1.0x).

- **Time Scale slider (1–24)** — change live; the new value is applied immediately and re-applied on every `StateIngame` entry (vanilla wipes the engine time scale on level transitions).
- **`/time_faster` / `/time_slower`** + bindable hotkeys — step the slider up/down by 1.
- **`/pause`** + hotkey + Pause Speed slider (1–24, default 1) — host-only toggle between the configured pause speed and normal. VT2 has no true freeze primitive; `set_time_scale(1)` is the closest thing (UI still updates). Clients see the change since time scale is server-driven.

The pause feature and the time slider share the same engine setter; if both are touched in the same session, the last write wins. We keep them as separate widgets matching Hacks's UX. Setting the slider while paused updates the post-unpause target but doesn't override the active pause speed.

## 0.2.26-alpha (2026-05-19)

### Added: Level Control group — port from Janoti's "Hacks" (Group A)

New "Level Control" settings group + six chat commands + six bindable hotkeys, sourced from the corresponding features in Janoti's [Hacks](https://steamcommunity.com/sharedfiles/filedetails/?id=3266071368) (uploaded as "Helpers 2"):

- **`/fail`** + hotkey — fail the current mission (`Managers.state.game_mode:fail_level()`).
- **`/restart`** + hotkey — retry the current mission (`Managers.state.game_mode:retry_level()`).
- **`/kill_bots`** + hotkey — kill every bot in the party. On EAC-secure realm only allowed pre-round (vanilla anti-cheat would flag mid-round bot kills); unrestricted on modded realm.
- **`/die`** + hotkey — kill your local character (`death_system:kill_unit`).
- **`/fix_sound`** + hotkey — stop the looping vortex SFX that gets stuck after restarting mid-storm. Fires `sfx_player_in_vortex_false` on the local first-person extension, same trick Craven's script uses.
- **`/win`** also gets a hotkey (the command itself already existed in v0.2.25).

All five level-flow commands no-op in the keep with a friendly echo so a mis-press while sorting loadout doesn't yank you out of the inn state machine. The `mod.gt_*` functions are exposed as named members (not just locals) so VMF's `keybind_type = "function_call"` resolver can find them via the `function_name` string.

## 0.2.24-alpha (2026-05-17)

### Added: Skip Intro Splash Screens toggle

New "Startup" group with a single checkbox: **Skip Intro Splash Screens**. Same end result as bIbIbI's [Skip Intro mod](https://steamcommunity.com/sharedfiles/filedetails/?id=1395453301) — skips the Fatshark/engine logo splash sequence at game launch.

Implementation uses the canonical vanilla bypass: `StateSplashScreen.on_enter` (state_splash_screen.lua:92-110) checks a set of `Development.parameter` flags including `"skip_splash"` — if any are set, `self._skip_splash = true` and the splash sequence is bypassed. Same mechanism as the `-skip-splash` command-line argument.

`Development.set_parameter()` is a no-op in release builds, so we write directly to `Development._hardcoded_dev_params.skip_splash` (same trick the third-person camera section uses for `third_person_mode`). Done at mod load time, which runs before `StateSplashScreen.on_enter`, so the flag is in place when the check fires.

**Note:** changing the setting mid-session shows no immediate change — the splash for the current boot has already run. The flag is still updated so the next launch reflects the new setting.

## 0.2.23-alpha (2026-05-17)

### Added: AI Takeover VMF widget

The `/ai` command from v0.2.22 is now also exposed as a checkbox in the Gameplay group ("AI Takeover (bot controls your character)"). Chat command and checkbox stay in lockstep — the command just flips the setting, and `on_setting_changed` runs the same RPC pipeline. Auto-resets to off on game state change (level transition / leaving a mission) so the checkbox never persists a stale "on" across runs that didn't actually swap.

Same v1 scope as v0.2.22: client-only, refused on host self-toggle, refused in versus and the keep.

## 0.2.22-alpha (2026-05-17)

### Added: AI Toggle (`/ai`) — hand off control to a bot mid-mission

New chat command `/ai` lets a **client** hand their character over to bot AI (and toggle back). Useful for multiplayer testing where the mod author hosts on one machine and wants the second machine's player to behave as a bot, and as a general "stepping away" utility for clients who need to leave mid-run.

VT2 has no hot-swap path between human and bot units — they use different `go_type`s with incompatible extension stacks. So toggling means despawn-human + add-bot (and the reverse). Both halves of the dance exist in vanilla (see `GameModeBase._add_bot_to_party` / `_remove_bot_instant` and `GameModeAdventure.player_entered_game_session`); we compose them and wire them to a player-driven trigger.

Server-driven by necessity — `ProfileSynchronizer` and `PartyManager` mutation APIs all assert `is_server`. Client sends a VMF network request (`gt_ai_toggle_request`) and the host runs the swap. Host saves the original peer/profile metadata; toggling again recreates the human Player object via `add_remote_player`, re-claims the slot via `assign_peer_to_party`, and re-assigns the profile via `assign_full_profile(..., is_bot=false)`. Spawning system picks them up next tick.

**v1 scope:**
- Client (remote peer) self-toggle: supported.
- Host self-toggle: refused with a message — destroying the host's local Player object mid-mission would tear down camera/HUD/input bindings that aren't trivial to recreate.
- Versus: refused (heroes have no bot AI in versus).
- Keep / inn: refused (no spawning system running).

**Known rough edges (acceptable for v1, will iterate based on testing):**
- Inventory / current ammo / temporary buffs don't persist across the swap — the bot inherits the profile's default loadout from the spawning system.
- Client-side camera transition when their unit despawns is whatever vanilla does for "your player_unit just got removed" (likely spectator-style); untested.

## 0.2.21-alpha (2026-05-16)

### Added: Disable Enemy Spawns toggle

New checkbox in the Gameplay group + `/no_enemies` chat command. When on, every enemy spawn — hordes, specials, bosses, patrols, and pre-placed level-load enemies — is refused. Every enemy in VT2 funnels through `ConflictDirector`'s two public entry points (`spawn_queued_unit` for the pacing-system queue, `spawn_unit_immediate` for terror events / scripted triggers); hooks on both refuse the call when the setting is on.

Existing enemies are NOT despawned — the toggle affects future spawns only. Combine with `/god` to walk past anything already alive when toggling mid-mission.

Tooltip + Workshop description updated. Chat-command bullet line in the Workshop description extended with `/no_enemies`.

## 0.2.20-alpha (2026-05-15)

### Changed: Godmode now also makes the player invisible to enemy AI

Uses the engine's own canonical signal — `GenericStatusExtension:set_invisible(true, false, "gt_godmode")` — which AI perception explicitly skips (`perception_utils.lua:381`). Same primitive Shade's Shadowfall ult uses, just with a `reason = "gt_godmode"` namespace so it doesn't clobber other invisibility sources.

`skip_third_person=false` so the 3P body fades as a visual cue that godmode is on. First-person view (1P weapon arms) is unaffected since those are a separate unit.

Belt-and-suspenders re-apply on each `GenericStatusExtension.extensions_ready` — `self.invisible` is reset to `{}` on extension init, so a level transition while godmode is on would otherwise leave the new player unit visible to AI.

Tooltip + Workshop description updated. Forward-declared `_apply_godmode` at the top of the file so `on_setting_changed` (defined before the godmode section) can bind to the local instead of a nil global — see `feedback_lua_forward_reference.md`.

## 0.2.19-alpha (2026-05-15)

### Changed: Godmode now also blocks disablers

The two `DamageUtils` hooks (add_damage_network, add_damage_network_player) stop hp damage but disablers (gutter runner / assassin pounce, packmaster hook, chaos-spawn / corruptor / tentacle grabs, hanging cage) bypass the damage pipeline entirely — they push the character state machine directly into the disabler state.

Hook `GenericStateMachine.change_state` (the chokepoint every `csm:change_state(state_name, params)` call funnels through) and drop the transition when (a) godmode is on AND (b) the unit is the local player AND (c) the requested state is one of: `pounced_down`, `grabbed_by_pack_master`, `grabbed_by_chaos_spawn`, `grabbed_by_corruptor`, `grabbed_by_tentacle`, `in_hanging_cage`. Normal gameplay states (`stunned`, `ledge_hanging`, `overpowered`, `knocked_down`, `dead`) are NOT touched.

Godmode tooltip + Workshop description updated to advertise the broader behaviour.

## 0.2.18-alpha (2026-05-14)

### Fixed: Free camera now actually freezes the player

The free camera (`/freecam`) was supposed to detach the camera while leaving the character in place — but WASD was still moving the character alongside the camera. The engine's `_enter_free_flight` calls `input_manager:block_device_except_service("FreeFlight", "keyboard", ...)` which is meant to stop the Player input service from receiving keyboard input, but empirically that block doesn't reliably stop the character state machine from reading movement.

Belt-and-suspenders fix: while freecam is active, also call `loco:set_disabled(true)` on the local player's locomotion extension. That yanks the unit out of the locomotion update list entirely — character state machine still ticks (animation pose, etc.) but no movement can be applied regardless of what the Player input service produces. On freecam exit (toggle off, F8 press, or level transition via the `_exit_free_flight` hook), `loco:set_disabled(false)` re-enables the character cleanly. `pcall`-wrapped to survive engine API drift.

## 0.2.17-dev — first public Workshop release (2026-05-14)

### Changed: Workshop visibility flipped private → public

gt was uploaded as `friends_only` from its inception. After the noclip feature landed and verified working in 0.2.17-dev, the user flagged the mod ready for a public release. `itemV2.cfg`:

- `visibility`: `"friends_only"` → `"public"`
- `title`: `"Tweaker: General (WIP)"` → `"Tweaker: General"`
- `description`: replaced the one-liner with a sectioned feature description matching ct/cim/the rest of the Tweaker series — Third-Person Camera, Noclip, Keep Menus in Missions, Gameplay toggles, Chat commands, Compatibility — plus the canonical BMC block.
- `preview.jpg`: replaced with the Tweaker General artwork (1024×1024, JPG q=85, 215 KB).

`upload_gt.ps1`'s visibility guard updated `friends_only` → `public` and `--allow-public` added so the launcher's safety gate is satisfied. Upload pushed via `vmblauncher upload general_tweaker --allow-public`; verified live via `ISteamRemoteStorage/GetPublishedFileDetails`: `visibility=0`, `file_size=1346271` (matches `bundleV2/` byte-for-byte).

## 0.2.17-dev (2026-05-14)

### Fixed: Noclip chat command now applies immediately

`/noclip` previously relied on `mod.on_setting_changed` firing after `mod:set("noclip_enabled", ...)` to actually flip the locomotion state. That worked from the VMF settings menu but was unreliable when toggled from the chat command. Added an explicit `_apply_noclip(new_val)` call after the `mod:set`, mirroring the same belt-and-suspenders pattern `/tp` already uses.

Also added `mod:info` diagnostic lines in `_apply_noclip` — every toggle now logs `[noclip] ON — loco.state now '...'` or `[noclip] no locomotion extension yet ...` so post-mortem debugging of "didn't work" reports is one log-grep instead of a re-build cycle.

## 0.2.16-dev (2026-05-14)

### Added: Noclip (player flies through walls)

New "Noclip" toggle in the Gameplay group plus a `/noclip` chat command. Unlike the existing detached freecam, noclip moves the **player body** through walls — WASD flies in look direction, Space/Ctrl for up/down, Left Shift for a speed boost. Two new numeric sliders (`noclip_speed` default 15 m/s, `noclip_boost_multiplier` default 3.0x) tune the base and boost speed.

Built on the engine's `script_driven_no_mover` locomotion state (used by chaos-spawn-grab and tentacle-grab), which teleports the unit by `velocity_wanted * dt` each tick without touching the mover — so static geometry, props, and enemies are all bypassed. The dead-simple `Mover.set_collision_disabled` / `set_mover_disable_reason("noclip", true)` paths don't work for players: the locomotion templates and `PlayerUnitLocomotionExtension` call `Mover.flying_frames(mover)` and `Mover.move(mover, ...)` without nil-guarding the mover, so nuking it fatals immediately. The no-mover *state* path bypasses both calls without touching the mover handle.

Three hooks make it stick:

1. **`PlayerUnitLocomotionExtension.update_script_driven_no_mover_movement`** — when noclip is on for the local player, ignore whatever velocity the character state machine wrote (walking writes ground-plane velocity, falling writes gravity) and compute our own from W/A/S/D + Space/Ctrl projected through the first-person camera rotation.
2. **`mod.update` heartbeat** — re-asserts `loco.state = "script_driven_no_mover"` each tick. Basic states (standing/walking/jumping/falling) don't touch `locomotion.state`, but transitions into ledge-hang / ladder / knockdown call `enable_script_driven_movement()` which would hand us back to the wall-respecting mover update.
3. **`PlayerUnitLocomotionExtension.extensions_ready`** — re-arms noclip on each player spawn (mission entry, respawn) if the persisted VMF setting is on. Without this, the setting stays "on" while the actual locomotion state is whatever the engine initialised it to (usually `script_driven`).

On toggle-off, the mover is snapped to the player's current position before handing control back, otherwise the mover stays at the entry point and the next `Mover.move()` yanks the player back there.

Caveats baked into the tooltip: toggling off mid-air drops you, and special states (ledge-hang/ladder/career-ability/knockdown) may briefly fight the mode.

## 0.2.10-dev (2026-05-01)

### Changed: Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`gt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`general_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3713619122` and internal mod ID `"gt"` preserved — existing user settings are unaffected.

`itemV2.cfg` set to `visibility = "private"` (overriding the prior local `upload/item.cfg` which had `"public"` — never re-asserted on Workshop because no upload was performed during the migration).
