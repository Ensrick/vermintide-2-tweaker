-- ============================================================
-- Accessory Craft Panel — 3 per-slot craft buttons (overlay)
-- ============================================================
-- A self-contained overlay panel drawn on top of the Athanor accessories view
-- (HeroWindowWeaveProperties, amulet mode). Three buttons — CRAFT NECKLACE /
-- CHARM / TRINKET — each crafting one accessory slot from its current
-- bubble-edited state via mod._cim_amulet_craft_one_slot.
--
-- WHY A SEPARATE OVERLAY (not create_default_button into the host window):
-- the previous approaches injected UIWidgets.create_default_button widgets into
-- the host window's draw arrays anchored to the full-size center "viewport"
-- scenegraph node. That produced: a screen-covering black box (the default
-- button background stretched to fill the giant node), bottom-left corner
-- placement, and overlapping hotspots (one click fired two slots). This module
-- follows the proven cosmetics_tweaker `_glow_picker.lua` pattern instead:
--   * its OWN scenegraph with each button node EXPLICITLY positioned/sized,
--   * HAND-ROLLED widget defs (hotspot + sized rect + text + menu_frame_12
--     texture_frame border, matching GUT's Mod Tweaker popup) so the background
--     is the button size, not the node size,
--   * its OWN draw pass (begin_pass on our scenegraph → draw_widget → end_pass)
--     hooked off HeroWindowWeaveProperties._draw,
--   * its own per-frame hotspot read for clicks (non-overlapping nodes).
-- Because positions are explicit constants, moving the buttons is a reliable
-- 2-number edit, not a guess against an opaque node.
-- ============================================================

local mod = get_mod("cim")

-- UI feedback sound — routed through the HOST WINDOW's own vanilla _play_sound.
-- `HeroWindowWeaveProperties._play_sound(self, event)` calls `self._parent:play_sound(event)`
-- (hero_window_weave_properties.lua:2837); that parent is HeroViewStateWeaveForge,
-- whose play_sound (hero_view_state_weave_forge.lua:859) is the EXACT path vanilla
-- uses for every forge click/hover in this window. `event` is a real Wwise event
-- name ("Play_hud_select" / "Play_hud_hover", both grep-confirmed in the vanilla
-- source). `pw` is Panel._properties_win (the live HeroWindowWeaveProperties).
--
-- WHY NOT the old music_world path: the previous version resolved a wwise_world off
-- Managers.world:world("music_world"), but that world is NOT registered in the
-- weave-forge UI context (the user's log showed `has_music=false`), so the Wwise
-- trigger silently no-op'd and no sound ever played. The window's own _play_sound
-- has no such dependency. Fully pcall-guarded: a nil parent/event is silent.
local function _play_sound(pw, event)
    if pw and pw._play_sound then
        pcall(pw._play_sound, pw, event)
    end
end

local Panel = {}

Panel._built           = false
Panel._scenegraph      = nil
Panel._widgets         = nil   -- array drawn each frame
Panel._properties_win  = nil   -- set by the draw hook each frame (craft context)
Panel._on_craft        = nil   -- function(slot_index, slot_name) — set by cim

-- ---- Layout constants (tweak these to reposition — explicit + reliable) ----
local BTN_W, BTN_H = 340, 64
local BTN_GAP      = 16                  -- vertical gap between buttons
local SIDE_INSET   = 70                  -- distance from the LEFT screen edge
-- 3 buttons stacked, vertically centred: y offsets +(H+gap), 0, -(H+gap).
local _ROW_STEP    = BTN_H + BTN_GAP

-- Background fill colours (ARGB). Pressed > hover > base, so a click produces a
-- clearly perceptible flash (base ~6% alpha -> pressed ~28% alpha + brighter RGB).
local _COL_BASE    = { 235,  26,  22,  16 }   -- dark base
local _COL_HOVER   = { 245,  70,  58,  40 }   -- brighter while hovered
local _COL_PRESSED = { 255, 130, 108,  78 }   -- bright flash while held (click feedback)

-- Visual top-to-bottom order: Necklace, Charm, Trinket. idx/slot match
-- _AMULET_SLOT_BY_INDEX (idx1=ring/charm, idx2=necklace, idx3=trinket_1).
local _BUTTONS = {
    { idx = 2, slot = "slot_necklace",  label = "CRAFT NECKLACE", node = "cim_acc_btn_1" },
    { idx = 1, slot = "slot_ring",      label = "CRAFT CHARM",    node = "cim_acc_btn_2" },
    { idx = 3, slot = "slot_trinket_1", label = "CRAFT TRINKET",  node = "cim_acc_btn_3" },
}

-- Exposed for the regression tests (expected built-widget count).
Panel.NUM_BUTTONS = #_BUTTONS
Panel.BUTTONS     = _BUTTONS   -- read-only introspection (slot/idx mapping)

-- _build() runs every frame until it succeeds; guard so a persistent failure
-- (missing UI global, init error) logs ONCE instead of spamming the log.
Panel._build_fail_logged = false
local function _fail_once(fmt, ...)
    if Panel._build_fail_logged then return end
    Panel._build_fail_logged = true
    mod:info(fmt, ...)
end

local function _make_scenegraph_definition()
    local def = {
        root = {
            is_root = true,
            size     = { 1920, 1080 },
            position = { 0, 0, (rawget(_G, "UILayer") and UILayer.default) or 1 },
        },
    }
    for i, b in ipairs(_BUTTONS) do
        -- i=1 → top (+_ROW_STEP), i=2 → middle (0), i=3 → bottom (-_ROW_STEP).
        local y = -(i - 2) * _ROW_STEP
        def[b.node] = {
            parent               = "root",
            horizontal_alignment = "left",
            vertical_alignment   = "center",
            size                 = { BTN_W, BTN_H },
            position             = { SIDE_INSET, y, 10 },
        }
    end
    return def
end

-- menu_frame_12 9-slice ornate border — the SAME frame GUT's Mod Tweaker popups
-- use (gui_tweaker _mod_tweaker_definitions.create_tooltip_popup). Safe on this
-- renderer: the panel draws on HeroWindowWeaveProperties.self._ui_top_renderer,
-- which IS ingame_ui_context.ui_top_renderer (hero_window_weave_properties.lua:143)
-- — the exact renderer GUT draws menu_frame_12 on. Metrics copied verbatim from GUT.
local FRAME_TEXTURE   = "menu_frame_12"
local FRAME_TEX_SIZE  = { 64, 64 }
local FRAME_TEX_SIZES = { corner = { 11, 11 }, vertical = { 5, 1 }, horizontal = { 1, 5 } }

-- Hand-rolled button widget: hotspot (input) + filled rect (bg, button-sized) +
-- centred label + a menu_frame_12 texture_frame border. Hover brightens the bg
-- via the hotspot is_hover flag read in draw().
local function _widget_button(node, label)
    return {
        element = {
            passes = {
                { content_id = "hotspot", pass_type = "hotspot" },
                { pass_type = "rect", style_id = "rect" },
                { pass_type = "text", style_id = "text", text_id = "text" },
                -- Ornate menu_frame_12 border, drawn LAST (highest z) so its edges
                -- sit crisply over the fill — mirrors GUT's popup frame ordering.
                { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
            },
        },
        content = {
            text    = label,
            frame   = FRAME_TEXTURE,
            hotspot = {},
        },
        style = {
            rect = {
                size  = { BTN_W, BTN_H },
                color = { 235, 26, 22, 16 },        -- dark base (overwritten per-frame in draw)
            },
            text = {
                font_size = 22,
                font_type = "hell_shark_header",
                horizontal_alignment = "center",
                vertical_alignment   = "center",
                text_color = { 255, 245, 232, 215 },
                offset     = { 0, 0, 2 },
                size       = { BTN_W, BTN_H },
            },
            -- menu_frame_12 9-slice; area_size drives the frame size to the button.
            frame = {
                texture_size  = FRAME_TEX_SIZE,
                texture_sizes = FRAME_TEX_SIZES,
                color         = { 255, 255, 255, 255 },
                offset        = { 0, 0, 3 },
                area_size     = { BTN_W, BTN_H },
            },
        },
        offset        = { 0, 0, 0 },
        scenegraph_id = node,
    }
end

local function _build()
    if Panel._built then return true end
    local UISceneGraph = rawget(_G, "UISceneGraph")
    local UIWidget     = rawget(_G, "UIWidget")
    local UIRenderer   = rawget(_G, "UIRenderer")
    if not (UISceneGraph and UIWidget and UIRenderer) then
        _fail_once("[acc-panel] build aborted — missing UI globals (sg=%s widget=%s renderer=%s)",
            tostring(UISceneGraph), tostring(UIWidget), tostring(UIRenderer))
        return false
    end

    local sg_ok, sg = pcall(UISceneGraph.init_scenegraph, _make_scenegraph_definition())
    if not sg_ok then
        _fail_once("[acc-panel] init_scenegraph FAILED: %s", tostring(sg))
        return false
    end
    Panel._scenegraph = sg

    local widgets = {}
    for i, b in ipairs(_BUTTONS) do
        local w_ok, w = pcall(UIWidget.init, _widget_button(b.node, b.label))
        if not w_ok then
            _fail_once("[acc-panel] widget init FAILED for %s: %s", b.node, tostring(w))
            return false
        end
        widgets[i] = w
    end
    Panel._widgets = widgets
    Panel._built = true
    Panel._build_fail_logged = false  -- reset on success (allow a future re-log if torn down)
    mod:info("[acc-panel] built %d accessory craft buttons (own scenegraph overlay)", #widgets)
    -- DIAG (0.8.38-dev): dump the first built widget's actual pass list + frame
    -- content/style so the log confirms the texture_frame border pass survived
    -- UIWidget.init (i.e. whether the menu_frame_12 border is even in the widget).
    do
        local w1 = widgets[1]
        local ptypes = {}
        local el = w1 and w1.element
        if el and el.passes then
            for _, p in ipairs(el.passes) do ptypes[#ptypes + 1] = tostring(p.pass_type) end
        end
        mod:info("[acc-panel] DIAG passes=[%s] content.frame=%s style.frame=%s",
            table.concat(ptypes, ","),
            tostring(w1 and w1.content and w1.content.frame),
            tostring(w1 and w1.style and w1.style.frame ~= nil))
    end
    return true
end

-- Draw + handle clicks in one pass off the host window's _draw. `ui_renderer`
-- should be the host window's ui_top_renderer; `input_service` its window input
-- service. Pcall-guarded throughout so a UI hiccup can't crash the forge.
function Panel.draw(ui_renderer, input_service, dt)
    if not _build() then return end
    if not ui_renderer then return end

    local UISceneGraph = rawget(_G, "UISceneGraph")
    local UIRenderer   = rawget(_G, "UIRenderer")

    pcall(UISceneGraph.update_scenegraph, Panel._scenegraph)

    local ok_b = pcall(UIRenderer.begin_pass, ui_renderer, Panel._scenegraph,
        input_service, dt, nil, { snap_pixel_positions = true })
    if not ok_b then return end

    local pw = Panel._properties_win
    for _, w in ipairs(Panel._widgets) do
        -- Visual feedback: pressed (held) > hover > base. These read the hotspot
        -- state the PREVIOUS frame's draw wrote onto ui_content (1-frame lag, not
        -- perceptible). draw_widget below re-runs the hotspot pass for this frame.
        local hs = w.content and w.content.hotspot
        if hs and w.style and w.style.rect then
            if hs.is_held then
                w.style.rect.color = _COL_PRESSED
            elseif hs.is_hover then
                w.style.rect.color = _COL_HOVER
            else
                w.style.rect.color = _COL_BASE
            end
        end
        pcall(UIRenderer.draw_widget, ui_renderer, w)
    end

    pcall(UIRenderer.end_pass, ui_renderer)

    -- After the pass each hotspot carries this frame's freshly-written edge events
    -- (on_hover_enter / on_release — see ui_passes.lua UIPasses.hotspot). Consume
    -- them here so each fires exactly once.
    for i, w in ipairs(Panel._widgets) do
        local hs = w.content and w.content.hotspot
        if hs then
            -- Hover-enter EDGE -> single hover sound (matches vanilla forge hover).
            if hs.on_hover_enter then
                hs.on_hover_enter = false
                _play_sound(pw, "Play_hud_hover")
            end
            -- Release EDGE -> click sound + craft dispatch. Vanilla button
            -- semantics: commit on release, not press. The pressed-flash visual is
            -- already handled by _COL_PRESSED (hs.is_held) above.
            if hs.on_release then
                hs.on_release = false  -- consume so it fires once
                _play_sound(pw, "Play_hud_select")
                local b = _BUTTONS[i]
                if b and type(Panel._on_craft) == "function" then
                    pcall(Panel._on_craft, b.idx, b.slot)
                end
            end
        end
    end
end

return Panel
