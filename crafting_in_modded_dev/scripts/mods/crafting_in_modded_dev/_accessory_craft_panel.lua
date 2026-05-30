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
--   * HAND-ROLLED widget defs (hotspot + sized rect + border + text) so the
--     background is the button size, not the node size,
--   * its OWN draw pass (begin_pass on our scenegraph → draw_widget → end_pass)
--     hooked off HeroWindowWeaveProperties._draw,
--   * its own per-frame hotspot read for clicks (non-overlapping nodes).
-- Because positions are explicit constants, moving the buttons is a reliable
-- 2-number edit, not a guess against an opaque node.
-- ============================================================

local mod = get_mod("cim_dev")

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

-- Hand-rolled button widget: hotspot (input) + filled rect (bg, button-sized) +
-- border + centred label. Hover brightens the bg via the hotspot is_hover flag
-- read in draw().
local function _widget_button(node, label)
    return {
        element = {
            passes = {
                { content_id = "hotspot", pass_type = "hotspot" },
                { pass_type = "rect",   style_id = "rect" },
                { pass_type = "border", style_id = "border" },
                { pass_type = "text",   style_id = "text", text_id = "text" },
            },
        },
        content = {
            text    = label,
            hotspot = {},
        },
        style = {
            rect = {
                size  = { BTN_W, BTN_H },
                color = { 235, 26, 22, 16 },        -- dark base
            },
            border = {
                thickness = 2,
                size      = { BTN_W, BTN_H },
                color     = { 255, 200, 170, 90 },  -- warm parchment edge
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

    for _, w in ipairs(Panel._widgets) do
        -- hover feedback: brighten the bg while hovered.
        local hs = w.content and w.content.hotspot
        if hs and w.style and w.style.rect then
            w.style.rect.color = hs.is_hover and { 245, 64, 52, 36 } or { 235, 26, 22, 16 }
        end
        pcall(UIRenderer.draw_widget, ui_renderer, w)
    end

    pcall(UIRenderer.end_pass, ui_renderer)

    -- Click handling: draw_widget updated each hotspot from input_service.
    -- Always consume on_release (so a stray click can't queue up), but only
    -- dispatch when a craft callback is wired.
    for i, w in ipairs(Panel._widgets) do
        local hs = w.content and w.content.hotspot
        if hs and hs.on_release then
            hs.on_release = false  -- consume so it fires once
            local b = _BUTTONS[i]
            if b and type(Panel._on_craft) == "function" then
                pcall(Panel._on_craft, b.idx, b.slot)
            end
        end
    end
end

return Panel
