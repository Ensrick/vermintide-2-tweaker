-- Pure appearance ownership for CWV families that reuse vanilla cosmetic
-- sources.  The render, persistence, and peer-sync paths remain owned by
-- Cosmetics' canonical exact-hand systems; this module only declares which
-- surface owns the icon and where each independently selectable hand comes
-- from.

local M = {}

M.families = {
    cwv_dr_dawi_mace = {
        item_type = "cwv_dr_dawi_mace",
        skin_table = "cwv_dr_dawi_mace_skins",
        icon_owner = "right_hand_unit",
        primary_source = "dr_1h_hammer",
    },
    cwv_dr_dawi_dual_maces = {
        item_type = "cwv_dr_dawi_dual_maces",
        skin_table = "cwv_dr_dawi_dual_maces_skins",
        icon_owner = "right_hand_unit",
        primary_source = "dr_1h_hammer",
        independent_hands = {
            right_hand_unit = {
                matching_item_key = "dr_1h_hammer",
                unit_field = "right_hand_unit",
            },
            left_hand_unit = {
                matching_item_key = "dr_1h_hammer",
                unit_field = "right_hand_unit",
            },
        },
    },
    cwv_dr_dawi_mace_shield = {
        item_type = "cwv_dr_dawi_mace_shield",
        skin_table = "cwv_dr_dawi_mace_shield_skins",
        icon_owner = "left_hand_unit",
        primary_source = "dr_1h_hammer",
        shield_pool_source = "dr_1h_axe_shield",
    },
}

function M.get(item_type)
    return M.families[item_type]
end

function M.icon_ownership(item_type)
    local family = M.get(item_type)
    if not family then return nil end
    return family.icon_owner == "left_hand_unit" and "shield" or "primary"
end

function M.dual_sources()
    local out = {}
    for item_type, family in pairs(M.families) do
        if family.independent_hands then
            out[item_type] = family.independent_hands
        end
    end
    return out
end

function M.shield_pool_source(item_type)
    local family = M.get(item_type)
    return family and family.shield_pool_source or nil
end

return M
