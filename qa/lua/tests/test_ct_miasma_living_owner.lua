-- #361: drive the actual registered Miasma server-update callback. The only
-- candidate delta is the pure owner selector; runtime stays the installed Dev
-- module. Private environments avoid replacing any game/QA global or gate.
return function(H, repo_root, load_candidate)
    local PREFIX = "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local function production(name, env)
        local relative = PREFIX .. name .. ".lua"
        local value, path
        if load_candidate then
            value, path = load_candidate(relative, env)
        else
            path = repo_root .. "/" .. relative
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            value = chunk()
        end
        local normalized = type(path) == "string" and path:gsub("\\", "/")
        assert(normalized and normalized:sub(-#relative) == relative,
            "Miasma owner tests require actual production source paths")
        return value
    end

    local function fixture()
        local f = { native_calls = 0, moves = {}, units = {} }
        local env = setmetatable({}, { __index = _G })
        env._G, env.printf = env, function() end
        f.env = env
        f.dead, f.living, f.prior = {}, {}, {}
        f.aura = { alive = true }
        f.buff = { radius = 8 }
        env.HEALTH_ALIVE = { [f.living] = true, [f.prior] = true }
        env.POSITION_LOOKUP = { [f.dead] = "dead-position", [f.living] = "living-position", [f.prior] = "prior-position" }
        env.BuffTemplates = { curse_rotten_miasma = { buffs = { { safe_area_radius = { 8, 8, 8, 8, 8 } } } } }
        local target = { update = function() end }
        env.MutatorTemplates = { curse_rotten_miasma = { server = target } }
        env.Managers = { state = { side = { get_side_from_name = function(_, name)
            assert(name == "heroes")
            return { PLAYER_UNITS = f.units }
        end } } }
        env.ScriptUnit = { has_extension = function(unit, system)
            if system == "inventory_system" then
                return { has_inventory_item = function(_, slot, item)
                    assert(slot == "slot_level_event" and item == "wpn_deus_relic_01")
                    return unit.carrying == true
                end }
            end
            assert(system == "buff_system" and unit == f.aura)
            return { get_buff_type = function(_, name)
                assert(name == "curse_rotten_miasma")
                return f.buff
            end }
        end }
        env.Unit = {
            alive = function(unit) return unit.alive == true end,
            set_data = function() error("unchanged radius must not rewrite aura data") end,
            flow_event = function() error("unchanged radius must not emit aura flow") end,
            set_local_position = function(unit, node, position)
                assert(unit == f.aura and node == 0 and f.native_calls == 1,
                    "move must follow exactly one native update of the same aura")
                f.moves[#f.moves + 1] = position
            end,
        }
        local mod = {}
        f.enabled = true
        function mod:get(id)
            if id == "miasma_permanent_carrier" then return f.enabled end
            if id == "miasma_safe_radius" then return 8 end
            if id == "miasma_stack_interval" then return 1.3 end
            error("unexpected setting " .. tostring(id))
        end
        mod._ct_effective_setting = function(id) return mod:get(id) end
        function mod:dofile(path)
            assert(path == "scripts/mods/chaos_wastes_tweaker_dev/_ct_miasma_policy")
            return production("_ct_miasma_policy", env)
        end
        function mod:hook(table_target, method, callback)
            assert(table_target == target and method == "update" and f.hook == nil,
                "one exact native server-update hook required")
            f.hook = callback
        end
        env.get_mod = function(id) assert(id == "ct_dev"); return mod end
        production("_ct_miasma", env)
        assert(type(f.hook) == "function" and env.__ct_miasma361_hook_installed == true)
        f.data = { rotten_miasma_safe_area = f.aura }
        function f.call()
            f.native_calls = 0
            return f.hook(function(context, data, dt, t)
                f.native_calls = f.native_calls + 1
                assert(context == f and data == f.data and dt == 0.2 and t == 7)
            end, f, f.data, 0.2, 7)
        end
        return f
    end

    H.test("CT #361 dead torch holder cannot replace prior living owner", function()
        local f = fixture()
        f.dead.carrying, f.units = true, { f.dead }
        f.data._ct_miasma_owner = f.prior
        f.call()
        assert(f.data._ct_miasma_owner == f.prior, "dead holder replaced prior living owner")
        assert(#f.moves == 1 and f.moves[1] == "prior-position")
    end)

    H.test("CT #361 later living holder wins over earlier dead inventory holder", function()
        local f = fixture()
        f.dead.carrying, f.living.carrying, f.units = true, true, { f.dead, f.living }
        f.call()
        assert(f.data._ct_miasma_owner == f.living, "earlier dead holder hid the living holder")
        assert(#f.moves == 1 and f.moves[1] == "living-position")
    end)

    H.test("CT #361 dead-only inventory cannot arm permanent aura ownership", function()
        local f = fixture()
        f.dead.carrying, f.units = true, { f.dead }
        f.data._ct_miasma_owner = f.dead
        f.call()
        assert(f.data._ct_miasma_owner == nil, "dead-only holder retained permanent aura ownership")
        assert(#f.moves == 0 and f.native_calls == 1)
    end)

    H.test("CT #361 normal living pickup and dropped-torch retention stay native-first", function()
        local f = fixture()
        f.living.carrying, f.units = true, { f.living }
        f.call()
        assert(f.data._ct_miasma_owner == f.living and f.moves[1] == "living-position")
        f.living.carrying = false
        f.call()
        assert(f.data._ct_miasma_owner == f.living and f.moves[2] == "living-position")
    end)

    H.test("CT #361 disabled option leaves native aura and clears remembered owner", function()
        local f = fixture()
        f.enabled, f.living.carrying, f.units = false, true, { f.living }
        f.data._ct_miasma_owner = f.prior
        f.call()
        assert(f.data._ct_miasma_owner == nil and #f.moves == 0 and f.native_calls == 1)
    end)

    H.test("CT #361 absent native aura does not invoke a replacement spawn or owner move", function()
        local f = fixture()
        f.data.rotten_miasma_safe_area = nil
        f.living.carrying, f.units = true, { f.living }
        f.call()
        assert(#f.moves == 0 and f.data._ct_miasma_owner == nil and f.native_calls == 1)
    end)

    H.test("CT #361 native update error still propagates without CT move", function()
        local f = fixture()
        local ok, err = pcall(f.hook, function() error("native-miasma-error", 0) end,
            f, f.data, 0.2, 7)
        assert(not ok and tostring(err):find("native-miasma-error", 1, true) and #f.moves == 0)
    end)
end
