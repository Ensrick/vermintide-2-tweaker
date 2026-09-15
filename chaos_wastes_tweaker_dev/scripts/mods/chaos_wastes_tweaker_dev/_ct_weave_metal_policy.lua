-- _ct_weave_metal_policy.lua -- engine-free contract for the Metal wind curse adapter (#253).
--
-- Pure decisions for the first staged Weave wind ("Metal first" in
-- WEAVE_CURSE_FEASIBILITY_253.md): the explicit CT context that stands in for the
-- Metal template's global `Managers.weave:get_wind_strength()` read, the chat
-- command grammar (`/ct_weave_metal on | off | status | strength <1-5>`), the
-- host-side per-level mutator-list composition, and the armor snapshot/compare
-- helpers the teardown check uses. Ordinary Lua values only; the runtime owner
-- (`_ct_weave_metal_runtime.lua`) binds these decisions to live engine seams.
-- Invariants: the context exposes ONLY the values Metal consumes (`wind`,
-- `wind_strength`); the adapter is off by default and never appears in the
-- curse menu; composition never mutates the list it is handed.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: mod:dofile
-- from _ct_weave_metal_runtime.lua; qa/lua/tests/test_ct_weave_metal_policy.lua.
local M = {}

M.WIND = "metal"
M.MUTATOR = "metal"
M.MECHANISM = "deus"
M.COMMAND = "ct_weave_metal"
M.DEFAULT_ENABLED = false
M.EXPOSED_IN_MENU = false
M.STRENGTH_SETTING = "weave_metal_strength"
-- Vanilla Weave templates carry wind_strength 1..5 [src: scripts/settings/weaves/weave_10.lua:6].
M.DEFAULT_STRENGTH = 1
M.MIN_STRENGTH = 1
M.MAX_STRENGTH = 5
-- Metal stores exactly one context value [src: mutator_metal.lua:61]; `wind` is the identity tag.
M.CONTEXT_KEYS = { "wind", "wind_strength" }
M.ACTIONS = { "on", "off", "status", "strength" }
M.USAGE = "/ct_weave_metal on | off | status | strength <1-5>"
-- Vanilla armor override the template declares [src: mutator_metal.lua:21-34].
M.EXPECTED_ARMOR_CATEGORY = 6
M.EXPECTED_ARMOR_BREEDS = 11

function M.normalize_strength(value)
    local n = tonumber(value)
    if n == nil or n ~= n or n ~= math.floor(n) then return nil end
    if n < M.MIN_STRENGTH or n > M.MAX_STRENGTH then return nil end
    return n
end

function M.effective_strength(stored)
    return M.normalize_strength(stored) or M.DEFAULT_STRENGTH
end

function M.build_context(strength)
    return { wind = M.WIND, wind_strength = M.effective_strength(strength) }
end

function M.context_keys(context)
    local keys = {}
    for key in pairs(context) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return keys
end

function M.context_matches(context)
    if type(context) ~= "table" then return false, "context is not a table" end
    local keys = M.context_keys(context)
    if table.concat(keys, ",") ~= table.concat(M.CONTEXT_KEYS, ",") then
        return false, "context keys drifted: " .. table.concat(keys, ",")
    end
    if context.wind ~= M.WIND then
        return false, "context wind drifted: " .. tostring(context.wind)
    end
    if M.normalize_strength(context.wind_strength) == nil then
        return false, "context wind_strength invalid: " .. tostring(context.wind_strength)
    end
    return true
end

-- Chat grammar. A bare command reads as `status`. Returns a parsed table or
-- nil plus a player-facing reason.
function M.parse_command(action, value)
    if action == nil or action == "" then return { action = "status" } end
    if type(action) ~= "string" then return nil, "unknown action" end
    action = action:lower()
    if action == "on" or action == "off" or action == "status" then
        if value ~= nil and value ~= "" then
            return nil, "'" .. action .. "' takes no argument"
        end
        return { action = action }
    end
    if action == "strength" then
        local n = M.normalize_strength(value)
        if not n then
            return nil, string.format("strength must be a whole number from %d to %d",
                M.MIN_STRENGTH, M.MAX_STRENGTH)
        end
        return { action = "strength", strength = n }
    end
    return nil, "unknown action '" .. action .. "'"
end

-- Pure state transition: returns enabled, strength, changed.
function M.transition(parsed, enabled, strength)
    enabled = enabled == true
    strength = M.effective_strength(strength)
    if parsed.action == "on" then return true, strength, not enabled end
    if parsed.action == "off" then return false, strength, enabled end
    if parsed.action == "strength" then
        return enabled, parsed.strength, parsed.strength ~= strength
    end
    return enabled, strength, false
end

-- Host-side per-level composition. Returns a NEW list with the Metal mutator
-- appended, or nil plus the reason nothing was appended. Never mutates `list`.
function M.compose_mutators(list, opts)
    opts = opts or {}
    if opts.enabled ~= true then return nil, "disabled" end
    if opts.is_server ~= true then return nil, "client" end
    if opts.mechanism ~= M.MECHANISM then
        return nil, "mechanism:" .. tostring(opts.mechanism)
    end
    if type(list) ~= "table" then return nil, "no_list" end
    local copy = {}
    for i = 1, #list do
        if list[i] == M.MUTATOR then return nil, "already_listed" end
        copy[i] = list[i]
    end
    copy[#copy + 1] = M.MUTATOR
    return copy, "appended"
end

function M.armor_breeds(template)
    local names = type(template) == "table" and template.modify_primary_armor_category_breeds
    local copy = {}
    if type(names) == "table" then
        for i = 1, #names do copy[i] = names[i] end
    end
    return copy
end

-- Records each breed's current primary armor category (false when unset) so
-- teardown can prove vanilla's stop path restored it exactly
-- [src: mutator_templates.lua:63-73].
function M.snapshot_armor(breeds, names)
    local snapshot, count = {}, 0
    breeds = type(breeds) == "table" and breeds or {}
    for i = 1, #names do
        local breed = breeds[names[i]]
        local category = type(breed) == "table" and breed.primary_armor_category or nil
        snapshot[names[i]] = category or false
        count = count + 1
    end
    return snapshot, count
end

function M.armor_mismatches(breeds, snapshot)
    local bad, total = 0, 0
    breeds = type(breeds) == "table" and breeds or {}
    for name, expected in pairs(snapshot or {}) do
        total = total + 1
        local breed = breeds[name]
        local current = type(breed) == "table" and breed.primary_armor_category or nil
        if (current or false) ~= expected then bad = bad + 1 end
    end
    return bad, total
end

function M.status_text(view)
    view = view or {}
    return string.format(
        "Metal wind adapter: %s (hidden from the curse menu); strength %d; host=%s; mechanism=%s; bridge=%s; level=%s; activations=%d teardowns=%d armor_faults=%d",
        view.enabled and "ON" or "off", M.effective_strength(view.strength),
        view.is_server and "yes" or "no", tostring(view.mechanism or "none"),
        view.bridged and "ready" or "missing", view.level_active and "armed" or "idle",
        tonumber(view.activations) or 0, tonumber(view.teardowns) or 0,
        tonumber(view.restored_bad) or 0)
end

return M
