-- _wt_sword_push_combo_owner.lua - once-per-mod #348 boot producer authority.
--
-- Owns the schema-1 boot record and private native-chain identity snapshots.
-- The entry retains this module once because VMF dofile is not a cache, and
-- supplies the setting getter and original producer at its existing load position.
-- Reentry never rereads settings or repairs lost authority; a failed first
-- attempt is terminal and native producer writes are not rolled back.
--
-- Owned by: the matching Weapons Tweaker entry point. Consumed via:
-- mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_sword_push_combo_owner")
local M = {}
local installed = setmetatable({}, { __mode = "k" })
local RECORD, SETTING = "_wt348_sword_push_combo", "wt_revert_1h_sword_push_combo"
local SWORD = "one_handed_swords_template_1"
local FIELDS = { "schema", "setting_id", "boot_enabled", "weapons", "source", "action", "before", "applied" }
local function chain_snapshot(value)
    if value == nil then return { nodes = {} } end
    if type(value) ~= "table" then return nil end
    local nodes, seen, cells = {}, {}, 0
    local function visit(t)
        if seen[t] then return true end
        if getmetatable(t) ~= nil or #nodes >= 32 then return false end
        seen[t] = true
        local row = { target = t, fields = {}, count = 0 }
        nodes[#nodes + 1] = row
        for key, child in next, t do
            if type(key) ~= "string" and type(key) ~= "number" then return false end
            cells = cells + 1; if cells > 256 then return false end
            row.count = row.count + 1; row.fields[key] = child
            if type(child) == "table" and not visit(child) then return false end
        end
        return true
    end
    return visit(value) and { nodes = nodes } or nil
end
local function intact(snapshot)
    if not snapshot then return false end
    for _, row in ipairs(snapshot.nodes) do
        if getmetatable(row.target) ~= nil then return false end
        local count = 0
        for key, value in next, row.target do
            count = count + 1
            if not rawequal(rawget(row.fields, key), value) then return false end
        end
        if count ~= row.count then return false end
        for key, value in next, row.fields do
            if not rawequal(rawget(row.target, key), value) then return false end
        end
    end
    return true
end
local function view(weapons)
    if weapons ~= nil and type(weapons) ~= "table" then return nil end
    local source = weapons and rawget(weapons, SWORD)
    if source ~= nil and type(source) ~= "table" then return nil end
    local actions = source and rawget(source, "actions")
    if actions ~= nil and type(actions) ~= "table" then return nil end
    local one = actions and rawget(actions, "action_one")
    if one ~= nil and type(one) ~= "table" then return nil end
    local action = one and rawget(one, "light_attack_bopp")
    if action ~= nil and type(action) ~= "table" then return nil end
    return { source = source, action = action, chain = action and rawget(action, "allowed_chain_actions") }
end
local function valid(mod, weapons, prior)
    local record, now = rawget(mod, RECORD), view(weapons)
    if prior.failed or not now or not rawequal(record, prior.record)
            or getmetatable(record) ~= nil or not rawequal(weapons, prior.weapons)
            or not rawequal(now.source, prior.source) or not rawequal(now.action, prior.action)
            or not rawequal(now.chain, prior.applied) or not intact(prior.before_snapshot)
            or not intact(prior.applied_snapshot) then return false end
    local count = 0
    for key, value in next, record do
        count = count + 1
        if not rawequal(rawget(prior.fields, key), value) then return false end
    end
    if count ~= prior.field_count then return false end
    for key, value in next, prior.fields do
        if not rawequal(rawget(record, key), value) then return false end
    end
    return true
end
function M.install(mod, weapons, get_enabled, patch)
    if type(mod) ~= "table" or type(get_enabled) ~= "function" or type(patch) ~= "function" then
        return nil, "dependencies-unavailable"
    end
    local prior = installed[mod]
    if prior then
        if valid(mod, weapons, prior) then return prior.record, "already-installed" end
        return nil, "producer-authority-lost"
    end
    if rawget(mod, RECORD) ~= nil then return nil, "record-without-private-authority" end
    -- A failed first attempt cannot be reinterpreted as a fresh boot.
    local state = { failed = true }; installed[mod] = state
    local ok, problem = pcall(function()
        local before = assert(view(weapons), "source-shape-unproven")
        local snapshot = assert(chain_snapshot(before.chain), "before-chain-unproven")
        local enabled = not not get_enabled()
        if enabled then patch() end -- Original producer operation, at the original load position.
        local after = assert(view(weapons), "source-shape-changed")
        assert(rawequal(before.source, after.source) and rawequal(before.action, after.action)
            and intact(snapshot), "producer-source-changed")
        local applied = assert(chain_snapshot(after.chain), "applied-chain-unproven")
        local record = { schema = 1, setting_id = SETTING, boot_enabled = enabled,
            weapons = weapons, source = before.source, action = before.action,
            before = before.chain, applied = after.chain }
        assert(rawget(mod, RECORD) == nil, "record-published-by-another-owner")
        state.weapons, state.source, state.action = weapons, before.source, before.action
        state.applied, state.before_snapshot, state.applied_snapshot = after.chain, snapshot, applied
        state.record, state.fields, state.field_count = record, {}, 0
        for _, key in ipairs(FIELDS) do
            local value = rawget(record, key)
            if value ~= nil then state.fields[key] = value; state.field_count = state.field_count + 1 end
        end
        rawset(mod, RECORD, record)
        state.failed = false
        assert(valid(mod, weapons, state), "record-readback-rejected")
    end)
    -- Preserve the first setting/producer exception, including its exact object.
    -- Native patch writes are not rolled back; no record/retry can bless them.
    if not ok then state.failed = true; error(problem, 0) end
    return state.record, "installed"
end
return M
