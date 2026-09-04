-- Exact public-stream #426 contract. The Dev stream deliberately owns a
-- different catalog, so these tests load only the stable modules and freeze the
-- 10+19 public order independently.

return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local policy = assert(loadfile(base .. "_ct_wire_policy.lua"))()
    local runtime = assert(loadfile(base .. "_ct_wire_runtime.lua"))()
    local Catalog = assert(loadfile(base .. "_lib_wire_catalog.lua"))()
    local function reserve(value, buff_max)
        return policy.reserve_lookups(value, { buff = buff_max or 65535 })
    end

    local expected_power = {
        "ct_meta_stagger", "ct_meta_crit", "ct_meta_health",
        "ct_meta_cooldown", "ct_meta_ammo", "ct_meta_movespeed",
        "ct_boon_asuryan_wrath", "ct_boon_manann_tempest",
        "ct_boon_taal_twinned_arrow", "ct_boon_vauls_anvil",
    }
    local expected_buff = {
        "ct_miracle_of_ulric", "ct_miracle_of_isha_aegis",
        "ct_miracle_of_isha_wounds", "ct_meta_stagger_stack",
        "power_up_ct_meta_stagger_exotic", "ct_meta_crit_stack",
        "power_up_ct_meta_crit_exotic", "ct_meta_health_stack",
        "power_up_ct_meta_health_exotic", "ct_meta_cooldown_stack",
        "power_up_ct_meta_cooldown_exotic", "ct_meta_ammo_stack",
        "power_up_ct_meta_ammo_exotic", "ct_meta_movespeed_stack",
        "power_up_ct_meta_movespeed_exotic",
        "power_up_ct_boon_asuryan_wrath_unique",
        "power_up_ct_boon_manann_tempest_unique",
        "power_up_ct_boon_taal_twinned_arrow_unique",
        "power_up_ct_boon_vauls_anvil_unique",
    }

    local function axis(names)
        local out = {}
        for i = 1, #(names or {}) do
            rawset(out, i, names[i])
            rawset(out, names[i], i)
        end
        return out
    end
    local function joined(left, right)
        local out = {}
        for i = 1, #left do out[#out + 1] = left[i] end
        for i = 1, #right do out[#out + 1] = right[i] end
        return out
    end
    local function lookup()
        return {
            deus_power_up_templates = axis({ "natural_bond", "deus_larger_clip" }),
            buff_templates = axis({ "power_up_movespeed_exotic", "deus_ammo_pickup" }),
            rarities = axis({ "common", "rare", "exotic", "unique" }),
        }
    end
    local function power_up(name, client_id)
        return { name = name, rarity = "exotic", client_id = client_id or 1 }
    end
    -- Mirrors the pinned scripts/utils/byte_array.lua operations used by
    -- DeusPowerUpUtils, including write_string's intentional lack of tail
    -- truncation. The production adapter must be safe with these semantics.
    local function source_byte_array(trace)
        trace = trace or {}
        return {
            write_int32 = function(array, value, index)
                index = index or #array + 1
                local unsigned = value < 0 and value + 4294967296 or value
                for offset = 0, 3 do
                    array[index + offset] = math.floor(
                        unsigned / (256 ^ offset)) % 256
                end
                return array, index + 4
            end,
            read_int32 = function(array, index)
                index = index or 1
                local value = array[index] + array[index + 1] * 256
                    + array[index + 2] * 65536 + array[index + 3] * 16777216
                if value >= 2147483648 then value = value - 4294967296 end
                return value, index + 4
            end,
            write_uint8 = function(array, value, index)
                index = index or #array + 1
                array[index] = value
                return array, index + 1
            end,
            read_uint8 = function(array, index)
                return array[index or 1], index + 1
            end,
            read_string = function(array, start_index, end_index, out_array)
                start_index = start_index or 1
                end_index = end_index or #array
                out_array = out_array or {}
                for i = start_index, end_index do
                    out_array[i] = string.char(array[i])
                end
                trace.encode_arrays = trace.encode_arrays or {}
                trace.encode_arrays[#trace.encode_arrays + 1] = array
                return table.concat(out_array, "", 1, end_index), end_index + 1
            end,
            write_string = function(array, value, start_index,
                    string_start, string_end)
                start_index = start_index or 1
                string_start = string_start or 1
                string_end = string_end or #value
                for i = string_start, string_end do
                    array[start_index + i - 1] = string.byte(value, i)
                end
                trace.decode_arrays = trace.decode_arrays or {}
                trace.decode_arrays[#trace.decode_arrays + 1] = array
                return array, string_end + 1
            end,
        }
    end
    local function identity_deflate()
        return {
            CompressDeflate = function(_, value) return value end,
            DecompressDeflate = function(_, value) return value, 0 end,
        }
    end
    local function raw_snapshot(value)
        local snap = { metatable = getmetatable(value), values = {}, count = 0 }
        for key, entry in next, value do
            snap.count = snap.count + 1
            rawset(snap.values, key, entry)
        end
        return snap
    end
    local function raw_unchanged(value, snap, label)
        H.equal(getmetatable(value), snap.metatable, label .. " metatable")
        local count = 0
        for key, entry in next, value do
            count = count + 1
            H.equal(rawget(snap.values, key), entry, label .. " key " .. tostring(key))
        end
        H.equal(count, snap.count, label .. " count")
        for key, entry in next, snap.values do
            H.equal(rawget(value, key), entry, label .. " missing " .. tostring(key))
        end
    end
    local function lookup_snapshot(value)
        return {
            outer = raw_snapshot(value),
            power = type(rawget(value, "deus_power_up_templates")) == "table"
                and raw_snapshot(rawget(value, "deus_power_up_templates")) or nil,
            buff = type(rawget(value, "buff_templates")) == "table"
                and raw_snapshot(rawget(value, "buff_templates")) or nil,
        }
    end
    local function lookup_unchanged(value, snap, label)
        raw_unchanged(value, snap.outer, label .. " outer")
        local power = rawget(value, "deus_power_up_templates")
        local buff = rawget(value, "buff_templates")
        if snap.power then raw_unchanged(power, snap.power, label .. " power") end
        if snap.buff then raw_unchanged(buff, snap.buff, label .. " buff") end
    end
    local function globals_for(nl)
        local templates, powers, buffs = {}, {}, {}
        for name, spec in pairs(policy.power_up_entries()) do
            templates[name] = {}
            powers[spec.rarity] = powers[spec.rarity] or {}
            powers[spec.rarity][name] = { name = name, rarity = spec.rarity }
        end
        for name in pairs(policy.buff_entries()) do buffs[name] = {} end
        return {
            NetworkLookup = nl,
            DeusPowerUpTemplates = templates,
            DeusPowerUps = powers,
            BuffTemplates = buffs,
        }
    end

    H.test("CT public #426 freezes the exact legacy 10+19 order", function()
        H.equal(policy.POWER_UP_COUNT, 10)
        H.equal(policy.BUFF_COUNT, 19)
        H.equal(policy.WIRE_ROW_COUNT, 29)
        H.deep_equal(policy.power_order(), expected_power)
        H.deep_equal(policy.buff_order(), expected_buff)
        H.equal(policy.count(policy.power_up_entries()), 10)
        H.equal(policy.count(policy.buff_entries()), 19)
        H.equal(#policy.GATED_SETTING_IDS, 17)
        H.equal(policy.is_power_up("ct_kill_heal"), false)
        H.equal(policy.is_buff("power_up_ct_kill_heal_exotic"), false)
        H.equal(policy.is_power_up("ct_meta_stagger"), true)
        H.equal(policy.is_buff("ct_miracle_of_ulric"), true)
    end)

    H.test("CT public #426 bootstrap failures keep every CT namespace unavailable", function()
        local function read(path)
            local f = assert(io.open(repo_root .. "/" .. path, "rb"))
            local text = f:read("*a")
            f:close()
            return text
        end
        local lookup_lib = assert(loadfile(
            base .. "_lib_network_lookup.lua"))()
        local bootstrap = assert(loadfile(
            base .. "_ct_wire_bootstrap.lua"))()
        local main = read(
            "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua")
        local first = assert(main:find("local _injected_dormants = {}", 1, true))
        local last = assert(main:find(
            "local function inject_dormant_boon(power_up_name, rarity)",
            first, true))
        local bootstrap_source = main:sub(first, last - 1) .. [[
return {
    register_power = register_power_up_in_network_lookup,
    register_buff = register_buff_in_network_lookup,
}
]]

        local function policy_copy(reserve_override, overrides)
            local copy = {}
            for key, value in next, policy do rawset(copy, key, value) end
            if reserve_override then
                rawset(copy, "reserve_lookups", reserve_override)
            end
            for key, value in next, overrides or {} do rawset(copy, key, value) end
            return copy
        end

        local cases = {
            { name = "bootstrap-load-error", bootstrap_error = true },
            { name = "bootstrap-api-missing", bootstrap_value = {} },
            { name = "policy-load-error", policy_error = true },
            { name = "policy-api-missing", policy_value = {} },
            { name = "lookup-load-error", lookup_error = true },
            { name = "lookup-api-missing", lookup_value = {} },
            { name = "network-missing", network_missing = true },
            { name = "capacity-shape-missing", capacity_value = {} },
            { name = "capacity-read-throws", capacity_error = true },
            { name = "capacity-exhausted", capacity = 2 },
            { name = "reserve-throws", policy_value = policy_copy(function()
                error("planted reservation failure")
            end) },
            { name = "reserve-mutates-then-throws", policy_value = policy_copy(
                function(network_lookup)
                    local power = rawget(network_lookup,
                        "deus_power_up_templates")
                    rawset(power, "ct_meta_health", 77)
                    rawset(power, 77, "ct_meta_health")
                    rawset(power, "other_mod_boon", 88)
                    rawset(power, 2, nil)
                    rawset(power, 88, "other_mod_boon")
                    setmetatable(power, { __index = function()
                        error("mutated strict metatable")
                    end })
                    rawset(network_lookup, "buff_templates", {
                        [1] = "ct_miracle_of_ulric",
                        ct_miracle_of_ulric = 1,
                    })
                    setmetatable(network_lookup, { __index = function()
                        error("mutated root metatable")
                    end })
                    error("planted reservation failure after mutation")
                end) },
            { name = "reservation-unverified", policy_value = policy_copy(function()
                return { power_up = {}, buff = {} }
            end) },
            { name = "reservation-mutates-then-unverified",
                policy_value = policy_copy(function(network_lookup)
                    local power = rawget(network_lookup,
                        "deus_power_up_templates")
                    local buff = rawget(network_lookup, "buff_templates")
                    rawset(power, "ct_meta_crit", 3)
                    rawset(power, 3, "ct_meta_crit")
                    rawset(buff, "ct_miracle_of_ulric", 3)
                    rawset(buff, 3, "ct_miracle_of_ulric")
                    rawset(buff, "other_mod_buff", 44)
                    rawset(buff, 2, nil)
                    rawset(buff, 44, "other_mod_buff")
                    setmetatable(buff, { __newindex = function()
                        error("mutated strict metatable")
                    end })
                    return { power_up = {}, buff = {} }
                end) },
            { name = "verifier-mutates-then-throws",
                policy_value = policy_copy(nil, {
                    capture_integrity = function(network_lookup)
                        local power = rawget(network_lookup,
                            "deus_power_up_templates")
                        rawset(power, "other_mod_boon", 55)
                        rawset(power, 2, nil)
                        rawset(power, 55, "other_mod_boon")
                        error("planted verifier failure after mutation")
                    end,
                }) },
            { name = "integrity-verifier-throws",
                policy_value = policy_copy(nil, {
                    integrity = function()
                        error("planted integrity verifier failure")
                    end,
                }) },
            { name = "lookup-malformed", malformed_lookup = true },
        }

        for i = 1, #cases do
            local case = cases[i]
            local nl = {
                deus_power_up_templates = axis({
                    "natural_bond", "other_mod_boon",
                }),
                buff_templates = axis({
                    "power_up_movespeed_exotic", "other_mod_buff",
                }),
            }
            if case.malformed_lookup then
                rawset(nl.buff_templates, "half_row", 3)
            end
            local before = lookup_snapshot(nl)
            local mod = {}
            function mod:dofile(path)
                if path:find("_ct_wire_bootstrap", 1, true) then
                    if case.bootstrap_error then error("planted bootstrap load") end
                    return case.bootstrap_value or bootstrap
                end
                if path:find("_ct_wire_policy", 1, true) then
                    if case.policy_error then error("planted policy load") end
                    return case.policy_value or policy
                end
                if path:find("_lib_network_lookup", 1, true) then
                    if case.lookup_error then error("planted lookup load") end
                    return case.lookup_value or lookup_lib
                end
                error("unexpected bootstrap dofile: " .. tostring(path))
            end
            local env = {
                mod = mod,
                NetworkLookup = nl,
                printf = function() end,
                _dbg = function() end,
            }
            if not case.network_missing then
                env.Network = {
                    type_info = function()
                        if case.capacity_error then
                            error("planted capacity read")
                        end
                        if case.capacity_value then return case.capacity_value end
                        return { max = case.capacity or 65535 }
                    end,
                }
            end
            env._G = env
            setmetatable(env, { __index = _G })
            local chunk = assert(loadstring(bootstrap_source,
                "@ct_public_426_bootstrap_failure.lua"))
            setfenv(chunk, env)
            local ok, exports = pcall(chunk)
            H.equal(ok, true, case.name .. " bootstrap raised")
            H.equal(rawget(mod, "_ct_wire_reservation_ready"), false,
                case.name .. " reservation escaped")

            for _, name in ipairs({ "ct_meta_health", "ct_future_boon" }) do
                H.equal(mod._ct_is_modded_power_up(name), true,
                    case.name .. " lost owned power namespace")
                H.equal(mod._ct_power_up_wire_allowed(name), false,
                    case.name .. " allowed owned power")
                exports.register_power(name)
            end
            for _, name in ipairs({
                    "ct_miracle_of_ulric", "power_up_ct_future_unique",
                }) do
                H.equal(mod._ct_is_ct_buff_template(name), true,
                    case.name .. " lost owned buff namespace")
                H.equal(mod._ct_buff_wire_allowed(name), false,
                    case.name .. " allowed owned buff")
                exports.register_buff(name)
            end
            H.equal(mod._ct_power_up_wire_allowed("natural_bond"), true,
                case.name .. " blocked vanilla power")
            H.equal(mod._ct_power_up_wire_allowed("other_mod_boon"), true,
                case.name .. " blocked unrelated mod power")
            H.equal(mod._ct_buff_wire_allowed("power_up_movespeed_exotic"), true,
                case.name .. " blocked vanilla buff")
            H.equal(mod._ct_buff_wire_allowed("other_mod_buff"), true,
                case.name .. " blocked unrelated mod buff")
            lookup_unchanged(nl, before, case.name)
        end
    end)

    H.test("CT public #426 reserves both axes only after both preflight", function()
        local nl = lookup()
        local result = assert(reserve(nl))
        H.equal(result.power_up.added, 10)
        H.equal(result.buff.added, 19)
        H.equal(result.power_up.order, nil)
        H.equal(result.power_up.lookup, nil)
        H.equal(result.buff.order, nil)
        H.equal(result.buff.lookup, nil)
        for i = 1, #expected_power do
            H.equal(rawget(nl.deus_power_up_templates, expected_power[i]), 2 + i)
            H.equal(rawget(nl.deus_power_up_templates, 2 + i), expected_power[i])
        end
        for i = 1, #expected_buff do
            H.equal(rawget(nl.buff_templates, expected_buff[i]), 2 + i)
            H.equal(rawget(nl.buff_templates, 2 + i), expected_buff[i])
        end
        local again = assert(reserve(nl))
        H.equal(again.power_up.added, 0)
        H.equal(again.buff.added, 0)
    end)

    H.test("CT public #426 reservation result cannot mutate frozen catalog", function()
        local nl = lookup()
        local result = assert(reserve(nl))
        result.power_up.order = { "hostile" }
        result.buff.order = { "hostile" }
        result.power_up.first_id = 999999
        H.deep_equal(policy.power_order(), expected_power)
        H.deep_equal(policy.buff_order(), expected_buff)
        local again = assert(reserve(nl))
        H.equal(again.power_up.added, 0)
        H.equal(again.buff.added, 0)
        H.equal(rawget(nl.deus_power_up_templates, expected_power[1]), 3)
        H.equal(rawget(nl.buff_templates, expected_buff[1]), 3)
    end)

    H.test("CT public #426 buff refusal leaves power raw shape byte-stable", function()
        local cases = {}

        local partial = lookup()
        rawset(partial.buff_templates, expected_buff[1], 3)
        rawset(partial.buff_templates, 3, expected_buff[1])
        cases[#cases + 1] = { partial, "partial-existing-catalog:buff_templates" }

        local sparse = lookup()
        rawset(sparse.buff_templates, 4, "foreign_gap")
        rawset(sparse.buff_templates, "foreign_gap", 4)
        cases[#cases + 1] = { sparse, "lookup-numeric-side-sparse:buff_templates" }

        local asymmetric = lookup()
        rawset(asymmetric.buff_templates, "half_row", 3)
        cases[#cases + 1] = { asymmetric, "lookup-pair-asymmetric:buff_templates" }

        local invalid_key = lookup()
        rawset(invalid_key.buff_templates, 1.5, "fractional")
        cases[#cases + 1] = { invalid_key, "lookup-numeric-key-invalid:buff_templates" }

        local foreign_key = lookup()
        rawset(foreign_key.buff_templates, true, "invalid")
        cases[#cases + 1] = { foreign_key, "lookup-key-invalid:buff_templates" }

        cases[#cases + 1] = {
            { deus_power_up_templates = axis({ "natural_bond" }) },
            "lookup-axis-missing:buff_templates",
        }

        for i = 1, #cases do
            local nl, expected = cases[i][1], cases[i][2]
            local before = lookup_snapshot(nl)
            local result, reason = reserve(nl)
            H.equal(result, nil, "case " .. i)
            H.equal(reason, expected, "case " .. i)
            lookup_unchanged(nl, before, "case " .. i)
        end
    end)

    H.test("CT public #426 every power refusal leaves both axes untouched", function()
        local cases = {}

        local partial = lookup()
        rawset(partial.deus_power_up_templates, expected_power[1], 3)
        rawset(partial.deus_power_up_templates, 3, expected_power[1])
        cases[#cases + 1] = {
            partial, "partial-existing-catalog:deus_power_up_templates",
        }

        local zero = lookup()
        rawset(zero.deus_power_up_templates, 0, "zero")
        cases[#cases + 1] = {
            zero, "lookup-numeric-key-invalid:deus_power_up_templates",
        }

        local negative = lookup()
        rawset(negative.deus_power_up_templates, -1, "negative")
        cases[#cases + 1] = {
            negative, "lookup-numeric-key-invalid:deus_power_up_templates",
        }

        local infinite = lookup()
        rawset(infinite.deus_power_up_templates, math.huge, "infinite")
        cases[#cases + 1] = {
            infinite, "lookup-numeric-key-invalid:deus_power_up_templates",
        }

        local duplicate = lookup()
        rawset(duplicate.deus_power_up_templates, "alias", 1)
        cases[#cases + 1] = {
            duplicate, "lookup-pair-asymmetric:deus_power_up_templates",
        }

        cases[#cases + 1] = {
            { buff_templates = axis({ "power_up_movespeed_exotic" }) },
            "lookup-axis-missing:deus_power_up_templates",
        }

        for i = 1, #cases do
            local nl, expected = cases[i][1], cases[i][2]
            local before = lookup_snapshot(nl)
            local result, reason = reserve(nl)
            H.equal(result, nil, "case " .. i)
            H.equal(reason, expected, "case " .. i)
            lookup_unchanged(nl, before, "case " .. i)
        end
    end)

    H.test("CT public #426 wrong full legacy order refuses without raw mutation", function()
        local wrong_power = {}
        for i = 1, #expected_power do wrong_power[i] = expected_power[i] end
        wrong_power[1], wrong_power[2] = wrong_power[2], wrong_power[1]
        local wrong_buff = {}
        for i = 1, #expected_buff do wrong_buff[i] = expected_buff[i] end
        wrong_buff[1], wrong_buff[2] = wrong_buff[2], wrong_buff[1]

        local cases = {
            {
                {
                    deus_power_up_templates = axis(joined(
                        { "natural_bond", "deus_larger_clip" }, wrong_power)),
                    buff_templates = axis({ "power_up_movespeed_exotic", "deus_ammo_pickup" }),
                }, "legacy-order-mismatch:deus_power_up_templates:ct_meta_crit",
            },
            {
                {
                    deus_power_up_templates = axis({ "natural_bond", "deus_larger_clip" }),
                    buff_templates = axis(joined(
                        { "power_up_movespeed_exotic", "deus_ammo_pickup" }, wrong_buff)),
                }, "legacy-order-mismatch:buff_templates:ct_miracle_of_isha_aegis",
            },
        }
        for i = 1, #cases do
            local nl, expected = cases[i][1], cases[i][2]
            setmetatable(nl.deus_power_up_templates, { marker = "power-" .. i })
            setmetatable(nl.buff_templates, { marker = "buff-" .. i })
            local before = lookup_snapshot(nl)
            local result, reason = reserve(nl)
            H.equal(result, nil, "wrong order case " .. i)
            H.equal(reason, expected, "wrong order case " .. i)
            lookup_unchanged(nl, before, "wrong order case " .. i)
        end
    end)

    H.test("CT public #426 mixed idempotent and malformed axes remain atomic", function()
        local cases = {}
        local complete_power = {
            deus_power_up_templates = axis(joined(
                { "natural_bond", "deus_larger_clip" }, expected_power)),
            buff_templates = axis({ "power_up_movespeed_exotic", "deus_ammo_pickup" }),
        }
        rawset(complete_power.buff_templates, expected_buff[1], 3)
        rawset(complete_power.buff_templates, 3, expected_buff[1])
        cases[#cases + 1] = {
            complete_power, "partial-existing-catalog:buff_templates",
        }

        local complete_buff = {
            deus_power_up_templates = axis({ "natural_bond", "deus_larger_clip" }),
            buff_templates = axis(joined(
                { "power_up_movespeed_exotic", "deus_ammo_pickup" }, expected_buff)),
        }
        rawset(complete_buff.deus_power_up_templates, expected_power[1], 3)
        rawset(complete_buff.deus_power_up_templates, 3, expected_power[1])
        cases[#cases + 1] = {
            complete_buff, "partial-existing-catalog:deus_power_up_templates",
        }

        for i = 1, #cases do
            local nl, expected = cases[i][1], cases[i][2]
            setmetatable(nl.deus_power_up_templates, { marker = "power-" .. i })
            setmetatable(nl.buff_templates, { marker = "buff-" .. i })
            local before = lookup_snapshot(nl)
            local result, reason = reserve(nl)
            H.equal(result, nil, "mixed case " .. i)
            H.equal(reason, expected, "mixed case " .. i)
            lookup_unchanged(nl, before, "mixed case " .. i)
        end
    end)

    H.test("CT public #426 aliased axes refuse atomically", function()
        local shared = axis({ "vanilla_one", "vanilla_two" })
        local nl = {
            deus_power_up_templates = shared,
            buff_templates = shared,
        }
        local before = lookup_snapshot(nl)
        local result, reason = reserve(nl)
        H.equal(result, nil)
        H.equal(reason, "lookup-axes-aliased")
        lookup_unchanged(nl, before, "aliased")
    end)

    H.test("CT public #426 codec capacities refuse before either axis mutates", function()
        local cases = {}
        for _, count in ipairs({ 246, 255 }) do
            local names = {}
            for i = 1, count do names[i] = "vanilla_power_" .. tostring(i) end
            cases[#cases + 1] = {
                {
                    deus_power_up_templates = axis(names),
                    buff_templates = axis({ "vanilla_buff" }),
                }, 65535, "lookup-capacity-exceeded:deus_power_up_templates",
            }
        end
        local huge = lookup()
        rawset(huge.deus_power_up_templates, 9007199254740992, "huge")
        rawset(huge.deus_power_up_templates, "huge", 9007199254740992)
        cases[#cases + 1] = {
            huge, 65535, "lookup-numeric-key-invalid:deus_power_up_templates",
        }
        cases[#cases + 1] = {
            lookup(), 20, "lookup-capacity-exceeded:buff_templates",
        }
        for i = 1, #cases do
            local nl, cap, expected = cases[i][1], cases[i][2], cases[i][3]
            local before = lookup_snapshot(nl)
            local result, reason = reserve(nl, cap)
            H.equal(result, nil, "case " .. i)
            H.equal(reason, expected, "case " .. i)
            lookup_unchanged(nl, before, "capacity case " .. i)
        end

        local nl = lookup()
        local before = lookup_snapshot(nl)
        local result, reason = policy.reserve_lookups(nl, nil)
        H.equal(result, nil)
        H.equal(reason, "lookup-capacity-missing:buff_templates")
        lookup_unchanged(nl, before, "missing capacity")
    end)

    H.test("CT public #426 strict metatables are never invoked", function()
        local nl = lookup()
        setmetatable(nl, {
            __index = function() error("strict outer read") end,
            __newindex = function() error("strict outer write") end,
        })
        setmetatable(nl.deus_power_up_templates, {
            __index = function() error("strict lookup read") end,
            __newindex = function() error("strict lookup write") end,
        })
        setmetatable(nl.buff_templates, {
            __index = function() error("strict lookup read") end,
            __newindex = function() error("strict lookup write") end,
        })
        assert(reserve(nl))
        H.equal(rawget(nl.deus_power_up_templates, expected_power[10]), 12)
        H.equal(rawget(nl.buff_templates, expected_buff[19]), 21)
    end)

    H.test("CT public #426 exact identity and integrity cover all 29 rows", function()
        local a, b = lookup(), lookup()
        assert(reserve(a))
        assert(reserve(b))
        local identity = assert(policy.build_identity(Catalog, a))
        H.equal(identity, policy.build_identity(Catalog, b))
        H.truthy(identity:find("ct%-wire%-v1:29:") == 1)
        H.truthy(#identity <= 64)
        local snapshot = assert(policy.capture_integrity(a))
        H.equal(#snapshot.rows, 29)
        H.equal(policy.integrity(snapshot), true)
        local id = rawget(b.buff_templates, expected_buff[1])
        rawset(b.buff_templates, expected_buff[1], id + 500)
        H.truthy(policy.build_identity(Catalog, b) ~= identity)
        rawset(a, "buff_templates", {})
        H.equal(policy.integrity(snapshot), false)
    end)

    H.test("CT public #426 registry and runtime readiness are closed", function()
        local nl = lookup()
        assert(reserve(nl))
        local registry = {}
        for name in pairs(policy.power_up_entries()) do registry[name] = {} end
        H.equal(policy.power_registry_ready(registry), true)
        registry.foreign = {}
        H.equal(policy.power_registry_ready(registry), false)
        registry.foreign = nil
        registry.ct_meta_ammo = nil
        H.equal(policy.power_registry_ready(registry), false)
        local globals = globals_for(nl)
        H.equal(policy.catalog_ready(globals), true)
        globals.BuffTemplates.ct_miracle_of_ulric = nil
        H.equal(policy.catalog_ready(globals), false)
    end)

    H.test("CT public #426 shop clone floor validates raw identity before native", function()
        local powers = {
            exotic = {
                natural_bond = { name = "natural_bond", rarity = "exotic" },
                ct_meta_health = { name = "ct_meta_health", rarity = "exotic" },
                ct_retired = { name = "ct_retired", rarity = "exotic" },
            },
            unique = {
                ct_meta_health = { name = "ct_meta_health", rarity = "unique" },
            },
        }
        H.equal(policy.shop_power_up_decision(
            powers, "exotic", "natural_bond", 17, 0,
            "remote", false, "host", true), true)
        H.equal(policy.shop_power_up_decision(
            powers, "exotic", "ct_meta_health", 17, 0,
            "remote", false, "host", true), false)
        H.equal(policy.shop_power_up_decision(
            powers, "exotic", "ct_meta_health", 17, 0,
            "remote", true, "host", true), true)
        H.equal(policy.shop_power_up_decision(
            powers, "unique", "ct_meta_health", 17, 0,
            "remote", true, "host", true), false)
        H.equal(policy.shop_power_up_decision(
            powers, "exotic", "ct_retired", 17, 0,
            "remote", true, "host", true), false)
        H.equal(policy.shop_power_up_decision(
            powers, "exotic", "missing", 17, 0,
            "remote", true, "host", true), false)
        H.equal(policy.shop_power_up_decision(
            powers, nil, "ct_meta_health", 17, 0,
            "remote", true, "host", true), false)
        powers.exotic.ct_meta_health.rarity = "rare"
        H.equal(policy.shop_power_up_decision(
            powers, "exotic", "ct_meta_health", 17, 0,
            "remote", true, "host", true), false)
    end)

    H.test("CT public #426 shop floor validates the complete native request", function()
        local native_row = { name = "natural_bond", rarity = "exotic" }
        local ct_row = { name = "ct_meta_health", rarity = "exotic" }
        local exotic = { natural_bond = native_row, ct_meta_health = ct_row }
        local powers = { exotic = exotic }
        for _, value in ipairs({ exotic, native_row, ct_row, powers }) do
            setmetatable(value, { __index = function() error("strict shop index") end })
        end
        local snapshots = {
            powers = raw_snapshot(powers),
            exotic = raw_snapshot(exotic),
            native = raw_snapshot(native_row),
            ct = raw_snapshot(ct_row),
        }
        local function decide(name, exact, overrides)
            overrides = overrides or {}
            local client_id = rawget(overrides, "client_id")
            if client_id == nil and not rawget(overrides, "nil_client_id") then client_id = 17 end
            local discount = rawget(overrides, "discount")
            if discount == nil and not rawget(overrides, "nil_discount") then discount = 0 end
            local sender = rawget(overrides, "sender")
            if sender == nil and not rawget(overrides, "nil_sender") then sender = "remote" end
            local server_peer = rawget(overrides, "server_peer")
            if server_peer == nil and not rawget(overrides, "nil_server_peer") then
                server_peer = "host"
            end
            local receiver_server = rawget(overrides, "receiver_server")
            if receiver_server == nil then receiver_server = true end
            return policy.shop_power_up_decision(
                powers, "exotic", name, client_id, discount, sender, exact,
                server_peer, receiver_server)
        end

        H.equal(decide("natural_bond", false), true,
            "ordinary content was coupled to CT parity")
        H.equal(decide("natural_bond", false, { sender = "other" }), true,
            "known non-CT peer lost ordinary shop access")
        H.equal(decide("ct_meta_health", true), true)
        H.equal(decide("ct_meta_health", true, { discount = 10000 }), true)

        for _, case in ipairs({
            { { receiver_server = false }, "shop-sender-context-invalid" },
            { { nil_sender = true }, "shop-sender-context-invalid" },
            { { sender = "host" }, "shop-sender-context-invalid" },
            { { nil_server_peer = true }, "shop-sender-context-invalid" },
            { { nil_client_id = true }, "shop-client-id-invalid" },
            { { client_id = "17" }, "shop-client-id-invalid" },
            { { client_id = 0 / 0 }, "shop-client-id-invalid" },
            { { client_id = math.huge }, "shop-client-id-invalid" },
            { { client_id = 1.5 }, "shop-client-id-invalid" },
            { { client_id = 2147483648 }, "shop-client-id-invalid" },
            { { nil_discount = true }, "shop-discount-invalid" },
            { { discount = "0" }, "shop-discount-invalid" },
            { { discount = 0 / 0 }, "shop-discount-invalid" },
            { { discount = -math.huge }, "shop-discount-invalid" },
            { { discount = -1 }, "shop-discount-invalid" },
            { { discount = 0.5 }, "shop-discount-invalid" },
            { { discount = 10001 }, "shop-discount-invalid" },
            { { discount = -2147483649 }, "shop-discount-invalid" },
        }) do
            local allowed, reason = decide("ct_meta_health", true, case[1])
            H.equal(allowed, false)
            H.equal(reason, case[2])
        end

        -- Sender proof is decided before any mutable engine-registry read.
        local allowed, reason = policy.shop_power_up_decision(
            nil, "exotic", "ct_meta_health", 17, 0,
            "remote", false, "host", true)
        H.equal(allowed, false)
        H.equal(reason, "ct-sender-unproven")
        raw_unchanged(powers, snapshots.powers, "shop registry")
        raw_unchanged(exotic, snapshots.exotic, "shop rarity")
        raw_unchanged(native_row, snapshots.native, "shop native row")
        raw_unchanged(ct_row, snapshots.ct, "shop CT row")
    end)

    H.test("CT public #426 filters every synchronized state family", function()
        local native = power_up("natural_bond", 1)
        local custom = power_up("ct_meta_crit", 2)
        local values = { native, custom }
        local kept, removed = runtime.filter_values(policy, "power_ups", values, false)
        H.equal(removed, 1)
        H.equal(#kept, 1)
        H.equal(kept[1], native)
        local exact, exact_removed = runtime.filter_values(
            policy, "power_ups", values, true)
        H.equal(exact_removed, 0)
        H.equal(#exact, 2)
        H.equal(exact[1], native)
        H.equal(exact[2], custom)
        H.deep_equal(select(1, runtime.filter_values(policy, "bought_power_ups",
            { "ct_meta_crit", "natural_bond" }, false)), { "natural_bond" })
        H.deep_equal(select(1, runtime.filter_values(policy, "persistent_buffs",
            { "ct_miracle_of_ulric", "deus_ammo_pickup" }, false)),
            { "deus_ammo_pickup" })

        local plan = runtime.plan_state_strip(policy, {
            player = { { key = "departed", values = values } },
            persistent = { { key = "p", values = {
                "ct_miracle_of_ulric", "deus_ammo_pickup" } } },
            party = values,
            bought = { "natural_bond", "ct_meta_crit" },
        })
        H.equal(plan.removed.player, 1)
        H.equal(plan.removed.persistent, 1)
        H.equal(plan.removed.party, 1)
        H.equal(plan.removed.bought, 1)
        H.equal(plan.player[1].key, "departed")
    end)

    H.test("CT public #426 containment owns current and stale CT namespaces", function()
        local native = power_up("natural_bond", 1)
        local current = power_up("ct_meta_crit", 2)
        local stale = power_up("ct_kill_heal", 3)
        local unsafe, unsafe_removed = policy.filter_power_ups(
            { native, current, stale }, false)
        H.deep_equal(unsafe, { native })
        H.equal(unsafe_removed, 2)
        local exact, exact_removed = policy.filter_power_ups(
            { native, current, stale }, true)
        H.deep_equal(exact, { native, current })
        H.equal(exact_removed, 1)

        local buffs, buff_removed = policy.filter_persistent_buffs({
            "deus_ammo_pickup", "ct_miracle_of_ulric",
            "power_up_ct_kill_heal_exotic",
        }, true)
        H.deep_equal(buffs, { "deus_ammo_pickup", "ct_miracle_of_ulric" })
        H.equal(buff_removed, 1)
        H.equal(policy.power_up_allowed("ct_kill_heal", true), false)
        H.equal(policy.buff_allowed("power_up_ct_kill_heal_exotic", true), false)
        H.equal(policy.power_up_allowed("natural_bond", false), true)
        H.equal(policy.buff_allowed("power_up_movespeed_exotic", false), true)
    end)

    H.test("CT public #426 malformed synchronized rows fail closed", function()
        local native = power_up("natural_bond", 1)
        local cases = {
            { { [1] = native, [3] = native }, "array-sparse" },
            { { [1] = native, extra = true }, "array-key-invalid" },
            { { {} }, "power-up-name-invalid:1" },
            { { { name = "natural_bond", client_id = 1 } },
                "power-up-rarity-invalid:1" },
            { { power_up("ct_meta_crit", 2) }, nil },
            { { { name = "ct_meta_crit", rarity = "common", client_id = 2 } },
                "power-up-rarity-mismatch:1" },
            { { power_up("natural_bond", 2147483648) },
                "power-up-client-id-invalid:1" },
            { { power_up("natural_bond", -2147483649) },
                "power-up-client-id-invalid:1" },
            { { power_up("natural_bond", math.huge) },
                "power-up-client-id-invalid:1" },
        }
        for i = 1, #cases do
            local filtered, _, reason = policy.filter_power_ups(cases[i][1], true)
            if cases[i][2] == nil then
                H.truthy(type(filtered) == "table", "valid control " .. i)
            else
                H.equal(filtered, nil, "case " .. i)
                H.equal(reason, cases[i][2], "case " .. i)
            end
        end
        H.equal(policy.filter_power_up_names({ [2] = "natural_bond" }, true), nil)
        H.equal(policy.filter_persistent_buffs({ "" }, true), nil)
        local ok = pcall(runtime.plan_state_strip, policy, {
            party = { [1] = native, [3] = native },
        })
        H.equal(ok, false)

        local strict = { native }
        setmetatable(strict, {
            __index = function() error("array index") end,
            __len = function() error("array len") end,
        })
        local validated = assert(policy.filter_power_ups(strict, true))
        H.equal(validated[1], native)
    end)

    H.test("CT public #426 state strip planner bounds aggregate allocation", function()
        local half = math.floor(runtime.MAX_STATE_ENTRIES / 2) + 1
        local a, b = {}, {}
        for i = 1, half do
            a[i] = power_up("natural_bond", i)
            b[i] = power_up("natural_bond", i)
        end
        local snapshot = {
            player = {
                { key = "a", values = a },
                { key = "b", values = b },
            },
            persistent = {}, party = {}, bought = {},
        }
        local ok, reason = pcall(runtime.plan_state_strip, policy, snapshot)
        H.equal(ok, false)
        H.truthy(tostring(reason):find(
            "shared-state-entry-total-unbounded", 1, true) ~= nil)
        H.equal(snapshot.player[1].values, a)
        H.equal(snapshot.player[2].values, b)
        H.equal(#a, half)
        H.equal(#b, half)

        H.equal(pcall(runtime.plan_state_strip, policy, {
            player = { [2] = { key = "sparse", values = {} } },
            persistent = {},
        }), false)
        H.equal(pcall(runtime.plan_state_strip, policy, {
            player = { [runtime.MAX_STATE_ENTRIES + 1] = {
                key = "wide", values = {},
            } },
            persistent = {},
        }), false)
    end)

    H.test("CT public #426 encoded receiver sanitizes before vanilla decode", function()
        local wire = {
            mixed = { power_up("natural_bond", 1), power_up("ct_meta_health", 2) },
            custom = { power_up("ct_meta_health", 2) },
            native = { power_up("natural_bond", 1) },
        }
        local encoded_values = {}
        local codec = {
            decode = function(token)
                if token == "bad" then error("malformed") end
                return wire[token]
            end,
            encode = function(values)
                encoded_values[#encoded_values + 1] = values
                return "sanitized"
            end,
        }
        local sanitized, err, removed, remaining =
            runtime.sanitize_encoded_power_ups(policy, codec, "mixed", false)
        H.equal(sanitized, "sanitized")
        H.equal(err, nil)
        H.equal(removed, 1)
        H.equal(remaining, 1)
        H.equal(encoded_values[1][1], wire.mixed[1])
        local all, _, all_removed, all_remaining =
            runtime.sanitize_encoded_power_ups(policy, codec, "custom", false)
        H.equal(all, "sanitized")
        H.equal(all_removed, 1)
        H.equal(all_remaining, 0)
        H.equal(runtime.sanitize_encoded_power_ups(policy, codec, "bad", false), nil)
        H.equal(runtime.sanitize_encoded_power_ups(policy, {}, "native", false), nil)
        local exact, _, exact_removed, exact_remaining =
            runtime.sanitize_encoded_power_ups(policy, codec, "mixed", true)
        H.equal(exact, "mixed")
        H.equal(exact_removed, 0)
        H.equal(exact_remaining, 2)
    end)

    H.test("CT public #426 encoded receiver contains isolated codec failures", function()
        local decodes = 0
        local decode_error, reason = runtime.sanitize_encoded_power_ups(
            policy, {
                decode = function()
                    decodes = decodes + 1
                    error("planted decode")
                end,
                encode = function() return "unused" end,
            }, "bad", false)
        H.equal(decode_error, nil)
        H.equal(reason, "codec-decode-failed")
        H.equal(decodes, 1)

        local encode_error, encode_reason = runtime.sanitize_encoded_power_ups(
            policy, {
                decode = function()
                    return { power_up("ct_meta_health", 2) }
                end,
                encode = function() error("planted encode") end,
            }, "custom", false)
        H.equal(encode_error, nil)
        H.equal(encode_reason, "codec-encode-failed")

        local called = false
        local refused, refuse_reason = runtime.sanitize_encoded_power_ups(
            policy, {
                decode = function()
                    called = true
                    return nil, "planted-decode-refusal"
                end,
                encode = function() return "unused" end,
            }, "blocked", false)
        H.equal(refused, nil)
        H.equal(refuse_reason, "planted-decode-refusal")
        H.equal(called, true)
    end)

    H.test("CT public #426 fresh codec isolates malformed-long then short-valid", function()
        local nl = lookup()
        assert(reserve(nl))
        setmetatable(nl.deus_power_up_templates, {
            __index = function() error("strict power lookup") end,
        })
        setmetatable(nl.rarities, {
            __index = function() error("strict rarity lookup") end,
        })
        local trace = {}
        local byte_array = source_byte_array(trace)
        local codec = assert(runtime.power_up_codec(
            byte_array, identity_deflate(), nl))
        local short = assert(codec.encode({ power_up("natural_bond", 7) }))
        local malformed_long = short .. string.char(255, 3, 1, 0, 0, 0)

        -- Pinned ByteArray.write_string overwrites without truncating. Reusing
        -- one table therefore retains the longer tail; the adapter must not.
        local reused = {}
        byte_array.write_string(reused, malformed_long)
        byte_array.write_string(reused, short)
        H.equal(#reused, #malformed_long,
            "source-faithful write_string unexpectedly truncated its tail")
        trace.decode_arrays = {}

        local rejected, reject_reason = runtime.sanitize_encoded_power_ups(
            policy, codec, malformed_long, false)
        H.equal(rejected, nil)
        H.equal(reject_reason, "decoded-lookup-invalid:2")
        local accepted, accept_reason, removed, remaining =
            runtime.sanitize_encoded_power_ups(policy, codec, short, false)
        H.equal(accepted, short)
        H.equal(accept_reason, nil)
        H.equal(removed, 0)
        H.equal(remaining, 1)
        H.equal(#trace.decode_arrays, 2)
        H.truthy(trace.decode_arrays[1] ~= trace.decode_arrays[2],
            "decoder reused a byte array across attempts")
        H.equal(#trace.decode_arrays[1], #malformed_long)
        H.equal(#trace.decode_arrays[2], #short,
            "short valid decode retained phantom bytes")

        H.equal(runtime.power_up_codec(nil, identity_deflate(), nl), nil)
        H.equal(runtime.power_up_codec({}, identity_deflate(), nl), nil)
        H.equal(runtime.power_up_codec(byte_array, {}, nl), nil)
        H.equal(runtime.power_up_codec(byte_array, identity_deflate(), {}), nil)
        H.equal(runtime.sanitize_encoded_power_ups(
            policy, codec, short .. "x", false), nil,
            "misaligned decoded payload escaped")
        H.equal(runtime.sanitize_encoded_power_ups(policy, codec,
            string.rep("x", runtime.MAX_POWER_UP_ENCODED_BYTES + 1), false), nil,
            "oversized encoded payload escaped")

        local expanded_codec = assert(runtime.power_up_codec(byte_array, {
            CompressDeflate = function(_, value) return value end,
            DecompressDeflate = function()
                return string.rep("x", runtime.MAX_POWER_UP_RAW_BYTES + 6), 0
            end,
        }, nl))
        H.equal(runtime.sanitize_encoded_power_ups(
            policy, expanded_codec, "tiny", false), nil,
            "oversized decompressed payload escaped")
        local trailing_codec = assert(runtime.power_up_codec(byte_array, {
            CompressDeflate = function(_, value) return value end,
            DecompressDeflate = function(_, value) return value, 1 end,
        }, nl))
        H.equal(runtime.sanitize_encoded_power_ups(
            policy, trailing_codec, short, false), nil,
            "compressed trailing bytes escaped")

        local encoder_arrays = {}
        local throwing_byte_array = source_byte_array()
        local source_write_int32 = throwing_byte_array.write_int32
        throwing_byte_array.write_int32 = function(array, value, index)
            encoder_arrays[#encoder_arrays + 1] = array
            if #encoder_arrays == 1 then
                array[index] = 123
                error("planted partial encoder write")
            end
            return source_write_int32(array, value, index)
        end
        local throwing_codec = assert(runtime.power_up_codec(
            throwing_byte_array, identity_deflate(), nl))
        H.equal(pcall(throwing_codec.encode,
            { power_up("natural_bond", 7) }), false)
        local ok_short_encode, encoded_short = pcall(throwing_codec.encode,
            { power_up("natural_bond", 7) })
        H.equal(ok_short_encode, true)
        H.equal(type(encoded_short), "string")
        H.equal(#encoder_arrays, 2)
        H.truthy(encoder_arrays[1] ~= encoder_arrays[2],
            "encoder reused a byte array after a partial write")
    end)

    H.test("CT public #426 exact encoded state validates and strips stale rows", function()
        local encode_calls = 0
        local wire = {
            valid = { power_up("ct_meta_crit", 2) },
            stale = { power_up("ct_kill_heal", 3) },
            sparse = { [1] = power_up("natural_bond", 1),
                [3] = power_up("ct_meta_crit", 2) },
            rarity = { { name = "ct_meta_crit", rarity = "common", client_id = 2 } },
            client = { power_up("natural_bond", 2147483648) },
        }
        local codec = {
            decode = function(token) return wire[token] end,
            encode = function(values)
                encode_calls = encode_calls + 1
                H.equal(#values, 0)
                return "empty"
            end,
        }
        local valid, _, removed = runtime.sanitize_encoded_power_ups(
            policy, codec, "valid", true)
        H.equal(valid, "valid")
        H.equal(removed, 0)
        H.equal(encode_calls, 0, "valid exact bytes were re-encoded")
        local stale, _, stale_removed = runtime.sanitize_encoded_power_ups(
            policy, codec, "stale", true)
        H.equal(stale, "empty")
        H.equal(stale_removed, 1)
        H.equal(encode_calls, 1)
        H.equal(runtime.sanitize_encoded_power_ups(
            policy, codec, "sparse", true), nil)
        H.equal(runtime.sanitize_encoded_power_ups(
            policy, codec, "rarity", true), nil)
        H.equal(runtime.sanitize_encoded_power_ups(
            policy, codec, "client", true), nil)
    end)

    H.test("CT public #426 wire and sender verdicts are conjunctive", function()
        local state = { installed = true, applied = "enabled", all = true, peer = true }
        local instance = {
            is_installed = function() return state.installed end,
            applied_state = function() return state.applied end,
            all_peers_have = function() return state.all end,
            peer_has = function(_, id) return state.peer and id == "peer" end,
        }
        H.equal(runtime.wire_safe(instance, function() return true end), true)
        state.all = false
        H.equal(runtime.wire_safe(instance, function() return true end), false)
        state.all = true
        H.equal(runtime.wire_safe(instance, function() error("drift") end), false)
        H.equal(runtime.sender_exact(instance, "peer", function() return true end), true)
        H.equal(runtime.sender_exact(instance, "other", function() return true end), false)
        H.equal(runtime.sender_exact(instance, nil, function() return true end), false)
        H.equal(runtime.roster_sender_exact(
            instance, "peer", function() return true end), true)
        state.all = false
        H.equal(runtime.sender_exact(instance, "peer", function() return true end), true)
        H.equal(runtime.roster_sender_exact(
            instance, "peer", function() return true end), false)
    end)

    H.test("CT public #426 numeric receiver floors rawget unknown and unproven ids", function()
        local nl = lookup()
        assert(reserve(nl))
        local powers, buffs = nl.deus_power_up_templates, nl.buff_templates
        H.equal(runtime.lookup_receiver_decision(policy, powers, 999999,
            false, "power_up"), false)
        H.equal(runtime.lookup_receiver_decision(policy, powers,
            rawget(powers, "ct_meta_crit"), false, "power_up"), false)
        H.equal(runtime.lookup_receiver_decision(policy, powers,
            rawget(powers, "ct_meta_crit"), true, "power_up"), true)
        H.equal(runtime.lookup_receiver_decision(policy, buffs,
            rawget(buffs, "ct_miracle_of_ulric"), false, "buff"), false)
        H.equal(runtime.lookup_receiver_decision(policy, powers, 1,
            false, "power_up"), true)
        H.equal(runtime.lookup_receiver_decision(policy, powers, -1,
            true, "power_up"), false)
        H.equal(runtime.lookup_receiver_decision(policy, powers, 0 / 0,
            true, "power_up"), false)
        H.equal(runtime.lookup_receiver_decision(policy, powers, math.huge,
            true, "power_up"), false)
        H.equal(runtime.lookup_receiver_decision(policy, powers, 9007199254740992,
            true, "power_up"), false)

        local stale_id = #powers + 1
        rawset(powers, stale_id, "ct_kill_heal")
        rawset(powers, "ct_kill_heal", stale_id)
        H.equal(runtime.lookup_receiver_decision(
            policy, powers, stale_id, true, "power_up"), false)
        local stale_buff_id = #buffs + 1
        rawset(buffs, stale_buff_id, "power_up_ct_kill_heal_exotic")
        rawset(buffs, "power_up_ct_kill_heal_exotic", stale_buff_id)
        H.equal(runtime.lookup_receiver_decision(
            policy, buffs, stale_buff_id, true, "buff"), false)
    end)

    H.test("CT public #426 live buff planning deduplicates parent ids", function()
        local ids = runtime.ct_live_buff_ids(policy, {
            { id = 8, buff_template_name = "ct_miracle_of_ulric" },
            { id = 8, buff_template_name = "ct_miracle_of_ulric" },
            { id = 9, buff_template_name = "deus_ammo_pickup" },
            { id = 10, buff_template_name = "ct_meta_health_stack" },
            { id = 11, buff_template_name = "power_up_ct_kill_heal_exotic" },
        }, 5, { [10] = true })
        H.deep_equal(ids, { 8, 11 })
    end)

    H.test("CT public #426 cached lookup-id arrays strip only unproven CT rows", function()
        local nl = lookup()
        assert(reserve(nl))
        local buffs = nl.buff_templates
        local native_id = rawget(buffs, "deus_ammo_pickup")
        local ct_id = rawget(buffs, "ct_miracle_of_ulric")
        local stale_id = #buffs + 1
        rawset(buffs, stale_id, "power_up_ct_kill_heal_exotic")
        rawset(buffs, "power_up_ct_kill_heal_exotic", stale_id)

        local filtered, removed = runtime.filter_lookup_ids(
            policy, buffs, { native_id, ct_id, stale_id }, false, "buff")
        H.deep_equal(filtered, { native_id })
        H.equal(removed, 2)
        local exact, exact_removed = runtime.filter_lookup_ids(
            policy, buffs, { native_id, ct_id, stale_id }, true, "buff")
        H.deep_equal(exact, { native_id, ct_id })
        H.equal(exact_removed, 1)

        local malformed = {
            { [2] = native_id },
            { native_id, [runtime.MAX_WIRE_ARRAY_ROWS + 1] = native_id },
            { 999999 },
            { "1" },
        }
        for i = 1, #malformed do
            H.equal(runtime.filter_lookup_ids(
                policy, buffs, malformed[i], false, "buff"), nil, "case " .. i)
        end
        local strict = { native_id, ct_id }
        setmetatable(strict, { __index = function() error("array index") end })
        H.deep_equal(assert(runtime.filter_lookup_ids(
            policy, buffs, strict, false, "buff")), { native_id })
    end)

    H.test("CT public #426 native removed-buff sentinels are accepted exactly", function()
        local ids = assert(runtime.ct_live_buff_ids(policy, {
            { removed = true },
            { id = 8, buff_template_name = "ct_miracle_of_ulric" },
        }, 2))
        H.deep_equal(ids, { 8 })
        H.equal(runtime.ct_live_buff_ids(policy, {
            { removed = true, id = 8 },
        }, 1), nil)
        H.equal(runtime.ct_live_buff_ids(policy, {
            { removed = false },
        }, 1), nil)
        local sentinel = { removed = true }
        setmetatable(sentinel, { __index = function() error("sentinel index") end })
        H.deep_equal(assert(runtime.ct_live_buff_ids(policy, { sentinel }, 1)), {})
    end)

    H.test("CT public #426 active buff planning rejects unbounded malformed state", function()
        local valid = {
            { id = 1, buff_template_name = "deus_ammo_pickup" },
            { id = 2, buff_template_name = "ct_miracle_of_ulric" },
        }
        for _, count in ipairs({ -1, 0.5, math.huge, -math.huge,
                runtime.MAX_ACTIVE_BUFF_ROWS + 1 }) do
            local ids, reason = runtime.ct_live_buff_ids(policy, valid, count)
            H.equal(ids, nil)
            H.equal(reason, "active-buff-count-invalid")
        end
        local nan = 0 / 0
        H.equal(runtime.ct_live_buff_ids(policy, valid, nan), nil)
        H.equal(runtime.ct_live_buff_ids(policy, { [2] = valid[2] }, 2), nil)
        for _, bad in ipairs({
            { id = "2", buff_template_name = "ct_miracle_of_ulric" },
            { id = 2147483648, buff_template_name = "ct_miracle_of_ulric" },
            { id = 2, buff_template_name = "" },
        }) do
            H.equal(runtime.ct_live_buff_ids(policy, { bad }, 1), nil)
        end
        local strict_entry = {
            id = 3, buff_template_name = "ct_meta_health_stack",
        }
        setmetatable(strict_entry, { __index = function() error("entry index") end })
        local strict = { strict_entry }
        setmetatable(strict, { __index = function() error("list index") end })
        H.deep_equal(assert(runtime.ct_live_buff_ids(policy, strict, 1)), { 3 })
    end)

    H.test("CT public #426 stable source wires all containment owners", function()
        local function read(path)
            local f = assert(io.open(repo_root .. "/" .. path, "rb"))
            local text = f:read("*a"); f:close(); return text
        end
        local main = read("chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua")
        local owner = read("chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_peer_parity_owner.lua")
        local runtime_source = read("chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_wire_runtime.lua")
        local package = read("chaos_wastes_tweaker/resource_packages/chaos_wastes_tweaker/chaos_wastes_tweaker.package")
        local manifest = read("tools/shared_lib/manifest.psd1")
        H.truthy(main:find('local MOD_VERSION = "0.7.132-beta"', 1, true))
        H.truthy(main:find('scripts/mods/chaos_wastes_tweaker/_ct_peer_parity_owner', 1, true))
        H.truthy(main:find("mod._ct_power_up_wire_allowed(name)", 1, true))
        H.truthy(main:find("mod._ct_wire_reservation_ready", 1, true))
        H.truthy(main:find('scripts/mods/chaos_wastes_tweaker/_ct_wire_bootstrap', 1, true))
        H.truthy(main:find('mod._ct_is_modded_power_up = owned_power', 1, true))
        H.truthy(main:find('mod._ct_is_ct_buff_template = owned_buff', 1, true))
        local owner_install = assert(main:find(
            "-- Install the public #426 owner only after", 1, true))
        local owner_install_end = assert(main:find(
            "sync_host_dependent_state = function()", owner_install, true))
        local owner_install_source = main:sub(
            owner_install, owner_install_end - 1)
        local reservation_floor = assert(owner_install_source:find(
            "if mod._ct_wire_reservation_ready ~= true then", 1, true))
        local owner_load = assert(owner_install_source:find(
            'scripts/mods/chaos_wastes_tweaker/_ct_peer_parity_owner', 1, true))
        H.truthy(reservation_floor < owner_load)
        H.equal(owner_install_source:find("error(", 1, true), nil,
            "bootstrap failure must leave unrelated stable features loadable")
        local meta_start = assert(main:find(
            "local function _make_meta_proc(stack_name)", 1, true))
        local meta_finish = assert(main:find(
            "local function register_meta_boon(spec)", meta_start, true))
        local meta_proc = main:sub(meta_start, meta_finish - 1)
        H.truthy(meta_proc:find('type(mod._ct_wire_safe) ~= "function"', 1, true))
        H.truthy(meta_proc:find('buff_extension:add_buff(stack_name)', 1, true))
        H.truthy(meta_proc:find('type(mod._ct_wire_safe) ~= "function"', 1, true)
            < meta_proc:find('buff_extension:add_buff(stack_name)', 1, true))
        local isha_hook = assert(main:find(
            'mod:hook_safe("DeusSpawning", "_apply_initial_buffs"', 1, true))
        local isha_guard = assert(main:find(
            'if type(mod._ct_wire_safe) ~= "function" or not mod._ct_wire_safe() then',
            isha_hook, true))
        local isha_promote = assert(main:find(
            "if rc._ct_isha_pending and not rc._ct_isha_active then",
            isha_guard, true))
        H.truthy(isha_guard < isha_promote)
        H.truthy(owner:find('"set_bought_power_ups"', 1, true))
        H.truthy(owner:find('"set_player_persistent_buffs"', 1, true))
        H.truthy(owner:find('"rpc_deus_add_power_ups"', 1, true))
        H.truthy(owner:find("Runtime.power_up_codec(", 1, true))
        H.equal(owner:find("encoded_string_to_power_ups", 1, true), nil,
            "owner still calls the native reusable decoder")
        H.equal(owner:find("power_ups_to_encoded_string", 1, true), nil,
            "owner still treats the native encoder as a decoder reset")
        H.truthy(runtime_source:find("local bytes = {}", 1, true),
            "isolated codec does not allocate fresh byte arrays")
        H.truthy(main:find(
            'pcall(require, "scripts/utils/byte_array")', 1, true))
        H.truthy(main:find(
            'pcall(require, "scripts/utils/lib_deflate")', 1, true))
        H.truthy(owner:find('"rpc_deus_remove_power_up"', 1, true))
        local shop_hook = assert(owner:find(
            'register_hook("DeusRunController", "rpc_deus_shop_power_up_bought"',
            1, true))
        local shop_floor = assert(owner:find(
            "policy.shop_power_up_decision(", shop_hook, true))
        local shop_native = assert(owner:find(
            "return func(self, channel_id, rarity, name, client_id, discount)",
            shop_floor, true))
        H.truthy(shop_hook < shop_floor and shop_floor < shop_native,
            "shop receiver floor must run before the native pre-clone receiver")
        H.truthy(owner:sub(shop_hook, shop_native):find(
            'rawget(self, "_run_state")', 1, true))
        H.truthy(owner:sub(shop_hook, shop_native):find(
            'rawget(run_state, "_is_server") == true', 1, true))
        H.truthy(owner:sub(shop_hook, shop_native):find(
            'rawget(run_state, "_server_peer_id")', 1, true))
        H.truthy(owner:find('"SharedState", "_set_server_rpc"', 1, true))
        H.truthy(owner:find('"GameNetworkManager", "hot_join_sync"', 1, true))
        H.truthy(owner:find('"GameNetworkManager", "set_peer_synchronizing"', 1, true))
        H.truthy(owner:find('"NetworkServer", "is_network_state_fully_synced_for_peer"', 1, true))
        H.truthy(owner:find("managers.player.human_players", 1, true))
        H.equal(owner:find("managers.player.players", 1, true), nil)
        H.truthy(owner:find('"BuffSystem", "hot_join_sync"', 1, true))
        H.truthy(owner:find('"ct_426_public_hot_join_containment"', 1, true))
        H.truthy(package:find('"scripts/mods/chaos_wastes_tweaker/*"', 1, true))
        H.truthy(manifest:find("chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_lib_peer_parity.lua", 1, true))
        H.truthy(manifest:find("chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_lib_wire_catalog.lua", 1, true))
    end)
end
