local mod = get_mod("gut_dev")

-- ============================================================================
-- Compendium HeroView injection — Phase 0
-- ============================================================================
-- Registers the HeroViewStateCompendium sub-state into HeroView's screen list
-- (so transition_with_fade("hero_view", { menu_state_name = "gut_compendium" })
-- routes to it), and captures the ingame_ui_context so /armory /bestiary
-- can open it from the keep. The top-tab button (HeroWindowOptions) is Phase 1 —
-- for now the chat commands are the entry point, which keeps Phase 0 off the
-- crash-sensitive tab-bar hooks.
--
-- Hook pairs used here: HeroView.init (distinct from gut's existing HeroView.on_enter
-- hook), StateInGameRunning.update (gut doesn't hook it elsewhere). Verified no
-- duplicate (Class, method) registrations.

-- Register the sub-state descriptors after HeroView builds its screen list.
-- TWO screens are appended in this SAME loop (do NOT add a second HeroView.init
-- hook — VMF silently drops duplicate (Class, method) registrations):
--   * gut_compendium    -> HeroViewStateCompendium   (Armory/Bestiary, Phase 0 stub)
--   * gut_mod_tweaker   -> HeroViewStateModTweaker    (Mod Tweaker KEEP sub-state,
--                          build 2 — replaces the leave/re-enter ModTweakerView path
--                          that produced the deprecated-menu look + the LA atlas
--                          renderer-recreation crash; see _mod_tweaker_state.lua).
local _GUT_HERO_SCREENS = {
    {
        name = "gut_compendium",
        state_name = "HeroViewStateCompendium",
        hotkey_disabled = true,
        draw_background_world = false,
        camera_position = { 0, 0, 0 },
        camera_rotation = { 0, 0, 0 },
        contains_new_content = function() return false end,
    },
    {
        name = "gut_mod_tweaker",
        state_name = "HeroViewStateModTweaker",
        hotkey_disabled = true,
        draw_background_world = false,
        camera_position = { 0, 0, 0 },
        camera_rotation = { 0, 0, 0 },
        contains_new_content = function() return false end,
    },
}

mod:hook_safe("HeroView", "init", function(self, ingame_ui_context)
    mod._gut_ingame_ui_context = ingame_ui_context
    local params = self._state_machine_params
    local list = params and params.settings_by_screen
    if type(list) ~= "table" then return end
    for _, descriptor in ipairs(_GUT_HERO_SCREENS) do
        local present = false
        for i = 1, #list do
            if list[i].name == descriptor.name then present = true; break end
        end
        if not present then
            list[#list + 1] = descriptor
            mod:info("[gut:heroview] registered %s screen (%s)", descriptor.name, descriptor.state_name)
        end
    end
end)

-- Capture ingame_ui_context while in-game so the command can open the hero view
-- from scratch (HeroView.init only fires once the view is already opening). Self-
-- disables after the first successful capture to avoid per-frame overhead.
mod:hook_safe("StateInGameRunning", "update", function(self)
    if not mod._gut_ingame_ui_context and self.ingame_ui_context then
        mod._gut_ingame_ui_context = self.ingame_ui_context
        pcall(function() mod:hook_disable("StateInGameRunning", "update") end)
    end
end)

-- Switch an ALREADY-OPEN hero_view to the Compendium sub-state via HeroView's OWN
-- internal screen-change mechanism (issue #223). This is the ONLY correct path from
-- inside hero_view: HeroView.update consumes _requested_screen_change_data next frame
-- -> _change_screen_by_name -> _wanted_state, and the running GameStateMachine swaps
-- HeroViewStateOverview -> HeroViewStateCompendium WITHOUT re-running HeroView.on_enter
-- (hero_view.lua:236-245, 470-490). Contrast with an IngameUI transition back to
-- "hero_view" + force_open, which re-runs HeroView.on_enter -> _setup_hdr_gui ->
-- create_world("hero_view_hdr") while the old world still exists -> engine fatal
-- 'World "hero_view_hdr" already exists' (the #223 crash; ingame_ui.lua:953 forces the
-- on_exit/on_enter block whenever force_open is set even if old_view == new_view).
-- The state machine passes its own state_machine_params (parent = HeroView,
-- ingame_ui_context) to the new state's on_enter (state_machine.lua:74-78), but no
-- per-transition params, so the mode is stashed on the mod for the state to read.
-- Returns true when the switch was requested. `hero_view` is the live HeroView instance
-- (reachable as the panel window's self.parent.parent, or ingame_ui.views.hero_view).
function mod._gut_switch_to_compendium_state(hero_view, mode)
    if not (hero_view and hero_view.requested_screen_change_by_name) then
        return false
    end
    mod._gut_pending_compendium_mode = mode or "armory"
    local ok = pcall(hero_view.requested_screen_change_by_name, hero_view, "gut_compendium")
    if ok then
        printf("[gut:217] hero_view internal state switch -> gut_compendium (mode=%s)", tostring(mode or "armory"))
        return true
    end
    printf("[gut:217] hero_view internal state switch FAILED (requested_screen_change_by_name raised)")
    return false
end

-- Open the Compendium hero-view screen. `mode` ("armory"/"bestiary") is passed as
-- a transition param (best-effort; the Phase-0 panel is identical either way).
function mod._gut_open_compendium(mode)
    local ctx = mod._gut_ingame_ui_context
    if not ctx then
        mod:echo("Hero menu isn't ready yet - open the keep first, then retry.")
        return
    end
    if ctx.is_in_inn == false then
        mod:echo("The Compendium only opens in the keep/inn.")
        return
    end
    local ingame_ui = ctx.ingame_ui
    if not (ingame_ui and ingame_ui.transition_with_fade) then
        mod:echo("Could not open the hero view (ingame_ui unavailable).")
        return
    end
    -- HARD GUARD (#223): if hero_view is ALREADY the current view, an
    -- IngameUI re-enter (transition_with_fade + force_open) fatals on the duplicate
    -- hero_view_hdr world. Route to the internal state switch instead; if that path is
    -- somehow unavailable, no-op rather than fall through to the crashing transition
    -- (a dead tab beats a dead game).
    if ingame_ui.current_view == "hero_view" then
        local hero_view = ingame_ui.views and ingame_ui.views.hero_view
        if not mod._gut_switch_to_compendium_state(hero_view, mode) then
            printf("[gut:217] blocked hero_view re-enter (already inside; state switch unavailable)")
        end
        return
    end
    -- From OUTSIDE hero_view (e.g. /armory typed while walking the keep): the fresh
    -- open needs force_open so the sub-state applies. IngameUI.handle_transition only
    -- runs post_update_on_enter (the sole consumer of menu_state_name) when
    -- old_view ~= new_view OR force_open (ingame_ui.lua:953). Here old_view is not
    -- hero_view, so this is safe (no duplicate-world re-enter). Mirrors the vanilla
    -- keep-button flow (ingame_view_menu_layout_console.lua:742-745).
    ingame_ui:transition_with_fade("hero_view", {
        menu_state_name = "gut_compendium",
        gut_compendium_mode = mode or "armory",
        force_open = true,
    })
end

-- Open the Mod Tweaker as a HeroView SUB-STATE (KEEP path). Mirrors
-- _gut_open_compendium: routes through transition_with_fade("hero_view", {
-- menu_state_name = "gut_mod_tweaker" }) so it stays INSIDE the already-open
-- hero_view and never recreates the renderer. The in-mission path is the standalone
-- ModTweakerView (gut hooks IngameViewLayoutLogic.setup_button_layout + the
-- mod_tweaker_view transition for that), which this does NOT touch.
function mod._gut_open_mod_tweaker()
    local ctx = mod._gut_ingame_ui_context
    if not ctx then
        mod:echo("Hero menu isn't ready yet - open the keep first, then retry.")
        return
    end
    if ctx.is_in_inn == false then
        mod:echo("The Mod Tweaker hero-menu screen only opens in the keep/inn (use the ESC menu in a mission).")
        return
    end
    local ingame_ui = ctx.ingame_ui
    if ingame_ui and ingame_ui.transition_with_fade then
        ingame_ui:transition_with_fade("hero_view", {
            menu_state_name = "gut_mod_tweaker",
            -- force_open = true is LOAD-BEARING when hero_view is ALREADY the active view
            -- (the keep ESC menu IS hero_view). IngameUI.handle_transition only re-enters
            -- the view — and thus only runs post_update_on_enter, the ONLY consumer of
            -- menu_state_name — when `old_view ~= new_view or force_open`
            -- (ingame_ui.lua:953). Same mechanism + the same fix the ESC closure in
            -- gui_tweaker.lua uses; mirrors the vanilla keep-button flow
            -- (ingame_view_menu_layout_console.lua:742-745).
            force_open = true,
        })
    else
        mod:echo("Could not open the hero view (ingame_ui unavailable).")
    end
end

-- Chat opener mirroring /armory. Lets the user open the Mod Tweaker sub-state
-- from the keep without the ESC menu (useful for testing the no-deprecated-look /
-- no-LA-crash path directly).
mod:command("mod_tweaker", "Open the Mod Tweaker (hero-menu sub-state, keep only)", function()
    if mod._gut_open_mod_tweaker then mod._gut_open_mod_tweaker()
    else mod:echo("Mod Tweaker sub-state not ready (inject module didn't load).") end
end)

return {}
