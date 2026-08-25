return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local peer_owner_path = base .. "_ct_peer_parity_owner.lua"

    local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(source, needle)
        local count, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return count end
            count = count + 1
            at = found + #needle
        end
    end

    local PEER_CHECK_NAMES = {
        "peer_parity_beacon_installed",
        "ct_426_exact_wire_catalog",
        "ct_426_exact_gate_fails_closed",
        "issue426_runtime_gate_presentation",
        "peer_parity_gate_classify",
        "issue426_hot_join_fence",
        "ct_wire_strip_name_predicate",
        "modded_power_up_registry",
    }

    local function valid_peer_dependencies(checks)
        return {
            rt_register = function(name, fn)
                checks[#checks + 1] = { name = name, fn = fn }
            end,
            collect_setting_ids = function() return { "fixture_gate" } end,
            rpc_schema = 7,
            add_dormant_to_pool = function() end,
            remove_dormant_from_pool = function() end,
            injected_dormants = {},
            trait_boons = {},
            register_trait_boon = function() end,
        }
    end

    local function inert_mod()
        local calls = { dofile = 0, hook = 0, command = 0, echo = 0, checks = {} }
        local mod = {
            dofile = function() calls.dofile = calls.dofile + 1 end,
            hook = function() calls.hook = calls.hook + 1 end,
            command = function() calls.command = calls.command + 1 end,
            echo = function() calls.echo = calls.echo + 1 end,
        }
        mod.update = function() end
        return mod, calls, valid_peer_dependencies(calls.checks)
    end

    local function fake_peer_runtime(with_instance)
        local calls = {
            loads = {}, hooks = {}, commands = {}, checks = {}, features = {},
            installs = 0, base_updates = 0, beacon_updates = 0,
        }
        local mod = {}
        mod.update = function() calls.base_updates = calls.base_updates + 1 end
        local policy = {
            POWER_UP_COUNT = 0,
            BUFF_COUNT = 0,
            GATED_SETTING_IDS = { "fixture_gate" },
            GATE_REASON = "fixture closed",
            power_registry_ready = function() return true end,
            catalog_ready = function() return true end,
            capture_integrity = function()
                return { network_lookup = {}, rows = {} }
            end,
            build_identity = function() return "ct-wire-v1:0:fixture" end,
            integrity = function() return true end,
            power_up_entries = function() return {} end,
            buff_entries = function() return {} end,
            count = function() return 0 end,
            is_power_up = function() return false end,
            is_buff = function() return false end,
            runtime_gate_spec = function(mod_id, ids, evaluate)
                return { mod_id = mod_id, setting_ids = ids, evaluate = evaluate }
            end,
            try_register_runtime_gate = function() return true end,
        }
        local instance
        if with_instance then
            instance = {
                EXACT_MODE = true,
                WIRE_IDENTITY = "ct-wire-v1:0:fixture",
                FAILSAFE_POSTURE = "feature_inert_until_confirmed",
                _initial_applied = "disabled",
                __classify = function(peers, acknowledgements)
                    for peer_id in pairs(peers) do
                        if not acknowledgements[peer_id] then return false end
                    end
                    return true
                end,
            }
            function instance:register_gated_feature(name, callbacks)
                calls.features[#calls.features + 1] = { name = name, callbacks = callbacks }
            end
            function instance:install()
                calls.installs = calls.installs + 1
                local previous = mod.update
                mod.update = function(dt)
                    calls.beacon_updates = calls.beacon_updates + 1
                    if previous then return previous(dt) end
                end
                return true
            end
            function instance:is_installed() return true end
            function instance:applied_state() return "disabled" end
            function instance:all_peers_have() return false end
            function instance:peer_has() return false end
            function instance:require_peer() return false end
            function instance:forget_peer() end
            function instance:feature_count() return #calls.features end
        end
        mod.dofile = function(_, path)
            calls.loads[#calls.loads + 1] = path
            if path:find("_ct_wire_policy", 1, true) then return policy end
            if path:find("_lib_wire_catalog", 1, true) then return {} end
            if path:find("_lib_peer_parity", 1, true) then
                if not with_instance then return false end
                return function(factory_mod, options)
                    H.equal(factory_mod, mod)
                    H.equal(options.channel, "ct_boon_catalog_exact_v1")
                    H.equal(options.schema, 7)
                    H.equal(options.wire_identity, "ct-wire-v1:0:fixture")
                    return instance
                end
            end
            error("unexpected owner dependency: " .. tostring(path))
        end
        mod.hook = function(_, class_name, method_name, callback)
            calls.hooks[#calls.hooks + 1] = {
                class_name = class_name, method_name = method_name, callback = callback,
            }
        end
        mod.command = function(_, name, description, callback)
            calls.commands[#calls.commands + 1] = {
                name = name, description = description, callback = callback,
            }
        end
        mod.echo = function() end
        mod.get_name = function() return "ct_dev" end
        local deps = valid_peer_dependencies(calls.checks)
        return mod, calls, deps, instance
    end

    local TRANSACTION_FIELDS = {
        "_ct_wire_policy",
        "_ct_wire_catalog_identity",
        "_ct_wire_catalog_error",
        "_ct_wire_catalog_integrity",
        "_ct_wire_catalog_power_count",
        "_ct_wire_catalog_buff_count",
        "_ct_peer_parity",
        "_ct_is_modded_power_up",
        "_ct_wire_safe",
        "_ct_is_ct_buff_template",
        "_ct_filter_wire_entries",
        "_ct_strip_modded_content",
        "_ct_census_modded_content",
        "_ct_wire_runtime_gate_registered",
        "_peer_parity_epoch_sequences",
        "update",
    }

    local function transaction_fixture(fault)
        fault = fault or {}
        local calls = {
            loads = {}, hooks = {}, commands = {}, checks = {}, gates = {},
            features = {}, retained_updates = {}, installs = 0, removes = 0,
            adds = 0, traits = 0, base_updates = 0, beacon_updates = 0,
            export_newindex = 0, update_newindex = 0, native_hooks = 0,
        }
        local mod = {}
        local base_update = function() calls.base_updates = calls.base_updates + 1 end
        rawset(mod, "update", base_update)
        rawset(mod, "_ct_wire_policy", false)
        rawset(mod, "_ct_peer_parity", "prior-peer")
        rawset(mod, "_ct_wire_safe", false)
        rawset(mod, "_ct_filter_wire_entries", "prior-filter")
        rawset(mod, "_ct_wire_runtime_gate_registered", false)
        local epoch_sequences = { unrelated = 9, ct_boon_catalog_exact_v1 = 41 }
        rawset(mod, "_peer_parity_epoch_sequences", epoch_sequences)

        local policy = {
            POWER_UP_COUNT = 0,
            BUFF_COUNT = 0,
            GATED_SETTING_IDS = { "fixture_gate" },
            GATE_REASON = "fixture closed",
            power_registry_ready = function() return true end,
            catalog_ready = function() return true end,
            capture_integrity = function() return { network_lookup = {}, rows = {} } end,
            build_identity = function() return "ct-wire-v1:0:fixture" end,
            integrity = function() return true end,
            power_up_entries = function() return {} end,
            buff_entries = function() return {} end,
            count = function() return 0 end,
            is_power_up = function() return false end,
            is_buff = function() return false end,
            runtime_gate_spec = function(mod_id, ids, evaluate)
                return { mod_id = mod_id, setting_ids = ids, evaluate = evaluate }
            end,
            try_register_runtime_gate = function(_, _, spec)
                calls.gates[#calls.gates + 1] = spec
                if fault.point == "runtime_gate" then error("planted runtime gate") end
                return true
            end,
        }

        local instance = {
            EXACT_MODE = true,
            WIRE_IDENTITY = "ct-wire-v1:0:fixture",
            FAILSAFE_POSTURE = "feature_inert_until_confirmed",
            _initial_applied = "disabled",
            _installed = false,
            __classify = function(peers, acknowledgements)
                for peer_id in pairs(peers) do
                    if not acknowledgements[peer_id] then return false end
                end
                return true
            end,
        }
        function instance:register_gated_feature(name, callbacks)
            calls.features[#calls.features + 1] = { name = name, callbacks = callbacks }
            if fault.immediate_feature_callbacks then
                callbacks.on_enable()
                callbacks.on_disable()
            end
            if fault.point == "feature" then error("planted feature registrar") end
        end
        function instance:install()
            calls.installs = calls.installs + 1
            local previous = mod.update
            local wrapped = function(dt)
                if previous then previous(dt) end
                if self._installed then calls.beacon_updates = calls.beacon_updates + 1 end
            end
            calls.retained_updates[#calls.retained_updates + 1] = wrapped
            if fault.point == "install_throw" then error("planted install throw") end
            if fault.point == "install_false" then return false end
            mod.update = wrapped
            self._installed = true
            return true
        end
        function instance:is_installed() return self._installed end
        function instance:applied_state() return "disabled" end
        function instance:all_peers_have() return false end
        function instance:peer_has() return false end
        function instance:require_peer() return false end
        function instance:forget_peer() end
        function instance:feature_count() return #calls.features end

        mod.dofile = function(_, path)
            calls.loads[#calls.loads + 1] = path
            if path:find("_ct_wire_policy", 1, true) then return policy end
            if path:find("_lib_wire_catalog", 1, true) then return {} end
            if path:find("_lib_peer_parity", 1, true) then
                epoch_sequences.ct_boon_catalog_exact_v1 = 42
                return function() return instance end
            end
            error("unexpected owner dependency: " .. tostring(path))
        end
        mod.hook = function(_, class_name, method_name, callback)
            calls.hooks[#calls.hooks + 1] = {
                class_name = class_name, method_name = method_name, callback = callback,
            }
            if fault.point == "hook_" .. tostring(#calls.hooks) then
                error("planted hook registrar")
            end
        end
        mod.command = function(_, name, description, callback)
            calls.commands[#calls.commands + 1] = {
                name = name, description = description, callback = callback,
            }
            if fault.point == "command" then error("planted command registrar") end
        end
        mod.echo = function() end
        mod.get_name = function() return "ct_dev" end

        local deps = {
            rt_register = function(name, callback)
                calls.checks[#calls.checks + 1] = { name = name, fn = callback }
                if fault.point == "rt_" .. tostring(#calls.checks) then
                    error("planted runtime-check registrar")
                end
            end,
            collect_setting_ids = function() return { "fixture_gate" } end,
            rpc_schema = 7,
            add_dormant_to_pool = function()
                calls.adds = calls.adds + 1
                if fault.throw_on_pool_callbacks then error("planted pool add") end
            end,
            remove_dormant_from_pool = function()
                calls.removes = calls.removes + 1
                if fault.point == "pool_removal" then error("planted pool removal") end
            end,
            injected_dormants = {
                dormant_fixture = { rarity = "exotic" },
                trait_fixture = { rarity = "exotic" },
            },
            trait_boons = { { name = "trait_fixture" } },
            register_trait_boon = function()
                calls.traits = calls.traits + 1
                if fault.throw_on_pool_callbacks then error("planted trait registration") end
            end,
        }

        local inherited_update
        if fault.update_shape == "false" then
            rawset(mod, "update", false)
        elseif fault.update_shape == "missing" then
            rawset(mod, "update", nil)
        elseif fault.update_shape == "inherited" then
            rawset(mod, "update", nil)
            inherited_update = base_update
        end
        local mod_metatable = {
            __index = function(_, name)
                if name == "update" then return calls.meta_update or inherited_update end
            end,
            __newindex = function(t, name, value)
                if name == "update" and fault.update_newindex then
                    calls.update_newindex = calls.update_newindex + 1
                    calls.meta_update = value
                    error("planted update publication")
                end
                if fault.export_newindex and type(name) == "string"
                        and name:find("^_ct_") then
                    calls.export_newindex = calls.export_newindex + 1
                    error("planted export publication")
                end
                rawset(t, name, value)
            end,
        }
        setmetatable(mod, mod_metatable)

        local raw_snapshot = {}
        for i = 1, #TRANSACTION_FIELDS do
            local name = TRANSACTION_FIELDS[i]
            raw_snapshot[name] = rawget(mod, name)
        end
        return mod, calls, deps, instance, raw_snapshot, {
            metatable = mod_metatable,
            effective_update = mod.update,
            raw_update = rawget(mod, "update"),
        }
    end

    local function registration_signature(calls)
        return table.concat({
            #calls.loads, #calls.hooks, #calls.commands, #calls.checks,
            #calls.gates, #calls.features, #calls.retained_updates,
            calls.installs, calls.removes, calls.adds, calls.traits,
            calls.beacon_updates, calls.export_newindex, calls.update_newindex,
        }, ":")
    end

    H.test("CT boon split stays below the frozen entry-file baseline", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        local _, lines = source:gsub("\n", "\n")
        -- 12040 = 2026-07-18 ratchet after the OOP W5 regression-suite extraction
        -- (_ct_regression.lua) shrank the entry. This physical-line ceiling only
        -- moves DOWN; the tighter non-empty ceiling lives in
        -- test_ct_entry_decomposition.lua.
        H.truthy(lines + 1 < 12040, "CT entry file regrew to its frozen baseline")
    end)

    H.test("CT boon split loads each explicit owner once in dependency order", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        local names = {
            "_ct_boon_balance",
            "_ct_boon_registry",
            "_ct_meta_trait_boons",
        }
        local previous = 0
        for _, name in ipairs(names) do
            local needle = 'mod:dofile(\n    "scripts/mods/chaos_wastes_tweaker_dev/' .. name .. '")'
            H.equal(occurrences(source, needle), 1, name .. " must have one entry-manifest load")
            local at = assert(source:find(needle, 1, true))
            H.truthy(at > previous, name .. " loaded out of dependency order")
            previous = at
        end
        H.equal(source:find("_ct_boon_runtime\")", 1, true), nil)
    end)

    H.test("CT boon split publishes only the bounded cross-module contracts", function()
        local balance = read(base .. "_ct_boon_balance.lua")
        local registry = read(base .. "_ct_boon_registry.lua")
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local meta_owner = read(base .. "_ct_meta_boon_owner.lua")
        H.truthy(balance:find("sync_reckless_swings = sync_reckless_swings", 1, true))
        H.truthy(registry:find("inject_dormant_boon = inject_dormant_boon", 1, true))
        H.truthy(meta:find("sync_host_dependent_state = sync_host_dependent_state", 1, true))
        H.truthy(meta:find("balance/registry modules must load before meta boons", 1, true))
        H.truthy(meta_owner:find("return function(mod, deps)", 1, true))
    end)

    H.test("CT meta boon owner is installed once with explicit dependencies", function()
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local owner = read(base .. "_ct_meta_boon_owner.lua")
        local owner_path = "scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_boon_owner"

        H.equal(occurrences(meta, owner_path), 1,
            "meta-boon owner must have one wrapper load")
        H.equal(occurrences(meta, "install_meta_boons(mod, {"), 1,
            "meta-boon owner must have one synchronous install")
        H.truthy(meta:find("context = context", 1, true))
        H.truthy(meta:find("registry = registry", 1, true))
        H.equal(meta:find("pcall(install_meta_boons", 1, true), nil,
            "owner errors must propagate through the wrapper")

        local factory = assert(loadfile(base .. "_ct_meta_boon_owner.lua"))()
        H.equal(type(factory), "function")
        local ok, err = pcall(factory, {}, nil)
        H.equal(ok, false, "missing dependencies must fail closed")
        H.truthy(tostring(err):find("missing dependency table", 1, true))

        for _, marker in ipairs({
            "local CT_META_BOONS = {",
            "local function _make_meta_proc",
            "local function _ct_clamp_current_ammo_256",
            "power_ups.ct_meta_movespeed = {",
        }) do
            H.equal(meta:find(marker, 1, true), nil,
                marker .. " must not remain in the trait wrapper")
            H.truthy(owner:find(marker, 1, true),
                marker .. " must live in the meta-boon owner")
        end
    end)

    H.test("CT peer parity owner installs synchronously at the former boundary", function()
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local settings = read(base .. "_ct_settings_lifecycle_owner.lua")
        local owner_path = "scripts/mods/chaos_wastes_tweaker_dev/_ct_peer_parity_owner"

        H.equal(occurrences(meta, owner_path), 1,
            "peer-parity owner must have one wrapper load")
        H.equal(occurrences(meta, "install_peer_parity_owner(mod, {"), 1,
            "peer-parity owner must have one synchronous install")
        H.equal(meta:find("pcall(install_peer_parity_owner", 1, true), nil,
            "owner dependency/install errors must stop the wrapper")
        H.truthy(meta:find("}) ~= true then", 1, true),
            "a false installer result must fail the synchronous load")

        local kill_heal_at = assert(meta:find('inject_dormant_boon("ct_kill_heal", "exotic")', 1, true))
        local owner_at = assert(meta:find(owner_path, kill_heal_at, true))
        local next_check_at = assert(meta:find('_rt_register("issue406_kill_heal_mod_boon_catalog"', owner_at, true))
        H.truthy(kill_heal_at < owner_at and owner_at < next_check_at,
            "owner moved away from the former line-478 registration boundary")
        local dependency_block = meta:sub(owner_at, next_check_at - 1)

        local meta_load_at = assert(settings:find("_ct_meta_trait_boons", 1, true))
        local clear_at = assert(settings:find("mod._ct_boon_runtime_context = nil", meta_load_at, true))
        local rebroadcast_at = assert(settings:find("_ct_stack_rebroadcast_owner", clear_at, true))
        H.truthy(meta_load_at < clear_at and clear_at < rebroadcast_at,
            "peer owner must finish before context clear and stack rebroadcast")

        for _, needle in ipairs({
            "rt_register = _rt_register",
            "collect_setting_ids = _collect_setting_ids",
            "rpc_schema = CT_RPC_SCHEMA",
            "add_dormant_to_pool = _add_dormant_to_pool",
            "remove_dormant_from_pool = _remove_dormant_from_pool",
            "injected_dormants = _injected_dormants",
            "trait_boons = CT_TRAIT_BOONS",
            "register_trait_boon = register_trait_boon",
        }) do
            H.equal(occurrences(dependency_block, needle), 1,
                "missing exact owner dependency: " .. needle)
        end
    end)

    H.test("CT peer parity implementation and eight checks have one owner", function()
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local owner = read(peer_owner_path)
        for _, marker in ipairs({
            'channel     = "ct_boon_catalog_exact_v1"',
            'mod:command("ct_426_diag"',
            'mod:hook("GameNetworkManager", "hot_join_sync"',
            'mod:hook("GameNetworkManager", "remove_peer"',
            "local wire_safe = function()",
            "local function _ct_strip_modded_content",
        }) do
            H.equal(occurrences(owner, marker), 1, marker .. " must live once in the owner")
            H.equal(occurrences(meta, marker), 0, marker .. " must leave the wrapper")
        end
        H.equal(occurrences(owner, "local owner_update = function(dt)"), 2,
            "owner must retain exactly the installed and fail-safe update branches")

        local previous = 0
        for _, name in ipairs(PEER_CHECK_NAMES) do
            local needle = 'register_peer_check("' .. name .. '"'
            H.equal(occurrences(owner, needle), 1, name .. " must be owner-owned once")
            H.equal(occurrences(meta, needle), 0, name .. " must leave the wrapper")
            local at = assert(owner:find(needle, 1, true))
            H.truthy(at > previous, name .. " runtime-check order changed")
            previous = at
        end
    end)

    H.test("CT peer parity owner has one terminal publication boundary", function()
        local owner = read(peer_owner_path)
        local reserve_at = assert(owner:find('rawset(mod, OWNER_MARKER, false)', 1, true))
        local pool_at = assert(owner:find('_ct_eject_modded_pools()', reserve_at, true))
        local command_at = assert(owner:find('mod:command("ct_426_diag"', pool_at, true))
        local hook_at = assert(owner:find('mod:hook("GameNetworkManager", "hot_join_sync"', command_at, true))
        local final_check_at = assert(owner:find(
            'register_peer_check("modded_power_up_registry"', hook_at, true))
        local seed_at = assert(owner:find('rawset(mod, "update", effective_update_before',
            final_check_at, true))
        local install_at = assert(owner:find('install_plan.inst:install()', seed_at, true))
        local capture_at = assert(owner:find(
            'install_plan.update_chain.previous = rawget(mod, "update")', install_at, true))
        local commit_at = assert(owner:find('rawset(mod, OWNER_MARKER, true)', capture_at, true))
        H.truthy(reserve_at < pool_at and pool_at < command_at and command_at < hook_at
            and hook_at < final_check_at and final_check_at < seed_at and seed_at < install_at
            and install_at < capture_at and capture_at < commit_at,
            "throwable registration escaped the pre-beacon transaction")
        H.equal(occurrences(owner, 'rawset(mod, OWNER_MARKER, false)'), 2,
            "owner needs one reservation and one terminal-failure marker")
        H.equal(occurrences(owner, 'rawset(mod, OWNER_MARKER, true)'), 1,
            "owner must expose one successful commit boundary")
        H.equal(occurrences(owner, 'install_plan.inst:install()'), 1,
            "beacon install must remain one irreversible call")
        H.equal(occurrences(owner, 'rawset(mod, "update", effective_update_before'), 1,
            "beacon install needs one raw effective-update seed")
        H.equal(occurrences(owner, "stage_public(\"update\""), 1,
            "final update wrapper must be staged before beacon install")
        H.equal(occurrences(owner, "mod.update ="), 0,
            "owner publication must bypass throwing __newindex paths")
    end)

    H.test("CT peer parity owner rejects malformed dependencies before side effects", function()
        local install = assert(loadfile(peer_owner_path))()
        local function rejected(mod, calls, deps, label)
            local original_update = mod.update
            local ok = pcall(install, mod, deps)
            H.equal(ok, false, label .. " must be rejected")
            H.equal(calls.dofile, 0, label .. " reached dofile")
            H.equal(calls.hook, 0, label .. " reached hook registration")
            H.equal(calls.command, 0, label .. " reached command registration")
            H.equal(calls.echo, 0, label .. " reached echo")
            H.equal(#calls.checks, 0, label .. " registered runtime checks")
            H.truthy(rawequal(mod.update, original_update), label .. " replaced mod.update")
            H.equal(rawget(mod, "_ct_peer_parity"), nil, label .. " exported peer state")
            H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), nil,
                label .. " claimed installation")
        end

        for _, capability in ipairs({ "dofile", "hook", "command", "echo" }) do
            for _, value in ipairs({ false, "missing" }) do
                local mod, calls, deps = inert_mod()
                mod[capability] = value == "missing" and nil or value
                rejected(mod, calls, deps, "mod." .. capability .. "/" .. tostring(value))
            end
        end
        for _, dependency in ipairs({
            "rt_register", "collect_setting_ids", "add_dormant_to_pool",
            "remove_dormant_from_pool", "register_trait_boon",
        }) do
            for _, value in ipairs({ false, "missing" }) do
                local mod, calls, deps = inert_mod()
                deps[dependency] = value == "missing" and nil or value
                rejected(mod, calls, deps, dependency .. "/" .. tostring(value))
            end
        end
        for _, dependency in ipairs({ "rpc_schema", "injected_dormants", "trait_boons" }) do
            for _, value in ipairs({ false, "missing" }) do
                local mod, calls, deps = inert_mod()
                deps[dependency] = value == "missing" and nil or value
                rejected(mod, calls, deps, dependency .. "/" .. tostring(value))
            end
        end

        local mod, calls = inert_mod()
        local throwing = setmetatable({}, {
            __index = function() error("planted dependency read") end,
        })
        rejected(mod, calls, throwing, "throwing dependency table")
    end)

    H.test("CT peer parity terminal failures restore raw state and make retries inert", function()
        local install = assert(loadfile(peer_owner_path))()
        local fault_cases = {
            { label = "pool removal", point = "pool_removal" },
            { label = "command", point = "command" },
            { label = "runtime gate", point = "runtime_gate" },
            { label = "feature", point = "feature" },
            { label = "hot-join hook", point = "hook_1" },
            { label = "remove-peer hook", point = "hook_2" },
            { label = "install throw", point = "install_throw" },
            { label = "install false", point = "install_false" },
            {
                label = "inherited update install failure",
                point = "install_throw",
                update_shape = "inherited",
                update_newindex = true,
            },
            { label = "false update restore", point = "install_throw", update_shape = "false" },
            { label = "missing update restore", point = "install_throw", update_shape = "missing" },
            {
                label = "immediate feature pool callbacks",
                point = "hook_1",
                immediate_feature_callbacks = true,
                throw_on_pool_callbacks = true,
            },
        }
        for i = 1, #PEER_CHECK_NAMES do
            fault_cases[#fault_cases + 1] = {
                label = "runtime check " .. tostring(i),
                point = "rt_" .. tostring(i),
            }
        end

        local global_names = { "Managers", "Network", "NetworkLookup", "BuffTemplates", "get_mod" }
        local global_before = {}
        for i = 1, #global_names do
            local name = global_names[i]
            global_before[name] = rawget(_G, name)
        end
        local package_key = "qa.ct_peer_parity_owner_transaction"
        local package_before = package.loaded[package_key]
        local ok_all, err_all = xpcall(function()
            package.loaded[package_key] = { sentinel = true }
            for _, fault in ipairs(fault_cases) do
                local mod, calls, deps, _, raw_snapshot, surface_snapshot =
                    transaction_fixture(fault)
                local ok = pcall(install, mod, deps)
                H.equal(ok, false, fault.label .. " must fail the owner transaction")
                H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), false,
                    fault.label .. " did not leave a terminal false marker")
                H.truthy(rawequal(getmetatable(mod), surface_snapshot.metatable),
                    fault.label .. " changed metatable identity")
                H.truthy(rawequal(rawget(mod, "update"), surface_snapshot.raw_update),
                    fault.label .. " changed raw update shape")
                H.truthy(rawequal(mod.update, surface_snapshot.effective_update),
                    fault.label .. " changed effective inherited update")
                H.equal(calls.update_newindex, 0,
                    fault.label .. " reached update __newindex publication")
                for i = 1, #TRANSACTION_FIELDS do
                    local name = TRANSACTION_FIELDS[i]
                    H.truthy(rawequal(rawget(mod, name), raw_snapshot[name]),
                        fault.label .. " failed to restore raw " .. name)
                end
                local sequences = rawget(mod, "_peer_parity_epoch_sequences")
                H.equal(rawget(sequences, "ct_boon_catalog_exact_v1"), 41,
                    fault.label .. " leaked a factory epoch mutation")
                for i = 1, #global_names do
                    local name = global_names[i]
                    H.truthy(rawequal(rawget(_G, name), global_before[name]),
                        fault.label .. " changed raw global " .. name)
                end
                H.equal(package.loaded[package_key].sentinel, true,
                    fault.label .. " changed package.loaded state")

                local signature_before_callbacks = registration_signature(calls)
                local base_updates_before = calls.base_updates
                local native_hooks_before = calls.native_hooks
                for _, row in ipairs(calls.commands) do
                    H.equal(pcall(row.callback), true, fault.label .. " retained command errored")
                end
                for _, spec in ipairs(calls.gates) do
                    local ok_gate, available = pcall(spec.evaluate)
                    H.equal(ok_gate, true, fault.label .. " retained gate errored")
                    H.equal(available, false, fault.label .. " retained gate did not fail closed")
                end
                for _, row in ipairs(calls.features) do
                    H.equal(pcall(row.callbacks.on_enable), true,
                        fault.label .. " retained on_enable errored")
                    H.equal(pcall(row.callbacks.on_disable), true,
                        fault.label .. " retained on_disable errored")
                end
                for _, row in ipairs(calls.hooks) do
                    local ok_hook, result = pcall(row.callback,
                        function()
                            calls.native_hooks = calls.native_hooks + 1
                            return "native-pass"
                        end, {}, "peer")
                    H.equal(ok_hook, true, fault.label .. " retained hook errored")
                    H.equal(result, "native-pass", fault.label .. " retained hook blocked native")
                end
                for _, row in ipairs(calls.checks) do
                    local ok_check, result = pcall(row.fn)
                    H.equal(ok_check, true, fault.label .. " retained check errored")
                    H.truthy(type(result) == "string" and result ~= "",
                        fault.label .. " retained check reported a false pass")
                end
                for _, update in ipairs(calls.retained_updates) do
                    H.equal(pcall(update, 0.1), true, fault.label .. " retained update errored")
                end
                local expected_update_passes = #calls.retained_updates
                if fault.update_shape == "false" or fault.update_shape == "missing" then
                    expected_update_passes = 0
                end
                H.equal(calls.base_updates - base_updates_before, expected_update_passes,
                    fault.label .. " retained update did not preserve prior callback")
                H.equal(calls.native_hooks - native_hooks_before, #calls.hooks,
                    fault.label .. " retained hook did not pass through exactly once")
                H.equal(calls.adds, 0, fault.label .. " retained callback added a pool row")
                H.equal(calls.traits, 0, fault.label .. " retained callback registered a trait")
                H.equal(registration_signature(calls), signature_before_callbacks,
                    fault.label .. " retained callback changed owner registration state")

                local before_retry = registration_signature(calls)
                local retry_ok, retry_err = pcall(install, mod, deps)
                H.equal(retry_ok, false, fault.label .. " retry unexpectedly ran")
                H.truthy(tostring(retry_err):find("already installed", 1, true) ~= nil,
                    fault.label .. " retry did not hit the terminal marker")
                H.equal(registration_signature(calls), before_retry,
                    fault.label .. " retry duplicated a retained surface")
                H.truthy(rawequal(getmetatable(mod), surface_snapshot.metatable),
                    fault.label .. " retry changed metatable identity")
                H.truthy(rawequal(rawget(mod, "update"), surface_snapshot.raw_update),
                    fault.label .. " retry changed raw update shape")
                H.truthy(rawequal(mod.update, surface_snapshot.effective_update),
                    fault.label .. " retry changed effective inherited update")
                H.equal(calls.update_newindex, 0,
                    fault.label .. " retry reached update __newindex publication")
                for i = 1, #TRANSACTION_FIELDS do
                    local name = TRANSACTION_FIELDS[i]
                    H.truthy(rawequal(rawget(mod, name), raw_snapshot[name]),
                        fault.label .. " retry changed raw " .. name)
                end
                for i = 1, #global_names do
                    local name = global_names[i]
                    H.truthy(rawequal(rawget(_G, name), global_before[name]),
                        fault.label .. " retry changed raw global " .. name)
                end
                H.equal(package.loaded[package_key].sentinel, true,
                    fault.label .. " retry changed package.loaded state")
            end
        end, debug.traceback)

        for i = 1, #global_names do
            local name = global_names[i]
            rawset(_G, name, global_before[name])
        end
        package.loaded[package_key] = package_before
        if not ok_all then error(err_all) end
    end)

    H.test("CT peer parity raw-seeds an inherited update before beacon install", function()
        local install = assert(loadfile(peer_owner_path))()
        local mod, calls, deps, _, raw_snapshot, surface_snapshot = transaction_fixture({
            update_shape = "inherited",
            update_newindex = true,
        })
        H.equal(raw_snapshot.update, nil, "fixture update must begin raw-missing")
        H.equal(surface_snapshot.raw_update, nil, "raw update snapshot changed")
        H.equal(type(surface_snapshot.effective_update), "function",
            "fixture must expose an inherited update")

        H.equal(install(mod, deps), true)
        H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), true)
        H.truthy(rawequal(getmetatable(mod), surface_snapshot.metatable),
            "successful install changed metatable identity")
        H.equal(calls.update_newindex, 0,
            "beacon or owner publication reached inherited update __newindex")
        H.equal(calls.meta_update, nil,
            "beacon wrapper leaked into metatable-owned state")
        H.equal(type(rawget(mod, "update")), "function",
            "owner update was not raw-published")
        H.truthy(rawequal(mod.update, rawget(mod, "update")),
            "effective update did not resolve to the raw owner wrapper")

        mod.update(0.1)
        H.equal(calls.base_updates, 1, "inherited callback was not preserved")
        H.equal(calls.beacon_updates, 1, "beacon callback was not preserved")
    end)

    H.test("CT peer parity raw publication bypasses export __newindex", function()
        local install = assert(loadfile(peer_owner_path))()
        local mod, calls, deps = transaction_fixture({ export_newindex = true })
        H.equal(install(mod, deps), true)
        H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), true)
        H.equal(calls.export_newindex, 0, "final exports reached __newindex")
        H.equal(calls.installs, 1)
        H.equal(#calls.hooks, 2)
        H.equal(#calls.checks, #PEER_CHECK_NAMES)
        H.equal(calls.removes, 2, "initial fail-closed pool ejection changed")
        H.equal(calls.adds, 0)
        H.equal(calls.traits, 0)
        local feature = calls.features[1].callbacks
        feature.on_enable()
        H.equal(calls.adds, 1, "committed feature did not restore dormant pool")
        H.equal(calls.traits, 1, "committed feature did not restore trait boon")
        mod.update(0.1)
        H.equal(calls.base_updates, 1, "committed update dropped prior callback")
        H.equal(calls.beacon_updates, 1, "committed update dropped beacon callback")
    end)

    H.test("CT peer parity owner preserves installed branch and rejects duplicate install", function()
        local install = assert(loadfile(peer_owner_path))()
        local mod, calls, deps, instance = fake_peer_runtime(true)
        local installed = install(mod, deps)
        H.equal(installed, true)
        H.equal(rawget(mod, "_ct_peer_parity_owner_installed"), true)
        H.equal(mod._ct_peer_parity, instance)
        H.equal(calls.installs, 1)
        H.equal(#calls.features, 1)
        H.equal(calls.features[1].name, "ct_modded_boons_miracles")
        H.equal(#calls.hooks, 2)
        H.equal(calls.hooks[1].class_name, "GameNetworkManager")
        H.equal(calls.hooks[1].method_name, "hot_join_sync")
        H.equal(calls.hooks[2].class_name, "GameNetworkManager")
        H.equal(calls.hooks[2].method_name, "remove_peer")
        H.equal(#calls.commands, 1)
        H.equal(calls.commands[1].name, "ct_426_diag")
        H.equal(#calls.checks, #PEER_CHECK_NAMES)
        for i = 1, #PEER_CHECK_NAMES do
            H.equal(calls.checks[i].name, PEER_CHECK_NAMES[i])
            H.equal(type(calls.checks[i].fn), "function")
        end

        mod.update(0.25)
        H.equal(calls.base_updates, 1, "installed branch dropped the original update")
        H.equal(calls.beacon_updates, 1, "installed branch dropped the beacon update")

        local before = {
            loads = #calls.loads,
            hooks = #calls.hooks,
            commands = #calls.commands,
            checks = #calls.checks,
            installs = calls.installs,
            update = mod.update,
            peer = mod._ct_peer_parity,
        }
        local ok, err = pcall(install, mod, deps)
        H.equal(ok, false)
        H.truthy(tostring(err):find("already installed", 1, true))
        H.equal(#calls.loads, before.loads)
        H.equal(#calls.hooks, before.hooks)
        H.equal(#calls.commands, before.commands)
        H.equal(#calls.checks, before.checks)
        H.equal(calls.installs, before.installs)
        H.truthy(rawequal(mod.update, before.update))
        H.truthy(rawequal(mod._ct_peer_parity, before.peer))
    end)

    H.test("CT peer parity owner preserves the mutually exclusive fail-safe update branch", function()
        local install = assert(loadfile(peer_owner_path))()
        local mod, calls, deps = fake_peer_runtime(false)
        local original_update = mod.update
        rawset(mod, "update", nil)
        local update_newindex = 0
        local mod_metatable = {
            __index = function(_, name)
                if name == "update" then return original_update end
            end,
            __newindex = function(t, name, value)
                if name == "update" then
                    update_newindex = update_newindex + 1
                    error("fail-safe update reached __newindex")
                end
                rawset(t, name, value)
            end,
        }
        setmetatable(mod, mod_metatable)
        H.equal(install(mod, deps), true)
        H.equal(mod._ct_peer_parity, nil)
        H.equal(calls.installs, 0)
        H.equal(#calls.hooks, 0, "fail-safe branch must not install peer hooks")
        H.equal(#calls.commands, 1)
        H.equal(#calls.checks, #PEER_CHECK_NAMES)
        H.truthy(rawequal(getmetatable(mod), mod_metatable),
            "fail-safe branch changed metatable identity")
        H.equal(update_newindex, 0,
            "fail-safe update publication reached inherited __newindex")
        H.equal(type(rawget(mod, "update")), "function",
            "fail-safe owner wrapper was not raw-published")
        H.truthy(not rawequal(mod.update, original_update),
            "fail-safe branch must own its bounded retry wrapper")
        mod.update(0.25)
        H.equal(calls.base_updates, 1, "fail-safe branch dropped the original update")
        H.equal(calls.beacon_updates, 0, "fail-safe branch ran an unavailable beacon")
        H.equal(mod._ct_wire_safe(), false)
    end)

    H.test("CT meta boon extraction ratchets both modules", function()
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local owner = read(base .. "_ct_meta_boon_owner.lua")
        local peer_owner = read(peer_owner_path)
        local _, meta_lines = meta:gsub("\n", "\n")
        local _, owner_lines = owner:gsub("\n", "\n")
        local _, peer_owner_lines = peer_owner:gsub("\n", "\n")
        H.truthy(meta_lines + 1 < 1500,
            "trait wrapper must remain below the target after peer extraction")
        H.truthy(owner_lines + 1 < 1500,
            "new meta-boon owner must start below the target")
        H.truthy(peer_owner_lines + 1 < 1500,
            "new peer-parity owner must start below the target")
    end)
end
