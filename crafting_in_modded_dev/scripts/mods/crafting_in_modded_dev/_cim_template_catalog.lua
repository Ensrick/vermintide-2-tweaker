-- Pure builder for standard-forge acquisition selectors.
--
-- The UI row is deliberately not an owned backend item. It retains an exact
-- reference to the registered ItemMasterList definition so icons, models,
-- skin families, and future metadata remain owned by the weapon provider.
-- Kept engine-free for exhaustive catalog regression coverage.

local M = {}

local function _contains(values, wanted)
    if type(values) ~= "table" then return false end
    for _, value in ipairs(values) do
        if value == wanted then return true end
    end
    return false
end

local function _is_cwv_definition(key, data)
    return data.cwv_definition == true
        or type(data.cwv_key) == "string"
        or (type(key) == "string" and key:sub(1, 4) == "cwv_" and data.cwv_variant == true)
end

-- The native Craft Item picker selects a weapon FAMILY, not an ItemMasterList
-- row. Vanilla carries helper/preview/Versus aliases beside the real weapon
-- row (for example `es_bastard_sword_preview`), all sharing one item_type.
-- Exact-key enumeration therefore renders the same weapon more than once.
-- CWV definitions are the exception: each authored cwv_key is a genuine
-- craftable variant even when two variants deliberately share an item_type.
function M.craft_family(key, data)
    if type(data) ~= "table" then return nil end
    if type(data.cim_craft_family) == "string" and data.cim_craft_family ~= "" then
        return "provider:" .. data.cim_craft_family
    end
    if _is_cwv_definition(key, data) then
        return "cwv:" .. tostring(data.cwv_key or key)
    end
    if type(data.item_type) == "string" and data.item_type ~= "" then
        return "item_type:" .. tostring(data.slot_type or "?") .. ":" .. data.item_type
    end
    return type(key) == "string" and ("key:" .. key) or nil
end

local function _candidate_score(key, data)
    local score = 0
    if key == data.item_type then score = score + 100 end
    if key == data.name then score = score + 40 end
    if data.is_local ~= true then score = score + 20 end
    if not (type(key) == "string" and key:find("_preview$")) then score = score + 10 end
    if data.mechanisms == nil then score = score + 5 end
    return score
end

local function _candidate_wins(next_candidate, current)
    if not current then return true end
    if next_candidate.score ~= current.score then
        return next_candidate.score > current.score
    end
    return next_candidate.key < current.key
end

function M.build(args)
    args = args or {}
    local item_master_list = args.item_master_list
    local career_name = args.career_name
    local craftable_slot_types = args.craftable_slot_types or {}
    local base_power = tonumber(args.base_power) or 5
    local requires_unowned_dlc = args.requires_unowned_dlc or function() return false end
    local versus_shadowed = args.versus_shadowed or function() return false end
    local real_names = args.real_names
    local cache = {}
    local report = { total = 0, cwv = 0, eligible = 0, suppressed = 0, collisions = {} }

    if type(item_master_list) ~= "table" or type(career_name) ~= "string" then
        return cache, report
    end

    local representatives = {}
    local candidates = {}
    for key, data in pairs(item_master_list) do
        if type(data) == "table"
            and data.slot_type and craftable_slot_types[data.slot_type]
            and _contains(data.can_wield, career_name)
            and data.item_type ~= "weapon_skin"
            and data.rarity ~= "magic" and data.rarity ~= "promo"
            and not requires_unowned_dlc(key)
            and not versus_shadowed(data, real_names) then
            local family = M.craft_family(key, data)
            local candidate = {
                key = key,
                data = data,
                family = family,
                score = _candidate_score(key, data),
            }
            report.eligible = report.eligible + 1
            candidates[#candidates + 1] = candidate
            local current = family and representatives[family]
            if family and _candidate_wins(candidate, current) then
                representatives[family] = candidate
            end
        end
    end

    for i = 1, #candidates do
        local candidate = candidates[i]
        local kept = representatives[candidate.family]
        if kept ~= candidate then
            report.suppressed = report.suppressed + 1
            report.collisions[#report.collisions + 1] = {
                family = candidate.family,
                kept = kept and kept.key or "<none>",
                dropped = candidate.key,
            }
        end
    end
    table.sort(report.collisions, function(a, b)
        if a.family ~= b.family then return tostring(a.family) < tostring(b.family) end
        return tostring(a.dropped) < tostring(b.dropped)
    end)

    local ordered = {}
    for _, candidate in pairs(representatives) do ordered[#ordered + 1] = candidate end
    table.sort(ordered, function(a, b)
        if a.family ~= b.family then return a.family < b.family end
        return a.key < b.key
    end)

    for i = 1, #ordered do
        local candidate = ordered[i]
        local key = candidate.key
        local data = candidate.data
        local bid = "cim_template_" .. key
        cache[bid] = {
                backend_id = bid,
                cim_acquisition_template = true,
                cim_acquisition_key = key,
                cim_acquisition_family = candidate.family,
                key = key,
                ItemId = key,
                ItemInstanceId = bid,
                rarity = "default",
                data = data,
                properties = {},
                traits = {},
                power_level = base_power,
                CustomData = {
                    power_level = tostring(base_power),
                    rarity = "default",
                    properties = "{}",
                    traits = "[]",
                },
        }
        report.total = report.total + 1
        if _is_cwv_definition(key, data) then report.cwv = report.cwv + 1 end
    end

    return cache, report
end

return M
