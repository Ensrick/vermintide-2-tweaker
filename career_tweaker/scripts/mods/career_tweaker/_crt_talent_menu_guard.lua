-- _crt_talent_menu_guard.lua -- preserve live talent-buff state on no-op close.
--
-- This module is intentionally independent of the retired casting/transposition
-- system. Vanilla initializes each picker from the backend selection, then
-- unconditionally persists and calls TalentExtension:talents_changed() on
-- close. That rebuild clears live talent buffs even when no row changed.

local mod = get_mod("crt")
mod._crt = mod._crt or {}

local TalentSelection = mod:dofile("scripts/mods/career_tweaker/_crt_talent_selection")
mod._crt.talent_selection = TalentSelection

local engine_printf = rawget(_G, "printf")

local function _trace(format_string, ...)
    if engine_printf then
        pcall(engine_printf, format_string, ...)
    end
end

local function _capture(window)
    window._crt_talent_selection_on_enter = TalentSelection.snapshot(window._selected_talents)
end

local function _unchanged(window)
    return TalentSelection.equal(window._crt_talent_selection_on_enter, window._selected_talents)
end

local function _skip_noop_close(window, picker_name)
    window.ui_animator = nil
    mod._crt.talent_menu_noop_skips = (mod._crt.talent_menu_noop_skips or 0) + 1
    _trace("[crt:283] close picker=%s selection=unchanged action=preserve_live_buffs", picker_name)
end

-- Hook pre-flight: these are the only active Career Tweaker registrations for
-- both pairs. The historical copies in _crt_talent_swap.lua remain dormant.
mod:hook_safe("HeroWindowTalents", "on_enter", function(self)
    mod._crt.talent_window_instance = self
    _capture(self)
    if mod._crt_auto_dump_check then
        mod._crt_auto_dump_check()
    end
end)

mod:hook("HeroWindowTalents", "on_exit", function(func, self, params)
    mod._crt.talent_window_instance = nil
    if _unchanged(self) then
        _skip_noop_close(self, "desktop")
        return
    end

    _trace("[crt:283] close picker=desktop selection=changed action=vanilla_reapply")
    return func(self, params)
end)

mod:hook_safe("HeroWindowTalentsConsole", "on_enter", function(self)
    _capture(self)
end)

mod:hook("HeroWindowTalentsConsole", "on_exit", function(func, self, params)
    if _unchanged(self) then
        _skip_noop_close(self, "controller")
        return
    end

    _trace("[crt:283] close picker=controller selection=changed action=vanilla_reapply")
    return func(self, params)
end)

mod._crt.talent_menu_guard_installed = true
_trace("[crt:283] applied: no-op talent closes preserve live buffs (desktop+controller)")

return {
    capture = _capture,
    unchanged = _unchanged,
}
