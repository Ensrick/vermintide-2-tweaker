-- _gut_custom_stats_policy.lua - engine-free host custom scoreboard statistics.
--
-- Owns the detached custom topic descriptors, the bounded per-mission ledger
-- keyed by stats_id, and the pure credit decisions for #1570 friendly-fire
-- damage, #1571 melee/ranged damage, and #1572 Permanent Health Restored.
-- The live adapter observes vanilla's own damage_dealt credit and the server
-- permanent-health write; this module never touches StatisticsDefinitions,
-- NetworkLookup, or a vanilla wire.
-- Owned by: _gut_custom_stats.lua. Consumed via: mod:dofile.
local M = {}

M.MAX_PLAYERS = 16
M.MAX_OBSERVED = 8
M.MAX_VALUE = 1000000000
M.MAX_EVENT = 1000000
M.MAX_STATS_ID_BYTES = 64
M.SCORE_PLAYER_LIMIT = 4

M.FRIENDLY_FIRE = "friendly_fire_damage"
M.MELEE = "melee_damage_dealt"
M.RANGED = "ranged_damage_dealt"
M.PERMANENT_HEALTH = "permanent_health_restored"

-- Appended after #1414's thirteen native/supplemental rows only when the user
-- enables the custom rows, so the default registry stays thirteen topics.
M.TOPICS = {
    {
        name = M.FRIENDLY_FIRE,
        display_text = "gut_scoreboard_topic_friendly_fire_damage",
        custom = true,
        mod_localized = true,
    },
    {
        name = M.MELEE,
        display_text = "gut_scoreboard_topic_melee_damage_dealt",
        custom = true,
        mod_localized = true,
    },
    {
        name = M.RANGED,
        display_text = "gut_scoreboard_topic_ranged_damage_dealt",
        custom = true,
        mod_localized = true,
    },
    {
        name = M.PERMANENT_HEALTH,
        display_text = "gut_scoreboard_topic_permanent_health_restored",
        custom = true,
        mod_localized = true,
    },
}

local TOPIC_SET = {}
for _, topic in ipairs(M.TOPICS) do TOPIC_SET[topic.name] = true end

local function _finite(value)
    return type(value) == "number" and value == value
        and value < math.huge and value > -math.huge
end

function M.is_topic(name)
    return type(name) == "string" and TOPIC_SET[name] == true
end

function M.valid_stats_id(stats_id)
    return type(stats_id) == "string" and #stats_id > 0
        and #stats_id <= M.MAX_STATS_ID_BYTES
        and stats_id:match("^[%w%._:%-]+$") ~= nil
end

function M.new_ledger()
    return { rows = {}, count = 0, overflow = 0, rejected = 0 }
end

local function _ledger_ok(ledger)
    return type(ledger) == "table" and type(ledger.rows) == "table"
        and type(ledger.count) == "number"
end

-- Credit one validated amount. A new player row beyond the cap is refused and
-- counted rather than evicting a live player's totals; totals saturate at
-- MAX_VALUE instead of overflowing the presenter.
function M.credit(ledger, stats_id, topic, amount)
    if not _ledger_ok(ledger) then return false, "ledger" end
    if not M.valid_stats_id(stats_id) then
        ledger.rejected = (ledger.rejected or 0) + 1
        return false, "stats-id"
    end
    if not M.is_topic(topic) then
        ledger.rejected = (ledger.rejected or 0) + 1
        return false, "topic"
    end
    if not _finite(amount) or amount <= 0 or amount > M.MAX_EVENT then
        ledger.rejected = (ledger.rejected or 0) + 1
        return false, "amount"
    end
    local row = ledger.rows[stats_id]
    if not row then
        if ledger.count >= M.MAX_PLAYERS then
            ledger.overflow = (ledger.overflow or 0) + 1
            return false, "player-cap"
        end
        row = {}
        ledger.rows[stats_id] = row
        ledger.count = ledger.count + 1
    end
    local total = (row[topic] or 0) + amount
    if total > M.MAX_VALUE then total = M.MAX_VALUE end
    row[topic] = total
    return true, total
end

function M.forget(ledger, stats_id)
    if not _ledger_ok(ledger) or ledger.rows[stats_id] == nil then return false end
    ledger.rows[stats_id] = nil
    ledger.count = math.max(ledger.count - 1, 0)
    return true
end

-- Detached values for the scoreboard's selected rows. The host owns the whole
-- mission's authority, so a known player with no ledger row is a real zero.
function M.scores_for_players(ledger, players, limit)
    local result = {}
    if not _ledger_ok(ledger) or type(players) ~= "table" then return result end
    limit = math.min(math.max(math.floor(tonumber(limit) or M.SCORE_PLAYER_LIMIT), 0),
        M.SCORE_PLAYER_LIMIT)
    local visited = 0
    for _, player in ipairs(players) do
        if visited >= limit then break end
        local stats_id = type(player) == "table" and player.stats_id or nil
        if stats_id ~= nil then
            visited = visited + 1
            local key = tostring(stats_id)
            local row = ledger.rows[key]
            local values = {}
            for _, topic in ipairs(M.TOPICS) do
                local value = type(row) == "table" and row[topic.name] or 0
                values[topic.name] = _finite(value) and value or 0
            end
            result[key] = values
        end
    end
    return result
end

function M.copy_scores(scores)
    local copy, count = {}, 0
    for key, values in pairs(type(scores) == "table" and scores or {}) do
        if count >= M.SCORE_PLAYER_LIMIT then break end
        if type(key) == "string" and type(values) == "table" then
            local row = {}
            for _, topic in ipairs(M.TOPICS) do
                local value = rawget(values, topic.name)
                if _finite(value) and value >= 0 then row[topic.name] = value end
            end
            copy[key] = row
            count = count + 1
        end
    end
    return count > 0 and copy or nil
end

-- One register_damage call credits vanilla's clamped damage_dealt to at most
-- one attacker (statistics_util.lua:580-593). Compare the bounded observed
-- rows and accept exactly one positive delta; anything else is refused.
function M.plan_damage_credit(ids, before, after)
    if type(ids) ~= "table" or type(before) ~= "table" or type(after) ~= "table" then
        return nil, "observation"
    end
    local attacker, amount, changed = nil, nil, 0
    for i = 1, math.min(#ids, M.MAX_OBSERVED) do
        local old, new = before[i], after[i]
        if _finite(old) and _finite(new) and new ~= old then
            changed = changed + 1
            attacker, amount = ids[i], new - old
        end
    end
    if changed == 0 then return nil, "no-credit" end
    if changed > 1 then return nil, "ambiguous" end
    if not M.valid_stats_id(attacker) then return nil, "stats-id" end
    if not _finite(amount) or amount <= 0 or amount > M.MAX_EVENT then
        return nil, "amount"
    end
    return attacker, amount
end

-- facts: attacker_id, victim_owner_id (owner of the damaged unit, if any),
-- victim_is_player_unit, same_side, enemy_side. Self damage, including the
-- attacker's own non-hero units, and allied non-hero units stay uncredited.
function M.damage_kind(facts)
    if type(facts) ~= "table" or not M.valid_stats_id(facts.attacker_id) then
        return nil, "facts"
    end
    if facts.victim_owner_id ~= nil and facts.victim_owner_id == facts.attacker_id then
        return "self"
    end
    if facts.enemy_side == true then return "enemy" end
    if facts.victim_is_player_unit == true and facts.same_side == true
            and facts.victim_owner_id ~= nil then
        return "friendly_fire"
    end
    return nil, "unclassified-victim"
end

-- Vanilla kill classifier, statistics_util.lua:227-257, lifted verbatim onto
-- injected lookups: the item's slot type, overridden by any attack type
-- (light/heavy attacks are melee, every other attack type ranged), then the
-- weapon template's buff type. Non-item sources stay unclassified.
function M.classify_attack(item, attack_type, buff_kind_for_template)
    if type(item) ~= "table" then return nil end
    local slot_type = item.slot_type
    if attack_type then
        slot_type = (attack_type == "heavy_attack" or attack_type == "light_attack")
            and "melee" or "ranged"
    end
    if not slot_type then
        local template_name = item.template
        if template_name and type(buff_kind_for_template) == "function" then
            local ok, kind = pcall(buff_kind_for_template, template_name)
            if ok then slot_type = kind end
        end
    end
    if slot_type == "melee" or slot_type == "ranged" then return slot_type end
    return nil
end

function M.topic_for_attack(kind)
    if kind == "melee" then return M.MELEE end
    if kind == "ranged" then return M.RANGED end
    return nil
end

-- Permanent health is the server game-object field written by add_heal
-- (player_unit_health_extension.lua:856-872). Only a positive finite delta is
-- credited; the healer's player receives it, otherwise the healed player.
function M.plan_heal_credit(before, after, healer_id, healed_id)
    if not _finite(before) or not _finite(after) then return nil, "health" end
    local delta = after - before
    if delta <= 0 then return nil, "no-gain" end
    if delta > M.MAX_EVENT then return nil, "amount" end
    local target = M.valid_stats_id(healer_id) and healer_id
        or (M.valid_stats_id(healed_id) and healed_id or nil)
    if not target then return nil, "stats-id" end
    return target, delta
end

return M
