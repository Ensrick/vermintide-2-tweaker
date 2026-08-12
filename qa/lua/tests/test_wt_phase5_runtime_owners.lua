return function(H, repo_root)
    local streams = {
        {
            tag = "wt",
            root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            entry = "weapon_tweaker.lua",
            ns = "weapon_tweaker",
        },
        {
            tag = "wt_dev",
            root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            entry = "weapon_tweaker_dev.lua",
            ns = "weapon_tweaker_dev",
        },
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count(source, needle)
        local found, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return found end
            found = found + 1
            cursor = at + #needle
        end
    end

    for _, stream in ipairs(streams) do
        H.test(stream.tag .. ": phase-5 owners are installed once and old ownership left entry", function()
            local entry = read(stream.root .. stream.entry)
            local transform_call = '"scripts/mods/' .. stream.ns .. '/_wt_transform_runtime").install(mod, {'
            local safety_call = '"scripts/mods/' .. stream.ns .. '/_wt_cross_character_safety").install(mod, {'
            H.equal(count(entry, transform_call), 1)
            H.equal(count(entry, safety_call), 1)
            H.equal(count(entry, 'mod:traced_hook("GearUtils", "create_equipment"'), 0)
            H.equal(count(entry, 'mod:hook("AnimationSystem", "anim_event_with_variable_float"'), 0)
            H.equal(count(entry, "local _weapon_scale_overrides"), 0)
            H.equal(count(entry, "local _weapon_grip_offsets"), 0)
            H.equal(count(entry, "mod._wt_link_filter = function"), 0)
        end)
    end

    H.test("transform owner preserves receiver, hand, surface, and transport contracts", function()
        local root = streams[1].root
        local grip_policy = assert(loadfile(root .. "_wt_grip_offset_policy.lua"))()
        local applications, traced, safe = {}, {}, {}
        local mod = { _wt = {} }
        function mod:traced_hook(_, method, fn) traced[method] = fn end
        function mod:hook_safe(_, method, fn) safe[method] = fn end
        function mod:warning() end
        function mod:error() end
        local appearance = { apply = function(unit, descriptor)
            applications[#applications + 1] = { unit = unit, descriptor = descriptor }
        end }

        local owner = assert(loadfile(root .. "_wt_transform_runtime.lua"))()
            .install(mod, { appearance = appearance, grip_policy = grip_policy, dbg = function() end })
        H.equal(type(traced.create_equipment), "function")
        H.equal(type(safe._wield_slot), "function")
        H.equal(mod._wt587_transform_contract.transport, "none")
        H.equal(mod._wt587_transform_contract.first_person, "unchanged")

        local handgun = mod._wt587_baked_transform_plan("es_handgun", "wh_captain")
        H.equal(handgun.offset[1], 0)
        H.equal(handgun.offset[2], -0.17)
        H.equal(handgun.offset[3], -0.05)
        H.equal(handgun.durable, true)
        H.equal(mod._wt587_baked_transform_plan("es_handgun", "es_mercenary").offset, nil)

        local shield = mod._wt587_baked_transform_plan("es_mace_shield", "wh_zealot")
        H.equal(shield.rotation[1], 25)
        H.equal(shield.rotation[2], -17.5)
        H.equal(shield.rotation[3], -15)
        H.equal(shield.rotation.hand, "left")

        local slot = {
            left_unit_1p = "left1", right_unit_1p = "right1",
            left_unit_3p = "left3", right_unit_3p = "right3",
        }
        owner.offset_weapon_units(slot, "wh_crossbow", "es_mercenary")
        H.equal(#applications, 1)
        H.equal(applications[1].unit, "left3")
        H.equal(applications[1].descriptor.offset[2], 0.100)
        H.equal(applications[1].descriptor.offset[3], 0.025)

        applications = {}
        owner.scale_weapon_units(slot, "we_1h_sword", "es_mercenary")
        H.equal(#applications, 4, "scale remains intentionally shared by 1P and 3P")
        H.equal(applications[1].descriptor.scale[1], 1.15)
    end)

    H.test("cross-character safety preserves skip_sync and sanitizes links without mutation", function()
        local old = {
            Weapons = _G.Weapons, Unit = _G.Unit, ScriptUnit = _G.ScriptUnit,
            GearUtils = _G.GearUtils, AnimationSystem = _G.AnimationSystem,
        }
        local ok, err = pcall(function()
            _G.Weapons = nil
            _G.Unit = {
                alive = function() return true end,
                has_node = function(_, node) return node ~= "missing" end,
                animation_find_variable = function(_, name)
                    return name == "valid" and 3 or nil
                end,
            }
            _G.ScriptUnit = {}
            _G.GearUtils = { link_units = function() end }
            _G.AnimationSystem = {}
            local hooks = {}
            local mod = { _wt = {} }
            function mod:hook(_, method, fn) hooks[method] = fn end
            local owner = assert(loadfile(streams[1].root .. "_wt_cross_character_safety.lua"))()
                .install(mod, { dbg = function() end, dbg_alert = function() end })
            H.equal(type(owner.validate_attachment_sources), "function")
            H.equal(type(hooks.anim_event_with_variable_float), "function")
            H.equal(type(hooks.link_units), "function")

            local forwarded
            hooks.anim_event_with_variable_float(function(...)
                forwarded = { ... }
                return "ok"
            end, "self", "unit", "event", "valid", 0.5, true)
            H.equal(forwarded[6], true, "skip_sync must remain the sixth forwarded argument")
            forwarded = nil
            hooks.anim_event_with_variable_float(function(...) forwarded = { ... } end,
                "self", "unit", "event", "missing", 0.5, false)
            H.equal(forwarded, nil, "unknown animation variables fail closed")

            local original = {
                { source = "j_hand", target = "j_weapon" },
                { source = "a_unwielded_bad", target = "j_weapon" },
                { source = "j_hand", target = "missing" },
            }
            local filtered, dropped, substituted = mod._wt_link_filter(original,
                function(name) return name == "j_hand" or name == "j_hips" end,
                function(name) return name == "j_weapon" end)
            H.equal(dropped, 1)
            H.equal(substituted, 1)
            H.equal(#filtered, 2)
            H.equal(filtered[2].source, "j_hips")
            H.equal(original[2].source, "a_unwielded_bad",
                "hip fallback must clone rather than mutate shared linking data")
        end)
        _G.Weapons, _G.Unit, _G.ScriptUnit = old.Weapons, old.Unit, old.ScriptUnit
        _G.GearUtils, _G.AnimationSystem = old.GearUtils, old.AnimationSystem
        if not ok then error(err) end
    end)

    H.test("public and dev phase-5 owners are exact mirror files", function()
        for _, name in ipairs({ "_wt_transform_runtime.lua", "_wt_cross_character_safety.lua" }) do
            H.equal(read(streams[1].root .. name), read(streams[2].root .. name))
        end
    end)
end
