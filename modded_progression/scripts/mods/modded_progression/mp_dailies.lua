-- MP-owned daily quest lifecycle and Silver Shilling ledger (issue #573).
--
-- Vanilla supplies quest templates and event mappings, but daily selection and
-- reset timestamps are PlayFab CloudScript concerns.  MP therefore uses the
-- vanilla objective definitions with an explicitly local, deterministic UTC
-- rotation.  Roster, progress, claim markers, and currency live in one VMF
-- setting so a claim is one copy-on-write persistence transaction.

local mod = get_mod("mp")
local M = {}

M.STATE_KEY = "mp_daily_v2"
M.ID_PREFIX = "mp_daily_v2_"
M.REWARD_KIND = "SM"
M.REWARD_AMOUNT = 5
M.SCHEMA = 2

local DAY_SECONDS = 86400
local ROSTER_SIZE = 3
local _ui_serial = 0
local _ui_state_revision
local _ui_state_balance
local DAILY_TEMPLATES = {
    "daily_collect_grimoires",
    "daily_collect_loot_die",
    "daily_collect_painting_scrap",
    "daily_collect_tomes",
    "daily_complete_levels_hero_bright_wizard",
    "daily_complete_levels_hero_dwarf_ranger",
    "daily_complete_levels_hero_empire_soldier",
    "daily_complete_levels_hero_witch_hunter",
    "daily_complete_levels_hero_wood_elf",
    "daily_complete_quickplay_missions",
    "daily_kill_bosses",
    "daily_kill_critters",
    "daily_kill_elites",
    "daily_score_headshots",
}

local function log(fmt, ...)
    pcall(printf, "[mp:daily] " .. fmt, ...)
end

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[deep_copy(key, seen)] = deep_copy(child, seen) end
    return copy
end

local function utc_period(now)
    return math.floor((tonumber(now) or os.time()) / DAY_SECONDS)
end

local function target_for(template_name)
    local target = QuestSettings and QuestSettings[template_name]
    return type(target) == "number" and math.max(1, math.floor(target)) or nil
end

local function templates()
    return require("scripts/managers/quest/quest_templates").quests
end

local function candidate_pool()
    local source = templates()
    local pool = {}
    for _, name in ipairs(DAILY_TEMPLATES) do
        local template = source[name]
        if template and type(template.stat_mappings) == "table"
                and #template.stat_mappings == 1 and target_for(name) then
            pool[#pool + 1] = name
        end
    end
    return pool
end

-- Small deterministic PRNG. Values stay below Lua's exact-integer boundary.
local function next_seed(seed)
    return (seed * 48271) % 2147483647
end

local function build_roster(period)
    local pool = candidate_pool()
    local entries = {}
    local seed = (period * 7919 + 573) % 2147483648
    for slot = 1, math.min(ROSTER_SIZE, #pool) do
        seed = next_seed(seed)
        local index = (seed % #pool) + 1
        local template_name = table.remove(pool, index)
        local key = string.format("%s%d_slot_%d", M.ID_PREFIX, period, slot)
        local id = string.format("%s%d_%d_%s", M.ID_PREFIX, period, slot, template_name)
        entries[key] = {
            id = id,
            key = key,
            template = template_name,
            target = target_for(template_name),
            progress = 0,
            claimed = false,
            reward = {
                reward_type = "currency",
                currency_code = M.REWARD_KIND,
                amount = M.REWARD_AMOUNT,
            },
        }
    end
    return entries
end

local function normalized_ledger(ledger)
    ledger = type(ledger) == "table" and deep_copy(ledger) or {}
    ledger.balance = math.max(0, math.floor(tonumber(ledger.balance) or 0))
    ledger.transactions = type(ledger.transactions) == "table" and ledger.transactions or {}
    return ledger
end

local function new_state(period, previous, reason)
    local revision = type(previous) == "table" and tonumber(previous.revision) or 0
    return {
        schema = M.SCHEMA,
        revision = revision + 1,
        period = period,
        high_water_period = period,
        next_reset_at = (period + 1) * DAY_SECONDS,
        last_wall_time = os.time(),
        entries = build_roster(period),
        ledger = normalized_ledger(previous and previous.ledger),
        migration = {
            legacy_simulated_dailies_retired = true,
            legacy_currency_not_imported = true,
            reason = reason,
        },
    }
end

local function read_state()
    local state = mod:get(M.STATE_KEY)
    return type(state) == "table" and state or nil
end

-- Issue #578: UI consumers need a cheap, monotonic invalidation edge. The
-- persisted revision can restart after reset/migration, so expose a runtime
-- serial that advances whenever the observed revision or balance changes.
-- Store views compare this scalar inside their native sync methods; no extra
-- timer, polling loop, or per-frame table allocation is introduced.
local function publish_ui_state(state)
    local revision = type(state) == "table" and tonumber(state.revision) or nil
    local balance = type(state) == "table" and type(state.ledger) == "table"
        and tonumber(state.ledger.balance) or 0
    if revision ~= _ui_state_revision or balance ~= _ui_state_balance then
        _ui_state_revision = revision
        _ui_state_balance = balance
        _ui_serial = _ui_serial + 1
    end
end

local function write_state(state)
    local ok, err = pcall(mod.set, mod, M.STATE_KEY, state, false)
    if not ok then return nil, err end
    publish_ui_state(state)
    return true
end

local function register_templates(state)
    if not state or type(state.entries) ~= "table" then return end
    local source = templates()
    for _, entry in pairs(state.entries) do
        local original = source[entry.template]
        if original and not source[entry.id] then source[entry.id] = deep_copy(original) end
    end
end

function M.ensure(now)
    now = tonumber(now) or os.time()
    local wall_period = utc_period(now)
    local state = read_state()
    local reason

    if not state or state.schema ~= M.SCHEMA or type(state.entries) ~= "table" then
        reason = state and "schema_migration" or "initial_generation"
        state = new_state(wall_period, state, reason)
        write_state(state)
        log("generation period=%d reason=%s roster=%d revision=%d", wall_period, reason, ROSTER_SIZE, state.revision)
    else
        local high_water = math.max(tonumber(state.high_water_period) or state.period or wall_period,
            tonumber(state.period) or wall_period)
        if wall_period > high_water then
            reason = wall_period > high_water + 1 and "missed_resets" or "scheduled_reset"
            local old_period = state.period
            state = new_state(wall_period, state, reason)
            write_state(state)
            log("reset old_period=%s new_period=%d reason=%s revision=%d", tostring(old_period), wall_period, reason, state.revision)
        elseif wall_period < high_water then
            -- Never roll a roster back or mint a second reward set after a
            -- backwards wall-clock adjustment.
            if state.last_clock_warning_period ~= wall_period then
                state = deep_copy(state)
                state.last_clock_warning_period = wall_period
                state.last_wall_time = now
                state.revision = (tonumber(state.revision) or 0) + 1
                write_state(state)
                log("clock_backwards wall_period=%d retained_period=%d revision=%d", wall_period, high_water, state.revision)
            end
        end
    end

    register_templates(state)
    publish_ui_state(state)
    return state
end

function M.is_owned_id(id)
    return type(id) == "string" and id:sub(1, #M.ID_PREFIX) == M.ID_PREFIX
end

function M.find_by_id(id, state)
    if not M.is_owned_id(id) then return nil end
    state = state or M.ensure()
    for _, entry in pairs(state.entries or {}) do
        if entry.id == id then return entry end
    end
    return nil
end

function M.quest_slice()
    local state = M.ensure()
    local result = {}
    for key, entry in pairs(state.entries) do
        if not entry.claimed then
            result[key] = { name = entry.id, type = "daily", reward = deep_copy(entry.reward) }
        end
    end
    return result
end

function M.quest_by_key(key)
    local state = M.ensure()
    local entry = state.entries and state.entries[key]
    if not entry or entry.claimed then return nil end
    return { name = entry.id, type = "daily", reward = deep_copy(entry.reward) }
end

function M.key_for_id(id)
    local entry = M.find_by_id(id)
    return entry and entry.key or nil
end

local function display_value(value)
    if type(value) == "function" then
        local ok, result = pcall(value)
        return ok and result or "<Error>"
    end
    if type(value) == "string" then
        local localize = rawget(_G, "Localize")
        if localize then
            local ok, result = pcall(localize, value)
            if ok then return result end
        end
    end
    return value
end

-- Build the evaluated UI row without ever delegating an MP-owned id to
-- QuestManager.get_data_by_id. Vanilla's completed/progress callbacks read a
-- registered StatisticsDatabase definition and fatal for our intentionally
-- local-only keys (#581). The source template remains presentation-only.
function M.quest_data(id)
    local entry = M.find_by_id(id)
    if not entry then return nil end
    local source = templates()[entry.template] or {}
    return {
        claimed = entry.claimed == true,
        id = id,
        name = display_value(source.name),
        desc = display_value(source.desc),
        icon = source.icon,
        summary_icon = source.summary_icon,
        completed = (entry.progress or 0) >= entry.target,
        progress = { math.min(entry.progress or 0, entry.target), entry.target },
        requirements = nil,
        reward = deep_copy(entry.reward),
    }
end

local function mapping_matches(map, ...)
    for index = 1, select("#", ...) do
        if type(map) ~= "table" then return false end
        map = map[select(index, ...)]
        if not map then return false end
    end
    return true
end

function M.increment(quests, ...)
    local state = M.ensure()
    local next_state
    local changed = 0
    for _, quest_data in pairs(quests or {}) do
        local entry = M.find_by_id(quest_data.name, state)
        if entry and not entry.claimed and (entry.progress or 0) < entry.target then
            local template = templates()[entry.template]
            local map = template and template.stat_mappings and template.stat_mappings[1]
            if map and mapping_matches(map, ...) then
                next_state = next_state or deep_copy(state)
                local next_entry = next_state.entries[entry.key]
                next_entry.progress = math.min(next_entry.target, (next_entry.progress or 0) + 1)
                changed = changed + 1
                local p = next_entry.progress
                if p == 1 or p == next_entry.target or p % 10 == 0 then
                    log("progress id=%s value=%d/%d", next_entry.id, p, next_entry.target)
                end
            end
        end
    end
    if next_state then
        next_state.revision = (tonumber(next_state.revision) or 0) + 1
        next_state.last_wall_time = os.time()
        write_state(next_state)
    end
    return changed
end

function M.claim(ids)
    local state = M.ensure()
    local next_state = deep_copy(state)
    local seen = {}
    local granted = {}
    local total = 0

    for _, id in ipairs(ids or {}) do
        if seen[id] then return nil, "Duplicate quest id in claim transaction." end
        seen[id] = true
        local entry = M.find_by_id(id, next_state)
        if not entry then return nil, "Quest is not owned by the current MP roster." end
        if entry.claimed or next_state.ledger.transactions[id] then return nil, "Quest already claimed." end
        if (entry.progress or 0) < entry.target then return nil, "Quest is not complete." end
        entry.claimed = true
        next_state.ledger.transactions[id] = {
            kind = "daily_claim",
            amount = M.REWARD_AMOUNT,
            period = next_state.period,
        }
        total = total + M.REWARD_AMOUNT
        granted[#granted + 1] = id
    end
    if #granted == 0 then return nil, "No quests supplied." end

    next_state.ledger.balance = next_state.ledger.balance + total
    next_state.revision = (tonumber(next_state.revision) or 0) + 1
    local wrote, write_error = write_state(next_state)
    if not wrote then return nil, "Atomic claim persistence failed: " .. tostring(write_error) end

    local verified = read_state()
    for _, id in ipairs(granted) do
        local verified_entry = verified and M.find_by_id(id, verified)
        if not verified or not verified.ledger or not verified.ledger.transactions[id]
                or verified.ledger.balance ~= next_state.ledger.balance
                or not verified_entry or not verified_entry.claimed then
            return nil, "Atomic claim persistence verification failed."
        end
    end
    log("claim count=%d amount=%d balance=%d revision=%d", #granted, total,
        verified.ledger.balance, verified.revision)
    return granted, total
end

function M.balance()
    return M.ensure().ledger.balance
end

function M.ui_revision()
    return _ui_serial
end

local function ledger_adjust(amount, kind)
    amount = math.floor(tonumber(amount) or 0)
    local state = M.ensure()
    if amount < 0 and state.ledger.balance < -amount then return false end
    local next_state = deep_copy(state)
    next_state.ledger.balance = next_state.ledger.balance + amount
    next_state.revision = (tonumber(next_state.revision) or 0) + 1
    local tx_id = string.format("mp_ledger_%s_%d_%d", kind, os.time(), next_state.revision)
    next_state.ledger.transactions[tx_id] = { kind = kind, amount = amount, period = next_state.period }
    local wrote, write_error = write_state(next_state)
    if not wrote then
        log("ledger_write_failed kind=%s error=%s", kind, tostring(write_error))
        return false
    end
    local verified = read_state()
    if not verified or not verified.ledger or verified.ledger.balance ~= next_state.ledger.balance
            or not verified.ledger.transactions[tx_id] then
        log("ledger_verify_failed kind=%s revision=%d", kind, next_state.revision)
        return false
    end
    log("ledger kind=%s amount=%d balance=%d revision=%d", kind, amount,
        next_state.ledger.balance, next_state.revision)
    return true
end

function M.credit(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    return ledger_adjust(amount, "local_credit")
end

function M.spend(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    return ledger_adjust(-amount, "local_spend")
end

function M.seconds_until_reset(now)
    now = tonumber(now) or os.time()
    return math.max(0, M.ensure(now).next_reset_at - now)
end

function M.reset()
    local ok, err = pcall(mod.set, mod, M.STATE_KEY, {}, false)
    if not ok then return nil, err end
    publish_ui_state(nil)
    return true
end

-- Pure test seams used by the in-game regression command.
M._test = {
    deep_copy = deep_copy,
    utc_period = utc_period,
    new_state = new_state,
    next_seed = next_seed,
}

return M
