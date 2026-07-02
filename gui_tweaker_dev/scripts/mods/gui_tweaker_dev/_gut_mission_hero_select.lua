local mod = get_mod("gut_dev")

-- _gut_mission_hero_select.lua — in-mission HERO SELECT access.
--
-- Sibling of _gut_mission_inventory.lua; mirrors its structure exactly. Where the
-- inventory module opens the HeroView EQUIPMENT layout mid-mission, this one opens
-- the HeroView TALENTS layout — the live-safe "manage your current hero/career"
-- surface (talents + active-ability passives + the career's cosmetics tab via the
-- tab strip). Created 2026-06-24.
--
-- ============================================================================
-- WHY THIS OPENS HeroView "talents", NOT the standalone CharacterSelectionView
-- ============================================================================
-- There are TWO separate top-level views in vanilla (source-confirmed):
--   * CharacterSelectionView — the career/hero PICK grid (the "C" key screen).
--   * HeroView — inventory / loadout / TALENTS / cosmetics (one view, swaps named
--     window-layouts inside HeroViewStateOverview).
--
-- A mid-mission career CHANGE is NOT SAFE, on two independent axes, so this feature
-- is scoped to VIEW + the live-safe TALENTS/cosmetics surface only (no live career
-- swap). The deferred-to-keep limit is documented in the tooltip + CHANGELOG.
--
-- (1) Career is bound at unit-spawn and has no live setter.
--     CareerExtension.init reads career_index from extension_init_data and builds
--     the abilities/talents at unit construction (career_extension.lua:9-41);
--     career_index() (:806) is a getter only. To change career you must DESTROY
--     and RECREATE the player unit. The ONLY swap path the engine exposes goes
--     through force_respawn = true:
--       - CharacterSelectionStateCharacter._change_profile hardcodes
--         force_respawn = true (character_selection_state_character.lua:1602-1615);
--         the "Select" button always routes here when profile/career differs.
--       - ProfileRequester._request_profile calls
--         Managers.state.game_mode:force_respawn(...) (profile_requester.lua:92),
--         despawning the live unit before set_career_index.
--     In a real mission force_respawn lands the player on the LEVEL START spawn
--     point, not their current position (GameModeAdventure.force_respawn ->
--     AdventureSpawning, _find_spawn_point falls back to data.position — the level's
--     fixed start — because there's no room_manager mid-mission). A mid-mission
--     career swap would yank the player back to the level start with fresh
--     health/ammo, and desync the career game-object id / party profile across peers
--     if forced locally. So career CHANGE is keep/inn-only by engine design.
--
-- (2) CharacterSelectionView mounts a KEEP-ONLY preview WORLD unconditionally.
--     CharacterSelectionView.post_update_on_enter ALWAYS builds the viewport widget
--     (character_selection_view.lua:522), whose style references
--     level_name = "levels/ui_character_selection/world"
--     (character_selection_view_definitions.lua:385). The UIWidget viewport pass
--     loads that level via the same engine path that fatals AT MOUNT mid-mission for
--     other keep-only preview worlds (the cog/Customize "ui_store_preview/world"
--     crash already guarded in _gut_mission_inventory.lua, GUID ef637399). It is NOT
--     gated on is_in_inn, so there's no clean force path that skips the load. This is
--     the same C-level resource-load fatal class that bypasses pcall.
--
-- Conclusion (matches the safety investigation): open HeroView's TALENTS layout
-- instead. It reuses the EXACT same vanilla `hero_view_force` transition the
-- inventory feature already uses (just a different menu_sub_state_name), which the
-- inventory feature has already proven crash-safe mid-mission; talent changes apply
-- to the LIVE character immediately (no respawn); and the user can tab to Cosmetics
-- from there via the in-mission tab strip (gut_mission_menu_tabs). True career-PICK
-- is left to the keep, exactly as vanilla intends.
--
-- ============================================================================
-- HOOK PRE-FLIGHT (VMF no-duplicate-hook rule)
-- ============================================================================
-- This module registers NO hooks at all. The open path drives
-- Managers.ui:handle_transition("hero_view_force", ...) directly (no hook), and the
-- InventorySettings game-mode patch it relies on is ALREADY owned by
-- _gut_mission_inventory.lua's mod._gut_apply_keep_menus (pure data mutation, no
-- hook). Whole-mod grep for "CharacterSelection" returns only a comment, and for
-- HeroView there is exactly one hook (HeroView.on_enter, loc registration) which we
-- do NOT touch. So there are zero new (Class, method) pairs here — nothing to
-- collide with.
--
-- EXIT handling: 100% vanilla and free. `hero_view_force` sets
-- self.views.hero_view.exit_to_game = true (ingame_ui_settings.lua:441-444), so on
-- ESC/back HeroView routes straight back to the mission via the vanilla
-- exit_menu/exit_to_game path (hero_view.lua:576-590) — NO custom exit closure, and
-- crucially NO hardcoded transition_with_fade("ingame_menu") (which would dump the
-- player into the deprecated bare IngameView — the gut v0.2.46 bug). Because we
-- reuse the vanilla transition verbatim, IngameUI's own current_view origin tracking
-- handles the exit; we never construct a custom view that would need a hand-rolled
-- origin capture.
--
-- DISPATCH WIRING (mirrors the inventory feature):
--   * mod.gut_open_mission_hero_select is a PUBLIC `mod.` field, so the VMF keybind
--     `function_name = "gut_open_mission_hero_select"` resolves it at invoke time,
--     and the /hero_select command (registered below) calls it directly.
--   * The InventorySettings loadout-access patch is shared with the inventory
--     feature (mod._gut_apply_keep_menus); we just force-flip the same flags inline
--     for the current call so the HeroView panels init even if neither toggle is on
--     (idempotent — same pattern as gut_open_mission_inventory).
--
-- Module dofile's from gui_tweaker_dev.lua AFTER the main chunk (next to the
-- inventory dofile), so any view globals are resolvable at load time.

-- ============================================================
-- Open Hero Select In Mission (direct transition -> HeroView "talents")
-- ============================================================
mod.gut_open_mission_hero_select = function()
    if not (Managers.ui and Managers.ui.handle_transition) then
        mod:echo("UI manager not available (not in-game?).")
        return
    end
    -- (#173) IN-MISSION ONLY — the keep already has a native hero-select keybind. ROBUST keep
    -- detection: primary = level_key == "inn_level" (the keep level; this is what gut's cutscene
    -- code uses reliably), backup = DamageUtils.is_in_inn. printf so the next log shows EXACTLY
    -- the context this keybind fired in (was guessing whether is_in_inn was the problem).
    local gm  = Managers.state and Managers.state.game_mode
    local lvl = (gm and gm.level_key) and gm:level_key() or nil
    local dui = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    local in_keep = (lvl == "inn_level") or dui or false
    local _pf = rawget(_G, "printf")
    if _pf then _pf("[gut:heroselect] keybind fired -> in_keep=%s level_key=%s is_in_inn=%s (bail=%s)",
        tostring(in_keep), tostring(lvl), tostring(dui), tostring(in_keep)) end
    if in_keep then
        return  -- in the keep: do nothing; the native keep keybind handles hero select
    end
    -- ADVENTURE-EXCLUSIVE (same directive as the inventory feature): block the whole
    -- Chaos Wastes run -- hub AND mission. CW is loadout-locked via the deus boon
    -- system, so opening the hero/loadout flow crashes. Covers the /hero_select
    -- command + the gut_open_hero_select_hotkey keybind (both route here).
    local mech = Managers.mechanism and Managers.mechanism:current_mechanism_name()
    if mech == "deus" then
        mod:echo("In-mission hero select is disabled in Chaos Wastes -- it crashes (CW is loadout-locked). Adventure only.")
        return
    end
    -- The HeroView talents/cosmetics panels depend on the same
    -- loadout_access_supported_game_modes patch the inventory feature uses. If the
    -- user hasn't enabled either persistent toggle, force-flip the relevant
    -- game-mode flags for the current call so the panels init correctly. Idempotent.
    -- (deus stays nil -- blocked above and crash-prone.)
    if InventorySettings then
        local modes = InventorySettings.inventory_loadout_access_supported_game_modes
        if modes then
            modes.adventure = true
            modes.survival  = true
            modes.deus      = nil
        end
    end
    -- Open HeroView on the TALENTS layout. Same vanilla `hero_view_force` transition
    -- as the inventory feature (exit_to_game = true -> free exit-to-mission), only
    -- the sub-state differs. Talent changes apply to the live character immediately;
    -- no respawn, no keep-only world. pcall-guarded per the brief.
    local ok, err = pcall(function()
        Managers.ui:handle_transition("hero_view_force", {
            menu_state_name     = "overview",
            menu_sub_state_name = "talents",
            use_fade            = true,
        })
    end)
    if not ok then
        mod:echo("Could not open hero select: " .. tostring(err))
    end
end

mod:command("hero_select", "Open the hero/talents screen mid-mission (HeroView talents layout; live-safe -- talents apply immediately, no respawn). Career PICK stays keep-only by design.", function()
    mod.gut_open_mission_hero_select()
end)
