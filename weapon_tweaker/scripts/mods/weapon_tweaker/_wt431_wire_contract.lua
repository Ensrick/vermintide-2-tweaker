-- Pure/catalog and narrow VMF transport policy for issue #431.
--
-- Presence is not enough to authorize a process-local NetworkLookup integer.
-- This module fingerprints every WT-owned damage-profile name together with
-- its actual local integer, then wraps the existing peer-parity transport so
-- only an exact catalog match can become an acknowledgement. The gameplay
-- sender floor remains separately unconditional.

local M = {}

M.WIRE_IDENTITY_VERSION = 1
M.MAX_SAFE_STRING = 64
M.MAX_VMF_JSON_LENGTH = 500
M.MAX_RETIRED_EPOCHS_PER_PEER = 8
M.MAX_RETIRED_PEERS = 32
M.RUNTIME_GATE_SETTINGS = {
    "authentic_brace_of_pistols",
    "wt_brett_sword_shield_buff",
    "wt_dual_axes_cleave",
    "wt_executioner_light_headshot_bonus",
    "wt_one_hand_axe_cleave_nerf",
    "wt_priest_punch_buff",
}

local function _positive_integer(value)
    return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function _safe_string(value)
    return type(value) == "string" and value ~= "" and #value <= M.MAX_SAFE_STRING
        and value:match("^[%w_.:%-]+$") ~= nil
end

local function _feed_hash(seed, multiplier, modulus, value)
    for i = 1, #value do
        seed = (seed * multiplier + string.byte(value, i)) % modulus
    end
    return seed
end

function M.build_wire_identity(fallbacks, lookup)
    if type(fallbacks) ~= "table" or type(lookup) ~= "table" then
        return nil, "fallbacks-or-lookup-missing"
    end

    local names = {}
    for custom, fallback in pairs(fallbacks) do
        if type(custom) ~= "string" or custom == ""
                or type(fallback) ~= "string" or fallback == "" then
            return nil, "invalid-fallback-entry"
        end
        names[#names + 1] = custom
    end
    table.sort(names)
    if #names == 0 then return nil, "fallback-registry-empty" end

    local canonical = { "wt431-wire-v", tostring(M.WIRE_IDENTITY_VERSION), "\n" }
    for i = 1, #names do
        local custom = names[i]
        local fallback = fallbacks[custom]
        local id = rawget(lookup, custom)
        local fallback_id = rawget(lookup, fallback)
        if not _positive_integer(id) or rawget(lookup, id) ~= custom then
            return nil, "custom-lookup-mismatch:" .. custom
        end
        if not _positive_integer(fallback_id) or rawget(lookup, fallback_id) ~= fallback then
            return nil, "fallback-lookup-mismatch:" .. fallback
        end
        canonical[#canonical + 1] = custom
        canonical[#canonical + 1] = "="
        canonical[#canonical + 1] = tostring(id)
        canonical[#canonical + 1] = ">"
        canonical[#canonical + 1] = fallback
        canonical[#canonical + 1] = "\n"
    end

    local input = table.concat(canonical)
    local h1 = _feed_hash(104729, 131, 2147483647, input)
    local h2 = _feed_hash(130363, 257, 2147483629, input)
    return string.format("wt431-v%d:%d:%08x:%08x",
        M.WIRE_IDENTITY_VERSION, #names, h1, h2), nil, names
end

-- Class-31 sender floor. Deliberately has no setting/toggle argument: once a
-- WT-owned profile reaches the sender, an unconfirmed peer always receives the
-- vanilla lookup entry. The owner-side repoint is only the first line of
-- defence; this pure coercion is the unconditional wire boundary.
function M.safe_profile_name(fallbacks, profile_name, parity_confirmed)
    if parity_confirmed == true or type(fallbacks) ~= "table" then
        return profile_name
    end
    return fallbacks[profile_name] or profile_name
end

local function _default_epoch(mod, proxy)
    local sequence = tonumber(mod and mod._wt431_epoch_sequence) or 0
    sequence = sequence + 1
    if mod then mod._wt431_epoch_sequence = sequence end
    local entropy = tostring(proxy):match("0x(%x+)") or "0"
    return string.format("e%d-%s", sequence, entropy:lower()):sub(1, M.MAX_SAFE_STRING)
end

-- Exact upper bound for the restricted-alphabet payload emitted below:
-- [schema,reply,"identity","epoch","challenge","reply_echo"]
function M.max_json_envelope_length()
    return 2 + 5 + 10 + (M.MAX_SAFE_STRING + 2) * 4
end

function M.wrap_parity_transport(mod, identity, opts)
    opts = opts or {}
    if type(mod) ~= "table" or not _safe_string(identity) then
        return nil, "mod-or-identity-invalid"
    end

    local parity_instance
    local peer_epoch = {}
    local retired_epoch = {}
    local retired_peer_order = {}
    local outstanding = {}
    local reply_to = {}
    local sequence = 0
    local proxy = {}
    local local_epoch = opts.session_epoch or _default_epoch(mod, proxy)
    if not _safe_string(local_epoch) then return nil, "session-epoch-invalid" end

    local function challenge()
        sequence = sequence + 1
        -- Put the monotonic component first so even a maximum-length injected
        -- epoch cannot truncate away the value which makes this query fresh.
        return string.format("q%d-%s", sequence, local_epoch):sub(1, M.MAX_SAFE_STRING)
    end

    local function retire(peer_id, epoch)
        if type(peer_id) ~= "string" or not _safe_string(epoch) then return end
        local retired = retired_epoch[peer_id]
        if not retired then
            retired = { set = {}, order = {} }
            retired_epoch[peer_id] = retired
            retired_peer_order[#retired_peer_order + 1] = peer_id
            if #retired_peer_order > M.MAX_RETIRED_PEERS then
                local oldest_peer = table.remove(retired_peer_order, 1)
                retired_epoch[oldest_peer] = nil
            end
        end
        if retired.set[epoch] then return end
        retired.set[epoch] = true
        retired.order[#retired.order + 1] = epoch
        if #retired.order > M.MAX_RETIRED_EPOCHS_PER_PEER then
            local oldest = table.remove(retired.order, 1)
            retired.set[oldest] = nil
        end
    end

    local function transport_forget(peer_id)
        if type(peer_id) ~= "string" then return end
        retire(peer_id, peer_epoch[peer_id])
        peer_epoch[peer_id] = nil
        outstanding[peer_id] = nil
        reply_to[peer_id] = nil
    end

    local function revoke(peer_id)
        if not parity_instance or type(peer_id) ~= "string" then return end
        pcall(parity_instance.forget_peer, parity_instance, peer_id)
        pcall(parity_instance.require_peer, parity_instance, peer_id)
    end

    local function accept_epoch(peer_id, epoch, challenged)
        if not _safe_string(epoch) then return false end
        if retired_epoch[peer_id] and retired_epoch[peer_id].set[epoch] then return false end
        local current = peer_epoch[peer_id]
        if current == nil or current == epoch then
            peer_epoch[peer_id] = epoch
            return true
        end
        if not challenged then return false end
        retire(peer_id, current)
        peer_epoch[peer_id] = epoch
        return true
    end

    function proxy:network_send(channel, recipient, schema, is_reply)
        local query, echo = "", ""
        if is_reply == 0 or is_reply == nil then
            query = challenge()
            if type(recipient) == "string" and recipient ~= "others" then
                outstanding[recipient] = query
            else
                outstanding.__broadcast = query
            end
        elseif type(recipient) == "string" then
            echo = reply_to[recipient] or ""
        end
        return mod:network_send(channel, recipient, schema, is_reply,
            identity, local_epoch, query, echo)
    end

    function proxy:network_register(channel, receiver)
        return mod:network_register(channel, function(sender_peer_id, schema, is_reply,
                remote_identity, remote_epoch, remote_query, remote_echo)
            if type(sender_peer_id) ~= "string" or remote_identity ~= identity then
                revoke(sender_peer_id)
                return
            end

            local is_query = is_reply == 0 or is_reply == nil
            if is_query then
                if not _safe_string(remote_query)
                        or not accept_epoch(sender_peer_id, remote_epoch, false) then
                    revoke(sender_peer_id)
                    return
                end
                reply_to[sender_peer_id] = remote_query
            else
                local expected = outstanding[sender_peer_id] or outstanding.__broadcast
                if not _safe_string(remote_echo) or remote_echo ~= expected
                        or not accept_epoch(sender_peer_id, remote_epoch, true) then
                    revoke(sender_peer_id)
                    return
                end
                outstanding[sender_peer_id] = nil
            end
            return receiver(sender_peer_id, schema, is_reply)
        end)
    end

    function proxy:_bind_parity_instance(instance)
        parity_instance = instance
        if type(instance) == "table" and type(instance.forget_peer) == "function"
                and instance._wt431_transport_forget_wrapped ~= true then
            local original = instance.forget_peer
            instance.forget_peer = function(self, peer_id)
                transport_forget(peer_id)
                return original(self, peer_id)
            end
            instance._wt431_transport_forget_wrapped = true
        end
    end

    function proxy:debug(...) return mod:debug(...) end
    function proxy:echo(...) return mod:echo(...) end
    function proxy:localize(...) return mod:localize(...) end
    proxy._wt431_transport_forget = transport_forget
    proxy._wt431_local_epoch = local_epoch
    proxy._wt431_retired_peer_count = function() return #retired_peer_order end
    proxy._wt431_is_epoch_retired = function(_, peer_id, epoch)
        local retired = retired_epoch[peer_id]
        return retired ~= nil and retired.set[epoch] == true
    end
    setmetatable(proxy, {
        __index = mod,
        __newindex = function(_, key, value) mod[key] = value end,
    })
    return proxy
end

function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" then return false, "get-mod-missing" end
    local ok, gut = pcall(get_mod_fn, "gut_dev")
    local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
    if type(tweaker) ~= "table" or type(tweaker.register_runtime_gate) ~= "function" then
        return false, "mod-tweaker-unavailable"
    end
    return tweaker:register_runtime_gate(gate_id, spec)
end

function M.runtime_gate_spec(mod_id, evaluate)
    if type(mod_id) ~= "string" or mod_id == "" or type(evaluate) ~= "function" then
        return nil
    end
    local setting_ids = {}
    for i = 1, #M.RUNTIME_GATE_SETTINGS do
        setting_ids[i] = M.RUNTIME_GATE_SETTINGS[i]
    end
    return { mod_id = mod_id, setting_ids = setting_ids, evaluate = evaluate }
end

return M
