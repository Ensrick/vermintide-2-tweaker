local mod = get_mod("gut_dev")

-- ============================================================================
-- Respawn countdown over a dead teammate's portrait (optional)  [#285]
-- ============================================================================
-- Shows a large number (seconds till respawn, one decimal) centred on a dead
-- teammate's HUD portrait.
--
-- Why an estimate: VT2 Adventure has NO client-synced respawn countdown. The
-- authoritative timer (respawn_handler.lua -> respawn_time) is host-only on a
-- plain non-networked Lua table, so a client cannot read it. We anchor a
-- countdown to the game-time at which the frame's `data.is_dead` flag flips true
-- (unit_frames_handler.lua:775-776, set from `status_extension:is_dead()` at
-- :704) and tick down the mechanism's hero_respawn_time (30 default). It can read
-- a touch early if the host has a faster_respawn buff (invisible to clients);
-- clamped at 0. Teammates only (`_frame_type == "team"`); your own death uses the
-- game's own overlay.
--
-- #285 ROOT CAUSE (the old implementation drew nothing): every symbol it used was
-- individually valid, but it drew from a hook_safe on UnitFrameUI.draw and
-- issued its own begin_pass/draw_text/end_pass on the LIVE frame's own retained
-- ui_renderer + ui_scenegraph, right after the frame's own draw (which itself
-- early-returns on `not self._dirty` -- the steady state of a settled dead-skull
-- portrait). Piggybacking an immediate-mode pass onto that per-frame retained
-- renderer never composited to screen.
--
-- FIX -- port the mechanism proven by the "复活CD / Respawn CD (beta)" Workshop
-- mod (id 3747644100): drive the draw from `IngameHud.update` (ingame_hud.lua:372,
-- unhooked by gut) using IngameHud's own HUD renderer (the same one gut's HUD
-- customizer draws its overlay on -- gui_tweaker_dev.lua:660), through our own
-- throwaway root scenegraph. Position is read from the live UnitFramesHandler
-- component's team-frame "portrait_pivot" node (team_member_unit_frame_ui_
-- definitions.lua:72). Font is the same one Respawn CD uses for its number:
-- hell_shark_header -> material "materials/fonts/gw_head", font "gw_head"
-- (ui_fonts.lua:58).

local UIRenderer   = UIRenderer
local UISceneGraph = UISceneGraph
local Vector3      = Vector3

local RESPAWN_TIME  = 30                         -- respawn_handler.lua:7 (Adventure default)
local FONT_MATERIAL = "materials/fonts/gw_head"  -- Fonts.hell_shark_header[1] (ui_fonts.lua:58)
local FONT_NAME     = "gw_head"                   -- Fonts.hell_shark_header[3]
local ROOT_SG_DEF   = {
    root = { scale = "hud_scale_fit", position = { 0, 0, (UILayer and UILayer.hud) or 100 }, size = { 1920, 1080 } },
}
local _render_settings = { snap_pixel_positions = true }
local _scenegraph      = nil
local _onset           = {}  -- unique_id -> game-time at death onset

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

-- Draw one centred number (with a 1px shadow) at a portrait's screen position.
local function _draw_number(renderer, cx, cy, secs, size)
    local r = mod:get("gut_respawn_r") or 255
    local g = mod:get("gut_respawn_g") or 60
    local b = mod:get("gut_respawn_b") or 60
    local text = string.format("%.1f", secs)

    local tw = 0
    local ok_sz, w = pcall(UIRenderer.text_size, renderer, text, FONT_MATERIAL, size, FONT_NAME)
    if ok_sz and w then tw = w end
    local x = cx - tw * 0.5
    local y = cy

    UIRenderer.draw_text(renderer, text, FONT_MATERIAL, size, FONT_NAME, Vector3(x + 2, y - 2, 990), { 200, 0, 0, 0 })
    UIRenderer.draw_text(renderer, text, FONT_MATERIAL, size, FONT_NAME, Vector3(x, y, 991), { 255, r, g, b })
end
mod._gut_respawn_draw = _draw_number  -- exposed so the regression test can locate this file

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

    local total = _respawn_total()
    local size  = mod:get("gut_respawn_font_size") or 32
    local input = self._ingame_ui_context and self._ingame_ui_context.input_manager
        and self._ingame_ui_context.input_manager:get_service("ingame_menu")
    if not _scenegraph then _scenegraph = UISceneGraph.init_scenegraph(ROOT_SG_DEF) end

    local began, seen = false, {}
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

                local ok_pos, pos = pcall(UISceneGraph.get_world_position, widget.ui_scenegraph, "portrait_pivot")
                if ok_pos and pos then
                    if not began then
                        UIRenderer.begin_pass(renderer, _scenegraph, input, dt, nil, _render_settings)
                        began = true
                    end
                    _draw_number(renderer, pos[1], pos[2], secs, size)
                end
            end
        end
    end
    if began then UIRenderer.end_pass(renderer) end

    -- Release onset stamps for anyone no longer dead / gone.
    for uid in pairs(_onset) do
        if not seen[uid] then _onset[uid] = nil end
    end
end)

return {}
