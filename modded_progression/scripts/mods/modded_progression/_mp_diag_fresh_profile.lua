-- _mp_diag_fresh_profile.lua - Read-only backend topology (#840) and login-cache (#1684) census.
--
-- The destructive fresh-
-- profile overlay remains disabled until every required consumer boundary is
-- proven. This module must stay pure: it never calls an interface method.
--
-- Owned by: modded_progression.lua. Consumed via: the entry-point dofile manifest.
local M = {}

M.PROFILE_INTERFACES = {
    { name = "items", slice = "inventory,loadouts,cosmetics", mirror_field = "_backend_mirror", methods = {
        "get_all_backend_items", "get_loadout", "get_item_from_id", "set_loadout_item" } },
    { name = "talents", slice = "talents", mirror_field = "_backend_mirror", methods = {
        "get_talents", "get_talent_tree", "set_talents" } },
    { name = "hero_attributes", slice = "experience,hero attributes", mirror_field = "_backend_mirror",
        methods = { "get", "set" } },
    { name = "peddler", slice = "currencies,store ownership", mirror_field = "_backend_mirror", methods = {
        "get_chips", "set_chips", "get_peddler_stock" } },
    -- Statistics is the one audited PlayFab interface that names this field
    -- `_mirror`; treating only `_backend_mirror` as canonical would hide it.
    { name = "statistics", slice = "progress,achievements", mirror_field = "_mirror",
        methods = { "get_stats", "save" } },
    { name = "quests", slice = "quests,reward claims", mirror_field = "_backend_mirror", methods = {
        "update_quests", "get_quests", "claim_quest_rewards" } },
    { name = "crafting", slice = "item mutation,unlocks", mirror_field = "_backend_mirror", methods = {
        "craft", "get_craft_result", "get_unlocked_weapon_skins", "get_unlocked_cosmetics" } },
    { name = "loot", slice = "containers,mission rewards,achievement rewards", mirror_field = "_backend_mirror",
        methods = { "open_loot_chest", "generate_end_of_level_loot", "claim_achievement_rewards",
            "get_highest_chest_level" } },
    { name = "keep_decorations", slice = "keep decoration ownership,loadout", mirror_field = "_backend_mirror",
        methods = { "get_decoration", "set_decoration", "get_unlocked_keep_decorations" } },
}

-- These manager methods bypass the loadout/talent/total-power override
-- registries and reach the canonical manager or mirror directly.
M.MANAGER_METHODS = {
    "get_interface", "get_read_only_data", "get_stats", "set_stats",
    "get_user_data", "set_user_data", "get_backend_mirror", "get_total_power_level",
}

local function _sorted_copy(values)
    local copy = {}
    for i, value in ipairs(values or {}) do copy[i] = value end
    table.sort(copy)
    return copy
end

function M.validate_catalog()
    local seen = {}
    for _, spec in ipairs(M.PROFILE_INTERFACES) do
        if type(spec.name) ~= "string" or spec.name == "" or seen[spec.name] then return false end
        if type(spec.slice) ~= "string" or spec.slice == "" or type(spec.mirror_field) ~= "string"
                or type(spec.methods) ~= "table" or #spec.methods == 0 then return false end
        seen[spec.name] = true
    end
    return #M.PROFILE_INTERFACES == 9 and #M.MANAGER_METHODS == 8
end

function M.audit(backend)
    local report = {
        rows = {},
        manager_missing = {},
        topology_complete = true,
        all_share_canonical = true,
    }
    local backend_is_table = type(backend) == "table"
    local interfaces = backend_is_table and rawget(backend, "_interfaces") or nil
    local canonical_mirror = backend_is_table and rawget(backend, "_backend_mirror") or nil
    report.canonical_mirror_present = canonical_mirror ~= nil

    for _, method in ipairs(M.MANAGER_METHODS) do
        if not backend_is_table or type(backend[method]) ~= "function" then
            report.manager_missing[#report.manager_missing + 1] = method
        end
    end
    if #report.manager_missing > 0 then report.topology_complete = false end

    for _, spec in ipairs(M.PROFILE_INTERFACES) do
        local interface = type(interfaces) == "table" and interfaces[spec.name] or nil
        local interface_is_table = type(interface) == "table"
        local row = {
            name = spec.name,
            slice = spec.slice,
            present = interface ~= nil,
            table_shape = interface_is_table,
            missing = {},
            same_mirror = nil,
        }
        if not interface_is_table then
            report.topology_complete = false
            report.all_share_canonical = false
        else
            for _, method in ipairs(spec.methods) do
                if type(interface[method]) ~= "function" then row.missing[#row.missing + 1] = method end
            end
            if #row.missing > 0 then report.topology_complete = false end
            local interface_mirror = rawget(interface, spec.mirror_field)
            row.same_mirror = canonical_mirror ~= nil and interface_mirror == canonical_mirror
            if not row.same_mirror then
                report.topology_complete = false
                report.all_share_canonical = false
            end
        end
        row.missing = _sorted_copy(row.missing)
        report.rows[#report.rows + 1] = row
    end

    if not report.canonical_mirror_present then
        report.topology_complete = false
        report.all_share_canonical = false
    end
    report.manager_missing = _sorted_copy(report.manager_missing)
    return report
end

function M.summary(report)
    local present, methods_missing, mirror_mismatch = 0, 0, 0
    for _, row in ipairs(report and report.rows or {}) do
        if row.present then present = present + 1 end
        methods_missing = methods_missing + #(row.missing or {})
        if row.same_mirror == false then mirror_mismatch = mirror_mismatch + 1 end
    end
    return {
        present = present,
        audited = #M.PROFILE_INTERFACES,
        methods_missing = methods_missing,
        manager_methods_missing = #(report and report.manager_missing or {}),
        mirror_mismatch = mirror_mismatch,
        topology_complete = report and report.topology_complete == true,
        all_share_canonical = report and report.all_share_canonical == true,
    }
end

-- #1684: inspect only the current native response cache. This does not fetch,
-- establish local eligibility, expand bundles, or grant anything. item_id is a
-- catalogue key in the native UI, NOT an owned/backend ItemInstanceId.
local function _login_raw(value, key)
    if type(value) == "table" then return rawget(value, key) end
    return nil -- exactly one nil; tail calls into type() require an argument
end

local function _login_finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function _login_scalar(value)
    local kind = type(value)
    if kind == "string" then
        local text = value:sub(1, 95):gsub("[^A-Za-z0-9_./:%-]", "?")
        return "s:" .. text .. (#value > 95 and "~" or "")
    end
    if kind == "number" then
        return _login_finite(value) and ("n:" .. string.format("%.17g", value)) or "n:nonfinite"
    end
    if kind == "boolean" then return value and "b:true" or "b:false" end
    return "type:" .. kind
end

function M.login_cache_lines(backend, realm, index)
    local function unavailable(status)
        return { "status=" .. status .. " request=none eligibility=unproven grant=none" }, 1
    end
    if realm ~= true then return unavailable("realm_unavailable") end
    local day = index
    if type(day) == "string" and #day <= 10 and day:match("^%d+$") then day = tonumber(day) end
    if not _login_finite(day) or day < 1 or day > 2147483647 or day ~= math.floor(day) then
        return unavailable("invalid_index")
    end
    local peddler = _login_raw(_login_raw(backend, "_interfaces"), "peddler")
    local payload = _login_raw(peddler, "_login_rewards")
    if type(payload) ~= "table" then return unavailable("cache_unavailable") end
    local schema = rawget(payload, "event_type")
    if schema ~= "personal_time_strike" and schema ~= "calendar" then
        return { "status=unsupported_schema event_type=" .. _login_scalar(schema)
            .. " request=none eligibility=unproven grant=none" }, 1
    end
    local row = _login_raw(rawget(payload, "rewards"), day)
    local metadata, fields_ok
    if schema == "personal_time_strike" then
        local total, next_at, end_at = rawget(payload, "total_claims"),
            rawget(payload, "next_claim_timestamp"), rawget(payload, "end_of_claim_timestamp")
        fields_ok = (total == nil or _login_finite(total))
            and _login_finite(next_at) and _login_finite(end_at)
        metadata = "total_claims=" .. _login_scalar(total)
            .. " next_claim_timestamp=" .. _login_scalar(next_at)
            .. " end_of_claim_timestamp=" .. _login_scalar(end_at)
    else
        local start_at, total, old = rawget(payload, "start_time"),
            rawget(payload, "total_rewards"), rawget(payload, "num_allowed_old_segments_to_claim")
        local claimed = _login_raw(rawget(payload, "claimed_rewards"), day)
        fields_ok = _login_finite(start_at) and _login_finite(total)
            and _login_finite(old) and _login_finite(claimed)
        metadata = "start_time=" .. _login_scalar(start_at) .. " total_rewards=" .. _login_scalar(total)
            .. " old_segments=" .. _login_scalar(old) .. " claimed_raw_counter=" .. _login_scalar(claimed)
    end
    local status = fields_ok and type(_login_raw(row, 1)) == "table"
        and "observed_cache" or "unsupported_data"
    local lines = { false, metadata }
    for i = 1, 8 do
        local reward = _login_raw(row, i)
        if reward ~= nil and (type(reward) ~= "table"
                or type(_login_raw(reward, "reward_type")) ~= "string") then status = "unsupported_data" end
        local key, amount, currency = _login_raw(reward, "item_id"),
            _login_raw(reward, "amount"), _login_raw(reward, "currency_code")
        if (amount ~= nil and not _login_finite(amount))
                or (currency ~= nil and type(currency) ~= "string")
                or (key ~= nil and type(key) ~= "string") then status = "unsupported_data" end
        -- The native UI indexes ItemMasterList/Currencies with this string.
        -- Malformed non-string keys are shape-only, never opaque identifiers.
        local catalogue_key = type(key) == "string" and _login_scalar(key) or ("type:" .. type(key))
        lines[#lines + 1] = string.format(
            "slot=%d kind=%s reward_type=%s currency_code=%s amount=%s catalog_item_key=%s",
            i, type(reward), _login_scalar(_login_raw(reward, "reward_type")),
            _login_scalar(currency), _login_scalar(amount), catalogue_key)
    end
    lines[1] = string.format("status=%s schema=%s index=%d request=none eligibility=unproven grant=none",
        status, schema, day)
    lines[#lines + 1] = "sampled_slots=1-8 slot9_present=" .. (_login_raw(row, 9) ~= nil and "true" or "false")
        .. " tail=unscanned"
    return lines, #lines
end

return M
