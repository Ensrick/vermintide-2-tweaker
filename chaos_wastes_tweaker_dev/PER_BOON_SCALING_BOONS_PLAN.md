# Per-Boon Scaling Boons — Implementation Plan

A new family of CW boons modeled on the existing `boon_meta_01` (+1% damage and +1% attack speed per boon). Each new boon scales a different stat per total boon count.

## Proposed Boons

| Internal name        | Effect (per boon)                          | stat_buff(s)                                          | Multiplier(s)   |
|----------------------|---------------------------------------------|--------------------------------------------------------|------------------|
| `ct_meta_stagger`    | +1% stagger power, +1% cleave               | `power_level_impact`, `power_level_melee_cleave`       | 0.01, 0.01       |
| `ct_meta_crit`       | +1% crit chance, +5% crit power             | `critical_strike_chance`, `critical_strike_effectiveness` | 0.01, 0.05    |
| `ct_meta_health`     | +1% health, +1% healing/THP gain            | `max_health`, `healing_received`                       | 0.01, 0.01       |
| `ct_meta_cooldown`   | +2% cooldown reduction                       | `cooldown_regen`                                       | 0.02             |

Internal names use `ct_` prefix to avoid collisions with vanilla `boon_meta_*` slots and to make removal/triage trivial.

## Reference: How `boon_meta_01` Works

The existing per-boon scaling boon is a drop-in blueprint. Three pieces wire it together:

### 1. Power-up definition

`scripts/settings/dlcs/morris/deus_power_up_settings.lua:4877`

```lua
boon_meta_01 = {
    advanced_description = "description_boon_meta_01",
    display_name = "display_name_boon_meta_01",
    icon = "deus_icon_meta_01",
    max_amount = 1,
    rectangular_icon = true,
    buff_template = {
        buffs = {
            {
                apply_buff_func = "boon_meta_01_apply",
                buff_func = "boon_meta_01_boon_granted",
                event = "on_boon_granted",
                name = "boon_meta_01",
            },
        },
    },
    description_values = {
        { value_type = "percent", value = MorrisBuffTweakData.boon_meta_01_data.damage_multiplier_per_stack },
        { value_type = "percent", value = MorrisBuffTweakData.boon_meta_01_data.attack_speed_multiplier_per_stack },
    },
},
```

### 2. Stack buff (the actual stat container)

`scripts/settings/dlcs/morris/morris_buff_settings.lua:7243`

```lua
boon_meta_01_stack = {
    buffs = {
        {
            name = "boon_meta_01_stack",
            stat_buff = "damage_dealt",
            multiplier = MorrisBuffTweakData.boon_meta_01_data.damage_multiplier_per_stack,
            max_stacks = math.huge,
        },
        {
            name = "boon_meta_01_stack_atk_speed",
            stat_buff = "attack_speed",
            multiplier = MorrisBuffTweakData.boon_meta_01_data.attack_speed_multiplier_per_stack,
            max_stacks = math.huge,
        },
    },
},
```

### 3. Apply/reconcile functions

`scripts/settings/dlcs/morris/morris_buff_settings.lua:2024` (initial apply when boon is acquired)

```lua
boon_meta_01_apply = function (unit, buff, params)
    local player = Managers.player:owner(unit)
    if not player then return end
    local buff_extension = ScriptUnit.extension(unit, "buff_system")
    local deus_run_controller = Managers.mechanism:game_mechanism():get_deus_run_controller()
    local num_boons = #deus_run_controller:get_player_power_ups(player:network_id(), player:local_player_id())
    for i = 1, num_boons do
        buff_extension:add_buff("boon_meta_01_stack")
    end
end,
```

`scripts/settings/dlcs/morris/morris_buff_settings.lua:4929` (reconcile on every subsequent boon grant)

```lua
boon_meta_01_boon_granted = function (unit, buff, params)
    local player = Managers.player:owner(unit)
    if not player then return end
    local buff_extension = ScriptUnit.extension(unit, "buff_system")
    local num_existing_stacks = buff_extension:num_buff_stacks("boon_meta_01_stack")
    local deus_run_controller = Managers.mechanism:game_mechanism():get_deus_run_controller()
    local num_boons = #deus_run_controller:get_player_power_ups(player:network_id(), player:local_player_id())
    for i = num_existing_stacks + 1, num_boons do
        buff_extension:add_buff("boon_meta_01_stack")
    end
    local existing_stacks = buff_extension:get_stacking_buff("boon_meta_01_stack")
    for i = num_existing_stacks, num_boons + 1, -1 do
        buff_extension:remove_buff(existing_stacks[i].id)
    end
end,
```

## stat_buff Key Verification

All target stat_buffs are confirmed present in vanilla VT2 (grepped via `stat_buff = "<name>"` in `scripts/settings/dlcs/morris/`):

| stat_buff key                     | Used by (representative)                          | Notes                                                                 |
|------------------------------------|---------------------------------------------------|-----------------------------------------------------------------------|
| `damage_dealt`                     | `boon_meta_01_stack`                              | Outgoing damage                                                       |
| `attack_speed`                     | `boon_meta_01_stack_atk_speed`                    | Attack speed                                                          |
| `power_level_impact`               | several morris range/melee boons                  | Stagger power                                                         |
| `power_level_melee_cleave`         | morris melee boons                                | Cleave                                                                |
| `critical_strike_chance`           | morris crit boons                                 | Flat add to crit roll                                                 |
| `critical_strike_effectiveness`    | morris crit boons                                 | "Crit power" — bonus damage on crit                                   |
| `max_health`                       | morris health boons                               | Total HP                                                              |
| `healing_received`                 | `damage_utils.lua` `apply_buffs_to_value`         | Covers kits/draughts AND THP gained from talents (single pipe)        |
| `cooldown_regen`                   | `deus_cooldown_regen`, `boon_supportbomb_concentration_01` | Positive multiplier = regen faster (e.g. 0.02 = +2% effective)  |

## Where the Globals Live at Runtime

By the time a VMF mod loads, all of these are merged and reachable:

- `BuffTemplates` — populated via `DLCUtils.merge("buff_templates", BuffTemplates)` at `buff_templates.lua:9532`
- `BuffFunctionTemplates.functions` — populated via `DLCUtils.merge("buff_function_templates", BuffFunctionTemplates.functions)` at `buff_function_templates.lua:5568`
- `DeusPowerUpTemplates` — defined in morris's `deus_power_up_settings.lua`
- `DeusPowerUpsArray` and `DeusPowerUpsArrayByRarity` — already mutated by chaos_wastes_tweaker (`chaos_wastes_tweaker.lua:104`), confirming the access pattern works

## Implementation Steps

For each new boon, register five pieces:

1. **`BuffTemplates.<name>_stack`** — the stat-stacking buff (one or two `stat_buff` siblings depending on whether the boon scales 1 or 2 stats), `max_stacks = math.huge`.
2. **`BuffFunctionTemplates.functions.<name>_apply`** — initial-apply function; counts current power_ups and adds N stacks.
3. **`BuffFunctionTemplates.functions.<name>_boon_granted`** — reconciler; runs on every subsequent boon grant.
4. **`DeusPowerUpTemplates.<name>`** — the boon definition (display_name, advanced_description, icon, max_amount = 1, buff_template wiring, description_values).
5. **Pool insertion** — append to `DeusPowerUpsArray` AND to the right rarity bucket in `DeusPowerUpsArrayByRarity[<rarity>]`.

Plus localization entries for `display_name_<name>` and `description_<name>` in `chaos_wastes_tweaker_localization.lua`.

## Open Questions (Need User Input)

1. **Rarity tier per boon** — common, rare, exotic, or unique? Affects shrine roll weights.
2. **Icons** — reuse `deus_icon_meta_01` for all four, or pick differentiated vanilla icons (e.g. `deus_icon_max_health`, `deus_icon_critical_chance`, `deus_icon_cooldown_reg_not_hit`)?
3. **Toggleability** — wire each into the existing `disable_boon_*` setting pattern so users can opt out individually?
4. **Per-mod prefix on internal names** — confirm `ct_meta_*` vs alternative naming.

## Risks / Caveats

- **`max_health` mid-run** — Adding `max_health` stacks during a CW run may not retroactively heal the player to their new ceiling; vanilla health buffs typically just raise the cap. Worth verifying in-game.
- **`cooldown_regen` semantics** — Vanilla uses positive multiplier to mean *faster regen*. 0.02 per boon stack should compound multiplicatively via the standard `apply_buffs_to_value` pipeline; verify the per-boon math doesn't run away at 30+ boons (60% reduction = effectively 2.5x cooldown regen rate, which may be over-strong for ult careers).
- **`healing_received` ambiguity** — Confirmed it covers THP-from-kill talents via `damage_utils.lua`, but worth a smoke test with Mercenary/Slayer THP-on-cleave to make sure the pipe is actually applied.
- **`max_amount = 1`** — Each scaling boon should be unique-per-player so the player can stack multiple *different* meta boons but not double up on one, matching `boon_meta_01`.

## Files That Will Change

- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` — boon registration logic
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_localization.lua` — display names + descriptions
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_data.lua` — (optional) toggle settings
