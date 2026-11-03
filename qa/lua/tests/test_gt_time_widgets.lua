-- Pure table/localization checks for the actual General time widget owner.
return function(H, repo_root)
    local base = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local Factory = assert(loadfile(base .. "_gt_time_widgets.lua"))()
    local Core = assert(loadfile(base .. "_gt_time_owner.lua"))()
    local loc = assert(loadfile(base .. "general_tweaker_dev_localization.lua"))()
    local expected = {
        {"time_scale_value", "dropdown"},
        {"time_faster_hotkey", "keybind", "gt_time_faster", false},
        {"time_slower_hotkey", "keybind", "gt_time_slower", false},
        {"gt_time_normal_hotkey", "keybind", "gt_time_normal", true},
        {"gt_world_freeze_enabled", "checkbox"},
        {"pause_hotkey", "keybind", "gt_pause_toggle", true},
    }

    H.test("GT time widgets preserve IDs and only recovery keys are global", function()
        local widgets, ids = Factory.build(Core.presets()), {}
        H.equal(#widgets, #expected)
        for index, spec in ipairs(expected) do
            local widget = widgets[index]
            H.equal(widget.setting_id, spec[1]); H.equal(widget.type, spec[2])
            H.equal(ids[spec[1]], nil, "unique setting ID"); ids[spec[1]] = true
            H.equal(widget.tooltip, spec[1] .. "_tooltip")
            H.truthy(loc[spec[1]] and loc[widget.tooltip], "missing widget localization")
            if spec[2] == "keybind" then
                H.equal(widget.function_name, spec[3]); H.equal(widget.keybind_global, spec[4])
                H.equal(widget.keybind_trigger, "pressed"); H.equal(widget.keybind_type, "function_call")
                H.equal(#widget.default_value, 0, "default bindings must not conflict")
            end
        end
        H.equal(ids.pause_value, nil, "legacy slowdown has no widget")
        H.equal(widgets[1].default_value, 13); H.equal(widgets[5].default_value, false)
        H.equal(widgets[5].save, nil, "runtime owns transient reset")
    end)

    H.test("GT time dropdown labels match all native preset identities", function()
        local rows, widgets = Core.presets(), Factory.build(Core.presets())
        H.equal(#widgets[1].options, 24)
        for index, option in ipairs(widgets[1].options) do
            H.equal(option.value, index); H.equal(rows[index].index, index)
            H.equal(option.text, "gt_time_preset_" .. index, "raw localization key")
            local text = string.format(assert(loc[option.text]).en)
            local multiplier, percent = text:match("^([%d.]+)x %(([%d.]+)%%")
            H.truthy(multiplier and percent, "readable multiplier and percentage required")
            H.truthy(math.abs(tonumber(multiplier) - rows[index].multiplier) <= 1e-12)
            H.truthy(math.abs(tonumber(percent) - rows[index].percent) <= 1e-12)
        end
        H.truthy(loc.gt_time_preset_13.en:find("1x", 1, true))
    end)

    H.test("GT time factories isolate VMF option/default mutation", function()
        local rows = Core.presets()
        local first, second = Factory.build(rows), Factory.build(rows)
        for index, widget in ipairs(first) do
            H.truthy(widget ~= second[index])
            if widget.type == "keybind" then
                H.truthy(widget.default_value ~= second[index].default_value)
            end
        end
        for index, option in ipairs(first[1].options) do
            H.truthy(option ~= second[1].options[index] and option ~= rows[index])
            H.equal(rows[index].text, nil, "factory must not localize or mutate core rows")
        end
        first[1].options[13].text = "localized once"; first[2].default_value[1] = "f1"
        rows[1].index = 24
        H.equal(second[1].options[13].text, "gt_time_preset_13")
        H.equal(second[1].options[1].value, 1); H.equal(#second[2].default_value, 0)
        H.equal(Core.presets()[1].index, 1, "core preset storage remains private")
    end)

    H.test("GT time factory rejects incomplete or reordered preset identities", function()
        H.equal(pcall(Factory.build, nil), false); H.equal(pcall(Factory.build, {}), false)
        local rows = Core.presets(); rows[1].index = 24
        H.equal(pcall(Factory.build, rows), false)
        rows = Core.presets(); rows[24] = nil
        H.equal(pcall(Factory.build, rows), false)
    end)

    H.test("GT data loads actual pure time owners before runtime registration", function()
        local calls = 0
        local mod = { localize = function(_, key) return key end }
        local env = setmetatable({
            get_mod = function(name) H.equal(name, "gt_dev"); return mod end,
            require = function(name)
                if name == "scripts/mods/general_tweaker_dev/_gt_time_widgets" then
                    return { build = function(rows) calls = calls + 1; return Factory.build(rows) end }
                end
                H.equal(name, "scripts/mods/general_tweaker_dev/_gt_time_owner")
                return Core
            end,
        }, { __index = _G })
        local chunk = assert(loadfile(base .. "general_tweaker_dev_data.lua")); setfenv(chunk, env)
        local data, group = chunk()
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id == "time_group" then H.equal(group, nil); group = node end
            for _, value in pairs(node) do if type(value) == "table" then walk(value) end end
        end
        walk(data); H.equal(calls, 1); H.truthy(group)
        H.deep_equal(group.sub_widgets, Factory.build(Core.presets()))
    end)

    H.test("GT freeze copy states the bounded inspection and recovery contract", function()
        local text = loc.gt_world_freeze_enabled_tooltip.en
        for _, needle in ipairs({"Solo", "keyboard/mouse", "physics/actors", "walk/look",
            "pose, actions, and jumping do not advance", "Recovery keys", "peers arrive"}) do
            H.truthy(text:find(needle, 1, true), needle)
        end
        H.equal(loc.pause_value, nil, "legacy slowdown is not advertised")
    end)
end
