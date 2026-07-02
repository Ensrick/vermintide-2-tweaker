local mod = get_mod("gut_dev")

-- _gut_mission_inventory.lua — in-mission hero-view access.
--
-- MIGRATED from general_tweaker (gt) 2026-06-24: this feature moved out of gt and
-- into gut, which now owns the in-mission inventory. Folds gt's two source files
-- (_gt_mission_ui.lua + _gt_keep_menus.lua) into one module — they were always a
-- single user-facing feature. All gt_dev namespacing re-pointed to gut_dev; chat
-- command /gt_inv -> /inv; mod field mod.gt_open_mission_inventory ->
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
--       /inv command + the gut_open_inv_hotkey VMF keybind both route here.
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
--       - the /inv command (registered below) calls it directly.
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
    -- /inv command + the gut_open_inv_hotkey keybind (both route here).
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

mod:command("inv", "Open the inventory mid-mission (uses the same transition vanilla fires from the ESC-menu 'Open Inventory' entry)", function()
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
-- Cross-mod ref targets the STABLE cim id (`get_mod("cim")`), per the dev-clone
-- isolation rule — never cim_dev, even from gut_dev.
local function _gut_customize_allowed()
    -- Allowed in the keep always. Mid-mission it needs a mission-safe backend for the
    -- Customization view (HeroWindowItemCustomization): either cim (which ships the
    -- preview-world mount-fix + modded crafting) OR cosmetics_tweaker (illusion/cosmetic
    -- swaps -- #84/#87). gut carries its own copy of the mount-fix (below) so the
    -- cosmetics_tweaker path mounts even without cim. gut ALONE (neither present) leaves
    -- the cog inert mid-mission. STABLE cross-mod ids only (never cim_dev), per the
    -- dev-clone isolation rule.
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    return in_keep or (get_mod("cim") ~= nil) or (get_mod("cosmetics_tweaker") ~= nil)
end

mod:hook("HeroWindowLoadoutConsole", "_customize_item", function(func, self, item)
    local d = item and item.data
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    local allowed = _gut_customize_allowed()
    -- printf (not mod:debug) so the in-game test produces evidence with mod logging OFF.
    printf("[gut:84] customize click: item=%s slot=%s in_keep=%s cim=%s cosmetics_tweaker=%s -> %s",
        tostring(item and (item.key or (d and d.key)) or "?"),
        tostring(d and d.slot_type or "?"),
        tostring(in_keep),
        get_mod("cim") and "present" or "absent",
        get_mod("cosmetics_tweaker") and "present" or "absent",
        allowed and "ALLOW" or "BLOCK")
    if allowed then
        return func(self, item)
    end
    mod:echo("Customize is disabled mid-mission unless Crafting in Modded or Cosmetics Tweaker is loaded.")
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
-- (#84) Customization view MOUNT fix (cosmetics_tweaker path, no cim)
-- ============================================================
-- With the gate above now allowing the cog when cosmetics_tweaker is present (not only
-- cim), the Customization view (HeroWindowItemCustomization -- illusion swap + reroll)
-- can open mid-mission WITHOUT cim. But vanilla's _create_item_preview_widget_definition
-- hard-codes the keep-only preview world:
--     level_name  = "levels/ui_store_preview/world"
--     object_sets = LevelResource.object_set_names("levels/ui_store_preview/world")
-- Mid-mission that level isn't loaded, so the view FATALS at MOUNT
-- (_register_object_sets -> object_set_names, "Level not loaded"; crash GUID ef637399,
-- dlc_dwarf_interior 2026-05-24) BEFORE any tab is chosen. Only cim shipped this mount-fix,
-- which is why #87 was cim-only. This ports cim's proven fix
-- (crafting_in_modded.lua:2029-2093, v0.7.45) into gut so the cosmetics_tweaker path
-- mounts too.
--
-- Both hooks are INERT in the keep (vanilla is fine there) AND when cim is present (cim
-- owns the fix then; gut passes straight through so the two mods' same-method hooks on
-- different mod-ids don't fight over the returned table). The item still renders because
-- LootItemUnitPreviewer uses resource_packages/levels/ui_loot_preview, which is in
-- GlobalResources (boot_init.lua:159) and thus loaded everywhere. Visual cost mid-mission:
-- a clean empty backdrop instead of the keep's studio lighting.
--
-- SCOPE (#84 behavior half): this makes the view MOUNT so cosmetic changes can be tried
-- in-mission; whether a given illusion/skin actually applies + re-renders live is what the
-- in-game test verifies. cim still owns modded CRAFTING (reroll/salvage) -- those paths are
-- driven by cim's own window-lifecycle hooks and are simply absent without cim.
--
-- Pre-flight: gut hooks HeroWindowItemCustomization NOWHERE else (grep-verified before add).
local _CUSTOMIZE_MISSION_SAFE_ENV = "environment/ui_hdr"  -- mission-safe shading env (matches cim's _FORGE_MISSION_SAFE_ENV)

local function _gut_mount_fix_active()
    -- Take over the mount only when we must: mid-mission with cim ABSENT. In the keep
    -- vanilla works; with cim, cim's own hook does the level strip. STABLE cim id only.
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    return (not in_keep) and (get_mod("cim") == nil)
end

mod:hook("HeroWindowItemCustomization", "_create_item_preview_widget_definition", function(func, self)
    if not _gut_mount_fix_active() then return func(self) end
    printf("[gut:84] customize view mounting mid-mission (cosmetics path, no cim) -- serving level-free preview widget def")
    -- Mirror vanilla's widget shape minus level_name/object_sets; mission-safe shading env.
    return {
        element = {
            passes = {
                { pass_type = "viewport", style_id = "viewport" },
                { content_id = "button_hotspot", pass_type = "hotspot" },
            },
        },
        content = {
            activated = true,
            button_hotspot = {},
        },
        style = {
            viewport = {
                enable_sub_gui      = true,
                fov                 = 65,
                layer               = 962,
                shading_environment = _CUSTOMIZE_MISSION_SAFE_ENV,
                viewport_name       = "item_preview",
                viewport_type       = "default_forward",
                world_name          = "item_preview",
                camera_position     = { 0, 0, 0 },
                camera_lookat       = { 0, 0, 0 },
            },
        },
        offset        = { 0, 0, 0 },
        scenegraph_id = "item_preview",
    }
end)

mod:hook("HeroWindowItemCustomization", "_register_object_sets", function(func, self, viewport_widget, viewport_definition)
    if not _gut_mount_fix_active() then return func(self, viewport_widget, viewport_definition) end
    local vp = viewport_definition and viewport_definition.style and viewport_definition.style.viewport
    if vp and vp.level_name then
        return func(self, viewport_widget, viewport_definition)  -- has a level -> vanilla is safe
    end
    -- Level-free viewport (our stripped def): seed empty object_set_data so vanilla's
    -- trailing _show_object_set(nil, true) iterates an empty table and no-ops.
    local element = viewport_widget.element
    local pass_data = element and element.pass_data and element.pass_data[1]
    viewport_widget.content.object_set_data = {
        world       = pass_data and pass_data.world or nil,
        level       = pass_data and pass_data.level or nil,
        object_sets = {},
        level_name  = nil,
    }
    self:_show_object_set(nil, true)
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
    -- Gate the Crafting/Forge tab unless cim is present (item-customization
    -- preview-level crash). STABLE cim id only.
    local tb = self._title_button_widgets
    if tb and tb[3] and not get_mod("cim") then
        tb[3].content.button_hotspot.disable_button = true
    end
    -- (#155) COSMETICS tab (tb[4]): HeroWindowCosmeticsLoadoutConsole draws weapon-pose
    -- items via the `gui_pose_items_atlas` material (inside materials/ui/ui_1080p_pose_cosmetics),
    -- which vanilla only adds to the ingame renderer's Gui when is_in_inn -> mid-mission it's
    -- absent and the pose draw takes a C-FATAL at ui_passes.lua:134 (crash GUID 5c0865b4).
    -- The GUI material guard (_gut_gui_material_guard.lua) now INJECTS that material into the
    -- in-mission ingame renderers WHEN its resource is resident, publishing the outcome in
    -- mod._gut_pose_atlas_ingame. Enable the tab mid-mission ONLY when the atlas actually
    -- made it into the Gui (else keep it gated -- a blank or re-crashing tab helps no one).
    -- The draw hook below is belt-and-suspenders on the same signal.
    if tb and tb[4] then
        local pose_ok = mod._gut_pose_atlas_ingame and true or false
        tb[4].content.button_hotspot.disable_button = not pose_ok
        printf("[gut:155] in-mission Cosmetics tab %s (pose atlas in Gui=%s)",
            pose_ok and "ENABLED" or "gated", tostring(pose_ok))
    end
    mod:debug("[gut:mission-tabs] in-mission tab strip enabled (tabs=%s, forge_gated=%s, cosmetics_gated=%s)",
        tostring(tb and #tb or 0), tostring(not get_mod("cim")),
        tostring(not (mod._gut_pose_atlas_ingame and true or false)))
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
    -- Safe to draw in the keep always; mid-mission only once the material guard has
    -- injected gui_pose_items_atlas into the ingame Gui (mod._gut_pose_atlas_ingame).
    -- Without it, skipping the draw prevents the ui_passes.lua:134 C-fatal (blank tab).
    if not in_keep and not (mod._gut_pose_atlas_ingame and true or false) then
        mod:debug("[gut:cosmetics-guard] skipped HeroWindowCosmeticsLoadoutConsole:draw mid-mission (gui_pose_items_atlas not in Gui -> would C-fatal)")
        return
    end
    return func(self, ...)
end)

-- (#193) In-mission loadout CONTEXT-MENU crash gate. The loadout-selection window's context menu
-- (_show_context_menu sets _context_menu_active=true) draws delete-bar + loadout-icon textures
-- that aren't resident in the in-mission renderer -> UIRenderer_draw_texture C-fatal (uncatchable
-- by pcall; same class as the #155 cosmetics gate). Block the context menu from OPENING when not
-- in the keep -- basic loadout selection (viewing/picking) still works; only the right-click
-- rename/delete menu is suppressed mid-mission. gut hooks HeroWindowLoadoutSelectionConsole
-- NOWHERE else -> no duplicate hook.
mod:hook("HeroWindowLoadoutSelectionConsole", "_show_context_menu", function(func, self, loadout_button_widget)
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if not in_keep then
        mod:debug("[gut:loadout-guard] blocked HeroWindowLoadoutSelectionConsole:_show_context_menu mid-mission (context-menu textures not resident -> would C-fatal)")
        return
    end
    return func(self, loadout_button_widget)
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
-- worlds mid-mission and crash. In-mission inventory opens via the /inv direct
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
