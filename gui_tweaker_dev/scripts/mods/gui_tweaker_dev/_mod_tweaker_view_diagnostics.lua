local mod = get_mod("gut_dev")

-- Standalone Mod Tweaker render-state probes.
--
-- These diagnostics are debug-gated by their callers. Keeping them in one
-- install-only owner prevents the presentation class from exceeding the
-- repository's hard source-size ceiling; this module registers no hooks,
-- lifecycle callbacks, commands, or per-frame work.
local M = {}

function M.install(ModTweakerView, deps)
    local defs = assert(deps.defs, "Mod Tweaker diagnostics require defs")
    local UISceneGraph = assert(deps.UISceneGraph,
        "Mod Tweaker diagnostics require UISceneGraph")
    local math = assert(deps.math, "Mod Tweaker diagnostics require math")

    function ModTweakerView:_dump_state(reason)
        local sg = self.ui_scenegraph
        local function wp(id)
            local ok, p = pcall(UISceneGraph.get_world_position, sg, id)
            if ok and p then return string.format("{%.0f,%.0f,%.0f}", p[1], p[2], p[3]) end
            return "?"
        end
        local function sz(id)
            local ok, s = pcall(UISceneGraph.get_size, sg, id)
            if ok and s then return string.format("{%.0f,%.0f}", s[1], s[2]) end
            return "?"
        end
        mod:info("[mt:dump] (%s) active=%s alpha=%s categories=%d selected=%d tabs=%d rows=%d chrome=%d exit=%s scrollbar=%s",
            tostring(reason), tostring(self._active), tostring(self.render_settings.alpha_multiplier),
            #(self._categories or {}), self._selected or -1, #(self._tabs or {}), #(self._rows or {}),
            #(self._chrome or {}), tostring(self._exit ~= nil), tostring(self._scrollbar ~= nil))
        mod:info("[mt:dump] world: background=%s(%s) top_panel=%s(%s) list_mask=%s(%s) list_start=%s | screen=1920x1080",
            wp("background"), sz("background"), wp("background_top_panel"), sz("background_top_panel"),
            wp("list_mask"), sz("list_mask"), wp("mt_list_start"))
        for i = 1, math.min(#(self._tabs or {}), 8) do
            mod:info("[mt:dump]   tab[%d] '%s' world=%s", i,
                tostring(self._tabs[i].content.text_field), wp("mt_tab_" .. i))
        end
        for i = 1, math.min(#(self._rows or {}), 12) do
            local row = self._rows[i]
            local off = row.style and row.style.offset
            mod:info("[mt:dump]   row[%d] type=%s id=%s flag=%s value=%s offset=%s",
                i, tostring(row._wtype), tostring(row._setting_id),
                tostring(row.content.flag), tostring(row.content.value),
                off and string.format("{%.0f,%.0f}", off[1], off[2]) or "?")
        end
    end

    function ModTweakerView:_dump_scrollbar(reason)
        local sg = self.ui_scenegraph
        local function wp(id)
            local ok, p = pcall(UISceneGraph.get_world_position, sg, id)
            if ok and p then return string.format("{%.0f,%.0f,%.0f}", p[1], p[2], p[3]) end
            return "?"
        end
        local function sz(id)
            local ok, s = pcall(UISceneGraph.get_size, sg, id)
            if ok and s then return string.format("{%.0f,%.0f}", s[1], s[2]) end
            return "?"
        end
        local function color_of(style_tbl)
            if type(style_tbl) ~= "table" then return "?" end
            local c = style_tbl.color
            if type(c) == "table" and c[1] then
                return string.format("{A%d,R%d,G%d,B%d}", c[1], c[2] or 0, c[3] or 0, c[4] or 0)
            end
            return "?"
        end

        local bg = self._chrome and self._chrome[1]
        local bg_style = bg and bg.style and bg.style.rect
        mod:info("[mt:scrollbar] (%s) BACKGROUND chrome[1] color=%s sg_world=%s sg_size=%s",
            tostring(reason), color_of(bg_style), wp("background"), sz("background"))
        mod:info("[mt:scrollbar]   top_panel=%s(%s) bottom_panel=%s(%s) list_mask=%s(%s)",
            wp("background_top_panel"), sz("background_top_panel"),
            wp("background_bottom_panel"), sz("background_bottom_panel"),
            wp("list_mask"), sz("list_mask"))

        local sb = self._scrollbar
        local st = sb and sb.style
        local track_z = st and st.track and st.track.offset and st.track.offset[3]
        local thumb_z = st and st.thumb and st.thumb.offset and st.thumb.offset[3]
        mod:info("[mt:scrollbar]   TRACK color=%s sg=%s world=%s size=%s track_z=%s thumb_z=%s",
            color_of(st and st.track), defs.scrollbar_sg, wp(defs.scrollbar_sg), sz(defs.scrollbar_sg),
            tostring(track_z), tostring(thumb_z))
        local resolved_h = sb and sb.content and sb.content._resolved_thumb_h
        local resolved_off = sb and sb.content and sb.content._resolved_thumb_off
        mod:info("[mt:scrollbar]   THUMB color=%s style_size=%s style_off=%s resolved_h=%s resolved_off=%s",
            color_of(st and st.thumb),
            (st and st.thumb and st.thumb.size) and string.format("{%.0f,%.0f}", st.thumb.size[1], st.thumb.size[2]) or "?",
            (st and st.thumb and st.thumb.offset) and string.format("{%.0f,%.0f,%.0f}", st.thumb.offset[1], st.thumb.offset[2], st.thumb.offset[3]) or "?",
            resolved_h and string.format("%.1f", resolved_h) or "nil(pass-not-run)",
            resolved_off and string.format("%.1f", resolved_off) or "nil")
        do
            local ok_n, np = pcall(UISceneGraph.get_world_position, sg, defs.scrollbar_sg)
            local track_h = (st and st.track and st.track.size and st.track.size[2]) or 0
            if ok_n and np and resolved_off and resolved_h then
                local node_y = np[2]
                local thumb_bottom = node_y + resolved_off
                local thumb_top = thumb_bottom + resolved_h
                mod:info("[mt:scrollbar]   THUMB world-Y bottom=%.1f top=%.1f vs TRACK span [%.1f, %.1f] scroll_value=%s",
                    thumb_bottom, thumb_top, node_y, node_y + track_h,
                    sb and sb.content and tostring(sb.content.scroll_value) or "nil")
            else
                mod:info("[mt:scrollbar]   THUMB world-Y=? (node world pos or resolved thumb values unavailable — pass not run yet?)")
            end
        end

        local content_h = self._content_h or 0
        local visible_h = self._visible_h or 0
        local max_scroll = self._max_scroll or 0
        local track_h = (sb and sb.style and sb.style.track and sb.style.track.size and sb.style.track.size[2]) or 0
        local thumb_frac = (content_h > 0) and (visible_h / content_h) or 1
        local clamped = math.clamp(thumb_frac, 0.06, 1)
        local thumb_px = track_h * clamped
        mod:info("[mt:scrollbar]   content_h=%.0f visible_h=%.0f max_scroll=%.0f track_h=%.0f thumb_frac=%.3f (clamped %.3f) thumb_px=%.1f will_draw=%s",
            content_h, visible_h, max_scroll, track_h, thumb_frac, clamped, thumb_px,
            tostring(max_scroll > 0))

        local ok_sbp, sbp = pcall(UISceneGraph.get_world_position, sg, defs.scrollbar_sg)
        local ok_sbs, sbs = pcall(UISceneGraph.get_size, sg, defs.scrollbar_sg)
        local ok_fp, fp = pcall(UISceneGraph.get_world_position, sg, "background_frame")
        local ok_fs, fs = pcall(UISceneGraph.get_size, sg, "background_frame")
        if ok_sbp and sbp and ok_sbs and sbs and ok_fp and fp and ok_fs and fs then
            local cx, cy = sbp[1] + sbs[1] * 0.5, sbp[2] + sbs[2] * 0.5
            local inside = math.point_is_inside_2d_box({ cx, cy }, fp, fs)
            mod:info("[mt:scrollbar]   on_screen=%s sb_centre={%.0f,%.0f} vs frame origin={%.0f,%.0f} size={%.0f,%.0f}",
                tostring(inside), cx, cy, fp[1], fp[2], fs[1], fs[2])
        else
            mod:info("[mt:scrollbar]   on_screen=? (world/size lookup failed)")
        end
    end

    return ModTweakerView
end

return M
