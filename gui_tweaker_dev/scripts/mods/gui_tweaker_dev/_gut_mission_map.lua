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
-- BACKDROP (three tiers, #336 v0.2.206 rework). The v0.2.198 "transparent" tier turned
-- out NOT to be transparent in practice: with no world spawned by this window, nothing
-- clears the framebuffer behind the flat UI each frame, so both testers saw a SOLID BLACK
-- plate and the animated menu-button glow smeared permanent trails ("bleeding" -- additive
-- glow accumulating on stale pixels). User direction: give the map the proper menu
-- backdrop like the keep's. The literal keep menu level (levels/ui_keep_menu/world) ships
-- only inside the keep's level packages (level_settings.lua:72-73 inn packages) with no
-- standalone package, so mid-mission we mount the PROVEN in-repo substitute instead: the
-- small managed package `resource_packages/levels/ui_inventory_preview` and its level
-- `levels/ui_inventory_preview/world` + shading env `environment/ui_inventory_preview`
-- (the pairing vanilla uses at hero_window_character_preview_definitions.lua:225-227) --
-- the exact mechanic _gut_mission_hero_select.lua has already proven mission-safe. The
-- package async-loads under our OWN ref (MM_PKG_REF; distinct from hero-select's
-- "gut_hero_select" ref -- PackageManager.load on an already-loaded package just bumps the
-- refcount and fires the callback synchronously, package_manager.lua:26-27,56-58) when
-- the feature arms (StateIngame enter with the toggle on, re-kicked on open), and is
-- retained for the session (same rationale as hero-select's PACKAGE RETENTION note).
--   (1) keep backdrop resident, or state unknown (keep-only flows) -> vanilla def, no swap.
--   (2) keep NOT resident + preview package has_loaded (normal mid-mission case) -> the
--       vanilla-shaped def with level_name = levels/ui_inventory_preview/world, its own
--       LevelResource.object_set_names, shading env environment/ui_inventory_preview.
--       post_update runs VANILLA (widget + MenuWorldPreviewer world DO spawn): a real,
--       framebuffer-clearing menu stage renders behind the map UI (fixes black + bleed).
--   (3) keep NOT resident + preview package NOT loaded yet (first-open race / load
--       failure) -> the v0.2.198 level-less fallback for THAT open (no level_name key,
--       empty object_sets, post_update skipped so nothing spawns; black once, never a
--       crash), and the package load is (re-)kicked so the next open gets tier 2.
-- Every StartGameWindowBackgroundConsole consumer of the viewport / world_previewer is
-- nil-guarded in vanilla (update :147 world_previewer, draw :227 viewport, on_exit
-- :130-140 both), so a post_update that never creates them renders NOTHING from this
-- window. The loading plate still fades out: the skipping post_update sets
-- _fadeout_loading_overlay and runs _update_loading_overlay_fadeout_animation
-- (:236-261) so the overlay does not stay up. The fallback def has a nil level_name,
-- which vanilla _setup_object_sets (:112-123) would call LevelResource.object_set_names(nil)
-- on and raise -- the _setup_object_sets divert below short-circuits that. On tier 2 the
-- def's level_name IS resident, so _setup_object_sets runs vanilla safely; the
-- _update_object_sets scenery pass (keep-only object sets + "quick_play"/... flow events,
-- which don't exist on the preview stage) is diverted on BOTH swapped tiers.
--
-- AREA-VIDEO CRASH GUARD (#336 CRASH, 0-critical). With the map open mid-mission,
-- navigating to the area-selection screen hard-crashed: the console window builds a video
-- widget for the hovered area's preview video (material_name from
-- AreaSettings[area].video_settings, start_game_window_area_selection_console_v2.lua:362-370
-- -> _assign_video_player :647-670) and draws it on ui_top_renderer (:628-638) -> Gui.video
-- raises "Material 'area_video_bogenhafen' not found in Gui" (shipped ui_renderer.lua:1345;
-- user crash console-2026-07-06-03.24.08 at 03:28:50, reproduced by RainReligion). Root
-- cause: vanilla appends the AreaSettings video materials to the ingame ui/ui_top renderer
-- material lists ONLY in the keep (ingame_ui_settings.lua:594-601 / :681-688 `if is_in_inn`).
-- Layer 1 (_gut_gui_material_guard.lua) injects those materials into ingame renderers when
-- resident and publishes the per-material outcome in mod._gut_area_videos_ingame. Layer 2
-- (here): full-wrapper hooks on BOTH area-selection windows' video-widget builders
-- (StartGameWindowAreaSelectionConsoleV2._assign_video_player -- the console layout the
-- mid-mission map uses per start_game_window_layout_console.lua:54-58 and the user log --
-- and StartGameWindowAreaSelection._setup_video_player :458-476, the PC layout, same crash
-- class) that SKIP the video widget when its material is not in the Gui. Guard-not-bail:
-- both vanilla builders only create the video widget/player; skipping leaves _video_widget
-- nil, which every consumer nil-guards (v2 draw :629 + _destroy_video_widget :675; PC
-- draw_video :440 + _destroy_video_player :482/:488), so the static area image stays and
-- nothing else changes. Note the parent state's _create_video_players
-- (start_game_state_settings_overview.lua:246-263, at state enter :212) runs
-- World.create_video_player on every AreaSettings video resource and did NOT crash in
-- either user log mid-mission -- creation is safe; only the Gui DRAW of an unlisted
-- material is fatal, which is exactly what these two hooks pre-filter.
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
-- _update_object_sets, _setup_object_sets, post_update), TWO on the area-selection
-- windows (StartGameWindowAreaSelectionConsoleV2._assign_video_player,
-- StartGameWindowAreaSelection._setup_video_player -- the #336 crash guards), plus one
-- hook_safe on MatchmakingStateWaitForCountdown.on_enter (auto-start arm) and one full
-- hook on GameModeManager.complete_level (clean-transition divert). It also chains
-- mod.on_game_state_changed (preview-package arm; dofile'd after the main chunk defines
-- it). HOOK PRE-FLIGHT (grep 2026-07-05, re-run 2026-07-06 for the area windows): gut_dev
-- registers no other hook on StartGameWindowBackgroundConsole, none on
-- StartGameWindowAreaSelectionConsoleV2 / StartGameWindowAreaSelection (every other repo
-- hit is a comment or CHANGELOG line), none on MatchmakingStateWaitForCountdown, and on
-- GameModeManager only .has_activated_mutator (hb/hide_elements.lua -- a different
-- method, no collision).

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
local PREVIEW_PKG   = "resource_packages/levels/ui_inventory_preview"  -- managed package (mission-loadable)
local PREVIEW_LEVEL = "levels/ui_inventory_preview/world"   -- proven mission-safe menu stage (hero-select precedent)
local PREVIEW_ENV   = "environment/ui_inventory_preview"    -- its paired shading env (hero_window_character_preview_definitions.lua:227)
local MM_PKG_REF    = "gut_mission_map"                     -- OUR PackageManager ref (distinct from hero-select's "gut_hero_select")

-- Idempotent async kick of the preview-stage package load under OUR ref. Retained for
-- the session once loaded (mirrors _gut_mission_hero_select's PACKAGE RETENTION: unload
-- interleaves badly with HeroView's own load/unload cycle on the same package, and the
-- keep pins it constantly anyway). Re-entrant-safe: no-ops when already loaded (our ref)
-- or already in flight. If someone else's ref holds the package, load() just bumps our
-- refcount and fires the callback synchronously (package_manager.lua:26-27,56-58).
local _mm_pkg_load_in_flight = false
local function _kick_preview_pkg_load(ctx)
    local pm = Managers.package
    if not (pm and pm.load and pm.has_loaded) then return end
    if pm:has_loaded(PREVIEW_PKG, MM_PKG_REF) then return end
    if _mm_pkg_load_in_flight or (pm.is_loading and pm:is_loading(PREVIEW_PKG, MM_PKG_REF)) then return end
    _mm_pkg_load_in_flight = true
    _pf("[gut_dev:MM] preview backdrop package load START: %s (ref=%s ctx=%s)", PREVIEW_PKG, MM_PKG_REF, tostring(ctx))
    local ok, err = pcall(pm.load, pm, PREVIEW_PKG, MM_PKG_REF, function()
        _mm_pkg_load_in_flight = false
        _pf("[gut_dev:MM] preview backdrop package load COMPLETE: %s (ref=%s) -> next map open uses the preview stage", PREVIEW_PKG, MM_PKG_REF)
    end, true)
    if not ok then
        _mm_pkg_load_in_flight = false
        _pf("[gut_dev:MM] preview backdrop package load FAILED: %s (map falls back to the level-less backdrop)", tostring(err))
    end
end

-- Arm the preview package as soon as a play state starts with the feature enabled, so the
-- FIRST mid-mission map open already has the stage resident (the open itself re-kicks as
-- a fallback for toggle-flipped-mid-mission). Chained, never overwritten: the main chunk
-- defines mod.on_game_state_changed long before this module dofile's.
local _mm_prev_on_game_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name)
    if _mm_prev_on_game_state_changed then _mm_prev_on_game_state_changed(status, state_name) end
    if status == "enter" and state_name == "StateIngame" and mod:get("gut_mission_map") then
        _kick_preview_pkg_load("StateIngame enter")
    end
end

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

-- Swap hook (three tiers, #336 v0.2.206). Tier 1: keep path (ui_keep_menu resident, or
-- state unknown = keep-only flows) is byte-for-byte vanilla. Tier 2 (preview; the normal
-- mid-mission case once the package is in): keep NOT resident + preview package loaded
-- under OUR ref -> the vanilla-shaped def pointed at the inventory-preview stage. Only the
-- swapped marker is set (diverts the keep-only _update_object_sets scenery pass); the none
-- marker stays nil so post_update runs VANILLA and actually spawns the widget + world --
-- a real menu backdrop that clears the framebuffer every frame (fixes the v0.2.198 black
-- plate + button-glow bleeding: with no world, nothing erased stale pixels and the
-- additive glow accumulated). Tier 3 (level-less fallback; first-open race or load
-- failure): the v0.2.198 def with NO level_name key and empty object sets, BOTH markers
-- set, post_update skipped -- black once, never a crash -- and the package load re-kicked
-- for the next open. Full wrapper (not hook_safe): the vanilla body dereferences a keep
-- level that may not be resident, so flow must DIVERT. Markers are explicitly cleared on
-- tier 1 (and the none marker on tier 2) in case a window instance is re-entered.
mod:hook("StartGameWindowBackgroundConsole", "_create_viewport_definition", function(func, self, ...)
    -- Tier 1: keep backdrop resident, or state unknown -> vanilla def, no swap.
    if _can_get_level(KEEP_MENU_LEVEL) ~= false then
        self._gut_mm_swapped_backdrop = nil
        self._gut_mm_none_backdrop    = nil
        return func(self, ...)
    end
    -- Tier 2 (preview stage): keep not resident, preview package resident under OUR ref
    -- (has_loaded is reference-scoped, package_manager.lua:286-294) -> mount the proven
    -- mission-safe inventory-preview stage. The v0.2.190 lesson holds: gate on the PACKAGE
    -- (has_loaded), not can_get("level", ...) -- the level only becomes gettable once the
    -- managed package is loaded, which is exactly what hero-select proved in missions.
    local pm = Managers.package
    if pm and pm.has_loaded and pm:has_loaded(PREVIEW_PKG, MM_PKG_REF) then
        local ok_sets, object_sets = pcall(LevelResource.object_set_names, PREVIEW_LEVEL)
        if not ok_sets or type(object_sets) ~= "table" then
            object_sets = {}
        end
        self._gut_mm_swapped_backdrop = true   -- divert the keep-only object-set/flow-event pass
        self._gut_mm_none_backdrop    = nil    -- post_update runs vanilla: widget + world DO spawn
        _pf("[gut_dev:MM] backdrop def-swap PREVIEW: %s not resident -> %s (env=%s object_sets=%d)",
            KEEP_MENU_LEVEL, PREVIEW_LEVEL, PREVIEW_ENV, #object_sets)
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
                    shading_environment = PREVIEW_ENV,
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
    end
    -- Tier 3 (level-less fallback): keep not resident AND the preview package is not in
    -- yet (first-open race / load failure). Both markers set: swapped marker drives
    -- _update_object_sets; none marker drives _setup_object_sets and post_update (no
    -- world spawns). Re-kick the load so the NEXT open lands on tier 2.
    self._gut_mm_swapped_backdrop = true
    self._gut_mm_none_backdrop    = true
    _kick_preview_pkg_load("levelless fallback open")
    _pf("[gut_dev:MM] backdrop def-swap LEVELLESS-FALLBACK: %s not resident, %s not loaded yet -> no world this open (preview stage next open)",
        KEEP_MENU_LEVEL, PREVIEW_PKG)
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
-- Neither exists on either swapped tier: the preview stage (tier 2) is a different level
-- with none of the keep's object sets or flow events, and the level-less fallback
-- (tier 3) has no world_previewer at all (post_update skips its creation);
-- MenuWorldPreviewer.trigger_level_flow_event is a bare Level.trigger_event
-- (menu_world_previewer.lua:769-770) -- an engine-assert risk on a missing event. The
-- whole pass is backdrop scenery, so on a swapped instance divert it entirely; native
-- (keep) instances run vanilla untouched.
mod:hook("StartGameWindowBackgroundConsole", "_update_object_sets", function(func, self, ...)
    if not self._gut_mm_swapped_backdrop then
        return func(self, ...)
    end
    _pf("[gut_dev:MM] _update_object_sets diverted (swapped backdrop: keep-only object sets/flow events)")
end)

-- Object-set setup hook (#336 level-less fallback tier). Vanilla _setup_object_sets reads
-- self._viewport_widget_definition.style.viewport.level_name and calls
-- LevelResource.object_set_names(level_name) (start_game_window_background_console.lua:112-123).
-- On a fallback instance that level_name is nil (tier 3 omits the key), and
-- object_set_names(nil) raises. Short-circuit to an empty object-set map on the none
-- instance (or any nil-level def); keep (tier 1) AND preview (tier 2) instances carry a
-- RESIDENT level_name and run vanilla untouched. Full wrapper: the vanilla body raises
-- before returning.
mod:hook("StartGameWindowBackgroundConsole", "_setup_object_sets", function(func, self, ...)
    local vp_def = self._viewport_widget_definition
    local level_name = vp_def and vp_def.style and vp_def.style.viewport and vp_def.style.viewport.level_name
    if self._gut_mm_none_backdrop or level_name == nil then
        self._object_sets = {}
        _pf("[gut_dev:MM] _setup_object_sets diverted (level-less fallback backdrop: nil level_name -> empty object sets)")
        return
    end
    return func(self, ...)
end)

-- Level-less-fallback hook (#336, tier 3 only -- tier 2 preview instances run vanilla
-- here and DO spawn their world). On a none-backdrop instance vanilla post_update would
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
-- AREA-VIDEO CRASH GUARD (#336 CRASH). See the AREA-VIDEO docstring above.
-- ---------------------------------------------------------------

-- Is this area's preview video drawable in the CURRENT ingame Gui? Primary signal: the
-- per-material outcome _gut_gui_material_guard.lua published at ingame-renderer create
-- (true = vanilla listed it in the keep, or our injection landed; false = not resident at
-- renderer create, so it is NOT in the Gui and drawing it is the ui_renderer.lua:1345
-- fatal). Fallback when the signal is missing (guard passive because can_get was
-- untrustworthy, or an unknown DLC area): only the keep is safe -- vanilla puts area
-- videos in the Gui only when is_in_inn (ingame_ui_settings.lua:594-601/:681-688).
local function _area_video_drawable(material_name)
    local flags = mod._gut_area_videos_ingame
    if type(flags) == "table" and flags[material_name] ~= nil then
        return flags[material_name] and true or false
    end
    local gm  = Managers.state and Managers.state.game_mode
    local lvl = (gm and gm.level_key) and gm:level_key() or nil
    local dui = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    return (lvl == "inn_level") or dui or false
end

-- Console-layout window (the one the mid-mission map uses; user crash log shows
-- "Enter Substate StartGameWindowAreaSelectionConsoleV2"). Vanilla _assign_video_player
-- ONLY builds the video widget + registers the player on the ui_top world
-- (start_game_window_area_selection_console_v2.lua:647-670); skipping leaves
-- self._video_widget nil, which draw (:629) and _destroy_video_widget (:675) both
-- nil-guard, so the static area image stays and exit stays clean. Guard-not-bail
-- satisfied: no vanilla state mutation is lost besides the widget we must not create.
mod:hook("StartGameWindowAreaSelectionConsoleV2", "_assign_video_player", function(func, self, material_name, video_player)
    if _area_video_drawable(material_name) then
        return func(self, material_name, video_player)
    end
    _pf("[gut_dev:MM] area video '%s' is not in the ingame Gui -> video widget skipped (static area image kept; prevented ui_renderer draw fatal)",
        tostring(material_name))
end)

-- PC-layout sibling (start_game_window_layout.lua maps area_selection to
-- StartGameWindowAreaSelection): same crash class at the same draw funnel
-- (_setup_video_player :458-476 builds the widget, draw_video :432-452 draws it on the
-- ingame ui_renderer). Skipping leaves _video_widget nil and the VIDEO_REFERENCE_NAME
-- player uncreated; _destroy_video_player nil-guards both (:482 widget, :488 player).
mod:hook("StartGameWindowAreaSelection", "_setup_video_player", function(func, self, material_name, resource)
    if _area_video_drawable(material_name) then
        return func(self, material_name, resource)
    end
    _pf("[gut_dev:MM] area video '%s' (PC layout) is not in the ingame Gui -> video player skipped (static area image kept; prevented ui_renderer draw fatal)",
        tostring(material_name))
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
    -- Backdrop arm + tier report (#336). The kick is idempotent and, when the package is
    -- already resident under ANY ref, completes synchronously -- so a toggle flipped ON
    -- mid-mission still gets the preview stage on this very open whenever possible. No
    -- availability gate: the def-swap hook guarantees a spawn-safe viewport def in every
    -- state (keep def / preview def / level-less fallback), so the map opens
    -- unconditionally; the tier is only reported for triage ("levelless-fallback" =
    -- black backdrop once while the package streams in, not a failure).
    _kick_preview_pkg_load("map open")
    local keep_ok = _can_get_level(KEEP_MENU_LEVEL)
    local pm = Managers.package
    local preview_loaded = (pm and pm.has_loaded and pm:has_loaded(PREVIEW_PKG, MM_PKG_REF)) and true or false
    local tier = (keep_ok == true) and "keep" or (preview_loaded and "preview" or "levelless-fallback")
    _pf("[gut_dev:MM] backdrop tier: keep=%s preview_loaded=%s -> %s", tostring(keep_ok), tostring(preview_loaded), tier)
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
