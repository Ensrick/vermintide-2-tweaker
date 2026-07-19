-- _mp_diag_fresh_profile.lua - Read-only backend-topology census for issue #840.
--
-- The destructive fresh-
-- profile overlay remains disabled until every required consumer boundary is
-- proven. This module must stay pure: it never calls an interface method.
--
-- Owned by: modded_progression.lua. Consumed via: the entry-point dofile manifest.
local M = {}

M.PROFILE_INTERFACES = {
    { name = "items", slice = "inventory,loadouts,cosmetics", mirror_field = "_backend_mirror", methods = {
        "get_all_backend_items", "get_loadout", "get_item_from_id", "set_loadout_item" } },
    { name = "talents", slice = "talents", mirror_field = "_backend_mirror", methods = {
        "get_talents", "get_talent_tree", "set_talents" } },
    { name = "hero_attributes", slice = "experience,hero attributes", mirror_field = "_backend_mirror",
        methods = { "get", "set" } },
    { name = "peddler", slice = "currencies,store ownership", mirror_field = "_backend_mirror", methods = {
        "get_chips", "set_chips", "get_peddler_stock" } },
    -- Statistics is the one audited PlayFab interface that names this field
    -- `_mirror`; treating only `_backend_mirror` as canonical would hide it.
    { name = "statistics", slice = "progress,achievements", mirror_field = "_mirror",
        methods = { "get_stats", "save" } },
    { name = "quests", slice = "quests,reward claims", mirror_field = "_backend_mirror", methods = {
        "update_quests", "get_quests", "claim_quest_rewards" } },
    { name = "crafting", slice = "item mutation,unlocks", mirror_field = "_backend_mirror", methods = {
        "craft", "get_craft_result", "get_unlocked_weapon_skins", "get_unlocked_cosmetics" } },
    { name = "loot", slice = "containers,mission rewards,achievement rewards", mirror_field = "_backend_mirror",
        methods = { "open_loot_chest", "generate_end_of_level_loot", "claim_achievement_rewards",
            "get_highest_chest_level" } },
    { name = "keep_decorations", slice = "keep decoration ownership,loadout", mirror_field = "_backend_mirror",
        methods = { "get_decoration", "set_decoration", "get_unlocked_keep_decorations" } },
}

-- These manager methods bypass the loadout/talent/total-power override
-- registries and reach the canonical manager or mirror directly.
M.MANAGER_METHODS = {
    "get_interface", "get_read_only_data", "get_stats", "set_stats",
    "get_user_data", "set_user_data", "get_backend_mirror", "get_total_power_level",
}

local function _sorted_copy(values)
    local copy = {}
    for i, value in ipairs(values or {}) do copy[i] = value end
    table.sort(copy)
    return copy
end

function M.validate_catalog()
    local seen = {}
    for _, spec in ipairs(M.PROFILE_INTERFACES) do
        if type(spec.name) ~= "string" or spec.name == "" or seen[spec.name] then return false end
        if type(spec.slice) ~= "string" or spec.slice == "" or type(spec.mirror_field) ~= "string"
                or type(spec.methods) ~= "table" or #spec.methods == 0 then return false end
        seen[spec.name] = true
    end
    return #M.PROFILE_INTERFACES == 9 and #M.MANAGER_METHODS == 8
end

function M.audit(backend)
    local report = {
        rows = {},
        manager_missing = {},
        topology_complete = true,
        all_share_canonical = true,
    }
    local backend_is_table = type(backend) == "table"
    local interfaces = backend_is_table and rawget(backend, "_interfaces") or nil
    local canonical_mirror = backend_is_table and rawget(backend, "_backend_mirror") or nil
    report.canonical_mirror_present = canonical_mirror ~= nil

    for _, method in ipairs(M.MANAGER_METHODS) do
        if not backend_is_table or type(backend[method]) ~= "function" then
            report.manager_missing[#report.manager_missing + 1] = method
        end
    end
    if #report.manager_missing > 0 then report.topology_complete = false end

    for _, spec in ipairs(M.PROFILE_INTERFACES) do
        local interface = type(interfaces) == "table" and interfaces[spec.name] or nil
        local interface_is_table = type(interface) == "table"
        local row = {
            name = spec.name,
            slice = spec.slice,
            present = interface ~= nil,
            table_shape = interface_is_table,
            missing = {},
            same_mirror = nil,
        }
        if not interface_is_table then
            report.topology_complete = false
            report.all_share_canonical = false
        else
            for _, method in ipairs(spec.methods) do
                if type(interface[method]) ~= "function" then row.missing[#row.missing + 1] = method end
            end
            if #row.missing > 0 then report.topology_complete = false end
            local interface_mirror = rawget(interface, spec.mirror_field)
            row.same_mirror = canonical_mirror ~= nil and interface_mirror == canonical_mirror
            if not row.same_mirror then
                report.topology_complete = false
                report.all_share_canonical = false
            end
        end
        row.missing = _sorted_copy(row.missing)
        report.rows[#report.rows + 1] = row
    end

    if not report.canonical_mirror_present then
        report.topology_complete = false
        report.all_share_canonical = false
    end
    report.manager_missing = _sorted_copy(report.manager_missing)
    return report
end

function M.summary(report)
    local present, methods_missing, mirror_mismatch = 0, 0, 0
    for _, row in ipairs(report and report.rows or {}) do
        if row.present then present = present + 1 end
        methods_missing = methods_missing + #(row.missing or {})
        if row.same_mirror == false then mirror_mismatch = mirror_mismatch + 1 end
    end
    return {
        present = present,
        audited = #M.PROFILE_INTERFACES,
        methods_missing = methods_missing,
        manager_methods_missing = #(report and report.manager_missing or {}),
        mirror_mismatch = mirror_mismatch,
        topology_complete = report and report.topology_complete == true,
        all_share_canonical = report and report.all_share_canonical == true,
    }
end

return M
