-- Pure exact-item policy for Loremaster's Armoury inventory presentation.
-- Kept engine-free so offline tests can lock identity and fail-closed rules.

local M = {}

local function _backend_id(item)
    return type(item) == "table" and (item.backend_id or item.ItemInstanceId) or nil
end

local function _icon_for(armoury_key, vanilla_skin, skin_list)
    local variant = type(skin_list) == "table" and skin_list[armoury_key] or nil
    local icons = type(variant) == "table" and variant.icons or nil
    if type(icons) ~= "table" or type(vanilla_skin) ~= "string" then return nil end
    local icon = icons[vanilla_skin]
    return type(icon) == "string" and icon ~= "" and icon or nil
end

local function _illusion_icon(item, saved_illusion,
        backend_to_armoury, backend_to_vanilla, skin_list)
    if type(saved_illusion) ~= "string" then return nil end
    local armoury_key = type(backend_to_armoury) == "table"
        and backend_to_armoury[saved_illusion] or nil
    local vanilla_skin = item.skin or (type(backend_to_vanilla) == "table"
        and backend_to_vanilla[saved_illusion])
    return _icon_for(armoury_key, vanilla_skin, skin_list)
end

local function _offhand_icon(item, saved_offhands, skin_list)
    if type(saved_offhands) ~= "table" then return nil end
    local record = saved_offhands.left_hand_unit
    if type(record) ~= "table" then return nil end

    -- LA owns its authored variant/base-skin pairing. A cached vanilla icon
    -- must never mask a later LA selection on the same exact item.
    if record.armoury_key then
        return _icon_for(record.armoury_key,
            record.vanilla_key or item.skin, skin_list)
            or (record.cos_authored == true
                and type(record.inventory_icon) == "string"
                and record.inventory_icon ~= "" and record.inventory_icon or nil)
    end
    return type(record.inventory_icon) == "string"
        and record.inventory_icon ~= "" and record.inventory_icon or nil
end

function M.resolve_inventory_icon(item, saved_illusion, saved_offhands,
        backend_to_armoury, backend_to_vanilla, skin_list, ownership)
    if type(item) ~= "table" or not _backend_id(item) then return nil end

    local main_icon = _illusion_icon(item, saved_illusion,
        backend_to_armoury, backend_to_vanilla, skin_list)

    -- Dual weapons retain vanilla row one's main/right-hand ownership. Their
    -- independently customized left hand is visual-only and cannot replace
    -- the inventory icon.
    if ownership == "dual" then
        return main_icon
    end

    -- A shield is the independently owned presentation surface. Prefer its
    -- exact saved left-hand choice, then fall back to row one's LA illusion.
    if ownership == "shield" then
        return _offhand_icon(item, saved_offhands, skin_list) or main_icon
    end

    -- Compatibility for older callers that do not yet classify the item:
    -- preserve the former whole-illusion-first behavior.
    return main_icon or _offhand_icon(item, saved_offhands, skin_list)
end

return M
