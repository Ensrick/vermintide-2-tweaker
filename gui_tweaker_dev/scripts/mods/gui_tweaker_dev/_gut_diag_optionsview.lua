local mod = get_mod("gut_dev")

-- _gut_diag_optionsview.lua - vanilla OptionsView layout diagnostic (Mod Tweaker
-- scrollbar ground-truth).
--
-- Per-cluster diagnostics module (PROJECT_STANDARDS section 2.2b; renamed from
-- _gut_options_probe.lua under #499). Standing dev instrumentation, NOT keyed to a
-- single tracked issue: it captures the live vanilla settings-menu scroll/mask/
-- scrollbar machinery (field names confirmed against options_view.lua) so gut's
-- Mod Tweaker view can replicate native scrolling, plus the live Apply-button
-- READY-state colours (the decompiled source is older than the shipped build, so
-- its colours are wrong). Owns mod._opt_ref / _opt_dumped / _opt_apply_dumped, all
-- set and read within this file. Emits the [opt-probe] (layout) and [opt-apply]
-- (button colours) channels: topic prefixes, not issue-keyed, because no single
-- issue tracks it. Observe-only: two OptionsView hook_safe callbacks, zero
-- behaviour change.
--
-- Philosophy (user, 2026-06-19): "I don't want to type anything. I visit the
-- settings menu, you get the data automatically." So it AUTO-DUMPS the live
-- vanilla OptionsView the moment you open ESC -> Options, no command needed, once
-- per game session (so the log isn't spammed on every open); the `/dump_options`
-- command is kept only as a manual re-dump.
--
-- Owned by: gui_tweaker_dev.lua entry point. Consumed via:
--   mod:dofile("scripts/mods/gui_tweaker_dev/_gut_diag_optionsview")

local UISceneGraph = UISceneGraph

local function _vec(v)
    if type(v) ~= "table" then return tostring(v) end
    return string.format("{%s,%s,%s}", tostring(v[1]), tostring(v[2]), tostring(v[3]))
end

local function _dump_node(sg, name)
    local node = type(sg) == "table" and sg[name]
    if type(node) ~= "table" then return end
    local wp
    local ok, p = pcall(UISceneGraph.get_world_position, sg, name)
    if ok then wp = p end
    mod:info("[opt-probe] node '%s' parent=%s size=%s local_pos=%s world=%s",
        name, tostring(node.parent), _vec(node.size),
        _vec(node.local_position or node.position), wp and _vec(wp) or "?")
end

local function _dump_widget(label, w)
    if type(w) ~= "table" then
        mod:info("[opt-probe] widget '%s' = %s", label, type(w))
        return
    end
    local passes = w.element and w.element.passes
    if type(passes) == "table" then
        for i = 1, #passes do
            local p = passes[i]
            mod:info("[opt-probe]   %s pass[%d]: type=%s style_id=%s content_id=%s texture_id=%s",
                label, i, tostring(p.pass_type), tostring(p.style_id),
                tostring(p.content_id), tostring(p.texture_id))
        end
    end
    if type(w.content) == "table" then
        local keys = {}
        for k, v in pairs(w.content) do keys[#keys + 1] = tostring(k) .. "(" .. type(v) .. ")" end
        table.sort(keys)
        mod:info("[opt-probe]   %s content: %s", label, table.concat(keys, ", "))
    end
    if type(w.style) == "table" then
        for k, st in pairs(w.style) do
            if type(st) == "table" then
                mod:info("[opt-probe]   %s style.%s: material=%s texture=%s size=%s offset=%s masked=%s",
                    label, tostring(k), tostring(st.material),
                    tostring(st.texture_id or st.texture), _vec(st.size), _vec(st.offset),
                    tostring(st.masked or st.mask))
            end
        end
    end
end

local function _dump_options(self)
    if type(self) ~= "table" then return end
    mod:info("[opt-probe] ================= OptionsView layout dump =================")

    local sg = self.ui_scenegraph
    for _, n in ipairs({ "root", "screen", "background", "window", "list_mask",
                         "scrollbar", "settings_list", "title_text", "mask_rect" }) do
        _dump_node(sg, n)
    end
    if type(sg) == "table" then
        local names = {}
        for k in pairs(sg) do if type(k) == "string" then names[#names + 1] = k end end
        table.sort(names)
        mod:info("[opt-probe] ALL scenegraph nodes: %s", table.concat(names, ", "))
    end

    local fields = {}
    for k, v in pairs(self) do
        local ks = tostring(k)
        if ks:find("scroll") or ks:find("mask") or ks:find("list") or ks:find("bar") then
            fields[#fields + 1] = string.format("%s=%s", ks, type(v) == "table" and "table" or tostring(v))
        end
    end
    table.sort(fields)
    mod:info("[opt-probe] self scroll/mask/list/bar fields: %s", table.concat(fields, ", "))
    mod:info("[opt-probe] scroll_value=%s", tostring(self.scroll_value))

    local ssl = self.selected_settings_list
    if type(ssl) == "table" then
        mod:info("[opt-probe] selected_settings_list: scrollbar=%s visible_widgets_n=%s num_draws=%s start_index=%s max_offset_y=%s widgets_n=%s scenegraph_id_start=%s",
            tostring(ssl.scrollbar), tostring(ssl.visible_widgets_n), tostring(ssl.num_draws),
            tostring(ssl.start_index), tostring(ssl.max_offset_y),
            tostring(ssl.widgets and #ssl.widgets), tostring(ssl.scenegraph_id_start))
        if type(ssl.widgets) == "table" then
            for i = 1, math.min(3, #ssl.widgets) do
                local w = ssl.widgets[i]
                local st = w and w.style
                mod:info("[opt-probe]   list widget[%d]: scenegraph_id=%s offset=%s size=%s name=%s",
                    i, tostring(w and w.scenegraph_id), _vec(st and st.offset),
                    _vec(st and st.size), tostring(w and w.name))
            end
        end
    end

    _dump_widget("scrollbar", self.scrollbar)
    _dump_widget("scroll_field_widget", self.scroll_field_widget)

    mod:info("[opt-probe] ================= end dump =================")
end

-- Auto-dump on menu open (no typing), once per game session.
mod:hook_safe("OptionsView", "on_enter", function(self)
    mod._opt_ref = self
    if not mod._opt_dumped then
        mod._opt_dumped = true
        mod:info("[opt-probe] OptionsView opened — auto-dumping layout (once this session)")
        pcall(_dump_options, self)
    end
end)

-- Manual re-dump if a later capture is wanted.
mod:command("dump_options", "Re-dump the live settings-menu scroll/mask/scrollbar layout", function()
    if type(mod._opt_ref) ~= "table" then
        mod:echo("[opt-probe] no OptionsView captured yet — open ESC -> Options first")
        return
    end
    _dump_options(mod._opt_ref)
end)

-- (apply-color farm) The vanilla Apply button turns light-green when READY in the LIVE game,
-- but the decompiled source shows gold (cheeseburger) with no green, so the source is older
-- than the current build. Dump the LIVE Apply button's colors the moment it enters the ready
-- state (changes pending) so gut's Apply-ready colour can match EXACTLY. printf (survives
-- mod-logging-off). Fires once per session. To capture: open ESC -> Options and change one
-- setting; the [opt-apply] lines then show the real RGBA. No dup hook (gut hooks OptionsView
-- on_enter + draw_widgets elsewhere, NOT update_apply_button).
local function _dump_apply_colors(self)
    local w = self.apply_button
    if type(w) ~= "table" or type(w.style) ~= "table" then return end
    printf("[opt-apply] READY. disabled=%s",
        tostring(w.content and w.content.button_text and w.content.button_text.disabled))
    for sid, st in pairs(w.style) do
        if type(st) == "table" then
            local tc = st.text_color
            if type(tc) == "table" then
                printf("[opt-apply] style.%s text_color={%s,%s,%s,%s}", tostring(sid),
                    tostring(tc[1]), tostring(tc[2]), tostring(tc[3]), tostring(tc[4]))
            end
            local c = st.color
            if type(c) == "table" then
                printf("[opt-apply] style.%s color={%s,%s,%s,%s}", tostring(sid),
                    tostring(c[1]), tostring(c[2]), tostring(c[3]), tostring(c[4]))
            end
        end
    end
end
mod:hook_safe("OptionsView", "update_apply_button", function(self)
    if mod._opt_apply_dumped then return end
    pcall(function()
        -- Only the READY state (changes pending) carries the green we want.
        if not (self.changes_been_made and self:changes_been_made()) then return end
        mod._opt_apply_dumped = true
        _dump_apply_colors(self)
    end)
end)

mod:info("[gut] OptionsView probe installed (auto-dumps on first ESC -> Options open)")

return {}
