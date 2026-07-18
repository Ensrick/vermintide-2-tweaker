-- _cos_glow_instance_policy.lua
--
-- Issue 48: per-instance glow policy. A committed glow belongs to ONE exact
-- inventory instance wearing ONE exact illusion, never to every item that
-- happens to share the template or skin family.
--
-- Exact-instance identity is keyed by backend id, matching the issue 628
-- synthetic-item contract and the issue 702 offhand commit helper. The skin
-- suffix narrows the key further so swapping an illusion on the same instance
-- does not inherit the previous illusion's authored colour.
--
-- This module is pure policy: no game globals, no VMF, no rendering. The
-- picker owns persistence and the renderer owns painting; both ask here first.
-- Regression coverage: qa/lua/tests/test_cos_glow_instance_policy.lua

local M = {}

-- Canonical exact-instance key. nil backend id yields nil: an item we cannot
-- name exactly must never receive or keep a per-instance override.
function M.identity_key(backend_id, slot_data)
    if backend_id == nil then return nil end
    local skin = type(slot_data) == "table" and slot_data.skin or nil
    return string.format("backend:%s|skin:%s", tostring(backend_id), tostring(skin or ""))
end

-- Skin recorded on a peer's active payload. Falls back to parsing the identity
-- string so payloads that carry only the identity still bind to one illusion.
function M.expected_skin(peer_state)
    if type(peer_state) ~= "table" then return nil end
    local skin = peer_state.active_per_item_glow_skin
    if skin ~= nil then return tostring(skin) end
    local identity = peer_state.active_per_item_glow_identity
    if type(identity) == "string" then
        local parsed = identity:match("|skin:(.*)$")
        if parsed ~= nil then return parsed end
    end
    return nil
end

-- A declared constraint binds only when the receiver actually holds the field.
-- Absent local evidence is "unproven", not "matched".
local function _refines(expected, actual)
    if expected == nil or actual == nil then return true end
    return expected == actual
end

-- Remote receivers cannot use backend ids (they are owner-local), so a peer's
-- payload is bound to the wearer's render identity instead.
--
-- Fail closed when no skin is resolvable. Previously an all-nil payload matched
-- EVERY glow-capable unit on that wearer, which is exactly the family-wide
-- bleed issue 48 exists to prevent; rendering resident vanilla is the correct
-- fallback per docs/WEAPON_APPEARANCE_STANDARD.md conditional-presentation rule.
function M.remote_match(ctx, peer_state)
    if type(ctx) ~= "table" or type(peer_state) ~= "table" then return false end
    local expected_skin = M.expected_skin(peer_state)
    if expected_skin == nil then return false end
    if tostring(ctx.skin or "") ~= expected_skin then return false end
    if not _refines(peer_state.active_per_item_glow_slot, ctx.slot_name) then return false end
    if not _refines(peer_state.active_per_item_glow_item_name, ctx.item_name) then return false end
    if not _refines(peer_state.active_per_item_glow_item_template, ctx.item_template) then return false end
    return true
end

-- The runtime paint map is keyed by bare backend id, but persistence is keyed
-- by backend id AND skin. A persisted miss therefore has to CLEAR the runtime
-- entry: leaving it lets the previous illusion's override keep painting after
-- an illusion swap on the same instance.
function M.resolve_runtime(persisted_state, backend_id, identity)
    if backend_id == nil then
        return { action = "ignore" }
    end
    if type(persisted_state) ~= "table" then
        return { action = "clear", backend_id = backend_id }
    end
    return {
        action = "bind",
        backend_id = backend_id,
        identity = identity,
        state = persisted_state,
    }
end

-- An explicit per-item OFF is durable state, not a colour. The renderer
-- (_cos_glow.lua), the badge policy, and the composite icon builder already
-- consume `disabled`; this keeps it alive across shape/commit round trips so a
-- saved OFF is not silently rewritten into a colour on the next Apply.
function M.is_disabled(state)
    return type(state) == "table" and state.disabled == true
end

function M.carry_disabled(shaped, base)
    if type(shaped) ~= "table" then return shaped end
    if M.is_disabled(base) then
        shaped.disabled = true
    else
        shaped.disabled = nil
    end
    return shaped
end

return M
