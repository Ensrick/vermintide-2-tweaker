return function(H, repo_root)
    local public_path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_longbow_variable_zoom.lua"
    local dev_path = repo_root
        .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_longbow_variable_zoom.lua"
    local Policy = assert(loadfile(public_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    local function action()
        return {
            kind = "aim",
            buffed_zoom_thresholds = { "zoom_in_trueflight", "zoom_in" },
        }
    end

    local function template(value)
        return { actions = { action_two = { default = value } } }
    end

    local function runtime(value, item, career, options)
        options = options or {}
        local switches, observed = 0, nil
        local buff_extension = options.buff_extension
        if buff_extension == nil and not options.missing_buff then
            buff_extension = {
                has_buff_perk = function(_, perk)
                    if perk == "increased_zoom" and options.native_perk == true then
                        return true
                    end
                    return nil
                end,
            }
        end
        local status = {
            is_zooming = function() return options.zooming ~= false end,
            switch_variable_zoom = function(_, thresholds)
                switches, observed = switches + 1, thresholds
            end,
        }
        local result = Policy.post_update({
            current_action = value,
            item_name = item,
            owner_unit = {},
            zoom_condition_function = options.condition,
            buff_extension = buff_extension,
        }, {
            get_career_name = function() return career end,
            get_extension = function(_, name)
                if name == "status_system" then return status end
                if name == "input_system" then
                    return { get = function(_, input)
                        return input == "action_three" and options.pressed ~= false
                    end }
                end
            end,
        })
        return result, switches, observed
    end

    H.test("WT #316 exact Empire Longbow action and six-career allowlist", function()
        local aim = action()
        H.equal(1, Policy.register_templates({
            longbow_empire_template = template(aim),
            longbow_empire_tutorial_template = template(action()),
        }))
        H.truthy(Policy.is_registered(aim))
        H.equal(Policy.target_item, "es_longbow")
        H.equal(Policy.target_template, "longbow_empire_template")
        for _, career in ipairs({
                "es_mercenary", "es_knight", "es_questingknight",
                "wh_captain", "wh_bountyhunter", "wh_zealot",
            }) do
            H.truthy(Policy.is_supported_item_career("es_longbow", career), career)
        end
        for _, career in ipairs({ "es_huntsman", "wh_priest", "we_waywatcher" }) do
            H.equal(Policy.is_supported_item_career("es_longbow", career), false, career)
        end
        H.equal(Policy.is_supported_item_career("we_longbow", "es_mercenary"), false)
    end)

    H.test("WT #316 cycles only authored thresholds after native base aim", function()
        local aim = action()
        Policy.register_template(template(aim))
        local result, switches, thresholds = runtime(
            aim, "es_longbow", "wh_bountyhunter")
        H.equal(result, "switched")
        H.equal(switches, 1)
        H.equal(thresholds, aim.buffed_zoom_thresholds)
    end)

    H.test("WT #316 preserves native, unrelated, inactive, and condition paths", function()
        local aim = action()
        Policy.register_template(template(aim))
        local native_result, native_switches = runtime(
            aim, "es_longbow", "es_mercenary", { native_perk = true })
        H.equal(native_result, "native_perk")
        H.equal(native_switches, 0)
        H.equal(runtime(aim, "es_longbow", "es_huntsman"),
            "not_supported_item_career")
        H.equal(runtime(aim, "we_longbow", "es_mercenary"),
            "not_supported_item_career")
        H.equal(runtime(action(), "es_longbow", "es_mercenary"),
            "not_target_action")
        H.equal(runtime(aim, "es_longbow", "es_mercenary", { pressed = false }),
            "inactive")
        H.equal(runtime(aim, "es_longbow", "es_mercenary", { zooming = false }),
            "inactive")
        H.equal(runtime(aim, "es_longbow", "es_mercenary", {
            condition = function() return false end,
        }), "inactive")
    end)

    H.test("WT #316 fails open when native perk ownership cannot be read", function()
        local aim = action()
        Policy.register_template(template(aim))
        local explicit_false, false_switches = runtime(
            aim, "es_longbow", "es_mercenary", {
                buff_extension = {
                    has_buff_perk = function() return false end,
                },
            })
        H.equal(explicit_false, "switched")
        H.equal(false_switches, 1)

        local missing, missing_switches = runtime(
            aim, "es_longbow", "es_mercenary", { missing_buff = true })
        H.equal(missing, "extensions_unavailable")
        H.equal(missing_switches, 0)

        local malformed, malformed_switches = runtime(
            aim, "es_longbow", "es_mercenary", { buff_extension = {} })
        H.equal(malformed, "extensions_unavailable")
        H.equal(malformed_switches, 0)

        local throwing, throwing_switches = runtime(
            aim, "es_longbow", "es_mercenary", {
                buff_extension = {
                    has_buff_perk = function()
                        error("planted native-perk read failure")
                    end,
                },
            })
        H.equal(throwing, "extensions_unavailable")
        H.equal(throwing_switches, 0)
    end)

    H.test("WT #316 stable and dev share one owner hook and byte policy", function()
        H.equal(read(public_path), read(dev_path))
        local hooks, observer = {}, 0
        local aim = action()
        local mod = {
            hook_safe = function(_, class_name, method_name, callback)
                hooks[#hooks + 1] = { class_name, method_name, callback }
            end,
        }
        H.equal(Policy.install(
            mod, { longbow_empire_template = template(aim) }, function()
                observer = observer + 1
            end), Policy)
        H.equal(#hooks, 1)
        H.equal(hooks[1][1], "ActionAim")
        H.equal(hooks[1][2], "client_owner_post_update")
        hooks[1][3]({ current_action = {} }, 0.01, 1)
        H.equal(observer, 1)
    end)

    H.test("WT #316 resolves the dev observer after owner installation", function()
        local hooks, observer = {}, 0
        local aim = action()
        local mod = {
            hook_safe = function(_, _, _, callback)
                hooks[#hooks + 1] = callback
            end,
        }
        Policy.install(mod, { longbow_empire_template = template(aim) })
        mod._wt316_post_update_observer = function()
            observer = observer + 1
        end
        hooks[1]({ current_action = {} }, 0.01, 1)
        H.equal(observer, 1)
    end)

    H.test("WT #316 installed observer contains extension and diagnostic failures", function()
        local hooks = {}
        local aim = action()
        local mod = {
            hook_safe = function(_, _, _, callback)
                hooks[#hooks + 1] = callback
            end,
        }
        Policy.install(mod, { longbow_empire_template = template(aim) }, function()
            error("planted diagnostic failure")
        end)
        local prior_script_unit = _G.ScriptUnit
        _G.ScriptUnit = {
            has_extension = function(_, name)
                if name == "career_system" then
                    return { career_name = function() return "es_mercenary" end }
                end
            end,
        }
        local ok = pcall(hooks[1], {
            current_action = aim,
            item_name = "es_longbow",
            owner_unit = {},
            buff_extension = {
                has_buff_perk = function() error("planted extension failure") end,
            },
        }, 0.01, 1)
        _G.ScriptUnit = prior_script_unit
        H.equal(ok, true)
    end)

    H.test("WT #316 entry publishes the installed owner to the named runtime check", function()
        for _, stream in ipairs({
                {
                    root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
                    ns = "weapon_tweaker",
                },
                {
                    root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
                    ns = "weapon_tweaker_dev",
                },
        }) do
            local owner = read(stream.root .. "_wt_cross_char_template_patches.lua")
            local checks = read(stream.root .. "_wt_runtime_checks.lua")
            local entry = read(stream.root .. stream.ns .. ".lua")
            H.truthy(owner:find("mod._wt.longbow_variable_zoom = mod:dofile", 1, true))
            H.truthy(owner:find(".install(mod, Weapons)", 1, true))
            H.truthy(checks:find("or (mod._wt and mod._wt.longbow_variable_zoom)", 1, true))
            H.truthy(checks:find(
                '_rt_register("issue316_empire_longbow_cross_career_variable_zoom"',
                1, true))
            H.truthy(entry:find('_wt_cross_char_template_patches")', 1, true),
                "entry does not execute the publishing owner")
        end
    end)
end
