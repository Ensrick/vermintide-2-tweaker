-- Pure ownership policy for the glow editor's LootItemUnitPreviewer target.
-- The editor may repaint only the preview belonging to its exact backend item
-- and selected illusion; stale/asynchronous previewers fail closed.

local Policy = {}

local function _skin_of(item)
    if type(item) ~= "table" then return nil end
    local skin = item.skin
    if type(skin) == "string" and skin ~= "" then return skin end
    local data = item.data
    if type(data) == "table" and data.item_type == "weapon_skin" then
        return data.name or item.key
    end
    return nil
end

function Policy.resolve(host, backend_id, slot_data, is_unit)
    if host == nil or backend_id == nil then return nil, "missing_identity" end
    if host._item_backend_id ~= backend_id then return nil, "backend_mismatch" end

    local previewer = host._previewer
    local item = previewer and previewer._item
    local requested_skin = type(slot_data) == "table" and slot_data.skin or nil
    local preview_skin = _skin_of(item)
    if type(requested_skin) == "string" and requested_skin ~= ""
            and preview_skin ~= requested_skin then
        return nil, "skin_mismatch"
    end

    local spawned = previewer and previewer._spawned_units
    if type(spawned) ~= "table" then return nil, "not_spawned" end
    local units = {}
    for i = 1, #spawned do
        local unit = spawned[i]
        if type(is_unit) ~= "function" or is_unit(unit) then
            units[#units + 1] = unit
        end
    end
    if #units == 0 then return nil, "no_live_units" end

    local data = type(item) == "table" and item.data or nil
    return {
        units = units,
        skin = preview_skin or requested_skin or "",
        item_name = type(data) == "table" and (data.name or data.matching_item_key) or nil,
        item_template = type(data) == "table" and data.template or nil,
    }, "ready"
end

-- The standalone customization weapon and the persistent inventory character
-- are separate preview owners. A committed edit must advance the parent
-- HeroViewStateOverview revision so HeroWindowCharacterPreview repopulates its
-- loadout (VT2 source: hero_window_character_preview.lua:240-248).
function Policy.request_inventory_refresh(host, backend_id)
    if host == nil or backend_id == nil then return false, "missing_identity" end
    if host._item_backend_id ~= backend_id then return false, "backend_mismatch" end
    local parent = host._parent
    local revision = parent and parent.loadout_sync_id
    if type(revision) ~= "number" then return false, "revision_unavailable" end
    parent.loadout_sync_id = revision + 1
    return true, parent.loadout_sync_id
end

-- Resolve both preview owners from one immutable item snapshot. The pending
-- illusion row intentionally has no backend id; only the active customization
-- item may supply its identity, and only through the shared family validator.
function Policy.resolve_spawn(item, active_backend_id, active_item_type,
        resolve_item_type, resolve_preview_backend_id)
    local data = type(item) == "table" and item.data or nil
    local skin = _skin_of(item)
    local has_skin = type(skin) == "string" and skin ~= ""
    local context = { data = data, skin = skin, has_skin = has_skin }
    if not has_skin or type(data) ~= "table"
            or type(resolve_item_type) ~= "function"
            or type(resolve_preview_backend_id) ~= "function" then
        return context
    end
    local item_type = resolve_item_type(data)
    context.preview_backend_id = resolve_preview_backend_id(
        item.backend_id or data.backend_id, item_type,
        active_backend_id, active_item_type)
    context.glow_backend_id = resolve_preview_backend_id(
        nil, item_type, active_backend_id, active_item_type)
    return context
end

-- Bind the freshly returned spawn array before the caller stores it on the
-- previewer. Dirty editor state survives only for the exact item+skin; every
-- other rebuild restores committed runtime state before the shared painter.
function Policy.bind_spawned(units, context, picker, glow, log)
    local backend_id = context and context.glow_backend_id
    local skin = context and context.skin
    local data = context and context.data
    if type(units) ~= "table" or backend_id == nil or skin == nil
            or type(data) ~= "table" or type(picker) ~= "table"
            or type(glow) ~= "table" then
        return false
    end
    local slot_data = { skin = skin }
    local dirty = picker.is_open_for(backend_id, slot_data)
    if not dirty then picker.restore_runtime_for(backend_id, slot_data) end
    for i = 1, 2 do
        local unit = units[i]
        if unit then
            glow.bind_glow_unit(unit, backend_id, skin, nil,
                data.matching_item_key or data.name, data.template)
        end
    end
    if type(log) == "function" then
        log("[glow:796] preview spawn rebound backend=%s skin=%s dirty=%s units=%d",
            tostring(backend_id), tostring(skin), tostring(dirty), #units)
    end
    return true, dirty
end

return Policy
