# General Tweaker Changelog

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

The free camera (`gt freecam`) was supposed to detach the camera while leaving the character in place — but WASD was still moving the character alongside the camera. The engine's `_enter_free_flight` calls `input_manager:block_device_except_service("FreeFlight", "keyboard", ...)` which is meant to stop the Player input service from receiving keyboard input, but empirically that block doesn't reliably stop the character state machine from reading movement.

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

`gt noclip` previously relied on `mod.on_setting_changed` firing after `mod:set("noclip_enabled", ...)` to actually flip the locomotion state. That worked from the VMF settings menu but was unreliable when toggled from the chat command. Added an explicit `_apply_noclip(new_val)` call after the `mod:set`, mirroring the same belt-and-suspenders pattern `tp` already uses.

Also added `mod:info` diagnostic lines in `_apply_noclip` — every toggle now logs `[noclip] ON — loco.state now '...'` or `[noclip] no locomotion extension yet ...` so post-mortem debugging of "didn't work" reports is one log-grep instead of a re-build cycle.

## 0.2.16-dev (2026-05-14)

### Added: Noclip (player flies through walls)

New "Noclip" toggle in the Gameplay group plus a `gt noclip` chat command. Unlike the existing detached freecam, noclip moves the **player body** through walls — WASD flies in look direction, Space/Ctrl for up/down, Left Shift for a speed boost. Two new numeric sliders (`noclip_speed` default 15 m/s, `noclip_boost_multiplier` default 3.0x) tune the base and boost speed.

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
