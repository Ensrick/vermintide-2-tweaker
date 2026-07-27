-- Pure target-qualified icon policy for Loremaster's Armoury offhand options.
-- LA owns icon assets and exact skin-to-icon mappings; Cosmetics only consumes
-- those mappings locally and never substitutes a sibling family's icon.

local M = {}

local function _nonempty(value)
    return type(value) == "string" and value ~= ""
end

function M.skin_item_type(skin_key, normalize)
    if not _nonempty(skin_key) then return nil end
    local item_type = string.match(skin_key, "^(.-)_skin_")
    if not item_type then return nil end
    return type(normalize) == "function" and normalize(item_type) or item_type
end

function M.new_target_option(fields, target_item_type)
    local option = {}
    for key, value in pairs(fields or {}) do option[key] = value end
    option.target_item_type = target_item_type
    -- A bridge option is a semantic LA choice, not an authored Cosmetics
    -- asset. Exact skin/icon data is attached to a per-item runtime copy.
    option.vanilla_skin = nil
    option.inventory_icon = nil
    option.cos_authored = false
    return option
end

function M.resolve_exact_icon(skin_list, armoury_key, target_item_type,
        exact_skin, normalize)
    if not _nonempty(armoury_key) then return nil, "missing-armoury-key" end
    if not _nonempty(target_item_type) then return nil, "missing-target-item-type" end
    if not _nonempty(exact_skin) then return nil, "missing-exact-skin" end
    if M.skin_item_type(exact_skin, normalize) ~= target_item_type then
        return nil, "foreign-skin-family"
    end
    local variant = type(skin_list) == "table"
        and rawget(skin_list, armoury_key) or nil
    local icons = type(variant) == "table" and variant.icons or nil
    local icon = type(icons) == "table" and rawget(icons, exact_skin) or nil
    if not _nonempty(icon) then return nil, "unmapped-exact-skin" end
    return icon, "exact-skin"
end

function M.resolve_for_item(option, target_item_type, exact_skin,
        skin_list, normalize)
    if type(option) ~= "table" or not option.la_armoury_key then return option end
    local resolved = {}
    for key, value in pairs(option) do resolved[key] = value end
    resolved.target_item_type = option.target_item_type or target_item_type
    resolved.cos_authored = false
    resolved.inventory_icon = nil
    resolved.vanilla_skin = nil
    if resolved.target_item_type ~= target_item_type then
        return resolved, "foreign-target"
    end
    local icon, reason = M.resolve_exact_icon(skin_list,
        option.la_armoury_key, target_item_type, exact_skin, normalize)
    if icon then
        resolved.inventory_icon = icon
        resolved.vanilla_skin = exact_skin
    end
    return resolved, reason
end

function M.selected_primary_skin(customization, backend_item,
        get_backend_skin, default_skins)
    local preview_item = customization and customization._previewer
        and customization._previewer._item
    if type(preview_item) == "table" and _nonempty(preview_item.skin) then
        return preview_item.skin, "preview-item"
    end

    -- `equipped` describes the committed skin and can remain true while a
    -- different row-one cell is selected for preview. Only the exact current
    -- selection is authoritative here.
    for _, widget in ipairs((customization
            and customization._illusion_widgets) or {}) do
        local content = widget and widget.content
        local hotspot = content and content.button_hotspot
        if hotspot and hotspot.is_selected
                and _nonempty(content.skin_key) then
            return content.skin_key, "selected-widget"
        end
    end

    if type(backend_item) == "table" and _nonempty(backend_item.skin) then
        return backend_item.skin, "backend-item"
    end
    if type(get_backend_skin) == "function" then
        local skin = get_backend_skin(backend_item)
        if _nonempty(skin) then return skin, "backend-interface" end
    end
    local key = type(backend_item) == "table" and backend_item.key or nil
    local default = key and type(default_skins) == "table"
        and default_skins[key] or nil
    if _nonempty(default) then return default, "default-skin" end
    return nil, "missing-skin"
end

function M.index_by_target(pools)
    local index = {}
    for item_type, hand_pools in pairs(pools or {}) do
        index[item_type] = index[item_type] or {}
        for hand_field, pool in pairs(hand_pools or {}) do
            index[item_type][hand_field] = index[item_type][hand_field] or {}
            for _, option in ipairs(pool or {}) do
                local key = option.armoury_key or option.la_armoury_key
                if key and not index[item_type][hand_field][key] then
                    index[item_type][hand_field][key] = option
                end
            end
        end
    end
    return index
end

function M.lookup(index, item_type, hand_field, armoury_key)
    local hands = type(index) == "table" and index[item_type] or nil
    local by_key = type(hands) == "table" and hands[hand_field] or nil
    return type(by_key) == "table" and by_key[armoury_key] or nil
end

return M
