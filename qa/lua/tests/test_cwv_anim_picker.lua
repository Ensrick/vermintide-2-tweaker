return function(H, repo_root)
    local path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/cwv_dev_anim_picker.lua"

    local settings = {}
    local fake_mod = {
        get = function(_, key) return settings[key] end,
        command = function() end,
        info = function() end,
    }
    local picker_loader = assert(loadfile(path))
    setfenv(picker_loader, setmetatable({ get_mod = function() return fake_mod end },
        { __index = _G }))
    local Picker = picker_loader()

    local function runtime_owner(resolve, installed)
        return { _cross_access_target_event = resolve,
            cross_access = { networked_3p_remap_installed = installed } }
    end

    -- The combined resolver is the production chunk. Extract the exact named
    -- registration from its production owner because other checks in that file
    -- use LuaJIT goto syntax unavailable in this Lua 5.1 host. No copied picker,
    -- baked map or named-check algorithm is used, and no production goto is edited.
    local function installed_fixture()
        local base = repo_root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
        local hooks, counts, checks = {}, {}, {}
        local mod = { _cwv_dev_anim_picker = Picker }
        local function hook(_, class, method, callback)
            local key = class .. "." .. method
            hooks[key], counts[key] = callback, (counts[key] or 0) + 1
        end
        mod.hook, mod.hook_safe = hook, hook
        local env = setmetatable({}, { __index = _G })
        local function load(name)
            local chunk = assert(loadfile(base .. name .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        local om = { greataxe = { ANIM_REMAP_3P = {} }, remote_audio_dispatch = {} }
        om.cross_access = load("_cwv_cross_access")(mod, {
            om = om, dbg = function() end, es_all_careers = {}, wh_all_careers = {},
        })
        H.equal(type(hooks["WeaponUnitExtension._play_3p_anim"]), "function")
        H.equal(counts["WeaponUnitExtension._play_3p_anim"], 1)
        -- A stale legacy/global marker must not substitute for the owner that
        -- actually installed the callback, in either direction.
        env._cwv_networked_3p_remap_installed = false
        local file = assert(io.open(base .. "_cwv_regression_identity.lua", "rb"))
        local source = file:read("*a"); file:close()
        local first = assert(source:find('_rt_register("issue317_career_scoped_animation_picker", function()', 1, true))
        local last = assert(source:find("\nend)", first, true)) + 4
        local chunk = assert(loadstring("return function(mod, _om, _rt_register)\n"
            .. source:sub(first, last) .. "\nend", "@issue317-production-registration"))
        setfenv(chunk, env)
        chunk()(mod, om, function(name, callback) checks[name] = callback end)
        return checks.issue317_career_scoped_animation_picker, om, mod
    end

    H.test("CWV #317 named check drives the installed combined resolver and owner", function()
        local check, om = installed_fixture()
        local actual, calls = om._cross_access_target_event, 0
        om._cross_access_target_event = function(...)
            calls = calls + 1
            return actual(...)
        end
        H.equal(check(), nil)
        H.equal(calls, 4, "static vocabulary validation is not a live resolver test")
    end)

    H.test("CWV #317 named check rejects a disconnected picker resolver", function()
        local check, om = installed_fixture()
        om._cross_access_target_event = function() return nil end
        local result = check()
        H.equal(type(result), "string", "disconnected production resolver must fail")
    end)

    H.test("CWV #317 named check rejects an absent installed owner marker", function()
        local check, om = installed_fixture()
        om.cross_access.networked_3p_remap_installed = false
        local result = check()
        H.equal(type(result), "string", "uninstalled route must fail despite a valid picker")
    end)

    H.test("CWV #317 named check detects loss of the actual baked fallback", function()
        local check, om = installed_fixture()
        om._cross_access_target_event = Picker.resolve
        local result = check()
        H.equal(type(result), "string", "picker-only success cannot prove combined native fallback")
    end)

    H.test("CWV #317 installed-check error restores the exact player selection", function()
        local check, om = installed_fixture()
        local sid = "cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"
        settings.enable_cwv_dev_anim_picker, settings[sid] = true, "attack_swing_heavy_left"
        om._cross_access_target_event = function() error("installed-resolver-boom") end
        local result = check()
        H.equal(type(result), "string")
        H.truthy(result:find("installed%-resolver%-boom"))
        H.equal(Picker.resolve("cwv_wh_dual_axes", "wh_captain", "attack_swing_heavy_right"),
            "attack_swing_heavy_left")
        H.equal(settings.enable_cwv_dev_anim_picker, true)
        H.equal(settings[sid], "attack_swing_heavy_left")
        settings.enable_cwv_dev_anim_picker, settings[sid] = nil, nil
    end)

    H.test("CWV animation picker scopes picks to receiver and preserves defaults", function()
        local sid = "cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"
        settings.enable_cwv_dev_anim_picker = true
        settings[sid] = "attack_swing_heavy_down"
        H.equal(Picker.resolve("dr_dual_wield_axes", "wh_captain", "attack_swing_heavy_right"),
            "attack_swing_heavy_down")
        H.equal(Picker.resolve("cwv_wh_dual_axes", "wh_zealot", "attack_swing_heavy_right"),
            "attack_swing_heavy_down")
        H.equal(Picker.resolve("dr_dual_wield_axes", "dr_slayer", "attack_swing_heavy_right"), nil)
        H.equal(Picker.resolve("dr_dual_wield_axes", "es_mercenary", "attack_swing_heavy_right"), nil)
        settings[sid] = "__cwv_anim_unset__"
        H.equal(Picker.resolve("dr_dual_wield_axes", "wh_captain", "attack_swing_heavy_right"), nil)
        settings[sid] = "attack_swing_heavy_down"
        settings.enable_cwv_dev_anim_picker = false
        H.equal(Picker.resolve("dr_dual_wield_axes", "wh_captain", "attack_swing_heavy_right"), nil,
            "master toggle off must restore baked/default behavior")
    end)

    H.test("CWV animation picker options are closed-vocabulary and unshared", function()
        local groups = Picker.build_widget_tree()
        H.equal(#groups, 2)
        local first = groups[1].sub_widgets[1]
        local second = groups[1].sub_widgets[2]
        H.truthy(first.options ~= second.options)
        H.equal(first.options[1].value, "__cwv_anim_unset__")
        settings.enable_cwv_dev_anim_picker = true
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] =
            "invented_not_receiver_native"
        H.equal(Picker.resolve("cwv_wh_dual_axes", "wh_captain", "attack_swing_heavy_right"), nil,
            "invalid persisted values must never reach the animation network lookup")
        H.truthy(Picker.regression_check():find("out%-of%-vocabulary"))
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] = nil
        H.equal(Picker.regression_check(), nil)
    end)

    H.test("CWV issue 317 picker owns only the pre-RPC resolver seam", function()
        local source = require("cwv_source").combined(repo_root)
        H.truthy(source:find("mod._cwv_dev_anim_picker.resolve(item_key, career, source_event)", 1, true))
        H.truthy(source:find('mod:hook("WeaponUnitExtension", "_play_3p_anim"', 1, true))
        local picker_file = assert(io.open(path, "rb"))
        local picker_source = picker_file:read("*a")
        picker_file:close()
        H.equal(picker_source:find("anim_event_3p%s*="), nil,
            "picker must not mutate the shared Bardin template")
        H.equal(picker_source:find("NetworkLookup", 1, true), nil,
            "picker must not add a network payload")
    end)

    H.test("CWV issue 317 runtime contract drives both picks through the live resolver", function()
        settings.enable_cwv_dev_anim_picker = nil
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] = nil
        local live_calls = 0
        local baked = {
            dr_dual_wield_axes = {
                es_mercenary = {
                    attack_swing_heavy_right = "attack_swing_heavy_right_diagonal",
                },
            },
        }
        local function live(item_key, career, source_event)
            live_calls = live_calls + 1
            local picked = Picker.resolve(item_key, career, source_event)
            local by_item = baked[item_key]
            local by_career = by_item and by_item[career]
            return picked or (by_career and by_career[source_event])
        end
        H.equal(Picker.runtime_contract(runtime_owner(live, true)), nil)
        H.equal(live_calls, 4)
        H.equal(settings.enable_cwv_dev_anim_picker, nil,
            "runtime contract must not mutate the player's master setting")
        H.equal(settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"], nil,
            "runtime contract must not persist a synthetic pick")
        local missing_hook = Picker.runtime_contract(runtime_owner(live, false))
        H.truthy(type(missing_hook) == "string"
            and missing_hook:find("hook not installed", 1, true))

        local missing_resolver = Picker.runtime_contract(runtime_owner(nil, true))
        H.truthy(type(missing_resolver) == "string"
            and missing_resolver:find("resolver missing", 1, true))
    end)

    H.test("CWV issue 317 runtime contract restores its probe overlay after errors", function()
        settings.enable_cwv_dev_anim_picker = true
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] =
            "attack_swing_heavy_left"
        local err = Picker.runtime_contract(runtime_owner(function()
            error("synthetic live resolver failure")
        end, true))
        H.truthy(type(err) == "string"
            and err:find("synthetic live resolver failure", 1, true))
        H.equal(Picker.resolve("cwv_wh_dual_axes", "wh_captain",
            "attack_swing_heavy_right"), "attack_swing_heavy_left",
            "throwing probe left its private settings overlay installed")
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] = nil
        settings.enable_cwv_dev_anim_picker = nil
    end)

    H.test("CWV issue 317 dump reaches the engine console via printf", function()
        -- Source shape: the dump body must route every line through
        -- pcall(printf, ...) and never mod:info (invisible in the user's
        -- normal config -- mod logging OFF, repo NON-NEGOTIABLE 9).
        local picker_file = assert(io.open(path, "rb"))
        local picker_source = picker_file:read("*a")
        picker_file:close()
        local dump_body = picker_source:match("function M%.dump%(%)(.-)\nend")
        H.truthy(dump_body, "M.dump body not found in picker source")
        H.equal(dump_body:find("mod:info", 1, true), nil,
            "dump must not route through mod:info (#317)")
        H.truthy(dump_body:find("pcall(printf", 1, true),
            "dump must route through pcall(printf, ...) (#317)")

        -- Runtime capture: the dump emits printf lines end to end.
        settings.enable_cwv_dev_anim_picker = nil
        settings["cwv_dev_anim_saltz_dual_axes_attack_swing_heavy_right"] = nil
        local captured = 0
        local old_printf = rawget(_G, "printf")
        rawset(_G, "printf", function() captured = captured + 1 end)
        local ok = pcall(Picker.dump)
        rawset(_G, "printf", old_printf)
        H.truthy(ok, "dump crashed under printf capture")
        H.truthy(captured >= 4, "dump did not emit its banner/entry lines via printf")

        -- The in-game regression_check must itself pin the printf routing
        -- (it captures through the dump's environment) and still pass clean.
        H.equal(Picker.regression_check(), nil)
    end)
end
