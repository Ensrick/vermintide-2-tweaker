-- Non-discovered selective CT feature cases. The promotion suite supplies its
-- production loader; every leaf and its policy are loaded from the selected
-- stable production path, never pasted into this test or resolved from Dev.
return function(H, load_production)
    local ROOT = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"

    local function pack(...)
        return { n = select("#", ...), ... }
    end

    local function fixture()
        local f = { hooks = {}, commands = {}, checks = {}, settings = {}, loaded = {}, requests = {} }
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.printf = function() end
        env.Managers = { player = { is_server = true } }
        env.script_data = {}
        local mod = {}
        f.mod, f.env = mod, env
        function mod:get(id) return f.settings[id] end
        function mod:echo() end
        function mod:hook(target, method, callback)
            f.hooks[target] = f.hooks[target] or {}
            assert(not f.hooks[target][method], "duplicate CT hook: " .. tostring(target) .. "." .. method)
            f.hooks[target][method] = callback
        end
        function mod:command(name, _, callback)
            assert(not f.commands[name], "duplicate command: " .. name)
            f.commands[name] = callback
        end
        mod._ct_rt_register = function(name, callback)
            assert(not f.checks[name], "duplicate runtime check: " .. name)
            f.checks[name] = callback
        end
        env.get_mod = function(id)
            f.requests[#f.requests + 1] = id
            if id == "ct" then return mod end
            if id == "gut" then return f.gut end
            error("unexpected cross-mod lookup: " .. tostring(id))
        end
        function f.load(name)
            local path = ROOT .. name .. ".lua"
            local value, actual = load_production(path, env)
            assert(type(actual) == "string", "production loader must return actual path")
            local normalized = actual:gsub("\\", "/")
            assert(normalized:sub(-#path) == path, "wrong production path: " .. actual)
            assert(not normalized:find("chaos_wastes_tweaker_dev/", 1, true), "Dev production file loaded")
            f.loaded[path] = (f.loaded[path] or 0) + 1
            return value
        end
        function mod:dofile(path)
            local name = assert(path:match("^scripts/mods/chaos_wastes_tweaker/(.+)$"), path)
            return f.load(name)
        end
        function f.effective(id) return f.settings[id] end
        return f
    end

    local function modifier_fixture()
        local f = fixture()
        f.server, f.depth, f.disabled = true, 2, {}
        f.templates = {
            curse_empathy = { server = {}, client = {} },
            curse_abundance_of_life = { server = {}, client = {} },
        }
        f.node = { curse = "curse_skulls_of_fury" }
        f.controller = {
            get_current_node = function() return f.node end,
            get_completed_level_count = function() return f.depth end,
            get_run_seed = function() return "seed" end,
            get_current_node_key = function() return "node" end,
        }
        f.self = { _deus_run_controller = f.controller }
        f.install = f.load("_ct_progressive_modifier_runtime")
        f.ctx = {
            mod = f.mod, effective_setting = f.effective,
            is_curse_disabled = function(name) return f.disabled[name] end,
            is_server = function() return f.server end,
            templates = function() return f.templates end,
        }
        f.state = f.install(f.ctx)
        f.hook = f.hooks.GameModeDeus.mutators
        return f
    end

    H.test("CT official #289 installed hook preserves native nil-bearing tuple and arguments", function()
        local f = modifier_fixture()
        local list, calls = { f.node.curse }, 0
        local out = pack(f.hook(function(self, a, b, c)
            calls = calls + 1
            assert(self == f.self and a == "a" and b == nil and c == "c")
            return list, nil, "tail", nil
        end, f.self, "a", nil, "c"))
        assert(calls == 1 and out.n == 4 and out[1] == list and out[2] == nil and out[3] == "tail")
        assert(#list == 1 and f.node.curse == "curse_skulls_of_fury")
        assert(f.install(f.ctx) == f.state, "second install must be idempotent")
        local ok, err = pcall(f.hook, function() error("native289", 0) end, f.self)
        assert(not ok and tostring(err):find("native289", 1, true), "native error must propagate")
    end)

    H.test("CT official #289 host-only deterministic allowlist and adversarial exclusions", function()
        local f = modifier_fixture()
        f.settings.progressive_modifier_stack = true
        local function call(list)
            return f.hook(function() return list end, f.self)
        end
        local first = call({ f.node.curse })
        local second = call({ f.node.curse })
        assert(#first == 2 and first[2] == second[2] and first[2] ~= f.node.curse)
        assert(first[2] == "curse_empathy" or first[2] == "curse_abundance_of_life")
        assert(f.node.curse == "curse_skulls_of_fury", "graph curse must never change")
        f.server = false
        assert(#call({ f.node.curse }) == 1)
        f.server, f.depth = true, 1
        assert(#call({ f.node.curse }) == 1)
        f.depth = 2
        assert(#call({ "deus_more_hordes" }) == 1, "inactive node curse must not stack")
        f.disabled.curse_empathy = true
        f.templates.curse_abundance_of_life.packages = { "not_preloaded" }
        assert(#call({ f.node.curse }) == 1, "disabled/packaged candidates must not escape")
        f.templates.curse_abundance_of_life = nil
        assert(#call({ f.node.curse }) == 1, "missing template must fail open")
    end)

    local function elite_fixture()
        local f = fixture()
        f.server, f.depth, f.marked, f.applied = true, 4, {}, {}
        f.templates = { elite_base = {}, shockwave = {}, ignore_death_aura = {} }
        f.install = f.load("_ct_progressive_elite_runtime")
        f.ctx = {
            mod = f.mod, effective_setting = f.effective,
            is_server = function() return f.server end,
            completed_level_count = function() return f.depth end,
            already_marked = function(unit) return f.marked[unit] ~= nil end,
            templates = function() return f.templates end,
            apply_enhancements = function(unit, breed, data)
                if f.throw_apply then error("apply323", 0) end
                f.applied[#f.applied + 1] = { unit = unit, breed = breed, data = data }
            end,
        }
        f.state = f.install(f.ctx)
        f.hook = f.hooks.ConflictDirector._post_spawn_unit
        f.breed = { elite = true, name = "chaos_warrior" }
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        function f.call(native, breed, optional, unit)
            return f.hook(native, f, unit or "elite", "go", breed or f.breed,
                "position", "category", "animation", optional, "type", 12, "tail", nil)
        end
        return f
    end

    H.test("CT official #323 installed hook runs native first and keeps spawn payload private", function()
        local f = elite_fixture()
        local optional = { untouched = true }
        local calls = 0
        local out = pack(f.call(function(self, unit, go, breed, pos, cat, anim, data, kind, id, tail, hole)
            calls = calls + 1
            assert(self == f and unit == "elite" and go == "go" and breed == f.breed)
            assert(pos == "position" and cat == "category" and anim == "animation" and data == optional)
            assert(kind == "type" and id == 12 and tail == "tail" and hole == nil)
            assert(#f.applied == 0, "enhancement applied before native")
            return "native", nil, false, nil
        end, nil, optional))
        assert(calls == 1 and out.n == 4 and out[1] == "native" and out[2] == nil and out[3] == false)
        assert(#f.applied == 1 and optional.enhancements == nil and optional.name_index == nil)
        local data = f.applied[1].data
        assert(data ~= optional and data.enhancements[1] == f.templates.elite_base)
        assert(data.enhancements[2] == f.templates.shockwave or data.enhancements[2] == f.templates.ignore_death_aura)
        assert(type(data.name_index) == "number" and data.name_index >= 1 and data.name_index <= 16384)
        assert(f.install(f.ctx) == f.state)
    end)

    H.test("CT official #323 preserves native marks and rejects clients specials bosses trash and faults", function()
        local f = elite_fixture()
        local native = function() return "native", nil, "tail" end
        f.call(function() f.marked.elite = 1; return "marked" end, nil, {})
        assert(#f.applied == 0, "native's just-applied mark must win")
        f.marked.elite = nil
        f.call(native, nil, { enhancements = {} })
        for _, breed in ipairs({ { special = true }, { boss = true, elite = true }, {} }) do
            f.call(native, breed, {})
        end
        f.server = false
        f.call(native, nil, {})
        f.server, f.depth = true, nil
        f.call(native, nil, {})
        f.depth, f.settings.progressive_elite_enhancements = 4, false
        f.call(native, nil, {})
        assert(#f.applied == 0)
        f.settings.progressive_elite_enhancements, f.throw_apply = true, true
        local out = pack(f.call(native, nil, {}))
        assert(out.n == 3 and out[1] == "native" and out[3] == "tail" and f.state.errors == 1)
        local ok, err = pcall(f.call, function() error("native323", 0) end, nil, {})
        assert(not ok and tostring(err):find("native323", 1, true))
    end)

    local function prepare_miasma(f)
        local env = f.env
        f.aura, f.carrier, f.other = { alive = true }, {}, {}
        f.units, f.moves, f.flow = { f.carrier }, {}, 0
        f.buff = { radius = 8 }
        env.BuffTemplates = { curse_rotten_miasma = { buffs = { { safe_area_radius = { 8, 8, 8, 8, 8 } } } } }
        env.MutatorTemplates = { curse_rotten_miasma = { server = { update = function() end } } }
        env.Managers.state = { side = { get_side_from_name = function() return { PLAYER_UNITS = f.units } end } }
        env.HEALTH_ALIVE = { [f.carrier] = true, [f.other] = true }
        env.POSITION_LOOKUP = { [f.carrier] = "carrier-position", [f.other] = "other-position" }
        env.ScriptUnit = { has_extension = function(unit, name)
            if unit == f.aura and name == "buff_system" then
                return { get_buff_type = function() return f.buff end }
            end
            return { has_inventory_item = function() return unit.carrying == true end }
        end }
        env.Unit = {
            alive = function(unit) return unit.alive == true end,
            set_data = function(unit, key, value) assert(unit == f.aura and key == "radius"); f.radius = value end,
            flow_event = function(unit, name) assert(unit == f.aura and name == "update_radius"); f.flow = f.flow + 1 end,
            set_local_position = function(unit, node, position)
                assert(unit == f.aura and node == 0)
                f.moves[#f.moves + 1] = position
            end,
        }
    end

    H.test("CT official #361 installed update preserves tuple and keeps only one living-carrier aura", function()
        local f = fixture()
        prepare_miasma(f)
        f.settings.miasma_permanent_carrier, f.settings.miasma_safe_radius = true, 12
        f.settings.miasma_stack_interval = 0.5
        f.mod._ct_effective_setting = f.effective
        f.load("_ct_miasma")
        local target = f.env.MutatorTemplates.curse_rotten_miasma.server
        local hook = f.hooks[target].update
        local data, calls = {}, 0
        f.carrier.carrying = true
        local native = function(context, state, dt, t)
            calls = calls + 1
            assert(context == "context" and state == data and dt == 0.1 and t == 1)
            data.rotten_miasma_safe_area = f.aura
            return "native", nil, false, nil
        end
        local out = pack(hook(native, "context", data, 0.1, 1))
        assert(out.n == 4 and out[1] == "native" and out[3] == false and calls == 1)
        assert(data._ct_miasma_owner == f.carrier and f.moves[1] == "carrier-position")
        local template = f.env.BuffTemplates.curse_rotten_miasma.buffs[1]
        for i = 1, 5 do assert(template.safe_area_radius[i] == 12) end
        assert(template.buff_exposure_tick_rate == 0.5 and f.buff.radius == 12 and f.flow == 1)
        f.carrier.carrying = false
        hook(native, "context", data, 0.1, 1)
        assert(data._ct_miasma_owner == f.carrier, "dropping torch must keep living owner")
        f.env.HEALTH_ALIVE[f.carrier], f.carrier.carrying = false, true
        hook(native, "context", data, 0.1, 1)
        assert(data._ct_miasma_owner == nil, "dead inventory holder must not become permanent carrier")
        f.units, f.other.carrying = { f.other }, true
        hook(native, "context", data, 0.1, 1)
        assert(data._ct_miasma_owner == f.other and f.moves[#f.moves] == "other-position")
        -- Host-effective false must not fall back to a client's saved true.
        f.mod._ct_effective_setting = function(id)
            if id == "miasma_permanent_carrier" then return false end
            return f.settings[id]
        end
        hook(native, "context", data, 0.1, 1)
        assert(data._ct_miasma_owner == nil)
        local installed = hook
        f.load("_ct_miasma")
        assert(f.hooks[target].update == installed, "repeat module load must not duplicate VMF hook")
        local ok, err = pcall(hook, function() error("native361", 0) end, "context", data, 0.1, 1)
        assert(not ok and tostring(err):find("native361", 1, true))
    end)

    local function mission_fixture()
        local f = fixture()
        f.level, f.loads, f.collected = "morris_hub", {}, 0
        f.env.Managers.level_transition_handler = { get_current_level_key = function() return f.level end }
        local mechanism = { debug_load_deus_level = function(_, ...)
            f.loads[#f.loads + 1] = pack(...)
            if f.throw_load then error("native505", 0) end
        end }
        f.env.Managers.mechanism = { game_mechanism = function() return mechanism end }
        f.env.DeusDebugSpecificNodeGraph = { start = { mutators = { "original" } } }
        f.env.DEUS_LEVEL_SETTINGS = { pat_forest = { paths = { 3, 1 } } }
        f.env.DEUS_MAP_POPULATE_SETTINGS = { default = { LEVEL_ALIAS = { alias = "real-level" } } }
        f.mod._ct_collect_start_boons = function() f.collected = f.collected + 1; return { "existing" } end
        f.load("_ct_dev_mission")
        return f
    end

    H.test("CT official #505 installed loader gates host and exact chamber before state writes", function()
        local f = mission_fixture()
        f.env.script_data.deus_force_load_curse = "unchanged"
        f.env.Managers.player.is_server = false
        assert(f.mod._ct_dev_mission_do_load({ level_key = "alias" }) == false)
        f.env.Managers.player.is_server = true
        for _, level in ipairs({ "inn_level", "dlc_morris_map", "pat_forest_wastes_path1" }) do
            f.level = level
            assert(f.mod._ct_dev_mission_do_load({ level_key = "alias" }) == false)
        end
        assert(#f.loads == 0 and f.collected == 0 and f.env.script_data.deus_force_load_curse == "unchanged")
        assert(f.env.DeusDebugSpecificNodeGraph.start.mutators[1] == "original")
    end)

    H.test("CT official #505 menu uses authored keybind valid path final progress clamp and existing boons", function()
        local f = mission_fixture()
        local cat = f.mod._ct_dev_mission_catalog
        f.settings.ctdm_base = assert(cat.MISSION_INDEX_BY_KEY.pat_forest)
        f.settings.ctdm_curse = 2 -- Rotten Miasma
        f.settings.ctdm_progress = 5
        f.settings.ctdm_modifier1 = 1
        f.settings.ctdm_with_belakor = true
        f.env.script_data.deus_force_load_blessing = "legacy"
        f.mod.ct_dev_load_selected_mission()
        local args = f.loads[1]
        assert(args.n == 5 and args[1] == "pat_forest_nurgle_path3" and args[3] == 0.999 and args[5] == true)
        assert(f.env.script_data.deus_force_load_curse == "curse_rotten_miasma")
        assert(f.env.script_data.deus_force_load_blessing == nil and f.collected == 1)
        local mutators = f.env.DeusDebugSpecificNodeGraph.start.mutators
        assert(#mutators == 3 and mutators[1] == "deus_pacing_tweak" and mutators[3] == "increased_deus_soft_currency")
        assert(cat.build_menu_group().sub_widgets[1].function_name == "ct_dev_load_selected_mission")
        assert(cat.sanitize_progress(0/0) == 0 and cat.sanitize_progress(-1) == 0 and cat.sanitize_progress(math.huge) == 0.999)
        assert(f.mod._ct_dev_mission_do_load({ level_key = "alias", progress = 100 }) == true)
        assert(f.loads[2][1] == "real-level" and f.loads[2][3] == 0.999)
        f.throw_load = true
        assert(f.mod._ct_dev_mission_do_load({ level_key = "alias" }) == false, "native loader error must be reported")
    end)

    H.test("CT official #505 stable GUI bridge retains lifecycle and registers only category filtering", function()
        local f = fixture()
        local previous, registered = 0
        f.mod.on_all_mods_loaded = function() previous = previous + 1 end
        f.gut = { mod_tweaker = {
            register_dropdown_categories = function(_, provider, setting, categories)
                assert(provider == "ct" and setting == "ctdm_base" and #categories == 4)
                registered = categories
            end,
            register_profile_diagnostic = function() error("#919 must not be promoted") end,
        } }
        f.load("_ct_dev_mission")
        f.mod.on_all_mods_loaded()
        assert(previous == 1 and registered)
        local cat = f.mod._ct_dev_mission_catalog
        for i, category in ipairs(registered) do
            assert(category.label == cat.CATEGORIES[i])
            for index, mission in ipairs(cat.MISSIONS) do
                assert(category.match(index) == (mission.category == category.label))
            end
            assert(category.match(-1) == false)
        end
        f.gut = nil
        f.mod.on_all_mods_loaded()
        assert(previous == 2, "missing optional GUI must not suppress earlier lifecycle")
    end)

    H.test("CT official feature installer loads only selected leaves once and registers named checks", function()
        local f = fixture()
        prepare_miasma(f)
        local install = f.load("_ct_official_feature_leaf")
        local ctx = { mod = f.mod, effective_setting = f.effective, is_curse_disabled = function() return false end }
        local state = install(ctx)
        assert(install(ctx) == state)
        assert(state.modifiers.installed and state.elites.installed and state.reapply_miasma())
        assert(f.checks.issue289_progressive_modifier_stack and f.checks.issue323_progressive_elite_runtime)
        assert(f.checks.issue361_miasma_customization_installed() == nil)
        assert(f.checks.single_mission_loader_redesign_505() == nil)
        for path in pairs(f.loaded) do
            assert(not path:find("_audit", 1, true) and not path:find("_ct_tab", 1, true))
        end
        local count = 0
        for _, methods in pairs(f.hooks) do for _ in pairs(methods) do count = count + 1 end end
        assert(count == 3, "selected feature installer must own exactly three hook pairs")
    end)
end
