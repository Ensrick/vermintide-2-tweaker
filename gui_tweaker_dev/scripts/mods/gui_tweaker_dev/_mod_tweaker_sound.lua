local mod = get_mod("gut_dev")

-- _mod_tweaker_sound.lua - the ONE Wwise resolver for both Mod Tweaker presentations.
--
-- Both twins fire the native Options menu events on the Options menu's wwise
-- world: "Play_hud_select" on a commit (options_view.lua:544) and
-- "Play_hud_hover" on hover-enter (options_view.lua:424). The Esc route opens the
-- standalone ModTweakerView (_mod_tweaker_view.lua); the /mod_tweaker command opens
-- the keep HeroView sub-state (_mod_tweaker_state.lua), because
-- _ba_heroview_inject.lua registers that command after the entry file and VMF lets
-- a mod overwrite its own command (VMF commands.lua:15-28).
--
-- (#1670) Through 0.2.358-dev the sub-state still carried the pre-0.2.82-dev lookup
-- World.wwise_world(Managers.world:world("music_world")). On PC the music world is
-- the boot global MUSIC_WORLD made by Application.new_world (boot_init.lua:23,31-33)
-- and never registered with WorldManager (create_world, world_manager.lua:18-56, is
-- the only registration), so WorldManager.world fasserts (world_manager.lua:111-113,
-- error.lua:25-30) and the pcall around it dropped every click and hover on the
-- command route. Both twins now resolve here, exactly as OptionsView does
-- (options_view.lua:282-288), so the two routes cannot drift again.
--
-- Owned by: the two Mod Tweaker twins (mod:dofile per twin). The live check body
-- (check_routes) is registered once by _gut_mod_tweaker_contracts.lua.

local M = {}

M.PATH_GLOBAL = "MUSIC_WWISE_WORLD"
M.PATH_MANAGER = "Managers.world:wwise_world(music_world)"

-- Returns wwise_world, path name; or nil, reason. A world is only returned once it
-- is proven to be a Wwise handle (BUG_CLASSES "registered wwise world" rule): the
-- boot global, or a WorldManager registration read through has_world first,
-- because WorldManager.world fasserts on an unknown name.
function M.resolve()
    if rawget(_G, "GLOBAL_MUSIC_WORLD") and rawget(_G, "MUSIC_WWISE_WORLD") then
        return rawget(_G, "MUSIC_WWISE_WORLD"), M.PATH_GLOBAL
    end
    local managers = rawget(_G, "Managers")
    local wm = managers and managers.world
    if not (wm and type(wm.has_world) == "function" and type(wm.wwise_world) == "function") then
        return nil, "no world manager"
    end
    if not wm:has_world("music_world") then
        return nil, "music_world is not registered with Managers.world"
    end
    local ww = wm:wwise_world(wm:world("music_world"))
    if not ww then return nil, "music_world has no registered wwise world" end
    return ww, M.PATH_MANAGER
end

-- Fires one event on the resolved world. Returns true when it was triggered.
function M.play(event)
    local ok, ww = pcall(M.resolve)
    if not (ok and ww) then return false end
    return (pcall(function() WwiseWorld.trigger_event(ww, event) end))
end

-- One-time debug line per twin so a silent menu shows which path resolved.
function M.new_probe(tag)
    local probed = false
    return function()
        if probed then return end
        probed = true
        local ok, ww, path = pcall(M.resolve)
        pcall(mod.debug, mod, "[mt:wwise] (%s) GLOBAL_MUSIC_WORLD=%s resolved=%s path=%s", tag,
            tostring(rawget(_G, "GLOBAL_MUSIC_WORLD")), tostring(ok and ww ~= nil),
            tostring(ok and path or ww))
    end
end

-- (#1670) Body of the issue1670_command_route_sound_path check (registered in
-- _gut_mod_tweaker_contracts.lua). Keep only: the command route (sub-state) must
-- resolve the same wwise world, by the same path, as the Esc route (standalone
-- view), and that world must be the one vanilla OptionsView uses. Each twin
-- publishes the resolver its clicks and hovers fire on as gut_sound_resolve.
-- This is a wiring contract: both twins publish this module's resolve, so it
-- proves the published resolver, not that each click and hover fires through it.
-- The behavioural proof is the offline test_gut_mod_tweaker_sound_parity.lua (it
-- fires the real play_click/play_hover) plus the audible in-keep step. The verdict
-- is the only output: the check writes no log line of its own.
function M.check_routes()
    -- Live keep flag (state_ingame.lua:137, state_ingame_running.lua:175); the captured
    -- ingame UI context can outlive the keep it was taken in.
    local du = rawget(_G, "DamageUtils")
    if not (du and du.is_in_inn == true) then
        return "skip: not in the keep; /mod_tweaker opens the HeroView sub-state only in the keep"
    end
    local ctx = mod._gut_ingame_ui_context
    if not ctx then return "skip: no ingame UI context captured yet (open the keep menu once)" end
    local State = rawget(_G, "HeroViewStateModTweaker")
    if type(State) ~= "table" then return "HeroViewStateModTweaker class global not defined" end
    if type(State.gut_sound_resolve) ~= "function" then
        return "keep sub-state (command route) does not publish gut_sound_resolve"
    end
    local ui = ctx.ingame_ui
    local view = ui and ui.views and ui.views.mod_tweaker_view
    if not view then
        return "skip: standalone ModTweakerView (Esc route) is not attached to this IngameUI yet"
            .. " (open and close Esc > Mod Tweaker once, then rerun)"
    end
    if type(view.gut_sound_resolve) ~= "function" then
        return "standalone ModTweakerView (Esc route) does not publish gut_sound_resolve"
    end
    local esc_ww, esc_path = view.gut_sound_resolve()
    local cmd_ww, cmd_path = State.gut_sound_resolve()
    if not esc_ww then return "Esc route resolved no wwise world: " .. tostring(esc_path) end
    if cmd_ww ~= esc_ww or cmd_path ~= esc_path then
        return string.format("command route resolved %s (%s), Esc route %s (%s)",
            tostring(cmd_path), tostring(cmd_ww), tostring(esc_path), tostring(esc_ww))
    end
    if rawget(_G, "GLOBAL_MUSIC_WORLD") and cmd_ww ~= rawget(_G, "MUSIC_WWISE_WORLD") then
        return "GLOBAL_MUSIC_WORLD is set but the Mod Tweaker world is not MUSIC_WWISE_WORLD"
    end
    return nil
end

return M
