-- Offline proof for #250: issue250_deus_tab_talent_module_loaded FAILed with
-- "Tab talent runtime check missing" in a plain keep session (Rain's
-- 0.2.354-dev log on #1637) although the talent module loaded and its policy
-- check passed.
--
-- Through 0.2.359-dev the outer check ended with
-- `return check and check.fn() or "Tab talent runtime check missing"`. The
-- inner issue250_deus_tab_talent_tier_normalization returns nil on PASS, so
-- `check and nil` is nil and the `or` branch reported "missing" exactly when
-- the inner check passed. The inner check was also never registered by name:
-- only _gut_tab_property_refresh.lua dofiles the talent module.
--
-- These cases load the shipped provider whole, with the real property policy,
-- talent refresh and talent policy, in a test-local environment (get_mod,
-- IngamePlayerListUI and Managers resolve there; no global is swapped), and
-- judge each check with the /gut_regression_test PASS predicate
-- (gui_tweaker_dev.lua:155-156: pcall ok and a nil result).
return function(H, repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local MODULE = "issue250_deus_tab_talent_module_loaded"
    local INNER = "issue250_deus_tab_talent_tier_normalization"

    -- opts.mechanism: Managers.mechanism:current_mechanism_name() ("inn" = keep)
    -- opts.talent: "missing" (dofile throws), "no_checks" (module without
    --   rt_checks), "broken_policy" (talent policy tier count drifted)
    local function load_provider(opts)
        opts = opts or {}
        local env = setmetatable({}, { __index = _G })
        env._G = env
        local mod = { hooks = {} }
        for _, name in ipairs({ "debug", "info", "echo", "warning", "error" }) do
            mod[name] = function() end
        end
        function mod:hook(target, method, fn)
            self.hooks[#self.hooks + 1] = { target = target, method = method, fn = fn }
        end
        local function load_into_env(name)
            local chunk = assert(loadfile(base .. name .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        function mod:dofile(path)
            local name = path:match("([^/]+)$")
            if name == "_gut_tab_talent_refresh" then
                if opts.talent == "missing" then
                    error("cannot open " .. path)
                elseif opts.talent == "no_checks" then
                    return { refresh = function() return 0 end }
                end
            end
            local result = load_into_env(name)
            if name == "_gut_tab_talent_policy" and opts.talent == "broken_policy" then
                result.TIERS = 5
            end
            return result
        end
        env.get_mod = function() return mod end
        env.printf = function() end
        env.IngamePlayerListUI = {
            _update_dynamic_widget_information = function() end,
            _setup_mission_data = function() end,
        }
        local mechanism = opts.mechanism or "inn"
        env.Managers = {
            mechanism = { current_mechanism_name = function() return mechanism end },
        }
        local api = load_into_env("_gut_tab_property_refresh")
        return api, mod
    end

    local function checks_by_name(api)
        local by_name, order = {}, {}
        for _, check in ipairs(api.rt_checks or {}) do
            by_name[check.name] = check
            order[#order + 1] = check.name
        end
        return by_name, order
    end

    -- The runner's verdict (gui_tweaker_dev.lua:155-167).
    local function verdict(check)
        local ok, err = pcall(check.fn)
        if ok and err == nil then return "PASS", nil end
        if ok and type(err) == "string" and err:sub(1, 5) == "skip:" then return "SKIP", err end
        return "FAIL", tostring(err)
    end

    H.test("GUT #250 module-loaded check PASSes in a plain keep session", function()
        local api = load_provider({ mechanism = "inn" })
        local by_name = checks_by_name(api)
        H.truthy(by_name[MODULE] ~= nil, "module-loaded check registered")
        local result, msg = verdict(by_name[MODULE])
        H.equal(result, "PASS", "module-loaded verdict: " .. tostring(msg))
    end)

    H.test("GUT #250 module-loaded check PASSes inside Chaos Wastes too", function()
        local api = load_provider({ mechanism = "deus" })
        local result, msg = verdict(checks_by_name(api)[MODULE])
        H.equal(result, "PASS", "module-loaded verdict: " .. tostring(msg))
    end)

    H.test("GUT #250 tier-normalization check is reported by its own name", function()
        local api = load_provider()
        local by_name, order = checks_by_name(api)
        H.truthy(by_name[INNER] ~= nil, "inner check forwarded to the harness")
        local count = 0
        for _, name in ipairs(order) do
            if name == INNER then count = count + 1 end
        end
        H.equal(count, 1, "inner check registered exactly once")
        local result, msg = verdict(by_name[INNER])
        H.equal(result, "PASS", "inner verdict: " .. tostring(msg))
    end)

    H.test("GUT #250 module-loaded check surfaces a real inner failure", function()
        local api = load_provider({ talent = "broken_policy" })
        local by_name = checks_by_name(api)
        local result, msg = verdict(by_name[MODULE])
        H.equal(result, "FAIL")
        H.equal(msg, "talent tier/log bounds drifted")
        result, msg = verdict(by_name[INNER])
        H.equal(result, "FAIL")
        H.equal(msg, "talent tier/log bounds drifted")
    end)

    H.test("GUT #250 module-loaded check FAILs loudly when the module is gone", function()
        local api = load_provider({ talent = "missing" })
        local by_name = checks_by_name(api)
        H.equal(by_name[INNER], nil, "nothing to forward")
        local result, msg = verdict(by_name[MODULE])
        H.equal(result, "FAIL")
        H.truthy(msg:find("Tab talent normalization module failed to load", 1, true) ~= nil, msg)

        api = load_provider({ talent = "no_checks" })
        result, msg = verdict(checks_by_name(api)[MODULE])
        H.equal(result, "FAIL")
        H.equal(msg, "Tab talent runtime check missing")
    end)

    H.test("GUT #250 provider still owns both panel hooks after the forward", function()
        local api, mod = load_provider()
        local methods = {}
        for _, hook in ipairs(mod.hooks) do methods[hook.method] = true end
        H.truthy(methods._update_dynamic_widget_information, "dynamic-update hook")
        H.truthy(methods._setup_mission_data, "#533 mission-row hook")
        local by_name = checks_by_name(api)
        for _, name in ipairs({ "issue245_tab_weapon_property_refresh",
            "issue246_tab_equipped_illusion_refresh",
            "issue533_cw_collectible_rows_suppressed" }) do
            H.truthy(by_name[name] ~= nil, name .. " registered")
            local result, msg = verdict(by_name[name])
            H.equal(result, "PASS", name .. ": " .. tostring(msg))
        end
    end)
end
