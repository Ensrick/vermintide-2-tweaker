local mod = get_mod("gut")

-- ============================================================================
-- OptionsView layout probe (ground-truth for the Mod Tweaker scrollbar)
-- ============================================================================
-- Philosophy (user, 2026-06-19): "I don't want to type anything. I visit the
-- settings menu, you get the data automatically." So this AUTO-DUMPS the live
-- vanilla OptionsView the moment you open ESC -> Options — no command needed.
-- It dumps once per game session (so the log isn't spammed on every open); a
-- `/gut_dump_options` command is kept only as a manual re-dump.
--
-- What we capture (confirmed field names from options_view.lua): self.scroll_value,
-- self.scrollbar (widget), self.selected_settings_list (.scrollbar/.visible_widgets_n/
-- .num_draws/.start_index/.max_offset_y/.widgets), the `list_mask` scenegraph node
-- (the visible window bounds), and how list widgets are position-culled against it.

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
mod:command("gut_dump_options", "Re-dump the live settings-menu scroll/mask/scrollbar layout", function()
    if type(mod._opt_ref) ~= "table" then
        mod:echo("[opt-probe] no OptionsView captured yet — open ESC -> Options first")
        return
    end
    _dump_options(mod._opt_ref)
end)

mod:info("[gut] OptionsView probe installed (auto-dumps on first ESC -> Options open)")

return {}
