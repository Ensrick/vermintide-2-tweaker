return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Policy = assert(loadfile(root .. "_cim_keep_forge_interaction.lua"))()

    H.test("CIM restores only untrusted Keep forge interaction", function()
        H.equal(Policy.resolve(false, true, true), true)
        H.equal(Policy.resolve(false, true, false), false)
        H.equal(Policy.resolve(false, false, true), false)
        H.equal(Policy.resolve(true, false, false), true)
    end)

    H.test("CIM forge install preserves native stop prompt and original predicate", function()
        local calls = 0
        local original = function()
            calls = calls + 1
            return false
        end
        local defs = {
            forge_access = {
                client = {
                    can_interact = original,
                    stop = function() return "native-transition" end,
                    hud_description = function() return "native-prompt" end,
                },
            },
        }
        local mod = {
            _cim_is_in_keep = function() return false end,
            _cim_is_modded_realm = function() return true end,
        }
        local ok = Policy.install(mod, defs, function() end)
        H.truthy(ok)
        H.equal(defs.forge_access.client.can_interact(), false)
        H.equal(calls, 1)
        H.equal(defs.forge_access.client.stop(), "native-transition")
        H.equal(defs.forge_access.client.hud_description(), "native-prompt")
    end)

    H.test("CIM Keep forge uses shared authority inside MP's EAC-off window", function()
        local original = function() return false end
        local defs = { forge_access = { client = { can_interact = original } } }
        local mod = {
            _cim_is_in_keep = function() return true end,
            _cim_is_modded_realm = function() return true end,
        }
        H.truthy(Policy.install(mod, defs, function() end))
        H.equal(defs.forge_access.client.can_interact(), true)
    end)

    H.test("CIM forge install is reload-idempotent", function()
        local original = function() return false end
        local defs = { forge_access = { client = { can_interact = original } } }
        local mod = {
            _cim_is_in_keep = function() return false end,
            _cim_is_modded_realm = function() return false end,
        }
        H.truthy(Policy.install(mod, defs, function() end))
        local installed = defs.forge_access.client.can_interact
        H.truthy(Policy.install(mod, defs, function() end))
        H.equal(mod._cim_keep_forge_interaction_state.original_can_interact, original)
        H.equal(defs.forge_access.client.can_interact, installed)
    end)
    local proof_path = root .. "_cim_regression_keep_forge.lua"
    local Proof = assert(loadfile(proof_path))()
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a"); file:close()
        return (source:gsub("\r\n", "\n"))
    end
    local owner_source = read(root .. "_cim_keep_forge_interaction.lua")
    local function load_owner(source, private_printf)
        local forbidden = { Managers = true, GameSettingsDevelopment = true,
            script_data = true, Unit = true, World = true, get_mod = true }
        local environment = setmetatable({ printf = private_printf }, { __index = function(_, key)
            assert(not forbidden[key] and key ~= "printf", "unexpected engine/global contact: " .. key)
            return _G[key]
        end })
        return setfenv(assert(loadstring(source, "@detached-cim624-owner")), environment)()
    end
    local function mutate(before, after)
        local from, last = assert(owner_source:find(before, 1, true))
        assert(not owner_source:find(before, last + 1, true), "ambiguous mutation")
        return load_owner(owner_source:sub(1, from - 1) .. after .. owner_source:sub(last + 1))
    end
    local function named(policy, load_kind)
        local definitions = { forge_access = { client = { can_interact = function() return false end } } }
        local mod = {
            _cim_keep_forge_interaction = policy,
            _cim_is_modded_realm = function() return true end,
            _cim_is_in_keep = function() return true end,
        }
        assert(Policy.install(mod, definitions, function() end))
        local loads = 0
        mod.dofile = function(_, path)
            assert(path == "scripts/mods/crafting_in_modded_dev/_cim_regression_keep_forge")
            loads = loads + 1
            if load_kind == "throw" then error("missing detached proof") end
            if load_kind == "shape" then return {} end
            return assert(loadfile(proof_path))()
        end
        local registered = {}
        -- The real registration owner reads this private definitions table;
        -- no live _G member or engine object is changed.
        local environment = setmetatable({ _G = { InteractionDefinitions = definitions } }, { __index = _G })
        setfenv(assert(loadfile(root .. "_cim_regression_checks.lua")), environment)()({
            mod = mod,
            rt_register = function(name, callback)
                assert(not registered[name]); registered[name] = callback
            end,
        })
        return assert(registered.issue624_keep_forge_interaction), mod, definitions,
            function() return loads end
    end

    H.test("CIM named Keep forge proof executes production install without engine contact", function()
        H.equal(Proof(load_owner(owner_source)), nil)
    end)
    H.test("CIM issue624 real registration executes the detached installed-predicate proof", function()
        local check, _, _, loads = named(Policy)
        H.equal(check(), nil)
        H.equal(loads(), 1)
    end)
    H.test("CIM issue624 keeps the live installation identity audit", function()
        local check, _, definitions, loads = named(Policy)
        definitions.forge_access.client.can_interact = function() return true end
        H.truthy(check():find("another writer", 1, true))
        H.equal(loads(), 0)
    end)
    H.test("CIM issue624 missing installation fails before detached proof", function()
        local check, mod, _, loads = named(Policy)
        mod._cim_keep_forge_interaction_state = nil
        H.truthy(check():find("not installed", 1, true))
        H.equal(loads(), 0)
    end)
    H.test("CIM issue624 missing production installer fails rather than skips", function()
        local check = named({ resolve = Policy.resolve })
        H.truthy(check():find("not loaded", 1, true))
        H.equal(pcall(Proof, {}), false)
    end)
    H.test("CIM issue624 missing or malformed detached dependency fails rather than skips", function()
        for _, kind in ipairs({ "throw", "shape" }) do
            local check = named(Policy, kind)
            H.truthy(check():find("did not load", 1, true))
        end
    end)
    H.test("CIM issue624 rejects stale EAC adapter despite passing pure policy", function()
        local owner = mutate("is_modded = ok and resolved == true", "is_modded = false")
        H.equal(owner.resolve(false, true, true), true)
        local check = named(owner)
        H.truthy(check():find("native-false modded Keep", 1, true))
    end)
    H.test("CIM issue624 detects a production wrapper dropping its override", function()
        local check = named(mutate("return result\n", "return original_result\n"))
        H.truthy(check():find("native-false modded Keep", 1, true))
    end)
    H.test("CIM issue624 detects native argument reordering", function()
        local check = named(mutate(
            "original(interactor_unit, interactable_unit, data, config)",
            "original(interactable_unit, interactor_unit, data, config)"))
        H.truthy(check():find("native arguments changed", 1, true))
    end)
    H.test("CIM issue624 detects official and non-Keep scope widening", function()
        for _, pair in ipairs({
            { "eac_untrusted == true and in_keep == true", "in_keep == true" },
            { "eac_untrusted == true and in_keep == true", "eac_untrusted == true" },
        }) do
            local check = named(mutate(pair[1], pair[2]))
            H.truthy(check():find("boundary widened", 1, true))
        end
    end)
    H.test("CIM issue624 detects swallowed native exceptions", function()
        local check = named(mutate(
            "local original_result = original(interactor_unit, interactable_unit, data, config)",
            "local ok_native, original_result = pcall(original, interactor_unit, interactable_unit, data, config)\n"
            .. "        if not ok_native then original_result = false end"))
        H.truthy(check():find("native error/order contract", 1, true))
    end)
    H.test("CIM issue624 detects unbounded repeated first-use reports", function()
        local check = named(mutate("and not state.reported then", "then"))
        H.truthy(check():find("bounded native forge report", 1, true))
    end)
    H.test("CIM Keep forge preserves original single result and explicit native call shape", function()
        local owner = load_owner(owner_source)
        local called, marker = 0, {}
        local defs = { forge_access = { client = { can_interact = function(...)
            called = select("#", ...)
            return false, nil, marker
        end } } }
        H.truthy(owner.install({ _cim_is_in_keep = function() return false end }, defs, function() end))
        local result = { n = select("#", defs.forge_access.client.can_interact(1, nil, 3, nil, 5)),
            defs.forge_access.client.can_interact(1, nil, 3, nil, 5) }
        H.equal(called, 4) -- The native owner has exactly four arguments, not varargs.
        H.equal(result.n, 1)
        H.equal(result[1], false)
    end)
    H.test("CIM Keep forge default logger retains exact first-use message", function()
        local log = {}
        local owner = load_owner(owner_source, function(message) log[#log + 1] = message end)
        local defs = { forge_access = { client = { can_interact = function() return false end } } }
        H.truthy(owner.install({ _cim_is_modded_realm = function() return true end,
            _cim_is_in_keep = function() return true end }, defs))
        H.equal(defs.forge_access.client.can_interact(), true)
        H.equal(defs.forge_access.client.can_interact(), true)
        H.deep_equal(log, { "[cim:624] Keep forge interaction enabled; native forge transition retained" })
    end)
end
