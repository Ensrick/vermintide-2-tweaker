-- Pure policy for Weapon Tweaker's active Ensrick tweak-family master (#445).
-- No engine globals: exercised by qa/lua/tests/test_wt_rework_master_policy.lua.

local M = {}

M.MASTER_ID = "wt_rework_master_ensrick"
M.LABEL_PREFIX = "[Ensrick]"

-- The retired Big Rebalance br_* catalog is deliberately absent. This is the
-- complete visible Weapon Tweaks family owned by the current mod.
M.LEAF_IDS = {
    "authentic_brace_of_pistols",
    "moonfire_aoe_revert",
    "wt_bolt_staff_primary_overcharge_reduction",
    "wt_brett_sword_shield_buff",
    "wt_cog_hammer_heavy_speed_nerf",
    "wt_dual_axes_cleave",
    "wt_dual_axes_light_crit",
    "wt_executioner_light_headshot_bonus",
    "wt_greataxe_light_crit",
    "wt_mace_sword_speed_nerf",
    "wt_one_hand_axe_cleave_nerf",
    "wt_priest_punch_buff",
    "wt_revert_1h_sword_push_combo",
}

local MEMBERS = {}
for i = 1, #M.LEAF_IDS do MEMBERS[M.LEAF_IDS[i]] = true end

function M.is_member(setting_id)
    return MEMBERS[setting_id] == true
end

function M.decorate_label(setting_id, text)
    if not M.is_member(setting_id) or type(text) ~= "string" then return text end
    text = text:gsub("^%[Ensrick%]%s+", "")
    return M.LABEL_PREFIX .. " " .. text
end

local function value(current, id)
    return current[id] and true or false
end

-- Return only changed writes so a click remains one bounded transaction.
function M.plan(enabled, current)
    current = current or {}
    local desired = enabled and true or false
    local changes = {}
    for i = 1, #M.LEAF_IDS do
        local id = M.LEAF_IDS[i]
        if value(current, id) ~= desired then
            changes[#changes + 1] = { id = id, value = desired }
        end
    end
    if value(current, M.MASTER_ID) ~= desired then
        changes[#changes + 1] = { id = M.MASTER_ID, value = desired }
    end
    table.sort(changes, function(a, b) return a.id < b.id end)
    return changes
end

-- The master indicator is on only when every member is on. A partial/custom
-- selection intentionally displays it as off without changing any leaf.
function M.derive_master(current)
    current = current or {}
    for i = 1, #M.LEAF_IDS do
        if not value(current, M.LEAF_IDS[i]) then return false end
    end
    return #M.LEAF_IDS > 0
end

return M
