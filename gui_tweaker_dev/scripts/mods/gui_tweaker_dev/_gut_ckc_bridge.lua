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
-- This bridge, whenever CKC is installed AND togglable, TAKES OVER the native
-- crosshair_kill_confirm row in the vanilla Options menu. (#528: the bridge
-- is IMPLICIT - the former gut_ckc_options_bridge availability checkbox is gone;
-- CKC present = bridge active, no toggle. The old saved value is left orphaned
-- in mods_settings, unread.) The takeover:
--   * the row becomes a native checkbox that LIVE-drives the CKC
--     MOD via VMF's mod_state_changed (parity with the VMF-menu checkbox), NOT
--     staged through the options Apply pipeline;
--   * the native crosshair_kill_confirm user_setting is FORCED "off" (the prior
--     value is remembered and restored if the user opts out of the bridge), so
--     CrosshairUI stops drawing the vanilla marker;
--   * a gear button is appended to the right of the row; clicking it opens the
--     gut Mod Tweaker focused on CKC's options -- which live under Interface > HUD as a
--     "Crosshair Kill Confirmation" sub-collapsible, NOT a top-level tab (#339). The
--     focus request below still carries _CKC_NAME; the Mod Tweaker view redirects it to
--     the gut Interface tab and expands the HUD + CKC groups.
--
-- ZERO BEHAVIOR CHANGE when CKC is absent: install() registers NO hooks at all,
-- so the vanilla dropdown behaves exactly as stock.
--
-- THREE-SURFACE SYNC PRECEDENCE (#311, marker [CKC-SYNC-PRECEDENCE-311]). CKC's state
-- lives in exactly TWO stores, and every surface is a LIVE view on them -- none keeps an
-- authoritative shadow copy, so they cannot diverge:
--   (a) MASTER ENABLE = CKC's VMF mod-enabled flag (get_mod(CKC):is_enabled()). Written
--       via VMF mod_state_changed, read via is_enabled.
--   (b) FEATURE OPTIONS (duration / size / pop / the shape dropdowns) = CKC's OWN VMF
--       settings (mods_settings[CKC][id]), read/written via CKC's mod:get / mod:set.
-- The three surfaces and what each owns:
--   1. Vanilla Options row (THIS module) -- owns (a). Its On/Off drives the master enable
--      live (mod_state_changed) and DISPLAYS is_enabled; it never touches (b). This is why
--      "vanilla crosshair kill confirmation OFF => feature off" (#311): the row IS the CKC
--      master enable when CKC is installed.
--   2. gut Mod Tweaker > Interface > HUD > "Crosshair Kill Confirmation" group -- owns (b).
--      _inject_ckc_into_gut (_mod_tweaker_state/_view.lua) folds CKC's option nodes in;
--      edits write THROUGH to CKC via _cat_set -> ckc:set(id, val, true) -- the 3rd arg
--      fires CKC's on_setting_changed so the crosshair updates live (the own-or-pin
--      HB:set(id,v,true) cross-mod-sync doctrine). It carries NO master-enable widget (VMF
--      enable is a mod-list flag, not a settings-tree node).
--   3. CKC's OWN VMF options page -- also owns (b): native VMF read/write of the same store.
-- CONVERGENCE: surfaces 2 and 3 operate on the SAME (b) store, so there is a single source
-- of truth and last-write-wins with nothing to reconcile. They are never simultaneously
-- interactive (2 is a hero-view state, 3 is the ESC mod-settings view -- mutually exclusive),
-- and EACH rebuilds its rows from a live get on open, so a change made in one is reflected
-- the next time the other opens. The known VMF caveat (mod:set does NOT repaint an
-- already-open widget -- memory reference_vmf_checkbox_cached_display_state) therefore
-- cannot bite: no two option surfaces are ever on screen at once. Surface 1 reads is_enabled
-- live whenever it is shown, so a mod_state_changed from ANY path is reflected there too.
--
-- MODULE-SIDE LIFECYCLE CHAINING (deliberate). #313 landed while the gut main
-- file (gui_tweaker_dev.lua) was claimed by parallel #307 freecam work, so this
-- module does NOT rely on the main file wiring its callbacks. Instead it
-- chain-wraps mod.on_all_mods_loaded (-> install) at dofile time. The main file
-- contributes ONLY a single dofile line; adding that line later activates
-- everything here. The dofile must therefore run AFTER the main file defines/
-- chains that callback (it is placed next to the other OptionsView modules,
-- well below the definition). (#528: the on_setting_changed chain is gone with
-- the availability toggle it listened for.)
--
-- SOURCE PROVENANCE (verified 2026-07-05):
--   * vanilla setup/change/saved-value callbacks are SYNTHESIZED named methods on
--     OptionsView (options_view_settings.lua generate_settings:1298-1333; the
--     OptionsView.build_checkbox_widget consumes (flag, text, default), stores the
--     boolean in content.flag, and calls the synthesized callback after the native
--     checkbox pass flips it (options_view.lua:308-313, 1029-1147, 1483-1504;
--     options_view_definitions.lua:1299-1421).
--   * create_checkbox_widget returns an ALREADY-INITIALIZED widget, so we
--     append our gear passes to element.passes + gear content/style then RE-INIT the
--     widget (a fresh, correctly-sized pass_data array) and return that.
--   * VMF live toggle: get_mod("VMF").mod_state_changed(name, bool)
--     (vmf/modules/core/toggling.lua:53-67) -- self-guards is_togglable + idempotency.
--   * cog_icon / cog_icon_selected (58x58) exist in the menus atlas
--     (gui_menus_atlas.lua:1586-1610), which the Options view already binds
--     (playerlist_hover).

local _CKC_NAME = "Crosshair Kill Confirmation"
local _VANILLA  = "crosshair_kill_confirm"        -- native user_setting key
local WidgetPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_ckc_widget_policy")
local RenderPolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_ckc_render_policy")
-- (#528) _S_BRIDGE (the gut_ckc_options_bridge checkbox) retired: bridge is implicit.
local _S_SAVED  = "gut_ckc_saved_vanilla_group"    -- remembered pre-takeover vanilla group
local GEAR      = 26                               -- gear icon square (px, 1080p ref)
-- Native checkbox geometry from options_view_definitions.lua:1411-1421. The cog
-- sits alongside the 16px box and remains far clear of the list scrollbar.
local CHECKBOX_X = 642
local CHECKBOX_W = 16
local GEAR_GAP   = 14

local M = {}
local _active = false          -- CKC installed + togglable (set by install)
local _hooks_installed = false

-- ---------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------

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

-- The takeover is live whenever CKC is present+togglable (install marked _active).
-- (#528) No availability checkbox anymore - implicit. Hooks passthrough otherwise.
local function _is_active()
    return _active
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

-- Restore the remembered pre-takeover group and clear the memory. (#528) With the
-- availability toggle retired there is no menu opt-out path; this stays as a manual
-- recovery API only (M.restore - e.g. console/regression use after uninstalling CKC).
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
-- Gear button (appended to the bridged crosshair_kill_confirm checkbox row)
-- ---------------------------------------------------------------

-- Append a cog icon + hotspot to an ALREADY-INITIALIZED checkbox widget and return
-- a freshly re-initialized widget (UIWidget.init rebuilds pass_data to the new pass
-- count -- the original pass_data is a fixed-size Script.new_array we must not grow).
-- Placed immediately right of the native checkbox. masked = true on the texture
-- passes so it clips to the settings list like the sibling passes.
local function _append_gear(widget)
    local style   = widget.style
    local content = widget.content
    local passes  = widget.element and widget.element.passes
    if type(style) ~= "table" or type(content) ~= "table" or type(passes) ~= "table" then
        return nil
    end

    local wo = style.offset or { 0, 0, 0 }
    local sz = style.size or { 1300, 30 }
    -- [CKC-GEAR-LEFT-GUTTER-313] #528 now uses vanilla's checkbox at x=642
    -- (options_view_definitions.lua:1411-1421). Keep the #313 scrollbar guarantee by
    -- placing the cog beside that checkbox, far inside the list rather than at row-right.
    local gx = (wo[1] or 0) + CHECKBOX_X + CHECKBOX_W + GEAR_GAP
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

-- Gear click: request focus on CKC's options (the Mod Tweaker view redirects _CKC_NAME
-- to the gut Interface tab + HUD/CKC groups, #339), then open the Mod Tweaker. Guarded
-- for the title-screen OptionsView (no ingame_ui transitions) -- on failure, clear the
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
-- draw_widgets (_gut_glow_probe), on_enter + update_apply_button (_gut_diag_optionsview).
-- None of the (Class, method) pairs below is hooked anywhere else in the mod:
--   OptionsView.cb_crosshair_kill_confirm_setup
--   OptionsView.cb_crosshair_kill_confirm
--   OptionsView.cb_crosshair_kill_confirm_saved_value
--   OptionsView.build_checkbox_widget
--   OptionsView.update            (hook_safe; gear click poll + one-time enforce)

local function _register_hooks()
    if _hooks_installed then return end
    _hooks_installed = true

    -- setup: native checkbox contract is (boolean flag, localized label key, default).
    mod:hook("OptionsView", "cb_crosshair_kill_confirm_setup", function(func, self)
        if not _is_active() then return func(self) end
        return WidgetPolicy.checkbox_setup(_ckc_enabled(), "menu_settings_crosshair_kill_confirm")
    end)

    -- change: read the native checkbox boolean
    -- and LIVE-toggle the CKC mod via VMF. Deliberately does NOT call func, so the
    -- native user_setting stays forced "off" (never staged into the Apply pipeline).
    mod:hook("OptionsView", "cb_crosshair_kill_confirm", function(func, self, content, style)
        if not _is_active() then return func(self, content, style) end
        local chosen = WidgetPolicy.checkbox_value(content)
        local vmf = get_mod("VMF")
        if vmf and type(vmf.mod_state_changed) == "function" then
            pcall(vmf.mod_state_changed, _CKC_NAME, chosen == true)
        end
        _printf("[gut_dev:ckc] options toggle -> CKC %s (live)", chosen == true and "ENABLED" or "DISABLED")
    end)

    -- saved_value: repaint the checkbox from CKC's live enabled state.
    mod:hook("OptionsView", "cb_crosshair_kill_confirm_saved_value", function(func, self, widget)
        if not _is_active() then return func(self, widget) end
        local content = widget and widget.content
        WidgetPolicy.restore_checkbox(content, _ckc_enabled())
    end)

    -- gear: append the cog after the consolidated list hook has redirected this one
    -- definition through vanilla's checkbox builder.
    mod:hook("OptionsView", "build_checkbox_widget", function(func, self, element, scenegraph_id, base_offset)
        local widget = func(self, element, scenegraph_id, base_offset)
        if not _is_active() then return widget end
        if not (type(element) == "table" and element.setting_name == _VANILLA) then return widget end
        -- #528 verification crash: OptionsView's factory writes raw checkbox
        -- materials which this gameplay-list renderer does not load. Preserve
        -- native flag/hotspot behavior and harden only this borrowed row.
        local hardened = RenderPolicy.harden(widget)
        if not hardened then
            _printf("[gut_dev:528] CKC checkbox hardening failed; suppressing unsafe texture pass")
            local passes = widget and widget.element and widget.element.passes or {}
            for _, pass in ipairs(passes) do
                if pass.pass_type == "texture" and pass.texture_id == "checkbox" then
                    pass.content_check_function = function() return false end
                end
            end
        end
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

-- Called from the existing singleton OptionsView.build_settings_list hook owned by
-- _gut_video_profiles.lua. The temporary mutation makes vanilla dispatch this row
-- through build_checkbox_widget; restoration after the list build keeps the global
-- settings definition pristine and absent-CKC behavior byte-for-byte vanilla.
function M.prepare_settings_definition(definition)
    return WidgetPolicy.prepare_definition(definition, _VANILLA, _is_active())
end

function M.restore_settings_definition(token)
    WidgetPolicy.restore_definition(token)
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
    _printf("[gut_dev:ckc] bridge active (CKC installed + togglable; implicit, no toggle)")
end

-- Structural markers / API surface (published at load, regardless of CKC presence,
-- so the regression tests can see the module is wired).
M.is_active   = _is_active
M.enforce     = _enforce
M.restore     = _restore
M._CKC_NAME   = _CKC_NAME
M.widget_policy = WidgetPolicy
M.render_policy = RenderPolicy
mod._GUT_CKC_BRIDGE_MARKER = "gut-ckc-bridge-313"
mod._gut_ckc_bridge = M

-- Module-side lifecycle chaining (see header). Wrap the PREVIOUS callback captured
-- at this dofile point (the main file chains on_all_mods_loaded well above this
-- module's dofile site). (#528) The on_setting_changed chain was removed with the
-- availability toggle it listened for.
do
    local _prev_oaml = mod.on_all_mods_loaded
    mod.on_all_mods_loaded = function(...)
        if _prev_oaml then _prev_oaml(...) end
        pcall(M.install)
    end
end

_printf("[gut_dev:ckc] bridge module loaded (marker=%s)", tostring(mod._GUT_CKC_BRIDGE_MARKER))

return M
