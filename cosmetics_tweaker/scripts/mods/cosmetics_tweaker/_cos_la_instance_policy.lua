-- Pure exact-item policy for Loremaster's Armoury inventory presentation.
-- Kept engine-free so offline tests can lock identity and fail-closed rules.

local M = {}

local function _backend_id(item)
    return type(item) == "table" and (item.backend_id or item.ItemInstanceId) or nil
end

-- A preview may omit backend_id while vanilla rebuilds it from a pending
-- weapon_skin row.  The customization screen's exact item is a valid fallback
-- only when both sides prove the same normalized weapon family.  An explicit
-- item identity always wins; unrelated/no-family previews fail closed.
function M.resolve_preview_backend_id(exact_backend_id, preview_item_type,
        active_backend_id, active_item_type)
    if exact_backend_id ~= nil and exact_backend_id ~= "" then
        return exact_backend_id, "exact"
    end
    if type(preview_item_type) == "string" and preview_item_type ~= ""
        and preview_item_type == active_item_type
        and active_backend_id ~= nil and active_backend_id ~= "" then
        return active_backend_id, "same-family-fallback"
    end
    return nil, "unowned"
end

local function _selection_key(record)
    if type(record) ~= "table" then return nil, nil end
    local authored = record.la_armoury_key or record.armoury_key
    if type(authored) == "string" and authored ~= "" then
        return "authored", authored
    end
    local unit = record.unit or record.intended_unit or record.unit_path
    if type(unit) == "string" and unit ~= "" then return "unit", unit end
    return nil, nil
end

-- Selection records may be restored from persistence, so table identity is not
-- stable.  Ownership is instead the exact authored key or unit path present in
-- the current item's hand pool.  Ambiguous records and missing pools fail closed.
function M.selection_owned(selection, pool)
    local kind, key = _selection_key(selection)
    if not kind or type(pool) ~= "table" then return false end
    for _, candidate in ipairs(pool) do
        local candidate_kind, candidate_key = _selection_key(candidate)
        if candidate_kind == kind and candidate_key == key then return true end
    end
    return false
end

function M.resolve_preview_selection(selections_by_backend_id, backend_id,
        hand_field, pool)
    if type(selections_by_backend_id) ~= "table"
        or backend_id == nil or backend_id == "" then
        return nil, "unowned-item"
    end
    local hands = selections_by_backend_id[backend_id]
    local selection = type(hands) == "table" and hands[hand_field] or nil
    if selection == nil then return nil, "none" end
    if not M.selection_owned(selection, pool) then
        return nil, "foreign-selection"
    end
    return selection, "owned"
end

-- LootItemUnitPreviewer has a stronger truth source than Unit.get_data:
-- spawn_data[i].unit_name is the exact path returned by BackendUtils and queued
-- for that hand.  Authored paints may proceed only on a declared 1P/3P mesh.
function M.preview_target_matches(proven_unit_path, variant)
    if type(proven_unit_path) ~= "string" or proven_unit_path == ""
        or type(variant) ~= "table" or type(variant.new_units) ~= "table" then
        return false
    end
    return proven_unit_path == variant.new_units[1]
        or (variant.new_units[2] ~= nil
            and proven_unit_path == variant.new_units[2])
end

local function _icon_for(armoury_key, exact_skin, fallback_skin, skin_list)
    if type(armoury_key) ~= "string" or armoury_key == "" then
        return nil, "missing-armoury-key"
    end
    local variant = type(skin_list) == "table" and rawget(skin_list, armoury_key) or nil
    local icons = type(variant) == "table" and variant.icons or nil
    if type(variant) ~= "table" then return nil, "missing-variant", armoury_key end
    if type(icons) ~= "table" then return nil, "missing-icon-table", armoury_key end

    -- The exact backend item's current skin owns its inventory card.  The
    -- bridge's `vanilla_skin` is only a representative paint target and may
    -- belong to a different shield family (or a non-glow variant).
    if type(exact_skin) == "string" and exact_skin ~= "" then
        local icon = rawget(icons, exact_skin)
        if type(icon) == "string" and icon ~= "" then
            return icon, "exact-skin", armoury_key, exact_skin
        end
    end
    if type(fallback_skin) == "string" and fallback_skin ~= ""
            and fallback_skin ~= exact_skin then
        local icon = rawget(icons, fallback_skin)
        if type(icon) == "string" and icon ~= "" then
            return icon, "fallback-skin", armoury_key, fallback_skin
        end
    end
    return nil, "unmapped-skin", armoury_key
end

local function _illusion_icon(item, saved_illusion,
        backend_to_armoury, backend_to_vanilla, skin_list)
    if type(saved_illusion) ~= "string" then return nil, "no-main-selection" end
    local armoury_key = type(backend_to_armoury) == "table"
        and backend_to_armoury[saved_illusion] or nil
    -- LA itself uses the Armoury key directly as the setting/skin identity
    -- (`WeaponSkins.skins[Armoury_key]`).  Only hat/outfit clones populate the
    -- bridge maps, so requiring backend_to_armoury here drops legitimate
    -- per-instance weapon selections.  Positive SKIN_LIST membership is the
    -- source-backed direct-key proof; unknown strings still fail closed.
    if not armoury_key and type(skin_list) == "table"
            and type(rawget(skin_list, saved_illusion)) == "table" then
        armoury_key = saved_illusion
    end
    local fallback_skin = type(backend_to_vanilla) == "table"
        and backend_to_vanilla[saved_illusion] or nil
    -- A present exact main skin that is not authored must fail closed; using
    -- the clone's vanilla parent would show a different cosmetic. The parent
    -- is only a reconstruction fallback when the item omits its skin field.
    return _icon_for(armoury_key, item.skin,
        (type(item.skin) ~= "string" or item.skin == "") and fallback_skin or nil,
        skin_list)
end

local function _offhand_icon(item, saved_offhands, skin_list)
    if type(saved_offhands) ~= "table" then return nil, "no-offhand-selection" end
    local record = saved_offhands.left_hand_unit
    if type(record) ~= "table" then return nil, "no-left-selection" end

    -- LA owns its authored variant/base-skin pairing. A cached vanilla icon
    -- must never mask a later LA selection on the same exact item.
    local armoury_key = record.armoury_key or record.la_armoury_key
    if armoury_key then
        local icon, reason, resolved_key, resolved_skin = _icon_for(armoury_key,
            item.skin, record.vanilla_key, skin_list)
        if icon then return icon, reason, resolved_key, resolved_skin end
        if record.cos_authored == true
                and type(record.inventory_icon) == "string"
                and record.inventory_icon ~= "" then
            return record.inventory_icon, "authored-cached-icon", armoury_key,
                record.vanilla_key
        end
        return nil, reason, resolved_key, resolved_skin
    end
    if type(record.inventory_icon) == "string" and record.inventory_icon ~= "" then
        return record.inventory_icon, "vanilla-cached-icon", nil, record.vanilla_key
    end
    return nil, "missing-offhand-icon"
end

function M.resolve_inventory_icon_detailed(item, saved_illusion, saved_offhands,
        backend_to_armoury, backend_to_vanilla, skin_list, ownership)
    if type(item) ~= "table" or not _backend_id(item) then
        return nil, "missing-exact-item"
    end

    local main_icon, main_reason, main_key, main_skin = _illusion_icon(item, saved_illusion,
        backend_to_armoury, backend_to_vanilla, skin_list)

    -- Dual weapons retain vanilla row one's main/right-hand ownership. Their
    -- independently customized left hand is visual-only and cannot replace
    -- the inventory icon.
    if ownership == "dual" then
        return main_icon, main_reason, main_key, main_skin
    end

    -- A shield is the independently owned presentation surface. Prefer its
    -- exact saved left-hand choice, then fall back to row one's LA illusion.
    if ownership == "shield" then
        local icon, reason, key, skin = _offhand_icon(item, saved_offhands, skin_list)
        if icon then return icon, reason, key, skin end
        if main_icon then return main_icon, main_reason, main_key, main_skin end
        return nil, reason ~= "no-offhand-selection" and reason or main_reason,
            key or main_key, skin or main_skin
    end

    -- Compatibility for older callers that do not yet classify the item:
    -- preserve the former whole-illusion-first behavior.
    if main_icon then return main_icon, main_reason, main_key, main_skin end
    return _offhand_icon(item, saved_offhands, skin_list)
end

function M.resolve_inventory_icon(item, saved_illusion, saved_offhands,
        backend_to_armoury, backend_to_vanilla, skin_list, ownership)
    return M.resolve_inventory_icon_detailed(item, saved_illusion, saved_offhands,
        backend_to_armoury, backend_to_vanilla, skin_list, ownership)
end

return M
