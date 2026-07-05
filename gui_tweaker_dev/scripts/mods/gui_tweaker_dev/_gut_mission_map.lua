local mod = get_mod("gut_dev")

-- _gut_mission_map.lua -- in-mission mission-selection map access (#305).
--
-- Opens the start-game / mission-selection view (the keep's "M" map) DURING a
-- mission. Vanilla gates the "M" hotkey off mid-mission at the hotkey layer
-- (ingame_ui_settings.lua hotkey_map: can_interact_func "_handle_versus_matchmaking"
-- + disable_for_mechanism), so we bypass that layer and drive the transition
-- ourselves -- the exact pattern _gut_mission_inventory.lua uses for the inventory.
--
-- SAFETY -- backdrop swap REQUIRED after all (#336 CTD; supersedes the v0.2.188
-- docstring claim that no swap was needed). StartGameView ITSELF mounts no keep-only
-- world (init binds the live mission world, start_game_view.lua:48; create_ui_elements
-- builds flat widgets only, start_game_view.lua:183-195) -- but its WINDOWS do: the
-- "play" screen enters StartGameWindowBackgroundConsole, whose viewport def mounts
-- level_name = "levels/ui_keep_menu/world" and calls LevelResource.object_set_names
-- on it at def-BUILD time (start_game_window_background_console.lua:56/66; also
-- _setup_object_sets:114, and post_update:181 spawns the level via UIWidget.init).
-- That level resource is resident only in the hub; mid-mission the engine raises
-- "Level not loaded" -- FATAL, bypasses pcall (same class as Unit.node) -- crashing
-- exactly when the transition lands (crash log 2026-07-05 16.49.12-44a6c78a,
-- skittergate, 17:01:57). Fix: the def-swap hooks below (same recipe as
-- _gut_mission_hero_select.lua) mount the mission-safe inventory-preview stage
-- instead whenever the keep backdrop is not gettable.
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
-- Module dofile's from gui_tweaker_dev.lua after the main chunk. Registers TWO
-- singleton hooks on StartGameWindowBackgroundConsole (#336 backdrop swap below);
-- HOOK PRE-FLIGHT: gut_dev registers no other hook on that class (grep 2026-07-05).

local _pf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

-- Human-readable mechanism name for the block echo.
local function _mech_label(mech)
    if mech == "deus" then return "Chaos Wastes" end
    if mech == "versus" then return "Versus" end
    if mech == "weave" then return "a Winds of Magic weave" end
    return tostring(mech)
end

-- ---------------------------------------------------------------
-- BACKDROP SWAP (#336). See the SAFETY docstring above for the crash mechanics.
-- ---------------------------------------------------------------
local KEEP_MENU_LEVEL = "levels/ui_keep_menu/world"         -- native backdrop (hub bundle only)
local PREVIEW_LEVEL   = "levels/ui_inventory_preview/world" -- mission-safe stage (hero-select precedent)

-- can_get("level", name) with the hero-select trust protocol: the "level" query type
-- is only believed after it returns true for the CURRENT mission's own (resident)
-- level, so a broken can_get can never green-light a fatal spawn. Returns
-- true / false / nil (nil = unknown; can_get untrustworthy in this state).
local function _can_get_level(level_name)
    local can_get = Application and Application.can_get
    if not can_get then return nil end
    local gm = Managers.state and Managers.state.game_mode
    local level_key = (gm and gm.level_key) and gm:level_key() or nil
    local settings = level_key and rawget(_G, "LevelSettings") and LevelSettings[level_key]
    local current = settings and settings.level_name
    if not current then return nil end
    local ok_self, self_avail = pcall(can_get, "level", current)
    if not ok_self or not self_avail then return nil end
    local ok, avail = pcall(can_get, "level", level_name)
    if not ok then return nil end
    return avail and true or false
end
mod._gut_mm_can_get_level = _can_get_level   -- consumed by /regression_test

-- Swap hook. Keep path (ui_keep_menu resident, or state unknown = keep-only flows)
-- is byte-for-byte vanilla. Swapped path mirrors the vanilla def shape
-- (start_game_window_background_console.lua:47-84) with level_name/object_sets
-- re-pointed at the preview stage, and marks the window instance so the
-- _update_object_sets hook below knows this backdrop is swapped. Full wrapper (not
-- hook_safe): the vanilla body itself raises before returning, so flow must DIVERT.
mod:hook("StartGameWindowBackgroundConsole", "_create_viewport_definition", function(func, self, ...)
    if _can_get_level(KEEP_MENU_LEVEL) ~= false then
        return func(self, ...)
    end
    local ok_sets, object_sets = pcall(LevelResource.object_set_names, PREVIEW_LEVEL)
    if not ok_sets or type(object_sets) ~= "table" then object_sets = {} end
    self._gut_mm_swapped_backdrop = true
    _pf("[gut_dev:MM] backdrop def-swap APPLIED: %s not resident -> %s (%d object sets)",
        KEEP_MENU_LEVEL, PREVIEW_LEVEL, #object_sets)
    return {
        scenegraph_id = "root_fit",
        element = UIElements.Viewport,
        style = {
            viewport = {
                clear_screen_on_create = true,
                enable_sub_gui = false,
                fov = 50,
                layer = 990,
                level_name = PREVIEW_LEVEL,
                mood_setting = "default",
                shading_environment = "environment/ui_end_screen",
                viewport_name = "character_preview_viewport",
                world_name = "character_preview",
                world_flags = {
                    Application.DISABLE_SOUND,
                    Application.DISABLE_ESRAM,
                    Application.ENABLE_VOLUMETRICS,
                },
                object_sets = object_sets,
                camera_position = { 0, 0, 0 },
                camera_lookat = { 0, 0, 0 },
            },
        },
        content = {
            button_hotspot = {
                allow_multi_hover = true,
            },
        },
    }
end)

-- Scenery-pass hook. On layout switch the window drives KEEP-level object sets +
-- flow events ("quick_play"/"custom_game"/..., start_game_window_layout_console.lua:72+).
-- Neither exists on the preview stage, and MenuWorldPreviewer.trigger_level_flow_event
-- is a bare Level.trigger_event (menu_world_previewer.lua:769-770) -- an engine-assert
-- risk on a missing event. The whole pass is backdrop scenery, so on a swapped
-- instance divert it entirely; native (keep) instances run vanilla untouched.
mod:hook("StartGameWindowBackgroundConsole", "_update_object_sets", function(func, self, ...)
    if not self._gut_mm_swapped_backdrop then
        return func(self, ...)
    end
    _pf("[gut_dev:MM] _update_object_sets diverted (swapped backdrop: keep-only object sets/flow events)")
end)

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
    -- Backdrop availability gate (#336): the play screen's background window MUST
    -- mount a level (see SAFETY docstring). Fail CLOSED unless the keep backdrop is
    -- positively resident (never true mid-mission) or the swap hook's preview stage
    -- is positively gettable -- an unknown (nil) verdict is treated as unavailable.
    local keep_ok    = _can_get_level(KEEP_MENU_LEVEL)
    local preview_ok = _can_get_level(PREVIEW_LEVEL)
    if keep_ok ~= true and preview_ok ~= true then
        _pf("[gut_dev:MM] gate=backdrop blocked (keep=%s preview=%s) -> no-op",
            tostring(keep_ok), tostring(preview_ok))
        mod:echo("Cannot open the mission map here: no menu backdrop level is loadable.")
        return
    end
    _pf("[gut_dev:MM] gate=opened (mechanism=adventure host_only=%s is_host=%s backdrop keep=%s preview=%s) -> start_game_view_force menu_state_name=play",
        tostring(host_only), tostring(is_host), tostring(keep_ok), tostring(preview_ok))
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
