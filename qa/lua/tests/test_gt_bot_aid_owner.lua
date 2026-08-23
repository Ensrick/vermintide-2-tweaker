return function(H, repo_root)
    local path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_aid_owner.lua"

    local function new_mod(hook_impl)
        local hooks = {}
        local mod = {
            get = function() return false end,
            debug = function() end,
            _gt_bot_heal_policy = { is_eligible = function() return false end },
            _gt_teleport_loop_policy = {},
        }
        mod.hook = hook_impl or function(_, owner, method, callback)
            hooks[#hooks + 1] = { owner = owner, method = method, callback = callback }
        end
        return mod, hooks
    end

    local function context(mod)
        return {
            mod = mod,
            ScriptUnit = {},
            POSITION_LOOKUP = {},
            HEALTH_ALIVE = {},
            Vector3 = {},
            Unit = {},
            Managers = {},
            ALIVE = {},
            ignore_backward_gate_on = function() return false end,
        }
    end

    H.test("GT bot aid owner installs both hooks once and returns exact API", function()
        local install = assert(loadfile(path))()
        local mod, hooks = new_mod()
        local api = install(context(mod))

        H.equal(#hooks, 2)
        H.equal(hooks[1].owner, "BTConditions")
        H.equal(hooks[1].method, "can_activate_ability")
        H.equal(hooks[2].owner, "PlayerBotBase")
        H.equal(hooks[2].method, "_select_ally_by_utility")
        H.equal(type(hooks[1].callback), "function")
        H.equal(type(hooks[2].callback), "function")
        H.equal(api.status_needs_aid, mod._gt_status_needs_aid)
        H.equal(api.unit_needs_aid, mod._gt_unit_needs_aid)
        H.equal(api.aid_priority_on, mod._gt_aid_priority_on)
        H.equal(api.any_side_teammate_needs_aid, mod._gt_any_side_teammate_needs_aid)
        H.equal(api.label, mod._gt492_label)
        H.equal(mod._gt_bot_aid_owner_installed, true)

        local ok, err = pcall(install, context(mod))
        H.equal(ok, false)
        H.truthy(tostring(err):find("already installed", 1, true))
        H.equal(#hooks, 2)
    end)

    H.test("GT bot aid owner rejects missing dependencies before hooks", function()
        local install = assert(loadfile(path))()
        local mod, hooks = new_mod()

        local nil_ok = pcall(install, nil)
        H.equal(nil_ok, false)
        H.equal(#hooks, 0)
        local cases = {
            {},
            { mod = mod },
            { mod = {}, ignore_backward_gate_on = function() end },
        }
        for _, candidate in ipairs(cases) do
            local ok = pcall(install, candidate)
            H.equal(ok, false)
            H.equal(#hooks, 0)
        end

        local dependency_names = {
            "ScriptUnit",
            "POSITION_LOOKUP",
            "HEALTH_ALIVE",
            "Vector3",
            "Unit",
            "Managers",
            "ALIVE",
        }
        for _, name in ipairs(dependency_names) do
            local candidate = context(mod)
            candidate[name] = nil
            local ok, err = pcall(install, candidate)
            H.equal(ok, false)
            H.truthy(tostring(err):find("requires " .. name, 1, true))
            H.equal(#hooks, 0)
        end
    end)

    H.test("GT bot aid owner propagates registration failure without claiming install", function()
        local install = assert(loadfile(path))()
        local calls = 0
        local mod = new_mod(function()
            calls = calls + 1
            error("planted hook failure")
        end)

        local ok, err = pcall(install, context(mod))
        H.equal(ok, false)
        H.truthy(tostring(err):find("planted hook failure", 1, true))
        H.equal(calls, 1)
        H.equal(mod._gt_bot_aid_owner_installed, nil)
    end)
end
