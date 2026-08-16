local mod = get_mod("event_tweaker")

-- _evt_preview.lua — issue 532: preview the active mutators on the Tab-hold panel
--
-- Sibling of ct_dev's Starting-Boons preview (chaos_wastes_tweaker_dev.lua,
-- CT_BOON_PREVIEW_461_MARKER). Issue 461 asked the Tab-hold player-list panel to
-- preview "active mutators and starting boons set from the host"; ct shipped the
-- boons half, this ships the mutators half on the SAME right-hand panel.
--
-- Risk posture (untestable UI; PROJECT_STANDARDS 2.2b + "no-guessing" doctrine):
-- we do NOT append into vanilla's own reward widget list (those draw in vanilla's
-- UNguarded pass, so a mutator-icon atlas that is not resident in the keep could
-- assert mid-loop and kill the whole panel). Instead we build our OWN widgets and
-- draw them in our OWN begin_pass/end_pass with every draw_widget individually
-- pcall-wrapped -- worst case our pass no-ops and the panel is byte-identical to
-- vanilla. Icon and name are SEPARATE widgets per row, so a mutator whose icon
-- texture will not resolve still shows its NAME (fonts are always resident):
-- graceful degradation, never a blank/crashing row. Two hooks on DISTINCT
-- IngamePlayerListUI methods (singleton-clean; et had NO hook on this class):
-- `_setup_deed_reward_data` [safe] = build point (fires once on panel activation,
-- keep-only via `self._is_in_inn`, gated on the `preview_active_mutators` toggle;
-- builds onto the instance so `_draw` only draws -- zero per-frame allocation) and
-- `_draw` [safe] = the guarded draw pass (runs after vanilla closed its pass at
-- ingame_player_list_ui_v2.lua:1755).
--
-- DATA: mod._evt.preview_selection() (_evt_selection.lua) returns the active list
-- (preset + individual + floor-passing curses, weave-dropped names already
-- excluded) plus the issue 430 parity-DROPPED curse names. Active is what actually
-- injects; dropped curses render greyed/flagged "(skipped: a peer lacks the mod)"
-- so the preview NEVER advertises a curse that will not activate.
--
-- CLIENT CAVEAT: et is a host-config mod -- the mutator selection is the HOST's
-- local settings and et does NOT sync them to clients. So on a client the panel
-- shows the CLIENT's own selection with a caveat sub-line that the host decides;
-- that is exactly, and only, what et knows client-side.
--
-- PLACEMENT: ct draws its Starting-Boons block anchored to the reward_divider /
-- reward_item scenegraph nodes on banner_right (reward_divider Y=-700), growing
-- DOWN. When ct's boon preview is active we STACK our block ABOVE it (a positive Y
-- offset on the same reward_divider node) with a capped row count, so both render
-- together without overlap; when ct is absent our block takes ct's reward-slot
-- position (base offset 0).
--
-- Owned by: event_tweaker.lua entry point (dofile'd after _evt_selection so
-- ET.preview_selection exists). No mod._evt exports; consumes the selection surface.

local ET = mod._evt
local rt_register = ET.rt_register
local preview_selection = ET.preview_selection
-- Shared curse catalog (require = evaluated once and cached, same table as the
-- data/localization files see) - carries the issue 1149 god-icon fallback.
local Curses = require("scripts/mods/event_tweaker/event_tweaker_curses")

-- Marker for the issue532 regression check (a refactor that drops the block trips it).
local EVT_MUTATOR_PREVIEW_532_MARKER = "mutator_preview_ingame_playerlist_v0.4.30"

-- ---- display / icon resolution -------------------------------------------------
-- Player-facing name from the mutator template's own display_name loc key (the
-- same canonical source ct uses for boons), guarding the vanilla "<key>"
-- miss-sentinel; falls back to the raw injected name. On `mod` so the command +
-- widget builder + regression check share one resolver.
function mod._evt_mutator_display(name)
    local MT = rawget(_G, "MutatorTemplates")
    local tmpl = MT and MT[name]
    local key = tmpl and tmpl.display_name
    if key then
        local ok, raw = pcall(Localize, key)
        if ok and type(raw) == "string" and raw ~= "" and raw ~= "<" .. key .. ">" then
            return raw
        end
    end
    return tostring(name)
end

-- Icon texture name: the template's own in-game icon where it exposes one,
-- else the curse's god-theme icon (the icon vanilla's Deus curse UI shows,
-- deus_curse_ui.lua:106/144 - issue 1149: several managed curse templates
-- ship no per-template icon), else nil (name-only row).
function mod._evt_mutator_icon(name)
    local MT = rawget(_G, "MutatorTemplates")
    local tmpl = MT and MT[name]
    return Curses.icon_for(name, tmpl)
end

-- ---- ct coordination -----------------------------------------------------------
-- Is ct's Starting-Boons block drawing on this same panel right now? Checks both
-- the dev clone (ct_dev, which shipped #461) and stable (ct, once promoted).
-- pcall-guarded: reading a sibling mod's setting must never fault ours; a false
-- read just means we take the reward-slot position instead of stacking above.
function mod._evt_ct_boon_block_present()
    local ids = { "ct_dev", "ct" }
    for i = 1, #ids do
        local ok, present = pcall(function()
            local m = get_mod(ids[i])
            return (m and m:is_enabled() and m:get("preview_starting_boons")) and true or false
        end)
        if ok and present then
            return true
        end
    end
    return false
end

-- ---- widget geometry -----------------------------------------------------------
-- All widgets anchor to the reward_divider node so a single base_y shifts the whole
-- block. base_y 0 = ct's reward-slot; a positive base_y stacks us above ct's block.
local ICON            = 26
local ROW_H           = 30
local HEADER_GAP      = 42     -- header baseline -> first row
local CAVEAT_GAP      = 22     -- extra drop when the client caveat sub-line is shown
local CT_STACK_OFFSET = 380    -- push our block up this many px when ct's boons render below
local MAX_ACTIVE_STACKED, MAX_DROP_STACKED = 5, 2   -- keep the stacked block above ct's -700 header
local MAX_ACTIVE_SOLO,    MAX_DROP_SOLO    = 12, 5  -- reward-slot: room to grow down

local function _text_widget(text, font_size, color, x, y, z)
    return UIWidget.init(UIWidgets.create_simple_text(text, "reward_divider", font_size, nil, {
        horizontal_alignment = "left",
        vertical_alignment = "center",
        localize = false,
        word_wrap = false,
        font_size = font_size,
        font_type = "hell_shark",
        text_color = color,
        offset = { x, y, z },
    }))
end

-- Build the full widget list (header + optional client caveat + active rows +
-- overflow + greyed dropped-curse rows). Called once at panel activation.
local function _build_widgets(active, dropped, base_y, max_active, max_drop, title, caveat)
    local out = {}
    out[#out + 1] = _text_widget(title, 22, { 255, 255, 214, 138 }, 4, base_y, 3)

    local row0 = base_y - HEADER_GAP
    if caveat then
        out[#out + 1] = _text_widget(caveat, 16, { 255, 200, 190, 150 }, 4, base_y - 20, 3)
        row0 = row0 - CAVEAT_GAP
    end

    local row = 0
    local n_active = math.min(#active, max_active)
    for i = 1, n_active do
        local a = active[i]
        local disp = mod._evt_mutator_display(a.name)
        if a.is_curse then
            disp = disp .. " (curse)"
        end
        local ry = row0 - row * ROW_H
        local icon = mod._evt_mutator_icon(a.name)
        if icon then
            out[#out + 1] = UIWidget.init(UIWidgets.create_simple_texture(
                icon, "reward_divider", false, false, nil, { 4, ry, 0 }, { ICON, ICON }))
        end
        out[#out + 1] = _text_widget(disp, 20, { 255, 235, 235, 235 },
            4 + ICON + 10, ry - ICON * 0.5, 2)
        row = row + 1
    end
    if #active > n_active then
        local ry = row0 - row * ROW_H
        out[#out + 1] = _text_widget(string.format("+%d more", #active - n_active), 18,
            { 255, 200, 200, 200 }, 4, ry - ICON * 0.5, 2)
        row = row + 1
    end

    -- Peer-capability floors: package curses and Adventure Shadow are greyed +
    -- flagged when a current peer lacks the required implementation.
    if #dropped > 0 then
        local n_drop = math.min(#dropped, max_drop)
        for i = 1, n_drop do
            local ry = row0 - row * ROW_H
            out[#out + 1] = _text_widget(
                mod._evt_mutator_display(dropped[i]) .. " (skipped: a peer lacks the mod)",
                18, { 180, 150, 150, 150 }, 4, ry - ICON * 0.5, 2)
            row = row + 1
        end
        if #dropped > n_drop then
            local ry = row0 - row * ROW_H
            out[#out + 1] = _text_widget(string.format("+%d more skipped", #dropped - n_drop),
                16, { 180, 150, 150, 150 }, 4, ry - ICON * 0.5, 2)
            row = row + 1
        end
    end

    return out
end

-- ---- build point ---------------------------------------------------------------
-- Vanilla calls _setup_deed_reward_data once when the Tab panel activates. Keep-only
-- (self._is_in_inn) so the block coordinates with ct's keep-only boon preview; local
-- display toggle preview_active_mutators. Builds onto the instance so the per-frame
-- _draw hook only draws (zero per-frame allocation).
mod:hook_safe("IngamePlayerListUI", "_setup_deed_reward_data", function(self)
    self._evt_mutator_preview_widgets = nil
    if not self._is_in_inn then return end
    if not mod:get("preview_active_mutators") then return end
    local ok, err = pcall(function()
        local active, dropped = preview_selection()
        if #active == 0 and #dropped == 0 then return end
        local ct_present = mod._evt_ct_boon_block_present()
        local base_y     = ct_present and CT_STACK_OFFSET or 0
        local max_active = ct_present and MAX_ACTIVE_STACKED or MAX_ACTIVE_SOLO
        local max_drop   = ct_present and MAX_DROP_STACKED or MAX_DROP_SOLO
        -- Host-config vs client caveat: et never syncs the host's mutator picks to
        -- clients, so on a client this list is the client's OWN selection.
        local is_server  = self._local_player and self._local_player.is_server
        local caveat     = (not is_server) and mod:localize("evt_mutator_preview_client_caveat") or nil
        local title      = string.format("%s (%d)", mod:localize("evt_mutator_preview_header"), #active)
        self._evt_mutator_preview_widgets = _build_widgets(active, dropped, base_y, max_active, max_drop, title, caveat)
    end)
    if not ok then
        self._evt_mutator_preview_widgets = nil
        pcall(printf, "[et:532] mutator-preview build failed (panel unaffected): %s", tostring(err))
    end
end)

-- ---- draw point ----------------------------------------------------------------
-- Our OWN begin_pass/end_pass layered on top of vanilla's, each draw_widget
-- pcall-guarded so a non-resident mutator-icon texture can never crash the panel.
-- hook_safe = runs after vanilla's _draw closed its pass (ingame_player_list_ui_v2.lua:1755).
mod:hook_safe("IngamePlayerListUI", "_draw", function(self, dt)
    local widgets = self._evt_mutator_preview_widgets
    if not widgets or #widgets == 0 then return end
    pcall(function()
        local r = self._ui_top_renderer
        local sg = self._ui_scenegraph
        local im = self._input_manager
        local input_service = im and im:get_service("player_list_input")
        local rs = self._render_settings
        if not (r and sg and input_service and rs) then return end
        UIRenderer.begin_pass(r, sg, input_service, dt, nil, rs)
        for i = 1, #widgets do
            pcall(UIRenderer.draw_widget, r, widgets[i])
        end
        UIRenderer.end_pass(r)
    end)
end)

-- ---- textual preview / verify surface ------------------------------------------
-- Works even if the panel icons do not render, and confirms the mutator list the
    -- panel would show (active + peer-capability-gated skips).
mod:command("event_preview_mutators", "List the mutators this lobby will activate (the #532 Tab-hold preview)", function()
    local active, dropped = preview_selection()
    if #active == 0 and #dropped == 0 then
        mod:echo("[event_tweaker] No mutators selected. Pick an Event Preset or check mutators in the mod menu.")
        return
    end
    mod:echo("%s", string.format("[event_tweaker] Active Mutators preview (%d) -- shown on the right panel while holding Tab in the keep:", #active))
    for i = 1, #active do
        local a = active[i]
        mod:echo("%s", string.format("  %d. %s%s", i, mod._evt_mutator_display(a.name), a.is_curse and " (curse)" or ""))
    end
    if #dropped > 0 then
        mod:echo("%s", string.format("[event_tweaker] Skipped -- %d peer-gated mutator(s): a lobby peer lacks the required Tweaker: Events capability:", #dropped))
        for i = 1, #dropped do
            mod:echo("%s", string.format("  - %s", mod._evt_mutator_display(dropped[i])))
        end
    end
end)

-- issue 532 regression: the marker + the data builder + the display resolver + the
-- display toggle stay wired, so a future refactor can't silently drop the Tab-hold
-- mutator preview.
rt_register("issue532_mutator_preview_wired", function()
    if EVT_MUTATOR_PREVIEW_532_MARKER ~= "mutator_preview_ingame_playerlist_v0.4.30" then
        return "#532 REGRESSION: EVT_MUTATOR_PREVIEW_532_MARKER missing/mismatch; got " .. tostring(EVT_MUTATOR_PREVIEW_532_MARKER)
    end
    if type(preview_selection) ~= "function" then
        return "#532 REGRESSION: ET.preview_selection missing"
    end
    local a, d = preview_selection()
    if type(a) ~= "table" or type(d) ~= "table" then
        return "#532 REGRESSION: preview_selection must return (active table, dropped table)"
    end
    if type(mod._evt_mutator_display) ~= "function" then
        return "#532 REGRESSION: mod._evt_mutator_display missing"
    end
    if type(mod:get("preview_active_mutators")) ~= "boolean" then
        return "#532 REGRESSION: preview_active_mutators checkbox not registered (mod:get non-boolean)"
    end
end)

-- issue 1149 (localization half): every managed Cursed Adventure modifier must
-- surface a clean localized options label (no raw mutator key anywhere in the
-- player-facing string) and resolve an in-game icon for the Tab-hold preview.
rt_register("issue1149_modifier_loc_icon_coverage", function()
    local managed = Curses.MANAGED_CURSES
    for i = 1, #managed do
        local id = managed[i].id
        local title = mod:localize("mut_" .. id)
        if type(title) ~= "string" or title == "" then
            return "#1149 REGRESSION: no options label registered for " .. id
        end
        if title:find(id, 1, true) or title:find("mut_", 1, true) then
            return "#1149 REGRESSION: options label for " .. id .. " still shows the raw mutator key"
        end
        local tooltip = mod:localize("mut_" .. id .. "_tooltip")
        if type(tooltip) ~= "string" or tooltip:find("[" .. id .. "]", 1, true) then
            return "#1149 REGRESSION: tooltip for " .. id .. " missing or still bracket-tagged with the raw key"
        end
        if not mod._evt_mutator_icon(id) then
            return "#1149 REGRESSION: no in-game icon resolves for " .. id .. " (template icon + god-theme fallback both missing)"
        end
    end
end)
