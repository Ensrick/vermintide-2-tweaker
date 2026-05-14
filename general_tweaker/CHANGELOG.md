# General Tweaker Changelog

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
