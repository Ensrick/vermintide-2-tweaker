local mod = get_mod("gut_dev")
local _printf = rawget(_G, "printf") or function() end  -- engine printf (survives mod-logging-OFF)

-- ============================================================================
-- Crosshair Kill Confirmation (CKC) options-menu bridge (#313)
-- ============================================================================
-- WHAT. The sanctioned Workshop mod "Crosshair Kill Confirmation" by pixaal
-- (Workshop 1593460250, VMF id "Crosshair Kill Confirmation" -- note the SPACES)
-- renders its own kill-indicator crosshair. VT2 also ships a NATIVE
-- crosshair_kill_confirm setting (GAMEPLAY tab dropdown) consumed only by
-- CrosshairUI. With CKC installed the native marker is redundant/competing.
--
-- This bridge, ONLY when CKC is installed AND togglable AND the user's
-- gut_ckc_options_bridge checkbox is on (default on), TAKES OVER the native
-- crosshair_kill_confirm dropdown in the vanilla Options menu:
--   * the dropdown becomes a 2-option On / Off toggle that LIVE-drives the CKC
--     MOD via VMF's mod_state_changed (parity with the VMF-menu checkbox), NOT
--     staged through the options Apply pipeline;
--   * the native crosshair_kill_confirm user_setting is FORCED "off" (the prior
--     value is remembered and restored if the user opts out of the bridge), so
--     CrosshairUI stops drawing the vanilla marker;
--   * a gear button is appended to the right of the row; clicking it opens the
--     gut Mod Tweaker focused on the CKC tab (its 7 real options live there).
--
-- ZERO BEHAVIOR CHANGE when CKC is absent: install() registers NO hooks at all,
-- so the vanilla dropdown behaves exactly as stock.
--
-- MODULE-SIDE LIFECYCLE CHAINING (deliberate). #313 landed while the gut main
-- file (gui_tweaker_dev.lua) was claimed by parallel #307 freecam work, so this
-- module does NOT rely on the main file wiring its callbacks. Instead it
-- chain-wraps mod.on_all_mods_loaded (-> install) and mod.on_setting_changed
-- (-> M.on_setting_changed) at dofile time. The main file contributes ONLY a
-- single dofile line; adding that line later activates everything here. The
-- dofile must therefore run AFTER the main file defines/chains those two
-- callbacks (it is placed next to the other OptionsView modules, well below
-- both definitions).
--
-- SOURCE PROVENANCE (verified 2026-07-05):
--   * vanilla setup/change/saved-value callbacks are SYNTHESIZED named methods on
--     OptionsView (options_view_settings.lua generate_settings:1298-1333; the
--     drop_down setup returns (selection, options, menu_setting_name, default_index)
--     :1228-1271; change reads content.options_values[content.current_selection]
--     :1210-1226; saved_value sets content.current_selection :1273-1296).
--   * build_drop_down_widget returns UIWidget.init(definition) via
--     create_drop_down_widget (options_view.lua:1270-1289, options_view_definitions
--     .lua:2299-3047, ui_widget.lua:13-46) -- an ALREADY-INITIALIZED widget, so we
--     append our gear passes to element.passes + gear content/style then RE-INIT the
--     widget (a fresh, correctly-sized pass_data array) and return that.
--   * VMF live toggle: get_mod("VMF").mod_state_changed(name, bool)
--     (vmf/modules/core/toggling.lua:53-67) -- self-guards is_togglable + idempotency.
--   * cog_icon / cog_icon_selected (58x58) exist in the menus atlas
--     (gui_menus_atlas.lua:1586-1610), which the Options view already binds
--     (playerlist_hover).

local _CKC_NAME = "Crosshair Kill Confirmation"
local _VANILLA  = "crosshair_kill_confirm"        -- native user_setting key
local _S_BRIDGE = "gut_ckc_options_bridge"         -- gut checkbox (nil => treat as ON)
local _S_SAVED  = "gut_ckc_saved_vanilla_group"    -- remembered pre-takeover vanilla group
local GEAR      = 26                               -- gear icon square (px, 1080p ref)

local M = {}
local _active = false          -- CKC installed + togglable (set by install)
local _hooks_installed = false

-- ---------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------

local function _loc(key)
    local ok, s = pcall(Localize, key)
    if ok and type(s) == "string" then return s end
    return key
end

-- The gut bridge checkbox. The data.lua widget may land AFTER this module (the
-- shared files were claimed by #307), so a nil (unregistered) value means ON.
local function _bridge_on()
    local v = mod:get(_S_BRIDGE)
    if v == nil then v = true end
    return v and true or false
end

local function _ckc()
    return get_mod(_CKC_NAME)
end

local function _ckc_togglable(m)
    m = m or _ckc()
    if not m or type(m.get_internal_data) ~= "function" then return false end
    local ok, v = pcall(m.get_internal_data, m, "is_togglable")
    return (ok and v) and true or false
end

local function _ckc_enabled()
    local m = _ckc()
    if not m or type(m.is_enabled) ~= "function" then return false end
    local ok, en = pcall(m.is_enabled, m)
    return (ok and en) and true or false
end

-- The takeover is live only when CKC is present+togglable (install marked _active)
-- AND the user has the bridge checkbox on. Hooks passthrough to vanilla otherwise.
local function _is_active()
    return _active and _bridge_on()
end

-- ---------------------------------------------------------------
-- Vanilla-feature suppression / restore
-- ---------------------------------------------------------------

-- Force the native crosshair_kill_confirm setting off (remembering the prior group)
-- so CrosshairUI stops drawing the vanilla marker while CKC owns the feature. Cheap
-- + idempotent: once forced, cur == "off" and we no-op, preserving the saved group.
local function _enforce()
    if not _is_active() then return end
    local cur
    local ok = pcall(function() cur = Application.user_setting(_VANILLA) end)
    if not ok then return end
    if cur ~= nil and cur ~= "off" then
        mod:set(_S_SAVED, cur)  -- remember the user's pre-takeover choice
        pcall(function()
            Application.set_user_setting(_VANILLA, "off")
            Application.save_user_settings()
        end)
        pcall(function()
            if Managers.state and Managers.state.event then
                Managers.state.event:trigger("on_game_options_changed")
            end
        end)
        _printf("[gut_dev:ckc] native %s forced off (saved prior='%s')", _VANILLA, tostring(cur))
    end
end

-- Restore the remembered pre-takeover group (opt-out path) and clear the memory.
-- "off" is the cleared sentinel (enforce never saves "off"), so a restore is a no-op
-- when nothing was taken over.
local function _restore()
    local saved = mod:get(_S_SAVED)
    if saved ~= nil and saved ~= "off" then
        pcall(function()
            Application.set_user_setting(_VANILLA, saved)
            Application.save_user_settings()
        end)
        pcall(function()
            if Managers.state and Managers.state.event then
                Managers.state.event:trigger("on_game_options_changed")
            end
        end)
        _printf("[gut_dev:ckc] native %s restored to '%s'", _VANILLA, tostring(saved))
    end
    mod:set(_S_SAVED, "off")  -- mark "nothing saved"
end

-- ---------------------------------------------------------------
-- Gear button (appended to the crosshair_kill_confirm dropdown row)
-- ---------------------------------------------------------------

-- Append a cog icon + hotspot to an ALREADY-INITIALIZED dropdown widget and return
-- a freshly re-initialized widget (UIWidget.init rebuilds pass_data to the new pass
-- count -- the original pass_data is a fixed-size Script.new_array we must not grow).
-- Placed in the free gap right of the 1300px row (mask is 1400 wide). masked = true
-- on the texture passes so it clips to the settings list like the sibling passes.
local function _append_gear(widget)
    local style   = widget.style
    local content = widget.content
    local passes  = widget.element and widget.element.passes
    if type(style) ~= "table" or type(content) ~= "table" or type(passes) ~= "table" then
        return nil
    end

    local wo = style.offset or { 0, 0, 0 }
    local sz = style.size or { 1300, 30 }
    local gx = (wo[1] or 0) + (sz[1] or 1300) + 10
    local gy = (wo[2] or 0) + ((sz[2] or 30) / 2 - GEAR / 2)
    local gz = (wo[3] or 0) + 5

    content.gut_ckc_gear_tex       = "cog_icon"
    content.gut_ckc_gear_tex_hover = "cog_icon_selected"
    content.gut_ckc_gear_hotspot   = content.gut_ckc_gear_hotspot or {}

    style.gut_ckc_gear = {
        masked = true, offset = { gx, gy, gz }, size = { GEAR, GEAR },
        color = { 255, 255, 255, 255 },
    }
    style.gut_ckc_gear_hover = {
        masked = true, offset = { gx, gy, gz + 1 }, size = { GEAR, GEAR },
        color = { 255, 255, 255, 255 },
    }
    style.gut_ckc_gear_hotspot = { offset = { gx, gy, gz }, size = { GEAR, GEAR } }

    -- base cog (hidden while hovered)
    passes[#passes + 1] = {
        pass_type = "texture", style_id = "gut_ckc_gear", texture_id = "gut_ckc_gear_tex",
        content_check_function = function(c)
            local hs = c.gut_ckc_gear_hotspot
            return not (hs and hs.is_hover)
        end,
    }
    -- highlighted cog (shown while hovered)
    passes[#passes + 1] = {
        pass_type = "texture", style_id = "gut_ckc_gear_hover", texture_id = "gut_ckc_gear_tex_hover",
        content_check_function = function(c)
            local hs = c.gut_ckc_gear_hotspot
            return hs and hs.is_hover
        end,
    }
    -- hotspot (populates content.gut_ckc_gear_hotspot.is_hover / on_release each draw)
    passes[#passes + 1] = {
        content_id = "gut_ckc_gear_hotspot", pass_type = "hotspot", style_id = "gut_ckc_gear_hotspot",
    }

    return UIWidget.init({
        element = { passes = passes },
        content = content,
        style = style,
        offset = widget.offset,
        scenegraph_id = widget.scenegraph_id,
    })
end

-- Locate the crosshair_kill_confirm widget's gear hotspot in the ACTIVE settings
-- list (present only while the GAMEPLAY tab is shown). Scans rather than caching a
-- handle, so a fresh OptionsView instance (title / keep / in-mission) is always
-- resolved correctly.
local function _find_gear_hotspot(self)
    local sl = self.selected_settings_list
    local widgets = sl and sl.widgets
    if type(widgets) ~= "table" then return nil end
    local n = sl.widgets_n or #widgets
    for i = 1, n do
        local w = widgets[i]
        local c = w and w.content
        if c and c.gut_ckc_gear_hotspot and c.definition and c.definition.setting_name == _VANILLA then
            return c.gut_ckc_gear_hotspot
        end
    end
    return nil
end

-- Gear click: request focus on the CKC tab, then open the Mod Tweaker. Guarded for
-- the title-screen OptionsView (no ingame_ui transitions) -- on failure, clear the
-- request and echo a fallback hint.
local function _open_mod_tweaker()
    mod._gut_mt_focus_request = _CKC_NAME
    local ui = Managers.ui
    if ui and type(ui.handle_transition) == "function" then
        local ok = pcall(ui.handle_transition, ui, "mod_tweaker_view", { use_fade = true })
        if ok then
            _printf("[gut_dev:ckc] gear clicked -> Mod Tweaker (focus %s)", _CKC_NAME)
            return
        end
    end
    mod._gut_mt_focus_request = nil
    pcall(mod.echo, mod, "[gut] Open the Mod Tweaker from the ESC menu to edit Crosshair Kill Confirmation options.")
end

-- ---------------------------------------------------------------
-- OptionsView hooks (registered only when CKC is present + togglable)
-- ---------------------------------------------------------------
-- PRE-FLIGHT (no-duplicate-hook rule): the only other gut_dev OptionsView hooks are
-- draw_widgets (_gut_glow_probe), on_enter + update_apply_button (_gut_options_probe).
-- None of the (Class, method) pairs below is hooked anywhere else in the mod:
--   OptionsView.cb_crosshair_kill_confirm_setup
--   OptionsView.cb_crosshair_kill_confirm
--   OptionsView.cb_crosshair_kill_confirm_saved_value
--   OptionsView.build_drop_down_widget
--   OptionsView.update            (hook_safe; gear click poll + one-time enforce)

local function _register_hooks()
    if _hooks_installed then return end
    _hooks_installed = true

    -- setup: replace the 6-group vanilla list with a 2-option On/Off list reflecting
    -- CKC's live enabled state. Return shape matches setup_function EXACTLY:
    -- (selection_index, options, menu_setting_name, default_index).
    mod:hook("OptionsView", "cb_crosshair_kill_confirm_setup", function(func, self)
        if not _is_active() then return func(self) end
        local options = {
            { text = _loc("menu_settings_on"),  value = true },
            { text = _loc("menu_settings_off"), value = false },
        }
        local selection = _ckc_enabled() and 1 or 2
        return selection, options, "menu_settings_crosshair_kill_confirm", 1
    end)

    -- change: read the chosen boolean (mirrors set_function's non-slider extraction)
    -- and LIVE-toggle the CKC mod via VMF. Deliberately does NOT call func, so the
    -- native user_setting stays forced "off" (never staged into the Apply pipeline).
    mod:hook("OptionsView", "cb_crosshair_kill_confirm", function(func, self, content, style)
        if not _is_active() then return func(self, content, style) end
        local chosen
        pcall(function() chosen = content.options_values[content.current_selection] end)
        local vmf = get_mod("VMF")
        if vmf and type(vmf.mod_state_changed) == "function" then
            pcall(vmf.mod_state_changed, _CKC_NAME, chosen == true)
        end
        _printf("[gut_dev:ckc] options toggle -> CKC %s (live)", chosen == true and "ENABLED" or "DISABLED")
    end)

    -- saved_value: point current_selection at the index matching CKC's enabled state
    -- (mirrors saved_value_function writing content.current_selection).
    mod:hook("OptionsView", "cb_crosshair_kill_confirm_saved_value", function(func, self, widget)
        if not _is_active() then return func(self, widget) end
        local content = widget and widget.content
        if type(content) == "table" then
            local on = _ckc_enabled()
            local ov = content.options_values
            content.current_selection = (ov and table.find(ov, on)) or (on and 1 or 2)
        end
    end)

    -- gear: append the cog to the crosshair_kill_confirm row after the vanilla build.
    mod:hook("OptionsView", "build_drop_down_widget", function(func, self, element, scenegraph_id, base_offset)
        local widget = func(self, element, scenegraph_id, base_offset)
        if not _is_active() then return widget end
        if not (type(element) == "table" and element.setting_name == _VANILLA) then return widget end
        local ok, augmented = pcall(_append_gear, widget)
        if ok and type(augmented) == "table" then return augmented end
        return widget
    end)

    -- per-frame (hook_safe): one-time enforce on view entry (belt-and-suspenders,
    -- via a per-instance flag -- update is not hooked elsewhere in gut, so no merge
    -- needed) + poll the gear hotspot for a click.
    mod:hook_safe("OptionsView", "update", function(self)
        if not _is_active() then return end
        if not self.__gut_ckc_enforced then
            self.__gut_ckc_enforced = true
            pcall(_enforce)
        end
        local hs = _find_gear_hotspot(self)
        if hs and hs.on_release then
            hs.on_release = false   -- consume so the transition can't double-fire
            _open_mod_tweaker()
        end
    end)

    _printf("[gut_dev:ckc] OptionsView hooks registered (5 methods)")
end

-- ---------------------------------------------------------------
-- Public entry points + lifecycle
-- ---------------------------------------------------------------

-- Called from the chained on_all_mods_loaded (below). No-op (no hooks) when CKC is
-- absent or not togglable, so the vanilla dropdown is untouched.
function M.install()
    local m = _ckc()
    if not m then
        _printf("[gut_dev:ckc] CKC not installed; bridge inert (no hooks)")
        return
    end
    if not _ckc_togglable(m) then
        _printf("[gut_dev:ckc] CKC present but not togglable; bridge inert (no hooks)")
        return
    end
    _active = true
    _register_hooks()
    _enforce()
    _printf("[gut_dev:ckc] bridge active (CKC installed + togglable, bridge_on=%s)", tostring(_bridge_on()))
end

-- Chained from mod.on_setting_changed: react to the bridge checkbox flip.
function M.on_setting_changed(setting_id)
    if setting_id ~= _S_BRIDGE then return end
    if not _active then return end  -- CKC absent: nothing to enforce/restore
    if _bridge_on() then
        _printf("[gut_dev:ckc] bridge toggled ON -> enforce native off")
        pcall(_enforce)
    else
        _printf("[gut_dev:ckc] bridge toggled OFF -> restore native group")
        pcall(_restore)
    end
end

-- Structural markers / API surface (published at load, regardless of CKC presence,
-- so the regression tests can see the module is wired).
M.is_active   = _is_active
M.enforce     = _enforce
M.restore     = _restore
M._CKC_NAME   = _CKC_NAME
mod._GUT_CKC_BRIDGE_MARKER = "gut-ckc-bridge-313"
mod._gut_ckc_bridge = M

-- Module-side lifecycle chaining (see header). Wrap the PREVIOUS callbacks captured
-- at this dofile point; both must already exist (main file defines on_setting_changed
-- and chains on_all_mods_loaded well above this module's dofile site).
do
    local _prev_oaml = mod.on_all_mods_loaded
    mod.on_all_mods_loaded = function(...)
        if _prev_oaml then _prev_oaml(...) end
        pcall(M.install)
    end
end
do
    local _prev_osc = mod.on_setting_changed
    mod.on_setting_changed = function(setting_id, ...)
        if _prev_osc then _prev_osc(setting_id, ...) end
        pcall(M.on_setting_changed, setting_id)
    end
end

_printf("[gut_dev:ckc] bridge module loaded (marker=%s)", tostring(mod._GUT_CKC_BRIDGE_MARKER))

return M
