local mod = get_mod("gut")

-- Mod Tweaker: registered-category store + standalone persistence layer.
-- v0.1 scaffold. Hosts the runtime registry of mod-author-registered settings
-- categories and reads/writes them through VMF's per-mod kv store (the same
-- `mod:set` / `mod:get` path gui_tweaker already uses for its own settings),
-- which serialises into `user_settings.config` under the gut namespace. The
-- key shape is `mt::<mod_id>::<setting_id>` so the keyspace stays
-- inspectable and one author's keys can't collide with another's. The wider
-- VMF persistence verification (real namespace from the bytecode) lands with
-- task #2 — for now we stay inside gut's own slot, which is unconditionally
-- safe whether VMF's options view is open or not.

local SettingsModule = {}

-- Two-helper debug telemetry (PROJECT_STANDARDS § 3.6). Owner module wires
-- via init_dbg(...) before any registration calls land.
local _dbg = function() end
local _dbg_alert = function() end

function SettingsModule.init_dbg(dbg, dbg_alert)
    if type(dbg) == "function" then _dbg = dbg end
    if type(dbg_alert) == "function" then _dbg_alert = dbg_alert end
end

-- Registry: mod_id -> category record. A category record is the table the
-- author handed to register_category(); we own a clone, never the original.
local _categories = {}

-- Insertion-order list of mod_ids so the tab strip iterates deterministically
-- regardless of pairs() iteration order.
local _ordered_ids = {}

-- Per-(mod_id, setting_id) -> widget def, built lazily on register so reads
-- can find a widget's default value without re-walking the widget tree.
local _widget_index = {}

local function _walk_widgets(node, into)
    if type(node) ~= "table" then return end
    if type(node.setting_id) == "string" then
        into[node.setting_id] = node
    end
    if type(node.sub_widgets) == "table" then
        for i = 1, #node.sub_widgets do _walk_widgets(node.sub_widgets[i], into) end
    end
    if type(node.widgets) == "table" then
        for i = 1, #node.widgets do _walk_widgets(node.widgets[i], into) end
    end
end

local function _kv_key(mod_id, setting_id)
    return string.format("mt::%s::%s", tostring(mod_id), tostring(setting_id))
end

-- ---------------------------------------------------------------
-- Public API (called via SettingsModule.* by the controller).
-- ---------------------------------------------------------------

-- register_category(def) -- def: { mod_id, label, widgets, vmf_synced? }.
-- Returns true on success, (false, reason) on rejection.
function SettingsModule.register_category(def)
    if type(def) ~= "table" then return false, "category def must be a table" end
    local mod_id = def.mod_id
    if type(mod_id) ~= "string" or mod_id == "" then
        return false, "category def is missing string mod_id"
    end
    if _categories[mod_id] then
        return false, string.format("mod_id %q already registered with Mod Tweaker", mod_id)
    end
    if type(def.widgets) ~= "table" then
        return false, "category def is missing widgets table"
    end
    -- Shallow clone so author mutations after register don't leak in.
    local record = {
        mod_id      = mod_id,
        label       = def.label or mod_id,
        widgets     = def.widgets,
        vmf_synced  = def.vmf_synced and true or false,
        registered_at = os.time(),
    }
    _categories[mod_id] = record
    _ordered_ids[#_ordered_ids + 1] = mod_id
    _widget_index[mod_id] = {}
    for i = 1, #def.widgets do _walk_widgets(def.widgets[i], _widget_index[mod_id]) end
    _dbg("[mt] register_category: mod_id=%s label=%s widgets=%d vmf_synced=%s",
        mod_id, tostring(record.label), #def.widgets, tostring(record.vmf_synced))
    return true
end

function SettingsModule.is_registered(mod_id)
    return _categories[mod_id] ~= nil
end

function SettingsModule.list_categories()
    local out = {}
    for i = 1, #_ordered_ids do
        local id = _ordered_ids[i]
        out[i] = _categories[id]
    end
    return out
end

function SettingsModule.get_category(mod_id)
    return _categories[mod_id]
end

function SettingsModule.get_widget(mod_id, setting_id)
    local idx = _widget_index[mod_id]
    return idx and idx[setting_id] or nil
end

function SettingsModule.get(mod_id, setting_id)
    local stored = mod:get(_kv_key(mod_id, setting_id))
    if stored ~= nil then return stored end
    local widget = SettingsModule.get_widget(mod_id, setting_id)
    if widget then return widget.default end
    return nil
end

function SettingsModule.set(mod_id, setting_id, value)
    mod:set(_kv_key(mod_id, setting_id), value)
    local widget = SettingsModule.get_widget(mod_id, setting_id)
    if widget and type(widget.on_change) == "function" then
        local ok, err = pcall(widget.on_change, value)
        if not ok then
            _dbg_alert("[mt] on_change raised for %s.%s: %s",
                tostring(mod_id), tostring(setting_id), tostring(err))
        end
    end
    return value
end

-- Surfaces the kv key shape for diagnostics / tests; not part of the public
-- API contract.
function SettingsModule._kv_key(mod_id, setting_id) return _kv_key(mod_id, setting_id) end

return SettingsModule
