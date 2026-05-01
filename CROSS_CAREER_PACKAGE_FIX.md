# Fix Plan: Cross-Career Weapon Resource Package Crash

## Problem

When a player equips a cross-career weapon via weapon_tweaker and enters a mission (especially Chaos Wastes), the game crashes with:

```
Unit not found #ID[...]
Assertion failed `world.resource_manager().can_get(unit_type, unit_name)`
  at c_api_world.cpp:67 in stingray::plugin_api::world::spawn_unit
```

## Root Cause

The game's package loading pipeline and weapon_tweaker's backend hooks are out of sync:

1. **`ProfileSynchronizer.profile_packages()`** determines which resource packages to load by calling `BackendUtils.get_loadout_item()` for each inventory slot, then `WeaponUtils.get_weapon_packages()` to get the unit bundle paths.

2. **weapon_tweaker's backend hooks** intercept `get_loadout` / `get_loadout_item_id` to inject cross-career weapons from `loadout_cache`. But the hooks are installed lazily in `mod.update()` (waits for `Managers.backend`), so they may not be in place when `profile_packages` first runs.

3. **`set_loadout_item` is swallowed** — cross-career items are stored only in `loadout_cache` without calling the original function, so the real backend never persists them. After game restart, the cache is empty and packages are built from the native loadout only.

4. **Chaos Wastes compounds this** — each CW node triggers a level transition that rebuilds package lists from scratch. If the hook timing is even slightly off on one transition, packages are missing and spawn crashes.

Result: the weapon's 1P/3P unit bundles aren't in the resource manager when `GearUtils.create_equipment` → `World.spawn_unit` fires.

## Key Source References

- `ProfileSynchronizer.profile_packages()` — `Vermintide-2-Source-Code/scripts/game_state/components/profile_synchronizer.lua:71`
- `_add_slot_item_packages()` — same file `:38` — calls `BackendUtils.get_item_units` and `WeaponUtils.get_weapon_packages`
- `build_inventory_lists()` — same file `:163`
- `update_inventory_data()` — same file `:191` — called on profile/loadout changes, encodes packages for network sync
- `NetworkLookup.inventory_packages` — `scripts/network_lookup/network_lookup.lua:2315` — LUT used to encode packages over network; cross-career packages must be present here too
- `deus_chest_preload_system` — `scripts/entity_system/systems/deus_chest/deus_chest_preload_system.lua` — CW-specific preload for weapons acquired mid-run
- weapon_tweaker backend hooks — `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_backend.lua:72-143`

## Fix Strategy

### Option A: Hook `profile_packages` to inject cross-career weapon packages (Recommended)

Hook `BackendUtils.get_loadout_item` (or the higher-level `profile_packages` via a `ProfileSynchronizer` hook) so that when the game builds the package list, it sees the cross-career weapon and loads its bundles.

**Steps:**

1. **Persist `loadout_cache` to mod settings** so it survives game restarts. On `mod.on_all_mods_loaded`, restore from settings. On cache write, save to settings.

2. **Hook `BackendUtils.get_loadout_item`** (table-form hook, guarded) to return the cached cross-career item when queried for a career+slot that has an override. This is the single function `profile_packages` calls per slot — if this returns the cross-career item, the rest of the pipeline (`get_item_units` → `get_weapon_packages`) resolves the correct packages automatically.

3. **Install hooks early** — move backend hook installation from `mod.update()` to `mod.on_all_mods_loaded` with a retry in `mod.update()` as fallback. The hooks need to be in place before the first `profile_packages` call.

4. **Validate `NetworkLookup.inventory_packages`** — cross-career weapon packages must exist in this LUT or the network encoding will assert. Log a warning and skip the weapon (fall back to native loadout) if the package isn't in the lookup, rather than crashing.

### Option B: Force-load packages via `Managers.package` before spawn

Hook `GearUtils.create_equipment` (already hooked in `weapon_tweaker.lua:1027`) and, before calling the original, check if the weapon's unit packages are loaded. If not, synchronously load them via `Managers.package:load()`.

**Pros:** Simpler, doesn't need to touch the ProfileSynchronizer pipeline.
**Cons:** Synchronous package loading mid-spawn could cause a hitch/stutter. Packages loaded this way may not be tracked by ProfileSynchronizer's reference counting, risking premature unload. Also doesn't fix the NetworkLookup issue for multiplayer.

### Option C: Hybrid — early hook + safety net

Use Option A for the correct fix, plus add a `can_get` guard in the `GearUtils.create_equipment` hook as a safety net:

```lua
-- In the existing create_equipment hook, before calling func():
local item_units = BackendUtils.get_item_units(item_data, nil, nil, career_name)
if item_units and item_units.right_unit_3p then
    local rm = Application.resource_manager and Application.resource_manager()
    -- If resource isn't available, log warning and skip the cross-career override
    -- (let the native weapon spawn instead)
end
```

This prevents the hard crash even if the package fix has a gap.

## Recommended Implementation Order

1. **Persist loadout_cache** — save/restore via `mod:set`/`mod:get` on a serialized key. Small change, immediate impact on the restart-loses-loadout problem.

2. **Hook `BackendUtils.get_loadout_item`** — table-form hook that checks `loadout_cache` before delegating. Must be installed before first `profile_packages` call.

3. **Move hook installation to `on_all_mods_loaded`** — ensures hooks are in place before the game's first inventory package scan.

4. **Add `create_equipment` safety net** — pcall or `can_get` check before spawn, with fallback to native weapon. Prevents crash if anything else slips through.

5. **Test in Chaos Wastes** — equip cross-career weapon, complete multiple CW nodes, restart game mid-run and rejoin.

## Risk Notes

- Hooking `BackendUtils.get_loadout_item` is a table-form hook (not string-form). Must guard with nil check per CLAUDE.md hooking rules.
- `NetworkLookup.inventory_packages` is a fixed array built at boot. If a cross-career weapon's package isn't in this list, network sync will assert. May need to append to the lookup at mod init — verify this doesn't break hash consistency for multiplayer.
- The `set_loadout_item` swallow (not calling original) is intentional to avoid the backend rejecting a weapon the career can't natively wield. This must stay, but the package pipeline needs an alternative path to learn about the equipped weapon.
