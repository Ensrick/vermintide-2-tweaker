local mod = get_mod("gut")

-- Dual-version cim detection: stable gut must work whether the user runs stable cim
-- or the dev sibling cim_dev. Both provide the same mission-safe customize backend.
local function _has_cim() return get_mod("cim") or get_mod("cim_dev") end

-- _gut_mission_inventory.lua — in-mission hero-view access.
--
-- MIGRATED from general_tweaker (gt) 2026-06-24: this feature moved out of gt and
-- into gut, which now owns the in-mission inventory. Folds gt's two source files
-- (_gt_mission_ui.lua + _gt_keep_menus.lua) into one module — they were always a
-- single user-facing feature. All gt_dev namespacing re-pointed to gut_dev; chat
-- command /gt_inv -> /gut_inv; mod field mod.gt_open_mission_inventory ->
-- mod.gut_open_mission_inventory; setting ids all-gut_-prefixed.
--
-- Bundles the four "open the keep menus mid-mission" pieces. None of them share a
-- (Class, method) hook with any other gut section (verified by whole-mod grep
-- before migration — gut has zero pre-existing hooks on HeroWindowLoadoutConsole
-- or HeroWindowPanelConsole; its only on_enter hooks are HeroView/IngameView/
-- OptionsView/StateInGameRunning):
--
--   (1) Open Inventory In Mission — mod.gut_open_mission_inventory (no hook;
--       drives Managers.ui:handle_transition("hero_view_force") directly). The
--       /gut_inv command + the gut_open_inv_hotkey VMF keybind both route here.
--   (2) Mission Customize gear-icon cim-presence gate —
--       mod:hook("HeroWindowLoadoutConsole", "_customize_item") (singleton).
--   (3) Show menu tabs in-mission (console tab strip) —
--       mod:hook_safe("HeroWindowPanelConsole", "on_enter") (singleton).
--   (4) Keep Menus data patch — mod._gut_apply_keep_menus (InventorySettings
--       loadout-access patch + ESC-menu "Open Inventory" entry). NO hook (pure
--       data-table mutation).
--
-- DISPATCH WIRING:
--   * mod.gut_open_mission_inventory is a PUBLIC `mod.` field, so:
--       - the VMF keybind `function_name = "gut_open_mission_inventory"` resolves
--         it at invoke time,
--       - the /gut_inv command (registered below) calls it directly.
--   * mod._gut_apply_keep_menus is called by the on_setting_changed branch
--     (gut_mission_inventory_enabled) + the on_game_state_changed dispatcher in
--     gui_tweaker_dev.lua, plus once at this module's own load.
--
-- Module dofile's from gui_tweaker_dev.lua AFTER the main chunk, so the
-- HeroWindow* global classes are resolvable at load time.

-- ============================================================
-- Open Inventory In Mission (direct transition)
-- ============================================================
-- Vanilla's keep-bound menu hotkeys don't fire mid-mission — its
-- can_interact/transition_not_allowed gates inside handle_menu_hotkeys slam the
-- door (matchmaking state, voting-in-progress, view-not-ready checks, etc.) even
-- if the outer hotkeys-enabled guard is bypassed.
--
-- Janoti's `Open Inventory In Game` mod skips that whole subsystem and calls
-- `Managers.ui:handle_transition("hero_view_force", {...})` directly, which is the
-- same call vanilla makes from the ESC menu's Open Inventory entry. This bypasses
-- every hotkey gate because we're not pretending to be a hotkey press — we're
-- driving the transition ourselves.
--
-- `gut_mission_inventory_enabled` still toggles the
-- InventorySettings.inventory_loadout_access_supported_game_modes patch and the
-- ESC-menu entry (both load-bearing for the inventory view to actually function
-- once opened); the keybind/command below is the actual "open now" trigger.

mod.gut_open_mission_inventory = function()
    if not (Managers.ui and Managers.ui.handle_transition) then
        mod:echo("UI manager not available (not in-game?).")
        return
    end
    -- ADVENTURE-EXCLUSIVE (user directive 2026-06-18): block in-mission inventory in
    -- the WHOLE Chaos Wastes run -- hub AND mission. CW is loadout-locked via the
    -- deus boon system, so opening the loadout/customize flow crashes. Covers the
    -- /gut_inv command + the gut_open_inv_hotkey keybind (both route here).
    local mech = Managers.mechanism and Managers.mechanism:current_mechanism_name()
    if mech == "deus" then
        mod:echo("In-mission inventory is disabled in Chaos Wastes -- it crashes (CW is loadout-locked). Adventure only.")
        return
    end
    -- Inventory view depends on the loadout_access_supported_game_modes patch.
    -- If the user hasn't enabled `gut_mission_inventory_enabled`, force-flip the
    -- relevant game-mode flags for the current call so the loadout panel inits
    -- correctly. The patch is idempotent. (deus stays nil -- blocked above.)
    if InventorySettings then
        local modes = InventorySettings.inventory_loadout_access_supported_game_modes
        if modes then
            modes.adventure = true
            modes.survival  = true
            modes.deus      = nil
        end
    end
    Managers.ui:handle_transition("hero_view_force", {
        menu_state_name     = "overview",
        menu_sub_state_name = "equipment",
        use_fade            = true,
    })
end

mod:command("gut_inv", "Open the inventory mid-mission (uses the same transition vanilla fires from the ESC-menu 'Open Inventory' entry)", function()
    mod.gut_open_mission_inventory()
end)

-- ============================================================
-- Mission Customize gear-icon: cim presence gate (crash-hide, #87)
-- ============================================================
-- The gear/cog icon on the loadout panel routes to HeroWindowItemCustomization
-- (illusion swap + reroll properties / traits — the crafting screen). Vanilla's
-- preview viewport hard-loads `levels/ui_store_preview/world`, which is only in the
-- keep's package set; mid-mission the view fatals AT MOUNT (_create_ui_elements ->
-- _register_object_sets -> LevelResource.object_set_names), BEFORE any tab/state is
-- chosen. Crash GUID ef637399-8862-46dc-b7fb-8c6f9c475cf4 (2026-05-24, dlc_dwarf_interior).
--
-- ONLY crafting_in_modded (cim) ships the mount-time fix (its
-- _create_item_preview_widget_definition + _register_object_sets hooks strip the level
-- reference mid-mission so the screen mounts cleanly). cosmetics_tweaker does NOT ship
-- that fix (verified 2026-06-24) — it only hooks the view for illusion/glow rendering in
-- the KEEP — so cosmetics_tweaker is NOT a mission-safe backend. (#87 decision B:
-- cim-only for now; a follow-up issue tracks porting the mount-fix into
-- cosmetics_tweaker, after which the cosmetics-only tab-hide can be added.)
--
-- #87 gating (in-mission, no cim):
--   * The cog CLICK is killed at the source by the two query-method hooks below
--     (_is_customize_item_pressed -> nil, _is_selected_item_customizable -> false), so
--     neither the mouse path (_handle_input:266) nor the gamepad/refresh path
--     (_on_window_input:239) can reach _customize_item. The cog reads as INERT.
--   * This _customize_item hook stays as the final belt-and-suspenders guard: even if
--     some other path reached it, it no-ops mid-mission without cim.
-- NOTE: the cog ICON still DRAWS (its visibility is per-slot widget passes baked at
-- definition-build time with no clean per-instance hide; a true pixel-hide would be
-- fragile per-pass surgery — #87 decision A: inert-but-visible is acceptable). In the
-- keep, everything is unchanged (vanilla works without cim). CW is blocked earlier by
-- gut_open_mission_inventory.
--
-- Cross-mod ref uses _has_cim() (defined near the top of this file) so the stable
-- gut works with EITHER the stable (cim) or dev-sibling (cim_dev) of Crafting in Modded.
local function _gut_customize_allowed()
    -- Allowed in the keep always; mid-mission only with cim/cim_dev (the only
    -- mission-safe customization backend).
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    return in_keep or (_has_cim() ~= nil)
end

mod:hook("HeroWindowLoadoutConsole", "_customize_item", function(func, self, item)
    do
        local d = item and item.data
        local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
        mod:debug("[gut:customize_click] item.key=%s slot=%s backend_id=%s in_keep=%s cim=%s",
            tostring(item and (item.key or (d and d.key)) or "?"),
            tostring(d and d.slot_type or "?"),
            tostring(item and item.backend_id or "?"),
            tostring(in_keep),
            _has_cim() and "present" or "absent")
    end
    if _gut_customize_allowed() then
        return func(self, item)
    end
    mod:echo("Customize disabled mid-mission (Crafting in Modded mod isn't loaded — would crash the game).")
end)

-- Kill the cog CLICK at the source mid-mission (no cim), so the gear icon is INERT
-- rather than a guarded-but-clickable crash hazard. Returning nil from
-- _is_customize_item_pressed makes the mouse path (_handle_input:266) skip
-- _customize_item; returning false from _is_selected_item_customizable makes the
-- gamepad/refresh path (_on_window_input:239) skip it too. Both no-op the wrapped
-- function entirely when disallowed (no vanilla side effects to preserve — these are
-- pure read-only "is X pressed/customizable" queries). When allowed (keep or cim),
-- run vanilla unchanged.
mod:hook("HeroWindowLoadoutConsole", "_is_customize_item_pressed", function(func, self)
    if not _gut_customize_allowed() then return nil end
    return func(self)
end)

mod:hook("HeroWindowLoadoutConsole", "_is_selected_item_customizable", function(func, self)
    if not _gut_customize_allowed() then return false end
    return func(self)
end)

-- ============================================================
-- Show menu tabs in-mission (console "new GUI" tab strip)
-- ============================================================
-- The hero view's "new GUI" tab strip (Equipment / Talents / Crafting /
-- Cosmetics) is HeroWindowPanelConsole -- the console-style layout VT2 renders on
-- PC whenever Options -> "Use PC menu layout" is OFF (the default, so this is what
-- most players see). That class HIDES and INPUT-DISABLES the whole tab strip in a
-- mission: both its draw (hero_window_panel_console.lua:496) and its title-button
-- input loop (:360) are gated on `self.is_in_inn`, which is false mid-mission, so
-- on_enter's else-branch (:87-95) skips _setup_text_buttons_width /
-- _setup_input_buttons and only the system/back/close buttons remain. Net: open the
-- inventory in a mission and there are no clickable tabs (the reported symptom).
--
-- The title-button widgets ARE always built in create_ui_elements (:132-150)
-- regardless of is_in_inn -- only their setup + draw + input are gated. So we
-- re-enable the strip by flipping the instance's is_in_inn to true (post-on_enter)
-- and running the two setup methods vanilla skipped. We park _sync_delay far in the
-- future so _sync_news (the only keep-leaning helper the update branch then runs)
-- never executes its news work -- the "new" badges just don't refresh in-mission;
-- the tabs still draw and click.
--
-- PC console-layout only. The PC-options layout (HeroWindowOptions, "Use PC menu
-- layout" ON) already draws its strip in-mission, so it needs nothing here.
--
-- Crafting/Forge (tab 3) is gated OFF unless cim is loaded -- its item-customization
-- sub-path is the same ui_store_preview crash the _customize_item hook above guards
-- (belt-and-suspenders with that guard). NOTE: vanilla does NOT grey tab 3 in a
-- normal Adventure/Deus mission (the `forge` layout's can_add_function only blocks
-- versus/inn_vs, hero_window_layout_console.lua:139-141), so this disable_button
-- write is what keeps Crafting greyed with gut standalone. Tab 3 is asserted to be
-- the crafting tab in vanilla (hero_window_panel_console.lua:140,
-- text_field == "hero_window_crafting"). Loot is not a tab on this strip.
-- Inventory/Talents/Cosmetics are mission-safe (talent changes apply live).
-- Pre-flight: no other gut hook targets HeroWindowPanelConsole.
mod:hook_safe("HeroWindowPanelConsole", "on_enter", function(self)
    if not mod:get("gut_mission_menu_tabs") then return end
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if in_keep then return end          -- keep already shows the strip correctly
    self.is_in_inn = true               -- un-gate the tab-strip setup/draw/input branches
    self.force_ingame_menu = false
    self._sync_delay = 999999           -- park _sync_news so it never runs its keep-leaning news work
    pcall(function()
        self:_setup_text_buttons_width()
        self:_setup_input_buttons()
    end)
    -- Gate the Crafting/Forge tab unless cim/cim_dev is present (item-customization
    -- preview-level crash).
    local tb = self._title_button_widgets
    if tb and tb[3] and not _has_cim() then
        tb[3].content.button_hotspot.disable_button = true
    end
    -- (#155) COSMETICS tab (tb[4]) is NOT mission-safe (the line 204 claim was wrong):
    -- HeroWindowCosmeticsLoadoutConsole draws the weapon-pose items via gui_pose_items_atlas,
    -- which is absent from the in-mission renderer's Gui -> ui_passes.lua:134 C-FATAL (crash
    -- GUID 5c0865b4, client). cosmetics_tweaker does not make it mission-safe. Disable the
    -- tab mid-mission (keep unaffected); the draw-skip hook below covers any non-button path.
    if tb and tb[4] then
        tb[4].content.button_hotspot.disable_button = true
    end
    mod:debug("[gut:mission-tabs] in-mission tab strip enabled (tabs=%s, forge_gated=%s)",
        tostring(tb and #tb or 0), tostring(not _has_cim()))
end)

-- ============================================================
-- (#155) Cosmetics-loadout window crash guard (mid-mission)
-- ============================================================
-- HeroWindowCosmeticsLoadoutConsole:draw draws the weapon-POSE items via the
-- `gui_pose_items_atlas` material, which is NOT resident in the in-mission renderer's
-- Gui -> ui_passes.lua:134 takes a C-LEVEL fatal (uncatchable by pcall — same class as
-- the LA armoury_atlas crash). Crash GUID 5c0865b4-... (client). The tab gate above
-- blocks the click path; this is the belt-and-suspenders: SKIP this window's draw whenever
-- we're not in the keep, so the bad texture pass can never run. In the keep (where the
-- atlas is resident) draw runs unchanged. gut hooks this class NOWHERE else -> no dup hook.
mod:hook("HeroWindowCosmeticsLoadoutConsole", "draw", function(func, self, ...)
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if not in_keep then
        mod:debug("[gut:cosmetics-guard] skipped HeroWindowCosmeticsLoadoutConsole:draw mid-mission (gui_pose_items_atlas not resident -> would C-fatal)")
        return
    end
    return func(self, ...)
end)

-- ============================================================
-- Keep Menus in Missions (InventorySettings patch + ESC-menu entry)
-- ============================================================
-- PURE data-table mutation, NO hook.
--
-- Two patches:
--   (1) InventorySettings.inventory_loadout_access_supported_game_modes —
--       hero_view.lua:323 early-returns on adventure/deus and the loadout panel
--       never inits without this.
--   (2) menu_layouts.in_game.{alone,host,client} — adds an "Open Inventory" entry
--       to the ESC menu as a fallback for players who don't recall the hotkey.
--
-- (The legacy gt patch (3) — flipping the hotkeys-enabled arg of
-- IngameUI.handle_menu_hotkeys — was removed in gt v0.2.82-dev / Issue #62 because
-- it enabled the H/M/O/C/K view hotkeys too, which spawn unloaded ui_* preview
-- worlds mid-mission and crash. In-mission inventory opens via the /gut_inv direct
-- transition above, which doesn't depend on any hotkey flip.)
local _INVENTORY_BUTTON_ENTRY = {
    display_name = "interact_open_inventory_chest",
    fade = true,
    requires_player_unit = true,
    transition = "hero_view_force",
    transition_state = "overview",
}

local function _get_in_game_layouts()
    -- ingame_view_menu_layout is local_require'd, so its return table lives in
    -- package.loaded. Mutating that shared table affects the layouts seen by
    -- subsequently-created IngameView instances.
    local pkg = package and package.loaded
    local defs = pkg and pkg["scripts/ui/views/ingame_view_menu_layout"]
    return defs and defs.menu_layouts and defs.menu_layouts.in_game
end

local function _has_inventory_entry(layout)
    if type(layout) ~= "table" then return false end
    for _, entry in ipairs(layout) do
        if entry and entry.display_name == _INVENTORY_BUTTON_ENTRY.display_name then
            return true
        end
    end
    return false
end

local function _patch_in_game_menu(enabled)
    local in_game = _get_in_game_layouts()
    if not in_game then return end
    for _, key in ipairs({ "alone", "host", "client" }) do
        local layout = in_game[key]
        if type(layout) == "table" then
            local has = _has_inventory_entry(layout)
            if enabled and not has then
                -- Insert just before "options_menu_button_name" (slot 2 in vanilla
                -- in_game layouts) so the order matches the lobby layout: Return,
                -- Inventory, Options...
                table.insert(layout, 2, table.clone(_INVENTORY_BUTTON_ENTRY))
            elseif (not enabled) and has then
                for i = #layout, 1, -1 do
                    if layout[i] and layout[i].display_name == _INVENTORY_BUTTON_ENTRY.display_name then
                        table.remove(layout, i)
                    end
                end
            end
        end
    end
end

local function _patch_inventory_access()
    -- The InventorySettings loadout-access patch + ESC-menu entry are needed if
    -- EITHER in-mission feature is on: the inventory feature (this module) OR the
    -- hero-select feature (_gut_mission_hero_select.lua) -- both render HeroView
    -- panels mid-mission and depend on the same game-mode gate.
    local enabled = (mod:get("gut_mission_inventory_enabled")
        or mod:get("gut_mission_hero_select_enabled")) and true or false
    -- ADVENTURE-EXCLUSIVE (user directive 2026-06-18): in-mission inventory/loadout
    -- is OFF in Chaos Wastes -- viewing the hero screen or changing items/talents
    -- during a CW run crashes (CW is loadout-locked, managed by the deus boon
    -- system). So NEVER grant deus loadout access, and don't add the in-mission
    -- "Open Inventory" ESC-menu button while in a CW run.
    local in_deus = Managers and Managers.mechanism and Managers.mechanism.current_mechanism_name
        and Managers.mechanism:current_mechanism_name() == "deus"
    if InventorySettings then
        local modes = InventorySettings.inventory_loadout_access_supported_game_modes
        if modes then
            modes.adventure = enabled or nil
            modes.survival  = enabled or nil
            modes.deus      = nil   -- NEVER (CW loadout changes crash)
        end
    end
    _patch_in_game_menu(enabled and not in_deus)
end

-- Exposed for the on_game_state_changed + on_setting_changed dispatchers in
-- gui_tweaker_dev.lua (they call this at the points the gt file-local was called).
mod._gut_apply_keep_menus = _patch_inventory_access

-- Apply once at load (mirrors the original load-time call) so the ESC-menu entry +
-- InventorySettings patch reflect the persisted setting before any state change fires.
_patch_inventory_access()
