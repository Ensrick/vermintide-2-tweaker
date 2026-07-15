return function(H, repo_root)
    local module_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_bardin_disabler_probe.lua"
    local source_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/"

    local function exists(path)
        local file = io.open(path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    local source_fixture = source_root .. "settings/player_movement_settings.lua"
    local has_vanilla_source = exists(source_fixture)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function load_isolated()
        local old_get_mod = _G.get_mod
        local fake_mod = { _crt = {}, hooks = {} }
        function fake_mod:hook(class_name, method_name, body)
            self.hooks[#self.hooks + 1] = { "full", class_name, method_name, body }
        end
        function fake_mod:hook_safe(class_name, method_name, body)
            self.hooks[#self.hooks + 1] = { "safe", class_name, method_name, body }
        end
        _G.get_mod = function() return fake_mod end
        local ok, module = pcall(assert(loadfile(module_path)))
        _G.get_mod = old_get_mod
        return ok, module, fake_mod
    end

    H.test("CRT #440 probe is bounded observation-only instrumentation", function()
        local ok, module, fake_mod = load_isolated()
        H.truthy(ok, tostring(module))
        H.equal(module.max_rows_per_kind, 16)
        H.equal(module.hook_count, 5)
        H.equal(#fake_mod.hooks, 5)
        H.equal(type(fake_mod._crt_bardin_disabler_tick), "function")
        H.equal(module.regression_check(), nil)

        local source = read(module_path)
        H.equal(source:find("mod:set(", 1, true), nil)
        H.equal(source:find("NetworkLookup[", 1, true), nil)
        H.truthy(source:find("return func(self, unit, blackboard, t, reason, destroy)", 1, true))
        H.truthy(source:find("local result = func(self, t, unit, blackboard)", 1, true))
    end)

    H.test_if(has_vanilla_source,
        "CRT #440 source contract has no Bardin-specific dodge branch", function()
        local movement = read(source_root .. "settings/player_movement_settings.lua")
        local dodge = read(source_root
            .. "unit_extensions/default_player_unit/states/player_character_state_dodging.lua")
        H.truthy(movement:find(
            "units_player_movement_setting[unit] = table.clone(PlayerUnitMovementSettings)", 1, true))
        H.equal(movement:find("dwarf_ranger", 1, true), nil)
        H.equal(dodge:find("dwarf_ranger", 1, true), nil)
        H.truthy(dodge:find("movement_settings_table.dodging.distance", 1, true))
        H.truthy(dodge:find("status_extension:set_is_dodging(true)", 1, true))
        end, "optional decompiled vanilla source is not present in this clean clone")

    H.test_if(has_vanilla_source,
        "CRT #440 diagnostics cover each distinct disabler boundary", function()
        local pack = read(source_root
            .. "entity_system/systems/behaviour/nodes/bt_pack_master_attack_action.lua")
        local corruptor = read(source_root
            .. "entity_system/systems/behaviour/nodes/chaos_sorcerer/bt_corruptor_grab_action.lua")
        local prepare = read(source_root
            .. "entity_system/systems/behaviour/nodes/bt_prepare_for_crazy_jump_action.lua")
        local gutter = read(source_root
            .. "entity_system/systems/behaviour/nodes/bt_crazy_jump_action.lua")
        H.truthy(pack:find("target_status_ext:get_is_dodging()", 1, true))
        H.truthy(corruptor:find("blackboard.target_dodged = true", 1, true))
        H.truthy(prepare:find("Unit.world_position(blackboard.target_unit, 0) + Vector3(0, 0, 0.2)", 1, true))
        H.truthy(gutter:find('local radius = 1', 1, true))
        H.truthy(gutter:find('Unit.node(unit, "j_neck")', 1, true))
        end, "optional decompiled vanilla source is not present in this clean clone")
end
