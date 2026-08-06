return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local entry = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_path = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_item_grid_presentation.lua"
    local source = read(module_path)

    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count = count + 1
            offset = at + #needle
        end
    end

    H.test("Cosmetics entry delegates item-grid presentation exactly once", function()
        H.equal(occurrences(entry, "_cos_item_grid_presentation"), 3)
        H.truthy(entry:find(
            '"scripts/mods/cosmetics_tweaker/_cos_item_grid_presentation"',
            1, true))
        H.truthy(entry:find(
            "_cos_item_grid_presentation.refresh_illusion_glow_badges", 1, true))
        H.equal(entry:find('mod:hook("UIWidget", "init"', 1, true), nil)
        H.equal(entry:find('mod:hook_safe("ItemGridUI"', 1, true), nil)
        H.equal(entry:find("mod._cos_glow_badges_refresh = function", 1, true), nil)
    end)

    H.test("Cosmetics item-grid owner preserves hook count and order", function()
        local hooks = {}
        local mod = {
            hook = function(_, class_name, method_name)
                hooks[#hooks + 1] = "hook:" .. class_name .. "." .. method_name
            end,
            hook_safe = function(_, class_name, method_name)
                hooks[#hooks + 1] = "hook_safe:" .. class_name .. "." .. method_name
            end,
        }
        local deps = {
            glow_badge = {},
            glow_picker = {},
            composite_icons = {},
            refresh_glow_editor_button = function() end,
            resolve_composed_appearance = function() end,
        }
        local module = assert(loadfile(repo_root .. "/" .. module_path))()
        local owner = module.install(mod, deps)
        H.equal(#hooks, 4)
        H.equal(hooks[1], "hook:UIWidget.init")
        H.equal(hooks[2], "hook_safe:ItemGridUI.init")
        H.equal(hooks[3], "hook_safe:ItemGridUI.add_item_to_slot_index")
        H.equal(hooks[4], "hook_safe:ItemGridUI._populate_inventory_page")
        H.equal(module.install(mod, deps), owner)
        H.equal(#hooks, 4)
        H.truthy(type(owner.refresh_illusion_glow_badges) == "function")
        H.truthy(type(mod._cos_glow_badges_refresh) == "function")
    end)

    H.test("Cosmetics item-grid owner adds no lifecycle or transport surface", function()
        H.equal(source:find("network_register", 1, true), nil)
        H.equal(source:find("network_send", 1, true), nil)
        H.equal(source:find("mod.on_game_state_changed", 1, true), nil)
        H.equal(source:find("mod.update", 1, true), nil)
        H.equal(occurrences(source, 'mod:hook("UIWidget", "init"'), 1)
        H.equal(occurrences(source, 'mod:hook_safe("ItemGridUI"'), 3)
    end)
end
