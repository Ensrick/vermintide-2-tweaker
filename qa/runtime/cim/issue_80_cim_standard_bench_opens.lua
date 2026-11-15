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
-- condition, not a product verdict.

local MOD_ID = "cim_dev"

local function current_view()
    local ui = Managers.ui and Managers.ui._ingame_ui
    return ui and ui.current_view
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
        T.expect(cim._cim_standard_forge_active == true, "crafting window entered")
        T.note("current_view", tostring(current_view()))

        T.step("close the view")
        close_view(T)
    end,

    cleanup = function()
        close_view(nil)
    end,
}
