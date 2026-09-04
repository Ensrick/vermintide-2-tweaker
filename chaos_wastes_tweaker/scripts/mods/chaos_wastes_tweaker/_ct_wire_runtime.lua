-- Pure decisions used by the public CT #426 engine adapter.
-- Keeping decode/filter/planning here lets the offline Lua suite drive the
-- exact shipped behavior without pretending to emulate VMF or Stingray.

local M = {}
M.MAX_ACTIVE_BUFF_ROWS = 4096
M.MAX_WIRE_ARRAY_ROWS = 4096
M.MAX_STATE_ENTRIES = 4096
M.POWER_UP_ROW_BYTES = 6
M.MAX_POWER_UP_CODEC_ROWS = 4096
M.MAX_POWER_UP_RAW_BYTES = M.POWER_UP_ROW_BYTES * M.MAX_POWER_UP_CODEC_ROWS
M.MAX_POWER_UP_ENCODED_BYTES = 65535

local function call_true(object, method, ...)
    local fn = type(object) == "table" and object[method]
    if type(fn) ~= "function" then return false end
    local ok, value = pcall(fn, object, ...)
    return ok and value == true
end

function M.wire_safe(instance, integrity)
    if not call_true(instance, "is_installed") then return false end
    local ok_state, state = pcall(instance.applied_state, instance)
    if not ok_state or state ~= "enabled" then return false end
    if not call_true(instance, "all_peers_have") then return false end
    if type(integrity) ~= "function" then return false end
    local ok_integrity, intact = pcall(integrity)
    return ok_integrity and intact == true
end

function M.sender_exact(instance, peer_id, integrity)
    if type(peer_id) ~= "string" or peer_id == "" then return false end
    if not call_true(instance, "is_installed") then return false end
    if not call_true(instance, "peer_has", peer_id) then return false end
    if type(integrity) ~= "function" then return false end
    local ok, intact = pcall(integrity)
    return ok and intact == true
end

-- Relay-capable host receivers need proof for the sender AND the complete
-- current roster. They deliberately do not consume applied_state(): a newly
-- exact hot join may be proven before the feature's settle timer enables local
-- producers, while one unproven third peer must still stop a numeric relay.
function M.roster_sender_exact(instance, peer_id, integrity)
    if not M.sender_exact(instance, peer_id, integrity) then return false end
    return call_true(instance, "all_peers_have")
end

function M.filter_values(policy, kind, values, exact_safe)
    if type(policy) ~= "table" then return nil, 0, "policy-missing" end
    if kind == "power_ups" or kind == "party_power_ups" then
        return policy.filter_power_ups(values, exact_safe)
    elseif kind == "bought_power_ups" then
        return policy.filter_power_up_names(values, exact_safe)
    elseif kind == "persistent_buffs" then
        return policy.filter_persistent_buffs(values, exact_safe)
    end
    return nil, 0, "state-kind-invalid"
end

local function finite_integer(value, minimum, maximum)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value == math.floor(value) and value >= minimum and value <= maximum
end

local function dense_array_count(values, maximum)
    if type(values) ~= "table" then return nil, "array-missing" end
    local count, highest = 0, 0
    for key in next, values do
        if not finite_integer(key, 1, maximum) then
            return nil, "array-key-invalid"
        end
        count = count + 1
        if key > highest then highest = key end
    end
    if count ~= highest then return nil, "array-sparse" end
    return highest
end

-- DeusPowerUpUtils.encoded_string_to_power_ups owns a reusable module-local
-- byte array and clears it only after a successful decode. ByteArray.write_string
-- does not truncate a longer prior value, so an exception can poison the next
-- shorter packet. Build the pinned engine wire format directly instead: every
-- decode and encode below owns a fresh byte array that cannot survive the call.
-- The dependency surface is validated raw and every codec call remains under a
-- pcall in sanitize_encoded_power_ups.
function M.power_up_codec(byte_array, lib_deflate, network_lookup)
    if type(byte_array) ~= "table" or type(lib_deflate) ~= "table"
            or type(network_lookup) ~= "table" then
        return nil, "codec-dependency-missing"
    end
    local write_uint8 = rawget(byte_array, "write_uint8")
    local read_uint8 = rawget(byte_array, "read_uint8")
    local write_int32 = rawget(byte_array, "write_int32")
    local read_int32 = rawget(byte_array, "read_int32")
    local write_string = rawget(byte_array, "write_string")
    local read_string = rawget(byte_array, "read_string")
    local compress = rawget(lib_deflate, "CompressDeflate")
    local decompress = rawget(lib_deflate, "DecompressDeflate")
    if type(write_uint8) ~= "function" or type(read_uint8) ~= "function"
            or type(write_int32) ~= "function" or type(read_int32) ~= "function"
            or type(write_string) ~= "function" or type(read_string) ~= "function"
            or type(compress) ~= "function" or type(decompress) ~= "function" then
        return nil, "codec-dependency-malformed"
    end
    local power_lookup = rawget(network_lookup, "deus_power_up_templates")
    local rarity_lookup = rawget(network_lookup, "rarities")
    if type(power_lookup) ~= "table" or type(rarity_lookup) ~= "table" then
        return nil, "codec-lookup-missing"
    end

    local codec = {}
    codec.decode = function(encoded)
        if type(encoded) ~= "string"
                or #encoded > M.MAX_POWER_UP_ENCODED_BYTES then
            return nil, "encoded-payload-invalid"
        end
        local raw, trailing = decompress(lib_deflate, encoded)
        if type(raw) ~= "string" or trailing ~= 0 then
            return nil, "compressed-payload-invalid"
        end
        local raw_length = #raw
        if raw_length > M.MAX_POWER_UP_RAW_BYTES
                or raw_length % M.POWER_UP_ROW_BYTES ~= 0 then
            return nil, "decoded-payload-size-invalid"
        end

        local bytes = {}
        local written, next_index = write_string(bytes, raw)
        if not rawequal(written, bytes) or next_index ~= raw_length + 1
                or #bytes ~= raw_length then
            return nil, "byte-array-write-invalid"
        end

        local values = {}
        local index = 1
        for row = 1, raw_length / M.POWER_UP_ROW_BYTES do
            local power_id, after_power = read_uint8(bytes, index)
            local rarity_id, after_rarity = read_uint8(bytes, after_power)
            local client_id, after_client = read_int32(bytes, after_rarity)
            if not finite_integer(power_id, 0, 255)
                    or not finite_integer(rarity_id, 0, 255)
                    or not finite_integer(client_id, -2147483648, 2147483647)
                    or after_power ~= index + 1
                    or after_rarity ~= after_power + 1
                    or after_client ~= after_rarity + 4 then
                return nil, "decoded-row-invalid:" .. tostring(row)
            end
            local name = rawget(power_lookup, power_id)
            local rarity = rawget(rarity_lookup, rarity_id)
            if type(name) ~= "string" or name == ""
                    or type(rarity) ~= "string" or rarity == "" then
                return nil, "decoded-lookup-invalid:" .. tostring(row)
            end
            values[row] = {
                name = name,
                rarity = rarity,
                client_id = client_id,
            }
            index = after_client
        end
        if index ~= raw_length + 1 then return nil, "decoded-tail-invalid" end
        return values
    end

    codec.encode = function(values)
        local count, count_error = dense_array_count(
            values, M.MAX_POWER_UP_CODEC_ROWS)
        if not count then return nil, "encoded-values-invalid:" .. count_error end

        local bytes = {}
        local index = 1
        for row = 1, count do
            local value = rawget(values, row)
            if type(value) ~= "table" then
                return nil, "encoded-row-invalid:" .. tostring(row)
            end
            local power_id = rawget(power_lookup, rawget(value, "name"))
            local rarity_id = rawget(rarity_lookup, rawget(value, "rarity"))
            local client_id = rawget(value, "client_id")
            if not finite_integer(power_id, 0, 255)
                    or not finite_integer(rarity_id, 0, 255)
                    or not finite_integer(client_id, -2147483648, 2147483647) then
                return nil, "encoded-row-field-invalid:" .. tostring(row)
            end
            local written_power, after_power = write_uint8(bytes, power_id, index)
            local written_rarity, after_rarity = write_uint8(
                bytes, rarity_id, after_power)
            local written_client, after_client = write_int32(
                bytes, client_id, after_rarity)
            if not rawequal(written_power, bytes)
                    or not rawequal(written_rarity, bytes)
                    or not rawequal(written_client, bytes)
                    or after_power ~= index + 1
                    or after_rarity ~= after_power + 1
                    or after_client ~= after_rarity + 4 then
                return nil, "byte-array-row-write-invalid:" .. tostring(row)
            end
            index = after_client
        end
        local expected_length = count * M.POWER_UP_ROW_BYTES
        if index ~= expected_length + 1 or #bytes ~= expected_length then
            return nil, "encoded-byte-array-size-invalid"
        end
        local raw, after_raw = read_string(bytes)
        if type(raw) ~= "string" or #raw ~= expected_length
                or after_raw ~= expected_length + 1 then
            return nil, "byte-array-read-invalid"
        end
        local encoded = compress(lib_deflate, raw)
        if type(encoded) ~= "string"
                or #encoded > M.MAX_POWER_UP_ENCODED_BYTES then
            return nil, "encoded-payload-invalid"
        end
        return encoded
    end
    return codec
end

local function call_codec(operation, value, label)
    local ok, result, reason = pcall(operation, value)
    if not ok then return false, nil, "codec-" .. label .. "-failed" end
    if result == nil then
        return false, nil, reason or "codec-" .. label .. "-failed"
    end
    return true, result
end

function M.sanitize_encoded_power_ups(policy, codec, encoded, sender_is_exact)
    if type(codec) ~= "table" or type(codec.decode) ~= "function"
            or type(codec.encode) ~= "function" then
        return nil, "codec-missing"
    end
    local ok_decode, decoded, decode_error = call_codec(
        codec.decode, encoded, "decode")
    if not ok_decode or type(decoded) ~= "table" then
        return nil, decode_error or "decode-failed"
    end
    local filtered, removed, filter_error = M.filter_values(
        policy, "power_ups", decoded, sender_is_exact == true)
    if not filtered then return nil, "decoded-values-invalid:" .. tostring(filter_error) end
    if removed == 0 then return encoded, nil, 0, #decoded end
    local ok_encode, sanitized, encode_error = call_codec(
        codec.encode, filtered, "encode")
    if not ok_encode or type(sanitized) ~= "string" then
        return nil, encode_error or "encode-failed"
    end
    return sanitized, nil, removed, #filtered
end

function M.lookup_receiver_decision(policy, lookup, id, sender_is_exact, kind)
    if type(lookup) ~= "table" or type(id) ~= "number" or id <= 0
            or id ~= id or id == math.huge or id == -math.huge
            or id > 9007199254740991 or math.floor(id) ~= id then
        return false, nil, "invalid-lookup-id"
    end
    local name = rawget(lookup, id)
    if type(name) ~= "string" then return false, nil, "unknown-lookup-id" end
    local allowed, reason = policy.receiver_decision(name, sender_is_exact, kind)
    return allowed == true, name, reason
end

-- GameObject initializers cache persistent buff ids at player-unit creation.
-- Those arrays are replayed when GameSession.add_peer begins full object sync,
-- independently of the later BuffSystem hot-join pass. Sanitize a detached copy
-- before changing that authoritative cached field.
function M.filter_lookup_ids(policy, lookup, values, exact_safe, kind)
    if type(policy) ~= "table" or type(lookup) ~= "table"
            or type(values) ~= "table" then
        return nil, 0, "lookup-array-missing"
    end
    local count, maximum = 0, 0
    for key in next, values do
        if type(key) ~= "number" or key <= 0 or key ~= key
                or key == math.huge or key == -math.huge
                or key ~= math.floor(key) or key > M.MAX_WIRE_ARRAY_ROWS then
            return nil, 0, "lookup-array-key-invalid"
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, 0, "lookup-array-sparse" end
    local filtered, removed = {}, 0
    for i = 1, maximum do
        local id = rawget(values, i)
        local allowed, _, reason = M.lookup_receiver_decision(
            policy, lookup, id, exact_safe == true, kind)
        if allowed then
            filtered[#filtered + 1] = id
        elseif reason == "ct-sender-unproven"
                or reason == "stale-ct-identity" then
            removed = removed + 1
        else
            return nil, 0, "lookup-array-entry-invalid:"
                .. tostring(i) .. ":" .. tostring(reason)
        end
    end
    return filtered, removed
end

-- Snapshot shape is deliberately engine-neutral. Each per-player row retains
-- an opaque key object so the engine adapter can commit the filtered value to
-- the exact row it planned without re-enumerating mutable SharedState.
function M.plan_state_strip(policy, snapshot)
    snapshot = snapshot or {}
    local plan = {
        player = {}, persistent = {}, party = nil, bought = nil,
        removed = { player = 0, persistent = 0, party = 0, bought = 0 },
    }
    local total_entries = 0
    local function account(filtered, removed)
        total_entries = total_entries + #filtered + removed
        if total_entries > M.MAX_STATE_ENTRIES then
            error("shared-state-entry-total-unbounded")
        end
    end
    local function row_count(rows, label)
        if type(rows) ~= "table" then error(label .. "-rows-missing") end
        local count, maximum = 0, 0
        for key in next, rows do
            if type(key) ~= "number" or key <= 0 or key ~= key
                    or key == math.huge or key == -math.huge
                    or key ~= math.floor(key) or key > M.MAX_STATE_ENTRIES then
                error(label .. "-row-key-invalid")
            end
            count = count + 1
            if key > maximum then maximum = key end
        end
        if count ~= maximum then error(label .. "-rows-sparse") end
        return maximum
    end
    local player_count = row_count(snapshot.player or {}, "player")
    for i = 1, player_count do
        local row = rawget(snapshot.player, i)
        if type(row) ~= "table" then error("player-row-invalid") end
        local filtered, removed, reason = policy.filter_power_ups(row.values, false)
        if not filtered then error("player-state-invalid:" .. tostring(reason)) end
        account(filtered, removed)
        if removed > 0 then
            plan.player[#plan.player + 1] = { key = row.key, values = filtered }
            plan.removed.player = plan.removed.player + removed
        end
    end
    local persistent_count = row_count(snapshot.persistent or {}, "persistent")
    for i = 1, persistent_count do
        local row = rawget(snapshot.persistent, i)
        if type(row) ~= "table" then error("persistent-row-invalid") end
        local filtered, removed, reason = policy.filter_persistent_buffs(row.values, false)
        if not filtered then error("persistent-state-invalid:" .. tostring(reason)) end
        account(filtered, removed)
        if removed > 0 then
            plan.persistent[#plan.persistent + 1] = { key = row.key, values = filtered }
            plan.removed.persistent = plan.removed.persistent + removed
        end
    end
    if type(snapshot.party) == "table" then
        local filtered, removed, reason = policy.filter_power_ups(snapshot.party, false)
        if not filtered then error("party-state-invalid:" .. tostring(reason)) end
        account(filtered, removed)
        if removed > 0 then plan.party = filtered end
        plan.removed.party = removed
    end
    if type(snapshot.bought) == "table" then
        local filtered, removed, reason = policy.filter_power_up_names(snapshot.bought, false)
        if not filtered then error("bought-state-invalid:" .. tostring(reason)) end
        account(filtered, removed)
        if removed > 0 then plan.bought = filtered end
        plan.removed.bought = removed
    end
    return plan
end

-- Return unique parent buff ids. One top-level template may produce several
-- sub-buff rows sharing the same id; removing the parent once is sufficient.
function M.ct_live_buff_ids(policy, buffs, count, excluded_ids)
    local ids, seen = {}, {}
    excluded_ids = excluded_ids or {}
    if type(policy) ~= "table" or type(policy.is_owned_buff_name) ~= "function" then
        return nil, "policy-missing"
    end
    if type(buffs) ~= "table" then return nil, "active-buffs-missing" end
    if type(count) ~= "number" or count ~= count or count == math.huge
            or count == -math.huge or count < 0 or count ~= math.floor(count)
            or count > M.MAX_ACTIVE_BUFF_ROWS then
        return nil, "active-buff-count-invalid"
    end
    for i = 1, count do
        local buff = rawget(buffs, i)
        if type(buff) ~= "table" then
            return nil, "active-buff-entry-invalid:" .. tostring(i)
        end
        local removed = rawget(buff, "removed") == true
        if removed then
            local exact_sentinel = true
            for key, value in next, buff do
                if key ~= "removed" or value ~= true then
                    exact_sentinel = false
                    break
                end
            end
            if not exact_sentinel then
                return nil, "active-buff-sentinel-invalid:" .. tostring(i)
            end
        else
            local id = rawget(buff, "id")
            local name = rawget(buff, "buff_template_name")
            if type(id) ~= "number" or id ~= id or id == math.huge
                    or id == -math.huge or id <= 0 or id ~= math.floor(id)
                    or id > 2147483647 then
                return nil, "active-buff-id-invalid:" .. tostring(i)
            end
            if type(name) ~= "string" or name == "" then
                return nil, "active-buff-name-invalid:" .. tostring(i)
            end
            if not seen[id] and not rawget(excluded_ids, id)
                    and policy.is_owned_buff_name(name) then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

return M
