return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = base .. "_ct_bomb_cooldown_display.lua"
    local combat_path = base .. "_ct_combat_hooks.lua"

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
            H.truthy(module.install(2))
            local boon = module.manann_sources.manann_boon
            local trait = module.manann_sources.manann_trait
            H.truthy(boon and trait)
            H.truthy(boon.template ~= trait.template)
            H.equal(boon.icon, "deus_icon_trait_crit_chain_lightning")
            H.equal(trait.icon, "deus_icon_trait_crit_chain_lightning")
            H.equal(_G.BuffTemplates[boon.template].buffs[1].is_cooldown, true)
            H.equal(_G.BuffTemplates[trait.template].buffs[1].is_cooldown, true)
            H.truthy(module.valid_payload("manann_boon", 8, 1))
            H.truthy(module.valid_payload("manann_trait", 8, 1))
            H.equal(module.valid_payload("manann_trait", 8), false)
            H.equal(module.valid_payload("boon_supportbomb_speed_01", 30, 1), false)
            H.equal(module.regression_check_manann(2), nil)
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
        local notify = assert(combat:find("pcall(display.notify_allowed, owner_unit,", stamp, true))
        local vanilla = assert(combat:find(
            "return func(owner_unit, buff, params, world, param_order)", notify, true))
        H.truthy(toggle < eligibility and eligibility < rejection and rejection < stamp)
        H.truthy(stamp < notify and notify < vanilla)
        H.truthy(combat:find('is_boon and "manann_boon" or "manann_trait"', notify, true))
        H.truthy(combat:find("local MANANN_TEMPEST_COOLDOWN_S = 8.0", 1, true))
    end)

    H.test("CT #358 real chain_lightning hook resets authoritative deadlines and generations on rewind", function()
        local saved = {
            get_mod = _G.get_mod, ProcFunctions = _G.ProcFunctions,
            Managers = _G.Managers, ALIVE = _G.ALIVE, printf = _G.printf,
        }
        local now, calls, receipts, logs = 100, 0, {}, {}
        local fake_mod = {
            _ct_effective_setting = function(name)
                return name == "tweak_manann_tempest_cooldown"
            end,
            _ct_bomb_cooldown_display = {
                notify_allowed = function(unit, source, interval, generation)
                    receipts[#receipts + 1] = { unit, source, interval, generation }
                    return true
                end,
            },
        }
        function fake_mod:debug() end
        function fake_mod:get() return nil end
        function fake_mod:hook(class, method, wrapper)
            self.chain_lightning_hook = wrapper
        end
        _G.get_mod = function() return fake_mod end
        _G.ProcFunctions = { chain_lightning = function()
            calls = calls + 1
            return "vanilla", 42, nil, "tail"
        end }
        _G.Managers = { time = { time = function() return now end } }
        _G.ALIVE = setmetatable({}, { __index = function() return true end })
        _G.printf = function(fmt, ...)
            logs[#logs + 1] = string.format(fmt, ...)
        end

        local ok, failure = pcall(function()
            local combat = read(combat_path)
            local boundary = assert(combat:find(
                "-- v0.7.171-dev — Mathlann's Storm-Strike", 1, true))
            assert(loadstring(combat:sub(1, boundary - 1), "@_ct_combat_hooks_manann.lua"))()
            local hook = assert(fake_mod.chain_lightning_hook)
            local owner, hit = {}, {}
            local params = { hit, true, true }
            local order = { attacked_unit = 1, first_hit = 2, is_critical_strike = 3 }
            local trait = { template = { name = "deus_crit_chain_lightning" } }
            local boon = { template = { name = "power_up_ct_boon_manann_tempest_unique" } }
            local original = _G.ProcFunctions.chain_lightning

            hook(original, owner, trait, params, {}, order)
            H.equal(calls, 1)
            H.deep_equal(receipts[1], { owner, "manann_trait", 8, 1 })
            now = 104
            hook(original, owner, trait, params, {}, order)
            H.equal(calls, 1, "authoritative cooldown rejects an early second proc")
            H.equal(#receipts, 1)

            now = 0
            hook(original, owner, trait, params, {}, order)
            H.equal(calls, 2, "same-unit clock rewind releases the old timeline")
            H.deep_equal(receipts[2], { owner, "manann_trait", 8, 2 })
            hook(original, owner, boon, params, {}, order)
            H.equal(calls, 3)
            H.deep_equal(receipts[3], { owner, "manann_boon", 8, 1 })
            now = 8
            hook(original, owner, trait, params, {}, order)
            H.equal(calls, 4)
            H.deep_equal(receipts[4], { owner, "manann_trait", 8, 3 })

            local notify_attempts = 0
            fake_mod._ct_bomb_cooldown_display.notify_allowed = function()
                notify_attempts = notify_attempts + 1
                error("planted presentation failure")
            end
            now = 16
            local a, b, c, d = hook(original, owner, trait, params, {}, order)
            H.equal(a, "vanilla")
            H.equal(b, 42)
            H.equal(c, nil)
            H.equal(d, "tail")
            H.equal(calls, 5, "presentation failure cannot suppress or duplicate vanilla")
            H.equal(notify_attempts, 1, "one accepted proc makes one notification attempt")

            for i = 2, 6 do
                now = 16 + ((i - 1) * 8)
                hook(original, owner, trait, params, {}, order)
            end
            H.equal(calls, 10, "every accepted proc reaches vanilla exactly once")
            H.equal(notify_attempts, 6, "notification failures never retry in-band")
            H.equal(#logs, 4, "always-on presentation diagnostics have a hard session cap")
            H.truthy(logs[1]:find("[ct:issue358]", 1, true))
        end)
        _G.get_mod, _G.ProcFunctions = saved.get_mod, saved.ProcFunctions
        _G.Managers, _G.ALIVE = saved.Managers, saved.ALIVE
        _G.printf = saved.printf
        if not ok then error(failure, 0) end
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
            printf = _G.printf,
        }
        local world = {
            toggle = true, now = 0, logs = {}, extensions = {}, sent = {}, schema = 2,
        }
        local fake_mod = {}
        function fake_mod:network_register(channel, callback)
            self.channel, self.callback = channel, callback
        end
        function fake_mod:network_send(...)
            world.sent[#world.sent + 1] = { ... }
        end
        fake_mod._ct_effective_setting = function(name)
            if name == "tweak_manann_tempest_cooldown" then return world.toggle end
        end
        _G.get_mod = function() return fake_mod end
        _G.BuffTemplates = {}
        _G.printf = function(fmt, ...)
            world.logs[#world.logs + 1] = string.format(fmt, ...)
        end
        local module = assert(loadfile(module_path))()
        assert(module.install(world.schema))
        local ext = make_fake_buff_ext(_G.BuffTemplates)
        local unit = { "player_unit" }
        local player = { player_unit = unit }
        world.extensions[unit] = ext
        local owner = {
            local_player = true,
            is_player_controlled = function() return true end,
        }
        _G.Managers = {
            player = {
                is_server = true,
                local_player = function() error("unsafe local_player must not be called") end,
                local_player_safe = function() return player end,
                owner = function(_, u) return world.extensions[u] and owner or nil end,
            },
            time = {
                time = function(_, clock)
                    assert(clock == "game")
                    return world.now
                end,
            },
            state = {
                network = { network_client = { server_peer_id = "host-peer" } },
            },
        }
        _G.ScriptUnit = {
            has_extension = function(u, system)
                if system == "buff_system" then return world.extensions[u] end
                return nil
            end,
        }
        world.module, world.mod, world.ext, world.unit = module, fake_mod, ext, unit
        world.player, world.owner = player, owner
        world.receive = function(sender, name, interval, generation, schema)
            return fake_mod.callback(sender, schema or world.schema, name, interval, generation)
        end
        world.new_unit = function(name)
            local replacement = { name or "replacement_unit" }
            local replacement_ext = make_fake_buff_ext(_G.BuffTemplates)
            world.extensions[replacement] = replacement_ext
            player.player_unit = replacement
            return replacement, replacement_ext
        end
        world.restore = function()
            _G.get_mod = saved.get_mod
            _G.BuffTemplates = saved.BuffTemplates
            _G.Managers = saved.Managers
            _G.ScriptUnit = saved.ScriptUnit
            _G.printf = saved.printf
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
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1), "allowed proc applies locally")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), true, "allowed proc shows the timer")
            H.equal(ext:get_buff_type(COOLDOWN_TRAIT).duration, 8, "timer runs the 8s interval")
            H.equal(ext:has_buff_type(READY_TRAIT), false, "proc removes the ready state")
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "states stay mutually exclusive")
            world.now = 8
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true, "expiry restores the ready state")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false,
                "deadline expiry removes any stale finite display")
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
            H.truthy(module.notify_allowed(unit, "manann_boon", 8, 1))
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(COOLDOWN_BOON), true, "boon timer runs")
            H.equal(ext:has_buff_type(READY_BOON), false, "boon ready swapped out")
            H.equal(ext:has_buff_type(READY_TRAIT), true, "trait ready untouched by boon proc")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false, "trait timer untouched by boon proc")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 boon and trait retain independent semantic deadlines", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            ext:add_owned(BOON_OWNER)
            module.reconcile_manann_ready()
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            H.equal(module.deadline_for(unit, "manann_trait"), 8)
            world.now = 2
            H.truthy(module.notify_allowed(unit, "manann_boon", 8, 1))
            H.equal(module.deadline_for(unit, "manann_boon"), 10)

            world.now = 8
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true,
                "trait becomes ready at its own deadline")
            H.equal(ext:has_buff_type(COOLDOWN_BOON), true,
                "boon remains cooling until its later deadline")
            H.equal(ext:has_buff_type(READY_BOON), false)
            world.now = 10
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_BOON), true,
                "boon becomes ready at its independent deadline")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 remote higher generations replace receipt-relative deadlines", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            -- Host proc #1 at h=0 arrives after one second of latency.
            world.now = 1
            world.receive("host-peer", "manann_trait", 8, 1)
            H.equal(module.deadline_for(unit, "manann_trait"), 9)
            H.equal(module.generation_for(unit, "manann_trait"), 1)

            -- Host proc #2 is legitimately allowed at h=8 and arrives with
            -- lower latency while the old receipt-relative deadline is live.
            world.now = 8.1
            world.receive("host-peer", "manann_trait", 8, 2)
            H.equal(module.deadline_for(unit, "manann_trait"), 16.1)
            H.equal(module.generation_for(unit, "manann_trait"), 2)
            H.equal(ext:get_buff_type(COOLDOWN_TRAIT).duration, 8,
                "higher generation replaces the prior timer with a full new interval")

            world.now = 9
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false,
                "old receipt deadline cannot reveal ready during proc #2")
            world.now = 16.1
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 rewind preserves the unit epoch against delayed old packets", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            world.now = 100
            world.receive("host-peer", "manann_trait", 8, 1)
            H.equal(module.generation_for(unit, "manann_trait"), 1)

            world.now = 0
            module.reconcile_manann_ready()
            H.equal(module.deadline_for(unit, "manann_trait"), nil)
            H.equal(module.generation_for(unit, "manann_trait"), 1,
                "clock reset clears visibility but preserves the unit sequence epoch")

            -- A delayed accepted proc from the old clock may arrive first, but
            -- the authoritative new proc has a strictly higher unit generation
            -- and must replace it immediately.
            world.now = 0.1
            world.receive("host-peer", "manann_trait", 8, 2)
            H.equal(module.deadline_for(unit, "manann_trait"), 8.1)
            world.now = 0.2
            world.receive("host-peer", "manann_trait", 8, 3)
            H.equal(module.deadline_for(unit, "manann_trait"), 8.2)
            H.equal(module.generation_for(unit, "manann_trait"), 3)

            world.now = 0.3
            world.receive("host-peer", "manann_trait", 8, 2)
            H.equal(module.deadline_for(unit, "manann_trait"), 8.2,
                "old packet arriving after the new proc cannot poison the mirror")
            H.equal(module.generation_for(unit, "manann_trait"), 3)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 equal and older remote generations never extend or resurrect", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            world.now = 1
            world.receive("host-peer", "manann_trait", 8, 1)
            world.now = 8.1
            world.receive("host-peer", "manann_trait", 8, 2)
            H.equal(module.deadline_for(unit, "manann_trait"), 16.1)

            world.now = 10
            world.receive("host-peer", "manann_trait", 8, 2)
            world.receive("host-peer", "manann_trait", 8, 1)
            H.equal(module.deadline_for(unit, "manann_trait"), 16.1)
            H.equal(module.generation_for(unit, "manann_trait"), 2)
            H.equal(ext:count_type(COOLDOWN_TRAIT), 1)

            world.now = 17
            module.reconcile_manann_ready()
            H.equal(module.deadline_for(unit, "manann_trait"), nil)
            H.equal(module.generation_for(unit, "manann_trait"), 2,
                "expired receipts retain their replay floor")
            world.now = 18
            world.receive("host-peer", "manann_trait", 8, 2)
            world.receive("host-peer", "manann_trait", 8, 1)
            H.equal(module.deadline_for(unit, "manann_trait"), nil,
                "stale traffic cannot resurrect an expired cooldown")
            H.equal(ext:has_buff_type(READY_TRAIT), true)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 remote boon and trait generations are independent", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            ext:add_owned(BOON_OWNER)
            world.now = 1
            world.receive("host-peer", "manann_trait", 8, 1)
            world.now = 2
            world.receive("host-peer", "manann_boon", 8, 1)
            world.now = 8.2
            world.receive("host-peer", "manann_trait", 8, 2)
            H.equal(module.generation_for(unit, "manann_trait"), 2)
            H.equal(module.deadline_for(unit, "manann_trait"), 16.2)
            H.equal(module.generation_for(unit, "manann_boon"), 1)
            H.equal(module.deadline_for(unit, "manann_boon"), 10)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 remote callback rejects foreign and malformed generations", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            world.receive("forged-peer", "manann_trait", 8, 1)
            world.receive("host-peer", "manann_trait", 8, 1, world.schema + 1)
            world.receive("host-peer", "manann_trait", 8, nil)
            world.receive("host-peer", "manann_trait", 8, 0)
            world.receive("host-peer", "manann_trait", 8, 1.5)
            world.receive("host-peer", "manann_trait", 8,
                module.max_manann_generation + 1)
            world.receive("host-peer", "manann_trait", 8, "2")
            H.equal(module.deadline_for(unit, "manann_trait"), nil)
            H.equal(module.generation_for(unit, "manann_trait"), nil)

            -- Generic #357 keeps its exact no-generation callback behavior.
            world.receive("host-peer", "boon_supportbomb_speed_01", 30, nil)
            H.equal(ext:has_buff_type("ct_bomb_cooldown_display_speed"), true)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 local host path accepts authoritative distinct proc generations", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            H.equal(module.generation_for(unit, "manann_trait"), 1)
            H.equal(module.deadline_for(unit, "manann_trait"), 8)
            world.now = 8
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 2))
            H.equal(module.generation_for(unit, "manann_trait"), 2)
            H.equal(module.deadline_for(unit, "manann_trait"), 16)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 remote transport carries authoritative generation only for Manann receipts", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, owner, unit = world.module, world.owner, world.unit
            owner.local_player = false
            owner.network_id = function() return "owner-peer" end
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            world.now = 8
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 2))
            H.truthy(module.notify_allowed(unit, "manann_boon", 8, 1))
            H.truthy(module.notify_allowed(unit, "boon_supportbomb_speed_01", 30))

            H.equal(#world.sent, 4)
            H.deep_equal(world.sent[1], {
                "ct_bomb_cooldown_display_v1", "owner-peer", world.schema,
                "manann_trait", 8, 1,
            })
            H.deep_equal(world.sent[2], {
                "ct_bomb_cooldown_display_v1", "owner-peer", world.schema,
                "manann_trait", 8, 2,
            })
            H.deep_equal(world.sent[3], {
                "ct_bomb_cooldown_display_v1", "owner-peer", world.schema,
                "manann_boon", 8, 1,
            })
            H.deep_equal(world.sent[4], {
                "ct_bomb_cooldown_display_v1", "owner-peer", world.schema,
                "boon_supportbomb_speed_01", 30,
            })
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 toggle and source churn hide without forgetting a live deadline", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            local trait_owner_id = ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), true)
            world.now = 2
            world.toggle = false
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "toggle off removes ready")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false, "toggle off removes the timer")
            world.now = 3
            world.toggle = true
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false,
                "re-enable inside the deadline never claims ready")
            H.equal(ext:get_buff_type(COOLDOWN_TRAIT).duration, 5,
                "re-enable resumes only the remaining cooldown")
            ext:remove_buff(trait_owner_id)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false, "source loss removes ready")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false, "source loss leaves no stale timer")
            world.now = 4
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), false,
                "source reacquisition inside the deadline stays cooling")
            H.equal(ext:get_buff_type(COOLDOWN_TRAIT).duration, 4,
                "source reacquisition resumes the remaining duration")
            world.now = 8
            module.reconcile_manann_ready()
            H.equal(ext:has_buff_type(READY_TRAIT), true,
                "ready appears only when the original deadline expires")
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

    H.test("CT #358 local-player lifecycle reads are safe and error logs are bounded", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module = world.module
            _G.Managers.player.local_player_safe = function()
                error("Network backend has not been set")
            end
            for _ = 1, 10 do world.mod._ct_manann_ready_tick(0.5) end
            H.equal(#world.logs, 0,
                "expected pre-network absence is silent and never calls local_player")

            _G.Managers.player.local_player_safe = function() error("unexpected lookup failure") end
            for _ = 1, 10 do world.mod._ct_manann_ready_tick(0.5) end
            H.equal(#world.logs, 1, "one repeating failure logs only on its first edge")

            _G.Managers.player.local_player_safe = function() return world.player end
            world.mod._ct_manann_ready_tick(0.5)
            _G.Managers.player.local_player_safe = function() error("unexpected lookup failure") end
            world.mod._ct_manann_ready_tick(0.5)
            H.equal(#world.logs, 2, "recovery permits one later recurrence receipt")

            for i = 1, 10 do
                _G.Managers.player.local_player_safe = function()
                    error("distinct failure " .. tostring(i))
                end
                world.mod._ct_manann_ready_tick(0.5)
            end
            H.equal(#world.logs, 4, "error output has a hard per-session ceiling")
            H.equal(module._issue358_error_count, 4)
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 mod disable hides displays while preserving same-unit deadline", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            world.now = 2
            H.truthy(module.hide_manann_displays())
            H.equal(ext:has_buff_type(READY_TRAIT), false)
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false)
            H.equal(module.deadline_for(unit, "manann_trait"), 8,
                "disable cleanup does not diverge from the host bucket")

            local lifecycle = read(base .. "_ct_settings_lifecycle_owner.lua")
            H.truthy(lifecycle:find(
                "cooldown_display.hide_manann_displays()", 1, true),
                "mod.on_disabled owns synchronous presentation cleanup")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 player-unit replacement cannot inherit a prior mission deadline", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            world.now = 2

            local replacement, replacement_ext = world.new_unit("replacement")
            replacement_ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.equal(module.deadline_for(replacement, "manann_trait"), nil)
            H.equal(replacement_ext:has_buff_type(READY_TRAIT), true,
                "new unit starts from its own host-aligned bucket")
            H.equal(replacement_ext:has_buff_type(COOLDOWN_TRAIT), false)
            H.equal(module.deadline_for(unit, "manann_trait"), 8,
                "old weak-key state remains isolated until collection")
        end)
        world.restore()
        if not ok then error(failure, 0) end
    end)

    H.test("CT #358 backwards mission clock clears even a same-unit deadline", function()
        local world = load_ready_state_world()
        local ok, failure = pcall(function()
            local module, ext, unit = world.module, world.ext, world.unit
            world.now = 100
            ext:add_owned(TRAIT_OWNER)
            module.reconcile_manann_ready()
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 1))
            H.equal(module.deadline_for(unit, "manann_trait"), 108)

            world.now = 0
            module.reconcile_manann_ready()
            H.equal(module.deadline_for(unit, "manann_trait"), nil,
                "a reset game clock cannot leak the prior run's deadline")
            H.equal(ext:has_buff_type(COOLDOWN_TRAIT), false)
            H.equal(ext:has_buff_type(READY_TRAIT), true)
            H.truthy(module.notify_allowed(unit, "manann_trait", 8, 2))
            H.equal(module.generation_for(unit, "manann_trait"), 2,
                "same-unit rewind preserves the sequence epoch and accepts its successor")
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
        H.truthy(module_source:find("local_player_safe", 1, true))
        H.equal(module_source:find("player_manager:local_player(1)", 1, true), nil)
        H.truthy(module_source:find("MANANN_DEADLINES", 1, true))
        H.equal(module_source:find("MANANN_SEND_GENERATIONS", 1, true), nil)
        H.truthy(read(combat_path):find("bucket[generation_key] = bucket[generation_key] + 1", 1, true))
        H.truthy(module_source:find("MAX_MANANN_GENERATION", 1, true))
        H.truthy(read(base .. "chaos_wastes_tweaker_dev.lua"):find(
            "local CT_RPC_SCHEMA = 2", 1, true),
            "the added receipt field owns an all-current-build schema cliff")
    end)
end
