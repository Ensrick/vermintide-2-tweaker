-- Engine-free resolver for the local wield career-action boundary.
-- Callers inject provider identity resolvers and engine registries. Unknown
-- providers are never guessed: unresolved ownership fails open to vanilla.
local M = {}

local function nested(value, field)
    return type(value) == "table" and value[field] or nil
end

function M.backend_id(slot_data)
    local item_data = nested(slot_data, "item_data")
    return nested(item_data, "backend_id")
        or nested(nested(item_data, "data"), "backend_id")
        or nested(slot_data, "id")
end

function M.direct_item_key(slot_data)
    local item_data = nested(slot_data, "item_data")
    local data = nested(item_data, "data")
    return nested(item_data, "key") or nested(data, "key")
        or nested(item_data, "ItemId") or nested(data, "ItemId")
end

function M.resolve(slot_data, career_name, env)
    env = env or {}
    local item_data = nested(slot_data, "item_data")
    if type(item_data) ~= "table" then return nil, "item_data_unavailable" end

    local backend_id = M.backend_id(slot_data)
    local item_key
    local identity_source
    for _, resolver in ipairs(env.identity_resolvers or {}) do
        local ok, candidate = pcall(resolver, backend_id, item_data)
        if ok and type(candidate) == "string"
                and type(env.item_master_list) == "table"
                and rawget(env.item_master_list, candidate) then
            item_key = candidate
            identity_source = "provider"
            break
        end
    end
    local direct_key = M.direct_item_key(slot_data)
    if not item_key and type(direct_key) == "string"
            and type(env.item_master_list) == "table"
            and rawget(env.item_master_list, direct_key) then
        item_key = direct_key
        identity_source = "direct"
    end
    if not item_key then return nil, "canonical_item_unresolved" end

    local item = rawget(env.item_master_list, item_key)
    if type(item) ~= "table" then return nil, "canonical_item_unavailable" end
    if type(career_name) ~= "string" or career_name == "" then
        return nil, "career_unavailable"
    end

    local template
    if type(env.get_item_template) == "function" then
        local ok, result = pcall(env.get_item_template, item_data, backend_id)
        if ok and type(result) == "table" then template = result end
    end
    if type(template) ~= "table" then
        return nil, "effective_template_unavailable"
    end

    return {
        backend_id = backend_id,
        item_data = item_data,
        item_key = item_key,
        identity_source = identity_source,
        item = item,
        career_name = career_name,
        template = template,
    }, "ok"
end

function M.is_managed(context, weapon_unlock_map)
    if type(context) ~= "table" then return false end
    if context.identity_source == "provider" then return true end
    if context.identity_source ~= "direct" or type(weapon_unlock_map) ~= "table" then
        return false
    end
    local career_weapons = weapon_unlock_map[context.career_name]
    if type(career_weapons) ~= "table" then return false end
    for _, item_key in ipairs(career_weapons) do
        if item_key == context.item_key then return true end
    end
    return false
end

return M
