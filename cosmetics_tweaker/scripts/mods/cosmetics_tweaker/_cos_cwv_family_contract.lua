-- Pure appearance ownership for CWV families that reuse vanilla cosmetic
-- sources.  The render, persistence, and peer-sync paths remain owned by
-- Cosmetics' canonical exact-hand systems; this module only declares which
-- surface owns the icon and where each independently selectable hand comes
-- from.

local M = {}

-- CWV skins sometimes keep a vanilla matching_item_key because the engine's
-- apply path requires a real vanilla template.  That compatibility key is not
-- presentation ownership.  The producer stamps this field on every generated
-- ItemMasterList skin so borrowed-family pickers can reject sibling CWV items
-- without breaking vanilla application.
M.SKIN_OWNER_FIELD = "cwv_owner_item_type"

function M.skin_source_allowed(entry, admitted_owners)
    if type(entry) ~= "table" then return false, "invalid-entry" end
    local owner = entry[M.SKIN_OWNER_FIELD]
    if owner == nil or owner == "" then return true, "vanilla-owner" end
    if type(admitted_owners) == "table" and admitted_owners[owner] == true then
        return true, "admitted-cwv-owner"
    end
    return false, "foreign-cwv-owner"
end

M.families = {
    cwv_es_imperial_crowbill = {
        item_type = "cwv_es_imperial_crowbill",
        skin_table = "cwv_es_imperial_crowbill_skins",
        icon_owner = "right_hand_unit",
        primary_source = "bw_1h_crowbill",
    },
    cwv_dr_dawi_crowbill = {
        item_type = "cwv_dr_dawi_crowbill",
        skin_table = "cwv_dr_dawi_crowbill_skins",
        icon_owner = "right_hand_unit",
        primary_source = "bw_1h_crowbill",
    },
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
