local M = {}

local function _is_javelin_id(value)
    if type(value) ~= "string" then return false end
    if value == "cwv_es_javelin" or value == "cwv_wh_javelin"
            or value == "cwv_grenade_tuskgor_javelin" then
        return true
    end

    -- Backend ids and the generated default skins append a suffix to the
    -- concrete item key. Do not catch the retired/future javelin+shield family:
    -- that is a different weapon and must earn its own wire contract.
    local es_suffix = value:match("^cwv_es_javelin_(.+)$")
    if es_suffix and es_suffix:sub(1, 6) ~= "shield" then return true end
    local wh_suffix = value:match("^cwv_wh_javelin_(.+)$")
    if wh_suffix and wh_suffix:sub(1, 6) ~= "shield" then return true end
    return false
end

local function _candidate_is_javelin(value)
    return _is_javelin_id(value)
end

-- Accept the three shapes used by the live inventory paths: a backend item,
-- its `.data`/`.master_item` wrapper, or a SimpleInventory slot_data row.
-- The inherited vanilla name (`we_javelin`) is deliberately not evidence.
function M.is_cwv_javelin(item)
    if _candidate_is_javelin(item) then return true end
    if type(item) ~= "table" then return false end

    local data = item.item_data or item.data or item.master_item or item
    local mod_data = type(data) == "table" and data.mod_data or nil
    local candidates = {
        item.backend_id, item.ItemId, item.ItemInstanceId, item.skin,
        type(data) == "table" and data.backend_id or nil,
        type(data) == "table" and data.ItemId or nil,
        type(data) == "table" and data.ItemInstanceId or nil,
        type(data) == "table" and data.key or nil,
        type(data) == "table" and data.skin or nil,
        type(mod_data) == "table" and mod_data.backend_id or nil,
    }
    -- The candidate array is intentionally sparse for most wrapper shapes;
    -- `#candidates` is undefined across holes in Lua 5.1, so iterate present
    -- values rather than truncating at the first absent field.
    for _, candidate in pairs(candidates) do
        if _candidate_is_javelin(candidate) then return true end
    end
    return false
end

function M.feature_enabled(applied_state)
    return applied_state == "enabled"
end

function M.should_block(item, applied_state)
    return M.is_cwv_javelin(item) and not M.feature_enabled(applied_state)
end

-- Return the original table when no row is removed. Several callers cache the
-- backend result by identity, so needless copies would be observable churn.
function M.filter_unavailable(items, applied_state)
    if type(items) ~= "table" or M.feature_enabled(applied_state) then
        return items, 0
    end
    local filtered, removed = {}, 0
    for index = 1, #items do
        local item = items[index]
        if M.is_cwv_javelin(item) then
            removed = removed + 1
        else
            filtered[#filtered + 1] = item
        end
    end
    if removed == 0 then return items, 0 end
    return filtered, removed
end

-- Temporarily replace a custom transient-package reference with a registered
-- vanilla reference while a hot-join packet is encoded. The returned closure
-- restores the table byte-for-byte, including an absent fallback entry. This
-- helper is engine-free so the mutation and rollback contract can be tested
-- outside Vermintide.
function M.begin_ref_shadow(refs, custom_key, safe_key, safe_registered)
    if type(refs) ~= "table" or type(custom_key) ~= "string" then
        return function() end, false
    end

    local old_custom = rawget(refs, custom_key)
    local old_safe = type(safe_key) == "string" and rawget(refs, safe_key) or nil
    if old_custom == nil then return function() end, false end

    refs[custom_key] = nil
    if safe_registered and type(safe_key) == "string" then
        refs[safe_key] = (old_safe or 0) + old_custom
    end

    local restored = false
    return function()
        if restored then return end
        restored = true
        refs[custom_key] = old_custom
        if safe_registered and type(safe_key) == "string" then
            refs[safe_key] = old_safe
        end
    end, true
end

return M
