-- _crt_foot_knight.lua — Foot Knight opt-in career mechanics (Issue 619).
--
-- Owns bounded local buff state, capability-aware weapon checks, the once-per-
-- mission Final March state, and the outgoing category-damage multiplier.  The
-- server updates every player/bot while clients update only their local owner;
-- custom buff names never enter NetworkLookup or a vanilla RPC payload.
--
-- Owned by: career_tweaker.lua. Consumed via: mod._crt.foot_knight.

local mod = get_mod("crt")
local policy = mod:dofile("scripts/mods/career_tweaker/_crt_foot_knight_policy")
local buff_perks = require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names")

local M = {}

local SETTING_UNINTERRUPTIBLE = "rework_es_knight_innate_uninterruptible_heavies"
local SETTING_AURA_RANGE = "rework_es_knight_protective_presence_10m_rock_20m"
local SETTING_ROCK_SHIELD = "rework_es_knight_rock_shield_offense"
local SETTING_TEAMWORK_GREAT = "rework_es_knight_teamwork_great_weapon_offense"
local SETTING_FINAL_MARCH = "rework_es_knight_final_march"
local SETTING_SECONDARY_MELEE = "rework_es_knight_secondary_melee"

local BUFF_UNINTERRUPTIBLE = "crt_fk_uninterruptible_heavies"
local BUFF_ROCK_DODGE = "crt_fk_rock_dodge_distance"
local BUFF_ROCK_POWER = "crt_fk_rock_shield_power"
local BUFF_TEAMWORK_DR_CANCEL = "crt_fk_teamwork_innate_dr_cancel"
local BUFF_TEAMWORK_POWER = "crt_fk_teamwork_great_power"
local BUFF_FINAL_MARCH = "crt_fk_final_march"

-- Resident vanilla Foot Knight atlas keys, sourced from
-- talent_settings_markus.lua. Icons live on the stable effect buffs (not the
-- 0.2s reconciler), so HUD widgets persist until the effect actually ends.
local BUFF_ICONS = {
    [BUFF_UNINTERRUPTIBLE] = "markus_knight_ability_invulnerability",
    [BUFF_ROCK_DODGE] = "markus_knight_passive_block_cost_aura",
    [BUFF_ROCK_POWER] = "markus_knight_passive_power_increase",
    [BUFF_TEAMWORK_POWER] = "markus_knight_passive_power_increase",
    [BUFF_FINAL_MARCH] = "markus_knight_movement_speed_on_incapacitated_allies",
}

local _states = setmetatable({}, { __mode = "k" })
local _owned_live_ranges = setmetatable({}, { __mode = "k" })
local _tick_accumulator = 0
local _original_teamwork_range
local _owned_secondary_slot_types = setmetatable({}, { __mode = "k" })
local _last_secondary_slot_diagnostic

local function _register_local_template(name, body)
    if not BuffTemplates or rawget(BuffTemplates, name) ~= nil then return end
    BuffTemplates[name] = body
end

local function _register_templates()
    _register_local_template(BUFF_UNINTERRUPTIBLE, {
        buffs = {
            {
                name = BUFF_UNINTERRUPTIBLE,
                icon = BUFF_ICONS[BUFF_UNINTERRUPTIBLE],
                perks = { buff_perks.uninterruptible_heavy },
            },
        },
        _crt_local_only = true,
    })
    _register_local_template(BUFF_ROCK_POWER, {
        buffs = {
            {
                name = BUFF_ROCK_POWER,
                icon = BUFF_ICONS[BUFF_ROCK_POWER],
                stat_buff = "power_level",
                multiplier = 0.15,
                max_stacks = 1,
            },
        },
        _crt_local_only = true,
    })
    _register_local_template(BUFF_ROCK_DODGE, {
        buffs = {
            {
                name = BUFF_ROCK_DODGE,
                icon = BUFF_ICONS[BUFF_ROCK_DODGE],
                apply_buff_func = "apply_movement_buff",
                remove_buff_func = "remove_movement_buff",
                multiplier = 0.90,
                path_to_movement_setting_to_modify = {
                    "dodging",
                    "distance_modifier",
                },
            },
        },
        _crt_local_only = true,
    })
    _register_local_template(BUFF_TEAMWORK_DR_CANCEL, {
        buffs = {
            {
                name = BUFF_TEAMWORK_DR_CANCEL,
                stat_buff = "damage_taken",
                -- Foot Knight's native passive is -0.10 in the sourced live
                -- template. An equal opposite stat contribution removes only
                -- that innate bucket while preserving aura/talent/Final March.
                multiplier = 0.10,
                max_stacks = 1,
            },
        },
        _crt_local_only = true,
    })
    _register_local_template(BUFF_TEAMWORK_POWER, {
        buffs = {
            {
                name = BUFF_TEAMWORK_POWER,
                icon = BUFF_ICONS[BUFF_TEAMWORK_POWER],
                stat_buff = "power_level",
                multiplier = 0.05,
                max_stacks = 3,
            },
        },
        _crt_local_only = true,
    })
    _register_local_template(BUFF_FINAL_MARCH, {
        buffs = {
            {
                name = BUFF_FINAL_MARCH .. "_power",
                icon = BUFF_ICONS[BUFF_FINAL_MARCH],
                stat_buff = "power_level",
                multiplier = 0.50,
                duration = 60,
            },
            {
                name = BUFF_FINAL_MARCH .. "_dr",
                stat_buff = "damage_taken",
                multiplier = -0.50,
                duration = 60,
            },
        },
        _crt_local_only = true,
    })
end

local function _is_foot_knight(player)
    if not player or type(player.career_name) ~= "function" then return false end
    local ok, career_name = pcall(player.career_name, player)
    return ok and career_name == "es_knight"
end

local function _has_talent(unit, talent_name)
    local extension = unit and ScriptUnit.has_extension(unit, "talent_system")
    return extension and extension.has_talent and extension:has_talent(talent_name) == true
end

local function _wielded_template(unit)
    local inventory = unit and ScriptUnit.has_extension(unit, "inventory_system")
    if not inventory or not inventory.get_wielded_slot_item_template then return nil end
    local ok, template = pcall(inventory.get_wielded_slot_item_template, inventory)
    return ok and template or nil
end

local function _weapon_template_from_damage_source(unit, damage_source)
    local item = ItemMasterList and rawget(ItemMasterList, damage_source)
    local template_name = item and item.template
    if template_name and WeaponUtils and WeaponUtils.get_weapon_template then
        local ok, template = pcall(WeaponUtils.get_weapon_template, template_name)
        if ok and template then return template end
    end
    return _wielded_template(unit)
end

local function _is_melee_template(template)
    return template and MeleeBuffTypes and MeleeBuffTypes[template.buff_type] == true
end

local function _nearby_ally_count(unit, range)
    local side_manager = Managers.state and Managers.state.side
    local side = side_manager and side_manager.side_by_unit and side_manager.side_by_unit[unit]
    local units = side and side.PLAYER_AND_BOT_UNITS
    local origin = POSITION_LOOKUP and POSITION_LOOKUP[unit]
    if not units or not origin then return 0 end

    local count = 0
    local range_squared = range * range
    for i = 1, #units do
        local ally = units[i]
        local position = ally ~= unit and Unit.alive(ally) and POSITION_LOOKUP[ally]
        if position and Vector3.distance_squared(origin, position) < range_squared then
            count = count + 1
            if count == 3 then break end
        end
    end
    return count
end

local function _set_single_buff(buff_extension, state, field, enabled, buff_name)
    local id = state[field]
    if enabled and not id then
        state[field] = buff_extension:add_buff(buff_name, { attacker_unit = state.unit })
    elseif not enabled and id then
        pcall(buff_extension.remove_buff, buff_extension, id)
        state[field] = nil
    end
end

local function _set_teamwork_stacks(buff_extension, state, wanted)
    local ids = state.teamwork_ids
    while #ids > wanted do
        local id = table.remove(ids)
        pcall(buff_extension.remove_buff, buff_extension, id)
    end
    while #ids < wanted do
        local id = buff_extension:add_buff(BUFF_TEAMWORK_POWER, { attacker_unit = state.unit })
        if not id then break end
        ids[#ids + 1] = id
    end
end

local function _set_live_range(buff_extension, buff_name, enabled, desired, baseline)
    local buff = buff_extension:get_buff_type(buff_name)
    if not buff then return end
    local owned = _owned_live_ranges[buff]
    if enabled then
        if not owned then
            owned = { baseline = baseline }
            _owned_live_ranges[buff] = owned
        end
        buff.range = desired
    elseif owned then
        buff.range = owned.baseline
        _owned_live_ranges[buff] = nil
    end
end

local function _restore_all_live_ranges()
    for buff, owned in pairs(_owned_live_ranges) do
        if type(buff) == "table" and type(owned) == "table" then
            buff.range = owned.baseline
        end
    end
    _owned_live_ranges = setmetatable({}, { __mode = "k" })
end

local function _player_is_owned_here(player)
    if Managers.player and Managers.player.is_server then return true end
    return player and player.local_player == true
end

local function _in_mission()
    local transition = Managers.level_transition_handler
    if transition and transition.in_hub_level then
        local ok, in_hub = pcall(transition.in_hub_level, transition)
        if ok then return not in_hub end
    end
    return false
end

local function _all_other_allies_dead(player, unit, state)
    local manager = Managers.player
    local players = manager and manager.human_and_bot_players and manager:human_and_bot_players()
    local side_manager = Managers.state and Managers.state.side
    local owner_side = side_manager and side_manager.side_by_unit and side_manager.side_by_unit[unit]
    if not players or not owner_side then return false end

    local current = {}
    local dead_flags = {}
    for _, other in pairs(players) do
        if other ~= player then
            local other_unit = other.player_unit
            local other_side = other_unit and side_manager.side_by_unit[other_unit]
            if other_side == owner_side or state.allies[other] then
                state.allies[other] = true
                current[other] = true
                local is_dead = true
                if other_unit and Unit.alive(other_unit) then
                    local status = ScriptUnit.has_extension(other_unit, "status_system")
                    is_dead = status ~= nil and status:is_dead() == true
                end
                dead_flags[#dead_flags + 1] = is_dead
            end
        end
    end
    for known in pairs(state.allies) do
        if not current[known] then state.allies[known] = nil end
    end
    return policy.all_other_allies_dead(dead_flags)
end

local function _knock_back_disabler(unit)
    if not (Managers.player and Managers.player.is_server) then return end
    local status = ScriptUnit.has_extension(unit, "status_system")
    local disabler = status and status.get_disabler_unit and status:get_disabler_unit()
    if not (disabler and Unit.alive(disabler)) then return end

    local blackboard = BLACKBOARDS and BLACKBOARDS[disabler]
    local from = POSITION_LOOKUP and POSITION_LOOKUP[unit]
    local to = POSITION_LOOKUP and POSITION_LOOKUP[disabler]
    if not (blackboard and from and to and AiUtils and AiUtils.stagger) then return end

    local direction = Vector3.normalize(to - from)
    local t = Managers.time:time("game")
    AiUtils.stagger(disabler, blackboard, unit, direction, 4, stagger_types.heavy,
        1, nil, t, 1, true, true)
end

local function _update_player(player)
    local unit = player and player.player_unit
    if not (_player_is_owned_here(player) and _is_foot_knight(player)
            and unit and Unit.alive(unit)) then return end

    local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
    local status = ScriptUnit.has_extension(unit, "status_system")
    if not buff_extension or not status or status:is_dead() then return end

    local state = _states[unit]
    if not state then
        state = { unit = unit, teamwork_ids = {}, allies = setmetatable({}, { __mode = "k" }) }
        _states[unit] = state
    end

    local template = _wielded_template(unit)
    local weapon_type = template and template.weapon_type
    local shield_active = mod:get(SETTING_ROCK_SHIELD)
        and _has_talent(unit, "markus_knight_passive_block_cost_aura")
        and _is_melee_template(template) and policy.is_shield_type(weapon_type, template.name)
    local great_active = mod:get(SETTING_TEAMWORK_GREAT)
        and _has_talent(unit, "markus_knight_damage_taken_ally_proximity")
        and _is_melee_template(template) and policy.is_non_polearm_great_type(weapon_type, template.name)
    local ally_count = great_active and _nearby_ally_count(unit, 10) or 0
    local aura_enabled = mod:get(SETTING_AURA_RANGE) == true
    local teamwork_enabled = mod:get(SETTING_TEAMWORK_GREAT) == true

    -- Template patches govern future spawns. These live-instance writes make
    -- in-mission setting changes immediate without rebuilding talent buffs.
    _set_live_range(buff_extension, "markus_knight_passive",
        aura_enabled, 10, 5)
    _set_live_range(buff_extension, "markus_knight_passive_block_cost_aura",
        aura_enabled, 20, 10)
    _set_live_range(buff_extension, "markus_knight_passive_range",
        aura_enabled, 20, 10)
    _set_live_range(buff_extension, "markus_knight_damage_taken_ally_proximity",
        teamwork_enabled, 10, _original_teamwork_range or 5)

    _set_single_buff(buff_extension, state, "uninterruptible_id",
        mod:get(SETTING_UNINTERRUPTIBLE) == true, BUFF_UNINTERRUPTIBLE)
    _set_single_buff(buff_extension, state, "rock_dodge_id",
        mod:get(SETTING_ROCK_SHIELD) == true, BUFF_ROCK_DODGE)
    _set_single_buff(buff_extension, state, "rock_power_id", shield_active, BUFF_ROCK_POWER)
    _set_single_buff(buff_extension, state, "teamwork_dr_cancel_id",
        teamwork_enabled
            and buff_extension:has_buff_type("markus_knight_passive_damage_reduction") == true,
        BUFF_TEAMWORK_DR_CANCEL)
    _set_teamwork_stacks(buff_extension, state, ally_count)
    state.nearby_allies = ally_count

    if mod:get(SETTING_FINAL_MARCH) and not state.final_march_triggered
        and _in_mission() and _all_other_allies_dead(player, unit, state) then
        state.final_march_triggered = true
        state.final_march_id = buff_extension:add_buff(BUFF_FINAL_MARCH, { attacker_unit = unit })
        _knock_back_disabler(unit)
        pcall(printf, "[crt:619] Final March triggered owner=%s duration=60 power=50%% dr=50%%",
            tostring(player))
    end
end

function M.tick(dt)
    _tick_accumulator = _tick_accumulator + (dt or 0)
    if _tick_accumulator < 0.20 then return end
    _tick_accumulator = 0

    local manager = Managers.player
    local players = manager and manager.human_and_bot_players and manager:human_and_bot_players()
    if not players then return end
    for _, player in pairs(players) do
        _update_player(player)
    end
end

local function _secondary_slot_carriers()
    local carriers = {}
    local seen = {}
    local function add(career, label)
        local slot_map = career and career.item_slot_types_by_slot_name
        local slot_types = slot_map and slot_map.slot_ranged
        if type(slot_types) == "table" and not seen[slot_types] then
            seen[slot_types] = true
            carriers[#carriers + 1] = { slot_types = slot_types, label = label }
        end
    end

    -- Backend verification reads CareerSettings, while the hero inventory
    -- builds its cached filter from SPProfiles. They alias in stock data, but
    -- DLC reloads and other mods can replace either carrier independently.
    add(CareerSettings and CareerSettings.es_knight, "CareerSettings.es_knight")
    for profile_index, profile in pairs(SPProfiles or {}) do
        for career_index, career in ipairs(profile.careers or {}) do
            if career.name == "es_knight" then
                add(career, string.format("SPProfiles[%s].careers[%s]",
                    tostring(profile_index), tostring(career_index)))
            end
        end
    end
    return carriers, seen
end

local function _write_slot_plan(slot_types, planned)
    for i = #slot_types, 1, -1 do slot_types[i] = nil end
    for i = 1, #planned do slot_types[i] = planned[i] end
end

local function _reconcile_secondary_slots(enabled)
    local carriers, current = _secondary_slot_carriers()

    -- If a carrier array was replaced, abandon the detached member exactly as
    -- the former single-carrier implementation did. Never delete another
    -- owner's `melee` member from a replacement array.
    for slot_types in pairs(_owned_secondary_slot_types) do
        if not current[slot_types] then _owned_secondary_slot_types[slot_types] = nil end
    end

    local diagnostic_parts = {}
    for i = 1, #carriers do
        local carrier = carriers[i]
        local slot_types = carrier.slot_types
        local planned, owns = policy.plan_secondary_slot(
            slot_types, enabled, _owned_secondary_slot_types[slot_types] == true)
        _write_slot_plan(slot_types, planned)
        _owned_secondary_slot_types[slot_types] = owns or nil
        diagnostic_parts[#diagnostic_parts + 1] = carrier.label .. "={"
            .. table.concat(slot_types, ",") .. "}"
    end

    local diagnostic = string.format("enabled=%s carriers=%d %s",
        tostring(enabled), #carriers, table.concat(diagnostic_parts, " "))
    if diagnostic ~= _last_secondary_slot_diagnostic then
        _last_secondary_slot_diagnostic = diagnostic
        pcall(printf, "[crt:619] secondary-slot %s", diagnostic)
    end
end

function M.apply_settings()
    local template = BuffTemplates and rawget(BuffTemplates, "markus_knight_damage_taken_ally_proximity")
    local driver = template and template.buffs and template.buffs[1]
    if driver then
        if _original_teamwork_range == nil then _original_teamwork_range = driver.range end
        driver.range = mod:get(SETTING_TEAMWORK_GREAT) and 10 or _original_teamwork_range
    end

    _reconcile_secondary_slots(mod:get(SETTING_SECONDARY_MELEE) == true)
end

function M.restore()
    _restore_all_live_ranges()
    if _original_teamwork_range ~= nil and BuffTemplates then
        local template = rawget(BuffTemplates, "markus_knight_damage_taken_ally_proximity")
        local driver = template and template.buffs and template.buffs[1]
        if driver then driver.range = _original_teamwork_range end
    end
    _reconcile_secondary_slots(false)
    _owned_secondary_slot_types = setmetatable({}, { __mode = "k" })
    for unit, state in pairs(_states) do
        local buff_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "buff_system")
        if buff_extension then
            _set_single_buff(buff_extension, state, "uninterruptible_id", false, BUFF_UNINTERRUPTIBLE)
            _set_single_buff(buff_extension, state, "rock_dodge_id", false, BUFF_ROCK_DODGE)
            _set_single_buff(buff_extension, state, "rock_power_id", false, BUFF_ROCK_POWER)
            _set_single_buff(buff_extension, state, "teamwork_dr_cancel_id", false, BUFF_TEAMWORK_DR_CANCEL)
            _set_teamwork_stacks(buff_extension, state, 0)
            if state.final_march_id then
                pcall(buff_extension.remove_buff, buff_extension, state.final_march_id)
                state.final_march_id = nil
            end
        end
    end
    _states = setmetatable({}, { __mode = "k" })
end

function M.reset_mission_state()
    -- StateIngame can be entered again with a still-live unit. Remove every
    -- buff we own before forgetting its id so the following tick cannot stack
    -- a duplicate. This also resets Final March's once-per-mission latch.
    _restore_all_live_ranges()
    for unit, state in pairs(_states) do
        local buff_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "buff_system")
        if buff_extension then
            _set_single_buff(buff_extension, state, "uninterruptible_id", false, BUFF_UNINTERRUPTIBLE)
            _set_single_buff(buff_extension, state, "rock_dodge_id", false, BUFF_ROCK_DODGE)
            _set_single_buff(buff_extension, state, "rock_power_id", false, BUFF_ROCK_POWER)
            _set_single_buff(buff_extension, state, "teamwork_dr_cancel_id", false, BUFF_TEAMWORK_DR_CANCEL)
            _set_teamwork_stacks(buff_extension, state, 0)
            if state.final_march_id then
                pcall(buff_extension.remove_buff, buff_extension, state.final_march_id)
            end
        end
    end
    _states = setmetatable({}, { __mode = "k" })
    _tick_accumulator = 0
end

function M.outgoing_damage_multiplier(attacker_unit, attacker_player, attacked_unit, damage_source)
    if not (_is_foot_knight(attacker_player) and attacker_unit and attacked_unit) then return 1 end
    local template = _weapon_template_from_damage_source(attacker_unit, damage_source)
    if not _is_melee_template(template) then return 1 end

    local weapon_type = template.weapon_type
    local rock_active = mod:get(SETTING_ROCK_SHIELD)
        and _has_talent(attacker_unit, "markus_knight_passive_block_cost_aura")
        and policy.is_shield_type(weapon_type, template.name)
    local teamwork_active = mod:get(SETTING_TEAMWORK_GREAT)
        and _has_talent(attacker_unit, "markus_knight_damage_taken_ally_proximity")
        and policy.is_non_polearm_great_type(weapon_type, template.name)
    local state = _states[attacker_unit]
    local nearby_allies = teamwork_active and state and state.nearby_allies or 0
    local breed = Unit.alive(attacked_unit) and Unit.get_data(attacked_unit, "breed") or nil
    return policy.enemy_multiplier(rock_active, teamwork_active, nearby_allies, breed)
end

M.policy = policy
M.buff_icons = BUFF_ICONS
M.setting_ids = {
    SETTING_UNINTERRUPTIBLE,
    SETTING_AURA_RANGE,
    SETTING_ROCK_SHIELD,
    SETTING_TEAMWORK_GREAT,
    SETTING_FINAL_MARCH,
    SETTING_SECONDARY_MELEE,
}

_register_templates()
M.apply_settings()

-- The inventory caches its OR-filter when categories are created. Reconcile
-- the exact SPProfiles carrier immediately before every menu build so a reopen
-- after a hot toggle cannot retain a ranged-only or melee-only stale filter.
if HeroWindowLoadoutInventory and HeroWindowLoadoutInventory._create_item_categories then
    mod:hook(HeroWindowLoadoutInventory, "_create_item_categories",
        function(func, self, ...)
            _reconcile_secondary_slots(mod:get(SETTING_SECONDARY_MELEE) == true)
            return func(self, ...)
        end)
end

return M
