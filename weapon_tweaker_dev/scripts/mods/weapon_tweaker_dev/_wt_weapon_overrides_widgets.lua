-- _wt_weapon_overrides_widgets.lua - Pure Weapon Tweaks descriptor factory.
--
-- Owns fresh literal descriptors, built at the original data-array position.
-- No dependencies, settings reads or gameplay installers are introduced.
-- Repeated calls never share mutable VMF widget or options tables.
--
-- Owned by: the stream's _data.lua. Consumed via: mod:dofile(...).build().
local M = {}

function M.build()
    return {
        setting_id = "weapon_overrides",
        type = "group",
        -- Leaves sorted A->Z by display label (repo standing sort rule).
        sub_widgets = {
            {
                setting_id = "wt_rework_master_group",
                type = "group",
                sub_widgets = {
                    { setting_id = "wt_rework_master_ensrick", type = "checkbox", default_value = false },
                },
            },
            { setting_id = "authentic_brace_of_pistols", type = "checkbox", default_value = false },
            { setting_id = "wt_one_hand_axe_cleave_nerf", type = "checkbox", default_value = false },
            { setting_id = "wt_cog_hammer_heavy_speed_nerf", type = "checkbox", default_value = false },
            { setting_id = "wt_dual_axes_cleave", type = "checkbox", default_value = true },
            { setting_id = "wt_dual_axes_light_crit", type = "checkbox", default_value = true },
            { setting_id = "wt_executioner_light_headshot_bonus", type = "checkbox", default_value = false },
            -- #942: absolute heat, direct damage only; settings stay editable on mismatch.
            { setting_id = "wt_fire_sword_heat", type = "checkbox", default_value = false,
                sub_widgets = {
                    { setting_id = "wt_fire_sword_heat_armor", type = "checkbox", default_value = false },
                    { setting_id = "wt_fire_sword_heat_cleave_percent", type = "numeric", default_value = 2, range = { 0, 10 }, decimals_number = 2 },
                    { setting_id = "wt_fire_sword_heat_damage_percent", type = "numeric", default_value = 1, range = { 0, 10 }, decimals_number = 2 },
                    { setting_id = "wt_fire_sword_heat_armor_threshold", type = "numeric", default_value = 25, range = { 0, 100 }, decimals_number = 1 },
                },
            },
            -- Issue #943: independent Fire Sword heavy projections (both default off).
            { setting_id = "wt_fire_sword_nova_slowdown", type = "checkbox", default_value = false },
            { setting_id = "wt_fire_sword_sweep_opener", type = "checkbox", default_value = false },
            { setting_id = "wt_greataxe_light_crit", type = "checkbox", default_value = true },
            { setting_id = "wt_mace_sword_speed_nerf", type = "checkbox", default_value = false },
            { setting_id = "wt_bolt_staff_primary_overcharge_reduction", type = "checkbox", default_value = false },
            -- Explicit tooltip: the loc key ends in _tooltip, which VMF does NOT
            -- auto-resolve (auto path only tries <setting_id>_description).
            { setting_id = "wt_brett_sword_shield_buff", type = "checkbox", default_value = false, tooltip = "wt_brett_sword_shield_buff_tooltip" },
            -- Issue #348: revert 6.11.0 Kruber Empire 1h sword push-attack combo.
            -- Uses the auto-resolved <setting_id>_description loc key for its tooltip.
            { setting_id = "wt_revert_1h_sword_push_combo", type = "checkbox", default_value = false },
            { setting_id = "moonfire_aoe_revert", type = "checkbox", default_value = false },
            { setting_id = "wt_priest_punch_buff", type = "checkbox", default_value = false },
        },
    }
end

return M
