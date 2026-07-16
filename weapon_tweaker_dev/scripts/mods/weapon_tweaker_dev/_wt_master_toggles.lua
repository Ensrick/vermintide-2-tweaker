-- _wt_master_toggles.lua -- issue 611 "select all" master toggles for Weapon
-- Availability.
--
-- Adds one master checkbox per (receiving CAREER, melee/ranged slot, SOURCE
-- character) at the top of each `melee_<career>` / `ranged_<career>` leaf in
-- the Weapon Availability tree, and owns the cascade + derived-state logic:
--   * build_widgets(mod, data)  -- called from _data.lua AFTER the availability
--       sort and CWV strip. Buckets only the unlock rows inside one career leaf,
--       prepends its source masters in Kruber/Bardin/Kerillian/Saltzpyre/Sienna
--       order, and records the exact forward/reverse maps.
--   * seed(mod)                 -- derives every master's stored value from its
--       own career-scoped children at load.
--   * on_master_changed(mod,id) -- cascades one master to its own career only.
--   * on_child_changed(mod,id)  -- recomputes only that child's corresponding
--       master; deselecting one weapon flips that master OFF without touching
--       another career or source bucket.
--   * install_refresh_hook(mod) -- repaints changed checkboxes in the open VMF
--       menu and styles master labels with GUI Tweaker's established warm-tan
--       `font_button_normal` color.
--
-- SOURCE character comes from the display LABEL, not the weapon-key prefix: the
-- key prefix and in-game owner disagree for some ports (for example
-- `es_1h_flail` is shown "Saltzpyre: Flail"). Slot and receiving career come
-- from the enclosing leaf, so a master's children are exactly the checkboxes a
-- player sees beside it. Any CWV strip that ran before build_widgets is already
-- reflected.
--
-- No `get_mod`, engine global, or namespace-specific path lives at file scope,
-- so this module is byte-identical across the wt / wt_dev streams.

local M = {}

-- User-defined source order from RainReligion's issue 611 follow-up.
local CHAR_ORDER = { "kruber", "bardin", "kerillian", "saltzpyre", "sienna" }
local CHAR_ORDER_INDEX = {}
for index, character in ipairs(CHAR_ORDER) do CHAR_ORDER_INDEX[character] = index end

local LABEL_TO_CHAR = {
    Bardin = "bardin",
    Kerillian = "kerillian",
    Kruber = "kruber",
    Saltzpyre = "saltzpyre",
    Sienna = "sienna",
}

local function _master_id(career, slot, src_char)
    return "wtmaster_" .. career .. "_" .. slot .. "_" .. src_char
end
M.master_id = _master_id

local function _parse_master_id(master_id)
    if type(master_id) ~= "string" then return nil end
    local career, src = master_id:match("^wtmaster_(.+)_melee_([%a]+)$")
    if career then return career, "melee", src end
    career, src = master_id:match("^wtmaster_(.+)_ranged_([%a]+)$")
    if career then return career, "ranged", src end
    return nil
end
M.parse_master_id = _parse_master_id

function M.source_order_index(src_char)
    return CHAR_ORDER_INDEX[src_char]
end

-- Parse the source character key from a child row's raw English label
-- ("Character: Weapon"). Strips any leading dev-status tag defensively.
local function _source_char_of(mod, child_id)
    local raw = mod._wt_loc_raw
    local entry = type(raw) == "table" and raw[child_id]
    local label = type(entry) == "table" and entry.en
    if type(label) ~= "string" then return nil end
    while true do
        local clean, n = label:gsub("^%s*%b[]%s*", "", 1)
        label = clean
        if n == 0 then break end
    end
    local name = label:match("^([^:]+):")
    if not name then return nil end
    name = name:gsub("%s+$", "")
    return LABEL_TO_CHAR[name]
end
M.source_char_of = _source_char_of

local function _gather_unlock_nodes(node, out)
    if type(node) ~= "table" then return end
    local sid = node.setting_id
    if type(sid) == "string" and sid:sub(1, 7) == "unlock_"
            and node.type == "checkbox" then
        out[#out + 1] = node
    end
    if type(node.sub_widgets) == "table" then
        for _, child in ipairs(node.sub_widgets) do
            _gather_unlock_nodes(child, out)
        end
    end
end

-- Insert master rows into one exact career/slot leaf and record its maps.
local function _process_career_leaf(mod, leaf, career, slot, master_children,
        child_to_master, order_by_leaf)
    local nodes = {}
    _gather_unlock_nodes(leaf, nodes)

    local buckets = {}        -- src_char -> { child ids }
    local all_default_on = {} -- src_char -> bool (every child defaults ON)
    for _, node in ipairs(nodes) do
        local src = _source_char_of(mod, node.setting_id)
        if src then
            local bucket = buckets[src]
            if not bucket then
                bucket = {}
                buckets[src] = bucket
                all_default_on[src] = true
            end
            bucket[#bucket + 1] = node.setting_id
            if node.default_value ~= true then all_default_on[src] = false end
        end
    end

    local created = 0
    local new_masters = {}
    local leaf_order = {}
    for _, src in ipairs(CHAR_ORDER) do
        local bucket = buckets[src]
        if bucket and #bucket > 0 then
            local mid = _master_id(career, slot, src)
            master_children[mid] = bucket
            leaf_order[#leaf_order + 1] = mid
            for _, child_id in ipairs(bucket) do
                child_to_master[child_id] = mid
            end
            new_masters[#new_masters + 1] = {
                setting_id = mid,
                type = "checkbox",
                default_value = all_default_on[src] == true,
            }
            created = created + 1
        end
    end

    -- Prepend while preserving the explicit source order above the weapon rows.
    for i = #new_masters, 1, -1 do
        table.insert(leaf.sub_widgets, 1, new_masters[i])
    end
    order_by_leaf[leaf.setting_id] = leaf_order
    return created
end

function M.build_widgets(mod, data)
    local master_children = {}
    local child_to_master = {}
    local order_by_leaf = {}
    local created = 0

    local function walk(node)
        if type(node) ~= "table" then return end
        local sid = node.setting_id
        if type(sid) == "string" and type(node.sub_widgets) == "table" then
            local career = sid:match("^melee_(.+)$")
            local slot = "melee"
            if not career then
                career = sid:match("^ranged_(.+)$")
                slot = "ranged"
            end
            if career then
                created = created + _process_career_leaf(
                    mod, node, career, slot, master_children, child_to_master,
                    order_by_leaf)
                return -- this career leaf owns the complete bounded child set
            end
        end
        if type(node.sub_widgets) == "table" then
            for _, child in ipairs(node.sub_widgets) do walk(child) end
        end
    end

    if type(data) == "table" and type(data.options) == "table"
            and type(data.options.widgets) == "table" then
        for _, top in ipairs(data.options.widgets) do
            if type(top) == "table" and top.setting_id == "weapon_availability" then
                walk(top)
            end
        end
    end

    mod._wt_master_children = master_children
    mod._wt_child_to_master = child_to_master
    mod._wt_master_order_by_leaf = order_by_leaf
    return created
end

local function _is_on(mod, setting_id)
    return mod:get(setting_id) and true or false
end

function M.on_master_changed(mod, master_id)
    local children = mod._wt_master_children and mod._wt_master_children[master_id]
    if type(children) ~= "table" then return end
    local value = _is_on(mod, master_id)
    for _, child in ipairs(children) do
        if _is_on(mod, child) ~= value then
            mod:set(child, value, false) -- no re-notify; caller re-applies once
        end
    end
end

function M.on_child_changed(mod, child_id)
    local master_id = mod._wt_child_to_master and mod._wt_child_to_master[child_id]
    if not master_id then return end
    local children = mod._wt_master_children[master_id]
    local all_on = true
    for _, child in ipairs(children) do
        if not _is_on(mod, child) then all_on = false; break end
    end
    if _is_on(mod, master_id) ~= all_on then
        mod:set(master_id, all_on, false)
    end
end

function M.seed(mod)
    local master_children = mod._wt_master_children
    if type(master_children) ~= "table" then return 0 end
    local seeded = 0
    for master_id, children in pairs(master_children) do
        local all_on = true
        for _, child in ipairs(children) do
            if not _is_on(mod, child) then all_on = false; break end
        end
        if _is_on(mod, master_id) ~= all_on then
            mod:set(master_id, all_on, false)
        end
        seeded = seeded + 1
    end
    return seeded
end

-- VMF's checkbox factory returns a widget with `style.text.text_color`
-- (Vermintide-Mod-Framework vmf_options_view.lua:1184-1373,3327-3337).
-- GUI Tweaker uses `font_button_normal` for its warm-tan dropdown/chrome color
-- (_mod_tweaker_definitions.lua:298,475,1970,2010). Hooking the proven factory
-- styles only wtmaster rows and avoids inventing an unsupported _data.lua field.
local function _style_master_widget(widget, setting_id)
    if type(setting_id) ~= "string" or setting_id:sub(1, 9) ~= "wtmaster_" then
        return false
    end
    local text_style = type(widget) == "table" and type(widget.style) == "table"
        and widget.style.text
    if type(text_style) ~= "table" then return false end
    text_style.text_color = Colors.get_color_table_with_alpha("font_button_normal", 255)
    return true
end
M.style_master_widget = _style_master_widget

-- VMF caches checkbox state independently of mod:get. The callback hook forces
-- the established view refresh after a cascade/derived-state update; the factory
-- hook applies the master-label color once when each checkbox widget is created.
function M.install_refresh_hook(mod)
    if mod._wt_master_refresh_hooked then return end
    mod._wt_master_refresh_hooked = true

    mod:hook("VMFOptionsView", "initialize_checkbox_widget",
        function(func, self, definition, scenegraph_id)
            local widget = func(self, definition, scenegraph_id)
            _style_master_widget(widget,
                type(definition) == "table" and definition.setting_id)
            return widget
        end)

    mod:hook("VMFOptionsView", "callback_setting_changed",
        function(func, self, mod_name, setting_id, old_value, new_value)
            local a, b = func(self, mod_name, setting_id, old_value, new_value)
            pcall(function()
                if get_mod(mod_name) == mod and self
                        and self.update_picked_option_for_settings_list_widgets then
                    self:update_picked_option_for_settings_list_widgets()
                end
            end)
            return a, b
        end)
end

return M
