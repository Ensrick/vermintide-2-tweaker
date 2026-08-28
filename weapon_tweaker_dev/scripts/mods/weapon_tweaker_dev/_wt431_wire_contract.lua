-- Pure/catalog and narrow VMF transport policy for issue #431.
--
-- Presence is not enough to authorize a process-local NetworkLookup integer.
-- This module fingerprints every WT-owned damage-profile name together with
-- its actual local integer, then wraps the existing peer-parity transport so
-- only an exact catalog match can become an acknowledgement. The gameplay
-- sender floor remains separately unconditional.

local M = {}

M.WIRE_IDENTITY_VERSION = 2
M.MAX_SAFE_STRING = 64
M.MAX_VMF_JSON_LENGTH = 500
M.MAX_RETIRED_EPOCHS_PER_PEER = 8
M.MAX_RETIRED_PEERS = 32
M.MAX_PROFILE_DIGEST_DEPTH = 64
M.MAX_PROFILE_DIGEST_NODES = 32768
M.RUNTIME_GATE_MAX_ATTEMPTS = 30
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

local _KEY_ORDER = { boolean = 1, number = 2, string = 3 }
local _TWO_POW_53 = 9007199254740992

local function _number_token(value)
    if value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    -- Lua equality intentionally collapses +0 and -0, but division and some
    -- profile math do not. Preserve the sign bit in the semantic contract so
    -- peers cannot acknowledge numerically distinct gameplay data.
    if value == 0 then
        return 1 / value == -math.huge and "-0e0" or "0e0"
    end
    local sign = value < 0 and "-" or "+"
    local mantissa, exponent = math.frexp(math.abs(value))
    -- frexp plus the exact 53-bit significand avoids locale-sensitive decimal
    -- formatting. Identical IEEE-754 Lua numbers therefore hash identically
    -- even when two peers use different Windows regional settings.
    local significand = mantissa * _TWO_POW_53
    return sign .. string.format("%.0f", significand)
        .. "e" .. tostring(exponent)
end

-- DamageProfileTemplates are ordinary Lua data trees. Hash their semantic
-- content rather than their process-local table addresses so two peers only
-- acknowledge profiles with the same actual gameplay values. Unsupported
-- values, cycles, and non-finite numbers fail closed instead of being reduced
-- to unstable tostring() output.
local function _profile_content_digest(profile)
    if type(profile) ~= "table" then return nil, "profile-missing" end

    local h1, h2 = 104729, 130363
    local active = {}
    local nodes = 0
    local function feed(value)
        h1 = _feed_hash(h1, 131, 2147483647, value)
        h2 = _feed_hash(h2, 257, 2147483629, value)
    end
    local function walk(value, depth)
        nodes = nodes + 1
        if nodes > M.MAX_PROFILE_DIGEST_NODES then
            return false, "profile-too-large"
        end
        if depth > M.MAX_PROFILE_DIGEST_DEPTH then
            return false, "profile-too-deep"
        end
        local value_type = type(value)
        if value_type == "nil" then feed("z;"); return true end
        if value_type == "boolean" then
            feed(value and "b1;" or "b0;")
            return true
        end
        if value_type == "number" then
            local token = _number_token(value)
            if not token then
                return false, "profile-number-nonfinite"
            end
            feed("n" .. token .. ";")
            return true
        end
        if value_type == "string" then
            feed("s" .. tostring(#value) .. ":" .. value .. ";")
            return true
        end
        if value_type ~= "table" then
            return false, "profile-unsupported-" .. value_type
        end
        if active[value] then return false, "profile-cycle" end

        active[value] = true
        local keys = {}
        for key in pairs(value) do
            if not _KEY_ORDER[type(key)] then
                active[value] = nil
                return false, "profile-key-unsupported-" .. type(key)
            end
            if type(key) == "number"
                    and (key ~= key or key == math.huge or key == -math.huge) then
                active[value] = nil
                return false, "profile-key-number-nonfinite"
            end
            keys[#keys + 1] = key
        end
        table.sort(keys, function(left, right)
            local left_type, right_type = type(left), type(right)
            if left_type ~= right_type then
                return _KEY_ORDER[left_type] < _KEY_ORDER[right_type]
            end
            if left_type == "boolean" then
                return left == false and right == true
            end
            return left < right
        end)
        feed("t" .. tostring(#keys) .. "{")
        for _, key in ipairs(keys) do
            local ok, digest_error = walk(key, depth + 1)
            if not ok then active[value] = nil; return false, digest_error end
            ok, digest_error = walk(rawget(value, key), depth + 1)
            if not ok then active[value] = nil; return false, digest_error end
        end
        feed("}")
        active[value] = nil
        return true
    end

    local ok, digest_error = walk(profile, 1)
    if not ok then return nil, digest_error end
    return string.format("%08x%08x", h1, h2)
end

M.profile_content_digest = _profile_content_digest

function M.build_wire_identity(fallbacks, lookup, profiles)
    if type(fallbacks) ~= "table" or type(lookup) ~= "table"
            or type(profiles) ~= "table" then
        return nil, "fallbacks-lookup-or-profiles-missing"
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
        local profile_digest, digest_error =
            _profile_content_digest(rawget(profiles, custom))
        if not profile_digest then
            return nil, "custom-profile-invalid:" .. custom .. ":"
                .. tostring(digest_error)
        end
        canonical[#canonical + 1] = custom
        canonical[#canonical + 1] = "="
        canonical[#canonical + 1] = tostring(id)
        canonical[#canonical + 1] = ">"
        canonical[#canonical + 1] = fallback
        canonical[#canonical + 1] = "#"
        canonical[#canonical + 1] = profile_digest
        canonical[#canonical + 1] = "\n"
    end

    local input = table.concat(canonical)
    local h1 = _feed_hash(104729, 131, 2147483647, input)
    local h2 = _feed_hash(130363, 257, 2147483629, input)
    return string.format("wt431-v%d:%d:%08x:%08x",
        M.WIRE_IDENTITY_VERSION, #names, h1, h2), nil, names
end

-- Capture exact custom/fallback ids and semantic digests once, after every
-- producer has registered. The hot sender floor uses the indexed row to avoid
-- rebuilding or hashing unrelated profiles; it deliberately rehashes the one
-- active custom profile before allowing that process-local id onto the wire.
function M.capture_catalog(fallbacks, lookup, profiles)
    if type(fallbacks) ~= "table" or type(lookup) ~= "table"
            or type(profiles) ~= "table" then
        return nil, "fallbacks-lookup-or-profiles-missing"
    end
    local names = {}
    -- Validate before table.sort: a non-string key would make sort throw, and
    -- this runs unprotected at module load.
    for custom in pairs(fallbacks) do
        if type(custom) ~= "string" or custom == ""
                or type(fallbacks[custom]) ~= "string"
                or fallbacks[custom] == "" then
            return nil, "invalid-fallback-entry"
        end
        names[#names + 1] = custom
    end
    table.sort(names)
    if #names == 0 then return nil, "fallback-registry-empty" end
    local snapshot = {
        names = names,
        custom_ids = {},
        fallback_ids = {},
        custom_by_id = {},
        profile_digests = {},
    }
    for i = 1, #names do
        local custom = names[i]
        local fallback = fallbacks[custom]
        local custom_id = rawget(lookup, custom)
        local fallback_id = rawget(lookup, fallback)
        if not _positive_integer(custom_id) or rawget(lookup, custom_id) ~= custom then
            return nil, "custom-lookup-mismatch:" .. tostring(custom)
        end
        if not _positive_integer(fallback_id) or rawget(lookup, fallback_id) ~= fallback then
            return nil, "fallback-lookup-mismatch:" .. tostring(fallback)
        end
        snapshot.custom_ids[i] = custom_id
        snapshot.fallback_ids[i] = fallback_id
        snapshot.custom_by_id[custom_id] = i
        local profile_digest, digest_error =
            _profile_content_digest(rawget(profiles, custom))
        if not profile_digest then
            return nil, "custom-profile-invalid:" .. custom .. ":"
                .. tostring(digest_error)
        end
        snapshot.profile_digests[i] = profile_digest
    end
    return snapshot
end

-- Live-catalog integrity: every captured name must STILL resolve to the exact
-- id it had at capture, in both directions. A late registration by another mod
-- that shifts our indices makes this false, which closes the gate.
function M.catalog_intact(snapshot, fallbacks, lookup, profiles)
    if type(snapshot) ~= "table" or type(snapshot.names) ~= "table"
            or type(snapshot.custom_ids) ~= "table"
            or type(snapshot.fallback_ids) ~= "table"
            or type(snapshot.profile_digests) ~= "table"
            or type(fallbacks) ~= "table" or type(lookup) ~= "table"
            or type(profiles) ~= "table" then
        return false
    end
    for i = 1, #snapshot.names do
        local custom = snapshot.names[i]
        local fallback = fallbacks[custom]
        local custom_id = snapshot.custom_ids[i]
        local fallback_id = snapshot.fallback_ids[i]
        if type(custom) ~= "string" or custom == ""
                or type(fallback) ~= "string" or fallback == ""
                or not _positive_integer(custom_id)
                or rawget(lookup, custom) ~= custom_id
                or rawget(lookup, custom_id) ~= custom
                or not _positive_integer(fallback_id)
                or rawget(lookup, fallback) ~= fallback_id
                or rawget(lookup, fallback_id) ~= fallback then
            return false
        end
        local profile_digest = _profile_content_digest(rawget(profiles, custom))
        if profile_digest ~= snapshot.profile_digests[i] then return false end
    end
    return true
end

-- Sender-hot-path guard for one active WT-owned id. This deliberately
-- recomputes the semantic digest on every custom send. A cached full-catalog
-- verdict is insufficient: a table can be mutated in place after the beacon
-- identity was built, and that custom id must then fall back rather than ride
-- the old acknowledgement onto the wire.
function M.catalog_row_intact(snapshot, index, fallbacks, lookup, profiles)
    if type(snapshot) ~= "table" or not _positive_integer(index)
            or type(snapshot.names) ~= "table"
            or type(snapshot.custom_ids) ~= "table"
            or type(snapshot.fallback_ids) ~= "table"
            or type(snapshot.profile_digests) ~= "table"
            or type(fallbacks) ~= "table" or type(lookup) ~= "table"
            or type(profiles) ~= "table" then
        return false
    end
    local custom = snapshot.names[index]
    local fallback = custom and fallbacks[custom]
    local custom_id = snapshot.custom_ids[index]
    local fallback_id = snapshot.fallback_ids[index]
    if type(custom) ~= "string" or custom == ""
            or type(fallback) ~= "string" or fallback == ""
            or not _positive_integer(custom_id)
            or rawget(lookup, custom) ~= custom_id
            or rawget(lookup, custom_id) ~= custom
            or not _positive_integer(fallback_id)
            or rawget(lookup, fallback) ~= fallback_id
            or rawget(lookup, fallback_id) ~= fallback then
        return false
    end
    local profile_digest = _profile_content_digest(rawget(profiles, custom))
    return profile_digest ~= nil
        and profile_digest == snapshot.profile_digests[index]
end

-- Numeric sender disposition -- the application floor in one pure function.
-- A WT-owned id may stay custom ONLY under an installed exact gate plus an
-- intact live catalog. Every other branch either returns a fallback id proven
-- RESIDENT in the live lookup (both directions, not mere table presence) or
-- returns nil so the caller drops the RPC. The custom id can never survive a
-- policy or lookup failure.
function M.profile_id_for_send(is_server, damage_profile_id, exact_safe,
        snapshot, fallbacks, lookup, profiles)
    -- Truthy, mirroring the engine's own branch at weapon_system.lua:179
    -- (`if self.is_server or LEVEL_EDITOR_TEST`). A host dispatches its local
    -- receiver rather than wiring the id, so narrowing this to `== true` would
    -- risk dropping a host's own attack RPCs.
    if is_server then return damage_profile_id, "local" end
    if type(lookup) ~= "table" or type(fallbacks) ~= "table" then
        return nil, "drop"
    end
    if not _positive_integer(damage_profile_id) then return nil, "drop" end
    local index = type(snapshot) == "table" and type(snapshot.custom_by_id) == "table"
        and rawget(snapshot.custom_by_id, damage_profile_id) or nil
    if index then
        if exact_safe == true and M.catalog_row_intact(
                snapshot, index, fallbacks, lookup, profiles) then
            return damage_profile_id, "custom"
        end
        local fallback = fallbacks[snapshot.names[index]]
        local fallback_id = snapshot.fallback_ids[index]
        if type(fallback) ~= "string" or fallback == ""
                or not _positive_integer(fallback_id)
                or rawget(lookup, fallback) ~= fallback_id
                or rawget(lookup, fallback_id) ~= fallback then
            return nil, "drop"
        end
        return fallback_id, "fallback"
    end
    -- Not in the snapshot: prove the id is a resident vanilla entry. An id
    -- whose name is WT-owned but absent from the snapshot (registered after
    -- capture) is dropped rather than wired.
    local name = rawget(lookup, damage_profile_id)
    if type(name) ~= "string" or rawget(lookup, name) ~= damage_profile_id
            or fallbacks[name] ~= nil then return nil, "drop" end
    return damage_profile_id, "vanilla"
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
    local expected_schema = opts.schema or M.WIRE_IDENTITY_VERSION
    if not _positive_integer(expected_schema) then return nil, "schema-invalid" end

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
            -- Protocol-generation gate. The wrapped shared helper runs in
            -- legacy two-field mode, so reject the schema HERE -- before any
            -- epoch or challenge is accepted and before delegating -- so a
            -- previously acknowledged peer cannot stay exact-safe after
            -- presenting an incompatible generation.
            if schema ~= expected_schema then
                revoke(sender_peer_id)
                return
            end
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

-- Presentation-only bridge, so every failure is soft. Both GUT stream ids are
-- tried because a player may run either the public or the dev build, and the
-- register call itself is pcall'd -- a throwing third-party Mod Tweaker must
-- never take the gameplay module down with it.
function M.try_register_runtime_gate(get_mod_fn, gate_id, spec)
    if type(get_mod_fn) ~= "function" or type(gate_id) ~= "string"
            or gate_id == "" or type(spec) ~= "table" then
        return false, "runtime-gate-arguments-invalid"
    end
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local ok, gut = pcall(get_mod_fn, gut_id)
        local tweaker = ok and type(gut) == "table" and gut.mod_tweaker or nil
        if type(tweaker) == "table"
                and type(tweaker.register_runtime_gate) == "function" then
            local ok_register, registered = pcall(
                tweaker.register_runtime_gate, tweaker, gate_id, spec)
            if ok_register and registered == true then return true end
        end
    end
    return false, "mod-tweaker-unavailable"
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

-- Bounded retry for the optional presentation bridge: GUT may load after us,
-- so we re-try, but a player without GUT must not retry forever. State goes
-- terminal on the first success or at RUNTIME_GATE_MAX_ATTEMPTS, and the
-- caller stops ticking once terminal. Both callbacks are pcall'd.
function M.runtime_gate_retry_step(state, make_spec, register)
    state = type(state) == "table" and state or {}
    state.registered = state.registered == true
    state.terminal = state.terminal == true
    if state.registered == true or state.terminal == true then return state end
    state.attempts = (tonumber(state.attempts) or 0) + 1

    local ok_spec, spec = pcall(make_spec)
    local registered = false
    if ok_spec and type(spec) == "table" and type(register) == "function" then
        local ok_register, result = pcall(register, spec)
        registered = ok_register and result == true
    end
    state.registered = registered
    if registered or state.attempts >= M.RUNTIME_GATE_MAX_ATTEMPTS then
        state.terminal = true
    end
    return state
end

return M
