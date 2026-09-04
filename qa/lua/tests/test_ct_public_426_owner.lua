-- Behavioral adapter tests for the public-stream issue #426 owner. These run
-- the actual owner against engine-shaped fakes rather than accepting source
-- strings as proof that the final writer/receiver and hot-join floors work.

return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local policy = assert(loadfile(base .. "_ct_wire_policy.lua"))()
    local runtime = assert(loadfile(base .. "_ct_wire_runtime.lua"))()
    local Catalog = assert(loadfile(base .. "_lib_wire_catalog.lua"))()
    local install_owner = assert(loadfile(base .. "_ct_peer_parity_owner.lua"))()
    local function reserve(value, buff_max)
        return policy.reserve_lookups(value, { buff = buff_max or 65535 })
    end

    local function axis(names)
        local out = {}
        for i = 1, #names do
            rawset(out, i, names[i])
            rawset(out, names[i], i)
        end
        return out
    end
    local function power_up(name, client_id)
        return { name = name, rarity = "exotic", client_id = client_id or 1 }
    end
    -- Source-faithful subset of scripts/utils/byte_array.lua. In particular,
    -- write_string overwrites its prefix without truncating a longer tail.
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
    local function shop_receiver(is_server, server_peer_id)
        return { _run_state = {
            _is_server = is_server ~= false,
            _server_peer_id = server_peer_id or "host",
        } }
    end

    local function exact_globals()
        local nl = {
            deus_power_up_templates = axis({ "natural_bond" }),
            buff_templates = axis({ "power_up_movespeed_exotic" }),
            rarities = axis({ "common", "rare", "exotic", "unique" }),
        }
        assert(reserve(nl))
        local templates, powers, buffs, registry = {}, {}, {}, {}
        for name, spec in pairs(policy.power_up_entries()) do
            templates[name] = {}
            powers[spec.rarity] = powers[spec.rarity] or {}
            powers[spec.rarity][name] = { name = name, rarity = spec.rarity }
            registry[name] = { rarity = spec.rarity }
        end
        powers.exotic.natural_bond = {
            name = "natural_bond", rarity = "exotic",
        }
        for name in pairs(policy.buff_entries()) do buffs[name] = {} end
        return nl, templates, powers, buffs, registry
    end

    local GLOBAL_NAMES = {
        "NetworkLookup", "DeusPowerUpTemplates", "DeusPowerUps",
        "BuffTemplates", "Managers", "CHANNEL_TO_PEER_ID",
        "DeusPowerUpUtils", "GameSession", "get_mod", "printf",
    }

    local function with_fixture(options, body)
        options = options or {}
        local before, present = {}, {}
        for i = 1, #GLOBAL_NAMES do
            local name = GLOBAL_NAMES[i]
            before[name] = rawget(_G, name)
            present[name] = before[name] ~= nil
        end

        local ok_all, err_all = xpcall(function()
            local nl, templates, powers, buffs, registry = exact_globals()
            local calls = {
                hooks = {}, checks = {}, commands = {}, features = {},
                removed_pools = {}, added_pools = {}, logs = {},
                require_peer = {}, forgotten = {}, native = 0,
                hook_registrations = 0, check_registrations = 0,
                command_registrations = 0,
            }
            local default_safe = options.safe == true
            local mod
            local peer_state = {
                installed = false,
                applied = options.applied
                    or (default_safe and "enabled" or "disabled"),
                all = options.all == nil and default_safe or options.all,
                peer = options.peer == nil and default_safe or options.peer,
            }
            local instance = { EXACT_MODE = true }
            function instance:is_installed() return peer_state.installed end
            function instance:applied_state() return peer_state.applied end
            function instance:all_peers_have() return peer_state.all end
            function instance:peer_has(peer_id)
                return peer_state.peer and peer_id == "remote"
            end
            function instance:require_peer(peer_id)
                calls.require_peer[#calls.require_peer + 1] = peer_id
                if options.throw_require then error("planted require_peer") end
                local exact = self:peer_has(peer_id)
                if not exact then
                    peer_state.applied = "disabled"
                    peer_state.all = false
                end
                return exact
            end
            function instance:forget_peer(peer_id)
                calls.forgotten[#calls.forgotten + 1] = peer_id
                if options.throw_forget then error("planted forget_peer") end
                if peer_id == "remote" then peer_state.peer = false end
            end
            function instance:register_gated_feature(name, feature)
                calls.features[name] = feature
                if options.throw_feature_register then
                    error("planted feature registrar")
                end
                if options.false_feature_register then return false end
            end
            function instance:install()
                local prior = rawget(mod, "update")
                rawset(mod, "update", function(dt)
                    if type(prior) == "function" then prior(dt) end
                end)
                if options.throw_install then error("planted install") end
                if options.fail_install then return false end
                peer_state.installed = true
                return true
            end

            mod = {
                update = function() calls.previous_updates =
                    (calls.previous_updates or 0) + 1 end,
            }
            local original_update = mod.update
            function mod:dofile(path)
                if path:find("_ct_wire_runtime", 1, true) then return runtime end
                if path:find("_lib_wire_catalog", 1, true) then return Catalog end
                if path:find("_lib_peer_parity", 1, true) then
                    if options.bad_factory then return nil end
                    return function(_, opts)
                        local sequences = rawget(mod, "_peer_parity_epoch_sequences")
                        if type(sequences) ~= "table" then
                            sequences = {}
                            rawset(mod, "_peer_parity_epoch_sequences", sequences)
                        end
                        rawset(sequences, opts.channel,
                            (tonumber(rawget(sequences, opts.channel)) or 0) + 1)
                        instance.WIRE_IDENTITY = opts.wire_identity
                        return instance
                    end
                end
                error("unexpected dofile: " .. tostring(path))
            end
            function mod:hook(class_name, method_name, callback)
                calls.hook_registrations = calls.hook_registrations + 1
                calls.hooks[class_name .. "." .. method_name] = callback
                if calls.hook_registrations == options.throw_hook_at then
                    error("planted hook registrar")
                end
                if calls.hook_registrations == options.false_hook_at then
                    return false
                end
            end
            function mod:command(name, _, callback)
                calls.command_registrations = calls.command_registrations + 1
                calls.commands[name] = callback
                if options.throw_command then error("planted command registrar") end
                if options.false_command then return false end
            end
            function mod:echo(message) calls.echo = message end
            rawset(mod, "_ct_wire_policy", policy)
            rawset(mod, "_ct_wire_reservation_ready", true)

            local deps = {
                rpc_schema = 1,
                injected_dormants = registry,
                trait_boons = {},
                collect_setting_ids = function()
                    return policy.runtime_gate_setting_ids()
                end,
                rt_register = function(name, callback)
                    calls.check_registrations = calls.check_registrations + 1
                    calls.checks[name] = callback
                    if calls.check_registrations == options.throw_check_at then
                        error("planted runtime-check registrar")
                    end
                    if calls.check_registrations == options.false_check_at then
                        return false
                    end
                end,
                add_dormant_to_pool = function(name, rarity)
                    calls.added_pools[#calls.added_pools + 1] = { name, rarity }
                end,
                remove_dormant_from_pool = function(name, rarity)
                    calls.removed_pools[#calls.removed_pools + 1] = { name, rarity }
                    if options.throw_pool_remove
                            or (options.throw_pool_remove_after_install
                                and peer_state.installed) then
                        error("planted pool removal")
                    end
                    if options.false_pool_remove then return false end
                end,
                register_trait_boon = function() end,
                byte_array = options.byte_array
                    or source_byte_array(options.codec_trace),
                lib_deflate = options.lib_deflate or identity_deflate(),
            }
            if options.missing_byte_array then deps.byte_array = nil end
            if options.missing_lib_deflate then deps.lib_deflate = nil end

            rawset(_G, "NetworkLookup", nl)
            rawset(_G, "DeusPowerUpTemplates", templates)
            rawset(_G, "DeusPowerUps", powers)
            rawset(_G, "BuffTemplates", buffs)
            rawset(_G, "Managers", { player = { is_server = true } })
            rawset(_G, "CHANNEL_TO_PEER_ID", { [9] = "remote" })
            rawset(_G, "get_mod", function() return nil end)
            rawset(_G, "printf", function(fmt, ...)
                calls.logs[#calls.logs + 1] = string.format(fmt, ...)
            end)
            rawset(_G, "DeusPowerUpUtils", {
                encoded_string_to_power_ups = function()
                    error("native reusable decoder must not be called")
                end,
                power_ups_to_encoded_string = function()
                    error("native encoder must not be used as a reset")
                end,
            })

            local install_ok, install_result = pcall(install_owner, mod, deps)
            if options.expect_install_failure then
                H.equal(install_ok, false, "owner unexpectedly committed")
                H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), false)
            else
                if not install_ok then error(install_result) end
                H.equal(install_result, true)
                H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), true)
            end
            local fixture_codec = assert(runtime.power_up_codec(
                source_byte_array(), identity_deflate(), nl))
            body({
                mod = mod, calls = calls, hooks = calls.hooks,
                instance = instance, peer_state = peer_state,
                nl = nl, deps = deps, install_error = install_result,
                original_update = original_update,
                encode_power_ups = fixture_codec.encode,
            })
        end, debug.traceback)

        for i = 1, #GLOBAL_NAMES do
            local name = GLOBAL_NAMES[i]
            rawset(_G, name, present[name] and before[name] or nil)
        end
        if not ok_all then error(err_all) end
    end

    local function native_counter(fixture, ...)
        fixture.calls.native = fixture.calls.native + 1
        return ...
    end

    local function make_run_state(power_values, persistent_values)
        local power = power_values or {}
        local persistent = persistent_values or {}
        local server_state = {
            power_ups = { owner = { [1] = { [2] = { [3] = {
                [0] = power,
            } } } } },
            persistent_buffs = { owner = { [1] = { [2] = { [3] = {
                [0] = persistent,
            } } } } },
        }
        local state = {
            _shared_state = { _server_state = server_state },
            _party = {}, _bought = {},
        }
        function state:get_party_power_ups() return self._party end
        function state:get_bought_power_ups() return self._bought end
        function state:set_player_power_ups(peer, local_id, profile, career, values)
            self._shared_state._server_state.power_ups[peer][local_id]
                [profile][career][0] = values
        end
        function state:set_player_persistent_buffs(peer, local_id, profile, career, values)
            self._shared_state._server_state.persistent_buffs[peer][local_id]
                [profile][career][0] = values
        end
        function state:set_party_power_ups(values) self._party = values end
        function state:set_bought_power_ups(values) self._bought = values end
        return state
    end

    local function attach_run_state(state, buff_system)
        local controller = { _run_state = state }
        rawset(_G, "Managers", {
            player = { is_server = true },
            mechanism = { game_mechanism = function()
                return { get_deus_run_controller = function() return controller end }
            end },
            state = buff_system and { entity = { system = function(_, name)
                return name == "buff_system" and buff_system or nil
            end } } or nil,
        })
        return controller
    end

    local function attach_game_object_state(state, values, options)
        options = options or {}
        local controller, unit = { _run_state = state }, {}
        local game = { fields = { [42] = { network_buff_ids = values } } }
        rawset(_G, "GameSession", {
            game_object_field = function(session, id, key)
                if options.throw_reader then error("planted game-object reader") end
                return session.fields[id][key]
            end,
            set_game_object_field = function(session, id, key, next_values)
                options.write_attempts = (options.write_attempts or 0) + 1
                if options.throw_writer_once and options.write_attempts == 1 then
                    error("planted game-object writer")
                end
                session.fields[id][key] = next_values
            end,
        })
        rawset(_G, "Managers", {
            player = {
                is_server = true,
                human_players = function()
                    return { owner = { player_unit = unit } }
                end,
                players = function()
                    error("bot-inclusive roster must never be queried")
                end,
            },
            mechanism = { game_mechanism = function()
                return { get_deus_run_controller = function() return controller end }
            end },
            state = {
                network = {
                    game_session = game,
                    unit_storage = {
                        go_id = function(_, candidate)
                            if options.throw_go_id then error("planted go id") end
                            return candidate == unit and 42 or nil
                        end,
                    },
                },
            },
        })
        return controller, game, unit, options
    end

    H.test("CT public #426 owner publication is one terminal transaction", function()
        local public_fields = {
            "_ct_wire_catalog_identity", "_ct_wire_catalog_error",
            "_ct_wire_catalog_integrity", "_ct_wire_catalog_power_count",
            "_ct_wire_catalog_buff_count", "_ct_peer_parity",
            "_ct_strip_modded_content", "_ct_census_modded_content",
            "_ct_force_wire_inert", "_ct_wire_runtime_gate_registered",
            "_ct_wire_hook_markers", "_peer_parity_epoch_sequences",
        }
        local function assert_rolled(f, label)
            H.equal(rawget(f.mod, "_ct_peer_parity_owner_installed"), false,
                label .. " marker")
            H.equal(rawget(f.mod, "update"), f.original_update,
                label .. " update")
            for i = 1, #public_fields do
                H.equal(rawget(f.mod, public_fields[i]), nil,
                    label .. " leaked " .. public_fields[i])
            end
            local hook = f.hooks["DeusRunState.set_player_power_ups"]
            if hook then
                local native = power_up("natural_bond", 1)
                local original = { native, power_up("ct_meta_crit", 2) }
                local observed
                hook(function(_, _, _, _, _, values) observed = values end,
                    {}, "owner", 1, 2, 3, original)
                H.equal(#observed, 1, label .. " retained hook leaked CT state")
                H.equal(observed[1], native,
                    label .. " retained hook changed native state")
            end
            local command = f.calls.commands.ct_426_diag
            if command then
                command()
                H.equal(f.calls.echo, nil, label .. " retained command was not inert")
            end
            for _, check in pairs(f.calls.checks) do
                H.equal(check(), "public wire owner did not commit",
                    label .. " retained check was not inert")
            end
        end

        local hook_count, check_count, command_count
        with_fixture({}, function(f)
            hook_count = f.calls.hook_registrations
            check_count = f.calls.check_registrations
            command_count = f.calls.command_registrations
        end)
        H.truthy(hook_count > 0)
        H.equal(check_count, 4)
        H.equal(command_count, 1)
        local function assert_all_attempted(f, label)
            H.equal(f.calls.hook_registrations, hook_count, label .. " hooks")
            H.equal(f.calls.check_registrations, check_count, label .. " checks")
            H.equal(f.calls.command_registrations, command_count, label .. " commands")
            H.truthy(f.calls.features.ct_public_modded_boons ~= nil,
                label .. " feature")
        end
        for i = 1, hook_count do
            with_fixture({ throw_hook_at = i, expect_install_failure = true },
                function(f)
                    assert_rolled(f, "hook " .. i)
                    assert_all_attempted(f, "hook " .. i)
                end)
            with_fixture({ false_hook_at = i, expect_install_failure = true },
                function(f)
                    assert_rolled(f, "false hook " .. i)
                    assert_all_attempted(f, "false hook " .. i)
                end)
        end
        for _, option in ipairs({ "throw_command", "false_command" }) do
            with_fixture({ [option] = true, expect_install_failure = true },
                function(f)
                    assert_rolled(f, option)
                    assert_all_attempted(f, option)
                end)
        end
        for i = 1, 4 do
            with_fixture({ throw_check_at = i, expect_install_failure = true },
                function(f)
                    assert_rolled(f, "check " .. i)
                    assert_all_attempted(f, "check " .. i)
                end)
            with_fixture({ false_check_at = i, expect_install_failure = true },
                function(f)
                    assert_rolled(f, "false check " .. i)
                    assert_all_attempted(f, "false check " .. i)
                end)
        end
        for _, option in ipairs({ "throw_feature_register",
                "false_feature_register" }) do
            with_fixture({ [option] = true, expect_install_failure = true },
                function(f)
                    assert_rolled(f, option)
                    assert_all_attempted(f, option)
                    local feature = f.calls.features.ct_public_modded_boons
                    if feature then feature.on_enable(); feature.on_disable() end
                end)
        end
        for _, option in ipairs({ "throw_pool_remove", "false_pool_remove" }) do
            with_fixture({ [option] = true, expect_install_failure = true },
                function(f)
                    assert_rolled(f, option)
                    assert_all_attempted(f, option)
                    local purchase_calls, buff_calls = 0, 0
                    f.hooks["DeusRunController._try_buy_power_up"](
                        function() purchase_calls = purchase_calls + 1 end,
                        {}, {}, power_up("ct_meta_crit", 2), 0)
                    f.hooks["BuffSystem.add_buff"](
                        function() buff_calls = buff_calls + 1 end,
                        {}, {}, "ct_miracle_of_ulric", {}, false, 1, {})
                    H.equal(purchase_calls, 0)
                    H.equal(buff_calls, 0)
                end)
        end
        for _, option in ipairs({ "throw_install", "fail_install" }) do
            with_fixture({ [option] = true, expect_install_failure = true },
                function(f) assert_rolled(f, option) end)
        end
    end)

    H.test("CT public #426 missing beacon factory is terminal", function()
        with_fixture({ bad_factory = true, expect_install_failure = true }, function(f)
            H.equal(rawget(f.mod, "_ct_peer_parity_owner_installed"), false)
            H.equal(rawget(f.mod, "_ct_peer_parity"), nil)
            H.equal(rawget(f.mod, "update"), f.original_update)
        end)
    end)

    H.test("CT public #426 named runtime diagnostics exercise live owners", function()
        with_fixture({ safe = true }, function(f)
            local names = {
                "ct_426_public_exact_catalog",
                "ct_426_public_receiver_floors",
                "ct_426_public_hot_join_containment",
                "ct_426_public_gate_surface",
            }
            for i = 1, #names do
                H.equal(f.calls.checks[names[i]](), nil, names[i])
            end
            f.calls.commands.ct_426_diag()
            H.truthy(type(f.calls.echo) == "string")
            H.truthy(#f.calls.logs > 0)
        end)
    end)

    H.test("CT public #426 owner gates actual writers before mutation", function()
        with_fixture({ safe = false }, function(f)
            local custom = power_up("ct_meta_crit", 2)
            local native = power_up("natural_bond", 1)
            local received
            f.hooks["DeusRunState.set_player_power_ups"](function(_, _, _, _, _, values)
                received = values
                return "written"
            end, {}, "owner", 1, 2, 3, { native, custom })
            H.equal(#received, 1)
            H.equal(received[1], native)

            local bought
            f.hooks["DeusRunState.set_bought_power_ups"](function(_, values)
                bought = values
            end, {}, { "natural_bond", "ct_meta_crit" })
            H.deep_equal(bought, { "natural_bond" })

            local purchase_calls = 0
            local purchase = f.hooks["DeusRunController._try_buy_power_up"](
                function() purchase_calls = purchase_calls + 1; return true end,
                {}, {}, custom, 0)
            H.equal(purchase, false)
            H.equal(purchase_calls, 0)

            local buff_calls = 0
            f.hooks["BuffSystem.add_buff"](
                function() buff_calls = buff_calls + 1 end,
                {}, {}, "ct_miracle_of_ulric", {}, false, 1, {})
            H.equal(buff_calls, 0)
            f.hooks["BuffSystem.add_buff"](
                function() buff_calls = buff_calls + 1 end,
                {}, {}, "power_up_movespeed_exotic", {}, false, 1, {})
            H.equal(buff_calls, 1)
        end)
    end)

    H.test("CT public #426 owner receiver floors sanitize before native decode", function()
        with_fixture({ safe = false }, function(f)
            local mixed = assert(f.encode_power_ups({
                power_up("natural_bond", 1), power_up("ct_meta_health", 2),
            }))
            local custom = assert(f.encode_power_ups({
                power_up("ct_meta_health", 2),
            }))
            local native = assert(f.encode_power_ups({
                power_up("natural_bond", 1),
            }))
            local direct
            f.hooks["DeusRunController.rpc_deus_add_power_ups"](
                function(_, _, value) direct = value end, {}, 9, mixed, "node")
            H.equal(direct, native)
            direct = nil
            f.hooks["DeusRunController.rpc_deus_add_power_ups"](
                function(_, _, value) direct = value end, {}, 9, custom, "node")
            H.equal(direct, nil, "all-custom payload reached native decoder")

            local power_id = rawget(f.nl.deus_power_up_templates, "ct_meta_health")
            local remove_calls = 0
            f.hooks["DeusRunController.rpc_deus_remove_power_up"](
                function() remove_calls = remove_calls + 1 end, {}, 9, power_id)
            f.hooks["DeusRunController.rpc_deus_remove_power_up"](
                function() remove_calls = remove_calls + 1 end, {}, 9, 999999)
            H.equal(remove_calls, 0)

            local buff_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local buff_calls = 0
            f.hooks["BuffSystem.rpc_add_buff"](
                function() buff_calls = buff_calls + 1 end,
                {}, 9, 1, buff_id, 1, 1, false)
            f.hooks["BuffSystem.rpc_add_buff"](
                function() buff_calls = buff_calls + 1 end,
                {}, 9, 1, 999999, 1, 1, false)
            H.equal(buff_calls, 0)

            local shared_value
            local shared = {
                _original_context = "deus_run_state_test",
                _is_server = false,
                _server_peer_id = "remote",
                _key_type_lookup = { [4] = "power_ups" },
                _spec = { server = { power_ups = {
                    decode = function()
                        return { power_up("natural_bond", 1),
                            power_up("ct_meta_health", 2) }
                    end,
                    encode = function(values)
                        H.equal(#values, 1)
                        return "shared-sanitized"
                    end,
                } } },
            }
            f.hooks["SharedState._set_server_rpc"](
                function(_, _, _, _, _, _, _, _, value) shared_value = value end,
                shared, 9, 4, "owner", 1, 2, 3, 4, "mixed")
            H.equal(shared_value, "shared-sanitized")
        end)
    end)

    H.test("CT public #426 deus-add isolates malformed-long then short-valid", function()
        local trace = {}
        with_fixture({ safe = false, codec_trace = trace }, function(f)
            local short = assert(f.encode_power_ups({
                power_up("natural_bond", 1),
            }))
            local malformed_long = short .. string.char(255, 3, 1, 0, 0, 0)
            local native = {}
            local add = f.hooks["DeusRunController.rpc_deus_add_power_ups"]
            add(function(_, _, value) native[#native + 1] = value end,
                {}, 9, malformed_long, "node")
            H.equal(#native, 0, "malformed packet reached the native receiver")

            add(function(_, _, value) native[#native + 1] = value end,
                {}, 9, short, "node")
            H.deep_equal(native, { short })
            H.equal(#trace.decode_arrays, 2)
            H.truthy(trace.decode_arrays[1] ~= trace.decode_arrays[2],
                "actual owner callback reused decoder storage")
            H.equal(#trace.decode_arrays[1], #malformed_long)
            H.equal(#trace.decode_arrays[2], #short,
                "short valid callback retained phantom bytes")
        end)
    end)

    H.test("CT public #426 isolated codec dependencies fail owner closed", function()
        local cases = {
            { missing_byte_array = true },
            { missing_lib_deflate = true },
            { byte_array = {} },
            { lib_deflate = {} },
        }
        for i = 1, #cases do
            local options = cases[i]
            options.expect_install_failure = true
            with_fixture(options, function(f)
                H.equal(next(f.hooks), nil,
                    "codec dependency failure registered hooks in case " .. i)
                H.equal(rawget(f.mod, "_ct_wire_safe"), nil,
                    "codec dependency failure published a gate in case " .. i)
            end)
        end
    end)

    H.test("CT public #426 isolated codec operation failures drop before native", function()
        with_fixture({ safe = false, lib_deflate = {
            CompressDeflate = function(_, value) return value end,
            DecompressDeflate = function() error("planted decompressor failure") end,
        } }, function(f)
            local native = 0
            f.hooks["DeusRunController.rpc_deus_add_power_ups"](
                function() native = native + 1 end, {}, 9, "bad", "node")
            H.equal(native, 0)
        end)

        with_fixture({ safe = false, lib_deflate = {
            CompressDeflate = function() error("planted compressor failure") end,
            DecompressDeflate = function(_, value) return value, 0 end,
        } }, function(f)
            local mixed = assert(f.encode_power_ups({
                power_up("natural_bond", 1), power_up("ct_meta_health", 2),
            }))
            local native = 0
            f.hooks["DeusRunController.rpc_deus_add_power_ups"](
                function() native = native + 1 end, {}, 9, mixed, "node")
            H.equal(native, 0)
        end)
    end)

    H.test("CT public #426 shop receiver floor runs before vanilla clone", function()
        with_fixture({ safe = false }, function(f)
            local native = {}
            local hook = f.hooks[
                "DeusRunController.rpc_deus_shop_power_up_bought"]
            local function call(rarity, name)
                hook(function(_, _, got_rarity, got_name)
                    native[#native + 1] = { got_rarity, got_name }
                end, shop_receiver(), 9, rarity, name, 17, 0)
            end
            call("exotic", "ct_meta_health")
            H.equal(#native, 0, "unproven current CT row reached native clone")
            call("exotic", "natural_bond")
            H.deep_equal(native, { { "exotic", "natural_bond" } })
        end)

        with_fixture({ safe = true }, function(f)
            local native = {}
            local hook = f.hooks[
                "DeusRunController.rpc_deus_shop_power_up_bought"]
            local powers = rawget(_G, "DeusPowerUps")
            powers.exotic.ct_retired = {
                name = "ct_retired", rarity = "exotic",
            }
            powers.unique.ct_meta_health = {
                name = "ct_meta_health", rarity = "unique",
            }
            local function call(rarity, name)
                hook(function(_, _, got_rarity, got_name)
                    native[#native + 1] = { got_rarity, got_name }
                end, shop_receiver(), 9, rarity, name, 17, 0)
            end
            call("exotic", "ct_retired")
            call("unique", "ct_meta_health")
            call("exotic", "ct_meta_health")
            H.deep_equal(native, { { "exotic", "ct_meta_health" } })
            powers.exotic.ct_meta_health = nil
            call("exotic", "ct_meta_health")
            call(nil, "ct_meta_health")
            H.equal(#native, 1, "malformed shop identity reached native clone")
        end)
    end)

    H.test("CT public #426 SharedState validates exact host bytes and authority", function()
        local rows = {
            valid = { power_up("ct_meta_health", 2) },
            stale = { power_up("ct_kill_heal", 3) },
            malformed = {
                { name = "ct_meta_health", rarity = "common", client_id = 2 },
            },
            sparse = { [1] = power_up("natural_bond", 1),
                [3] = power_up("ct_meta_health", 2) },
        }
        with_fixture({ safe = true }, function(f)
            rawget(_G, "CHANNEL_TO_PEER_ID")[10] = "other"
            local encode_calls, received = 0, {}
            local shared = {
                _original_context = "deus_run_state_test",
                _is_server = false,
                _server_peer_id = "remote",
                _key_type_lookup = { [4] = "power_ups" },
                _spec = { server = { power_ups = {
                    decode = function(token) return rows[token] end,
                    encode = function(values)
                        encode_calls = encode_calls + 1
                        H.equal(#values, 0)
                        return "empty"
                    end,
                } } },
            }
            local hook = f.hooks["SharedState._set_server_rpc"]
            local function native(_, _, _, _, _, _, _, _, value)
                received[#received + 1] = value
            end
            hook(native, shared, 9, 4, "owner", 1, 2, 3, 0, "valid")
            H.deep_equal(received, { "valid" })
            H.equal(encode_calls, 0, "valid exact bytes were re-encoded")
            hook(native, shared, 9, 4, "owner", 1, 2, 3, 0, "stale")
            H.deep_equal(received, { "valid", "empty" })
            H.equal(encode_calls, 1)
            hook(native, shared, 9, 4, "owner", 1, 2, 3, 0, "malformed")
            hook(native, shared, 9, 4, "owner", 1, 2, 3, 0, "sparse")
            H.equal(#received, 2)

            hook(native, shared, 10, 4, "owner", 1, 2, 3, 0, "valid")
            H.equal(#received, 2, "non-host injected server state")
            shared._is_server = true
            hook(native, shared, 9, 4, "owner", 1, 2, 3, 0, "valid")
            H.equal(#received, 2, "host accepted client server-state mutation")
            shared._is_server = false
            hook(native, shared, 99, 4, "owner", 1, 2, 3, 0, "valid")
            H.equal(#received, 2, "unmapped sender reached native")

            shared._original_context = "inventory_state"
            hook(native, shared, 10, 4, "owner", 1, 2, 3, 0, "opaque")
            H.equal(received[#received], "opaque",
                "unrelated SharedState context was intercepted")
        end)
    end)

    H.test("CT public #426 unproven authoritative host full-state is sanitized", function()
        with_fixture({ safe = false }, function(f)
            local received
            local shared = {
                _original_context = "deus_run_state_test",
                _is_server = false,
                _server_peer_id = "remote",
                _key_type_lookup = { [4] = "power_ups" },
                _spec = { server = { power_ups = {
                    decode = function()
                        return { power_up("ct_meta_health", 2) }
                    end,
                    encode = function(values)
                        H.equal(#values, 0)
                        return "empty"
                    end,
                } } },
            }
            f.hooks["SharedState._set_server_rpc"](
                function(_, _, _, _, _, _, _, _, value) received = value end,
                shared, 9, 4, "owner", 1, 2, 3, 0, "custom")
            H.equal(received, "empty")
        end)
    end)

    H.test("CT public #426 SharedState codec failures never reach native", function()
        with_fixture({ safe = false }, function(f)
            local modes = { "decode-throw", "encode-throw", "encode-nil",
                "encode-wrong-type" }
            for i = 1, #modes do
                local mode, native = modes[i], 0
                local shared = {
                    _original_context = "deus_run_state_test",
                    _is_server = false,
                    _server_peer_id = "remote",
                    _key_type_lookup = { [4] = "power_ups" },
                    _spec = { server = { power_ups = {
                        decode = function()
                            if mode == "decode-throw" then error("decode") end
                            return { power_up("ct_meta_health", 2) }
                        end,
                        encode = function()
                            if mode == "encode-throw" then error("encode") end
                            if mode == "encode-nil" then return nil end
                            return {}
                        end,
                    } } },
                }
                f.hooks["SharedState._set_server_rpc"](
                    function() native = native + 1 end,
                    shared, 9, 4, "owner", 1, 2, 3, 0, "encoded")
                H.equal(native, 0, mode)
            end
        end)
    end)

    H.test("CT public #426 exact receiver proof precedes local gate settle", function()
        with_fixture({ applied = "disabled", all = true, peer = true }, function(f)
            local shared_value
            local shared = {
                _original_context = "deus_run_state_test",
                _is_server = false,
                _server_peer_id = "remote",
                _key_type_lookup = { [4] = "power_ups" },
                _spec = { server = { power_ups = {
                    decode = function()
                        return { power_up("ct_meta_health", 2) }
                    end,
                    encode = function() error("exact bytes must not re-encode") end,
                } } },
            }
            f.hooks["SharedState._set_server_rpc"](
                function(_, _, _, _, _, _, _, _, value) shared_value = value end,
                shared, 9, 4, "owner", 1, 2, 3, 0, "exact-bytes")
            H.equal(shared_value, "exact-bytes")

            local written
            f.hooks["DeusRunState.set_player_power_ups"](
                function(_, _, _, _, _, values) written = values end,
                {}, "owner", 1, 2, 3,
                { power_up("natural_bond", 1), power_up("ct_meta_health", 2) })
            H.equal(#written, 1, "producer escaped before local gate settled")
            H.equal(written[1].name, "natural_bond")
        end)
    end)

    H.test("CT public #426 exact peers retain cataloged writer and receiver rows", function()
        with_fixture({ safe = true }, function(f)
            local received
            f.hooks["DeusRunState.set_player_power_ups"](
                function(_, _, _, _, _, values) received = values end,
                {}, "owner", 1, 2, 3, { power_up("ct_meta_health", 2) })
            H.equal(received[1].name, "ct_meta_health")
            local exact = assert(f.encode_power_ups({
                power_up("ct_meta_health", 2),
            }))
            local direct
            f.hooks["DeusRunController.rpc_deus_add_power_ups"](
                function(_, _, value) direct = value end, {}, 9, exact, "node")
            H.equal(direct, exact)
            local buff_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local buff_calls = 0
            f.hooks["BuffSystem.rpc_add_buff"](
                function() buff_calls = buff_calls + 1 end,
                {}, 9, 1, buff_id, 1, 1, false)
            H.equal(buff_calls, 1)
        end)
    end)

    H.test("CT public #426 host buff relays require the complete exact roster", function()
        with_fixture({ applied = "enabled", all = false, peer = true }, function(f)
            local buff_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local methods = {
                "rpc_add_buff", "rpc_add_buff_synced",
                "rpc_add_buff_synced_relay", "rpc_add_buff_synced_params",
                "rpc_add_buff_synced_relay_params",
                "rpc_add_volume_buff_multiplier", "rpc_remove_volume_buff",
            }
            for i = 1, #methods do
                local calls = 0
                f.hooks["BuffSystem." .. methods[i]](
                    function() calls = calls + 1 end,
                    { is_server = true }, 9, 1, buff_id, 2, 3, 4)
                H.equal(calls, 0, methods[i] .. " relayed into an unproven roster")
            end
            local client_calls = 0
            f.hooks["BuffSystem.rpc_add_buff"](
                function() client_calls = client_calls + 1 end,
                { is_server = false }, 9, 1, buff_id, 2, 3, false)
            H.equal(client_calls, 1,
                "non-relaying exact client receiver was tied to unrelated peers")
            f.peer_state.all = true
            local host_calls = 0
            f.hooks["BuffSystem.rpc_add_buff"](
                function() host_calls = host_calls + 1 end,
                { is_server = true }, 9, 1, buff_id, 2, 3, false)
            H.equal(host_calls, 1)
        end)
    end)

    H.test("CT public #426 Deus mutation RPCs prove gate and exact sender", function()
        with_fixture({ safe = true }, function(f)
            local native_payload = assert(f.encode_power_ups({
                power_up("natural_bond", 1),
            }))
            local custom_payload = assert(f.encode_power_ups({
                power_up("ct_meta_health", 2),
            }))
            local add_values = {}
            local add = f.hooks["DeusRunController.rpc_deus_add_power_ups"]
            add(function(_, _, value) add_values[#add_values + 1] = value end,
                {}, 10, custom_payload, "node")
            add(function(_, _, value) add_values[#add_values + 1] = value end,
                {}, 10, native_payload, "node")
            H.deep_equal(add_values, { native_payload })

            local power_id = rawget(
                f.nl.deus_power_up_templates, "ct_meta_health")
            local native_id = rawget(
                f.nl.deus_power_up_templates, "natural_bond")
            local removed = {}
            local remove = f.hooks["DeusRunController.rpc_deus_remove_power_up"]
            remove(function(_, _, id) removed[#removed + 1] = id end,
                {}, 10, power_id)
            remove(function(_, _, id) removed[#removed + 1] = id end,
                {}, 10, native_id)
            H.deep_equal(removed, { native_id })

            add(function(_, _, value) add_values[#add_values + 1] = value end,
                {}, 9, custom_payload, "node")
            remove(function(_, _, id) removed[#removed + 1] = id end,
                {}, 9, power_id)
            H.equal(add_values[#add_values], custom_payload)
            H.equal(removed[#removed], power_id)

            f.instance:forget_peer("remote")
            local add_count, remove_count = #add_values, #removed
            add(function(_, _, value) add_values[#add_values + 1] = value end,
                {}, 9, custom_payload, "node")
            remove(function(_, _, id) removed[#removed + 1] = id end,
                {}, 9, power_id)
            H.equal(#add_values, add_count, "forgotten sender added CT state")
            H.equal(#removed, remove_count, "forgotten sender removed CT state")
        end)
    end)

    H.test("CT public #426 delayed CT remove cannot delete the last native boon", function()
        with_fixture({ applied = "disabled", all = false, peer = true }, function(f)
            local live = { "natural_bond", "deus_larger_clip" }
            local power_id = rawget(
                f.nl.deus_power_up_templates, "ct_meta_health")
            f.hooks["DeusRunController.rpc_deus_remove_power_up"](
                function()
                    live[#live] = nil -- mirrors vanilla's -1 fallback damage
                end, {}, 9, power_id)
            H.deep_equal(live, { "natural_bond", "deus_larger_clip" })
        end)
    end)

    H.test("CT public #426 strip covers departed state and both live buff families", function()
        with_fixture({ safe = false }, function(f)
            local native = power_up("natural_bond", 1)
            local custom = power_up("ct_meta_crit", 2)
            local player_written, persistent_written, party_written, bought_written
            local party_state = { native, custom }
            local bought_state = { "ct_meta_crit", "natural_bond" }
            local state = {}
            state._shared_state = { _server_state = {
                    power_ups = { departed = { [1] = { [2] = { [3] = {
                        [0] = { native, custom },
                    } } } } },
                    persistent_buffs = { departed = { [1] = { [2] = { [3] = {
                        [0] = { "ct_miracle_of_ulric", "deus_ammo_pickup" },
                    } } } } },
                } }
            state.get_party_power_ups = function() return party_state end
            state.get_bought_power_ups = function() return bought_state end
            state.set_player_power_ups = function(_, peer, local_id, profile, career, values)
                    player_written = { peer, local_id, profile, career, values }
                    state._shared_state._server_state.power_ups[peer][local_id]
                        [profile][career][0] = values
                end
            state.set_player_persistent_buffs = function(_, peer, local_id, profile, career, values)
                    persistent_written = { peer, local_id, profile, career, values }
                    state._shared_state._server_state.persistent_buffs[peer][local_id]
                        [profile][career][0] = values
                end
            state.set_party_power_ups = function(_, values)
                    party_written, party_state = values, values
                end
            state.set_bought_power_ups = function(_, values)
                    bought_written, bought_state = values, values
                end
            local controller = {
                _run_state = state,
                _ct_isha_pending = "ct_miracle_of_isha_wounds",
                _ct_isha_active = "ct_miracle_of_isha_aegis",
                _ct_isha_active_level = "node",
            }
            local removed_server, removed_local = {}, {}
            local active_values = {
                { id = 7, buff_template_name = "ct_miracle_of_ulric" },
                { id = 8, buff_template_name = "ct_meta_health_stack" },
                { id = 9, buff_template_name = "deus_ammo_pickup" },
            }
            local extension = {
                active_buffs = function()
                    return active_values, #active_values
                end,
            }
            local unit = {}
            local buff_system = {
                server_controlled_buffs = { [unit] = {
                    [12] = { template_name = "ct_miracle_of_ulric", local_buff_id = 7 },
                } },
                active_buff_units = { [unit] = extension },
                remove_server_controlled_buff = function(self, owner, id)
                    removed_server[#removed_server + 1] = { owner, id }
                    self.server_controlled_buffs[owner][id] = nil
                    for i = #active_values, 1, -1 do
                        if active_values[i].id == 7 then
                            active_values[i] = { removed = true }
                        end
                    end
                end,
            }
            -- Make removals observable to the owner's mandatory post-commit
            -- residual verification.
            extension.remove_buff = function(_, id, skip_net_sync)
                removed_local[#removed_local + 1] = { id, skip_net_sync }
                for i = #active_values, 1, -1 do
                    if active_values[i].id == id then
                        active_values[i] = { removed = true }
                    end
                end
            end
            rawset(_G, "Managers", {
                player = { is_server = true },
                mechanism = { game_mechanism = function()
                    return { get_deus_run_controller = function() return controller end }
                end },
                state = { entity = { system = function(_, name)
                    return name == "buff_system" and buff_system or nil
                end } },
            })

            H.equal(f.mod._ct_strip_modded_content("test"), true,
                table.concat(f.calls.logs, " || "))
            H.equal(player_written[1], "departed")
            H.equal(#player_written[5], 1)
            H.equal(player_written[5][1], native)
            H.deep_equal(persistent_written[5], { "deus_ammo_pickup" })
            H.equal(party_written[1], native)
            H.deep_equal(bought_written, { "natural_bond" })
            H.equal(controller._ct_isha_active, nil)
            H.equal(controller._ct_isha_active_level, nil)
            H.equal(controller._ct_isha_pending, "ct_miracle_of_isha_wounds",
                "host-local purchased pending blessing was destroyed")
            H.equal(removed_server[1][2], 12)
            H.equal(removed_local[1][1], 8)
            H.equal(removed_local[1][2], nil,
                "ordinary synced removal must notify existing peers")
            H.equal(f.mod._ct_census_modded_content().total, 0)
        end)
    end)

    H.test("CT public #426 strips cached player GameObject buff ids", function()
        with_fixture({ safe = false }, function(f)
            local native_id = rawget(f.nl.buff_templates, "power_up_movespeed_exotic")
            local ct_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local state = make_run_state({}, {})
            local _, game = attach_game_object_state(
                state, { native_id, ct_id })
            H.equal(f.mod._ct_census_modded_content().game_object_buffs, 1)
            H.equal(f.mod._ct_strip_modded_content("cached-game-object"), true,
                table.concat(f.calls.logs, " || "))
            H.deep_equal(game.fields[42].network_buff_ids, { native_id })
            H.equal(f.mod._ct_census_modded_content().total, 0)
        end)
    end)

    H.test("CT public #426 cached GameObject failures are closed and retryable", function()
        with_fixture({ safe = false }, function(f)
            local native_id = rawget(f.nl.buff_templates, "power_up_movespeed_exotic")
            local ct_id = rawget(f.nl.buff_templates, "ct_miracle_of_ulric")
            local state = make_run_state({}, {})
            local _, game, _, options = attach_game_object_state(
                state, { native_id, ct_id }, { throw_writer_once = true })
            H.equal(f.mod._ct_strip_modded_content("writer-fails"), false)
            H.deep_equal(game.fields[42].network_buff_ids, { native_id, ct_id })
            H.equal(f.mod._ct_strip_modded_content("writer-retries"), true,
                table.concat(f.calls.logs, " || "))
            H.equal(options.write_attempts, 2)
            H.deep_equal(game.fields[42].network_buff_ids, { native_id })

            for i, malformed in ipairs({
                    { [2] = native_id },
                    { 999999 },
                }) do
                game.fields[42].network_buff_ids = malformed
                local before = game.fields[42].network_buff_ids
                H.equal(f.mod._ct_strip_modded_content(
                    "malformed-game-object-" .. i), false)
                H.equal(game.fields[42].network_buff_ids, before)
            end
            game.fields[42].network_buff_ids = { native_id }
            options.throw_reader = true
            H.equal(f.mod._ct_strip_modded_content("reader-fails"), false)
            H.deep_equal(game.fields[42].network_buff_ids, { native_id })
        end)
    end)

    H.test("CT public #426 malformed SharedState coordinate trees fail closed", function()
        with_fixture({ safe = false }, function(f)
            local function tree(peer, local_id, profile, career, party)
                return { [peer] = { [local_id] = { [profile] = {
                    [career] = { [party] = {} },
                } } } }
            end
            local cases = {
                tree("", 1, 2, 3, 0),
                tree("0", 1, 2, 3, 0),
                tree("owner", 0, 2, 3, 0),
                tree("owner", -1, 2, 3, 0),
                tree("owner", math.huge, 2, 3, 0),
                tree("owner", 2147483648, 2, 3, 0),
                tree("owner", 1, 0, 3, 0),
                tree("owner", 1, 2, 0, 0),
                tree("owner", 1, 2, 3, 1),
            }
            for i = 1, #cases do
                local state = make_run_state({}, {})
                state._shared_state._server_state.power_ups = cases[i]
                attach_run_state(state)
                H.equal(f.mod._ct_census_modded_content().ok, false, "case " .. i)
                H.equal(f.mod._ct_strip_modded_content("bad-tree-" .. i), false)
            end
        end)
    end)

    H.test("CT public #426 wide SharedState trees refuse before mutation", function()
        with_fixture({ safe = false }, function(f)
            local roots = {}
            local wide_peers = {}
            for i = 1, policy.MAX_STATE_ROWS + 1 do
                wide_peers["peer-" .. tostring(i)] = {}
            end
            roots[#roots + 1] = wide_peers
            local wide_locals = { owner = {} }
            for i = 1, policy.MAX_STATE_ROWS + 1 do
                wide_locals.owner[i] = {}
            end
            roots[#roots + 1] = wide_locals

            for i = 1, #roots do
                local state = make_run_state({}, {})
                local root = roots[i]
                state._shared_state._server_state.power_ups = root
                attach_run_state(state)
                H.equal(f.mod._ct_census_modded_content().ok, false, "case " .. i)
                H.equal(f.mod._ct_strip_modded_content("wide-tree-" .. i), false)
                H.equal(state._shared_state._server_state.power_ups, root,
                    "case " .. i .. " root replaced")
                if i == 1 then
                    H.truthy(rawget(root, "peer-" .. tostring(
                        policy.MAX_STATE_ROWS + 1)) ~= nil)
                else
                    H.truthy(rawget(root.owner, policy.MAX_STATE_ROWS + 1) ~= nil)
                end
            end
        end)
    end)

    H.test("CT public #426 malformed live buff ownership state fails closed", function()
        with_fixture({ safe = false }, function(f)
            local unit = {}
            local cases = {
                function() return { server_controlled_buffs = {
                    [unit] = { [0] = { template_name = "ct_miracle_of_ulric" } },
                } } end,
                function() return { server_controlled_buffs = {
                    [unit] = { [math.huge] = {
                        template_name = "ct_miracle_of_ulric",
                    } },
                } } end,
                function() return { server_controlled_buffs = {
                    [unit] = { [1] = { template_name = "" } },
                } } end,
                function() return { server_controlled_buffs = {
                    [unit] = { [1] = {
                        template_name = "ct_miracle_of_ulric", local_buff_id = 0,
                    } },
                } } end,
                function() return { active_buff_units = {
                    [unit] = { active_buffs = function() error("active reader") end },
                } } end,
                function() return { active_buff_units = {
                    [unit] = { active_buffs = function()
                        return { { id = 1,
                            buff_template_name = "ct_miracle_of_ulric" } }, 1
                    end },
                } } end,
                function()
                    local units = {}
                    for _ = 1, runtime.MAX_ACTIVE_BUFF_ROWS + 1 do
                        units[{}] = { active_buffs = function() return {}, 0 end }
                    end
                    return { active_buff_units = units }
                end,
            }
            for i = 1, #cases do
                local state = make_run_state({}, {})
                local buff_system = cases[i]()
                attach_run_state(state, buff_system)
                H.equal(f.mod._ct_census_modded_content().ok, false, "case " .. i)
                H.equal(f.mod._ct_strip_modded_content("bad-live-buff-" .. i), false)
            end

            local state = make_run_state({}, {})
            local controller = attach_run_state(state)
            controller._ct_isha_active = 42
            H.equal(f.mod._ct_census_modded_content().ok, false)
            H.equal(f.mod._ct_strip_modded_content("bad-controller-marker"), false)
        end)
    end)

    H.test("CT public #426 current and stale live buffs are both stripped", function()
        with_fixture({ safe = false }, function(f)
            local unit, removed = {}, {}
            local active = {
                { id = 3, buff_template_name = "ct_meta_health_stack" },
                { id = 4, buff_template_name = "power_up_ct_kill_heal_exotic" },
                { id = 5, buff_template_name = "deus_ammo_pickup" },
            }
            local extension = {
                active_buffs = function() return active, #active end,
                remove_buff = function(_, id)
                    removed[#removed + 1] = id
                    for i = 1, #active do
                        if type(active[i]) == "table" and active[i].id == id then
                            active[i] = { removed = true }
                        end
                    end
                end,
            }
            local buff_system = { active_buff_units = { [unit] = extension } }
            attach_run_state(make_run_state({}, {}), buff_system)
            H.equal(f.mod._ct_strip_modded_content("current-and-stale"), true,
                table.concat(f.calls.logs, " || "))
            H.deep_equal(removed, { 3, 4 })
            H.equal(f.mod._ct_census_modded_content().total, 0)
        end)
    end)

    H.test("CT public #426 parity-loss failures remain armed for retry", function()
        with_fixture({ safe = false, throw_pool_remove_after_install = true }, function(f)
            local feature = f.calls.features.ct_public_modded_boons
            H.truthy(type(feature) == "table")
            feature.on_disable()
            -- A transient unreadable host state makes the first scheduled strip
            -- fail. The next update must retry rather than clearing the only job.
            local attempts = 0
            rawset(_G, "Managers", {
                player = { is_server = true },
                mechanism = { game_mechanism = function()
                    attempts = attempts + 1
                    return { get_deus_run_controller = function()
                        return { _run_state = {} }
                    end }
                end },
            })
            f.mod.update(15)
            H.equal(attempts, 1)
            f.mod.update(1)
            H.equal(attempts, 2,
                "failed parity-loss strip was not retried")
        end)
    end)

    H.test("CT public #426 lookup integrity drift ejects strips and recovers", function()
        local drifts = {
            {
                label = "power-forward",
                apply = function(f)
                    local axis = f.nl.deus_power_up_templates
                    local name = "ct_meta_crit"
                    local id = rawget(axis, name)
                    rawset(axis, name, id + 100)
                    return function() rawset(axis, name, id) end
                end,
            },
            {
                label = "buff-reverse",
                apply = function(f)
                    local axis = f.nl.buff_templates
                    local name = "ct_miracle_of_ulric"
                    local id = rawget(axis, name)
                    rawset(axis, id, "foreign")
                    return function() rawset(axis, id, name) end
                end,
            },
            {
                label = "axis-replacement",
                apply = function(f)
                    local prior = f.nl.buff_templates
                    rawset(f.nl, "buff_templates", {})
                    return function() rawset(f.nl, "buff_templates", prior) end
                end,
            },
            {
                label = "root-replacement",
                apply = function(f)
                    local prior = rawget(_G, "NetworkLookup")
                    rawset(_G, "NetworkLookup", {
                        deus_power_up_templates = f.nl.deus_power_up_templates,
                        buff_templates = f.nl.buff_templates,
                        rarities = f.nl.rarities,
                    })
                    return function() rawset(_G, "NetworkLookup", prior) end
                end,
            },
        }
        for i = 1, #drifts do
            local drift = drifts[i]
            with_fixture({ safe = true }, function(f)
                local custom = power_up("ct_meta_crit", 2)
                local state = make_run_state({ custom }, {})
                attach_run_state(state)
                local feature = f.calls.features.ct_public_modded_boons
                feature.on_enable()
                local adds_before = #f.calls.added_pools
                local removals_before = #f.calls.removed_pools
                local restore = drift.apply(f)
                f.mod.update(0)
                H.equal(f.mod._ct_wire_safe(), false, drift.label .. " gate")
                H.equal(#state._shared_state._server_state.power_ups
                    .owner[1][2][3][0], 0, drift.label .. " live strip")
                H.truthy(#f.calls.removed_pools > removals_before,
                    drift.label .. " pool ejection")

                local written
                f.hooks["DeusRunState.set_player_power_ups"](
                    function(_, _, _, _, _, values) written = values end,
                    state, "owner", 1, 2, 3, { custom })
                H.equal(#written, 0, drift.label .. " writer floor")

                restore()
                f.mod.update(0)
                H.equal(f.mod._ct_wire_safe(), true, drift.label .. " recovery")
                H.truthy(#f.calls.added_pools > adds_before,
                    drift.label .. " pool reinjection")
            end)
        end
    end)

    local sync_admission_cases = assert(loadfile(repo_root
        .. "/qa/lua/tests/ct_public_426_sync_admission_cases.lua"))()
    sync_admission_cases(
        H, with_fixture, power_up, make_run_state, attach_run_state)

    local shop_cases = assert(loadfile(repo_root
        .. "/qa/lua/tests/ct_public_426_shop_receiver_cases.lua"))()
    shop_cases(H, with_fixture)

    local terminal_cases = assert(loadfile(repo_root
        .. "/qa/lua/tests/ct_public_426_terminal_admission_cases.lua"))()
    terminal_cases(H, with_fixture)
end
