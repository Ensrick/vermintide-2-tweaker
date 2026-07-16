-- _wt_master_toggles.lua -- issue 611 "select all" master toggles for Weapon
-- Availability.
--
-- Adds one master checkbox per (receiving character, melee/ranged slot, SOURCE
-- character) at the top of each `<char>_melee_group` / `<char>_ranged_group` of
-- the Weapon Availability tree, and owns the cascade + auto-off runtime logic:
--   * build_widgets(mod, data)  -- called from _data.lua AFTER the availability
--       sort and the CWV strip have run. Walks the frozen availability subtree,
--       buckets every visible `unlock_<career>_<weapon>` checkbox by the SOURCE
--       character parsed from its display label, prepends the master rows, and
--       records `mod._wt_master_children` (master id -> { child ids }) and
--       `mod._wt_child_to_master` (child id -> master id).
--   * seed(mod)                 -- syncs every master's stored value to (all its
--       children currently ON) at load, so a returning user's saved child values
--       always render a truthful master state.
--   * on_master_changed(mod,id) -- user clicked a master: cascade its new value
--       to every child (notify = false, so no per-child re-entry; the caller
--       re-applies the unlocks once).
--   * on_child_changed(mod,id)  -- a child changed: recompute its owning master
--       = (all siblings ON) (notify = false). This is the issue-611 auto-off:
--       deselecting one weapon flips the master OFF while leaving the rest as-is.
--   * install_refresh_hook(mod) -- one post-hook on VMFOptionsView so cascaded /
--       auto-flipped checkboxes repaint inside the open menu (their display state
--       is cached and mod:set alone does not refresh it).
--
-- SOURCE character comes from the display LABEL, not the weapon-key prefix: the
-- key prefix and the in-game owner disagree for some ports (e.g. `es_1h_flail`
-- is shown "Saltzpyre: Flail"), and the user groups by what they SEE. Slot comes
-- from the enclosing `<char>_(melee|ranged)_group`, so a master's children are
-- EXACTLY the checkboxes rendered beneath it -> zero drift, and any CWV strip
-- that ran before build_widgets is already reflected.
--
-- No `get_mod`, engine global, or namespace-specific path lives at file scope, so
-- this module is byte-identical across the wt / wt_dev streams and safe to build
-- from _data.lua before the main script finishes.

local M = {}

-- Display order is alphabetical by character name (repo standing sort rule).
local CHAR_ORDER = { "bardin", "kerillian", "kruber", "saltzpyre", "sienna" }
local LABEL_TO_CHAR = {
    Bardin = "bardin",
    Kerillian = "kerillian",
    Kruber = "kruber",
    Saltzpyre = "saltzpyre",
    Sienna = "sienna",
}

local function _master_id(recv_char, slot, src_char)
    return "wtmaster_" .. recv_char .. "_" .. slot .. "_" .. src_char
end
M.master_id = _master_id

-- Parse the source character key from a child row's raw English label
-- ("Character: Weapon"). Strips any leading dev-status tag defensively (the
-- public beta carries none, but the availability sort strips them too, so this
-- stays robust against the dev stream / future tags).
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
    if type(sid) == "string" and sid:sub(1, 7) == "unlock_" and node.type == "checkbox" then
        out[#out + 1] = node
    end
    if type(node.sub_widgets) == "table" then
        for _, child in ipairs(node.sub_widgets) do
            _gather_unlock_nodes(child, out)
        end
    end
end

-- Insert master rows into one `<char>_(melee|ranged)_group` and record the maps.
local function _process_slot_group(mod, group, recv_char, slot, master_children, child_to_master)
    local nodes = {}
    _gather_unlock_nodes(group, nodes)

    local order = {}          -- source chars in discovery order (dedup)
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
                order[#order + 1] = src
            end
            bucket[#bucket + 1] = node.setting_id
            if node.default_value ~= true then all_default_on[src] = false end
        end
    end

    local created = 0
    local new_masters = {}
    for _, src in ipairs(CHAR_ORDER) do
        local bucket = buckets[src]
        if bucket and #bucket > 0 then
            local mid = _master_id(recv_char, slot, src)
            master_children[mid] = bucket
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

    -- Prepend the master rows (keeping their alphabetical order) ahead of the
    -- per-career subgroups.
    for i = #new_masters, 1, -1 do
        table.insert(group.sub_widgets, 1, new_masters[i])
    end
    return created
end

function M.build_widgets(mod, data)
    local master_children = {}
    local child_to_master = {}
    local created = 0

    local function walk(node)
        if type(node) ~= "table" then return end
        local sid = node.setting_id
        if type(sid) == "string" and type(node.sub_widgets) == "table" then
            local recv = sid:match("^(%w+)_melee_group$")
            local slot = "melee"
            if not recv then
                recv = sid:match("^(%w+)_ranged_group$")
                slot = "ranged"
            end
            if recv then
                created = created + _process_slot_group(
                    mod, node, recv, slot, master_children, child_to_master)
                return  -- already gathered this whole slot subtree
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
            mod:set(child, value, false)  -- no re-notify; caller re-applies once
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

-- One post-hook so cascaded / auto-flipped checkboxes repaint inside the open
-- options menu. VMF caches each checkbox's `is_checkbox_checked` independent of
-- the persisted value and only re-syncs it from `mod:get` on view (re)open;
-- `update_picked_option_for_settings_list_widgets` forces that re-sync in the
-- same frame. Identity-gated to this mod via `get_mod(mod_name) == mod` so the
-- source text carries no stream-specific id literal.
function M.install_refresh_hook(mod)
    if mod._wt_master_refresh_hooked then return end
    mod._wt_master_refresh_hooked = true
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
