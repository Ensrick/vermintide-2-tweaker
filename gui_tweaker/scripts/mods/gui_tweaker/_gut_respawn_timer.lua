local mod = get_mod("gut")

-- ============================================================================
-- Respawn countdown over a dead teammate's portrait (optional)  [#285]
-- ============================================================================
-- Shows a large number (seconds till respawn) centred on a dead teammate's HUD
-- portrait.
--
-- Why an estimate: VT2 Adventure has NO client-synced respawn countdown. The
-- authoritative timer (respawn_handler.lua -> respawn_time) is host-only on a
-- plain non-networked Lua table, so a client cannot read it. We anchor a
-- countdown to the game-time at which the frame's `data.is_dead` flag flips true
-- (unit_frames_handler.lua:775-776, set from `status_extension:is_dead()`) and
-- tick down the mechanism's hero_respawn_time (30 default). It can read a touch
-- early if the host has a faster_respawn buff (invisible to clients); clamped at
-- 0. Teammates only (`_frame_type == "team"`); your own death uses the game's
-- own overlay. Works for a pure client joining someone else's lobby: nothing is
-- read from host state, only the local frame's dead flag + the mechanism setting
-- (populated on every peer at mission load).
--
-- #285 HISTORY (two defects, two fixes):
--   1. Rendered NOTHING (fixed v0.2.183-dev): the original drew immediate-mode
--      text from a hook_safe on UnitFrameUI.draw, onto the team frame's own
--      retained ui_renderer -- a pass that early-returns on `not self._dirty`
--      once a dead portrait settles, so nothing composited. Moved to
--      IngameHud.update.
--   2. Drew in the WRONG SPOT + TINY (this fix): the v0.2.183 rewrite drew
--      immediate `draw_text` at `UISceneGraph.get_world_position(...)`. But a
--      node's world_position is ALREADY inverse_scale-transformed for the
--      resolution (ui_scenegraph.lua:249-252, hud_scale_fit branch); passing it
--      as an absolute draw coordinate inside a begin_pass makes UIRenderer apply
--      the resolution scale a SECOND time, shifting the number off the portrait
--      and onto the health/ability bar. Font defaulted to 32 -> "tiny".
--
-- FIX -- port the exact widget-based mechanism of the "复活CD / Respawn CD (beta)"
-- Workshop mod (id 3747644100, bundle 6e7d92af18da0995, decompiled clean). Build
-- our own scenegraph that MIRRORS the vanilla team frame's hierarchy (root
-- hud_scale_fit 1920x1080 -> pivot_parent{50,0} -> pivot -> portrait_pivot), set
-- our `pivot` node's LOCAL position to the dead teammate's own team-frame
-- `pivot.position` (the on-screen slot UnitFrameUI.set_position writes at
-- unit_frame_ui.lua:117, and `.position` aliases `.local_position` --
-- ui_scenegraph.lua:83), then draw a UIWidget through that scenegraph with
-- UIRenderer.draw_widget. Feeding a LOCAL position through an identical
-- hierarchy lets update_scenegraph (run inside begin_pass, ui_renderer.lua:344)
-- apply the hud_scale_fit transform EXACTLY ONCE, so the number lands on the
-- portrait pixel-for-pixel with the reference. Widget offsets/size/alignment and
-- the teammate font base (72, hell_shark_header -> materials/fonts/gw_head,
-- ui_fonts.lua:58) are copied verbatim from the reference's `team_respawn_text`.

local UIRenderer   = UIRenderer
local UISceneGraph = UISceneGraph
local UIWidget     = UIWidget

local RESPAWN_TIME   = 30                   -- respawn_handler.lua:7 (Adventure default)
local SIZE_X, SIZE_Y = 1920, 1080
local PORTRAIT_SCALE = 1

-- Mirror of Respawn CD's scenegraph_definition (Respawn_CD_data.lua:110-179).
-- `pivot.position` gets overwritten per dead teammate from their team frame.
local SCENEGRAPH_DEF = {
    root         = { scale = "hud_scale_fit", position = { 0, 0, (UILayer and UILayer.hud) or 100 }, size = { SIZE_X, SIZE_Y } },
    pivot_parent = { parent = "root",         vertical_alignment = "top",    horizontal_alignment = "left",   position = { 50, 0, 1 }, size = { 0, 0 } },
    pivot        = { parent = "pivot_parent", vertical_alignment = "top",    horizontal_alignment = "left",   position = { 0, 0, 1 },  size = { 0, 0 } },
    portrait_pivot = { parent = "pivot",      vertical_alignment = "center", horizontal_alignment = "center", position = { 0, 0, 0 },  size = { 0, 0 } },
}

-- Mirror of Respawn CD's `team_respawn_text` widget (Respawn_CD_data.lua:60-109):
-- one centred countdown number on the portrait_pivot node, big header font, 2px
-- drop shadow. font_size (72 base) + text_color are re-stamped each draw from the
-- gut settings; content is the integer seconds.
local TEAM_WIDGET_DEF = {
    scenegraph_id = "pivot",
    element = {
        passes = {
            { text_id = "respawn_countdown_text", style_id = "respawn_countdown_text", pass_type = "text", retained_mode = false },
        },
    },
    content = { respawn_countdown_text = "" },
    style = {
        respawn_countdown_text = {
            horizontal_alignment = "center",
            vertical_alignment   = "center",
            scenegraph_id        = "portrait_pivot",
            font_size            = 72,                 -- reference teammate base (Respawn_CD_main.lua:131)
            font_type            = "hell_shark_header",
            size                 = { PORTRAIT_SCALE * 86, PORTRAIT_SCALE * 108 },
            text_color           = { 255, 255, 255, 255 },  -- {alpha, r, g, b}
            offset               = { -(PORTRAIT_SCALE * 86) / 2, -(PORTRAIT_SCALE * 108) / 2, 50 },
            shadow_offset        = { 2, 2, 0 },
        },
    },
    offset = { 0, PORTRAIT_SCALE * -55, 0 },
}

local _render_settings = { snap_pixel_positions = true }
local _scenegraph      = nil
local _widget          = nil
local _onset           = {}  -- unique_id -> game-time at death onset
local _dummy_input     = { get = function() return end, has = function() return end }

local function _respawn_total()
    local m = Managers.mechanism
    return (m and m:setting("hero_respawn_time")) or RESPAWN_TIME
end

-- Hide the number over an open scoreboard/menu/view, matching the reference mod.
local function _menu_blocks_draw(self)
    local plist = self:component("IngamePlayerListUI")
    if plist and plist.is_active and plist:is_active() then return true end
    local ingame_ui = self:parent()
    if ingame_ui and (ingame_ui.menu_active or ingame_ui.current_view ~= nil) then return true end
    return false
end

-- Draw one teammate's countdown widget at `node_pos` (their frame's pivot LOCAL
-- position). Exposed on `mod` so the #285 regression test can locate this file.
mod._gut_respawn_draw = function(renderer, input, dt, node_pos, secs, font_size, r, g, b)
    if not _scenegraph then _scenegraph = UISceneGraph.init_scenegraph(SCENEGRAPH_DEF) end
    if not _widget     then _widget     = UIWidget.init(TEAM_WIDGET_DEF) end

    local lp = _scenegraph.pivot.local_position
    lp[1], lp[2], lp[3] = node_pos[1], node_pos[2], node_pos[3] or 0

    _widget.content.respawn_countdown_text = tostring(math.floor(secs))
    local style = _widget.style.respawn_countdown_text
    style.font_size = font_size
    local tc = style.text_color
    tc[1], tc[2], tc[3], tc[4] = 255, r, g, b

    UIRenderer.begin_pass(renderer, _scenegraph, input, dt, nil, _render_settings)
    UIRenderer.draw_widget(renderer, _widget)
    UIRenderer.end_pass(renderer)
end

mod:hook_safe("IngameHud", "update", function(self, dt, t)
    if not mod:get("gut_respawn_timer") then return end

    local handler = self:component("UnitFramesHandler")
    if not (handler and handler._unit_frames) then return end
    if _menu_blocks_draw(self) then return end

    local renderer = (self._ingame_ui_context and self._ingame_ui_context.ui_renderer)
        or (Managers.ui and Managers.ui._ingame_ui_context and Managers.ui._ingame_ui_context.ui_top_renderer)
    if not renderer then return end

    local now = Managers.time and Managers.time:time("game")
    if not now then return end

    local total     = _respawn_total()
    local font_size = mod:get("gut_respawn_font_size") or 72
    local r         = mod:get("gut_respawn_r") or 255
    local g         = mod:get("gut_respawn_g") or 255
    local b         = mod:get("gut_respawn_b") or 255
    local input     = (self._ingame_ui_context and self._ingame_ui_context.input_manager
        and self._ingame_ui_context.input_manager:get_service("ingame_menu")) or _dummy_input

    local seen = {}
    for i = 1, #handler._unit_frames do
        local uf     = handler._unit_frames[i]
        local widget = uf and uf.widget
        local data   = uf and uf.data
        local player = uf and uf.player_data and uf.player_data.player
        -- Teammates only; skip the local player's own frame (_frame_type == "player").
        if widget and data and player and widget._frame_type == "team" then
            local uid = player.unique_id and player:unique_id()
            if uid and data.is_dead and not data.assisted_respawn then
                seen[uid] = true
                local t0 = _onset[uid]
                if not t0 then t0 = now; _onset[uid] = now end
                local secs = total - (now - t0)
                if secs < 0 then secs = 0 end

                -- Read the frame's OWN pivot LOCAL position (its on-screen slot,
                -- unit_frame_ui.lua:117). `.position` aliases `.local_position`
                -- (ui_scenegraph.lua:83) so it is the slot, not a world coord.
                local ws    = widget.ui_scenegraph
                local pivot = ws and ws.pivot
                if pivot and pivot.position then
                    mod._gut_respawn_draw(renderer, input, dt, pivot.position, secs, font_size, r, g, b)
                end
            end
        end
    end

    -- Release onset stamps for anyone no longer dead / gone. On a mission load
    -- the team frames vanish, so every stamp is released here next frame -- no
    -- stale onset carries across missions, and the scenegraph/widget templates
    -- are stateless UI defs that are safe to persist.
    for uid in pairs(_onset) do
        if not seen[uid] then _onset[uid] = nil end
    end
end)

return {}
