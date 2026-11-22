-- qa/runtime/cim/issue_80_cim_standard_bench_opens.lua
-- WP-CIM-03 rig case: /cim_craft_standard opens the Keep crafting bench
-- instead of asserting. Advances #80 (class R); its in-mission tab route is
-- owned by gui_tweaker and is not decided here.
--
-- Engine reads (Vermintide-2-Source-Code):
--   * IngameUI.current_view = "hero_view" on the hero_view transitions:
--     scripts/ui/views/ingame_ui_settings.lua:442-449; cleared at ingame_ui.lua:239
--   * the assert this case forbids: scripts/ui/views/hero_view/hero_view.lua:477-480
--   * "exit_menu" transition: scripts/ui/views/ingame_ui_settings.lua:506; IngameUI.handle_transition: ingame_ui.lua:919
--
-- If the view opens but _cim_standard_forge_active stays false, record which
-- layout ran (hero_window_layout_console.lua:130 may be in use): card stop
-- condition, not a product verdict. describe_hero_view notes it on every run.
-- The case tests the PC layout the owner plays with: run it with
-- qa/runtime/plans/cim-cases.json, which sets use_pc_menu_layout = true. On the
-- console layout the bench opens the vanilla HeroWindowCraftingListConsole and
-- cim's flag is never set (known limitation, rig run 20261115-162744,
-- hero_window_layout_console.lua:128-141).
-- Diagnostic reads (notes only, never asserted):
--   * IngameUI.views, keyed by view name: ingame_ui.lua:146
--   * HeroView._machine and its state(): hero_view.lua:82-95, 438-442
--   * the overview state picks hero_window_layout_console when the gamepad is
--     active or UISettings.use_pc_menu_layout is false:
--     scripts/ui/views/hero_view/states/hero_view_state_overview.lua:143-156;
--     UISettings.use_pc_menu_layout: scripts/settings/ui_settings.lua:77
--   * local_require keeps the layout table in package.loaded:
--     foundation/scripts/util/local_require.lua:5-16
--   * active windows by index and get_layout_name:
--     hero_view_state_overview.lua:250-253, 337, 344-352; window NAME fields,
--     e.g. hero_window_crafting_console.lua:66

local MOD_ID = "cim_dev"

local LAYOUT_FILES = {
    console = "scripts/ui/views/hero_view/states/hero_window_layout_console",
    pc = "scripts/ui/views/hero_view/states/hero_window_layout",
}

local function current_view()
    local ui = Managers.ui and Managers.ui._ingame_ui
    return ui and ui.current_view
end

-- Notes which overview layout and windows the open hero view is running.
local function describe_hero_view(T)
    local ui = Managers.ui and Managers.ui._ingame_ui
    local views = ui and ui.views
    local view = type(views) == "table" and views.hero_view or nil
    local machine = type(view) == "table" and view._machine or nil
    local state
    if type(machine) == "table" and type(machine.state) == "function" then
        local ok, result = pcall(machine.state, machine)
        if ok and type(result) == "table" then state = result end
    end
    T.note("hero_view_state", tostring(state and state.NAME))
    if not state then return end

    local ok_name, layout_name = pcall(function()
        return type(state.get_layout_name) == "function" and state:get_layout_name() or nil
    end)
    T.note("layout_name", ok_name and tostring(layout_name) or ("error: " .. tostring(layout_name)))

    local package_table = rawget(_G, "package")
    local loaded = type(package_table) == "table" and package_table.loaded or {}
    local layout_file = state._layout_settings == nil and "none" or "unknown"
    for name, path in pairs(LAYOUT_FILES) do
        if state._layout_settings ~= nil and loaded[path] == state._layout_settings then
            layout_file = name
        end
    end
    T.note("layout_file", layout_file)
    T.note("hero_window_layout_console_in_use", tostring(layout_file == "console"))

    local ui_settings = rawget(_G, "UISettings")
    T.note("use_pc_menu_layout", tostring(type(ui_settings) == "table" and ui_settings.use_pc_menu_layout))
    local ok_pad, gamepad = pcall(function() return Managers.input:is_device_active("gamepad") end)
    T.note("gamepad_active", ok_pad and tostring(gamepad) or "unknown")

    local windows = type(state._active_windows) == "table" and state._active_windows or {}
    local indices = {}
    for index in pairs(windows) do indices[#indices + 1] = index end
    table.sort(indices, function(a, b) return tostring(a) < tostring(b) end)
    local names = {}
    for _, index in ipairs(indices) do
        local window = windows[index]
        names[#names + 1] = tostring(index) .. "=" .. tostring(type(window) == "table" and window.NAME)
    end
    T.note("active_windows", #names > 0 and table.concat(names, ",") or "none")
end

local function close_view(T)
    local ui = Managers.ui and Managers.ui._ingame_ui
    if ui and ui.current_view ~= nil then
        ui:handle_transition("exit_menu")
        if T then
            T.wait_until(function() return current_view() == nil end, 15, "view closed")
        end
    end
end

return {
    id = "cim-80-standard-bench-opens",
    issue = 80,
    class = "R",
    covers = "WP-CIM-03 RIG acceptance: /cim_craft_standard opens hero_view on the forge layout",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 90,

    host_forbid_log = { "Could not find state by name" },

    run = function(T)
        local cim = get_mod(MOD_ID)
        T.require(cim ~= nil, "cim_dev loaded")
        T.require(current_view() == nil, "no view open before the command")

        T.step("open the standard bench")
        T.cmd("cim_craft_standard")
        T.wait_until(function() return current_view() == "hero_view" end, 15, "hero view open")
        T.wait(2)
        T.note("current_view", tostring(current_view()))
        describe_hero_view(T)
        T.expect(cim._cim_standard_forge_active == true, "crafting window entered")

        T.step("close the view")
        close_view(T)
    end,

    cleanup = function()
        close_view(nil)
    end,
}
