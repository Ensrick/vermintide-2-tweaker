return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local streams = {
        {
            root = "gui_tweaker/scripts/mods/gui_tweaker/",
            package = "gui_tweaker/resource_packages/gui_tweaker/gui_tweaker.package",
            module_path = "scripts/mods/gui_tweaker/",
            dialogue = false,
        },
        {
            root = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/",
            package = "gui_tweaker_dev/resource_packages/gui_tweaker_dev/gui_tweaker_dev.package",
            module_path = "scripts/mods/gui_tweaker_dev/",
            dialogue = true,
        },
    }

    local function occurrences(source, needle)
        local count, at = 0, 1
        while true do
            at = source:find(needle, at, true)
            if not at then return count end
            count = count + 1
            at = at + #needle
        end
    end

    local function assert_unique_methods(owner, interaction, class_name)
        local seen = {}
        for method in (owner .. interaction):gmatch("function " .. class_name .. ":([%w_]+)") do
            H.equal(seen[method], nil, class_name .. ":" .. method .. " is installed twice")
            seen[method] = true
        end
        H.truthy(seen._handle_input, class_name .. " input surface is absent")
        H.truthy(seen._draw, class_name .. " draw surface is absent")
    end

    H.test("GUT size split installs each explicit module exactly once", function()
        for _, stream in ipairs(streams) do
            local main = read(stream.root .. (stream.dialogue and "gui_tweaker_dev.lua" or "gui_tweaker.lua"))
            local view = read(stream.root .. "_mod_tweaker_view.lua")
            local state = read(stream.root .. "_mod_tweaker_state.lua")
            local owners = {
                { source = main, name = "_gut_mod_tweaker_contracts" },
                { source = main, name = "_gut_ui_tweaks_integration" },
                { source = view, name = "_mod_tweaker_view_interaction" },
                { source = state, name = "_mod_tweaker_state_interaction" },
            }
            for _, owner in ipairs(owners) do
                H.equal(occurrences(owner.source, stream.module_path .. owner.name), 1,
                    owner.name .. " must have one owner")
                local module = read(stream.root .. owner.name .. ".lua")
                H.truthy(module:find("function M.install", 1, true), owner.name .. " has no explicit API")
                H.truthy(module:find("return M", 1, true), owner.name .. " does not export its API")
            end
        end
    end)

    H.test("GUT extracted presentation modules do not duplicate class methods", function()
        for _, stream in ipairs(streams) do
            local view = read(stream.root .. "_mod_tweaker_view.lua")
            local view_interaction = read(stream.root .. "_mod_tweaker_view_interaction.lua")
            assert_unique_methods(view, view_interaction, "ModTweakerView")

            local state = read(stream.root .. "_mod_tweaker_state.lua")
            local state_interaction = read(stream.root .. "_mod_tweaker_state_interaction.lua")
            assert_unique_methods(state, state_interaction, "HeroViewStateModTweaker")
        end
    end)

    H.test("GUT extracted modules remain hook and lifecycle neutral", function()
        for _, stream in ipairs(streams) do
            for _, name in ipairs({
                "_gut_mod_tweaker_contracts.lua",
                "_gut_ui_tweaks_integration.lua",
                "_mod_tweaker_view_interaction.lua",
                "_mod_tweaker_state_interaction.lua",
            }) do
                local source = read(stream.root .. name)
                H.equal(source:find("mod:hook(", 1, true), nil, name .. " owns an engine hook")
                H.equal(source:find("mod:hook_safe(", 1, true), nil, name .. " owns a safe hook")
                H.equal(source:find("mod:command(", 1, true), nil, name .. " owns a command")
                H.equal(source:find("function mod.update", 1, true), nil, name .. " owns update")
                H.equal(source:find("function mod.on_", 1, true), nil, name .. " owns lifecycle")
            end
        end
    end)

    H.test("GUT stable and dev interaction APIs preserve intentional parity", function()
        local stable = read(streams[1].root .. "_mod_tweaker_view_interaction.lua")
        local dev = read(streams[2].root .. "_mod_tweaker_view_interaction.lua")
        for _, dependency in ipairs({
            "deps.defs", "deps.UIRenderer", "deps.UISceneGraph",
            "deps.UIInverseScaleVectorToResolution", "deps.math", "deps.DD_FILTER_MIN", "deps.mt",
            "deps.resolve_step", "deps.format_keybind_value", "deps.poll_keybind_combo",
            "deps.cat_set", "deps.play_click", "deps.play_hover", "deps.printf",
        }) do
            H.truthy(stable:find(dependency, 1, true), "stable lacks " .. dependency)
            H.truthy(dev:find(dependency, 1, true), "dev lacks " .. dependency)
        end
        H.equal(stable:find("deps.DialogueUI", 1, true), nil, "stable leaked dev dialogue UI")
        H.truthy(dev:find("deps.DialogueUI", 1, true), "dev dialogue UI dependency was lost")
    end)

    H.test("GUT package globs include extracted root modules", function()
        for _, stream in ipairs(streams) do
            local package = read(stream.package)
            H.truthy(package:find('"' .. stream.module_path .. '*"', 1, true),
                "root Lua package glob was lost")
        end
    end)
end
