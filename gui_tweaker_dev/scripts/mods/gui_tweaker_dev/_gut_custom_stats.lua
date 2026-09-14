-- _gut_custom_stats.lua - host custom scoreboard statistics (#1570/#1571/#1572).
--
-- The Adventure host records three families into one bounded GUT ledger keyed
-- by stats_id: friendly-fire damage and melee/ranged damage from the exact
-- damage_dealt credit vanilla makes inside StatisticsUtil.register_damage, and
-- Permanent Health Restored from the server permanent-health write inside
-- PlayerUnitHealthExtension.add_heal. The ledger resets per StateIngame and
-- follows #437 retention. Non-host peers answer through the #1573 transport
-- child (`_gut_custom_stat_sync.lua`, loaded last below): a validated host
-- snapshot fills only acknowledged cells, and a mixed or no-GUT lobby keeps
-- the rows unavailable. No vanilla statistic, lookup, RPC or payload is added
-- or changed.
-- The entry point loads this after the #1414 presenter, #437 retention and
-- #1448 boss owners, so this StateIngame reset runs after the presenter's
-- end-screen capture. The module self-registers (presenter API, retention
-- listener, runtime checks) to keep the entry point within its size ceiling.
-- Owned by: gui_tweaker_dev.lua. Consumed via: mod:dofile from the entry point.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_custom_stats_policy")
local ScorePolicy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy")

local M = { rt_checks = {}, policy = Policy }
mod._GUT272_CUSTOM_STATS_MARKER = "gut-272-host-custom-ledger-v1"

local CREDIT_RECEIPT_CAP = 6
local credit_receipts = { friendly_fire = 0, attack = 0, heal = 0 }
local refusal_receipts, REFUSAL_RECEIPT_CAP = 0, 8
local active = false
local mission = 0
local ledger = Policy.new_ledger()
local runtime_reported = {}

local function _managers()
    return rawget(_G, "Managers")
end

local function _is_server()
    local managers = _managers()
    local player_manager = managers and managers.player
    return player_manager ~= nil and player_manager.is_server == true
end

local function _is_adventure()
    local managers = _managers()
    local mechanism = managers and managers.mechanism
    if not mechanism or type(mechanism.current_mechanism_name) ~= "function" then
        return false
    end
    local ok, name = pcall(mechanism.current_mechanism_name, mechanism)
    return ok and name == "adventure"
end

local function _recording()
    return active and _is_server() and _is_adventure()
end

local function _pack(...)
    return select("#", ...), { ... }
end

local function _stats_id(player)
    if type(player) ~= "table" or type(player.stats_id) ~= "function" then
        return nil
    end
    local ok, stats_id = pcall(player.stats_id, player)
    stats_id = ok and stats_id ~= nil and tostring(stats_id) or nil
    return Policy.valid_stats_id(stats_id) and stats_id or nil
end

local function _refused(family, reason)
    if refusal_receipts >= REFUSAL_RECEIPT_CAP then return end
    refusal_receipts = refusal_receipts + 1
    pcall(printf, "[gut:272] custom refusal evidence=%d/%d family=%s reason=%s mission=%d",
        refusal_receipts, REFUSAL_RECEIPT_CAP, tostring(family), tostring(reason), mission)
end

local function _credit(family, topic, stats_id, amount, other_id)
    local ok, result = Policy.credit(ledger, stats_id, topic, amount)
    if not ok then return _refused(family, result) end
    if credit_receipts[family] < CREDIT_RECEIPT_CAP then
        credit_receipts[family] = credit_receipts[family] + 1
        pcall(printf, "[gut:272] custom credit evidence=%d/%d family=%s topic=%s stats_id=%s other=%s amount=%.2f total=%.2f mission=%d",
            credit_receipts[family], CREDIT_RECEIPT_CAP, family, topic, stats_id,
            tostring(other_id), amount, result, mission)
    end
end

-- Observe the vanilla damage_dealt row of every registered player (humans and
-- bots, bounded) immediately before the wrapped call. Only the ids captured
-- here are re-read afterward, so iteration order cannot change the verdict.
local function _begin_damage_observation(statistics_db)
    if not _recording() or type(statistics_db) ~= "table" then return nil end
    local player_manager = _managers().player
    if type(player_manager.players) ~= "function" then return nil end
    local ok, players = pcall(player_manager.players, player_manager)
    if not ok or type(players) ~= "table" then return nil end
    local ids, before = {}, {}
    for _, player in pairs(players) do
        if #ids >= Policy.MAX_OBSERVED then break end
        local stats_id = _stats_id(player)
        if stats_id then
            local registered_ok, registered = pcall(statistics_db.is_registered,
                statistics_db, stats_id)
            if registered_ok and registered then
                local read_ok, value = pcall(statistics_db.get_stat, statistics_db,
                    stats_id, "damage_dealt")
                if read_ok and type(value) == "number" then
                    ids[#ids + 1] = stats_id
                    before[#before + 1] = value
                end
            end
        end
    end
    return #ids > 0 and { ids = ids, before = before } or nil
end

local function _call(owner, method, ...)
    local fn = type(owner) == "table" and owner[method] or nil
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, owner, ...)
    return ok and result or nil
end

local function _damage_facts(attacker_id, victim_unit)
    local managers = _managers()
    local player_manager = managers.player
    local attacker = _call(player_manager, "player_from_stats_id", attacker_id)
    local owner = _call(player_manager, "owner", victim_unit)
    local side_manager = managers.state and managers.state.side
    local victim_side = type(side_manager) == "table"
        and type(side_manager.side_by_unit) == "table"
        and side_manager.side_by_unit[victim_unit] or nil
    local attacker_side
    if attacker and type(attacker.unique_id) == "function" then
        local ok, unique_id = pcall(attacker.unique_id, attacker)
        if ok then
            attacker_side = _call(side_manager, "get_side_from_player_unique_id", unique_id)
        end
    end
    return {
        attacker_id = attacker_id,
        victim_owner_id = _stats_id(owner),
        victim_is_player_unit = _call(player_manager, "is_player_unit", victim_unit) == true,
        same_side = attacker_side ~= nil and attacker_side == victim_side,
        enemy_side = _call(side_manager, "is_enemy_by_side", attacker_side, victim_side) == true,
    }
end

local function _buff_kind_for_template(template_name)
    local weapon_utils = rawget(_G, "WeaponUtils")
    local template = weapon_utils and type(weapon_utils.get_weapon_template) == "function"
        and weapon_utils.get_weapon_template(template_name) or nil
    local buff_type = type(template) == "table" and template.buff_type or nil
    local melee_types = rawget(_G, "MeleeBuffTypes")
    local ranged_types = rawget(_G, "RangedBuffTypes")
    if buff_type ~= nil and type(melee_types) == "table" and melee_types[buff_type] then
        return "melee"
    end
    if buff_type ~= nil and type(ranged_types) == "table" and ranged_types[buff_type] then
        return "ranged"
    end
    return nil
end

local function _attack_kind(damage_data)
    local index = rawget(_G, "DamageDataIndex")
    local master = rawget(_G, "ItemMasterList")
    if type(index) ~= "table" or type(damage_data) ~= "table" or type(master) ~= "table" then
        return nil
    end
    local source = damage_data[index.DAMAGE_SOURCE_NAME]
    local item = type(source) == "string" and rawget(master, source) or nil
    return Policy.classify_attack(item, damage_data[index.ATTACK_TYPE],
        _buff_kind_for_template)
end

local function _finish_damage_observation(observation, victim_unit, damage_data,
        statistics_db)
    local after = {}
    for i, stats_id in ipairs(observation.ids) do
        local ok, value = pcall(statistics_db.get_stat, statistics_db, stats_id,
            "damage_dealt")
        after[i] = ok and value or nil
    end
    local attacker_id, amount = Policy.plan_damage_credit(observation.ids,
        observation.before, after)
    if not attacker_id then
        if amount == "ambiguous" then _refused("damage", amount) end
        return
    end
    local facts = _damage_facts(attacker_id, victim_unit)
    local kind = Policy.damage_kind(facts)
    if kind == "friendly_fire" then
        _credit("friendly_fire", Policy.FRIENDLY_FIRE, attacker_id, amount,
            facts.victim_owner_id)
    elseif kind == "enemy" then
        local topic = Policy.topic_for_attack(_attack_kind(damage_data))
        if topic then _credit("attack", topic, attacker_id, amount, nil) end
    end
end

-- Hook pre-flight: gui_tweaker_dev has no other hook on
-- StatisticsUtil.register_damage. Vanilla returns no values; every result is
-- still forwarded unchanged. Only GUT's own observation is pcall-contained.
mod:hook("StatisticsUtil", "register_damage", function(func, victim_unit, damage_data,
        statistics_db, ...)
    local observation
    if active then
        local ok, result = pcall(_begin_damage_observation, statistics_db)
        observation = ok and result or nil
    end
    local count, results = _pack(func(victim_unit, damage_data, statistics_db, ...))
    if observation then
        local ok, err = pcall(_finish_damage_observation, observation, victim_unit,
            damage_data, statistics_db)
        if not ok then _refused("damage", err) end
    end
    return unpack(results, 1, count)
end)

local function _permanent_health(extension)
    if not _recording() or type(extension) ~= "table" or extension.is_server ~= true then
        return nil
    end
    local session = rawget(_G, "GameSession")
    local game, object_id = extension.game, extension.health_game_object_id
    if type(session) ~= "table" or type(session.game_object_field) ~= "function"
            or not game or not object_id then
        return nil
    end
    local ok, value = pcall(session.game_object_field, game, object_id, "current_health")
    return ok and type(value) == "number" and value or nil
end

local function _finish_heal(extension, healer_unit, before)
    local after = _permanent_health(extension)
    if after == nil then return end
    local player_manager = _managers().player
    local healer = healer_unit ~= nil and _call(player_manager, "owner", healer_unit) or nil
    local healed_id = _stats_id(extension.player)
    local target, amount = Policy.plan_heal_credit(before, after, _stats_id(healer),
        healed_id)
    if target then
        _credit("heal", Policy.PERMANENT_HEALTH, target, amount, healed_id)
    elseif amount ~= "no-gain" then
        _refused("heal", amount)
    end
end

-- Hook pre-flight: gui_tweaker_dev has no other PlayerUnitHealthExtension hook.
-- add_heal writes permanent health only when is_server (source :856-872) and
-- returns no values; the before/after field reads bracket that write.
mod:hook("PlayerUnitHealthExtension", "add_heal", function(func, self, healer_unit,
        heal_amount, heal_source_name, heal_type, ...)
    local before
    if active then
        local ok, result = pcall(_permanent_health, self)
        before = ok and result or nil
    end
    local count, results = _pack(func(self, healer_unit, heal_amount, heal_source_name,
        heal_type, ...))
    if before ~= nil then
        local ok, err = pcall(_finish_heal, self, healer_unit, before)
        if not ok then _refused("heal", err) end
    end
    return unpack(results, 1, count)
end)

-- #437 retention decides whether a departed player's scoreboard survives a
-- rejoin. Mirror that decision so the custom rows never outlive the native
-- ones: drop a row the retention owner did not keep, evicted, or discarded.
function M.on_retention_event(event, stats_id, retained)
    if not active then return end
    if event == "unregister" and retained ~= true then
        Policy.forget(ledger, tostring(stats_id))
    elseif event == "evicted" then
        Policy.forget(ledger, tostring(stats_id))
    elseif event == "cleared" then
        local player_manager = _managers() and _managers().player
        local statistics_db = _call(player_manager, "statistics_db")
        if type(statistics_db) ~= "table" then return end
        for row_id in pairs(ledger.rows) do
            local ok, registered = pcall(statistics_db.is_registered, statistics_db, row_id)
            if not ok or not registered then Policy.forget(ledger, row_id) end
        end
    end
end

-- The recording host answers from its ledger. Every other peer answers only
-- from the #1573 child's accepted host snapshot (nil until one is valid), so
-- a client never fabricates a zero the host did not acknowledge.
function M.current_scores(players)
    if _recording() then
        return Policy.scores_for_players(ledger, players, Policy.SCORE_PLAYER_LIMIT)
    end
    local sync = rawget(mod, "_gut_custom_stat_sync")
    if type(sync) ~= "table" or type(sync.current_scores) ~= "function" then
        return nil
    end
    local ok, scores = pcall(sync.current_scores, players)
    return ok and type(scores) == "table" and scores or nil
end

local previous_state_changed = mod.on_game_state_changed
mod.on_game_state_changed = function(status, state_name, ...)
    if previous_state_changed then previous_state_changed(status, state_name, ...) end
    if state_name ~= "StateIngame" then return end
    if status == "enter" then
        mission = mission + 1
        ledger = Policy.new_ledger()
        active = true
    elseif status == "exit" then
        active = false
        ledger = Policy.new_ledger()
    end
end

local previous_disabled = mod.on_disabled
mod.on_disabled = function(...)
    if previous_disabled then previous_disabled(...) end
    active = false
    ledger = Policy.new_ledger()
end

local function _native_topics()
    local topics = {}
    for i = 1, 11 do
        topics[i] = {
            name = "native_" .. tostring(i),
            display_text = "native_label_" .. tostring(i),
            stat_type = "native_stat_" .. tostring(i),
        }
    end
    return topics
end

-- Execute the real presenter model with the custom registry and a detached
-- ledger row, then prove the non-host path (no custom scores) stays missing.
local function _model_cell(stats_id, topic_name, custom_scores)
    local topics = ScorePolicy.build_topic_registry(_native_topics(), Policy.TOPICS)
    local players = {
        [stats_id] = { name = "Tester", stats_id = stats_id, group_scores = {} },
    }
    local model = ScorePolicy.build_native_model(players, topics, {
        selected_page = 2,
        sort_topic = "player_name",
        custom_scores = custom_scores,
    })
    local row = model.players and model.players[1]
    return #topics, model.page_count, row and row.scores[topic_name], model.fingerprint
end

local function _verdict(name, report, fn)
    M.rt_checks[#M.rt_checks + 1] = {
        name = name,
        fn = function()
            if mod._GUT272_CUSTOM_STATS_MARKER ~= "gut-272-host-custom-ledger-v1" then
                return "custom statistics marker missing"
            end
            local failure, topic_count, fingerprint = fn()
            if failure then return failure end
            if not runtime_reported[name] then
                runtime_reported[name] = true
                report(topic_count or 0, tostring(fingerprint))
            end
        end,
    }
end

_verdict("issue1570_host_friendly_fire_statistic", function(topic_count, fingerprint)
    pcall(printf, "[gut:1570] runtime verdict=PASS topics=%d fp=%s", topic_count, fingerprint)
end, function()
    local attacker, amount = Policy.plan_damage_credit(
        { "peer-a:1", "peer-b:1" }, { 10, 20 }, { 10, 27.5 })
    if attacker ~= "peer-b:1" or amount ~= 7.5 then
        return "single damage_dealt delta was not attributed"
    end
    if Policy.plan_damage_credit({ "peer-a:1", "peer-b:1" }, { 1, 1 }, { 2, 2 }) then
        return "ambiguous damage_dealt deltas were credited"
    end
    local ally = Policy.damage_kind({
        attacker_id = attacker, victim_owner_id = "peer-a:1",
        victim_is_player_unit = true, same_side = true, enemy_side = false,
    })
    local own = Policy.damage_kind({
        attacker_id = attacker, victim_owner_id = attacker,
        victim_is_player_unit = true, same_side = true, enemy_side = false,
    })
    local foe = Policy.damage_kind({ attacker_id = attacker, enemy_side = true })
    if ally ~= "friendly_fire" or own ~= "self" or foe ~= "enemy" then
        return "friendly-fire victim classification failed"
    end
    local synthetic = Policy.new_ledger()
    Policy.credit(synthetic, attacker, Policy.FRIENDLY_FIRE, amount)
    local scores = Policy.scores_for_players(synthetic, { { stats_id = attacker } }, 4)
    local topic_count, pages, value, fingerprint = _model_cell(attacker,
        Policy.FRIENDLY_FIRE, scores)
    local _, _, missing = _model_cell(attacker, Policy.FRIENDLY_FIRE, nil)
    if topic_count ~= 17 or pages ~= 2 or value ~= 7.5 or missing ~= nil then
        return "friendly-fire model row failed"
    end
    return nil, topic_count, fingerprint
end)

_verdict("issue1571_host_melee_ranged_damage_statistic", function(topic_count, fingerprint)
    pcall(printf, "[gut:1571] runtime verdict=PASS topics=%d fp=%s", topic_count, fingerprint)
end, function()
    local item = { slot_type = "melee", template = "synthetic" }
    local function ranged_template() return "ranged" end
    if Policy.classify_attack(item, "light_attack") ~= "melee"
            or Policy.classify_attack(item, "heavy_attack") ~= "melee"
            or Policy.classify_attack(item, "n/a") ~= "ranged"
            or Policy.classify_attack(nil, "light_attack") ~= nil
            or Policy.classify_attack({ template = "synthetic" }, nil, ranged_template) ~= "ranged" then
        return "vanilla melee/ranged classifier drifted"
    end
    local synthetic = Policy.new_ledger()
    Policy.credit(synthetic, "peer-a:1", Policy.topic_for_attack("melee"), 12)
    Policy.credit(synthetic, "peer-a:1", Policy.topic_for_attack("ranged"), 5)
    local scores = Policy.scores_for_players(synthetic, { { stats_id = "peer-a:1" } }, 4)
    local topic_count, _, melee, fingerprint = _model_cell("peer-a:1", Policy.MELEE, scores)
    local _, _, ranged = _model_cell("peer-a:1", Policy.RANGED, scores)
    if melee ~= 12 or ranged ~= 5 then return "melee/ranged model rows failed" end
    return nil, topic_count, fingerprint
end)

_verdict("issue1572_host_permanent_health_statistic", function(topic_count, fingerprint)
    pcall(printf, "[gut:1572] runtime verdict=PASS topics=%d fp=%s", topic_count, fingerprint)
end, function()
    local healer, amount = Policy.plan_heal_credit(50, 70, "healer:1", "healed:1")
    local self_target = Policy.plan_heal_credit(50, 60, nil, "healed:1")
    if healer ~= "healer:1" or amount ~= 20 or self_target ~= "healed:1" then
        return "permanent-health attribution failed"
    end
    if Policy.plan_heal_credit(70, 70, "healer:1", "healed:1")
            or Policy.plan_heal_credit(70, 40, "healer:1", "healed:1") then
        return "non-positive permanent-health delta was credited"
    end
    local synthetic = Policy.new_ledger()
    Policy.credit(synthetic, healer, Policy.PERMANENT_HEALTH, amount)
    local scores = Policy.scores_for_players(synthetic, { { stats_id = healer } }, 4)
    local topic_count, _, value, fingerprint = _model_cell(healer,
        Policy.PERMANENT_HEALTH, scores)
    if value ~= 20 then return "permanent-health model row failed" end
    return nil, topic_count, fingerprint
end)

mod._gut_custom_stats = M
local retention = rawget(mod, "_gut_scoreboard_retention")
if type(retention) == "table" and type(retention.add_listener) == "function" then
    retention.add_listener(M.on_retention_event)
end
local register = rawget(mod, "_gut_rt_register")
if type(register) == "function" then
    for _, check in ipairs(M.rt_checks) do register(check.name, check.fn) end
end

-- #1573: the client transport is this ledger's child. It loads last so its
-- StateIngame clear runs after the presenter capture and this ledger reset,
-- and it self-registers its own runtime check. A load failure leaves the
-- host ledger intact and keeps non-host rows unavailable.
do
    local ok, err = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_custom_stat_sync")
    if not ok then
        printf("[gut:1573] custom statistics sync module failed: %s", tostring(err))
    end
end

return M
