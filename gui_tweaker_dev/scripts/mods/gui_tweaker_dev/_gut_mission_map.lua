local mod = get_mod("gut_dev")

-- _gut_mission_map.lua -- in-mission mission-selection map access (#305).
--
-- Opens the start-game / mission-selection view (the keep's "M" map) DURING a
-- mission. Vanilla gates the "M" hotkey off mid-mission at the hotkey layer
-- (ingame_ui_settings.lua hotkey_map: can_interact_func "_handle_versus_matchmaking"
-- + disable_for_mechanism), so we bypass that layer and drive the transition
-- ourselves -- the exact pattern _gut_mission_inventory.lua uses for the inventory.
--
-- SAFETY -- why this needs NO backdrop swap (unlike _gut_mission_hero_select.lua):
-- StartGameView mounts NO keep-only preview world. Its init binds the LIVE mission
-- world (self.world_manager:world("level_world"), start_game_view.lua:48) and
-- create_ui_elements builds only flat scenegraph widgets -- loading bg/text + the
-- console cursor -- with no viewport pass carrying a level_name
-- (start_game_view.lua:183-195). Contrast CharacterSelectionView, whose viewport def
-- mounts levels/ui_character_selection/world (a hub-only bundle) and therefore needed
-- the def-swap in _gut_mission_hero_select.lua. So this feature registers ZERO hooks
-- and needs no restore machinery.
--
-- TRANSITION (verified): Managers.ui:handle_transition("start_game_view_force",
-- { menu_state_name = "play", use_fade = true }).
--   * start_game_view_force sets current_view="start_game_view" + exit_to_game=true
--     (ingame_ui_settings.lua:451-454) -- mirrors hero_view_force /
--     character_selection_force.
--   * The vanilla "M" hotkey routes to the same transition with transition_state
--     "play" (hotkey_map, ingame_ui_settings.lua:777-808).
--   * StartGameView.post_update_on_enter reads params.menu_state_name and calls
--     _change_screen_by_name(menu_state_name, ...) (start_game_view.lua:500-515);
--     "play" resolves to StartGameStateSettingsOverview
--     (start_game_view_definitions.lua:90-91) -- the mission-selection screen.
--     use_fade is the standard transition fade flag the sibling transitions pass.
--
-- EXIT: 100% vanilla, no hook. exit_to_game=true makes StartGameView.exit pass
-- return_to_game=true -> "exit_menu" transition (start_game_view.lua:550-553), so
-- ESC/back drops straight back to the mission.
--
-- MECHANISM GATE (adventure-only). VT2 mechanisms: adventure / deus (Chaos Wastes) /
-- versus / weave (Winds of Magic) [src: ingame_ui_settings.lua:784-800
-- disable_for_mechanism keys; store_ui_settings.lua:47-57]. We open ONLY in adventure
-- -- the mission-selection map the issue asks for. Blocked elsewhere:
--   * deus: the "play" screen is the CW journey-selection layout
--     (start_game_window_deus_journey_selection); a mid-run open is nonsensical and
--     the repo has a documented deus-view crash class -- both sibling in-mission
--     features (_gut_mission_inventory / _gut_mission_hero_select) hard-block deus.
--   * versus: vanilla itself gates "M" behind _handle_versus_matchmaking; the versus
--     "play" layouts reference matchmaking/lobby state -- nonsensical mid-match.
--   * weave / anything else: no positive evidence the layout opens safely mid-run,
--     so blocked by the same allow-list posture.
--
-- DISPATCH WIRING:
--   * mod.gut_open_mission_map is a PUBLIC `mod.` field, so the VMF keybind
--     (function_name = "gut_open_mission_map", default "M") resolves it at invoke
--     time and the /map command calls it directly.
--   * VMF keybinds are NON-BLOCKING (keybindings.lua perform_keybind_action only
--     observes Keyboard.pressed; it never blocks the input service), so binding "M"
--     does NOT shadow the keep's vanilla "M". The keybind is registered whenever the
--     mod is enabled regardless of the gut_mission_map master checkbox
--     (options.lua initialize_default_settings_and_keybinds), so this function MUST
--     gate on mod:get("gut_mission_map") itself -- which it does (SILENT no-op when
--     off, so nothing changes with the feature disabled + the default "M" binding).
--
-- Module dofile's from gui_tweaker_dev.lua after the main chunk (command + public
-- field only; no load-time hooks). Registers NO mod:hook / mod:hook_safe.

local _pf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

-- Human-readable mechanism name for the block echo.
local function _mech_label(mech)
    if mech == "deus" then return "Chaos Wastes" end
    if mech == "versus" then return "Versus" end
    if mech == "weave" then return "a Winds of Magic weave" end
    return tostring(mech)
end

mod.gut_open_mission_map = function()
    if not (Managers.ui and Managers.ui.handle_transition) then
        mod:echo("UI manager not available (not in-game?).")
        return
    end
    -- Master toggle gate. When OFF the feature must change nothing -- and because the
    -- default keybind is "M" (registered regardless of this checkbox, see docstring),
    -- be SILENT here (printf only) so a stray M-press in a mission with the feature
    -- off does nothing visible. No echo.
    if not mod:get("gut_mission_map") then
        _pf("[gut_dev:MM] gate=disabled (gut_mission_map off) -> no-op")
        return
    end
    -- Keep detection: vanilla "M" already opens the map in the keep, so no-op there
    -- (silently -- vanilla handles it). Robust check mirrors _gut_mission_hero_select:
    -- level_key == "inn_level" (primary) OR DamageUtils.is_in_inn (backup).
    local gm  = Managers.state and Managers.state.game_mode
    local lvl = (gm and gm.level_key) and gm:level_key() or nil
    local dui = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    local in_keep = (lvl == "inn_level") or dui or false
    if in_keep then
        _pf("[gut_dev:MM] gate=keep (level_key=%s is_in_inn=%s) -> no-op; vanilla M handles the keep",
            tostring(lvl), tostring(dui))
        return
    end
    -- Mechanism gate: adventure only (see docstring). deus/versus/weave/other blocked.
    local mech = Managers.mechanism and Managers.mechanism.current_mechanism_name
        and Managers.mechanism:current_mechanism_name() or nil
    if mech ~= "adventure" then
        _pf("[gut_dev:MM] gate=mechanism blocked (mechanism=%s; adventure-only) -> no-op", tostring(mech))
        mod:echo("The in-mission map is available in Adventure only, not in " .. _mech_label(mech) .. ".")
        return
    end
    -- Host-only gate (issue #305 toggle, default off). Repo-standard host check is the
    -- Managers.player.is_server field (used across gt_dev).
    local host_only = mod:get("gut_mission_map_host_only") and true or false
    local is_host = (Managers.player and Managers.player.is_server) and true or false
    if host_only and not is_host then
        _pf("[gut_dev:MM] gate=host_only blocked (host_only=true is_host=false) -> no-op")
        mod:echo("The mission map is set to host only; only the party host can open it mid-mission.")
        return
    end
    _pf("[gut_dev:MM] gate=opened (mechanism=adventure host_only=%s is_host=%s) -> start_game_view_force menu_state_name=play",
        tostring(host_only), tostring(is_host))
    local ok, err = pcall(function()
        Managers.ui:handle_transition("start_game_view_force", {
            menu_state_name = "play",
            use_fade        = true,
        })
    end)
    if not ok then
        _pf("[gut_dev:MM] handle_transition FAILED: %s", tostring(err))
        mod:echo("Could not open the mission map: " .. tostring(err))
    end
end

mod:command("map", "Open the mission-selection map mid-mission (the same screen the keep's M key shows). Adventure only.", function()
    mod.gut_open_mission_map()
end)
