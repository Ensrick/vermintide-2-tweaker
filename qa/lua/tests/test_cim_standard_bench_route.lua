-- WP-CIM-03 (#80): /cim_craft_standard and the standard_crafting_hotkey keybind
-- open the Keep bench through a real HeroView screen. "forge" is a window
-- layout of the overview screen, not a screen: passing it as menu_state_name
-- asserts in HeroView._change_screen_by_name
-- (Vermintide-2-Source-Code/scripts/ui/views/hero_view/hero_view.lua:477-480).

local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    return (text:gsub("\r\n", "\n"))
end

local function names_in(text)
    local names = {}
    for name in ("\n" .. text):gmatch('[%s{,]name%s*=%s*"([^"]+)"') do
        names[name] = true
    end
    return names
end

return function(H, repo_root)
    local dev_root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local route_path = dev_root .. "_cim_bench_route.lua"
    -- The stable entry joins this list with the card's stable half (PR #1824
    -- holds crafting_in_modded/ while this lands).
    local entry_paths = {
        dev_root .. "crafting_in_modded_dev.lua",
    }

    local function load_route()
        local chunk, err = loadfile(route_path)
        assert(chunk, "cim bench route module is missing: " .. tostring(err))
        local M = chunk()
        assert(type(M) == "table", "cim bench route must return a table")
        return M
    end

    H.test("cim bench route: transition params name the overview screen and the forge layout", function()
        local M = load_route()
        local first = M.transition_params()
        H.deep_equal(first, { menu_state_name = "overview", menu_sub_state_name = "forge" })
        local second = M.transition_params()
        H.truthy(not rawequal(first, second), "a new table on each call")
        first.menu_state_name = "mutated"
        H.equal(M.transition_params().menu_state_name, "overview", "callers cannot poison the route")
    end)

    H.test("cim bench route: no entry passes forge as a HeroView screen", function()
        for i = 1, #entry_paths do
            local text = read(entry_paths[i])
            H.truthy(text ~= nil, "entry readable: " .. entry_paths[i])
            H.equal(text:find('menu_state_name = "forge"', 1, true), nil,
                "forge passed as a screen name in " .. entry_paths[i])
        end
    end)

    local source_root = (os.getenv("VT2_DECOMPILE_ROOT")
        or (repo_root .. "/../Vermintide-2-Source-Code")) .. "/scripts/ui/views/hero_view/"
    local definitions = read(source_root .. "hero_view_definitions.lua")
    local layouts = read(source_root .. "states/hero_window_layout.lua")
    H.test_if(definitions ~= nil and layouts ~= nil,
        "cim bench route: screen and sub-state names exist in the decompiled HeroView",
        function()
            local M = load_route()
            local params = M.transition_params()
            local screens = names_in(definitions)
            local windows = names_in(layouts)
            H.truthy(screens[params.menu_state_name],
                params.menu_state_name .. " is not a HeroView screen (hero_view_definitions.lua)")
            H.truthy(windows[params.menu_sub_state_name],
                params.menu_sub_state_name .. " is not a window layout (hero_window_layout.lua)")
            H.truthy(not screens.forge, "the decompile now has a screen named forge: re-check the route")
        end,
        "decompiled Vermintide-2-Source-Code checkout not found (set VT2_DECOMPILE_ROOT)")
end
