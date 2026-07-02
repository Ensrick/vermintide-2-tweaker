local mod = get_mod("gut_dev")

-- ============================================================================
-- Compendium (Armory + Bestiary) — Phase 1: hero-menu top-tab buttons (#217)
-- ============================================================================
-- Adds two tabs, Armory and Bestiary, to the hero/character menu's top tab
-- strip (Equipment / Talents / Crafting / Cosmetics ...). Clicking one opens
-- gut's existing Compendium hero-view sub-state (HeroViewStateCompendium) in the
-- matching mode via mod._gut_open_compendium(mode) (defined in
-- _ba_heroview_inject.lua). This is the "top-tab button (Phase 1)" the
-- _ba_compendium_state.lua header flagged.
--
-- WHICH LAYOUT: the CONSOLE layout (HeroWindowPanelConsole) — the tab strip VT2
-- renders on PC whenever Options -> "Use PC menu layout" is OFF (the DEFAULT, so
-- this is what most players see), and the strip gut already integrates with (the
-- mission-tabs on_enter hook in _gut_mission_inventory.lua). The PC-menu-layout
-- column (HeroWindowOptions) is a fixed-position vertical stack with no measured
-- reflow — deferred to a follow-up (see #217) to avoid a rushed overflow layout.
--
-- WHY DEFINITION-TABLE MUTATION (not per-instance widget surgery): the console
-- strip is data-driven. HeroWindowPanelConsole.create_ui_elements builds
-- self._title_button_widgets from `title_button_definitions`, and
-- _setup_text_buttons_width lays each out at `panel_entry_area.width /
-- #title_button_widgets` (hero_window_panel_console.lua:628-644) — a MEASURED
-- row, so appending buttons AUTO-REFLOWS with no fixed-width overlap. Each button
-- needs its own scenegraph node, and nodes cannot be added to a BUILT scenegraph
-- (UISceneGraph.update_scenegraph walks the array + `children` links, and the
-- built table has a newindex-error metatable — ui_scenegraph.lua:136,163,209).
-- So the ONLY clean way to get vanilla to build+position our tabs is to append to
-- the shared `scenegraph_definition` + `title_button_definitions` tables BEFORE
-- init_scenegraph / create_ui_elements read them (references captured at
-- HeroWindowPanelConsole module load: `local X = definitions.X`). This is the
-- same shared-table-mutation technique gut uses for menu_layouts and
-- InventorySettings (_gut_mission_inventory.lua).
--
-- LABELS: these are VANILLA game widgets — their text is resolved by the engine's
-- Localize(), NOT VMF's localizer, so a raw VMF loc key (gut_tab_armory) would
-- NOT resolve (VMF mod localization isn't registered into global Localize — see
-- VMF_RECIPES / feedback_vmf_localize_before_registration). The labels are set as
-- literals with localize=false. (Kept self-contained here rather than in
-- gui_tweaker_dev_localization.lua both because a vanilla widget needs a resolved
-- literal and to avoid clobbering a concurrent menu/localization reorg session
-- editing that file. If loc-file keys are wanted later, resolve them via
-- mod:localize at build time with these as the fallback.)
--
-- HOOKS (both verified NOT already hooked by gut on this class+method — gut's only
-- HeroWindowPanelConsole hook is on_enter in _gut_mission_inventory.lua):
--   * HeroWindowPanelConsole.create_ui_elements (FULL hook) — one hook does BOTH
--     the lazy definition injection (before func, so vanilla builds our tabs) AND
--     the per-instance label/grey pass (after func). A single hook avoids the
--     VMF duplicate-(Class,method) drop.
--   * HeroWindowPanelConsole._on_panel_button_selected (FULL hook) — routes a
--     press on our tabs to the Compendium instead of the vanilla layout switch.

local UIWidgets = UIWidgets

local DEFS_PATH = "scripts/ui/views/hero_view/windows/definitions/hero_window_panel_console_definitions"

-- Namespaced scenegraph-node / widget ids so they can't collide with vanilla
-- game_option_N or another mod's appended tabs. The routing hook matches on these.
local SGID_ARMORY   = "gut_ba_tab_armory"
local SGID_BESTIARY = "gut_ba_tab_bestiary"

-- Fallback literals. Preferred source is the mod loc file (keys gut_tab_armory /
-- gut_tab_bestiary) resolved via mod:localize at build time (below) -- if those
-- keys get added to gui_tweaker_dev_localization.lua later they win automatically;
-- until then these literals render. (They are NOT passed as raw keys because these
-- are vanilla game widgets: engine Localize() can't resolve a VMF mod loc key, so
-- the resolved literal is set with localize=false.)
local LABEL_ARMORY   = "Armory"
local LABEL_BESTIARY = "Bestiary"
local LOCKEY_ARMORY   = "gut_tab_armory"
local LOCKEY_BESTIARY = "gut_tab_bestiary"

-- scenegraph_id -> compendium mode, for the routing hook.
local MODE_BY_SGID = {
    [SGID_ARMORY]   = "armory",
    [SGID_BESTIARY] = "bestiary",
}

local MENU_OPTIONS_FONT_SIZE = 32

local _injected = false

-- Resolve a label from the mod loc file if the key is registered, else fall back
-- to the literal. Called once (from _ensure_defs_injected, at the first
-- create_ui_elements) -- well after mod-init loc registration, so mod:localize is
-- safe (no pre-registration flood).
--
-- (#224) For an UNREGISTERED key VMF returns the missing-key SENTINEL "<key>" (angle
-- brackets), NOT the bare key -- so a plain `s ~= key` guard lets "<gut_tab_armory>"
-- through, and because the tab text renders with localize=false it then shows the raw
-- "<GUT_TAB_ARMORY>" marker verbatim. Reject the bare key AND any "<...>" marker form
-- so we fall back to the display literal.
local function _resolve_label(key, fallback)
    local ok, s = pcall(function() return mod:localize(key) end)
    if ok and type(s) == "string" and s ~= "" and s ~= key and not s:find("^<.->$") then
        return s
    end
    return fallback
end

-- Build one console-panel tab button definition for the Compendium. Mirrors the
-- vanilla game_option buttons (UIWidgets.create_console_panel_button) but with the
-- label as a localize=false literal (vanilla Localize() can't resolve a VMF key).
local function _make_tab_def(scenegraph_id, size, label)
    local def = UIWidgets.create_console_panel_button(scenegraph_id, size, label, MENU_OPTIONS_FONT_SIZE, nil, "center")
    def.content.text_field = label
    -- All four text passes localize the same content.text_field; turn localization
    -- OFF on each so the literal renders verbatim (upper_case=true still applies).
    local style = def.style
    for _, sid in ipairs({ "text", "text_shadow", "text_hover", "text_disabled" }) do
        if style[sid] then
            style[sid].localize = false
        end
    end
    return def
end

-- Append our two scenegraph nodes + title-button definitions to the SHARED console
-- definition tables. Idempotent (guarded by _injected). Runs inside the
-- create_ui_elements hook (before func), so the definitions module is guaranteed
-- loaded (HeroWindowPanelConsole is executing) and the append is visible to the
-- create_ui_elements / init_scenegraph that immediately follow.
local function _ensure_defs_injected()
    if _injected then
        return
    end

    local defs = package and package.loaded and package.loaded[DEFS_PATH]
    local sg = defs and defs.scenegraph_definition
    local title_defs = defs and defs.title_button_definitions
    if type(sg) ~= "table" or type(title_defs) ~= "table" then
        return
    end

    -- Guard against a re-append if this ran once already for this table (e.g. a
    -- reload path re-set _injected): never add a node twice.
    if sg[SGID_ARMORY] then
        _injected = true
        return
    end

    -- Clone the vanilla tab node shape (parent = game_option_pivot, so
    -- _setup_text_buttons_width can size/position it like the others).
    local function _tab_node()
        return {
            horizontal_alignment = "left",
            parent = "game_option_pivot",
            vertical_alignment = "top",
            size = { 220, 68 },
            position = { 0, 0, 0 },
        }
    end

    sg[SGID_ARMORY]   = _tab_node()
    sg[SGID_BESTIARY] = _tab_node()

    -- Appended AFTER the 5 vanilla defs, so the vanilla
    -- `assert(title_button_widgets[3] == crafting)` and the 1..5 can_add loop are
    -- untouched (both run before our indices).
    local label_armory   = _resolve_label(LOCKEY_ARMORY,   LABEL_ARMORY)
    local label_bestiary = _resolve_label(LOCKEY_BESTIARY, LABEL_BESTIARY)
    title_defs[#title_defs + 1] = _make_tab_def(SGID_ARMORY,   sg[SGID_ARMORY].size,   label_armory)
    title_defs[#title_defs + 1] = _make_tab_def(SGID_BESTIARY, sg[SGID_BESTIARY].size, label_bestiary)

    _injected = true
    printf("[gut:217] compendium tabs injected into HeroWindowPanelConsole definitions (Armory, Bestiary)")
end

-- Per-instance pass (after vanilla create_ui_elements): grey our tabs mid-mission
-- (the Compendium is keep/inn-only, so mirror the crafting/cosmetics tab-gating).
-- In the keep they stay enabled (vanilla's can_add loop already left them so).
local function _apply_tab_state(self)
    local tabs = self._title_button_widgets
    if type(tabs) ~= "table" then
        return
    end
    local in_keep = self.is_in_inn and true or false
    for i = 1, #tabs do
        local w = tabs[i]
        if w and MODE_BY_SGID[w.scenegraph_id] then
            local hotspot = w.content and w.content.button_hotspot
            if hotspot then
                hotspot.disable_button = not in_keep
            end
        end
    end
end

-- Single FULL hook: inject defs (before func) + apply per-instance state (after).
mod:hook("HeroWindowPanelConsole", "create_ui_elements", function(func, self, ...)
    pcall(_ensure_defs_injected)
    func(self, ...)
    pcall(_apply_tab_state, self)
end)

-- Route a press on our tabs to the Compendium instead of the vanilla layout swap.
-- Vanilla _on_panel_button_selected(index) maps index -> layout_name_by_index and
-- calls set_layout_by_name; for our appended indices that map is wrong (index 6 ->
-- "system", 7 -> nil), so we MUST intercept before vanilla. Match on scenegraph_id
-- (robust vs. hardcoded indices / other mods appending tabs).
mod:hook("HeroWindowPanelConsole", "_on_panel_button_selected", function(func, self, index)
    local tabs = self._title_button_widgets
    local w = tabs and tabs[index]
    local mode = w and MODE_BY_SGID[w.scenegraph_id]
    if mode then
        local hotspot = w.content and w.content.button_hotspot
        -- Greyed mid-mission (Compendium is keep-only): consume the press silently.
        -- The opener itself also keep-gates, so this is belt-and-suspenders.
        if hotspot and hotspot.disable_button then
            return
        end
        pcall(function() self:_play_sound("Play_hud_select") end)
        -- (#223) This tab ALWAYS lives inside an already-open hero_view, so switch
        -- states with HeroView's own internal mechanism -- NEVER an IngameUI re-enter,
        -- which fatals on the duplicate hero_view_hdr world. self.parent is the
        -- HeroViewStateOverview; self.parent.parent is the live HeroView.
        local overview = self.parent
        local hero_view = overview and overview.parent
        if not (mod._gut_switch_to_compendium_state and mod._gut_switch_to_compendium_state(hero_view, mode)) then
            -- Internal switch unavailable (unexpected parent shape / another mod
            -- wrapping HeroView). Fall back to the opener, which carries its own hard
            -- guard against re-entering an already-open hero_view (so still no crash).
            if mod._gut_open_compendium then
                mod._gut_open_compendium(mode)
            else
                mod:echo("Compendium not ready (inject module didn't load).")
            end
        end
        return
    end
    return func(self, index)
end)

return {}
