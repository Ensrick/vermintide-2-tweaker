local mod = get_mod("gut_dev")

-- Mod Tweaker: controller + public API surface.
-- v0.1 scaffold. Wires the registry/persistence module (_mod_tweaker_settings),
-- the view class (_mod_tweaker_view), and exposes a single ModTweaker handle
-- that other mods reach via `get_mod("gut_dev").mod_tweaker`. The view itself
-- doesn't render yet — that's tasks #6-8. This task just stands up the API
-- surface so dogfood / regression hooks can land in parallel.

local ModTweaker = {}

-- Two-helper debug telemetry (PROJECT_STANDARDS § 3.6). gui_tweaker.lua wires
-- both halves via init_dbg(...) before the ESC entry hooks fire.
local _dbg = function() end
local _dbg_alert = function() end

function ModTweaker.init_dbg(dbg, dbg_alert)
    if type(dbg) == "function" then _dbg = dbg end
    if type(dbg_alert) == "function" then _dbg_alert = dbg_alert end
end

local Settings = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_settings")
local RuntimeGates = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_runtime_gates")
local Profiles = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_profiles")
local ProfileEventsModule = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_profile_events")
local ProfileEvents = ProfileEventsModule.new(Profiles, mod, function(...)
    local printer = rawget(_G, "printf")
    if printer then printer(...) end
end)

-- ---------------------------------------------------------------
-- Public API — addressed via get_mod("gut_dev").mod_tweaker:<method>(...).
-- ---------------------------------------------------------------

function ModTweaker:register_category(def)
    local ok, err = Settings.register_category(def)
    if not ok then
        _dbg_alert("[mt] register_category rejected: %s", tostring(err))
    end
    return ok, err
end

function ModTweaker:is_registered(mod_id)
    return Settings.is_registered(mod_id)
end

function ModTweaker:list_categories()
    return Settings.list_categories()
end

function ModTweaker:get_category(mod_id)
    return Settings.get_category(mod_id)
end

function ModTweaker:get(mod_id, setting_id)
    return Settings.get(mod_id, setting_id)
end

function ModTweaker:set(mod_id, setting_id, value)
    return Settings.set(mod_id, setting_id, value)
end

-- (#371) Live safety gates for settings whose owning feature cannot operate in
-- the current lobby. This API affects Mod Tweaker presentation and interaction;
-- the owner remains responsible for fail-closed runtime/network enforcement.
function ModTweaker:register_runtime_gate(gate_id, spec)
    local ok, err = RuntimeGates.register(gate_id, spec)
    if not ok then
        _dbg_alert("[mt:runtime-gate] registration rejected: %s", tostring(err))
    end
    return ok, err
end

function ModTweaker:unregister_runtime_gate(gate_id)
    return RuntimeGates.unregister(gate_id)
end

function ModTweaker:runtime_gate_status(mod_id, setting_id)
    return RuntimeGates.status(mod_id, setting_id)
end

function ModTweaker:apply_runtime_gate(row, mod_id, setting_id)
    return RuntimeGates.apply_row(row, mod_id, setting_id)
end

-- (#919) Owner-facing profile commit boundary. Mod Tweaker owns persistence,
-- while the registered owner is responsible for one bounded, domain-specific
-- snapshot of the values it will actually consume.
function ModTweaker:get_active_profile(tab_id)
    return ProfileEvents.get_active(tab_id)
end

function ModTweaker:register_profile_diagnostic(tab_id, callback)
    local ok, err = ProfileEvents.register(tab_id, callback)
    if not ok then _dbg_alert("[mt:profile-event] registration rejected: %s", tostring(err)) end
    return ok, err
end

function ModTweaker:emit_profile_diagnostic(tab_id, phase)
    return ProfileEvents.emit(tab_id, phase)
end

if type(mod._gut_rt_register) == "function" then
    mod._gut_rt_register("issue919_profile_diagnostic_api", function()
        if type(ModTweaker.get_active_profile) ~= "function"
                or type(ModTweaker.register_profile_diagnostic) ~= "function"
                or type(ModTweaker.emit_profile_diagnostic) ~= "function" then
            return "profile diagnostic API is incomplete"
        end
    end)
end

function ModTweaker:prune_runtime_gated_pending(pending_by_mod, mod_ids)
    local blocked = RuntimeGates.prune_pending(pending_by_mod, mod_ids)
    if blocked > 0 then
        _dbg_alert("[mt:runtime-gate] discarded %d newly blocked pending edit(s)", blocked)
    end
    return blocked
end

-- (#446) Mutually-exclusive group API. A sibling mod declares that a set of its own
-- (or cross-mod) boolean settings are mutually exclusive: switching one ON in the Mod
-- Tweaker turns the others OFF. The optional third argument requests the native Mod
-- Tweaker presentation: one collapsible containing a selected bubble for exactly one
-- member, plus a UI-only None/default choice. The underlying settings remain ordinary
-- VMF booleans, so the stock VMF menu and a missing/older gut keep working.
--
--   get_mod("gut_dev").mod_tweaker:register_exclusive_group("crt_zealot_thp", {
--       { mod = "crt", setting = "zealot_thp_none" },     -- None [Default]
--       { mod = "crt", setting = "zealot_thp_on_ability" },
--       { mod = "crt", setting = "zealot_thp_devotion" },
--   }, { control = "radio", label = "zealot_thp_group", none_label = "none_default" })
function ModTweaker:register_exclusive_group(group_id, members, presentation)
    local ok, err = Settings.register_exclusive_group(group_id, members, presentation)
    if not ok then
        _dbg_alert("[mt] register_exclusive_group rejected: %s", tostring(err))
    end
    return ok, err
end

-- Reverse lookup: the group_id a (mod_id, setting_id) belongs to, or nil. The view's
-- toggle handler calls this to decide whether a checkbox flip must sweep siblings.
function ModTweaker:get_exclusive_group_id(mod_id, setting_id)
    return Settings.get_exclusive_group_id(mod_id, setting_id)
end

-- The ordered member list for a group_id, or nil.
function ModTweaker:get_exclusive_members(group_id)
    return Settings.get_exclusive_members(group_id)
end

-- Optional { control="radio", label=, none_label= } presentation metadata.
function ModTweaker:get_exclusive_presentation(group_id)
    return Settings.get_exclusive_presentation(group_id)
end

-- (#505) Filtered/searchable dropdown API. A sibling mod declares CATEGORY chips for one of its
-- dropdown settings; when the user opens that dropdown in the Mod Tweaker, the popup gains (a) a
-- type-to-filter search line (works on ANY long dropdown with no registration) and (b) the declared
-- category chips to narrow the list. Each category is { label = <string>, match = <fn OR key-list> }:
-- a function match is called with (option_value, option_text) and returns whether the option belongs;
-- a key-list match tests the option VALUE for membership. Mirrors the #446 registry/API shape.
--
--   get_mod("gut_dev").mod_tweaker:register_dropdown_categories("ct_dev", "ctdm_base", {
--       { label = "Travel",    match = function(value) return travel_set[value] end },
--       { label = "Signature", match = { "sig_gorge", "sig_volcano" } },   -- key-list form
--   })
function ModTweaker:register_dropdown_categories(mod_id, setting_id, categories)
    local ok, err = Settings.register_dropdown_categories(mod_id, setting_id, categories)
    if not ok then
        _dbg_alert("[mt] register_dropdown_categories rejected: %s", tostring(err))
    end
    return ok, err
end

-- The normalized category list registered for a (mod_id, setting_id), or nil. The view calls this
-- when a dropdown opens to decide whether to render category chips.
function ModTweaker:get_dropdown_categories(mod_id, setting_id)
    return Settings.get_dropdown_categories(mod_id, setting_id)
end

-- Install entry point: wires debug + propagates to sub-modules. Returns the
-- handle table so the owner module can publish it onto `mod`.
function ModTweaker.install(dbg, dbg_alert)
    ModTweaker.init_dbg(dbg, dbg_alert)
    Settings.init_dbg(dbg, dbg_alert)
    RuntimeGates.init_dbg(dbg, dbg_alert)
    _dbg("[mt] installed")
    return ModTweaker
end

return ModTweaker
