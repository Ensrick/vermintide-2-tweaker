-- _cos_la_payload_policy.lua - field validation for inbound cos_la_* payloads.
--
-- RESPONSIBILITY
-- Pure (no engine globals, no mod calls). `M.clean(payload, from_host)` decides
-- whether a `cos_la_apply_req` (client to host) or `cos_la_apply` (host to all)
-- payload has the field types and values the receivers can store, and returns a
-- fresh table holding only the known fields. A peer payload is attacker data:
-- `hand_field` becomes a key of the table vanilla returns from
-- `BackendUtils.get_item_units` (the only valid hand keys are left_hand_unit and
-- right_hand_unit, Vermintide-2-Source-Code/scripts/managers/backend/backend_utils.lua:144-146),
-- and `offhand_unit` becomes a unit path on the next husk spawn (A3-F04, #416).
--
-- `""` is the legitimate CLEAR value for `offhand_unit` (_cos_offhand_picker.lua).
-- `slot` is not checked against a list: for weapons it carries a weapon template
-- name, not a slot name.
--
-- Consumed via: one mod:dofile in _cos_la_sync_transport.install; both receive
-- handlers call M.clean right after their schema check. Also driven by the
-- in-game check issue416_payload_policy (_cos_runtime_checks.lua).
local M = {}

M.HANDS = { left_hand_unit = true, right_hand_unit = true }
M.KINDS = { hat = true, armor = true, offhand = true, illusion = true }

M.MAX_SLOT = 128
M.MAX_UNIT = 200
M.MAX_KEY = 128

local function plain_string(value, max_len, allow_empty)
    if type(value) ~= "string" then return false end
    local len = #value
    if len > max_len then return false end
    if len == 0 then return allow_empty == true end
    return value:find("%c") == nil
end

local function optional_string(value, max_len, allow_empty)
    return value == nil or plain_string(value, max_len, allow_empty)
end

local function optional_key(value, max_len)
    return value == nil or (type(value) == "string" and #value <= max_len)
end

-- Returns `clean, nil` or `nil, reason`.
function M.clean(payload, from_host)
    if type(payload) ~= "table" then return nil, "payload_type" end
    local slot = payload.slot
    if not plain_string(slot, M.MAX_SLOT, false) then return nil, "slot" end
    local hand_field = payload.hand_field
    if hand_field ~= nil and not M.HANDS[hand_field] then return nil, "hand_field" end
    if not optional_string(payload.offhand_unit, M.MAX_UNIT, true) then
        return nil, "offhand_unit"
    end
    local revert = payload.revert
    if revert ~= nil and revert ~= true then return nil, "revert" end
    local armoury_key = payload.armoury_key
    if not optional_key(armoury_key, M.MAX_KEY) then return nil, "armoury_key" end
    if not optional_key(payload.vanilla_key, M.MAX_KEY) then return nil, "vanilla_key" end
    if not optional_key(payload.wearer_career, M.MAX_KEY) then return nil, "wearer_career" end
    local kind = payload.kind
    local kind_known = type(kind) == "string" and M.KINDS[kind] == true
    if (armoury_key ~= nil or revert ~= nil) and not kind_known then return nil, "kind" end
    local wearer = payload.wearer_peer_id
    if from_host == true then
        if type(wearer) ~= "string" or wearer == "" then return nil, "wearer_peer_id" end
    end
    return {
        slot = slot,
        kind = kind_known and kind or nil,
        hand_field = hand_field,
        offhand_unit = payload.offhand_unit,
        armoury_key = armoury_key,
        vanilla_key = payload.vanilla_key,
        wearer_career = payload.wearer_career,
        revert = revert,
        wearer_peer_id = from_host == true and wearer or nil,
    }, nil
end

return M
