return function(H, repo_root)
    local path = repo_root .. "/tools/shared_lib/_lib_modded_realm_authority.lua"
    local Authority = assert(loadfile(path))()

    H.test("modded realm authority accepts only exact raw flag or balanced depth", function()
        H.equal(Authority.is_modded({ ["eac-untrusted"] = true }, 0), true)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = false }, 1), true)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = nil }, 2), true)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = "true" }, 0), false)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = 1 }, 0), false)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = false }, 0.5), false)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = false }, math.huge), false)
        H.equal(Authority.is_modded(nil, 1), true)

        local inherited = setmetatable({}, { __index = { ["eac-untrusted"] = true } })
        H.equal(Authority.is_modded(inherited, 0), false)
    end)

    H.test("launch parameter authority survives a cleared or falsely restored raw flag", function()
        local hyphen = { application_parameter = { ["eac-untrusted"] = true } }
        local underscore = { application_parameter = { eac_untrusted = true } }
        local present_false = { application_parameter = { ["eac-untrusted"] = false } }
        H.equal(Authority.is_modded({ ["eac-untrusted"] = false }, 0, hyphen), true)
        H.equal(Authority.is_modded({ ["eac-untrusted"] = nil }, 0, underscore), true)
        H.equal(Authority.is_modded({}, 0, present_false), true)
        H.equal(Authority.is_modded({}, 0, { application_parameter = {} }), false)
        H.equal(Authority.is_modded({}, 0, { application_parameter = "bad" }), false)

        local inherited_parameters = setmetatable({}, {
            __index = { ["eac-untrusted"] = true },
        })
        local inherited_development = setmetatable({}, {
            __index = { application_parameter = hyphen.application_parameter },
        })
        H.equal(Authority.is_modded({}, 0,
            { application_parameter = inherited_parameters }), false)
        H.equal(Authority.is_modded({}, 0, inherited_development), false)
    end)

    H.test("modded realm authority preserves nested nil-hole returns and restores state", function()
        local script = { ["eac-untrusted"] = true }
        local state = { _mp_eac_depth = 0, _mp_modded_depth = 0 }
        local outer_depth, nested_depth
        local a, b, c = Authority.with_eac_off(script, state, function(_, x, y, z)
            outer_depth = state._mp_eac_depth
            local inner = Authority.with_eac_off(script, state, function()
                nested_depth = state._mp_eac_depth
                H.equal(Authority.is_modded(script, state._mp_modded_depth), true)
                return "inner", nil, "tail"
            end, nil, nil)
            H.equal(inner, "inner")
            return x, y, z
        end, nil, nil, 1, nil, 3)
        H.equal(a, 1)
        H.equal(b, nil)
        H.equal(c, 3)
        H.equal(outer_depth, 1)
        H.equal(nested_depth, 2)
        H.equal(script["eac-untrusted"], true)
        H.equal(state._mp_eac_depth, 0)
        H.equal(state._mp_modded_depth, 0)
    end)

    H.test("modded realm authority restores before reporting and re-raises original error", function()
        local sentinel = {}
        local script = { ["eac-untrusted"] = sentinel }
        local state = { _mp_eac_depth = 3, _mp_modded_depth = 4 }
        local observed
        local ok, err = pcall(Authority.with_eac_off, script, state, function()
            error("authority_test_boom")
        end, nil, function(message)
            observed = { message = message, flag = script["eac-untrusted"],
                eac = state._mp_eac_depth, modded = state._mp_modded_depth }
            error("observer_must_not_replace_original")
        end)
        H.equal(ok, false)
        H.truthy(tostring(err):find("authority_test_boom", 1, true) ~= nil)
        H.equal(observed.message:find("authority_test_boom", 1, true) ~= nil, true)
        H.equal(observed.flag, sentinel)
        H.equal(observed.eac, 3)
        H.equal(observed.modded, 4)
    end)

    H.test("modded realm authority unwinds a modded depth after a throw", function()
        local script = { ["eac-untrusted"] = true }
        local state = { _mp_eac_depth = 0, _mp_modded_depth = 0 }
        local observed_depth
        local ok = pcall(Authority.with_eac_off, script, state, function()
            observed_depth = state._mp_modded_depth
            error("modded_depth_boom")
        end, nil)
        H.equal(ok, false)
        H.equal(observed_depth, 1)
        H.equal(script["eac-untrusted"], true)
        H.equal(state._mp_eac_depth, 0)
        H.equal(state._mp_modded_depth, 0)
    end)

    H.test("CIM flag-only bracket preserves nil holes and restores after error", function()
        local script = { ["eac-untrusted"] = true }
        local a, b, c = Authority.with_eac_off(script, nil, function()
            H.equal(script["eac-untrusted"], nil)
            return 1, nil, 3
        end, nil)
        H.equal(a, 1)
        H.equal(b, nil)
        H.equal(c, 3)
        H.equal(script["eac-untrusted"], true)
        H.equal(pcall(Authority.with_eac_off, script, nil, function()
            error("cim_flag_boom")
        end, nil), false)
        H.equal(script["eac-untrusted"], true)
    end)

    H.test("CIM outer and MP inner brackets retain modded authority", function()
        local script = { ["eac-untrusted"] = true }
        local state = { _mp_eac_depth = 0, _mp_modded_depth = 0 }
        local mp = {
            with_eac_off = function(func, self, ...)
                return Authority.with_eac_off(script, state, func, self, nil, ...)
            end,
        }
        local function mp_inner(func, self, ...)
            return mp.with_eac_off(func, self, ...)
        end
        local a, b, c = Authority.sibling_with_eac_off(script, function() return mp end,
            function(_, x, y, z)
                return mp_inner(function()
                    H.equal(Authority.is_modded(script, state._mp_modded_depth), true)
                    H.equal(state._mp_eac_depth, 2)
                    H.equal(state._mp_modded_depth, 1)
                    return x, y, z
                end, nil)
            end, nil, nil, 1, nil, 3)
        H.equal(a, 1)
        H.equal(b, nil)
        H.equal(c, 3)
        H.equal(script["eac-untrusted"], true)
        H.equal(state._mp_eac_depth, 0)
        H.equal(state._mp_modded_depth, 0)
    end)

    H.test("CIM sibling resolver fails closed against malformed or hostile providers", function()
        H.equal(Authority.sibling_is_modded({ ["eac-untrusted"] = true }, function()
            error("raw authority must short-circuit before lookup")
        end), true)
        H.equal(Authority.sibling_is_modded({ ["eac-untrusted"] = false }, function()
            error("launch authority must short-circuit before lookup")
        end, { application_parameter = { ["eac-untrusted"] = true } }), true)
        H.equal(Authority.sibling_is_modded({}, function() return nil end), false)
        H.equal(Authority.sibling_is_modded({}, function() error("lookup boom") end), false)
        H.equal(Authority.sibling_is_modded({}, function() return { is_modded_realm = "true" } end), false)
        H.equal(Authority.sibling_is_modded({}, function()
            return { is_modded_realm = function() error("provider boom") end }
        end), false)
        H.equal(Authority.sibling_is_modded({}, function()
            return { is_modded_realm = function() return "true" end }
        end), false)
        H.equal(Authority.sibling_is_modded({}, function()
            return { is_modded_realm = function() return true end }
        end), true)
    end)

    H.test("MP, CIM-dev, and GT-dev adopt the shared authority", function()
        local function read(relative)
            local file = assert(io.open(repo_root .. relative, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        local mp = read("/modded_progression/scripts/mods/modded_progression/modded_progression.lua")
        local cim = read("/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        local swap = read("/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/illusion_swap.lua")
        local forge = read("/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/standard_forge.lua")
        local gt = read("/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_level_control.lua")
        H.truthy(mp:find("RealmAuthority.with_eac_off", 1, true) ~= nil)
        H.truthy(mp:find("mod.with_eac_off = function", 1, true) ~= nil)
        H.truthy(mp:find("mod.is_modded_realm = function()", 1, true) ~= nil)
        H.truthy(mp:find("local function _route_store_login_claim_for_realm", 1, true) ~= nil)
        H.truthy(mp:find(
            '_rt_register("modded_daily_realm_boundary"', 1, true) ~= nil)
        H.equal(mp:find(
            '_rt_register("simulated_daily_realm_boundary"', 1, true), nil)
        H.truthy(cim:find("mod._cim_is_modded_realm = function()", 1, true) ~= nil)
        H.truthy(cim:find("mod._cim_with_eac_off = function(func", 1, true) ~= nil)
        H.truthy(cim:find("RealmAuthority.sibling_with_eac_off", 1, true) ~= nil)
        H.truthy(cim:find("_lib_modded_realm_authority", 1, true) ~= nil)
        H.equal(swap:find('if script_data["eac-untrusted"]', 1, true), nil)
        H.equal(forge:find('if script_data["eac-untrusted"]', 1, true), nil)
        H.truthy(swap:find("_is_modded_realm()", 1, true) ~= nil)
        H.truthy(swap:find("_with_eac_off(func", 1, true) ~= nil)
        H.truthy(forge:find("_is_modded_realm()", 1, true) ~= nil)
        H.truthy(forge:find("_with_eac_off(func", 1, true) ~= nil)
        H.truthy(gt:find("_lib_modded_realm_authority", 1, true) ~= nil)
        H.truthy(gt:find("BackendGuard.reconcile", 1, true) ~= nil)
    end)
end
