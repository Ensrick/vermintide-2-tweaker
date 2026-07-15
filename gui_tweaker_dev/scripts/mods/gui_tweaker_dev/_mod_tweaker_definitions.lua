local mod = get_mod("gut_dev")
local NumericEditor = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_numeric_editor")

-- Mod Tweaker scenegraph + widgets (v0.3 — native settings-menu chrome).
-- Rebuilt to look like the game's Options menu by REUSING the native pieces
-- rather than hand-rolling rects. Verified inventory of options_view_definitions
-- (2026-06-17). The native definitions module exposes its scenegraph, background
-- chrome widgets, scrollbar, exit button, and the create_* widget factories — so
-- we require it and assemble from those. The window frame is `menu_frame_12`
-- (UIWidgets.create_frame), panels are create_simple_rect {255,10,10,10}, the
-- cogwheel is `cogwheel_small`, tabs are hand-built text buttons. The list rows are
-- hand-assembled to MATCH the native settings controls (ON/OFF stepper switch,
-- slider with a moving atlas thumb + native arrow textures) WITHOUT reusing the
-- native create_checkbox_widget / create_slider_widget factories — those reference
-- raw non-atlas materials that crash on the borrowed renderer (see the rows section
-- below). Borrowed renderer => same atlas, so all atlas-backed textures resolve.

local UIWidget = UIWidget
local UIWidgets = UIWidgets

-- The native options definitions: scenegraph + chrome + widget factories.
local OVD = local_require("scripts/ui/views/options_view_definitions")

local WINDOW_WIDTH  = OVD.scenegraph_definition.background.size[1]   -- 1400
local WINDOW_HEIGHT = OVD.scenegraph_definition.background.size[2]   -- 900
local LIST_MASK_W   = OVD.scenegraph_definition.list_mask.size[1]

-- ---------------------------------------------------------------
-- Scenegraph: clone the native one (so panel/frame/panels/list_mask/scrollbar/
-- tab nodes/title/cogwheel/exit all exist + lay out identically), then add our
-- own list anchor nodes under list_mask for the per-mod settings rows.
-- ---------------------------------------------------------------
-- DEEP copy, not shallow: a shallow clone shares the node TABLES with OVD, and our
-- mt_* nodes parent onto OVD nodes (background_top_panel / list_mask). When
-- init_scenegraph runs it attaches our children onto those SHARED OptionsView
-- parent nodes, which then corrupts the real OptionsView/ESC menu after we open
-- (it renders with our foreign children -> the "deprecated buttons" broken look).
-- A deep copy makes every node independent so we can never touch OVD's tables.
local function _deep_copy(t)
    if type(t) ~= "table" then return t end
    local c = {}
    for k, v in pairs(t) do c[k] = _deep_copy(v) end
    return c
end
local scenegraph_definition = _deep_copy(OVD.scenegraph_definition)

-- List container (scrolls) + its top-left anchor the row widgets hang off, the
-- same shape the native build_settings_list injects (parent list_mask).
scenegraph_definition.mt_list = {
    parent = "list_mask",
    horizontal_alignment = "center",
    vertical_alignment = "top",
    position = { 0, 0, -1 },
    offset = { 0, 0, 0 },
    size = { LIST_MASK_W, WINDOW_HEIGHT * 4 },
}
scenegraph_definition.mt_list_start = {
    parent = "mt_list",
    horizontal_alignment = "left",
    vertical_alignment = "top",
    position = { 40, 0, 10 },
    size = { 1, 1 },
}
-- (v0.2.69-dev) Open-dropdown POPUP anchor. SAME origin + parent as mt_list_start
-- (so it inherits the list scroll offset and a popup tracks its collapsed row), but a
-- HIGHER z so the overlay panel draws above the rows. The view draws the popup widget
-- OUTSIDE the row-cull loop, so unlike the rows it is never position-culled/clipped by
-- the list_mask — a dropdown opened near the bottom can extend past the visible list.
scenegraph_definition.mt_dropdown = {
    parent = "mt_list",
    horizontal_alignment = "left",
    vertical_alignment = "top",
    position = { 40, 0, 100 },
    size = { 1, 1 },
}
-- (#207) HOVER INFO POPUP anchor. SAME origin + parent as mt_list_start / mt_dropdown
-- (so it inherits the list scroll offset and the popup tracks its hovered row), but a
-- HIGHER z so the tooltip overlay draws above the rows AND above an open dropdown popup.
-- The view draws the tooltip widget OUTSIDE the row-cull loop, so (like the dropdown) it
-- is never position-culled by the list_mask — a tooltip on a near-bottom row can extend
-- past the visible list / be flipped to draw above its row (see layout_tooltip).
scenegraph_definition.mt_tooltip = {
    parent = "mt_list",
    horizontal_alignment = "left",
    vertical_alignment = "top",
    position = { 40, 0, 200 },
    size = { 1, 1 },
}
-- Vertical scrollbar track.
--
-- (v0.2.74-dev) POSITION ROOT-CAUSE FIX. The bar used to parent to `list_mask` and
-- right-align with a -30 inset. That anchor is WRONG: native `list_mask` is a
-- LEFT-aligned node 1400px wide (== WINDOW_WIDTH) sitting at +18 on the centered
-- background_frame (options_view_definitions.lua:274-287), so its RIGHT edge juts
-- ~18px PAST the decorated panel's right edge. Right-aligning to that off-panel
-- edge made the bar's X depend on a brittle absolute offset that landed it on/over
-- the frame border in the keep sub-state and OFF-PANEL (world x=-12) in the
-- standalone view at menu-origin {0,0} (probe v0.2.73-dev: on_screen anchor
-- inconsistent, x=-12 vs x=1638 across the two presentations).
--
-- Native solves this by parenting its scrollbar (`scrollbar_root`,
-- options_view_definitions.lua:316-329) to `background` right-aligned, NOT to the
-- over-wide list_mask. We do the same: parent to `background_frame` (the visible
-- decorated panel, centered + same 1400x900 size as `background`), right-align with
-- a small inset so the bar sits in the panel's right gutter just inside the frame
-- border, and vertical-center it with the list window's height (list_mask height =
-- WINDOW_HEIGHT-140 = 760) so it spans the same rows the list shows. Because the
-- anchor is now the centered panel frame, the bar's on-screen X is deterministic and
-- identical in BOTH the standalone-view and keep-sub-state presentations regardless
-- of the menu's world position. z high so it's above the rows.
--
-- vertical_alignment="center" (not "top") so the bar centers on the panel exactly
-- like list_mask; the thumb's downward travel is handled in the offset_function
-- (negative Y as scroll 0->1), unaffected by the node's own alignment.
local _LIST_WINDOW_H = OVD.scenegraph_definition.list_mask.size[2]
scenegraph_definition.mt_scrollbar = {
    parent = "background_frame",
    horizontal_alignment = "right",
    vertical_alignment = "center",
    -- -12 X: ~2px gutter past the 10px-wide bar keeps the whole bar just inside the
    -- visible right edge (frame right edge -> bar right edge ~12px in).
    position = { -12, 0, 50 },
    size = { 10, _LIST_WINDOW_H },
}
-- (#497) SEARCH BAND. Reserve a fixed strip at the TOP of the list window for the per-tab
-- search bar (mt_search + create_search_box below). The bar is fixed chrome (does NOT scroll)
-- sitting OUTSIDE and ABOVE the settings list, flush with the row-content width. To open the
-- strip we SHRINK the list window (list_mask) by SEARCH_BAND_H and nudge its centre DOWN by
-- half that, so its TOP edge drops by SEARCH_BAND_H while its BOTTOM stays put; the scrollbar
-- (also centre-anchored on background_frame, its track_h read at factory-call time) is shrunk
-- + shifted identically so it still spans the list. list_mask stays CENTRE-aligned -- the row
-- cull in _draw reads its live world-pos/size (alignment-correct either way), so we only
-- resize + offset it, never re-anchor it. The mt_search NODE is added lower (after ROW_W).
local SEARCH_BAND_H = 44
local SEARCH_BOX_H  = 30
scenegraph_definition.list_mask.size[2]        = scenegraph_definition.list_mask.size[2] - SEARCH_BAND_H
scenegraph_definition.list_mask.position[2]    = (scenegraph_definition.list_mask.position[2] or 0) - SEARCH_BAND_H / 2
scenegraph_definition.mt_scrollbar.size[2]     = scenegraph_definition.mt_scrollbar.size[2] - SEARCH_BAND_H
scenegraph_definition.mt_scrollbar.position[2] = (scenegraph_definition.mt_scrollbar.position[2] or 0) - SEARCH_BAND_H / 2
-- v0.2.65-dev: the "MOD TWEAKER" title is GONE entirely (node + factory + draws
-- removed in both twins). Native Options has NO title text in the top band — the
-- tab buttons span the whole band. The earlier band-split (a title in the upper
-- ~24px, tabs in the lower ~26px) was undone: tabs now occupy the FULL 50px band,
-- bottom-aligned +9px off the panel bottom, exactly like native button_pivot
-- (options_view_definitions.lua:204-217). No reserved x-space for a title.
-- (v0.2.149-dev) The bottom "Click a tab to pick a mod..." hint was removed to match the
-- vanilla Options menu (which has no bottom hint). Its `mt_hint` scenegraph node, the
-- `build_hint` factory, and the `_text_widget` helper it used were all deleted.
-- (v0.2.70-dev) APPLY button — bottom-right of the bottom panel. Clones native
-- `apply_button` (options_view_definitions.lua:344-357): parent = background_bottom_panel,
-- right/top aligned, position {-30,-7}, z 5 so it draws over the panel fill.
-- (Fix 2, v0.2.151-dev) WIDTH now TEXT-FIT to vanilla, not the old fixed 150. Vanilla's
-- apply/reset buttons are `_setup_text_button_size`'d — width measured from the label at
-- font 22 (~59 for "APPLY", ~86 for the reset label). Measuring via UIRenderer.text_size
-- is impractical HERE (the scenegraph is built at module-load, before any renderer exists),
-- so we use FIXED tuned widths in design space: APPLY_W=60 ("APPLY" @22), RESET_W=92
-- ("DEFAULT" @22). These feed both the node size AND the widget hotspot/box below so the
-- click zone tracks the visible text.
local APPLY_W = 60
local RESET_W = 92
scenegraph_definition.mt_apply = {
    parent = "background_bottom_panel",
    horizontal_alignment = "right",
    vertical_alignment = "top",
    position = { -30, -7, 5 },
    size = { APPLY_W, 30 },
}
-- (v0.2.148-dev) RESTORE DEFAULTS button — clones native `reset_to_default`
-- (options_view_definitions.lua:358-371; options_view.lua:855-856/981-984), which is
-- parented to the apply button and sits to its LEFT.
-- (Fix 2, v0.2.151-dev) local_position.x = -(apply_width + 50) — the vanilla gap (was the
-- fabricated -(APPLY_W + 20)). Based on the REAL apply width (APPLY_W=60), so the Default
-- button's right edge sits 50px left of Apply's left edge. Text-fit width RESET_W.
scenegraph_definition.mt_reset = {
    parent = "mt_apply",
    horizontal_alignment = "right",
    vertical_alignment = "top",
    position = { -(APPLY_W + 50), 0, 0 },
    size = { RESET_W, 30 },
}
-- (#561) Per-tab Profiles selector. Ten compact numbered buttons occupy the
-- bottom-left; Apply/Default remain on the right. The label and buttons are
-- independent widgets so the active slot can use the native gold highlight.
scenegraph_definition.mt_profiles_label = {
    parent = "background_bottom_panel", horizontal_alignment = "left",
    vertical_alignment = "top", position = { 30, -7, 5 }, size = { 90, 30 },
}
for i = 1, 10 do
    scenegraph_definition["mt_profile_" .. i] = {
        parent = "mt_profiles_label", horizontal_alignment = "right",
        vertical_alignment = "top", position = { 8 + i * 31, 0, 0 }, size = { 28, 30 },
    }
end
-- Horizontal tab strip spanning the FULL top panel (one node per registered mod),
-- matching native Options where the settings_button_N tabs span the whole band off
-- button_pivot (NO title sharing the band). Native metrics (options_view_definitions
-- .lua / options_view.lua):
--   * x0 = 65   -- button_pivot x offset off the panel's left edge (:204-217)
--   * gap = 20  -- inter-tab spacing (options_view.lua:993 adds +20 per tab)
--   * box 30px tall, BOTTOM-aligned, lifted +9px off the panel bottom (button_pivot
--     vertical_alignment="bottom", position offset {65,9}; tab box height 30 :386-525)
-- Native measures each tab's text width and packs tabs tightly (x += text_w + 20);
-- we keep FIXED-width tab nodes (the view binds labels into these slots) — a
-- deliberate simplification of the dynamic-measure layout, noted so it isn't read as
-- a bug. TAB_W is the fixed slot width; the +20 gap between slots matches native.
local TAB_W, TAB_GAP, TAB_X0 = 164, 20, 65
for i = 1, 10 do
    scenegraph_definition["mt_tab_" .. i] = {
        parent = "background_top_panel",
        horizontal_alignment = "left",
        vertical_alignment = "bottom",
        position = { TAB_X0 + (i - 1) * (TAB_W + TAB_GAP), 9, 4 },
        size = { TAB_W, 30 },
    }
end

-- ---------------------------------------------------------------
-- Chrome: build the native window widgets (frame, panels, edges, cogwheel,
-- list_mask) from the native background_widget_definitions, plus the native
-- scrollbar and exit (X) button. Returns an ORDERED list (draw back-to-front).
-- ---------------------------------------------------------------
local CHROME_ORDER = {
    "background",                 -- dark fill
    "background_top_panel",       -- top bar fill
    "background_bottom_panel",    -- bottom bar fill
    "background_top_panel_edge",  -- top divider
    "background_bottom_panel_edge",
    "background_frame",           -- menu_frame_12 border
    "menu_symbol",                -- cogwheel
}

local function build_chrome()
    local out = {}
    for i = 1, #CHROME_ORDER do
        local def = OVD.background_widget_definitions[CHROME_ORDER[i]]
        if def then
            out[#out + 1] = UIWidget.init(def)
        end
    end
    return out
end

local function build_exit_button()
    local def = OVD.button_definitions and OVD.button_definitions.exit_button
    return def and UIWidget.init(def) or nil
end

local function build_scrollbar()
    local def = OVD.scrollbar_definition
    return def and UIWidget.init(def) or nil
end

-- (v0.2.149-dev) `_text_widget` + `build_hint` were removed with the bottom hint — the
-- only consumer. See the mt_hint scenegraph-node note above.

-- A category TAB. Built as our OWN hotspot+text widget rather than
-- UIWidgets.create_text_button: that factory hard-codes `localize = true` +
-- `upper_case = true` on its text styles (ui_widgets.lua create_text_button), and
-- mod names are plain display strings (not loc keys) -> they render as the missing
-- marker "<Tweaker: GUI>". A hand-built text pass with `localize = false` shows the
-- raw label, guaranteed. The view reads content.hotspot for clicks and recolours
-- style.text for the selected tab.
local function create_tab(label, index)
    local sg = "mt_tab_" .. tostring(index)
    if not scenegraph_definition[sg] then
        return nil  -- more tabs than scenegraph nodes; unsupported for now
    end
    return UIWidget.init({
        scenegraph_id = sg,
        element = {
            passes = {
                { pass_type = "hotspot", content_id = "hotspot" },
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { hotspot = {}, text = tostring(label) },
        style = {
            text = {
                font_type = "hell_shark",
                -- (Fix 1, v0.2.151-dev) font 18 (was 22) = the FARMED vanilla title_buttons
                -- (tab) font, dumped live from the real Options menu. DECOUPLED from the
                -- Apply/Default buttons, which the farm shows at 22 (hell_shark apply/reset) —
                -- so tabs = 18 while those buttons stay 22 (see create_apply_button /
                -- create_default_button). The earlier shared 22 rendered the tabs too large.
                font_size = 18,
                horizontal_alignment = "center",
                vertical_alignment = "center",
                -- localize=false stays (mod names are display strings, not loc keys,
                -- so localizing draws the "<missing>" marker). upper_case=true is a
                -- pure render transform — independent of localize — that gives the
                -- native ALL-CAPS tab look (native sets it at ui_widgets.lua:9203).
                localize = false,
                upper_case = true,
                -- (Fix 2) Idle/base color matches the VANILLA options tab (UIWidgets.create_text_button,
                -- ui_widgets.lua:9208): normal tab text = font_button_normal @ 255. The view/state driver
                -- overwrites this per-frame (white when selected/hovered, font_button_normal otherwise —
                -- mirroring the vanilla text/text_hover split), but the base is set to match too.
                text_color = Colors.get_color_table_with_alpha("font_button_normal", 255),
                offset = { 0, 0, 2 },
            },
        },
        offset = { 0, 0, 0 },
    }), sg
end

-- List rows.
--
-- We do NOT reuse OVD.create_checkbox_widget / create_slider_widget: those use
-- RAW (non-atlas) materials -- checkbox_checked / checkbox_unchecked / rect_masked
-- / highlight_texture -- that are absent from the borrowed in-game renderer's Gui,
-- so they crash at ui_passes.lua:134 ("Material 'checkbox_checked' not found in
-- Gui"). Both `checkbox_*` and `rect_masked` are baked .material resources that
-- appear ONLY in options_view_definitions.lua and in no atlas_settings file.
--
-- Instead we assemble rows from things that DO resolve on that renderer:
--   * rect / border passes -- no material lookup at all, and
--   * atlas-backed textures that UIAtlasHelper resolves globally and whose master
--     atlas is resident: `slider_thumb` / `slider_thumb_hover` / `settings_arrow_normal`
--     / `settings_arrow_clicked` (gui_settings_atlas) for the slider thumb + the
--     native inc/dec arrows, and `playerlist_hover` (gui_menus_atlas) for the row
--     hover highlight. (v0.2.58-dev: booleans render as a native ON/OFF stepper
--     switch, NOT a hand-built `matchmaking_checkbox` box, to match the real
--     Options menu.)
-- All rows anchor to mt_list_start and stack downward via base_offset[2].
local LIST_SG  = "mt_list_start"
-- ROW_W = list_width − 100 so the row's right anchor RA = ROW_X + ROW_W lands in the
-- SAME proportions as native (native row content width = list_size_x − 100 = 1300
-- for the 1400 list — STEPPER/SLIDER_WIDGET_SIZE[1], options_view_definitions.lua
-- :1295/:3049/:1564). Was list_width − 80. With ROW_X = 0 (mt_list_start origin),
-- RA = ROW_W, so every arrow/value column below is RA − <native constant>.
local ROW_W    = LIST_MASK_W - 100
-- Gear-button box size. PROMOTED above RA (v0.2.67-dev) so the right-anchor shift below
-- can reserve a gear gutter of (GEAR_SIZE + 24) = 50px. The gear texture is authored at
-- 58px but texture_size rescales it into this 26px box (see create_gear_button).
local GEAR_SIZE = 36
-- Row height tuned toward native. Native settings rows are 30px tall with ZERO
-- inter-row gap (checkbox/slider both 30 — options_view_definitions.lua:1301/1566;
-- rows stack with no padding, options_view.lua:1111). gut was 46 (too tall / too
-- much air). 32 sits just above native 30 to give the 27px-tall arrow textures +
-- slider thumb a hair of margin. Rows already stack with no gap (each factory
-- decrements base_offset[2] by exactly ROW_H), so consecutive separators read as a
-- continuous rule like native. NEEDS IN-GAME EYEBALL: confirm the tighter rows read
-- well and nothing clips at 32px.
local ROW_H    = 32
-- Two-column layout (like the game's settings): the NAME fills the left column
-- [0, control column); every CONTROL (on/off switch, slider track, steppers) lives
-- in the right INPUT_FIELD_WIDTH-wide column.
--
-- Native right-justifies controls by SUBTRACTING the input-field width from the row
-- width (control_x = row_width − INPUT_FIELD_WIDTH = RA − 400), NOT via an alignment
-- flag — options_view_definitions.lua:3 (INPUT_FIELD_WIDTH=400). The per-element
-- arrow/value/track columns derive from this and are defined as the right-anchored
-- constants (DEC_ARROW_X / INC_ARROW_X_* / VALUE_X_* / SLIDER_TRACK_*) below the
-- arrow-texture block, shared identically by the stepper and slider factories so
-- every row's columns line up.
local INPUT_FIELD_WIDTH = 400

-- Per-row bottom separator (native "bottom_edge"): a faint full-width 2px rule at
-- the row's bottom, drawn as a plain `rect` pass (NEVER the native `rect_masked`
-- material — it's absent from the borrowed renderer and crashes; see the
-- raw-materials note above). Color/thickness mirror BOTTOM_EDGE_COLOR /
-- BOTTOM_EDGE_THICKNESS (options_view_definitions.lua:25-26): font_default @ alpha 50.
local SEP_THICKNESS = 2
local SEP_COLOR     = Colors.get_color_table_with_alpha("font_default", 50)

-- Native inc/dec arrows are TEXTURES, not "<"/">" glyphs: settings_arrow_normal
-- (idle) / settings_arrow_clicked (hover), both atlas sprites in gui_settings_atlas
-- (19x27, gui_settings_atlas.lua:116/410). The RIGHT arrow is the SAME texture
-- flipped horizontally via a texture_uv pass with uvs {{1,0},{0,1}}
-- (options_view_definitions.lua:1811-1819 / content.arrow.uvs :1920-1929).
local ARROW_NORMAL  = "settings_arrow_normal"
local ARROW_CLICKED = "settings_arrow_clicked"
local ARROW_W, ARROW_H = 19, 27
local FLIP_UVS = { { 1, 0 }, { 0, 1 } }

-- NATIVE-ANCHORED ARROW + VALUE COLUMNS (single source of truth for BOTH the on/off
-- stepper (create_checkbox) AND the slider (create_slider), so every row's arrows
-- line up flush down the whole column). All x are RA − <native constant>, where the
-- right anchor RA = ROW_X + ROW_W and ROW_X = 0 (mt_list_start origin), so RA = ROW_W.
-- Native (options_view_definitions.lua), arrow box 19×27, INPUT_FIELD_WIDTH = 400:
--   * decrement (left) arrow  = RA − 400  -- IDENTICAL column for stepper + slider
--                                            (stepper :3404-3415, slider :2193-2205)
--   * increment (right) arrow:
--       stepper = RA − 19   (flush right)               (:3446-3457)
--       slider  = RA − 71   (= RA−19−52, 52px inboard to clear its value box) (:2235-2251)
--   * value text (centered in its column):
--       stepper = RA − 200  (RA − INPUT_FIELD_WIDTH/2)  (:3503-3512)
--       slider  = RA − 25   (centered in the 50px box at RA − 50) (:2087-2119)
--   * slider track/fill box: x = RA − 400 + 30, width = INPUT_FIELD_WIDTH − 112 = 288,
--     height 10 (:2004-2013) — sits in the input-field column so the dec arrow (RA−400)
--     and inc arrow (RA−71) bracket it exactly as native.
-- Native does NOT share the increment column between steppers and sliders — only the
-- DECREMENT arrows align flush; within a type each increment arrow shares its column
-- (two columns 52px apart, by design — forcing them equal collides the slider value box).
-- (v0.2.67-dev) RA recedes 50px from the true row right edge so the gear button keeps
-- its own right-edge gutter. Previously RA = ROW_W put the stepper inc arrow at ROW_W−19,
-- colliding with the gear at ROW_W−36. Shifting every RA-derived column left by
-- (GEAR_SIZE+24)=50 opens a clean gutter where the gear lives alone. Applied
-- UNCONDITIONALLY (every row, gear-bearing or not) so all control columns stay aligned.
local RA            = ROW_W - (GEAR_SIZE + 24)     -- = ROW_W − 50 (was ROW_W); gear gutter
local DEC_ARROW_X   = RA - INPUT_FIELD_WIDTH       -- RA − 400, both stepper & slider
local INC_ARROW_X_STEPPER = RA - ARROW_W           -- RA − 19, flush right
local INC_ARROW_X_SLIDER  = RA - ARROW_W - 52      -- RA − 71, 52px inboard
local VALUE_X_STEPPER = RA - INPUT_FIELD_WIDTH / 2 -- RA − 200, centered in its column
local SLIDER_VALUE_W  = 50                          -- native slider value box (RA−50..RA)
local VALUE_X_SLIDER  = RA - SLIDER_VALUE_W / 2     -- RA − 25, centered in the 50px box
-- Slider track/fill box (input-field column).
local SLIDER_TRACK_X  = DEC_ARROW_X + 30            -- RA − 400 + 30
local SLIDER_TRACK_W  = INPUT_FIELD_WIDTH - 112     -- 288
-- Native stepper hotspots are INPUT_FIELD_WIDTH/2 = 200 wide (left hotspot at RA−400,
-- right hotspot at RA−200) for native click feel (:3435-3444, :3477-3487).
local ARROW_HOTSPOT_W = INPUT_FIELD_WIDTH / 2       -- 200
-- (v0.2.67-dev) Per-depth LEADING indent for nested child rows. Added to the LEFT label
-- x only (never the right-anchored arrow/value/track/gear columns, which stay column-
-- aligned). The view threads a 0-based `depth` into each factory; ind = INDENT_PER_DEPTH
-- * depth. Each label's clamp width is also narrowed by `ind` so an indented label still
-- terminates before the controls.
local INDENT_PER_DEPTH = 24
-- (#206) Shared LEFT label x for every non-chevron row (checkbox / slider / numeric /
-- stepper / dropdown / section title), so rows of DIFFERENT widget types left-align at a
-- given depth. Previously the base x was hard-coded per factory (checkbox & dropdown 12,
-- slider & section title 0), so toggles and dropdowns sat 12px right of sliders/titles at
-- the same depth -- the reported "indent on toggles". Collapsible GROUP HEADERS are exempt:
-- their label intentionally clears the +/- chevron column (tree-style), see create_group_header.
local LABEL_BASE_X = 12

local function _text_style(x, y, w, size, color, halign)
    return {
        font_type = "hell_shark",
        font_size = size or 22,
        horizontal_alignment = halign or "left",
        vertical_alignment = "center",
        localize = false,
        -- (Fix 1, v0.2.149-dev) ALL-CAPS to match the vanilla Options menu, which renders
        -- every row label / value upper-case. This single point covers every row label built
        -- through _text_style — checkbox / slider / numeric / dropdown / section-title /
        -- group-header labels, the dropdown value + option list, and the back-row label.
        -- (ON/OFF words + the numeric slider value are already caps / digits, so it's a no-op
        -- there.) The tooltip popup builds its OWN styles (create_tooltip_popup) and is NOT
        -- routed through here, so its description prose stays normal case.
        upper_case = true,
        text_color = color or Colors.get_color_table_with_alpha("font_default", 255),
        offset = { x, y, 3 },
        size = { w, ROW_H },
    }
end

-- Append a full-width bottom-edge separator pass + style to a row. The view sets
-- nothing on it; it draws every frame. `y` is the row's offset Y (base_offset[2]
-- after the factory decremented it). Row content occupies [y, y+ROW_H] in offset
-- space (offset adds to the list anchor, +Y is up), so the row's BOTTOM edge is at
-- y; the next row decrements to y-ROW_H. We draw the 2px rule flush at y so
-- consecutive rows' separators read as one continuous ruled list (native stacks
-- rows with no gap — options_view.lua:1111).
local function _append_separator(passes, style, y)
    passes[#passes + 1] = { pass_type = "rect", style_id = "separator" }
    style.separator = { offset = { 0, y, 1 }, size = { ROW_W, SEP_THICKNESS }, color = SEP_COLOR }
end

-- #605: one compact Character Dialogue event row.  The three controls are in
-- the same logical/rendered row so preview ownership and line state are never
-- detached from the event they affect.  Only the virtual window creates these.
local function create_dialogue_row(text, state_text, base_offset, depth)
    local y = base_offset[2] - ROW_H
    base_offset[2] = y
    local ind = INDENT_PER_DEPTH * (depth or 0)
    local pause_w, play_w, state_w, gap = 88, 72, 104, 8
    local pause_x = ROW_W - pause_w - 10
    local play_x = pause_x - play_w - gap
    local state_x = play_x - state_w - gap
    local label_x = LABEL_BASE_X + ind
    local label_w = math.max(80, state_x - label_x - 12)
    local button_color = { 220, 12, 12, 12 }
    local border_color = { 180, 90, 90, 90 }
    local text_color = Colors.get_color_table_with_alpha("font_button_normal", 255)
    local passes = {
        { pass_type = "hotspot", content_id = "state_hotspot", style_id = "state_hotspot" },
        { pass_type = "hotspot", content_id = "play_hotspot", style_id = "play_hotspot" },
        { pass_type = "hotspot", content_id = "pause_hotspot", style_id = "pause_hotspot" },
        { pass_type = "text", style_id = "label", text_id = "label" },
        { pass_type = "rect", style_id = "state_bg" },
        { pass_type = "border", style_id = "state_border" },
        { pass_type = "text", style_id = "state_text", text_id = "state_text" },
        { pass_type = "rect", style_id = "play_bg" },
        { pass_type = "border", style_id = "play_border" },
        { pass_type = "text", style_id = "play_text", text_id = "play_text" },
        { pass_type = "rect", style_id = "pause_bg" },
        { pass_type = "border", style_id = "pause_border" },
        { pass_type = "text", style_id = "pause_text", text_id = "pause_text" },
    }
    local content = {
        state_hotspot = {}, play_hotspot = {}, pause_hotspot = {},
        label = tostring(text), state_text = tostring(state_text or "DEFAULT"),
        play_text = "PLAY", pause_text = "PAUSE",
    }
    local function box(x, w, z, color)
        return { offset = { x, y + 3, z or 2 }, size = { w, ROW_H - 6 }, color = color }
    end
    local function button_text(x, w)
        local s = _text_style(x, y, w, 16, text_color, "center")
        s.upper_case = true
        return s
    end
    local style = {
        label = _text_style(label_x, y, label_w, 17, Colors.get_color_table_with_alpha("font_default", 255)),
        state_hotspot = box(state_x, state_w, 8), play_hotspot = box(play_x, play_w, 8),
        pause_hotspot = box(pause_x, pause_w, 8),
        state_bg = box(state_x, state_w, 2, button_color), state_border = box(state_x, state_w, 3, border_color),
        state_text = button_text(state_x, state_w),
        play_bg = box(play_x, play_w, 2, button_color), play_border = box(play_x, play_w, 3, border_color),
        play_text = button_text(play_x, play_w),
        pause_bg = box(pause_x, pause_w, 2, button_color), pause_border = box(pause_x, pause_w, 3, border_color),
        pause_text = button_text(pause_x, pause_w),
    }
    style.state_border.thickness, style.play_border.thickness, style.pause_border.thickness = 1, 1, 1
    _append_separator(passes, style, y)
    return UIWidget.init({
        scenegraph_id = LIST_SG, element = { passes = passes }, content = content,
        style = style, offset = { 0, 0, 0 },
    })
end

-- Prepend a whole-row hover highlight pass (atlas-backed "playerlist_hover" in
-- gui_menus_atlas — drawn ONLY when content.is_highlighted, which the view sets
-- from the row hotspot's is_hover each frame). Inserted at the FRONT of the pass
-- list so in immediate mode it paints UNDER the row's text/controls (z-offset
-- doesn't layer within one immediate-mode widget; draw ORDER does). NEVER the raw
-- `highlight_texture` material (absent on this renderer); "playerlist_hover" is an
-- atlas sprite proven on the borrowed renderer.
local function _append_highlight(passes, style, content, y)
    table.insert(passes, 1, {
        pass_type = "texture", style_id = "highlight", texture_id = "highlight_texture",
        content_check_function = function(c) return c.is_highlighted end,
    })
    content.highlight_texture = "playerlist_hover"
    content.is_highlighted = false
    -- Alpha was 70 (far too dim vs native). Native draws the "playerlist_hover"
    -- row highlight at full alpha when the row is highlighted (it's a soft sprite,
    -- so 255 reads as a gentle glow, not a hard fill) — match that. NEEDS IN-GAME
    -- EYEBALL: confirm the brightness reads like the native Options-menu hover.
    style.highlight = { offset = { 0, y + 2, 0 }, size = { ROW_W, ROW_H - 4 },
        color = { 255, 255, 255, 255 } }
    -- (row highlight) Full-row HOVER hotspot so the bar lights up when the cursor is anywhere on the
    -- row, not just over the control. Dropdown/slider/keybind rows only have a PARTIAL control hotspot
    -- (input box / track), so hovering their LABEL never set is_hover. Hover-ONLY: the view reads
    -- row_hs.is_hover for the highlight and never its on_release, so it can't steal the control clicks.
    passes[#passes + 1] = { pass_type = "hotspot", content_id = "row_hs", style_id = "row_hs" }
    content.row_hs = {}
    style.row_hs = { size = { ROW_W, ROW_H }, offset = { 0, y, 0 } }
end

-- Append the native texture-arrow pair (left + flipped right) for one stepper/
-- slider. Each arrow has its OWN content sub-table so the texture_uv pass can read
-- the flip uvs off it (ui_passes.lua:165 reads ui_content.uvs). `dec_x`/`inc_x`
-- are the left edges of the left/right arrow textures; `cy` is the row centre-Y.
--
-- (#92 corrected — match the VANILLA GAME SETTINGS menu, not VMF.) The prior fix
-- mirrored the VMF favourite-arrow ramp (one base arrow whose alpha rises 130->255),
-- which dimmed the arrows at REST — wrong. The real Options menu stepper
-- (create_stepper_widget, options_view_definitions.lua:3054) draws each inc/dec arrow
-- as TWO sprites:
--   * BASE idle sprite `settings_arrow_normal` at FULL alpha (font_default, 255):
--       left_arrow  :3404-3415 / right_arrow :3446-3457 (color = ...font_default,255).
--   * a separate HOVER overlay sprite `settings_arrow_clicked` seeded color
--       {0,255,255,255} = ALPHA 0 (invisible) at rest (left_arrow_hover :3417-3433 /
--       right_arrow_hover :3459-3475), faded UP to alpha 255 on hover and back to 0 on
--       de-hover by OptionsView.on_stepper_arrow_hover / _dehover (options_view.lua:
--       4335-4369), which animate pass_style.color[1] (the alpha) over
--       UISettings.scoreboard.topic_hover_duration.
-- So: idle = base sprite FULL, no dim; glow = the brighter `_clicked` overlay sprite
-- fading IN over the base. We replicate that exactly here — the base arrows stay at
-- full alpha, and a `_clicked` overlay per side ramps its OWN alpha 0->255 from the
-- dec/inc hotspot's is_hover inside the local_offset offset_function (our per-frame
-- stand-in for the native time-animation; the alpha endpoints are identical).
-- offset_function MUST live on a local_offset pass — only those run every frame
-- (memory reference_vt2_offset_function_local_offset_only); a texture pass's own
-- offset_function is ignored.
local ARROW_ALPHA_IDLE_BASE  = 255     -- base settings_arrow_normal: FULL at rest (native :3415/:3457)
-- Base sprite RGB TINT. Native draws the base arrow at {255,181,181,181} (grey), NOT white —
-- captured live 2026-06-25 (gut_dev v0.2.93 glow probe, [gut-glow-probe] NATIVE). Drawing the
-- base white (255) killed the hover glow: the white _clicked overlay fading in over a white base
-- = zero brightness contrast, so the glow was invisible (#92 arrows / #99 dropdown).
local ARROW_RGB_IDLE_BASE    = 181
local ARROW_OVERLAY_IDLE     = 0       -- _clicked overlay alpha at rest (native seed {0,255,255,255})
local ARROW_OVERLAY_HOVER    = 255     -- _clicked overlay alpha on hover (native ramps to 255)

local function _append_arrows(passes, style, content, dec_x, inc_x, cy)
    -- LEFT base arrow: normal sprite, full alpha, always drawn (native left_arrow).
    passes[#passes + 1] = {
        pass_type = "texture", style_id = "left_arrow", texture_id = "texture_id", content_id = "left_arrow",
    }
    -- RIGHT base arrow: same sprite flipped via texture_uv, full alpha (native right_arrow).
    passes[#passes + 1] = {
        pass_type = "texture_uv", style_id = "right_arrow", texture_id = "texture_id", content_id = "right_arrow",
    }
    -- LEFT hover overlay: _clicked sprite, alpha 0 at rest -> 255 on hover (native left_arrow_hover).
    passes[#passes + 1] = {
        pass_type = "texture", style_id = "left_arrow_hover", texture_id = "texture_id", content_id = "left_arrow_hover",
    }
    -- RIGHT hover overlay: _clicked sprite flipped, alpha 0 -> 255 on hover (native right_arrow_hover).
    passes[#passes + 1] = {
        pass_type = "texture_uv", style_id = "right_arrow_hover", texture_id = "texture_id", content_id = "right_arrow_hover",
    }
    content.left_arrow        = { texture_id = ARROW_NORMAL }
    content.right_arrow       = { texture_id = ARROW_NORMAL,  uvs = FLIP_UVS }
    content.left_arrow_hover  = { texture_id = ARROW_CLICKED }
    content.right_arrow_hover = { texture_id = ARROW_CLICKED, uvs = FLIP_UVS }
    local ay = cy - ARROW_H / 2
    -- Base arrows: FULL alpha, native GREY tint (181), NOT white — the white _clicked overlay
    -- needs a dimmer base to read as a glow (#92/#99, ground truth 2026-06-25). Overlays: alpha 0.
    style.left_arrow        = { texture_size = { ARROW_W, ARROW_H }, offset = { dec_x, ay, 4 }, color = { ARROW_ALPHA_IDLE_BASE, ARROW_RGB_IDLE_BASE, ARROW_RGB_IDLE_BASE, ARROW_RGB_IDLE_BASE } }
    style.right_arrow       = { texture_size = { ARROW_W, ARROW_H }, offset = { inc_x, ay, 4 }, color = { ARROW_ALPHA_IDLE_BASE, ARROW_RGB_IDLE_BASE, ARROW_RGB_IDLE_BASE, ARROW_RGB_IDLE_BASE } }
    -- (#92/#99) HOVER overlay is the BIGGER _clicked sprite. Ground truth from the vanilla
    -- slider (options_view_definitions.lua): left_arrow_hover :2206-2216 draws settings_arrow_clicked
    -- at size 30x35 (NOT the 19x27 base), offset base +6 x / -4 y; right_arrow_hover :2252-2259 at
    -- 30x35, offset base -16 x / -4 y. gut was drawing the overlay at 19x27 at the base position —
    -- too small + mispositioned (#92/#99 "arrows look wrong"). ay = cy - 13.5; -4 => cy - 17.5.
    style.left_arrow_hover  = { texture_size = { 30, 35 }, offset = { dec_x + 6,  ay - 4, 5 }, color = { ARROW_OVERLAY_IDLE, 255, 255, 255 } }
    style.right_arrow_hover = { texture_size = { 30, 35 }, offset = { inc_x - 16, ay - 4, 5 }, color = { ARROW_OVERLAY_IDLE, 255, 255, 255 } }

    -- One local_offset pass ramps each _clicked OVERLAY's alpha from its own hotspot's
    -- is_hover (dec -> left, inc -> right). The base arrows are NEVER touched (they stay
    -- full alpha). This is the native two-sprite hover-overlay scheme: glow = the brighter
    -- _clicked sprite fading in over the still-visible base (options_view.lua:4335-4369).
    passes[#passes + 1] = {
        pass_type = "local_offset",
        offset_function = function(_, ui_style, ui_content)
            -- (#92/#99) FADE the _clicked overlay in/out toward its hover target instead of a
            -- hard 0<->255 pop, matching the native gradual hover glow. Ease ~30%/frame toward
            -- the target, snapping when within 4. dec hotspot -> left overlay, inc -> right.
            local dec_hover = ui_content.dec and ui_content.dec.is_hover
            local inc_hover = ui_content.inc and ui_content.inc.is_hover
            if ui_style.left_arrow_hover then
                local c = ui_style.left_arrow_hover.color
                local t = dec_hover and ARROW_OVERLAY_HOVER or ARROW_OVERLAY_IDLE
                local d = t - (c[1] or 0)
                c[1] = (math.abs(d) < 4) and t or ((c[1] or 0) + d * 0.3)
            end
            if ui_style.right_arrow_hover then
                local c = ui_style.right_arrow_hover.color
                local t = inc_hover and ARROW_OVERLAY_HOVER or ARROW_OVERLAY_IDLE
                local d = t - (c[1] or 0)
                c[1] = (math.abs(d) < 4) and t or ((c[1] or 0) + d * 0.3)
            end
        end,
    }
end

-- Boolean ON/OFF SWITCH (native settings booleans are STEPPERS, not checkboxes —
-- options_view_settings.lua:456-468). Renders as: label (left column) + centered
-- ON/OFF text in the right column flanked by the two native arrow textures. The
-- whole-row hotspot still toggles content.flag (the view flips it on
-- on_left_release); either arrow is an alternate hit zone over the same hotspot.
-- The ON/OFF strings come from the game's own loc keys so they match exactly.
-- Two text passes (ON gated on flag, OFF gated on not-flag) avoid the view having
-- to recompute value_text — the displayed word follows content.flag automatically.
local function _on_off_text()
    -- Keep the game's localized "ON"/"OFF" only when it resolves cleanly; reject a
    -- "<missing-key>" marker (same guard as _vmf_label) and fall back to literals.
    local function _loc(key, fallback)
        local ok, s = pcall(Localize, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then return s end
        return fallback
    end
    return _loc("menu_settings_on", "ON"), _loc("menu_settings_off", "OFF")
end

local function create_checkbox(text, base_offset, depth)
    local y = base_offset[2] - ROW_H
    base_offset[2] = y
    local cy = y + ROW_H / 2
    local ind = INDENT_PER_DEPTH * (depth or 0)   -- LEFT label only; controls stay at RA
    -- Native ON/OFF stepper columns (shared with create_slider's left arrow so every
    -- row's decrement arrow lines up flush): [<] at DEC_ARROW_X (RA−400), value
    -- centered at VALUE_X_STEPPER (RA−200), [>] flush right at INC_ARROW_X_STEPPER
    -- (RA−19). The ON/OFF word (val_w wide) is centered on the value column.
    local val_w = 90
    local dec_x = DEC_ARROW_X                                  -- left arrow, RA−400
    local inc_x = INC_ARROW_X_STEPPER                          -- right arrow, RA−19
    local val_x = VALUE_X_STEPPER - val_w / 2                  -- centered on RA−200
    local on_txt, off_txt = _on_off_text()

    local passes = {
        -- style_id REQUIRED on the hotspot: all rows share mt_list_start (size {1,1}),
        -- so without an explicit style.hotspot size the hit target collapses to 1x1.
        { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
        { pass_type = "text", style_id = "label", text_id = "label" },
        { pass_type = "text", style_id = "on_text",  text_id = "on_text",
          content_check_function = function(c) return c.flag end },
        { pass_type = "text", style_id = "off_text", text_id = "off_text",
          content_check_function = function(c) return not c.flag end },
    }
    local style = {
        hotspot  = { size = { ROW_W, ROW_H }, offset = { 0, y, 0 } },
        -- (Fix 1, v0.2.151-dev) Label font 16 (was 28). The FARMED vanilla option-row label
        -- (dumped live from the real Options menu, hell_shark_masked, 16, upper_case, NOT
        -- dynamic) is 16 — booleans render as a STEPPER here, and every vanilla option row
        -- (checkbox/slider/dropdown) uses the same 16 label. The earlier 28 (from the
        -- create_checkbox_widget decompiled literal) rendered far too large once the global
        -- RESOLUTION_LOOKUP.scale doubled it. hell_shark (unmasked) here vs native
        -- hell_shark_masked, but the size matches. ON/OFF value text dropped 18 -> 16 to
        -- stay <= the label size.
        label    = _text_style(LABEL_BASE_X + ind, y, DEC_ARROW_X - LABEL_BASE_X - 12 - ind, 16),
        on_text  = _text_style(val_x, y, val_w, 16,
                     Colors.get_color_table_with_alpha("font_default", 255), "center"),
        off_text = _text_style(val_x, y, val_w, 16,
                     Colors.get_color_table_with_alpha("font_default", 255), "center"),
    }
    local content = {
        flag = false, hotspot = {}, label = text,
        on_text = on_txt, off_text = off_txt,
        -- dec/inc hotspots = the two arrow hit zones (alternate toggles).
        dec = {}, inc = {},
    }
    -- Arrow hit zones (the view treats either as a toggle). Native stepper hotspots
    -- are INPUT_FIELD_WIDTH/2 = 200 wide: left hotspot at DEC_ARROW_X (RA−400), right
    -- hotspot at VALUE_X_STEPPER (RA−200) (options_view_definitions.lua:3435-3444 /
    -- :3477-3487). Sized to native for the real click feel.
    passes[#passes + 1] = { pass_type = "hotspot", content_id = "dec", style_id = "dec" }
    passes[#passes + 1] = { pass_type = "hotspot", content_id = "inc", style_id = "inc" }
    style.dec = { size = { ARROW_HOTSPOT_W, ROW_H }, offset = { DEC_ARROW_X, y, 0 } }
    style.inc = { size = { ARROW_HOTSPOT_W, ROW_H }, offset = { VALUE_X_STEPPER, y, 0 } }
    _append_arrows(passes, style, content, dec_x, inc_x, cy)
    _append_highlight(passes, style, content, y)
    _append_separator(passes, style, y)

    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- Slider/numeric/dropdown: label + rect track + rect fill (proportion) + atlas
-- thumb that TRACKS internal_value + native texture arrows ([<]/[>] textures, the
-- right one flipped) + value text. The view adjusts content.value on
-- dec/inc.on_release and drags content.internal_value on the track; the fill width
-- and thumb x recompute every frame via offset_function from internal_value.
--
-- THUMB SIZE = slider_thumb's native atlas size 14x27 (gui_settings_atlas.lua:102).
local THUMB_W, THUMB_H = 14, 27
-- (v0.2.71-dev) NATIVE HOVER-GLOW thumb = slider_thumb_hover's native atlas size 34x25
-- (gui_settings_atlas.lua:396). It's a WIDER, glowing variant of the base thumb drawn
-- ON TOP only while hovering — the "glow" the native options slider shows. Both atlas
-- sprites (slider_thumb / slider_thumb_hover) live in the resident gui_settings_atlas,
-- so they resolve on the borrowed renderer (memory reference_vt2_options_widgets_raw_
-- materials greenlights both). gut previously sized thumb_hover at the base 14x27 (so it
-- was an invisible same-size overlay, not the glow). Native centers the wider glow on the
-- base thumb and drops Y by 1px (options_view_definitions.lua:1688-1695 / :2062-2073);
-- masked=false because the borrowed renderer has no stencil and the sprite is fully
-- contained in its UV rect.
local THUMB_HOVER_W, THUMB_HOVER_H = 34, 25
-- Measure a value with the exact path UIPasses.text uses: UIFontByResolution
-- supplies the scaled size/material and the style's font_type is forwarded as
-- font_name. UIRenderer.text_size returns design-space width plus the glyph
-- origin used by the native centered-alignment formula (ui_passes.lua:1964-1990,
-- 2177-2181; ui_renderer.lua:1254-1260).
local function _measure_value(renderer, value_style, text)
    if not renderer or not value_style then return nil end
    local ok_font, font, scaled_size = pcall(UIFontByResolution, value_style)
    if not ok_font or type(font) ~= "table" then return nil end
    local ok, width, _, origin = pcall(UIRenderer.text_size, renderer,
        tostring(text or ""), font[1], scaled_size, value_style.font_type)
    if not ok or type(width) ~= "number" then return nil end
    return width, origin and origin.x or 0
end

local function numeric_caret_x(renderer, value_style, text, box_w, caret_idx)
    local full_width, origin_x = _measure_value(renderer, value_style, text)
    if not full_width then return nil end
    local idx = math.clamp(caret_idx or #text, 0, #text)
    local prefix_width = _measure_value(renderer, value_style, string.sub(text, 1, idx))
    if not prefix_width then return nil end
    return NumericEditor.caret_x(value_style.offset[1], box_w, full_width, origin_x, prefix_width)
end

local function numeric_caret_index(renderer, value_style, text, box_w, click_x)
    local full_width, origin_x = _measure_value(renderer, value_style, text)
    if not full_width then return nil end
    local text_left = NumericEditor.centered_text_left(
        value_style.offset[1], box_w, full_width, origin_x)
    local advances = {}
    for idx = 0, #text do
        local width = _measure_value(renderer, value_style, string.sub(text, 1, idx))
        if not width then return nil end
        advances[idx + 1] = width
    end
    return NumericEditor.nearest_index(click_x, text_left, advances)
end

local function create_slider(text, tooltip, base_offset, depth)
    local y  = base_offset[2] - ROW_H
    base_offset[2] = y
    local cy = y + ROW_H / 2
    local ind = INDENT_PER_DEPTH * (depth or 0)   -- LEFT label only; controls stay at RA
    -- NATIVE right-anchored columns (shared with create_checkbox's decrement arrow so
    -- every row's [<] lines up flush). The track sits in the input-field column; the
    -- [<] arrow at DEC_ARROW_X (RA−400) brackets its left, the [>] arrow at
    -- INC_ARROW_X_SLIDER (RA−71, 52px inboard of the stepper's RA−19 to clear the value
    -- box), and the value text centered at VALUE_X_SLIDER (RA−25). These are constants
    -- across every slider row, so all arrows + tracks + values column-justify.
    local track_x = SLIDER_TRACK_X                     -- RA − 400 + 30 = 930
    local track_w = SLIDER_TRACK_W                     -- INPUT_FIELD_WIDTH − 112 = 288
    local dec_x = DEC_ARROW_X                           -- [<] RA−400 (flush w/ stepper)
    local inc_x = INC_ARROW_X_SLIDER                    -- [>] RA−71
    local val_x = VALUE_X_SLIDER - SLIDER_VALUE_W / 2   -- value box left (RA−50); text centered in it

    local passes = {
        { pass_type = "text", style_id = "label", text_id = "label" },
        { pass_type = "rect", style_id = "track" },
        -- (v0.2.67-dev) The yellow `fill` pass was DELETED here — native sliders have no
        -- growing colored fill; only the thumb conveys position over the flat dark track.
        -- POSITION DRIVER (the fix for "thumb doesn't move", build 4). A `local_offset`
        -- pass is the ONLY pass type whose draw body invokes `offset_function`
        -- (ui_passes.lua:4587-4593 — `UIPasses.local_offset.draw` is literally just
        -- `pass_definition.offset_function(...)`). The generic widget draw loop
        -- (ui_renderer.lua:521-555) reads `pass_style.offset` to place each pass but
        -- NEVER calls `offset_function` for `texture`/`rect`/`texture_uv` passes — so
        -- the prior per-pass offset_functions on the thumb/fill/thumb_hover were silently
        -- ignored, leaving the fill at width 0 and the thumb pinned at value 0. This is
        -- the exact native slider mechanism (options_view_definitions.lua:1673-1695): one
        -- local_offset pass mutates the OTHER passes' styles in place every frame. The
        -- offset_function here gets the WHOLE widget ui_style, so it indexes by style_id.
        {
            pass_type = "local_offset",
            offset_function = function(_, ui_style, ui_content)
                local iv = math.clamp(ui_content.internal_value or 0, 0, 1)
                -- Read the track geometry from content (set below to the native slider
                -- track column) so the thumb/fill track exactly what's rendered and what
                -- the view's drag math (which reads content.track_x/track_w) uses.
                local tx = ui_content.track_x or SLIDER_TRACK_X
                local tw = ui_content.track_w or SLIDER_TRACK_W
                local thumb_x = tx + tw * iv - THUMB_W / 2
                -- v0.2.67-dev: no growing fill anymore (native sliders have none — only the
                -- thumb conveys position over a flat dark track). The thumb + hover-thumb
                -- slide along the track from internal_value.
                if ui_style.thumb then ui_style.thumb.offset[1] = thumb_x end
                -- (v0.2.71-dev) Center the WIDER native glow (34px) on the base thumb (14px):
                -- glow_left = thumb_left + THUMB_W/2 - THUMB_HOVER_W/2 (native re-centering,
                -- options_view_definitions.lua:1688-1695). thumb_x is the base thumb's left.
                if ui_style.thumb_hover then
                    ui_style.thumb_hover.offset[1] = thumb_x + THUMB_W / 2 - THUMB_HOVER_W / 2
                end
                -- TYPE-TO-EDIT caret (v0.2.66-dev). While ui_content.editing, position a
                -- thin caret bar just right of the typed string + pulse its alpha. This
                -- runs in the local_offset pass because it ALREADY has the renderer-free
                -- frame hook AND the per-widget style table (texture/rect passes ignore
                -- their own offset_function — same mechanism as the thumb above). The
                -- caret x is computed from the rendered text width via UIRenderer.text_size
                -- so it sits at the end of the value text (which is centered in the value
                -- box at val_x..val_x+SLIDER_VALUE_W). Mirrors VMF's caret math
                -- (vmf_options_view.lua:4524-4529): text_offset = box_center − text_w/2,
                -- caret = text_offset + text_w − 3.
                if ui_style.caret then
                    if ui_content.editing then
                        ui_style.caret.color[1] = 0  -- hidden until we can measure (set below)
                        local r = ui_content._caret_renderer
                        if r then
                            local vs = ui_style.value
                            local s = tostring(ui_content.value_text or "")
                            -- #575: use the exact native font resolution + centered
                            -- glyph-origin formula. This remains correct across UI
                            -- scale, signs, decimal points, and proportional digits.
                            local idx = math.clamp(ui_content.caret_idx or #s, 0, #s)
                            local caret_x = numeric_caret_x(r, vs, s,
                                ui_content._caret_box_w or 64, idx)
                            if caret_x then ui_style.caret.offset[1] = caret_x end
                            -- Pulse alpha (math.sirp ping-pongs 0..1; *255 -> alpha). caret_t
                            -- is advanced by the view each frame it's editing.
                            local a = math.sirp(0, 0.85, (ui_content.caret_t or 0) * 1.5) * 255
                            ui_style.caret.color[1] = a
                        end
                    else
                        ui_style.caret.color[1] = 0  -- fully transparent when not editing
                    end
                end
                -- FOCUS background: a faint highlight behind the value box while editing,
                -- so the user can see which field has keyboard focus.
                if ui_style.value_focus_bg then
                    ui_style.value_focus_bg.color[1] = ui_content.editing and 90 or 0
                end
                -- DEBUG PROBE (gated): logs internal_value, the computed thumb offset[1],
                -- and whether the slider_thumb texture is set — so if the thumb still
                -- doesn't move in-game, the log pins the cause (bad internal_value vs.
                -- offset not applied vs. texture unresolved). Throttled to ~1/sec via a
                -- per-widget frame counter so it can't flood the log on every draw frame.
                ui_content._probe_n = (ui_content._probe_n or 0) + 1
                if ui_content._probe_n % 60 == 1 then
                    mod:debug("[mt:slider-probe] internal=%.3f thumb_off_x=%.1f thumb_tex=%s",
                        iv, thumb_x, tostring(ui_content.thumb))
                end
            end,
        },
        -- THUMB / THUMB_HOVER: plain texture passes; their offset[1] is driven by the
        -- local_offset pass above (NOT a per-pass offset_function, which texture passes
        -- ignore). thumb_hover only shows while the track is hovered.
        { pass_type = "texture", style_id = "thumb", texture_id = "thumb" },
        { pass_type = "texture", style_id = "thumb_hover", texture_id = "thumb_hover",
          content_check_function = function(c) return c.track_hs and c.track_hs.is_hover end },
        -- NUMBER-FIELD BEVEL (v0.2.67-dev): native input_field_background is two stacked
        -- rect_masked passes (outer {200,0,0,0} 52px + inner {255,10,10,10} 50px one z up)
        -- under the value text (options_view_definitions.lua:3-9 / :2075-2103). The borrowed
        -- renderer lacks rect_masked, so plain `rect` passes substitute (gut's established
        -- swap, same as the track/separator). ALWAYS-ON (unlike value_focus_bg). Draw order:
        -- bevel-outer -> bevel-inner -> value_focus_bg (transient focus) -> value text.
        { pass_type = "rect", style_id = "field_bg_outer" },
        { pass_type = "rect", style_id = "field_bg_inner" },
        -- TYPE-TO-EDIT focus background (v0.2.66-dev): faint rect behind the value box,
        -- alpha driven to 90 by the local_offset pass while c.editing, else 0 (invisible).
        -- Drawn BEFORE the value text (and AFTER the always-on bevel) so the number reads
        -- on top; z bumped to 3 (v0.2.67-dev) so it layers over the bevel while editing.
        { pass_type = "rect", style_id = "value_focus_bg" },
        -- Draggable track: click or drag anywhere on the bar to set the value
        -- (the arrow textures remain for fine ±1 steps).
        { pass_type = "hotspot", content_id = "track_hs", style_id = "track_hs" },
        { pass_type = "hotspot", content_id = "dec", style_id = "dec" },
        { pass_type = "hotspot", content_id = "inc", style_id = "inc" },
        { pass_type = "text", style_id = "value", text_id = "value_text" },
        -- TYPE-TO-EDIT caret (v0.2.66-dev): thin vertical bar after the typed text. Its
        -- offset[1] + pulsing alpha are driven every frame by the local_offset pass above
        -- (rect passes ignore their own offset_function, so it must be driven there). Alpha
        -- is 0 unless c.editing, so it's invisible in normal use.
        { pass_type = "rect", style_id = "caret" },
        -- TYPE-TO-EDIT focus hotspot (v0.2.66-dev): a hit zone over JUST the value box,
        -- separate from track_hs/dec/inc so a click on the number enters edit mode without
        -- triggering a drag or an arrow step (spec §6.1).
        { pass_type = "hotspot", content_id = "value_hs", style_id = "value_hs" },
    }
    local content = {
        label = text, thumb = "slider_thumb", thumb_hover = "slider_thumb_hover",
        dec = {}, inc = {}, track_hs = {},
        track_x = track_x, track_w = track_w,
        value = 0, internal_value = 0, min = 0, max = 1, num_decimals = 0, step = 1, value_text = "0",
        -- TYPE-TO-EDIT state (v0.2.66-dev). `value_hs` is the value-box focus hotspot.
        -- `editing` flags this row as the active text editor; `edit_str`/`caret_t` hold the
        -- in-progress string + caret pulse timer. `_caret_box_w` is the value box width the
        -- local_offset caret math reads; `_caret_renderer` is set by the view each frame so
        -- the offset_function can call UIRenderer.text_size with a live renderer.
        value_hs = {}, editing = false, edit_str = "", caret_t = 0,
        _caret_box_w = SLIDER_VALUE_W, _caret_renderer = nil,
    }
    -- Native slider track/fill height is 10 (options_view_definitions.lua:2004-2013).
    local TRACK_H = 10
    local style = {
        -- Label font 16 (was 18) = native slider label size
        -- (options_view_definitions.lua:1991-2002). hell_shark (unmasked) here vs
        -- native hell_shark_masked, but the size matches. Label fills the left column
        -- up to the decrement arrow.
        label      = _text_style(LABEL_BASE_X + ind, y, dec_x - LABEL_BASE_X - 12 - ind, 16),
        -- Track recolored to native `slider_box` near-black {255,5,5,5} (was {255,35,35,35}).
        -- The yellow `fill` style was DELETED (v0.2.67-dev) — native sliders have no fill.
        track      = { offset = { track_x, cy - TRACK_H / 2, 2 }, size = { track_w, TRACK_H }, color = { 255, 5, 5, 5 } },
        thumb      = { texture_size = { THUMB_W, THUMB_H }, offset = { track_x, cy - THUMB_H / 2, 4 }, color = { 255, 230, 230, 230 } },
        -- (v0.2.71-dev) NATIVE HOVER GLOW: wider 34x25 slider_thumb_hover sprite, centered
        -- vertically on the row (cy − H/2) and horizontally on the base thumb (driven by the
        -- local_offset pass above). z 5 = one above the base thumb (z4) so it overlays. Only
        -- drawn while the track is hovered (content_check on c.track_hs.is_hover). masked=false
        -- — the borrowed renderer has no stencil mask; the sprite is fully inside its UV rect.
        thumb_hover = { texture_size = { THUMB_HOVER_W, THUMB_HOVER_H }, masked = false,
                        offset = { track_x, cy - THUMB_HOVER_H / 2, 5 }, color = { 255, 255, 255, 255 } },
        -- Track drag hit zone kept WITHIN the track bounds (no ±overhang) so it can't
        -- overlap the [<]/[>] arrow hotspots that bracket it.
        track_hs   = { size = { track_w, ROW_H }, offset = { track_x, y, 0 } },
        -- Arrow hotspots tight over the textures (the slider's value box sits between
        -- the [>] arrow and the right edge, so native-200 hotspots would overlap it —
        -- keep them tight here; the stepper uses the native 200 hotspots).
        dec        = { size = { ARROW_W + 8, ROW_H }, offset = { dec_x - 4, y, 0 } },
        inc        = { size = { ARROW_W + 8, ROW_H }, offset = { inc_x - 4, y, 0 } },
        -- Value text centered in the native 50px value box at RA−50 (so it reads
        -- centered on VALUE_X_SLIDER = RA−25).
        value      = _text_style(val_x, y, SLIDER_VALUE_W, 20, nil, "center"),
        -- TYPE-TO-EDIT (v0.2.66-dev). value_focus_bg: faint highlight behind the value box
        -- (alpha 0 until editing, driven by the local_offset pass). caret: thin vertical bar
        -- (color[1]=alpha driven by the local_offset pass; offset[1] = end of typed text).
        -- value_hs: hit zone over JUST the value box so clicking the number focuses it
        -- without dragging the track or stepping an arrow.
        -- NUMBER-FIELD BEVEL (v0.2.67-dev), native input_field_background recipe. val_x is
        -- the value box left (RA−50), so native's 50px column drops in 1:1. Always-on.
        field_bg_outer = { offset = { val_x - 2, y + 4, 1 }, size = { 52, ROW_H - 8 },
                           color = { 200, 0, 0, 0 } },
        field_bg_inner = { offset = { val_x,     y + 4, 2 }, size = { 50, ROW_H - 8 },
                           color = { 255, 10, 10, 10 } },
        -- value_focus_bg z bumped 1->3 (v0.2.67-dev) so the transient editing highlight
        -- still draws OVER the always-on bevel (outer z1 / inner z2).
        value_focus_bg = { offset = { val_x, y + 4, 3 }, size = { SLIDER_VALUE_W, ROW_H - 8 },
                           color = { 0, 120, 100, 60 } },
        caret      = { offset = { val_x + SLIDER_VALUE_W / 2, cy - 9, 6 }, size = { 2, 18 },
                       color = { 0, 255, 255, 255 } },
        value_hs   = { size = { SLIDER_VALUE_W, ROW_H }, offset = { val_x, y, 0 } },
    }
    _append_arrows(passes, style, content, dec_x, inc_x, cy)
    _append_highlight(passes, style, content, y)
    _append_separator(passes, style, y)

    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

local function create_stepper(text, _options, _selected, base_offset, depth)
    return create_slider(text, "", base_offset, depth)
end

-- =====================================================================
-- REAL DROPDOWN (v0.2.69-dev). Native settings dropdowns are a SINGLE
-- down-pointing arrow on the right + the selected value; clicking opens a popup
-- list of options; selecting one sets the value + closes; click-away / Esc closes
-- (options_view_definitions.lua create_drop_down_widget :2299-3047). gut used to
-- route dropdowns through the slider's [<]/[>] arrows as a carousel; this is the
-- real thing.
--
-- TWO-PIECE design (so the popup can OVERLAY the rows without GPU clipping):
--   * create_dropdown      = the COLLAPSED row (label + selected value + single
--                            arrow). Anchored to LIST_SG like every other row, so
--                            it scrolls/culls with the list.
--   * create_dropdown_list = the POPUP overlay (bg panel + per-option rows + a
--                            highlight). Built on demand by the view when a dropdown
--                            opens, anchored to its OWN scenegraph node (mt_dropdown)
--                            so it draws LAST (over everything) and is never culled.
--
-- All textures are atlas-resident on the borrowed renderer: `drop_down_menu_arrow`
-- / `drop_down_menu_arrow_clicked` (gui_settings_atlas, same atlas as the slider
-- thumb + stepper arrows) and `playerlist_hover` (gui_menus_atlas, same atlas as
-- the row hover + gear). The bg panels are plain `rect` passes (no rect_masked —
-- absent from the borrowed renderer, same substitution as the track/separator).
local DD_ARROW          = "drop_down_menu_arrow"
local DD_ARROW_CLICKED  = "drop_down_menu_arrow_clicked"
local DD_ARROW_W, DD_ARROW_H = 31, 15
-- VERTICAL flip (swap the V coordinate) so the down chevron renders pointing UP when
-- the popup is open. Distinct from the stepper's FLIP_UVS, which is a HORIZONTAL flip
-- (for the left/right arrows). uvs {{0,1},{1,0}} = native dropdown-arrow flip
-- (options_view_definitions.lua content.arrow.uvs for the open state).
local DD_FLIP_UVS_V    = { { 0, 1 }, { 1, 0 } }
-- Identity uvs (no flip) for the down/closed orientation of a texture_uv glow pass.
local DD_NO_FLIP_UVS_V = { { 0, 0 }, { 1, 1 } }
-- The lit `drop_down_menu_arrow_clicked` glow sprite draws at FULL alpha when shown
-- (native style.arrow_hover / arrow_hover_flipped color = font_default,255). The glow
-- is the sprite APPEARING, not an alpha tween of the base.
local DD_ARROW_GLOW_ALPHA = 255
-- Popup row geometry (native: INPUT_FIELD_WIDTH-56 = 344 wide, 24 tall, max 10 rows).
local DD_ROW_W   = INPUT_FIELD_WIDTH - 56   -- 344
local DD_ROW_H   = 24
local DD_MAX_ROWS = 10
-- (#505) Filter-header band heights, added ABOVE the option rows when the view passes a
-- `header` spec to create_dropdown_list (a long / category-registered dropdown). The search
-- line is always present in the header; the chip row only when the dropdown has categories.
local DD_HEADER_SEARCH_H = 26
local DD_HEADER_CHIP_H   = 28

-- (#92 corrected — match the VANILLA GAME SETTINGS dropdown, not VMF.) The real Options
-- dropdown does NOT recolor its value text on hover/open: both the collapsed
-- `selected_option` (options_view_definitions.lua:2831-2833) and the popup option `text`
-- (:2779 / :2832-2833) carry default_color == hover_color == font_default (white, 255).
-- The hover/open affordance is the ARROW (down sprite + _clicked glow / up-flip), and in
-- the popup the `playerlist_hover` highlight sprite behind the hovered row (:2584-2597) —
-- NOT a text color ramp. So the value text stays a constant font_default white. (The prior
-- cheeseburger->white ramp matched VMF, the wrong menu.)
local _DD_VALUE_IDLE  = Colors.get_color_table_with_alpha("font_default", 255)   -- constant white
-- The picked option in the open popup stays font_title (gold) when NOT hovered — a gut
-- read-at-a-glance cue (deliberate gut extension; native option text is plain white).
local _DD_OPTION_SELECTED = Colors.get_color_table_with_alpha("font_title", 255)
local function _dd_value_color_idle()
    return { _DD_VALUE_IDLE[1], _DD_VALUE_IDLE[2], _DD_VALUE_IDLE[3], _DD_VALUE_IDLE[4] }
end

-- COLLAPSED dropdown row. label (left) + selected value text centered in the input-
-- field value column (reuse the stepper's VALUE_X_STEPPER column) + a single arrow
-- at RA-31 that points DOWN when closed, UP when open (texture_uv vertical flip).
-- A whole-row hotspot over the right INPUT_FIELD_WIDTH strip opens the popup. The
-- view sets content.active (open) so the arrow flips + the popup draws.
local function create_dropdown(text, base_offset, depth, opts)
    local y = base_offset[2] - ROW_H
    base_offset[2] = y
    local cy = y + ROW_H / 2
    local ind = INDENT_PER_DEPTH * (depth or 0)   -- LEFT label only; controls stay at RA
    local val_w = INPUT_FIELD_WIDTH - 60          -- value text fills most of the field column
    local val_x = RA - INPUT_FIELD_WIDTH + 10     -- left edge of the value text band
    local arrow_x = RA - DD_ARROW_W               -- single arrow flush near the right anchor
    local arrow_y = cy - DD_ARROW_H / 2

    local passes = {
        { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
        { pass_type = "text", style_id = "label", text_id = "label" },
        -- Selected value (centered in the field column). Upper-cased like native.
        { pass_type = "text", style_id = "value", text_id = "value_text" },
        -- (#92 corrected — match the VANILLA GAME SETTINGS dropdown, not VMF.)
        -- The real Options dropdown (create_drop_down_widget, options_view_definitions.lua:
        -- 2299) keeps a visible arrow in BOTH states and SWAPS which sprite/style draws —
        -- it never hides the only arrow:
        --   * CLOSED idle: `drop_down_menu_arrow` (down chevron) at full font_default alpha
        --     (style.arrow :2782-2793, drawn when not active).
        --   * OPEN idle: the same sprite drawn flipped/repositioned so it reads UP (style
        --     arrow* swapped on content.active).
        --   * GLOW: the brighter `drop_down_menu_arrow_clicked` sprite appears on HOVER
        --     (closed -> style.arrow_hover :2795-2806, low/down; open -> style.
        --     arrow_hover_flipped :2808-2818, high/up), all at full alpha 255. The "glow" is
        --     that lit _clicked sprite layering over the base while hovered/open — a TEXTURE
        --     swap, not an alpha ramp on the base (the base stays full alpha throughout).
        -- We replicate it with three passes so the arrow is ALWAYS visible (never gated to
        -- nothing) and glows on hover OR while open:
        --   * arrow_down  : base down sprite, full alpha, drawn when NOT active.
        --   * arrow_up    : base sprite vertically flipped (DD_FLIP_UVS_V), full alpha,
        --                   drawn when active — so opening SWAPS to the up arrow, never blank.
        --   * arrow_glow  : the _clicked sprite overlay, drawn whenever hovered OR active,
        --                   flipped to match the open orientation; its alpha ramps 0->255 so
        --                   the lit sprite "appears" as the glow (native two-sprite scheme).
        { pass_type = "texture", style_id = "arrow_down", texture_id = "arrow_tex",
          content_check_function = function(c) return not c.active end },
        { pass_type = "texture_uv", style_id = "arrow_up", texture_id = "arrow_up_tex",
          content_check_function = function(c) return c.active end },
        -- The lit _clicked glow sprite: only drawn while hovered or open (matches native
        -- arrow_hover / arrow_hover_flipped, which only draw under is_hover / active). The
        -- local_offset pass below picks its orientation (down when closed, up when open) and
        -- ramps its alpha so it fades IN over the base — the native "glow".
        { pass_type = "texture_uv", style_id = "arrow_glow", texture_id = "arrow_glow_tex",
          content_check_function = function(c) return (c.hotspot and c.hotspot.is_hover) or c.active end },
        -- Glow-driver pass. Native conveys "open"/"hovered" purely via the ARROW: the down
        -- base sprite swaps to the _clicked glow on hover, and to an up-flip while open
        -- (options_view_definitions.lua arrow / arrow_hover / arrow_hover_flipped). The value
        -- text is NEVER recolored (it stays font_default white — :2831-2833), so this pass
        -- only drives the _clicked glow overlay's alpha + orientation. offset_function is
        -- required — only a local_offset pass runs it every frame (memory
        -- reference_vt2_offset_function_local_offset_only).
        {
            pass_type = "local_offset",
            offset_function = function(_, ui_style, ui_content)
                local hovered = ui_content.hotspot and ui_content.hotspot.is_hover
                local open    = ui_content.active
                local lit     = hovered or open
                -- Glow sprite: full alpha when lit (native _clicked is drawn at 255), 0 when
                -- not (the content_check already hides it, but keep alpha coherent). Flip the
                -- glow to point UP while open, DOWN while closed, mirroring native arrow_hover
                -- (down) vs arrow_hover_flipped (up).
                -- Flip the SHARED content.uvs (what the texture_uv passes actually read) so the
                -- arrow + glow point UP while open, DOWN while closed. arrow_down is a plain
                -- texture pass (always down), hidden via content_check when active.
                ui_content.uvs = open and DD_FLIP_UVS_V or DD_NO_FLIP_UVS_V
                if ui_style.arrow_glow then
                    -- (#99) Native data ([gut-glow-probe] on menu_settings_motion_sickness_hit): the
                    -- glow is drop_down_menu_arrow_clicked (31x28), REPOSITIONED when it flips —
                    -- arrow_hover (closed) at 28-tall-centre +13, arrow_hover_flipped (open) at -12.
                    -- (.125's "same sprite as the arrow" made it the 31x15 base = invisible. Reverted.)
                    ui_style.arrow_glow.offset[2] = cy - 14 + (open and -12 or 13)
                    -- Fade the dropdown glow in/out like the stepper arrows, not a hard pop.
                    local c = ui_style.arrow_glow.color
                    local t = lit and DD_ARROW_GLOW_ALPHA or 0
                    local d = t - (c[1] or 0)
                    c[1] = (math.abs(d) < 4) and t or ((c[1] or 0) + d * 0.3)
                end
            end,
        },
    }
    if opts and opts.no_arrow then
        -- (#123) Keybind rows reuse this row but must read as a FIELD, not a dropdown:
        -- strip the arrow passes (arrow_down / arrow_up / arrow_glow + the local_offset
        -- glow-driver) so only the label + value field remain. No "fake dropdown arrow".
        local kept = {}
        for _, p in ipairs(passes) do
            local sid = p.style_id
            if sid ~= "arrow_down" and sid ~= "arrow_up" and sid ~= "arrow_glow" and p.pass_type ~= "local_offset" then
                kept[#kept + 1] = p
            end
        end
        passes = kept
    end
    local content = {
        hotspot = {}, label = text, value_text = "",
        active = false, arrow_tex = DD_ARROW,
        -- (dropdown-arrow fix, source-confirmed) The texture_uv pass reads the texture from
        -- content[texture_id] (a STRING) and the uvs from content.uvs (TOP-LEVEL, shared) —
        -- ui_passes.lua:145 texture_uv.draw. The old code stashed the texture in a sub-table and
        -- set texture_id="texture_id" (-> content.texture_id = nil -> nothing drew). So texture
        -- strings live in their own top-level keys, and the ONE shared content.uvs is flipped by
        -- the driver (up while open, down while closed).
        arrow_up_tex   = DD_ARROW,
        arrow_glow_tex = DD_ARROW_CLICKED,   -- (#99) native hover-glow sprite (31x28); driver repositions on flip
        uvs            = DD_NO_FLIP_UVS_V,
    }
    local style = {
        hotspot = { size = { INPUT_FIELD_WIDTH, ROW_H }, offset = { RA - INPUT_FIELD_WIDTH, y, 0 } },
        label   = _text_style(LABEL_BASE_X + ind, y, (RA - INPUT_FIELD_WIDTH) - LABEL_BASE_X - 12 - ind, 16),
        -- Idle value color = cheeseburger (native current_selection idle), ramped to white by
        -- the local_offset pass above on hover/open.
        value   = _text_style(val_x, y, val_w, 16, _dd_value_color_idle(), "center"),
        -- Base arrows: FULL alpha in BOTH states (native style.arrow color = font_default,255).
        arrow_down = { texture_size = { DD_ARROW_W, DD_ARROW_H }, offset = { arrow_x, arrow_y, 4 },
                       color = { 255, 181, 181, 181 } },   -- native grey tint (#99 ground truth)
        arrow_up   = { texture_size = { DD_ARROW_W, DD_ARROW_H }, offset = { arrow_x, arrow_y, 4 },
                       color = { 255, 181, 181, 181 } },   -- native grey tint (#99 ground truth)
        -- Glow overlay (_clicked sprite): seeded alpha 0, ramped to full when lit; one z above
        -- the base so the lit sprite reads on top (native draws _clicked at +0 over base +1,
        -- but on the borrowed renderer draw ORDER, not z, layers within one widget — this pass
        -- is appended after the base so it paints over).
        -- (#99b) The glow uses the `drop_down_menu_arrow_clicked` sprite, which is 31x28 in the
        -- atlas (NOT the 31x15 base) — drawing it at the base DD_ARROW_H squished + mispositioned
        -- it (the same bug the stepper arrows had, #92/#99). Use the true clicked height and
        -- re-center it on the row mid-line (cy - 28/2).
        arrow_glow = { texture_size = { DD_ARROW_W, 28 }, offset = { arrow_x, cy - 14, 5 },
                       color = { 0, 181, 181, 181 } },   -- (#99) drop_down_menu_arrow_clicked 31x28, native grey; driver ramps alpha 0->255 + shifts offset on flip
    }
    style.value.upper_case = true
    if opts and opts.field_box then
        -- (#123) Black box + bevel around the value, matching the slider's numeric-input box:
        -- a 2px-larger semi-transparent OUTER rect (the bevel) behind a near-black INNER rect.
        -- Inserted BEFORE the value text pass so the text reads on top (this renderer layers by
        -- draw ORDER within a widget, not z).
        local vi
        for i = 1, #passes do if passes[i].style_id == "value" then vi = i; break end end
        if vi then
            table.insert(passes, vi, { pass_type = "rect", style_id = "field_bg_inner" })
            table.insert(passes, vi, { pass_type = "rect", style_id = "field_bg_outer" })
        end
        -- Box spans the FULL control column: from the value-band left (val_x) to the right
        -- anchor (RA). Keybind rows have no arrow, so it fills the whole column (val_w stops
        -- ~50px short, where a dropdown's arrow sits). Re-center the value text to match.
        local box_w = RA - val_x
        style.field_bg_outer = { offset = { val_x - 2, y + 4, 1 }, size = { box_w + 4, ROW_H - 8 }, color = { 200, 0, 0, 0 } }
        style.field_bg_inner = { offset = { val_x,     y + 4, 2 }, size = { box_w,     ROW_H - 8 }, color = { 255, 10, 10, 10 } }
        if style.value and style.value.size then style.value.size[1] = box_w end
    end
    _append_highlight(passes, style, content, y)
    _append_separator(passes, style, y)

    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- POPUP overlay list for an open dropdown. Built on demand: `texts` is the option
-- labels, `current_idx` the selected option, `anchor_y` the collapsed row's offset
-- Y (so the popup drops one row-height below it), `start_index` the first visible
-- option (for >DD_MAX_ROWS scrolling — the view advances it on wheel). Drawn on the
-- mt_dropdown node (its own scenegraph node, drawn LAST so it overlays + isn't culled).
--   * bg shade (2px larger, behind) + bg panel  = plain rects (rect_masked absent).
--   * per-option row text + a per-option hotspot (content_id = "opt_<i>").
--   * one highlight sprite under the hovered/selected row (playerlist_hover).
-- The view reads content.opt_<i>.on_left_release to commit option i, and is_hover to
-- position the highlight. Returns the widget + the visible count (so the view can map
-- clicks to absolute option indices via start_index).
local function create_dropdown_list(texts, current_idx, anchor_y, start_index, header)
    start_index = math.max(1, start_index or 1)
    local n = #texts
    local num_draws = math.min(n, DD_MAX_ROWS)
    -- The popup top sits one ROW_H below the collapsed row's TOP (anchor_y is the
    -- collapsed row's bottom-Y; its top is anchor_y + ROW_H, so the list top is at
    -- anchor_y — i.e. flush under the collapsed row). Rows descend by DD_ROW_H.
    local list_top = anchor_y
    local x0 = RA - INPUT_FIELD_WIDTH + 10   -- align the popup under the value band

    -- (#505) Optional FILTER HEADER band above the option rows. `header` (nil = the plain
    -- dropdown, unchanged) carries { query = <string>, chips = { { label=, active= }, ... } }.
    -- The header occupies the TOP of the panel; option rows are pushed down by header_h so the
    -- popup still drops downward from the collapsed row. The view updates content.search_text
    -- each frame (query + blink caret) and reads content.chip_<i> hotspots for chip clicks.
    local chips = header and header.chips
    local n_chips = (type(chips) == "table") and #chips or 0
    local header_h = 0
    if header then
        header_h = DD_HEADER_SEARCH_H + (n_chips > 0 and DD_HEADER_CHIP_H or 0)
    end
    local opt_top = list_top - header_h            -- top of the OPTION-row area
    local panel_h = header_h + DD_ROW_H * num_draws

    local passes = {
        -- bg shade (border fake): 2px larger all around, one z behind the panel.
        { pass_type = "rect", style_id = "shade" },
        { pass_type = "rect", style_id = "panel" },
    }
    local style = {
        shade = { offset = { x0 - 2, list_top - panel_h - 2, 8 }, size = { DD_ROW_W + 4, panel_h + 4 },
                  color = { 255, 80, 80, 80 } },
        panel = { offset = { x0, list_top - panel_h, 9 }, size = { DD_ROW_W, panel_h },
                  color = { 255, 10, 10, 10 } },
    }
    local content = {}

    -- (#505) Header passes (search line + optional chip row). Built before the option rows so
    -- their hotspots resolve and their bg strips sit at the panel top.
    if header then
        local sy = list_top - DD_HEADER_SEARCH_H
        passes[#passes + 1] = { pass_type = "rect", style_id = "search_bg" }
        passes[#passes + 1] = { pass_type = "text", style_id = "search_text", text_id = "search_text" }
        style.search_bg = { offset = { x0, sy, 10 }, size = { DD_ROW_W, DD_HEADER_SEARCH_H }, color = { 255, 22, 22, 22 } }
        style.search_text = {
            font_type = "hell_shark", font_size = 15,
            horizontal_alignment = "left", vertical_alignment = "center",
            localize = false, upper_case = false,
            text_color = { 255, 200, 200, 200 },
            offset = { x0 + 8, sy, 12 }, size = { DD_ROW_W - 16, DD_HEADER_SEARCH_H },
        }
        content.search_text = tostring(header.query or "")
        if n_chips > 0 then
            local cy = list_top - DD_HEADER_SEARCH_H - DD_HEADER_CHIP_H
            local chip_w = DD_ROW_W / n_chips
            for ci = 1, n_chips do
                local chip = chips[ci]
                local cx = x0 + (ci - 1) * chip_w
                local bg_id, txt_id, hs_id = "chip_bg_" .. ci, "chip_txt_" .. ci, "chip_" .. ci
                local active = chip.active and true or false
                passes[#passes + 1] = { pass_type = "rect", style_id = bg_id }
                passes[#passes + 1] = { pass_type = "text", style_id = txt_id, text_id = txt_id }
                passes[#passes + 1] = { pass_type = "hotspot", content_id = hs_id, style_id = hs_id }
                style[bg_id]  = { offset = { cx + 2, cy + 3, 10 }, size = { chip_w - 4, DD_HEADER_CHIP_H - 6 },
                                  color = active and { 255, 90, 70, 30 } or { 255, 30, 30, 30 } }
                style[txt_id] = {
                    font_type = "hell_shark", font_size = 14,
                    horizontal_alignment = "center", vertical_alignment = "center",
                    localize = false, upper_case = false,
                    text_color = active and { 255, 255, 220, 150 } or { 255, 175, 175, 175 },
                    offset = { cx + 2, cy, 12 }, size = { chip_w - 4, DD_HEADER_CHIP_H },
                }
                style[hs_id]  = { offset = { cx, cy, 11 }, size = { chip_w, DD_HEADER_CHIP_H } }
                content[txt_id] = tostring(chip.label or "")
                content[hs_id]  = {}
            end
        end
    end

    -- Highlight sprite (drawn once, repositioned to the hovered/selected row by the view).
    passes[#passes + 1] = {
        pass_type = "texture", style_id = "hl", texture_id = "hl_tex",
        content_check_function = function(c) return c.hl_visible end,
    }
    content.hl_tex = "playerlist_hover"
    content.hl_visible = false
    style.hl = { offset = { x0, opt_top - DD_ROW_H, 10 }, size = { DD_ROW_W, DD_ROW_H },
                 color = { 255, 255, 255, 255 } }

    for k = 1, num_draws do
        local opt_i = start_index + k - 1
        local row_top = opt_top - (k - 1) * DD_ROW_H
        local text_id = "txt_" .. k
        local hs_id   = "opt_" .. k
        -- (#92 corrected — match the VANILLA GAME SETTINGS popup, not VMF.) The real Options
        -- dropdown popup (create_drop_down_widget list_pass, options_view_definitions.lua:
        -- 2546-2598) recolors each option's text to default_color/hover_color which are BOTH
        -- font_default white (:2779 / :2832-2833) — i.e. the option TEXT does NOT brighten on
        -- hover. The hover affordance is the `playerlist_hover` HIGHLIGHT SPRITE drawn behind
        -- the hovered row (:2584-2597) — which gut already provides via the single `hl` sprite
        -- the view repositions to the hovered/selected row. So the option text is a CONSTANT
        -- font_default white; we keep ONLY a gut extension: the currently-picked option stays
        -- font_title (gold) so it reads at a glance (native leaves it plain white). No
        -- cheeseburger idle / white-hover ramp (that was the wrong-menu VMF mechanism).
        local is_sel = (opt_i == current_idx)
        passes[#passes + 1] = {
            pass_type = "text", style_id = text_id, text_id = text_id,
            content_check_function = function(c, st)
                if st and st.text_color then
                    -- Picked option = gold (gut cue); every other option = constant white
                    -- (native option text never recolors on hover — the hl sprite does the work).
                    local src = is_sel and _DD_OPTION_SELECTED or _DD_VALUE_IDLE
                    local tc = st.text_color
                    tc[1], tc[2], tc[3], tc[4] = src[1], src[2], src[3], src[4]
                end
                return true
            end,
        }
        passes[#passes + 1] = { pass_type = "hotspot", content_id = hs_id, style_id = hs_id }
        content[text_id] = tostring(texts[opt_i] or "")
        content[hs_id]   = {}
        style[text_id] = {
            font_type = "hell_shark", font_size = 16,
            horizontal_alignment = "center", vertical_alignment = "center",
            localize = false, upper_case = false,
            -- Seeded idle; the content_check_function above overwrites it every frame.
            text_color = is_sel and { _DD_OPTION_SELECTED[1], _DD_OPTION_SELECTED[2], _DD_OPTION_SELECTED[3], _DD_OPTION_SELECTED[4] }
                                 or { _DD_VALUE_IDLE[1], _DD_VALUE_IDLE[2], _DD_VALUE_IDLE[3], _DD_VALUE_IDLE[4] },
            offset = { x0, row_top - DD_ROW_H, 12 }, size = { DD_ROW_W, DD_ROW_H },
        }
        style[hs_id] = { offset = { x0, row_top - DD_ROW_H, 11 }, size = { DD_ROW_W, DD_ROW_H } }
    end

    local w = UIWidget.init({
        scenegraph_id = "mt_dropdown",
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
    -- Stash the geometry the view needs to map hover/clicks -> absolute option index.
    w._dd_num_draws  = num_draws
    w._dd_start      = start_index
    w._dd_total      = n
    w._dd_list_top   = opt_top        -- (#505) OPTION-row top (below any header band)
    w._dd_x0         = x0
    w._dd_row_h      = DD_ROW_H
    -- (#505) filtered-space selected index (highlight seed) + header geometry the view reads.
    w._dd_cur        = current_idx
    w._dd_header_h   = header_h
    w._dd_chip_count = n_chips
    return w
end

-- ---------------------------------------------------------------
-- (#207) HOVER INFO POPUP — native options-menu tooltip, HAND-BUILT for the borrowed
-- renderer. Native settings rows carry an `option_tooltip` pass (ui_passes.lua:3350) that
-- composes UITooltipPasses.generic_text + a box drawn by UITooltipPasses.background: a
-- `{255,3,3,3}` fill rect + the `item_tooltip_frame_01` frame (ui_passes_tooltips.lua:21-71).
-- item_tooltip_frame_01's texture IS `menu_frame_12` (ui_frame_settings.lua:921-941) — the
-- SAME frame gut's window chrome (background_frame) already draws, so it's PROVEN resident on
-- the borrowed HeroView / level-world renderer. So this popup reproduces the native box the
-- proven way: a plain `rect` "panel" fill (dark {255,3,3,3}, NO atlas/material lookup) + a
-- `texture_frame` menu_frame_12 border (the real settings-tooltip frame, sized per-frame),
-- plus plain `text` passes, on the mt_tooltip scenegraph node (parented to mt_list so it
-- scrolls with the rows, z above them) drawn LAST in the view's draw loop so it overlays +
-- isn't culled. Title = the row label (font_title, larger size 22); description = the node's
-- localized `tooltip`, word-wrapped below it (font_default, size 18). The view sets
-- content.title / content.desc + the geometry + the fade alpha every frame via layout_tooltip.
local TT_W             = math.min(600, ROW_W)   -- native tooltip width 600, clamped to gut's panel
local TT_PAD_X         = 16
local TT_PAD_Y         = 12
local TT_GAP           = 6                       -- vertical gap between title + description
local TT_TITLE_SIZE    = 22
local TT_DESC_SIZE     = 18
local TT_SCREEN_MARGIN = 8                       -- px margin from a screen edge before flipping the box's side
-- (#207) menu_frame_12 9-slice BORDER — the SAME ornate frame the NATIVE settings option
-- tooltip draws: vanilla option_tooltip -> UITooltipPasses.background uses item_tooltip_frame_01,
-- whose texture IS menu_frame_12, over a {255,3,3,3} fill (ui_passes_tooltips.lua:21-71 /
-- ui_frame_settings.lua:921-941). menu_frame_12 is already proven to resolve on the borrowed
-- renderer (gut's window chrome background_frame uses it via UIWidgets.create_frame). We draw it
-- as a texture_frame pass whose area_size + offset are set per-frame in layout_tooltip so the
-- frame resizes with the box. Metrics copied verbatim from UIFrameSettings.menu_frame_12.
local TT_FRAME_TEXTURE   = "menu_frame_12"
local TT_FRAME_TEX_SIZE  = { 64, 64 }
local TT_FRAME_TEX_SIZES = { corner = { 11, 11 }, vertical = { 5, 1 }, horizontal = { 1, 5 } }

-- One reusable tooltip widget. The view sets content.title / content.desc and every frame
-- calls layout_tooltip to size/position the box + ramp the fade alpha. Mirrors the dropdown
-- popup's z-ordering (drawn above rows). The border is the native menu_frame_12 9-slice (the
-- SAME frame the real settings tooltip uses — see TT_FRAME_* above), NOT a flat grey rect.
local function create_tooltip_popup()
    local passes = {
        -- Dark panel FILL (native settings-tooltip background = {255,3,3,3}).
        { pass_type = "rect", style_id = "panel" },
        -- TITLE (header, larger) over a word-wrapped DESCRIPTION below it.
        { pass_type = "text", style_id = "title", text_id = "title" },
        { pass_type = "text", style_id = "desc",  text_id = "desc" },
        -- menu_frame_12 BORDER, drawn LAST (highest z) so its edges sit crisply over the fill.
        -- area_size + offset are driven per-frame by layout_tooltip so it wraps the box exactly.
        { pass_type = "texture_frame", style_id = "frame", texture_id = "frame" },
    }
    local content = { title = "", desc = "", frame = TT_FRAME_TEXTURE }
    local style = {
        panel = { offset = { 0, 0, 60 }, size = { TT_W, 10 }, color = { 255, 3, 3, 3 } },
        title = {
            font_type = "hell_shark", font_size = TT_TITLE_SIZE,
            horizontal_alignment = "left", vertical_alignment = "top",
            localize = false, word_wrap = true,
            text_color = Colors.get_color_table_with_alpha("font_title", 255),
            offset = { 0, 0, 62 }, size = { TT_W - TT_PAD_X * 2, 30 },
        },
        desc = {
            font_type = "hell_shark", font_size = TT_DESC_SIZE,
            horizontal_alignment = "left", vertical_alignment = "top",
            localize = false, word_wrap = true,
            text_color = Colors.get_color_table_with_alpha("font_default", 255),
            offset = { 0, 0, 62 }, size = { TT_W - TT_PAD_X * 2, 30 },
        },
        -- menu_frame_12 9-slice; color[1] (alpha) ramped by the fade. area_size/offset per-frame.
        frame = {
            texture_size = TT_FRAME_TEX_SIZE, texture_sizes = TT_FRAME_TEX_SIZES,
            color = { 255, 255, 255, 255 },
            offset = { 0, 0, 63 }, area_size = { TT_W, 10 },
        },
    }
    return UIWidget.init({
        scenegraph_id = "mt_tooltip",
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- Measure one word-wrapped text block: returns (line_count, line_height) in UNSCALED UI
-- space, mirroring the native generic_text / text-pass measurement (ui_passes.lua:1992-2000
-- / 4001-4007): word_wrap with the SCALED font size + the raw box width, line height =
-- (font_max - font_min) * inv_scale. Caller pcall-guards; on failure falls back to 1 line.
local function _tt_measure(renderer, style, text, inner_w)
    local font, scaled = UIFontByResolution(style)
    local lines = UIRenderer.word_wrap(renderer, text, font[1], scaled, inner_w)
    local _, fmin, fmax = UIGetFontHeight(renderer.gui, style.font_type, scaled)
    local line_h = (fmax - fmin) * RESOLUTION_LOOKUP.inv_scale
    return math.max(1, #lines), line_h
end

-- Lay out + fade the tooltip popup for the hovered row, every frame. `row_list_y` is the
-- hovered row's offset Y (its bottom edge, in mt_list_start / mt_tooltip space, which share
-- the {40,0} origin); `world_row_y` is that same bottom edge in screen/design space (for the
-- on-screen flip test); `alpha` is the fade [0..1].
-- (#207) Anchors the box ABOVE the row by default (its bottom edge flush to the row's top),
-- matching the native options tooltip; FLIPS it BELOW only when drawing above would run off the
-- TOP of the visible screen. Box height fits the wrapped title + description. Mutates in place.
local function layout_tooltip(widget, renderer, title, desc, row_list_y, world_row_y, alpha)
    local style, content = widget.style, widget.content
    content.title = tostring(title or "")
    content.desc  = tostring(desc or "")
    local inner_w = TT_W - TT_PAD_X * 2

    -- Measure wrapped heights (native generic_text approach). Fallback = 1 line each.
    local title_lines, title_lh = 1, TT_TITLE_SIZE + 8
    local desc_lines,  desc_lh  = 1, TT_DESC_SIZE + 6
    pcall(function() title_lines, title_lh = _tt_measure(renderer, style.title, content.title, inner_w) end)
    pcall(function() desc_lines,  desc_lh  = _tt_measure(renderer, style.desc,  content.desc,  inner_w) end)
    local title_h = title_lines * title_lh
    local desc_h  = desc_lines  * desc_lh
    local box_h   = TT_PAD_Y + title_h + TT_GAP + desc_h + TT_PAD_Y

    -- (#207) DEFAULT = draw the box ABOVE the row (its bottom edge flush to the row's top), like
    -- the native options tooltip. `box_top` is the box's TOP edge in offset space (offset is
    -- bottom-left, +Y up). Drawing above puts the box's TOP at world Y = world_row_y + ROW_H +
    -- box_h; flip to BELOW only if that runs off the TOP of the visible screen. Screen height is
    -- read in the SAME design space as world_row_y (res_h * inv_scale; falls back to 1080).
    local screen_h = 1080
    pcall(function()
        local r = RESOLUTION_LOOKUP
        if r and r.res_h and r.inv_scale then screen_h = r.res_h * r.inv_scale end
    end)
    local above_top_world = world_row_y + ROW_H + box_h
    local draw_below = above_top_world > (screen_h - TT_SCREEN_MARGIN)
    local box_top    = draw_below and row_list_y or (row_list_y + ROW_H + box_h)
    local box_bottom = box_top - box_h
    local x0 = LABEL_BASE_X
    if x0 + TT_W > ROW_W then x0 = math.max(0, ROW_W - TT_W) end

    style.panel.offset[1], style.panel.offset[2] = x0, box_bottom
    style.panel.size[1],   style.panel.size[2]   = TT_W, box_h
    -- menu_frame_12 border wraps the fill exactly (same rect); area_size drives the 9-slice.
    style.frame.offset[1],    style.frame.offset[2]    = x0, box_bottom
    style.frame.area_size[1], style.frame.area_size[2] = TT_W, box_h
    style.title.offset[1] = x0 + TT_PAD_X
    style.title.offset[2] = box_top - TT_PAD_Y - title_h
    style.title.size[1],   style.title.size[2]   = inner_w, title_h
    style.desc.offset[1]  = x0 + TT_PAD_X
    style.desc.offset[2]  = box_top - TT_PAD_Y - title_h - TT_GAP - desc_h
    style.desc.size[1],    style.desc.size[2]    = inner_w, desc_h

    -- Fade: alpha [0..1] -> 0..255 on EVERY pass color (panel, frame, both texts).
    local a = math.floor(math.clamp(alpha or 0, 0, 1) * 255 + 0.5)
    style.panel.color[1]      = a
    style.frame.color[1]      = a
    style.title.text_color[1] = a
    style.desc.text_color[1]  = a
end

-- Section / unsupported row: label-only text (font_title, upper case). Safe.
local function create_section_title(text, base_offset, depth)
    local y = base_offset[2] - ROW_H
    base_offset[2] = y
    local ind = INDENT_PER_DEPTH * (depth or 0)   -- LEFT label only
    -- (Fix 1, v0.2.151-dev) font 18 (was 24) = the FARMED vanilla in-list header font
    -- (dumped live from the real Options menu). The decompiled 24 (keybind_info/tooltip)
    -- rendered too large once the global scale doubled it.
    local st = _text_style(LABEL_BASE_X + ind, y, ROW_W - LABEL_BASE_X - ind, 18, Colors.get_color_table_with_alpha("font_title", 255))
    st.upper_case = true
    local passes = { { pass_type = "text", style_id = "label", text_id = "label" } }
    local style  = { label = st }
    _append_separator(passes, style, y)
    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = { label = text },
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- Collapsible GROUP header: a clickable row with a [+]/[-] indicator + the group name
-- on a faint tinted bar. The view toggles expand/collapse on hotspot release and
-- rebuilds. (style_id on the hotspot is REQUIRED — shared mt_list_start node.)
local function create_group_header(text, expanded, base_offset, depth)
    local y = base_offset[2] - ROW_H
    base_offset[2] = y
    local ind = INDENT_PER_DEPTH * (depth or 0)   -- LEFT indicator + label only
    local cy = y + ROW_H / 2
    local passes = {
        { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
        -- (v0.2.67-dev) The tinted `bg` bar pass was DELETED — the larger colored title
        -- text (font 22 / font_title) is the group differentiator now, not a colored bar.
        -- (#165) Collapse/expand indicator is now the drop_down_menu_arrow CHEVRON sprite (was the
        -- text glyph "[+]"/"[-]"), drawn via rotated_texture: ▼ DOWN when expanded (angle 0), ▶ RIGHT
        -- when collapsed (angle +pi/2 — VT2 UI is Y-up, so a down chevron rotated +90° CCW points
        -- right), like a native tree toggle. Hover brighten comes from the row's _append_highlight bar.
        -- (#165) Per-frame glow driver. ONLY a local_offset pass runs its offset_function every
        -- frame (reference_vt2_offset_function_local_offset_only), and it mutates the LIVE ui_style
        -- used for drawing — the exact proven pattern the dropdown arrow glow uses. Read the row
        -- hotspot's is_hover and brighten ui_style.arrow grey->white. (The earlier _apply_row_hover
        -- attempt wrote row.style — a possibly-cloned table — so it never reached the render.)
        { pass_type = "local_offset", offset_function = function(_, ui_style, ui_content)
            -- Fade the orangey `_clicked` glow sprite in/out (alpha ramp toward 255/0,
            -- snapping within 4) — the EXACT scheme the dropdown + stepper arrow glows use.
            -- (Fix 4, v0.2.149-dev) An EXPANDED group keeps its arrow lit even when NOT
            -- hovered, so an open section reads as active (like the row highlight below).
            -- ui_content.expanded is baked at build time AND refreshed live each frame by
            -- the twins' _apply_row_hover (from self._expanded[row._group_key], the same
            -- source the row toggle uses), so it tracks a toggle without a rebuild.
            local hov = ui_content.hotspot and ui_content.hotspot.is_hover
            local lit = hov or ui_content.expanded
            local g = ui_style.arrow_glow
            if g and g.color then
                local t = lit and 255 or 0
                local d = t - (g.color[1] or 0)
                g.color[1] = (math.abs(d) < 4) and t or ((g.color[1] or 0) + d * 0.3)
            end
        end },
        { pass_type = "rotated_texture", style_id = "arrow", texture_id = "arrow_tex" },
        -- (#165) the orangey hover GLOW: drop_down_menu_arrow_clicked drawn OVER the chevron at the
        -- same rotation, alpha-ramped by the driver above — same glow image as every other arrow.
        { pass_type = "rotated_texture", style_id = "arrow_glow", texture_id = "arrow_glow_tex" },
        { pass_type = "text",    style_id = "label",     text_id = "label" },
    }
    local content = { hotspot = {}, arrow_tex = "drop_down_menu_arrow",
                      arrow_glow_tex = "drop_down_menu_arrow_clicked", label = tostring(text),
                      -- (Fix 4, v0.2.149-dev) initial expanded state; the glow driver reads it,
                      -- and the twins refresh it live each frame in _apply_row_hover.
                      expanded = expanded and true or false }
    local style = {
        hotspot   = { size = { ROW_W, ROW_H }, offset = { 0, y, 0 } },
        -- (v0.2.67-dev) The tinted `bg` style was DELETED — see the pass note above.
        -- (#165) Pivot = sprite centre so it rotates in place; sized ~24x12 + vertically centred on
        -- the row, sitting in the old indicator column (left of the label at 46+ind).
        -- (#165) REST arrow dimmed 180 -> 130 grey so the white hover arrow reads as an
        -- obvious glow. Centre = (8+ind+12, cy) for the 24x12 sprite.
        -- (#165) ONE arrow pass. The view's _apply_row_hover drives this colour DIRECTLY each frame
        -- (grey 130 at rest -> white 255 on hover). The arrow pass always renders (no content_check),
        -- so the hover shows reliably — the old content_check `arrow_hover` overlay never appeared
        -- (rotated_texture ignores content_check_function on the borrowed Mod Tweaker renderer).
        arrow       = { angle = expanded and 0 or (-math.pi * 0.5), pivot = { 12, 6 },
                        texture_size = { 24, 12 }, color = { 255, 181, 181, 181 },
                        offset = { 8 + ind, cy - 6, 1 } },
        -- (#165) orangey hover glow overlay (drop_down_menu_arrow_clicked, 31x28 -> 24x22).
        -- The CHEVRON sits ~1px from the BOTTOM of this sprite, NOT at its box centre. Ground
        -- truth is the #99 dropdown: the 28-tall glow needs +13 to align its chevron with the
        -- base arrow, i.e. the chevron is 13/28 below box-centre -> ~1px up from the bottom of
        -- our 22-tall box. So we must rotate about the CHEVRON (pivot {12,1}), not the box
        -- centre ({12,11}). The old box-centre pivot left the chevron ~10px off the rotation
        -- centre: a vertical shift while expanded, and -- once rotated 90deg for the collapsed
        -- state -- a SIDEWAYS shift onto the wrong side of the base arrow (the reported bug).
        -- offset cy-1 keeps the rotation centre at (20+ind, cy) = the base chevron, so the glow
        -- now sits on the chevron in BOTH states. Alpha seeds 0, driver ramps to 255 on hover.
        arrow_glow  = { angle = expanded and 0 or (-math.pi * 0.5), pivot = { 12, 1 },
                        texture_size = { 24, 22 }, color = { 0, 181, 181, 181 },
                        offset = { 8 + ind, cy - 1, 2 } },
        -- (#206) EXEMPT from LABEL_BASE_X: a collapsible group's label intentionally clears
        -- the +/- chevron column (chevron spans ~8..32+ind), so it sits at 46+ind, tree-style
        -- indented past the toggle. This is by design, not the cross-row misalignment #206 fixed.
        -- (Fix 1, v0.2.151-dev) font 18 (was 24) = the FARMED vanilla in-list header font.
        label     = _text_style(46 + ind, y, ROW_W - 60 - ind, 18, Colors.get_color_table_with_alpha("font_title", 255), "left"),
    }
    _append_highlight(passes, style, content, y)
    _append_separator(passes, style, y)
    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- GEAR / "Advanced Settings" drill-down button. A small clickable cogwheel in the
-- row's 3rd (far-right) column, attached ONLY to rows that own nested sub-options
-- (gut nested: a non-group node with sub_widgets; VMF flat: the next node is deeper).
-- Clicking it drills INTO that setting's children (the view swaps the list for a
-- Back row + parent row + child rows). It's a SEPARATE widget anchored to the same
-- LIST_SG node at the parent row's Y, drawn after the row; the view reads its
-- hotspot for clicks.
--
-- TEXTURE = `cog_icon` idle / `cog_icon_selected` hover (v0.2.67-dev) — the native
-- equipment-menu cog (58x58, gui_menus_atlas; gui_menus_atlas.lua:1586-1613). That atlas
-- is proven-resident on the borrowed renderer (gut's `playerlist_hover` lives there too).
-- Was `cogwheel_small` (gui_icons_atlas, 40x40). texture_size rescales the 58px sprite
-- into the GEAR_SIZE (26px) box. style_id on the hotspot is REQUIRED: every list row +
-- gear shares the mt_list_start node (size {1,1}), so without an explicit style.hotspot
-- size the hit target collapses to 1x1 (same gotcha as the checkbox).
-- (GEAR_SIZE is defined once near ROW_W — promoted above RA for the column-shift math.)
local function create_gear_button(y)
    local cy   = y + ROW_H / 2
    local gx   = ROW_W - GEAR_SIZE - 10        -- TRUE row right edge; sits alone in the gutter
    local gy   = cy - GEAR_SIZE / 2
    local passes = {
        { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
        -- Hover highlight UNDER the cog (drawn first; gated on the hotspot's is_hover,
        -- set by the view each frame). Atlas-safe "playerlist_hover" sprite.
        { pass_type = "texture", style_id = "gear_hl", texture_id = "gear_hl_tex",
          content_check_function = function(c) return c.is_highlighted end },
        -- Idle cog (always drawn) + a hover cog drawn OVER it when highlighted
        -- (cog_icon_selected), gated on the same is_highlighted flag the view sets.
        { pass_type = "texture", style_id = "cog", texture_id = "cog_tex" },
        { pass_type = "texture", style_id = "cog_hover", texture_id = "cog_hover_tex",
          content_check_function = function(c) return c.is_highlighted end },
    }
    local content = {
        hotspot = {}, cog_tex = "cog_icon", cog_hover_tex = "cog_icon_selected",
        gear_hl_tex = "playerlist_hover", is_highlighted = false,
    }
    local style = {
        hotspot = { size = { GEAR_SIZE + 8, ROW_H }, offset = { gx - 4, y, 0 } },
        gear_hl = { texture_size = { GEAR_SIZE + 10, GEAR_SIZE + 10 },
                    offset = { gx - 5, gy - 5, 5 }, color = { 70, 255, 255, 255 } },
        cog       = { texture_size = { GEAR_SIZE, GEAR_SIZE }, offset = { gx, gy, 6 },
                    color = Colors.get_color_table_with_alpha("font_title", 255) },
        cog_hover = { texture_size = { GEAR_SIZE, GEAR_SIZE }, offset = { gx, gy, 7 },
                    color = { 255, 255, 255, 255 } },
    }
    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- ---------------------------------------------------------------
-- (v0.2.75-dev) SHARED DRILL SUBTREE PLAN — fixes "VMF dropdowns show no options".
--
-- The previous gear-drill rendered the drilled parent's DIRECT children only (a
-- single hard-coded `depths[j] == pdepth + 1` level). That meant a dropdown nested
-- THREE deep — VMF's wt anim picker is `checkbox (depth 1) -> set-group (depth 2) ->
-- per-attack dropdown (depth 3)` — was never reachable: drilling the checkbox showed
-- the depth-2 set GROUP headers, and the single-level loop never built the depth-3
-- dropdown nodes under them. The dropdowns therefore never existed as rows, so their
-- already-correctly-read `.options` (node.options / option.text / option.value, same
-- field/path VMF's own options view uses) were never surfaced — the "?" / blank a
-- user saw was the absence of the row, not an empty option list.
--
-- This planner walks the WHOLE subtree under the drilled parent (every node with
-- `depth > pdepth`) using the SAME group-collapse / gear-parent rules as the normal
-- list loop, just rebased so the parent sits at row-depth 0 and a flat-depth-d node
-- renders at row-depth (d - pdepth). A child that is itself a `group` honors the
-- caller's expand state (`is_expanded`): collapsed groups hide their descendants
-- inline (like the normal list), expanded groups reveal them — so the user can drill
-- the checkbox, expand a set-group, and finally see + pick its dropdowns. A non-group
-- node that still has deeper children gets a gear so it can be drilled one level further.
--
-- Returns an ORDERED instruction list `{ index = j, depth = row_depth, has_gear = bool }`.
-- Pure data (no widget building, no class methods), so BOTH twins (the standalone
-- ModTweakerView and the HeroView sub-state) feed it their identical nodes/depths
-- arrays and build rows from the result through their own _build_node_row/_append_row.
--   * `get_type(node)`  — returns the node's widget "type" (the caller's _nf(node,"type")).
--   * `is_expanded(node, flat_depth, row_depth)` — true if a group node is expanded.
-- NOTE: the "header" exclusion from the normal loop is intentionally NOT replicated
-- here — a VMF per-mod header only ever appears at the top level (depth 0), never
-- inside a drilled subtree, so it can't be a child here.
local function plan_drill_children(nodes, depths, p_idx, pdepth, get_type, is_expanded)
    local out = {}
    local skip_below = nil   -- flat-depth: while set, skip deeper nodes (collapsed group / gear parent)
    for j = p_idx + 1, #nodes do
        local d = depths[j]
        if d <= pdepth then break end        -- climbed back out of the parent's subtree
        if not (skip_below and d > skip_below) then
            skip_below = nil
            local node = nodes[j]
            local wtype = get_type(node)
            local row_depth = d - pdepth      -- parent is row-depth 0; first children row-depth 1
            -- Has deeper children iff the NEXT node in the subtree is deeper than this one.
            local nd = depths[j + 1]
            local has_children = (nd ~= nil) and (nd > d)
            if wtype == "group" then
                -- Collapsible group: emit it (no gear); hide its descendants while collapsed.
                out[#out + 1] = { index = j, depth = row_depth, has_gear = false, is_group = true }
                if not is_expanded(node, d, row_depth) then skip_below = d end
            elseif has_children then
                -- Non-group node with its own deeper children: gear + skip them inline
                -- (drilling the gear re-enters this planner one level down).
                out[#out + 1] = { index = j, depth = row_depth, has_gear = true }
                skip_below = d
            else
                out[#out + 1] = { index = j, depth = row_depth, has_gear = false }
            end
        end
    end
    return out
end

-- "< Back" row shown at the TOP of a drilled-in advanced view. Clicking it (or the
-- first ESC) drills back OUT to the normal list. Same shape as a group header (a
-- clickable tinted bar) but with a back chevron + the parent setting's name, so the
-- player knows which setting's advanced options they're editing.
local function create_back_row(parent_label, base_offset)
    local y = base_offset[2] - ROW_H
    base_offset[2] = y
    local passes = {
        { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
        -- (v0.2.67-dev) The tinted `bg` bar pass was DELETED for consistency with the
        -- group header — the colored chevron + label text is the differentiator.
        { pass_type = "text",    style_id = "indicator", text_id = "indicator" },
        { pass_type = "text",    style_id = "label",     text_id = "label" },
    }
    local content = {
        hotspot = {}, indicator = "< Back",
        label = "Advanced: " .. tostring(parent_label or ""),
    }
    local style = {
        hotspot   = { size = { ROW_W, ROW_H }, offset = { 0, y, 0 } },
        -- (v0.2.67-dev) The tinted `bg` style was DELETED — see the pass note above.
        indicator = _text_style(10, y, 90, 20, Colors.get_color_table_with_alpha("font_title", 255), "left"),
        label     = _text_style(108, y, ROW_W - 120, 22, Colors.get_color_table_with_alpha("font_title", 255), "left"),
    }
    _append_highlight(passes, style, content, y)
    _append_separator(passes, style, y)
    return UIWidget.init({
        scenegraph_id = LIST_SG,
        element = { passes = passes },
        content = content,
        style = style,
        offset = { 0, 0, 0 },
    })
end

-- Rect-based scrollbar (track + draggable thumb). Pure rect/hotspot passes so it's
-- safe on the borrowed renderer (NO mask_rect/rounded_background materials). The
-- view sets content.scroll_value [0..1] + content.thumb_frac (visible/total) each
-- frame; the thumb size/offset derive in the offset_function. content.hotspot
-- drives the drag (view reads on_pressed + the held LMB).
local function build_scrollbar_rect()
    local track_h = scenegraph_definition.mt_scrollbar.size[2]
    return UIWidget.init({
        scenegraph_id = "mt_scrollbar",
        element = {
            passes = {
                { pass_type = "rounded_background", style_id = "track" },  -- (#166) rounded corners like the vanilla scrollbar
                -- THUMB SIZE/POSITION DRIVER (v0.2.77-dev) — the fix for "thumb is always
                -- the full length of the track and can't be dragged". The thumb-sizing
                -- offset_function previously lived on the `rect` thumb pass itself, but the
                -- generic widget draw loop (ui_renderer.lua:521-555) NEVER calls
                -- `offset_function` for texture/rect/texture_uv passes — only a dedicated
                -- `local_offset` pass invokes it (UIPasses.local_offset.draw,
                -- ui_passes.lua:4587-4593, is literally just
                -- `pass_definition.offset_function(...)`). So the per-pass version silently
                -- never ran: the thumb kept its scenegraph style size {8, track_h} = the
                -- FULL track height regardless of content, leaving nothing to grab. This is
                -- the identical defect that burned the gut SLIDER 3x (fixed v0.2.59); the
                -- fix is the same native pattern (options_view_definitions.lua:1673-1695) —
                -- one local_offset pass that mutates the OTHER passes' styles in place each
                -- frame. The offset_function here gets the WHOLE widget ui_style, so it
                -- indexes the thumb sub-style by key. The view sets content.scroll_value
                -- [0..1] + content.thumb_frac (visible/total) each frame (gated on
                -- _max_scroll>0; see _mod_tweaker_view.lua:1801 / _mod_tweaker_state.lua:1754).
                {
                    pass_type = "local_offset",
                    offset_function = function(_, ui_style, ui_content)
                        if not ui_style.thumb then return end
                        -- MIRRORS NATIVE create_scrollbar (ui_widgets.lua:2168-2386), the
                        -- exact widget the vanilla Options view uses on an identically
                        -- center-aligned node (scrollbar_root, options_view_definitions.lua:316).
                        -- Native shrinks the thumb to scroll_length * bar_height_percentage
                        -- (:2183) and positions it with `scroll_bar_box.offset[axis] =
                        -- current_position`, `current_position = (scroll_length - thumb_length)
                        -- * value` clamped to [0, end_position] (:2251-2259).
                        --
                        -- SIGN (v0.2.78-dev fix for the inverted/overflowing thumb): this
                        -- scenegraph is +Y-UP. The view scrolls the LIST by `list_node.offset[2]
                        -- = +scroll_y` and notes "Positive Y shifts the stack UP (reveals lower
                        -- rows)" (_mod_tweaker_view.lua:1752-1759). gut's scroll_value is
                        -- scroll_y/max_scroll = 0 at the TOP of the content, 1 at the BOTTOM.
                        -- For the thumb to read correctly it must sit HIGH (max offset) at the
                        -- top and LOW (offset 0) at the bottom -> offset = end_position *
                        -- (1 - scroll_value). The prior v0.2.77 code used a NEGATIVE offset that
                        -- put the thumb below the track origin at scroll=0 (bottom of the track)
                        -- and let it run off the track bottom as you scrolled.
                        local frac = math.clamp(ui_content.thumb_frac or 1, 0.06, 1)
                        local th = track_h * frac
                        ui_style.thumb.size[2] = th
                        -- end_position = scroll_length - thumb_length (native :2251): the max
                        -- travel of the thumb's bottom-left origin above the track bottom.
                        local end_position = track_h - th
                        local current_position =
                            end_position * (1 - math.clamp(ui_content.scroll_value or 0, 0, 1))
                        -- Clamp to [0, end_position] so the thumb can NEVER overflow past the
                        -- track top or bottom (native :2254): bottom edge = offset (>=0) and
                        -- top edge = offset + th <= end_position + th = track_h. In-bounds.
                        ui_style.thumb.offset[2] = math.clamp(current_position, 0, end_position)
                        -- Probe hooks: resolved height + the thumb's offset[2] (bottom-left
                        -- origin above the track bottom, in node-local +Y-up coords). The view
                        -- turns these into world-Y top/bottom in the [mt:scrollbar] dump.
                        ui_content._resolved_thumb_h = th
                        ui_content._resolved_thumb_off = ui_style.thumb.offset[2]
                    end,
                },
                -- THUMB: plain rect pass; its size[2]/offset[2] are driven by the
                -- local_offset pass above (NOT a per-pass offset_function, which rect
                -- passes ignore).
                { pass_type = "rounded_background", style_id = "thumb" },  -- (#166) rounded corners like the vanilla scrollbar
                { pass_type = "hotspot", content_id = "hotspot" },
            },
        },
        content = { scroll_value = 0, thumb_frac = 1, hotspot = {} },
        style = {
            -- (v0.2.78-dev) REAL VANILLA SCROLLBAR COLORS — read straight from native
            -- create_scrollbar (ui_widgets.lua:2286-2306), the widget the Options view uses:
            --   * thumb (scroll_bar_box) default = Colors.font_button_normal =
            --     {255, 160, 146, 101} (colors.lua:1021-1026) — the warm tan. (Already this
            --     value since v0.2.76; it turns out to be the exact native default.)
            --   * track (background) default = {255, 5, 5, 5} — near-black. The previous
            --     {70,70,70} was FABRICATED; replaced with the real vanilla value so the bar
            --     reads like the in-game Options scrollbar, not an invented grey.
            -- The {8, track_h} thumb SIZE below is the SCENEGRAPH default; the local_offset
            -- pass above overwrites size[2]/offset[2] every frame (do NOT move the sizing back
            -- onto the rect pass — it would silently never run; see the pass comment above).
            track   = { offset = { 0, 0, 0 }, size = { 8, track_h }, color = { 255, 5, 5, 5 },       corner_radius = 2 },  -- (#166) vanilla corner_radius = 2
            thumb   = { offset = { 0, 0, 2 }, size = { 8, track_h }, color = { 255, 160, 146, 101 }, corner_radius = 2 },
            hotspot = { offset = { -4, 0, 3 }, size = { 16, track_h } },
        },
        offset = { 0, 0, 0 },
    })
end

-- (v0.2.70-dev) APPLY button. Hand-built (rect bg + border + hotspot + centered text),
-- like every other gut widget — NOT UIWidgets.create_text_button (which hardcodes
-- localize=true and references atlas/material backing that can miss on the borrowed
-- renderer; see the create_tab note). The view drives two content flags each frame:
--   * content.button_hotspot.is_hover -> brightens the bg/text
--   * content.disabled (no pending edits) -> greys the text + suppresses the click
-- The bg is a plain rect (no rect_masked); the border is the `border` pass (no material
-- lookup). Gold text ("cheeseburger" {255,255,168,0}) when enabled, dim grey when
-- disabled — mirroring native update_apply_button (options_view.lua:3129-3140).
local function create_apply_button()
    -- Label from the game's own loc key when it resolves cleanly (same guard as the
    -- ON/OFF stepper text); fall back to the literal so a missing key never blanks it.
    local function _loc(key, fallback)
        local ok, s = pcall(Localize, key)
        if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then return s end
        return fallback
    end
    local label = _loc("menu_settings_apply", "APPLY")
    return UIWidget.init({
        scenegraph_id = "mt_apply",
        element = {
            -- (v0.2.71-dev) BOX REMOVED — the bg `rect` + `border` passes were dropped so
            -- APPLY reads as bare text + hover (matches the user's "just text" ask). The
            -- `bg`/`border` STYLE tables below are KEPT so the per-frame writes in both
            -- twins' _draw (asty.bg.color / asty.border.color) still index a live table —
            -- they're now harmless no-ops (no pass renders them). Hover/enabled feedback
            -- lives entirely in the text color block. Hotspot stays for click + hover.
            passes = {
                { pass_type = "hotspot", content_id = "button_hotspot", style_id = "button_hotspot" },
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { button_hotspot = {}, text = tostring(label), disabled = true },
        style = {
            -- (Fix 2, v0.2.151-dev) Whole-button hit zone fits the text-fit APPLY_W node
            -- (was fixed 150). Text centers in the node size (the text pass carries no
            -- explicit size), so hotspot == node width keeps the click zone over the label.
            button_hotspot = { size = { APPLY_W, 30 }, offset = { 0, 0, 0 } },
            bg     = { offset = { 0, 0, 0 }, size = { APPLY_W, 30 }, color = { 200, 10, 10, 10 } },
            border = { offset = { 0, 0, 1 }, size = { APPLY_W, 30 }, color = { 255, 80, 80, 80 },
                       thickness = 1 },
            text   = {
                font_type = "hell_shark", font_size = 22,
                horizontal_alignment = "center", vertical_alignment = "center",
                localize = false, upper_case = true,
                -- (Fix 3, v0.2.149-dev) Base = font_button_normal {255,160,146,101} (was
                -- cheeseburger gold). Apply is the same create_text_button widget type as
                -- the tabs + Default, so it now shares their scheme: font_button_normal idle,
                -- white on hover (ENABLED). The twins' per-frame driver overwrites this each
                -- frame (idle / white-on-hover / disabled font_default α75).
                text_color = Colors.get_color_table_with_alpha("font_button_normal", 255),
                offset = { 0, 0, 2 },
            },
        },
        offset = { 0, 0, 0 },
    })
end

-- (v0.2.148-dev) RESTORE DEFAULTS button. Mirrors create_apply_button (bare text + hover,
-- no box), on the mt_reset node to Apply's LEFT. Clones native `reset_to_default`. Always
-- enabled — clicking it STAGES every current-tab setting back to its default_value (the
-- view/state twins then repaint the rows; the user clicks Apply to commit, exactly like a
-- normal staged edit). Label comes from gut's own loc key `gut_mt_reset` via mod:localize
-- (gut loc keys are NOT in the global Localize table, unlike the vanilla "menu_settings_*"
-- keys create_apply_button uses), falling back to the literal so a missing key never blanks
-- it. upper_case=true renders "Default" as "DEFAULT" like the native chrome.
local function create_default_button()
    local label = "DEFAULT"   -- (Fix 3, v0.2.149-dev) was "RESTORE DEFAULTS"; loc gut_mt_reset is now "Default"
    local ok, s = pcall(mod.localize, mod, "gut_mt_reset")
    if ok and type(s) == "string" and s ~= "" and not string.find(s, "^<") then label = s end
    return UIWidget.init({
        scenegraph_id = "mt_reset",
        element = {
            passes = {
                { pass_type = "hotspot", content_id = "button_hotspot", style_id = "button_hotspot" },
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { button_hotspot = {}, text = tostring(label) },
        style = {
            -- (Fix 2, v0.2.151-dev) Hit zone fits the text-fit RESET_W node (was fixed 150).
            button_hotspot = { size = { RESET_W, 30 }, offset = { 0, 0, 0 } },
            text   = {
                font_type = "hell_shark", font_size = 22,
                horizontal_alignment = "center", vertical_alignment = "center",
                localize = false, upper_case = true,
                -- (Fix 3, v0.2.149-dev) Base = font_button_normal {255,160,146,101} (was
                -- font_default). Matches the TAB + Apply scheme (all create_text_button in
                -- vanilla). The twins' per-frame driver sets idle = font_button_normal and
                -- brightens to white on hover (this button is always enabled).
                text_color = Colors.get_color_table_with_alpha("font_button_normal", 255),
                offset = { 0, 0, 2 },
            },
        },
        offset = { 0, 0, 0 },
    })
end

local function _profile_text_widget(scenegraph_id, text, width)
    return UIWidget.init({
        scenegraph_id = scenegraph_id,
        element = { passes = {
            { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
            { pass_type = "rect", style_id = "bg" },
            { pass_type = "text", style_id = "text", text_id = "text" },
        } },
        content = { hotspot = {}, text = text },
        style = {
            hotspot = { size = { width, 30 }, offset = { 0, 0, 0 } },
            bg = { size = { width, 30 }, offset = { 0, 0, 0 }, color = { 0, 0, 0, 0 } },
            text = { font_type = "hell_shark", font_size = 18,
                horizontal_alignment = "center", vertical_alignment = "center",
                localize = false, text_color = { 255, 160, 146, 101 },
                offset = { 0, 0, 2 } },
        },
        offset = { 0, 0, 0 },
    })
end

local function create_profile_controls()
    local profile_label = "Profiles"
    local ok, localized = pcall(mod.localize, mod, "gut_mt_profiles")
    if ok and type(localized) == "string" and localized ~= ""
            and not string.find(localized, "^<") then
        profile_label = localized
    end
    local label = _profile_text_widget("mt_profiles_label", profile_label, 90)
    local buttons = {}
    for i = 1, 10 do
        buttons[i] = _profile_text_widget("mt_profile_" .. i, tostring(i), 28)
    end
    return label, buttons
end

-- (#497) SEARCH box node + factory. The node sits in the band freed above list_mask
-- (see SEARCH_BAND_H): parented to background_frame (the fixed centred panel, NOT the
-- scrolling list) so it never moves, left-aligned at x=58 = list_mask inset (18) +
-- mt_list_start inset (40) so its left edge lines up with the row content, and width =
-- ROW_W so it spans the row-content column exactly ("flush with the length of the menu").
-- _LIST_WINDOW_H is the ORIGINAL list height (captured before the shrink above), so
-- _LIST_TOP is the original top margin; the box is vertically centred in the freed band.
local _LIST_TOP = (WINDOW_HEIGHT - _LIST_WINDOW_H) / 2
scenegraph_definition.mt_search = {
    parent = "background_frame",
    horizontal_alignment = "left",
    vertical_alignment = "top",
    position = { 58, -(_LIST_TOP + (SEARCH_BAND_H - SEARCH_BOX_H) / 2), 6 },
    size = { ROW_W, SEARCH_BOX_H },
}

-- (#497) Per-tab SEARCH box widget. A fixed (non-scrolling) input field. The view focuses it
-- on click, captures printable keystrokes into self._search_str (Keyboard.keystrokes -- the
-- SAME raw path the numeric type-to-edit uses), and re-filters the current tab's rows live.
-- The view drives content.text each frame (the query + a blink caret when focused, or the
-- placeholder when empty+unfocused) and style.text.text_color / style.bg_inner.color for
-- focus emphasis. #572 reuses the exact atlas-backed inventory search material from
-- HeroWindowCraftingInventoryConsole (`search_filters_icon`, gui_menus_atlas), so no
-- custom asset/package is introduced. The icon is a passive texture pass: the existing
-- full-field hotspot remains the only focus/click target. #572 follow-up: render the
-- padded tile at 95px (112px reduced by 15%, rounded), translate its visible glyph into
-- the field, and hide it while typing.
local function search_icon_visible(content)
    return not content.search_focused
end

local function create_search_box()
    local W, H, PAD = ROW_W, SEARCH_BOX_H, 14
    -- The atlas entry is a padded 128x128 tile. Vanilla's negative offset belongs to a
    -- separate inventory filter-control region; copying it to this full-width field put
    -- the visible glyph outside the bar. Render the padded tile 15% smaller than #572's
    -- prior 112px pass and translate its centred art wholly inside the field (about x=8..32).
    -- Vanilla centers the 128px atlas tile at y=-4. Preserve that optical
    -- alignment at our 95px scale: round(-4 * 95 / 128) = -3 design pixels.
    local ICON_TEXTURE, ICON_SIZE, ICON_X, ICON_Y = "search_filters_icon", 95, -28, -3
    local TEXT_X = 47
    return UIWidget.init({
        scenegraph_id = "mt_search",
        element = {
            passes = {
                { pass_type = "rect", style_id = "bg_outer" },
                { pass_type = "rect", style_id = "bg_inner" },
                { pass_type = "texture", style_id = "search_icon", texture_id = "search_icon",
                  content_check_function = search_icon_visible },
                { pass_type = "hotspot", content_id = "hotspot", style_id = "hotspot" },
                { pass_type = "text", style_id = "text", text_id = "text" },
            },
        },
        content = { hotspot = {}, text = "", search_icon = ICON_TEXTURE, search_focused = false },
        style = {
            bg_outer = { offset = { 0, 0, 1 }, size = { W, H }, color = { 220, 0, 0, 0 } },
            bg_inner = { offset = { 2, 2, 2 }, size = { W - 4, H - 4 }, color = { 255, 14, 14, 14 } },
            search_icon = {
                horizontal_alignment = "left", vertical_alignment = "center",
                texture_size = { ICON_SIZE, ICON_SIZE }, offset = { ICON_X, ICON_Y, 3 },
                color = { 255, 255, 255, 255 },
                base_color = { 255, 255, 255, 255 },
                disabled_color = { 128, 128, 128, 128 },
            },
            hotspot  = { size = { W, H }, offset = { 0, 0, 0 } },
            text = {
                font_type = "hell_shark", font_size = 20,
                horizontal_alignment = "left", vertical_alignment = "center",
                localize = false, upper_case = false, word_wrap = false,
                text_color = { 255, 255, 255, 255 },
                offset = { TEXT_X, 0, 4 }, size = { W - TEXT_X - PAD, H },
            },
        },
        offset = { 0, 0, 0 },
    })
end

return {
    scenegraph_definition = scenegraph_definition,
    list_sg = LIST_SG,
    list_node = "mt_list",
    scrollbar_sg = "mt_scrollbar",
    list_mask_sg = "list_mask",
    build_scrollbar_rect = build_scrollbar_rect,
    window = { w = WINDOW_WIDTH, h = WINDOW_HEIGHT, list_mask_w = LIST_MASK_W },
    build_chrome = build_chrome,
    build_exit_button = build_exit_button,
    build_scrollbar = build_scrollbar,
    create_apply_button = create_apply_button,
    apply_sg = "mt_apply",
    create_default_button = create_default_button,
    reset_sg = "mt_reset",
    create_profile_controls = create_profile_controls,
    create_tab = create_tab,
    -- (#497) Per-tab search box (fixed input field above the list).
    create_search_box = create_search_box,
    search_sg = "mt_search",
    search_icon_contract = {
        texture = "search_filters_icon", native_size = 128, size = 95,
        previous_size = 112, scale_from_previous = 95 / 112,
        scale = 0.7421875, icon_x = -28, icon_y = -3,
        native_icon_y = -4,
        visible_left = 8, visible_right = 32, text_x = 47,
        hotspot_w = ROW_W, hotspot_h = SEARCH_BOX_H,
        focus_content_key = "search_focused",
        source = "HeroWindowCraftingInventoryConsole",
    },
    search_icon_visible = search_icon_visible,
    create_checkbox = create_checkbox,
    create_slider = create_slider,
    create_stepper = create_stepper,
    create_dropdown = create_dropdown,
    create_dropdown_list = create_dropdown_list,
    dropdown_sg = "mt_dropdown",
    -- (#207) Hover info popup (native-style per-setting tooltip) — hand-built for the
    -- borrowed renderer (rect bg + frame + title/desc text). layout_tooltip sizes/positions
    -- + fades it each frame from the view's draw loop.
    create_tooltip_popup = create_tooltip_popup,
    layout_tooltip = layout_tooltip,
    tooltip_sg = "mt_tooltip",
    create_section_title = create_section_title,
    create_group_header = create_group_header,
    create_dialogue_row = create_dialogue_row,
    create_gear_button = create_gear_button,
    create_back_row = create_back_row,
    -- (v0.2.75-dev) Shared drill subtree planner — both twins build a drilled view's
    -- child rows from this so a 3-deep dropdown (checkbox -> group -> dropdown) is reached.
    plan_drill_children = plan_drill_children,
    -- #575 exact native-metric click/caret helpers shared by both presentations.
    numeric_caret_x = numeric_caret_x,
    numeric_caret_index = numeric_caret_index,
    -- Geometry the view needs to trim a gear-parent's whole-row hotspot so it doesn't
    -- overlap (and double-fire with) the gear in the 3rd column.
    row_w = ROW_W,
    gear_col_w = GEAR_SIZE + 24,
}
