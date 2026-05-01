# Skeleton Hordes — Research & Plan

## Goal

Add skeleton horde presets so players can face hordes of:
1. **Necromancer skeletons** (Sienna's pet skeleton models) as hostile horde enemies
2. **Ethereal/ghost skeletons** (Sofia's ghost skeleton models) as hostile horde enemies

## Approach

Use `chaos_skeleton` as the base breed — it's a proven horde enemy with `behavior = "marauder"`, `unit_template = "ai_unit_skeleton"`, and full horde pipeline compatibility. Clone it with different `base_unit` paths (visual models) and `default_inventory_template` (weapons/armor).

We do NOT modify the original `pet_skeleton` or `ethereal_skeleton_*` breeds — those use `ai_unit_pet_skeleton` (commander-controlled) and `ai_unit_skeleton` (event-only) respectively, neither of which is a standard horde enemy.

## Breed Data

### Source breeds (visual donors)

| Breed | base_unit | inventory_template |
|-------|-----------|-------------------|
| `chaos_skeleton` | `units/beings/npcs/skeleton/chr_npc_skeleton` | `chaos_skeleton` |
| `pet_skeleton` | `units/beings/npcs/necromancer_skeleton/chr_npc_necromancer_skeleton` | `undead_npc_skeleton` |
| `pet_skeleton_armored` | (same necromancer model) | `undead_npc_skeleton_armored` |
| `pet_skeleton_dual_wield` | (same necromancer model) | `undead_npc_skeleton_dual_wield` |
| `pet_skeleton_with_shield` | (same necromancer model) | `undead_npc_skeleton_with_shield` |
| `ethereal_skeleton_with_hammer` | `units/beings/enemies/undead_ethereal_skeleton/chr_undead_ethereal_skeleton` | `undead_ethereal_skeleton_2h` |
| `ethereal_skeleton_with_shield` | (same ethereal model) | `undead_ethereal_skeleton_with_shield` |

### Cloned breeds (what we create)

All clones use `chaos_skeleton` as the base breed data (behavior, unit_template, stats), with only `base_unit` and `default_inventory_template` swapped.

| Clone Name | base_unit from | inventory_template | Notes |
|-----------|----------------|-------------------|-------|
| `et_necro_skeleton` | `pet_skeleton` | `undead_npc_skeleton` | Sword skeleton |
| `et_necro_skeleton_armored` | `pet_skeleton_armored` | `undead_npc_skeleton_armored` | 2H hammer + armor |
| `et_necro_skeleton_dual_wield` | `pet_skeleton_dual_wield` | `undead_npc_skeleton_dual_wield` | Dual swords |
| `et_necro_skeleton_shield` | `pet_skeleton_with_shield` | `undead_npc_skeleton_with_shield` | Sword + shield |
| `et_ghost_skeleton_hammer` | `ethereal_skeleton_with_hammer` | `undead_ethereal_skeleton_2h` | 2H hammer |
| `et_ghost_skeleton_shield` | `ethereal_skeleton_with_shield` | `undead_ethereal_skeleton_with_shield` | Sword + shield |

### Inventory anim_state_events (required for weapon draw)

| inventory_template | anim_state_event |
|-------------------|-----------------|
| `undead_npc_skeleton` | `to_sword` |
| `undead_npc_skeleton_armored` | `to_2h_hammer` |
| `undead_npc_skeleton_dual_wield` | `to_dual_wield` |
| `undead_npc_skeleton_with_shield` | `to_shield` |
| `undead_ethereal_skeleton_2h` | `to_2h_hammer` |
| `undead_ethereal_skeleton_with_shield` | `to_shield` |

## Package Loading

The `EnemyPackageLoader` loads packages by breed name: `resource_packages/breeds/<breed_name>`. Our cloned breeds (`et_necro_skeleton`, etc.) don't have their own packages — the models live in the source breed packages.

### Solution: Hook `EnemyPackageLoader._breed_package_name`

Redirect our custom breed names to the source breed's package:

```lua
-- Map cloned breed → source breed whose package contains the model
local PACKAGE_REDIRECT = {
    et_necro_skeleton            = "pet_skeleton",
    et_necro_skeleton_armored    = "pet_skeleton_armored",
    et_necro_skeleton_dual_wield = "pet_skeleton_dual_wield",
    et_necro_skeleton_shield     = "pet_skeleton_with_shield",
    et_ghost_skeleton_hammer     = "ethereal_skeleton_with_hammer",
    et_ghost_skeleton_shield     = "ethereal_skeleton_with_shield",
}

mod:hook("EnemyPackageLoader", "_breed_package_name", function(func, self, breed_name)
    local redirect = PACKAGE_REDIRECT[breed_name]
    if redirect then
        return func(self, redirect)
    end
    return func(self, breed_name)
end)
```

We also need to ensure our breeds are added to `EnemyPackageLoader._session_breed_map` so the packages actually get loaded. Hook `EnemyPackageLoader.request_breed` or inject into `_breeds_to_load_at_startup`.

## Data Still Needed (in-game verification)

1. **`et_dump_breeds`** — confirm `pet_skeleton`, `ethereal_skeleton_with_hammer` etc. are registered in `Breeds` at runtime (DLC-gated?)
2. **`table.create_copy` availability** — the game uses this in breed files; need to confirm it works for our cloning
3. **Animation compatibility** — does the necromancer skeleton model play `marauder` behavior animations correctly? The existing `chaos_skeleton` uses `marauder` with a different skeleton model. If the necromancer model has the same animation events (which is expected since they share the skeleton rig), it should work.
4. **Shield unit_template** — for shield-bearing clones, we may need `ai_unit_skeleton_with_shield` instead of `ai_unit_skeleton`

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Necromancer model missing marauder animations | Low | High | All skeletons share same rig; chaos_skeleton proves marauder works on skeleton |
| Package not loading (model not found) | Medium | Crash | Hook _breed_package_name to redirect |
| Inventory template not loaded | Low | Visual | Templates are in ai_inventory_templates.lua, loaded globally |
| DLC gate prevents breed data loading | Low | Medium | Check Breeds table at runtime, skip if missing |
| Shield clones need different unit_template | Medium | Broken shield | Use ai_unit_skeleton_with_shield for shield variants |
