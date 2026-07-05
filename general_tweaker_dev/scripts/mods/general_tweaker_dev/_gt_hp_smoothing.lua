local mod = get_mod("gt_dev")

-- _gt_hp_smoothing.lua -- presentation-only smoothing of the local player's own
-- HUD health-bar drop.
--
-- Issue #308 (Melee Latency Smoothing). Under latency, damage reaches a client
-- as a batched `rpc_add_damage`, so the displayed bar can jump in a chunk. This
-- eases the DISPLAYED fill of the local player's own unit-frame health bar down
-- to the new value over a configurable window, so a sudden loss reads more
-- smoothly. It is strictly cosmetic: it never reads or writes any health
-- extension, only the widget's `content.total_health_bar.bar_value`.
--
-- Rules: only DOWNWARD changes are eased; heals / upward snapshots apply
-- instantly; knockdown and death SNAP (read from the frame's own
-- `self.data.is_knocked_down` / `self.data.is_dead`, unit_frames_handler.lua:
-- 707/739). Only the local player's own frame is touched -- `self._frame_type
-- == "player"` (unit_frame_ui.lua:31); teammate/enemy frames pass through.
--
-- Hook points (string-form / lazy -- UnitFrameUI loads in-mission, not at file
-- scope; grep-verified there is no other gt_dev hook on either method):
--   * UnitFrameUI.set_total_health_percentage (unit_frame_ui.lua:765) -- captures
--     the incoming target fraction as it arrives (bursty, not per-frame).
--   * UnitFrameUI.update (unit_frame_ui.lua:242) -- per-frame; writes our eased
--     value into content.total_health_bar.bar_value AFTER vanilla's own lerp ran
--     (hook_safe runs post-original), so we simply own the local player's fill.
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile.

-- Single-instance state (there is exactly one "player" frame). Reset when the
-- widget identity changes (mission transition rebuilds the frame).
local _st = {
    widget    = nil,   -- the UnitFrameUI instance we are smoothing
    displayed = nil,   -- currently-shown fraction (0..1, already * multiplier)
    target    = nil,   -- fraction we are easing toward
    from      = nil,   -- fraction the current ease started from
    elapsed   = 0,     -- seconds into the current ease
    dur       = 0,     -- ease duration (s); 0 = settled / snapped
}

local function _reset_to(widget, target)
    _st.widget    = widget
    _st.displayed = target
    _st.target    = target
    _st.from      = target
    _st.elapsed   = 0
    _st.dur       = 0
end

-- Capture a new target for the player frame. Upward / first-sight -> snap;
-- downward -> begin an ease from the currently-displayed value over the window.
local function _capture(widget, target)
    if _st.widget ~= widget or _st.displayed == nil then
        _reset_to(widget, target)
        return
    end
    if target >= _st.displayed then
        -- heal / snapshot up -> instant
        _st.displayed = target
        _st.target    = target
        _st.from      = target
        _st.elapsed   = 0
        _st.dur       = 0
    else
        -- damage -> ease down over the configured window
        _st.from    = _st.displayed
        _st.target  = target
        _st.elapsed = 0
        _st.dur     = (tonumber(mod:get("gt_hp_smoothing_ms")) or 150) / 1000
    end
end

-- ============================================================
-- Capture hook: observe the target fraction as vanilla receives it.
-- ============================================================
-- set_total_health_percentage(self, total_health_percentage, health_multiplier)
-- -- unit_frame_ui.lua:765. The displayed target vanilla animates to is
-- pct * multiplier (matches _on_player_total_health_changed at :1235), so we
-- track the same value and converge exactly when settled.
mod:hook_safe("UnitFrameUI", "set_total_health_percentage", function(self, total_health_percentage, health_multiplier)
    if not mod:get("gt_hp_smoothing") then return end
    if self._frame_type ~= "player" then return end
    local target = (total_health_percentage or 0) * (health_multiplier or 1)
    _capture(self, target)
end)

-- ============================================================
-- Per-frame drive: write the eased value into the health bar.
-- ============================================================
mod:hook_safe("UnitFrameUI", "update", function(self, dt)
    if not mod:get("gt_hp_smoothing") then return end
    if self._frame_type ~= "player" then return end
    if _st.widget ~= self or _st.displayed == nil then return end  -- no target captured yet

    -- Snap through knock/death transitions (no ease when downed/dead).
    local data = self.data
    if data and (data.is_dead or data.is_knocked_down) then
        _st.displayed = _st.target
        _st.dur = 0
    elseif _st.dur > 0 then
        _st.elapsed = _st.elapsed + (dt or 0)
        local p = _st.elapsed / _st.dur
        if p >= 1 then p = 1; _st.dur = 0 end
        _st.displayed = _st.from + (_st.target - _st.from) * p
    end

    -- Write our eased fill. content.total_health_bar.bar_value is the main
    -- visible fill (unit_frame_ui.lua:1385). We run after vanilla's update, so
    -- this overrides vanilla's own lerp for the player's total-health bar only.
    local widget = self._widget_by_feature and self:_widget_by_feature("health", "dynamic")
    local content = widget and widget.content and widget.content.total_health_bar
    if content then
        content.bar_value = _st.displayed
    end
end)
