-- Actual production-module tests. Canonical post-apply runs use repository
-- files; an explicit bounded root selects the ignored pre-apply overlay.
return function(H, root)
    root = root:gsub("\\", "/"):gsub("/$", "")
    local base = os.getenv("VT2_CT_OFFICIAL_OVERLAY_ROOT")
    if base then
        base = base:gsub("\\", "/"):gsub("/$", "")
        assert(base == root .. "/.temp/public-promotion-20261105/overlays/ct", "unowned CT overlay root")
    else
        base = root
    end
    local prefix = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local function exists(path)
        local f = io.open(path, "rb")
        if f then f:close(); return true end
        return false
    end
    local function load_production(relative, env)
        assert(type(relative) == "string" and not relative:find("..", 1, true), "unsafe production path")
        assert(relative:sub(1, #prefix) == prefix, "not an official CT production module")
        local actual = base .. "/" .. relative
        if not exists(actual) then
            -- Only unchanged official dependencies may fall back outside an
            -- overlay. Every selected module must physically exist in it.
            assert(relative == prefix .. "_adventure_pool.lua", "missing selected overlay module " .. relative)
            actual = root .. "/" .. relative
        end
        local fn = assert(loadfile(actual))
        if env then setfenv(fn, env) end
        return fn(), actual
    end
    local function fragment(name)
        local fn = assert(loadfile(base .. "/qa/lua/tests/" .. name .. ".lua"))()
        fn(H, load_production)
    end
    fragment("ct_official_shop_cases")
    fragment("ct_official_feature_cases")
    fragment("ct_official_rescue_cases")
    fragment("ct_official_boon_repair_cases")
    fragment("ct_official_cooldown_cases")

    local function pack(...) return { n = select("#", ...), ... } end
    local function fixture(settings)
        settings = settings or {}
        local hooks, rpc, checks = {}, {}, {}
        local mod = {}
        local env = setmetatable({
            Managers = { player = { is_server = true }, state = {}, mechanism = {} },
            TerrorEventUtils = {}, Breeds = {}, printf = function() end,
        }, { __index = _G })
        env._G = env
        function mod:get(key) return settings[key] end
        function mod:dofile(vm_path)
            assert(vm_path:sub(1, 13) == "scripts/mods/", "non-native VM path")
            return load_production("chaos_wastes_tweaker/" .. vm_path .. ".lua", env)
        end
        function mod:hook(class, method, callback)
            hooks[class] = hooks[class] or {}
            assert(not hooks[class][method], "duplicate production hook " .. method)
            hooks[class][method] = callback
        end
        mod.hook_safe = mod.hook
        function mod:network_register(name, callback) assert(not rpc[name]); rpc[name] = callback end
        function mod:network_send(...) self.last_send = pack(...) end
        local function effective(key)
            local value = settings[key]
            if mod.runtime then return mod.runtime.setting(key, value, function(k) return settings[k] end) end
            return value
        end
        local install = load_production(prefix .. "_ct_official_verify_runtime.lua", env)
        mod.runtime = install(mod, {
            effective_setting = effective, rpc_schema = 2,
            rt_register = function(name, callback) checks[name] = callback end,
            altar_uses = function() return 1 end,
        })
        return mod.runtime, mod, env, hooks, rpc, settings, checks
    end

    H.test("CT official #912 exact setup and replay baseline including zero", function()
        local runtime, _, _, _, _, settings = fixture({ starting_coins = 324 })
        local controller, args = {}, { 1, "hardest", "journey", nil, 175, nil, false, nil, {} }
        runtime.setup(controller, args); assert(args[5] == 324 and controller._ct_progdiff_start == "hardest")
        args[5] = 999; runtime.setup(controller, args); assert(args[5] == 324)
        local balance = 324
        controller.get_own_peer_id = function() return "self" end
        controller.get_player_soft_currency = function() return balance end
        runtime.capture_coins(controller); assert(runtime.coins_regression(controller) == nil)
        balance = 711; assert(runtime.coins_regression(controller) == nil)
        settings.starting_coins = 0; runtime.setup(controller, args); assert(args[5] == 0)
        for _, malformed in ipairs({ -1, 3001, 1.25, "324", 0/0, math.huge }) do
            settings.starting_coins = malformed; args[5] = 175
            runtime.setup(controller, args); assert(args[5] == 175)
        end
    end)
    H.test("CT official #460 installed ramp and authenticated hotjoin original tier", function()
        local runtime, mod, env, hooks, rpc = fixture({ progressive_difficulty = true, progressive_difficulty_increase = true, progressive_coin_reduction = -25 })
        env.Difficulties, env.DifficultyLookup = {}, {}
        for i, key in ipairs(runtime.progressive.TIERS) do env.Difficulties[i] = key; env.DifficultyLookup[key] = i end
        local completed = 2
        local rc = { _ct_progdiff_start = "hardest", _run_state = { get_completed_level_count = function() return completed end, is_server = function() return true end } }
        env.Managers.mechanism.game_mechanism = function() return { get_deus_run_controller = function() return rc end } end
        assert(hooks.DeusRunController.get_run_difficulty(function() return "hardest" end, rc) == "cataclysm")
        completed = 4; assert(hooks.DeusRunController.get_run_difficulty(function() return "cataclysm" end, rc) == "cataclysm_2")
        assert(runtime.coin_multiplier(2) == 1.5)
        env.DifficultyLookup.cataclysm = nil
        assert(hooks.DeusRunController.get_run_difficulty(function() return "hardest" end, rc) == "hardest")
        env.Managers.mechanism.server_peer_id = function() return "host" end
        rpc.ct_progdiff_start("forged", 2, "hard"); assert(mod._ct_progdiff_pending_host_start == nil)
        rpc.ct_progdiff_start("host", 1, "hard"); assert(mod._ct_progdiff_pending_host_start == nil)
        rpc.ct_progdiff_start("host", 2, "hard"); assert(mod._ct_progdiff_pending_host_start == "hard")
        local args = { 1, "cataclysm", nil, nil, 0 }; runtime.setup(rc, args)
        assert(rc._ct_progdiff_start == "hard" and mod._ct_progdiff_pending_host_start == nil)
        local called = false
        hooks.DeusMechanism.sync_mechanism_data(function() called = true; assert(mod.last_send[1] == "ct_progdiff_start"); return "a", nil, "c" end, { _deus_run_controller = rc }, "late", true)
        assert(called and mod.last_send[4] == "hard")
    end)
    H.test("CT official #146 completed graph finale and independent approach", function()
        local runtime, _, _, _, _, settings = fixture({ finale_dominant_god = 2, finale_approach_god = 3 })
        local graph = { arena = { level = "arena_citadel_nurgle_path1", level_type = "ARENA", level_seed = 3 }, approach = { level = "sig_citadel_slaanesh_path4", level_type = "SIGNATURE", level_seed = 2 }, regular = { level = "bell", theme = "nurgle" } }
        runtime.force_finale(graph, { AVAILABLE_CURSES = { ARENA = { tzeentch = { "t1", "t2" } }, SIGNATURE = { khorne = { "k" } } } })
        assert(graph.arena.level == "arena_citadel_tzeentch_path1" and graph.arena.curse == "t2")
        assert(graph.approach.level == "sig_citadel_khorne_path4" and graph.approach.curse == "k")
        assert(graph.regular.theme == "nurgle")
        settings.finale_approach_god = 0; runtime.force_finale(graph); assert(graph.approach.theme == "tzeentch")
    end)
    H.test("CT official #221 masters compose and #107 actual universal hook consumes them", function()
        local runtime, _, env, hooks, _, settings = fixture({ ban_all_grudge_marks = true, ban_all_traits = true, disable_all_listed_curses = true, enable_altar_reuse = false, enable_boon_reworks = false, enable_boon_vauls_anvil = true })
        assert(runtime.setting("altar_reuse_count_upgrade", 10, function(k) return settings[k] end) == 1)
        assert(runtime.setting("disable_curse_rotten_miasma", false, function(k) return settings[k] end))
        assert(not runtime.setting("enable_boon_vauls_anvil", true, function(k) return settings[k] end))
        local base, mark = { name = "base" }, { name = "periodic_shield" }
        local data = { enhancements = { base, mark, "warping" } }
        local native_calls = 0
        local native = function(_, _, payload) native_calls = native_calls + 1; return payload, nil, 3 end
        local result = pack(hooks[env.TerrorEventUtils].apply_breed_enhancements(native, {}, {}, data))
        assert(result.n == 3 and result[2] == nil and native_calls == 1 and #data.enhancements == 1 and data.enhancements[1] == base)
        env.Managers.player.is_server = false; data.enhancements = { base, mark }
        hooks[env.TerrorEventUtils].apply_breed_enhancements(native, {}, {}, data); assert(#data.enhancements == 2)
        local traits = runtime.umbrella.filter_traits(true, { "a", "b" }); assert(#traits == 0)
        assert(settings.enable_boon_vauls_anvil == true)
    end)
    H.test("CT official #221 #107 ban-all retains non-grudge scaffolds needed by #323", function()
        local _, _, env, hooks = fixture({ ban_all_grudge_marks = true })
        local base, elite, termite, mark = { name = "base" }, { name = "elite_base" }, { name = "termite_base" }, { name = "commander" }
        local data = { enhancements = { base, elite, termite, mark } }
        local calls = 0
        hooks[env.TerrorEventUtils].apply_breed_enhancements(function(_, _, payload)
            calls = calls + 1
            assert(#payload.enhancements == 3 and payload.enhancements[1] == base and payload.enhancements[2] == elite and payload.enhancements[3] == termite)
        end, {}, {}, data)
        assert(calls == 1)
    end)
    H.test("CT official #249 authoritative grant remains behind stronger public parity gate", function()
        local runtime, mod, env = fixture()
        local count, local_count = 0, 0
        local ext = { num_buff_stacks = function() return 2 end, add_buff = function() local_count = local_count + 1 end }
        env.Managers.state.entity = { system = function() return { add_buff = function(_, unit, name, source, networked) assert(unit == source and name == "ct_meta_ammo_stack" and networked == true); count = count + 1 end } end }
        mod._ct_wire_safe = function() return false end
        runtime.grant_stack({}, "ct_meta_ammo_stack", "ct_meta_ammo_stack_1", 5, ext); assert(count == 0)
        mod._ct_wire_safe = function() return true end
        env.Managers.player.is_server = false
        runtime.grant_stack({}, "ct_meta_ammo_stack", "ct_meta_ammo_stack_1", 5, ext); assert(count == 0 and local_count == 0)
        env.Managers.player.is_server = true
        runtime.grant_stack({}, "ct_meta_ammo_stack", "ct_meta_ammo_stack_1", 5, ext); assert(count == 3 and local_count == 0)
        env.Managers.state.entity = nil
        runtime.grant_stack({}, "ct_meta_ammo_stack", "ct_meta_ammo_stack_1", 5, ext); assert(local_count == 0)
    end)
    H.test("CT official #256 current ammo clamps without mutating capacities", function()
        local runtime = fixture()
        local ext = { _max_ammo = 60, _current_ammo = 80, _available_ammo = -4 }
        runtime.clamp_ammo(ext); assert(ext._max_ammo == 60 and ext._current_ammo == 60 and ext._available_ammo == 0)
        runtime.clamp_ammo(ext); assert(ext._max_ammo == 60 and ext._current_ammo == 60)
    end)
    H.test("CT official #249 actual parity-enable callback replaces local-only stacks once", function()
        local _, mod, env = fixture()
        local unit, removed, added, callback = {}, 0, 0
        local stacks = { { id = 1 }, { id = 2 }, { id = 3 } }
        local system = { server_controlled_buffs = {} }
        local ext = {
            num_buff_stacks = function() return #stacks end,
            get_stacking_buff = function() return stacks end,
            remove_buff = function(_, id)
                for i = #stacks, 1, -1 do if stacks[i].id == id then table.remove(stacks, i); removed = removed + 1; return 1 end end
                return 0
            end,
        }
        function system:add_buff(target, name, source, replicated)
            assert(target == unit and source == unit and replicated == true)
            added = added + 1
            local id = 10 + added
            stacks[#stacks + 1] = { id = id }
            self.server_controlled_buffs[unit] = self.server_controlled_buffs[unit] or {}
            self.server_controlled_buffs[unit][id] = { template_name = name, local_buff_id = id }
            return id
        end
        local rows = { { name = "ct_meta_ammo" }, {}, {}, {}, {} }
        env.BuffTemplates = { ct_meta_ammo_stack = { buffs = { { name = "ct_meta_ammo_stack_1", max_stacks = 30 } } } }
        env.ScriptUnit = { has_extension = function() return ext end, extension = function() return ext end }
        env.Managers.player.human_and_bot_players = function() return { { player_unit = unit, network_id = function() return "peer" end, local_player_id = function() return 1 end } } end
        env.Managers.state.entity = { system = function() return system end }
        env.Managers.mechanism.game_mechanism = function() return { get_deus_run_controller = function() return { get_player_power_ups = function() return rows end } end } end
        mod._ct_peer_parity = { register_gated_feature = function(_, name, feature) assert(name == "ct249_stack_rebroadcast"); callback = feature.on_enable end }
        local install = load_production(prefix .. "_ct_stack_rebroadcast_owner.lua", env)
        install(mod, { rt_register = function() end }); assert(type(callback) == "function")
        mod._ct_wire_safe = function() return false end; callback(); assert(added == 0 and removed == 0)
        mod._ct_wire_safe = function() return true end; callback(); assert(added == 5 and removed == 3 and #stacks == 5)
        callback(); assert(added == 5 and removed == 3)
    end)
    H.test("CT official #322 actual pickup dispatch preserves game object and nil tuple", function()
        local runtime, mod = fixture()
        local unit, tallied, marked = {}, 0, 0
        mod._ct_tally_count = function(name, value) assert(name == "deus_cursed_chest" and value == unit); tallied = tallied + 1 end
        mod._ct_official_chest_cap = { pickup_chest = function(value) assert(value == unit); marked = marked + 1 end }
        local result = pack(runtime.finish_pickup(function(_, _, name, ...) assert(name == "deus_cursed_chest" and select("#", ...) == 3); return unit, 42, nil, "tail", nil end, {}, {}, "deus_cursed_chest", 1, nil, 3))
        assert(result.n == 5 and result[1] == unit and result[2] == 42 and result[3] == nil and result[4] == "tail" and tallied == 1 and marked == 1)
    end)
    H.test("CT official #471 actual wave dispatch tops up both categories and restores template", function()
        local runtime, _, env = fixture({ cot_enemy_multiplier = 3 })
        local function box(v) return { unbox = function() return v end } end
        env.Vector3Box = box
        env.Managers.state.entity = { system = function() return { nav_world = function() return {} end } end }
        local passes, decals = 0, 0
        env.ConflictUtils = { find_positions_around_position = function(_, accepted, _, minimum, maximum, want, forbidden, spacing)
            assert(minimum == 6 and maximum >= 8 and spacing == 2 and #forbidden == 1)
            passes = passes + 1; for _ = 1, want do accepted[#accepted + 1] = {} end
        end }
        for _, category in ipairs({ "cursed_chest_enemies", "cursed_chest_elites" }) do
            local difficulty = { hardest = 2 }
            local element = { spawn_counter_category = category, amount = 2, difficulty_amount = difficulty, min_distance = 6, max_distance = 8, pre_spawn_unit_func = function() decals = decals + 1 end }
            local event = { center_position = box({}), spawn_positions = { box({}) }, spawn_table = { 1, 2, 3 } }
            local result = pack(runtime.spawn_around(function(_, actual) assert(actual.amount == (category == "cursed_chest_enemies" and 6 or 2)); return "a", nil, "c" end, event, element, 0))
            assert(result.n == 3 and result[3] == "c" and #event.spawn_positions == 3 and element.amount == 2 and element.difficulty_amount == difficulty)
            local ok = pcall(runtime.spawn_around, function() error("native") end, event, element, 0)
            assert(not ok and element.amount == 2 and element.difficulty_amount == difficulty)
        end
        assert(passes == 2 and decals == 4)
    end)
    H.test("CT official #470 installed mutator callback only fills missing rank8", function()
        local _, _, env, hooks = fixture()
        local health = { [7] = 125 }
        env.Breeds.curse_mutator_sorcerer = { max_health = health }
        hooks.MutatorHandler.initialize_mutators(); assert(health[8] == 150 and health[7] == 125)
        health[8] = 0; hooks.MutatorHandler.initialize_mutators(); assert(health[8] == 0)
        health[7], health[8] = nil, nil; hooks.MutatorHandler.initialize_mutators(); assert(health[8] == nil)
    end)
    H.test("CT official #258 #271 exact injected lighting channel selection ct_public_interior_shading", function()
        local runtime, _, env = fixture()
        local changed = {}
        env.Vector3 = function(x, y, z) return { x=x,y=y,z=z } end
        env.ShadingEnvironment = {
            vector3 = function() return {x=1,y=2,z=3} end,
            set_vector3 = function(_, key, value) changed[key] = value.x end,
            scalar = function() return 2 end,
            set_scalar = function(_, key, value) changed[key] = value end,
        }
        runtime.light("dlc_termite_3", "nurgle", {}); assert(next(changed) == nil)
        runtime.light("dlc_termite_3", "tzeentch", {}); assert(changed.ambient_tint_top == 2 and changed.sun_color == nil)
        changed = {}; runtime.light("dlc_termite_2", "khorne", {})
        assert(changed.exposure == 4 and changed.secondary_sun_color == 2 and changed.ambient_tint == 2 and changed.sun_color == nil)
    end)
    H.test("CT official #917 actual final-result apply honors own compatible skin and exclusion", function()
        local runtime, _, env = fixture({ preserve_adventure_illusions = true })
        env.ItemMasterList = { own_skin = { matching_item_key = "sword" }, wrong_skin = { matching_item_key = "bow" } }
        local state = runtime.illusions
        local probe = { key = "sword", skin = "random" }
        state.apply_to_result("upgrade_item", probe, { skin = "own_skin" }); assert(probe.skin == "own_skin")
        probe.skin = "random"; state.apply_to_result("upgrade_item", probe, { skin = "wrong_skin" }); assert(probe.skin == "random")
        state.suppress(true); state.apply_to_result("upgrade_item", probe, { skin = "own_skin" }); assert(probe.skin == "random")
    end)
    H.test("CT official #252 installed prompt rewrites same-tier reuse only", function()
        local _, _, env, hooks = fixture()
        local unit = {}
        local equipped, stored = { rarity = "rare" }, { rarity = "rare" }
        local chest = { _chest_type = "upgrade", _go_id = 7, get_stored_purchase = function() return stored end, get_purchase_cost = function() return 30 end }
        env.DEUS_CHEST_TYPES = { upgrade = "upgrade" }
        env.ScriptUnit = { has_extension = function(value) assert(value == unit); return chest end }
        env.RaritySettings = { rare = { order = 3, display_name = "Rare" }, exotic = { order = 4 } }
        env.Managers.state.network = { profile_synchronizer = { others_actually_ingame = function() return true end } }
        env.Managers.mechanism.game_mechanism = function() return { get_deus_run_controller = function() return {
            get_own_loadout = function() return equipped, {} end,
            get_own_peer_id = function() return "self" end,
            get_player_soft_currency = function() return 50 end,
        } end } end
        local info = { content = {}, style = { rarity = {}, cost_text = {} } }
        local tooltip = { content = {}, style = { item = {} } }
        local view = { _widgets_by_name = { chest_content = info, weapon_tooltip = tooltip } }
        hooks.DeusUpgradeWeaponInteractionUI._populate_widget(view, unit, "slot_melee")
        assert(info.content.reward_info_text == "Reroll this weapon?" and tooltip.content.item == equipped and info.content.cost_text == "50/30")
        info.content.reward_info_text = "native"; stored.rarity = "exotic"
        hooks.DeusUpgradeWeaponInteractionUI._populate_widget(view, unit, "slot_melee")
        assert(info.content.reward_info_text == "native")
    end)
    H.test("CT official selected settings realize once with matching localized ids", function()
        local mod = { localize = function(_, key) return key end, get = function() return nil end }
        local env = setmetatable({ get_mod = function(name) assert(name == "ct"); return mod end }, { __index = _G })
        env._G = env
        function mod:dofile(vm_path) return load_production("chaos_wastes_tweaker/" .. vm_path .. ".lua", env) end
        local loc = load_production(prefix .. "chaos_wastes_tweaker_localization.lua", env)
        local data = load_production(prefix .. "chaos_wastes_tweaker_data.lua", env)
        local ids = {}
        local function walk(widgets)
            for _, widget in ipairs(widgets or {}) do
                assert(not ids[widget.setting_id], "duplicate setting " .. widget.setting_id)
                ids[widget.setting_id] = widget
                assert(loc[widget.setting_id], "missing setting localization " .. widget.setting_id)
                if widget.tooltip then assert(loc[widget.tooltip], "missing tooltip " .. widget.tooltip) end
                for _, option in ipairs(widget.options or {}) do
                    if not tonumber(option.text) then assert(loc[option.text], "missing dropdown localization " .. option.text) end
                end
                walk(widget.sub_widgets)
            end
        end
        walk(data.options.widgets)
        for _, id in ipairs({ "ct_buy_starting_boons", "ct_individual_boon_prices", "progressive_difficulty", "progressive_difficulty_increase", "progressive_coin_reduction", "progressive_modifier_stack", "progressive_elite_enhancements", "miasma_safe_radius", "finale_approach_god", "preserve_adventure_illusions", "enable_altar_reuse", "ban_all_traits", "ban_all_grudge_marks", "disable_all_listed_curses", "enable_boon_reworks", "ctdm_base", "ctdm_curse", "ctdm_progress" }) do
            assert(ids[id], "missing selected widget " .. id)
        end
        assert(loc.ct_tab_chests_of_trials and loc.ct_tab_pilgrims_coins)
    end)
end
