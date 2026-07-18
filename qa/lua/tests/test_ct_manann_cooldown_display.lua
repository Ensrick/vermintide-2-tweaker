return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = base .. "_ct_bomb_cooldown_display.lua"
    local combat_path = base .. "_ct_combat_hooks.lua"
    local main_path = base .. "chaos_wastes_tweaker_dev.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_isolated()
        local saved_get_mod = _G.get_mod
        local saved_templates = _G.BuffTemplates
        local fake_mod = {}
        function fake_mod:network_register(channel, callback)
            self.channel, self.callback = channel, callback
        end
        _G.get_mod = function() return fake_mod end
        _G.BuffTemplates = {}
        local ok, module = pcall(assert(loadfile(module_path)))
        return ok, module, fake_mod, saved_get_mod, saved_templates
    end

    H.test("CT #358 registers independent boon and trait cooldown timers", function()
        local ok, module, _, old_get_mod, old_templates = load_isolated()
        local test_ok, failure = pcall(function()
            H.truthy(ok, tostring(module))
            H.truthy(module.install(1))
            local boon = module.manann_sources.manann_boon
            local trait = module.manann_sources.manann_trait
            H.truthy(boon and trait)
            H.truthy(boon.template ~= trait.template)
            H.equal(boon.icon, "deus_icon_trait_crit_chain_lightning")
            H.equal(trait.icon, "deus_icon_trait_crit_chain_lightning")
            H.equal(_G.BuffTemplates[boon.template].buffs[1].is_cooldown, true)
            H.equal(_G.BuffTemplates[trait.template].buffs[1].is_cooldown, true)
            H.truthy(module.valid_payload("manann_boon", 8))
            H.truthy(module.valid_payload("manann_trait", 8))
            H.equal(module.regression_check_manann(1), nil)
        end)
        _G.get_mod = old_get_mod
        _G.BuffTemplates = old_templates
        if not test_ok then error(failure, 0) end
    end)

    H.test("CT #358 notification follows only the real allowed proc branch", function()
        local combat = read(combat_path)
        local toggle = assert(combat:find(
            'if not effective_setting("tweak_manann_tempest_cooldown") then', 1, true))
        local eligibility = assert(combat:find(
            "if not (ALIVE[owner_unit] and ALIVE[hit_unit] and first_hit and is_critical_strike) then",
            toggle, true))
        local rejection = assert(combat:find("if t < bucket[key] then", eligibility, true))
        local stamp = assert(combat:find(
            "bucket[key] = t + MANANN_TEMPEST_COOLDOWN_S", rejection, true))
        local notify = assert(combat:find("display.notify_allowed(owner_unit,", stamp, true))
        local vanilla = assert(combat:find(
            "return func(owner_unit, buff, params, world, param_order)", notify, true))
        H.truthy(toggle < eligibility and eligibility < rejection and rejection < stamp)
        H.truthy(stamp < notify and notify < vanilla)
        H.truthy(combat:find('is_boon and "manann_boon" or "manann_trait"', notify, true))
        H.truthy(combat:find("local MANANN_TEMPEST_COOLDOWN_S = 8.0", 1, true))
    end)

    H.test("CT #358 has offline and runtime regression wiring", function()
        local module_source = read(module_path)
        -- The runtime regression check moved to _ct_regression.lua (OOP W5 suite
        -- extraction); it is registered from there via mod._ct_rt_register.
        H.truthy(read(base .. "_ct_regression.lua"):find(
            "issue358_manann_tempest_cooldown_display", 1, true))
        H.equal(module_source:find("NetworkLookup.buff_templates[", 1, true), nil)
        H.truthy(module_source:find("function M.regression_check_manann", 1, true))
    end)
end
