-- Behavioral coverage for the GUT #209 screen-particle diagnostics: the pure
-- lifecycle ledger, and the production instrument in _gut_camera.lua loaded
-- under a fake VMF environment with the captured hook callbacks composed as
-- the mod framework composes them (callback(next_fn, <original call args>),
-- mod_shim.lua:108-109) over a fake PlayerUnitFirstPerson surface
-- (player_unit_first_person.lua:1073/:1081/:1089).
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Ledger = assert(loadfile(root .. "_gut_screen_particle_ledger.lua"))()

    H.test("GUT #209 ledger tracks create/stop/destroy and renders snapshots", function()
        local state = Ledger.new()
        H.equal(Ledger.snapshot(state), "none")

        H.equal(Ledger.note_create(state, 11, "fx/overheat"), true)
        H.equal(Ledger.note_create(state, 7, "fx/vomit"), true)
        H.equal(Ledger.note_create(state, nil, "fx/never_stored"), false)
        H.equal(state.count, 2)
        H.equal(Ledger.snapshot(state), "11=fx/overheat(live),7=fx/vomit(live)")

        H.equal(Ledger.note_stop(state, 7), true)
        H.equal(Ledger.note_stop(state, 99), false)
        H.equal(Ledger.note_stop(state, nil), false)
        H.equal(Ledger.snapshot(state), "11=fx/overheat(live),7=fx/vomit(stopped)")

        H.equal(Ledger.note_destroy(state, 11), true)
        H.equal(Ledger.note_destroy(state, 11), false)
        H.equal(Ledger.note_destroy(state, nil), false)
        H.equal(state.count, 1)
        H.equal(Ledger.snapshot(state), "7=fx/vomit(stopped)")
    end)

    H.test("GUT #209 ledger row budget caps with a single marked final row", function()
        local state = Ledger.new()
        local printed, capped_marks = 0, 0
        for _ = 1, Ledger.MAX_ROWS + 25 do
            local allowed, capped_now = Ledger.row_allowed(state)
            if allowed then printed = printed + 1 end
            if capped_now then capped_marks = capped_marks + 1 end
        end
        H.equal(printed, Ledger.MAX_ROWS)
        H.equal(capped_marks, 1)
        H.equal(state.capped, true)
    end)

    local function load_production()
        local receipts = {}
        local world = { destroys = {}, next_id = 100 }
        local env

        local PlayerUnitFirstPerson = {}
        -- Vanilla model (player_unit_first_person.lua:1073-1095).
        PlayerUnitFirstPerson.create_screen_particles = function(self, name, pos, ...)
            world.next_id = world.next_id + 1
            return world.next_id
        end
        PlayerUnitFirstPerson.stop_spawning_screen_particles = function(self, id)
            world.stopped = id
        end
        PlayerUnitFirstPerson.destroy_screen_particles = function(self, id)
            world.destroys[#world.destroys + 1] = id
        end
        PlayerUnitFirstPerson.set_first_person_mode = function() end
        PlayerUnitFirstPerson.extensions_ready = function() end

        local PlayerUnitOverchargeExtension = {}
        PlayerUnitOverchargeExtension._update_screen_effect = function(self)
            world.oc_updates = (world.oc_updates or 0) + 1
        end
        -- Vanilla model (player_unit_overcharge_extension.lua:145-159): both
        -- ids die via World.destroy_particles, bypassing the FP-ext surface.
        PlayerUnitOverchargeExtension._destroy_all_screen_space_particles = function(self)
            self.onscreen_particles_id = nil
            self.critical_onscreen_particles_id = nil
        end

        local checks = {}
        local mod = { hooks = {} }
        local store = {}
        function mod:get(key) return store[key] end
        function mod:set(key, value) store[key] = value end
        function mod:echo() end
        function mod:info() end
        function mod:command() end
        function mod:dofile(path)
            return assert(loadfile(repo_root .. "/gui_tweaker_dev/" .. path .. ".lua"))()
        end
        mod._gut_rt_register = function(name, fn) checks[name] = fn end
        local function resolve(target)
            if type(target) == "string" then return env[target] end
            return target
        end
        function mod:hook(target, method, fn)
            local obj = resolve(target)
            self.hooks[tostring(target) .. ":" .. method] = fn
            if obj and obj[method] then
                local orig = obj[method]
                obj[method] = function(...)
                    return fn(orig, ...)
                end
            end
        end
        function mod:hook_safe(target, method, fn)
            local obj = resolve(target)
            if obj and obj[method] then
                local orig = obj[method]
                obj[method] = function(...)
                    orig(...)
                    fn(...)
                end
            end
        end

        env = setmetatable({
            get_mod = function() return mod end,
            printf = function(fmt, ...)
                receipts[#receipts + 1] = string.format(fmt, ...)
            end,
            PlayerUnitFirstPerson = PlayerUnitFirstPerson,
            PlayerUnitOverchargeExtension = PlayerUnitOverchargeExtension,
            GenericStatusExtension = {
                set_zooming = function() end,
                switch_variable_zoom = function() end,
            },
            Development = {},
            Managers = {},
        }, { __index = _G })
        env._G = env

        local chunk = assert(loadfile(root .. "_gut_camera.lua"))
        setfenv(chunk, env)
        chunk()
        local function saw(needle)
            for i = 1, #receipts do
                if receipts[i]:find(needle, 1, true) then return true end
            end
            return false
        end
        return {
            env = env, mod = mod, world = world, receipts = receipts,
            checks = checks, saw = saw,
            fp = PlayerUnitFirstPerson, oc = PlayerUnitOverchargeExtension,
        }
    end

    H.test("GUT #209 production instrument rows and transition receipts", function()
        local P = load_production()
        local fp_self = {}

        -- First-person create passes through, keeps the id, and prints a row.
        local id = P.fp.create_screen_particles(fp_self, "fx/screenspace_test", nil)
        H.equal(id, 101)
        H.truthy(P.saw("[gut:209] create | effect=fx/screenspace_test id=101 tp=false"))

        -- Third-person entry receipt lists the live id.
        P.mod._gut_apply_tp(true)
        H.truthy(P.saw("[gut:209] tp-entry | live=101=fx/screenspace_test(live)"))

        -- New spawns are suppressed in 3P and never reach the engine.
        local before = P.world.next_id
        local sid = P.fp.create_screen_particles(fp_self, "fx/screenspace_new", nil)
        H.equal(sid, nil)
        H.equal(P.world.next_id, before)
        H.truthy(P.saw("create-suppressed-3p | effect=fx/screenspace_new id=nil tp=true"))

        -- The #216 overcharge destroy in 3P reports its off-surface deaths.
        local oc_self = setmetatable({ onscreen_particles_id = 101 }, { __index = P.oc })
        P.oc._update_screen_effect(oc_self)
        H.equal(oc_self.onscreen_particles_id, nil)
        H.equal(P.world.oc_updates, nil)
        H.truthy(P.saw("destroy-overcharge-3p | effect=overcharge id=101 tp=true"))

        -- Exit receipt now shows an empty ledger.
        P.mod._gut_apply_tp(false)
        H.truthy(P.saw("[gut:209] tp-exit | live=none"))

        -- Back in 1P the overcharge update reaches vanilla again.
        P.oc._update_screen_effect(oc_self)
        H.equal(P.world.oc_updates, 1)
    end)

    H.test("GUT #209 receipts are direct and fail closed when engine printf throws", function()
        local file = assert(io.open(root .. "_gut_camera.lua", "rb"))
        local source = file:read("*a")
        file:close()

        H.equal(source:find('local _printf209 = rawget(_G, "printf")', 1, true), nil)
        H.truthy(source:find('pcall(printf, "[gut:209] %s | effect=', 1, true))
        H.truthy(source:find('pcall(printf, "[gut:209] tp-%s | live=%s"', 1, true))

        local P = load_production()
        P.env.printf = function() error("planted #209 logger failure") end

        local create_ok, id = pcall(P.fp.create_screen_particles,
            {}, "fx/screenspace_logger_fault", nil)
        H.equal(create_ok, true)
        H.equal(id, 101)
        H.equal(pcall(P.mod._gut_apply_tp, true), true)
    end)

    H.test("GUT #209 stop/destroy rows keep the #216 nil-guards", function()
        local P = load_production()
        local fp_self = {}
        local id = P.fp.create_screen_particles(fp_self, "fx/warpfire", nil)

        -- nil ids are refused before reaching the engine.
        P.fp.stop_spawning_screen_particles(fp_self, nil)
        H.equal(P.world.stopped, nil)
        P.fp.destroy_screen_particles(fp_self, nil)
        H.equal(#P.world.destroys, 0)

        -- Real ids flow through and the ledger echoes the owning effect name.
        P.fp.stop_spawning_screen_particles(fp_self, id)
        H.equal(P.world.stopped, id)
        H.truthy(P.saw("stop-spawning | effect=fx/warpfire id=" .. id))
        P.fp.destroy_screen_particles(fp_self, id)
        H.deep_equal(P.world.destroys, { id })
        H.truthy(P.saw("destroy | effect=fx/warpfire id=" .. id))

        -- Forced 3P reset receipt fires only when 3P was live.
        P.mod._gut_tp_reset_enabled()
        H.equal(P.saw("tp-reset-exit"), false)
        P.mod._gut_apply_tp(true)
        P.mod._gut_tp_reset_enabled()
        H.truthy(P.saw("[gut:209] tp-reset-exit | live=none"))
    end)

    H.test("GUT #209 named runtime check passes on the captured chain", function()
        local P = load_production()
        H.equal(type(P.checks.issue209_screen_particle_receipts), "function")
        H.equal(P.checks.issue209_screen_particle_receipts(), nil)
        -- The check restored the row budget and left no probe ids behind.
        H.equal(P.checks.issue209_screen_particle_receipts(), nil)
    end)
end
