-- _cos_custom_illusion_sync.lua -- semantic custom-illusion peer transport.
--
-- Translates Cosmetics-owned ct_* skin identity into the existing bounded
-- per-hand mesh channel. Vanilla wire encoding must still null these keys
-- (#421); this policy supplies the mod-peer-only equivalent and keeps exact
-- per-instance component choices as the final writer.
--
-- Owned by: cosmetics_tweaker.lua. Consumed through: install(mod, deps).

local M = {}

local HAND_FIELDS = { "right_hand_unit", "left_hand_unit" }

local function _item_identity(item)
    if type(item) ~= "table" then return nil, nil, nil end
    local data = type(item.data) == "table" and item.data or item
    -- Backend-item `.key` can be an instance/provider identity; the embedded
    -- ItemMasterList definition's name is the authoritative weapon family.
    local key = data.name or data.key or item.name or item.key
    local template = item.template or data.template
    local backend_id = item.backend_id or item.ItemInstanceId
        or data.backend_id or data.ItemInstanceId
    return key, template, backend_id
end

function M.resolve(custom_skin_keys, item_master, weapon_skins, item, skin_key)
    local item_key, template_key, backend_id = _item_identity(item)
    if not (skin_key and custom_skin_keys and custom_skin_keys[skin_key]) then
        return template_key, nil, "not-custom", backend_id
    end

    local definition = type(item_master) == "table" and rawget(item_master, skin_key) or nil
    local skin = type(weapon_skins) == "table" and rawget(weapon_skins, skin_key) or nil
    if type(definition) ~= "table" or type(skin) ~= "table" then
        return template_key, nil, "missing-definition", backend_id
    end
    if not item_key or definition.matching_item_key ~= item_key then
        return template_key, nil, "wrong-family", backend_id
    end

    template_key = template_key or definition.template or skin.template
    if not template_key then
        return nil, nil, "missing-template", backend_id
    end

    local desired = {}
    for _, hand in ipairs(HAND_FIELDS) do
        local unit_path = definition[hand] or skin[hand]
        if type(unit_path) == "string" and unit_path ~= "" then
            desired[hand] = unit_path
        end
    end
    if next(desired) == nil then
        return template_key, nil, "missing-hands", backend_id
    end
    return template_key, desired, "exact-family", backend_id
end

-- Return an ordered list of semantic STORE/CLEAR operations and the baseline
-- state to remember. Desired hands are deliberately re-emitted on every replay
-- edge. A committed per-instance hand selection owns that hand and is untouched.
function M.plan(previous, desired, claimed_hands)
    previous = type(previous) == "table" and previous or {}
    desired = type(desired) == "table" and desired or {}
    claimed_hands = type(claimed_hands) == "table" and claimed_hands or {}
    local operations, next_state = {}, {}

    for _, hand in ipairs(HAND_FIELDS) do
        if not claimed_hands[hand] then
            local unit_path = desired[hand]
            if unit_path then
                operations[#operations + 1] = { hand = hand, unit = unit_path }
                next_state[hand] = unit_path
            elseif previous[hand] then
                operations[#operations + 1] = { hand = hand, unit = "" }
            end
        end
    end
    return operations, next_state
end

function M.install(owner, deps)
    assert(type(owner) == "table", "custom illusion sync requires owner")
    assert(type(deps) == "table" and type(deps.unit_alive) == "function",
        "custom illusion sync requires runtime dependencies")
    assert(type(deps.owner_for_unit) == "function"
        and type(deps.wearer_is_human) == "function"
        and type(deps.selection_for) == "function"
        and type(deps.send) == "function",
        "custom illusion sync requires identity, selection, and send adapters")

    owner._cos_custom_illusion_sent = owner._cos_custom_illusion_sent or {}
    local diag_seen = {}

    local function publish(unit, item, skin_key, edge)
        if not (unit and deps.unit_alive(unit)) then
            return false, "unit-unavailable"
        end

        local template_key, desired, reason, backend_id = M.resolve(
            deps.custom_skin_keys, deps.item_master, deps.weapon_skins,
            item, skin_key)
        if not template_key then return false, reason end

        local wearer = deps.owner_for_unit(unit)
        if not wearer then return false, "owner-unproven" end
        if not deps.wearer_is_human(wearer) then return false, "bot-unowned" end
        if not wearer.peer_id then return false, "peer-unproven" end

        local wearer_key = tostring(wearer.peer_id)
        local by_template = owner._cos_custom_illusion_sent[wearer_key]
        if not by_template then
            by_template = {}
            owner._cos_custom_illusion_sent[wearer_key] = by_template
        end

        local selected = backend_id and deps.selection_for(backend_id) or nil
        local claimed = {}
        if type(selected) == "table" then
            for hand, option in pairs(selected) do
                if type(option) == "table" then claimed[hand] = true end
            end
        end

        local operations, next_state = M.plan(
            by_template[template_key], desired, claimed)
        local accepted = 0
        for _, operation in ipairs(operations) do
            if deps.send(unit, template_key, operation.hand, operation.unit) ~= true then
                return false, "send-failed", accepted
            end
            accepted = accepted + 1
        end
        by_template[template_key] = next(next_state) and next_state or nil

        if skin_key and deps.custom_skin_keys[skin_key]
            and type(deps.log) == "function"
        then
            local key = tostring(edge) .. "|" .. tostring(skin_key) .. "|" .. tostring(reason)
            if not diag_seen[key] then
                diag_seen[key] = true
                pcall(deps.log,
                    "[cos:918] semantic-plan edge=%s skin=%s template=%s reason=%s ops=%d",
                    tostring(edge or "?"), tostring(skin_key), tostring(template_key),
                    tostring(reason), #operations)
            end
        end
        return true, reason, accepted
    end

    owner._cos_send_custom_skin_hands = function(...)
        local ok, applied, reason, count = pcall(publish, ...)
        if ok then return applied, reason, count end
        if type(deps.log) == "function" then
            pcall(deps.log, "[cos:918] semantic publish failed: %s", tostring(applied))
        end
        return false, "publish-error", 0
    end

    owner._cos_custom_illusion_runtime_installed = true
    return true
end

return M
