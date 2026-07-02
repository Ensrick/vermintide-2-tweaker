local mod = get_mod("gut")

-- ============================================================================
-- Respawn countdown over a dead teammate's portrait (optional)
-- ============================================================================
-- Shows a large number (seconds till respawn, one decimal) over a teammate's
-- portrait while it's in the dead/skull state.
--
-- Why an estimate: VT2 Adventure has NO client-synced respawn countdown. The
-- authoritative timer (`respawn_handler.lua` -> game_mode_data.respawn_timer) is
-- host-only and on a plain non-networked Lua table, so a client can't read it.
-- What IS client-safe is the teammate frame's `data.is_dead` flag — set by
-- UnitFramesHandler from the networked status extension (husk-safe), and it's the
-- exact signal that drives the dead-skull portrait. So we anchor a countdown to
-- the moment that flag flips true and tick down RESPAWN_TIME (30, or the
-- mechanism's hero_respawn_time). It can read a touch early if the host has a
-- faster_respawn buff (invisible to clients); clamped at 0.
--
-- Teammates only (`_frame_type == "team"`); your own death uses the game's overlay.
-- Drawn over the frame's "portrait_pivot" node (team_member_unit_frame_ui_definitions).
-- Hooks UnitFrameUI.draw (post) — gut/hb don't hook it, so no collision.

local UIRenderer    = UIRenderer
local UISceneGraph  = UISceneGraph
local Vector3       = Vector3

local RESPAWN_TIME   = 30                       -- respawn_handler.lua:7 (Adventure default)
local FONT_MATERIAL  = "materials/fonts/arial"  -- proven to render with a nil font-name (HudCustomizer)
local _render_settings = { snap_pixel_positions = true }
local _stamp = setmetatable({}, { __mode = "k" })  -- frame -> death-onset game-time (weak keys)

local function _draw_number(self, secs)
    local sg = self.ui_scenegraph
    local renderer = self.ui_renderer
    if not (sg and renderer) then return end
    local ok_pos, pos = pcall(UISceneGraph.get_world_position, sg, "portrait_pivot")
    if not ok_pos or not pos then return end

    local size = mod:get("gut_respawn_font_size") or 32
    local r = mod:get("gut_respawn_r") or 255
    local g = mod:get("gut_respawn_g") or 60
    local b = mod:get("gut_respawn_b") or 60
    local text = string.format("%.1f", secs)

    -- centre horizontally on the portrait pivot
    local tw = 0
    local ok_sz, w = pcall(UIRenderer.text_size, renderer, text, FONT_MATERIAL, size)
    if ok_sz and w then tw = w end
    local x = pos[1] - tw * 0.5
    local y = pos[2]
    local input = self.input_manager and self.input_manager:get_service("ingame_menu")

    UIRenderer.begin_pass(renderer, sg, input, 0, nil, _render_settings)
    UIRenderer.draw_text(renderer, text, FONT_MATERIAL, size, nil, Vector3(x + 2, y - 2, 990), { 200, 0, 0, 0 })
    UIRenderer.draw_text(renderer, text, FONT_MATERIAL, size, nil, Vector3(x, y, 991), { 255, r, g, b })
    UIRenderer.end_pass(renderer)
end

mod:hook_safe("UnitFrameUI", "draw", function(self, dt)
    if not mod:get("gut_respawn_timer") then return end
    if self._frame_type ~= "team" then return end          -- teammates only
    local data = self.data
    if not data then return end

    -- The dead/skull state (is_dead, before assisted respawn kicks in).
    if data.is_dead and not data.assisted_respawn then
        local now = Managers.time:time("game")
        local t0 = _stamp[self]
        if not t0 then
            t0 = now
            _stamp[self] = now
        end
        local total = (Managers.mechanism and Managers.mechanism:setting("hero_respawn_time")) or RESPAWN_TIME
        local secs = total - (now - t0)
        if secs < 0 then secs = 0 end
        _draw_number(self, secs)
    else
        _stamp[self] = nil
    end
end)

mod:info("[gut] Respawn timer widget installed (dead-teammate portrait countdown; toggle: %s)",
    tostring(mod:get("gut_respawn_timer")))

return {}
