return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = base .. "_ct_bomb_cooldown_display.lua"
    local combat_path = base .. "_ct_combat_hooks.lua"
    local main_path = base .. "chaos_wastes_tweaker_dev.lua"

local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
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

    -- ============================================================
    -- #358 ready-state machine: behavioral tests driving the REAL shipped
    -- module (loadfile) through in-game-reachable transitions on a faithful
    -- BuffExtension mini-model (add_buff/remove_buff/has_buff_type/
    -- get_buff_type/active_buffs semantics from buff_extension.lua).
    -- ============================================================
    local function make_fake_buff_ext(templates)
        local ext = { _buffs = {}, _next_id = 1 }
        function ext:add_buff(template_name, params)
            local template = templates[template_name]
            if not template then return nil end
            local sub = template.buffs[1]
            local duration = (params and params.external_optional_duration) or sub.duration
            local id = self._next_id
            self._next_id = id + 1
            self._buffs[#self._buffs + 1] = {
                id = id, buff_type = sub.name, template = sub, duration = duration,
            }
            return id
        end
        function ext:add_owned(buff_type)
            local id = self._next_id
            self._next_id = id + 1
            self._buffs[#self._buffs + 1] = { id = id, buff_type = buff_type }
            return id
        end
        function ext:remove_buff(id)
            for i = #self._buffs, 1, -1 do
                if self._buffs[i].id == id then table.remove(self._buffs, i) end
            end
        end
        function ext:remove_type(buff_type)
            for i = #self._buffs, 1, -1 do
                if self._buffs[i].buff_type == buff_type then table.remove(self._buffs, i) end
            end
        end
        function ext:has_buff_type(buff_type)
            for _, buff in ipairs(self._buffs) do
                if buff.buff_type == buff_type then return true end
            end
            return false
        end
        function ext:get_buff_type(buff_type)
            for _, buff in ipairs(self._buffs) do
                if buff.buff_type == buff_type then return buff end
            end
            return nil
        end
        function ext:count_type(buff_type)
            local n = 0
            for _, buff in ipairs(self._buffs) do
                if buff.buff_type == buff_type then n = n + 1 end
            end
            return n
        end
        function ext:active_buffs()
            return self._buffs, #self._buffs
        end
        return ext
    end

    local function load_ready_state_world()
        local saved = {
            get_mod = _G.get_mod, BuffTemplates = _G.BuffTemplates,
            Managers = _G.Managers, ScriptUnit = _G.ScriptUnit,
        }
        local world = { toggle = true }
        local fake_mod = {}
        function fake_mod:network_register(channel, callback)
            self.channel, self.callback = channel, callback
        end
        fake_mod._ct_effective_setting = function(name)
            if name == "tweak_manann_tempest_cooldown" then return world.toggle end
        end
        _G.get_mod = function() return fake_mod end
        _G.BuffTemplates = {}
        local module = assert(loadfile(module_path))()
        assert(module.install(1))
        local ext = make_fake_buff_ext(_G.BuffTemplates)
        local unit = { "player_unit" }
        local owner = {
            local_player = true,
            is_player_controlled = function() return true end,
        }
        _G.Managers = {
            player = {
                is_server = true,
                local_player = function() return { player_unit = unit } end,
                owner = function(_, u) return u == unit and owner or nil end,
            },
        }
        _G.ScriptUnit = {
            has_extension = function(u, system)
                if u == unit and system == "buff_system" then return ext end
                return nil
            end,
        }
        world.module, world.mod, world.ext, world.unit = module, fake_mod, ext, unit
        world.restore = function()
            _G.get_mod = saved.get_mod
            _G.BuffTemplates = saved.BuffTemplates
            _G.Managers = saved.Managers
            _G.ScriptUnit = saved.ScriptUnit
        end
        return world
    end

    local READY_TRAIT = "ct_manann_ready_display_trait"
    local READY_BOON = "ct_manann_ready_display_boon"
    local COOLDOWN_TRAIT = "ct_manann_cooldown_display_trait"
    local COOLDOWN_BOON = "ct_manann_cooldown_display_boon"
    local TRAIT_OWNER = "deus_crit_chain_lightning"
    local BOON_OWNER = "power_up_ct_boon_manann_tempest_unique"

    H.test("CT #358 ready state appears on acquisition and survives idle reconciles", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext = world.module, world.ext
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "no source -> no ready state")
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true, "trait acquisition shows ready")
            H.equal(ext:get_buff_type(READY_TRAIT).duration, nil, "ready state is infinite")
            H.equal(ext:has_buff_type(READY_BOON), false, "boon not owned -> boon stays hidden")
            -- rejected procs never call notify_allowed: idle reconciles are stable
            module.reconcile_manann_ready()
            module.reconcile_manann_ready()
            H.equal(ext:count_type(READY_TRAIT), 1, "idle reconciles never stack ready buffs")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 allowed proc swaps ready for the 8s timer, expiry restores ready", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true)
            H.truthy(module.notify_allowed(unit, "manann_trait", 8), "allowed proc applies locally")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), true, "allowed proc shows the timer")
            H.equal(ext:get_buff_type(COOLDOWN_TRAIT).duration, 8, "timer runs the 8s interval")
            H.equal(ext:has_buff_type(READY_TRAIT), false, "proc removes the ready state")
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "states stay mutually exclusive")
            -- the buff extension removing the finite buff at end_time IS expiry
            ext:remove_type(COOLDOWN_TRAIT)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true, "expiry restores the ready state")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 boon and trait ready states are independent", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            ext:add_owned(BOON_OWNER)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true)
            H.equal(ext:has_buff_type(READY_BOON), true)
            H.truthy(module.notify_allowed(unit, "manann_boon", 8))
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(COOLDOWN_BOON), true, "boon timer runs")
            H.equal(ext:has_buff_type(READY_BOON), false, "boon ready swapped out")
            H.equal(ext:has_buff_type(READY_TRAIT), true, "trait ready untouched by boon proc")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false, "trait timer untouched by boon proc")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 toggle-off and source loss remove both display states", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            local trait_owner_id = ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.truthy(module.notify_allowed(unit, "manann_trait", 8))
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), true)
            world.toggle = false
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "toggle off removes ready")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false, "toggle off removes the timer")
            world.toggle = true
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true, "re-enable restores ready")
            ext:remove_buff(trait_owner_id)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "source loss removes ready")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false, "source loss leaves no stale timer")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 ready reconciler ticks through the shared update dispatch", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext = world.module, world.ext
            H.truthy(module._ready_ticker_installed, "install wires the ticker")
            H.equal(type(world.mod._ct_manann_ready_tick), "function",
                "tick published for the mod.update dispatch")
            ext:add_owned(TRAIT_OWNER)
            world.mod._ct_manann_ready_tick(0.25)
            H.equal(ext:has_buff_type(READY_TRAIT), false, "throttle holds below the interval")
            world.mod._ct_manann_ready_tick(0.3)
            H.equal(ext:has_buff_type(READY_TRAIT), true, "accumulated dt runs the reconcile")
        end)
        world.restore()
        if not ok then error(failure, 0) end
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
