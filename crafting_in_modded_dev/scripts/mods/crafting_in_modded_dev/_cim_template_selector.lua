-- Pure acquisition-selector policy for the standard Craft Item grid.
-- Engine-free so the CIM/CWV ownership boundary can be exercised under Lua 5.1.

local M = {}

-- issue 628: canonical item identity is owned by `_cim_synthetic_item_contract`
-- so the standard-forge acquisition selector and the salvage eligibility filter
-- classify a synthetic item the same way. standard_forge injects the contract's
-- resolver at load; the inline body in `canonical_key` is the exact same policy,
-- kept as the fallback so this module stays pure and standalone-loadable for the
-- unit tests.
local _canonical_key_resolver = nil
local _craft_picker_role_resolver = nil
function M.set_canonical_key_resolver(fn)
    _canonical_key_resolver = type(fn) == "function" and fn or nil
end

function M.set_identity_contract(contract)
    contract = type(contract) == "table" and contract or nil
    _canonical_key_resolver = contract
        and type(contract.canonical_item_key) == "function"
        and contract.canonical_item_key or nil
    _craft_picker_role_resolver = contract
        and type(contract.craft_picker_role) == "function"
        and contract.craft_picker_role or nil
end

local function _rarity(item)
    if type(item) ~= "table" then return nil end
    return item.rarity
        or (type(item.CustomData) == "table" and item.CustomData.rarity)
        or (type(item.mod_data) == "table" and item.mod_data.rarity)
end

local function _power(item)
    if type(item) ~= "table" then return nil end
    local custom = type(item.CustomData) == "table" and item.CustomData or nil
    return tonumber(item.power_level or (custom and custom.power_level))
end

local function _is_craftable_row(item)
    local data = type(item) == "table" and type(item.data) == "table" and item.data or nil
    local slot_type = data and data.slot_type or (type(item) == "table" and item.slot_type)
    return slot_type == "melee" or slot_type == "ranged"
        or slot_type == "ring" or slot_type == "necklace" or slot_type == "trinket"
end

local function _craft_picker_role(item)
    if _craft_picker_role_resolver then return _craft_picker_role_resolver(item) end
    if not _is_craftable_row(item) then return "other" end
    local rarity = _rarity(item)
    return (rarity == nil or rarity == "default") and "selector" or "instance"
end

function M.canonical_key(item)
    if type(item) ~= "table" then return nil end
    -- When the contract resolver is injected (runtime), it is the single owner
    -- of synthetic identity; both this selector and salvage read through it.
    if _canonical_key_resolver then return _canonical_key_resolver(item) end

    -- New selectors carry an exact acquisition key. CWV definitions also
    -- carry cwv_key because their inherited .key/.name must remain the base
    -- weapon for vanilla preview/equip fallbacks.
    if type(item.cim_acquisition_key) == "string" then
        return item.cim_acquisition_key
    end
    local data = type(item.data) == "table" and item.data or nil
    if data and type(data.cwv_key) == "string" then
        return data.cwv_key
    end

    -- Compatibility with historical CWV blacksmith rows, whose inherited key
    -- named the base weapon but whose backend id retained the exact variant.
    local backend_id = item.backend_id or item.ItemInstanceId
    if type(backend_id) == "string" then
        local cwv_key = backend_id:match("^(cwv_.-)_%d%d%d$")
        if cwv_key then return cwv_key end
    end

    local key = item.key or (data and data.key) or item.ItemId
    return type(key) == "string" and key or nil
end

function M.canonical_family(item)
    if type(item) ~= "table" then return nil end
    if type(item.cim_acquisition_family) == "string" then
        return item.cim_acquisition_family
    end
    local data = type(item.data) == "table" and item.data or nil
    local key = M.canonical_key(item)
    if data and (data.cwv_definition == true or type(data.cwv_key) == "string") then
        return "cwv:" .. tostring(data.cwv_key or key)
    end
    if type(key) == "string" and key:sub(1, 4) == "cwv_" then
        return "cwv:" .. key
    end
    if data and type(data.cim_craft_family) == "string" then
        return "provider:" .. data.cim_craft_family
    end
    if data and (data.slot_type == "necklace" or data.slot_type == "ring"
        or data.slot_type == "trinket") then
        return "accessory:" .. tostring(data.slot_type) .. ":" .. tostring(key)
    end
    if data and type(data.item_type) == "string" then
        return "item_type:" .. tostring(data.slot_type or "?") .. ":" .. data.item_type
    end
    return key and ("key:" .. key) or nil
end

function M.inject(items, templates)
    if type(items) ~= "table" or type(templates) ~= "table" then return items end

    -- A real default-rarity row wins over CIM's synthetic selector. Modded
    -- crafted instances never count: vanilla can_craft_with excludes them,
    -- and this guard preserves the contract even if an upstream filter leaks.
    local real_families = {}
    for _, item in ipairs(items) do
        if not item.cim_acquisition_template and _craft_picker_role(item) == "selector" then
            local family = M.canonical_family(item)
            if family then
                local current = real_families[family]
                -- Legacy sessions can contain several real default CWV rows.
                -- Prefer the canonical 5-power Blacksmith row deterministically.
                if not current or (_power(item) == 5 and _power(current) ~= 5) then
                    real_families[family] = item
                end
            end
        end
    end

    -- Compact any stale/repeated synthetic rows in place. This makes injection
    -- idempotent even if a caller reuses the same filtered array.
    local synthetic_families = {}
    local write = 0
    for i = 1, #items do
        local item = items[i]
        local keep = true
        local role = item and _craft_picker_role(item) or "invalid"
        if role == "instance" then
            -- This module is called only for vanilla `can_craft_with`. Crafted
            -- items belong in inventory/salvage and can never be acquisition
            -- selectors, even if an upstream backend hook leaked one here.
            keep = false
        elseif item and item.cim_acquisition_template then
            local family = M.canonical_family(item)
            if not family or real_families[family] or synthetic_families[family] then
                keep = false
            else
                synthetic_families[family] = true
            end
        elseif item and role == "selector" and _is_craftable_row(item) then
            local family = M.canonical_family(item)
            -- Collapse repeated real/default weapon selectors too. Older code
            -- only bounded CIM's synthetic rows, allowing persisted/legacy CWV
            -- Blacksmith instances to appear beside each other indefinitely.
            if family and real_families[family] ~= item then
                keep = false
            end
        end
        if keep then
            write = write + 1
            items[write] = item
        end
    end
    for i = write + 1, #items do items[i] = nil end

    local pending = {}
    for _, template in pairs(templates) do
        local key = M.canonical_key(template)
        local family = M.canonical_family(template)
        if key and family and not real_families[family] and not synthetic_families[family] then
            pending[#pending + 1] = { key = key, family = family, template = template }
            synthetic_families[family] = true
        end
    end
    table.sort(pending, function(a, b)
        if a.family ~= b.family then return a.family < b.family end
        return a.key < b.key
    end)
    for i = 1, #pending do
        items[#items + 1] = pending[i].template
    end
    return items
end

return M
