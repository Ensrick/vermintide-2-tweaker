local mod = get_mod("gut_dev")

-- _gut_mission_map.lua -- in-mission mission-selection map access (#305).
--
-- Opens the start-game / mission-selection view (the keep's "M" map) DURING a
-- mission. Vanilla gates the "M" hotkey off mid-mission at the hotkey layer
-- (ingame_ui_settings.lua hotkey_map: can_interact_func "_handle_versus_matchmaking"
-- + disable_for_mechanism), so we bypass that layer and drive the transition
-- ourselves -- the exact pattern _gut_mission_inventory.lua uses for the inventory.
--
-- SAFETY -- backdrop must be TRANSPARENT (live mission visible) and the keep-only world
-- must NOT spawn mid-mission (#336 CTD). StartGameView ITSELF mounts no keep-only
-- world (init binds the live mission world, start_game_view.lua:48; create_ui_elements
-- builds flat widgets only, start_game_view.lua:183-195) -- but its WINDOWS do: the
-- "play" screen enters StartGameWindowBackgroundConsole, whose viewport def mounts
-- level_name = "levels/ui_keep_menu/world" and calls LevelResource.object_set_names
-- on it at def-BUILD time (start_game_window_background_console.lua:56/66; also
-- _setup_object_sets:114, and post_update:181 spawns the level via UIWidget.init).
-- That level resource is resident only in the hub; mid-mission the engine raises
-- "Level not loaded" -- FATAL, bypasses pcall (same class as Unit.node) -- crashing
-- exactly when the transition lands (crash log 2026-07-05 16.49.12-44a6c78a,
-- skittergate, 17:01:57).
--
-- BACKDROP (two tiers, #336 follow-up). The user wants the map drawn OVER the live game,
-- exactly like the in-mission hero/inventory views -- no black plate, no separate preview
-- world. So:
--   (1) keep backdrop resident, or state unknown (keep-only flows) -> vanilla def, no swap.
--   (2) keep NOT resident (the normal mid-mission case) -> a level-less def (NO level_name
--       key, empty object_sets) AND a post_update hook that SKIPS the vanilla body, so the
--       viewport widget is never UIWidget.init'd. No world is created at all and the live
--       mission shows through behind the flat map UI. The def still exists (shape-compatible)
--       only so create_ui_elements / _setup_object_sets don't nil-deref; it is never
--       instantiated on the transparent tier.
-- Every StartGameWindowBackgroundConsole consumer of the viewport / world_previewer is
-- nil-guarded in vanilla (update :147 world_previewer, draw :227 viewport, on_exit
-- :130-140 both), so a post_update that never creates them renders NOTHING from this
-- window. The loading plate still fades out: the skipping post_update sets
-- _fadeout_loading_overlay and runs _update_loading_overlay_fadeout_animation
-- (:236-261) so the overlay does not stay up. The transparent def has a nil level_name,
-- which vanilla _setup_object_sets (:112-123) would call LevelResource.object_set_names(nil)
-- on and raise -- the _setup_object_sets divert below short-circuits that.
--
-- AUTO-START (#336). Picking a mission from the mid-mission map must actually START it.
-- Vanilla matchmaking hangs mid-mission because nothing sets the countdown flag the
-- keep's waystone-portal normally sets: MatchmakingStateWaitForCountdown.update
-- (matchmaking_state_wait_for_countdown.lua:26-50) leaves for MatchmakingStateStartGame
-- only when Managers.matchmaking.countdown_has_finished (normal mode) or .start_game_now
-- (when search_config.wait_to_start_game) is true; in the keep the portal countdown sets
-- them, mid-mission NOTHING does. The on_enter hook below sets the right flag on entry
-- (host + adventure + not-in-keep only), so the state advances immediately.
-- MatchmakingStateStartGame then rolls the level + seed, calls
-- level_transition_handler:set_next_level(...) (matchmaking_state_start_game.lua:363) and
-- finally Managers.state.game_mode:complete_level() (:408). That last call mid-mission
-- would end the CURRENT round as a FAKE "won" (GameModeManager.complete_level sets
-- _level_completed at game_mode_base.lua:171-173; game_mode_adventure.lua:124-129 then
-- reports the round "won" with rewards/stats). The GameModeManager.complete_level hook
-- below diverts the armed call to Managers.level_transition_handler:promote_next_level_data()
-- instead -- the exact clean mid-mission swap the vanilla "return to keep" vote uses
-- (GameModeManager.start_specific_level, game_mode_manager.lua:678-692): set_next_level was
-- already called at :363, so promote alone completes the transition with NO win/loss.
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
-- Module dofile's from gui_tweaker_dev.lua after the main chunk. Registers FOUR
-- singleton hooks on StartGameWindowBackgroundConsole (_create_viewport_definition,
-- _update_object_sets, _setup_object_sets, post_update) plus one hook_safe on
-- MatchmakingStateWaitForCountdown.on_enter (auto-start arm) and one full hook on
-- GameModeManager.complete_level (clean-transition divert). HOOK PRE-FLIGHT (grep
-- 2026-07-05): gut_dev registers no other hook on StartGameWindowBackgroundConsole,
-- none on MatchmakingStateWaitForCountdown, and on GameModeManager only
-- .has_activated_mutator (hb/hide_elements.lua -- a different method, no collision).

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

-- Swap hook (two tiers, #336). Tier 1: keep path (ui_keep_menu resident, or state
-- unknown = keep-only flows) is byte-for-byte vanilla. Tier 2 (transparent; the normal
-- mid-mission case): keep NOT resident -> a def with NO level_name key and empty object
-- sets, and BOTH markers set. _gut_mm_swapped_backdrop drives the _update_object_sets
-- divert; _gut_mm_none_backdrop drives both the _setup_object_sets divert (nil level_name
-- would raise there) AND the post_update hook, which SKIPS widget creation entirely so no
-- world spawns and the live mission shows through. The def is never instantiated on this
-- tier -- it exists only to keep create_ui_elements / _setup_object_sets shape-compatible.
-- Full wrapper (not hook_safe): the vanilla body dereferences a keep level that may not be
-- resident, so flow must DIVERT.
mod:hook("StartGameWindowBackgroundConsole", "_create_viewport_definition", function(func, self, ...)
    -- Tier 1: keep backdrop resident, or state unknown -> vanilla def, no swap.
    if _can_get_level(KEEP_MENU_LEVEL) ~= false then
        return func(self, ...)
    end
    -- Tier 2 (transparent): keep not resident -> level-less def (no level_name key, empty
    -- object sets). Both markers set: swapped marker drives _update_object_sets; none
    -- marker drives _setup_object_sets and post_update (no world spawns -> live mission
    -- visible behind the flat map UI).
    self._gut_mm_swapped_backdrop = true
    self._gut_mm_none_backdrop    = true
    _pf("[gut_dev:MM] backdrop def-swap TRANSPARENT: %s not resident -> no world spawned (live mission visible)",
        KEEP_MENU_LEVEL)
    return {
        scenegraph_id = "root_fit",
        element = UIElements.Viewport,
        style = {
            viewport = {
                clear_screen_on_create = true,
                enable_sub_gui = false,
                fov = 50,
                layer = 990,
                mood_setting = "default",
                shading_environment = "environment/ui_end_screen",
                viewport_name = "character_preview_viewport",
                world_name = "character_preview",
                world_flags = {
                    Application.DISABLE_SOUND,
                    Application.DISABLE_ESRAM,
                    Application.ENABLE_VOLUMETRICS,
                },
                object_sets = {},
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
-- Neither exists on a transparent (world-less) instance, and there is no world_previewer
-- there at all (post_update skips its creation); MenuWorldPreviewer.trigger_level_flow_event
-- is a bare Level.trigger_event (menu_world_previewer.lua:769-770) -- an engine-assert risk
-- on a missing event. The whole pass is backdrop scenery, so on a swapped instance divert
-- it entirely; native (keep) instances run vanilla untouched.
mod:hook("StartGameWindowBackgroundConsole", "_update_object_sets", function(func, self, ...)
    if not self._gut_mm_swapped_backdrop then
        return func(self, ...)
    end
    _pf("[gut_dev:MM] _update_object_sets diverted (swapped backdrop: keep-only object sets/flow events)")
end)

-- Object-set setup hook (#336 transparent tier). Vanilla _setup_object_sets reads
-- self._viewport_widget_definition.style.viewport.level_name and calls
-- LevelResource.object_set_names(level_name) (start_game_window_background_console.lua:112-123).
-- On a transparent instance that level_name is nil (tier 2 omits the key), and
-- object_set_names(nil) raises. Short-circuit to an empty object-set map on the none
-- instance (or any nil-level def); native (keep) instances carry a level_name and run
-- vanilla untouched. Full wrapper: the vanilla body raises before returning.
mod:hook("StartGameWindowBackgroundConsole", "_setup_object_sets", function(func, self, ...)
    local vp_def = self._viewport_widget_definition
    local level_name = vp_def and vp_def.style and vp_def.style.viewport and vp_def.style.viewport.level_name
    if self._gut_mm_none_backdrop or level_name == nil then
        self._object_sets = {}
        _pf("[gut_dev:MM] _setup_object_sets diverted (transparent backdrop: nil level_name -> empty object sets)")
        return
    end
    return func(self, ...)
end)

-- Transparent-backdrop hook (#336). On a none-backdrop instance vanilla post_update would
-- UIWidget.init the viewport widget (start_game_window_background_console.lua:181) and spawn
-- a MenuWorldPreviewer world (:187-194), painting a plate over the live mission. Skip the
-- whole vanilla body so neither is ever created -- every downstream consumer of
-- self._viewport_widget / self.world_previewer is nil-guarded in vanilla (update :147,
-- draw :227, on_exit :130-140), so the window renders NOTHING and the live mission shows
-- through. Still drive the loading-plate fade so it does not stay up: vanilla arms the
-- fade when it creates the widget (:182); here we arm it directly and run the same
-- fadeout animation (:236-261). Native (keep) instances run vanilla untouched.
mod:hook("StartGameWindowBackgroundConsole", "post_update", function(func, self, dt, t)
    if not self._gut_mm_none_backdrop then
        return func(self, dt, t)
    end
    if self._show_loading_overlay and not self._fadeout_loading_overlay then
        self._fadeout_loading_overlay = true
    end
    self:_update_loading_overlay_fadeout_animation(dt)
end)

-- ---------------------------------------------------------------
-- AUTO-START (#336). See the AUTO-START docstring above for the matchmaking chain.
-- ---------------------------------------------------------------

-- Auto-start arm (hook_safe, observe-only). Mid-mission the matchmaking countdown flag is
-- never set (no waystone portal), so MatchmakingStateWaitForCountdown.update stalls forever
-- (matchmaking_state_wait_for_countdown.lua:26-50). On entry, set the flag the state polls:
-- start_game_now when the search_config is wait_to_start_game, else countdown_has_finished.
-- Gated to host + adventure + not-in-keep (in the keep the vanilla portal countdown owns
-- these flags -- never touch them there). Arm a timestamp so the complete_level divert below
-- fires only for THIS auto-start, not a later genuine level completion.
mod:hook_safe("MatchmakingStateWaitForCountdown", "on_enter", function(self, state_context)
    if not mod:get("gut_mission_map") then return end
    local is_host = (Managers.player and Managers.player.is_server) and true or false
    if not is_host then return end
    local mech = Managers.mechanism and Managers.mechanism.current_mechanism_name
        and Managers.mechanism:current_mechanism_name() or nil
    if mech ~= "adventure" then return end
    -- Not-in-keep (mirrors gut_open_mission_map's idiom): level_key ~= "inn_level" and
    -- not DamageUtils.is_in_inn. In the keep the waystone portal sets the countdown flags.
    local gm  = Managers.state and Managers.state.game_mode
    local lvl = (gm and gm.level_key) and gm:level_key() or nil
    local dui = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if lvl == "inn_level" or dui then return end
    -- Arm the divert window, then set the countdown flag the state's update polls.
    mod._gut_mm_autostart_t = Managers.time and Managers.time:time("main") or nil
    local sc = state_context and state_context.search_config
    if sc and sc.wait_to_start_game then
        Managers.matchmaking.start_game_now = true
    else
        Managers.matchmaking.countdown_has_finished = true
    end
    _pf("[gut_dev:MM] auto-start: WaitForCountdown entered mid-mission -> countdown flag set (wait_to_start_game=%s)",
        tostring(sc and sc.wait_to_start_game))
end)

-- Clean-transition divert (full wrapper). MatchmakingStateStartGame._start_game ends by
-- calling Managers.state.game_mode:complete_level() (matchmaking_state_start_game.lua:408);
-- mid-mission that would end the current round as a FAKE "won" (game_mode_adventure.lua:124-129).
-- When our auto-start armed recently (< 15s -- long enough to cover a short DLC/difficulty
-- vote round-trip, short enough not to swallow a much-later genuine completion), divert to
-- promote_next_level_data() instead: matchmaking already called set_next_level (:363), so
-- promote alone completes the mid-mission swap with NO win/loss -- exactly the vanilla
-- return-to-keep vote's mechanism (game_mode_manager.lua:678-692). Otherwise run vanilla.
mod:hook(GameModeManager, "complete_level", function(func, self, ...)
    local armed_t = mod._gut_mm_autostart_t
    if armed_t then
        local now = Managers.time and Managers.time:time("main") or nil
        if now and now - armed_t < 15 then
            mod._gut_mm_autostart_t = nil
            _pf("[gut_dev:MM] auto-start: diverting complete_level -> promote_next_level_data (no fake mission win)")
            Managers.level_transition_handler:promote_next_level_data()
            return
        end
        mod._gut_mm_autostart_t = nil  -- stale arm: expire and run vanilla
    end
    return func(self, ...)
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
    -- Backdrop tier report (#336). No availability gate any more: the def-swap hook
    -- guarantees a spawn-safe viewport def in every state (keep def / level-less
    -- transparent def), so the map opens unconditionally. The tier is only reported for
    -- triage -- "transparent" means the live mission shows through, not a failure.
    local keep_ok = _can_get_level(KEEP_MENU_LEVEL)
    local tier = (keep_ok == true) and "keep" or "transparent"
    _pf("[gut_dev:MM] backdrop tier: keep=%s -> %s", tostring(keep_ok), tier)
    _pf("[gut_dev:MM] gate=opened (mechanism=adventure host_only=%s is_host=%s tier=%s) -> start_game_view_force menu_state_name=play",
        tostring(host_only), tostring(is_host), tier)
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
