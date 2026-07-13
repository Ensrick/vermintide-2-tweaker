local mod = get_mod("gt_dev")

-- Focused per-frame consumable helpers. PlayerBotBase.update remains consolidated
-- in _gt_bot_fixes.lua; this module exports helpers and registers no hooks.
-- ----------------------------------------------------------------------------
-- FIX 6: Bots instantly grab their targeted/pinged pickup (no walking)
-- ----------------------------------------------------------------------------
-- WHAT
--   Bots normally walk to within 3.2m before looting (BTConditions.can_loot,
--   bt_bot_conditions.lua:877). Vanilla already has a failsafe: when an ordered
--   pickup has no navmesh path, player_bot_base.lua:1606-1633 sets
--   `forced_pickup_unit`, and can_loot then bypasses the distance gate because
--   `is_forced_pickup = forced_pickup_unit == interaction_unit` short-circuits
--   the `max_dist > dist` checks (bt_bot_conditions.lua:884-890).
-- FIX
--   Make that failsafe always-on for a bot's CURRENT pickup candidate: point
--   both `interaction_unit` and `forced_pickup_unit` at the live candidate
--   (mule/ordered first, then health, then ammo). is_forced_pickup then trips
--   and the bot loots from where it stands. We skip when the bot has an aid
--   target so we never stomp a revive interaction. EXPERIMENTAL -- verify
--   in-game. Host-side only.
local function _gt_instant_pickup_tick(self, unit, blackboard, t)
    if blackboard.target_ally_need_type then
        return
    end
    local mule_pickup = blackboard.mule_pickup
    if mod._gt_bot_pickup_is_reserved(mule_pickup) then
        if blackboard.interaction_unit == mule_pickup then
            blackboard.interaction_unit = nil
        end
        if blackboard.forced_pickup_unit == mule_pickup then
            blackboard.forced_pickup_unit = nil
        end
        mule_pickup = nil
    end
    local pickup = mule_pickup or blackboard.health_pickup or blackboard.ammo_pickup
    if not (pickup and Unit.alive(pickup)) then
        return
    end
    blackboard.interaction_unit = pickup
    blackboard.forced_pickup_unit = pickup
end

-- ----------------------------------------------------------------------------
-- REPLICANT BOTS PORT 2: Bots drink potions when in danger (configurable, #320)
-- ----------------------------------------------------------------------------
-- WHAT
--   Vanilla bots never drink their OWN potion -- player_bot_base.lua only ever
--   hands a potion to an ally or picks one up; there's no self-use behavior. So
--   a bot can sit on a Strength/Speed/Conc potion through a whole boss fight.
-- FIX (gt idiom; NOT a copy of Replicant's bt_bot_drink_pot_action BT node)
--   Throttled per-bot tick (mirrors the other _gt_*_tick fns). When a bot holds
--   a giveable/usable potion in slot_potion AND a configured "danger" is within
--   range, drive the drink the way BTBotHealAction does: wield slot_potion and
--   hold the use input until the potion is consumed (slot empties). One drink
--   per held potion (_gt_drinking latch cleared when the slot empties).
--
--   ADVANCED CONDITIONS (#320): the master toggle gt_bot_drink_potions_in_danger
--   now nests sub-widgets that decide WHAT counts as danger, all read LIVE each
--   scan inside _gt_danger_near (no on_setting_changed wiring):
--     * gt_bot_drink_range_m      -- scan radius in metres (was hard-coded 18)
--     * gt_bot_drink_on_boss      -- any breed.boss monster/lord in range
--     * gt_bot_drink_on_special   -- any breed.special (disabler/ranged) in range
--     * gt_bot_drink_on_patrol    -- >= gt_bot_drink_patrol_count elites in range
--     * gt_bot_drink_on_horde     -- >= gt_bot_drink_horde_count trash in range
--   Breed class is read live off each AI unit's Breed table (breed.boss /
--   breed.special / breed.elite; trash = none of those -- verified against
--   Vermintide-2-Source-Code/scripts/settings/breeds/*.lua 2026-07-04), not a
--   static name roster. Host-side only (bots are host-only). Default OFF.
local _GT_BOT_DANGER_RANGE = 18.0          -- meters; fallback danger scan radius
local _GT_BOT_PATROL_ELITE_THRESHOLD = 3   -- fallback: >= this many elites == "patrol"
local _GT_BOT_HORDE_TRASH_THRESHOLD = 8    -- fallback: >= this many trash == "horde"

-- True if any ENABLED danger condition is met within the configured range of
-- `self_pos`. Reads the live Breed table off each AI unit (breed.boss /
-- breed.special / breed.elite; trash = none of those) and the live menu
-- settings each call, so a condition change takes effect without a reload.
local function _gt_danger_near(unit, self_pos)
    if not self_pos then return false end
    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then return false end

    -- AI enemy units of this side (Side:enemy_units() -> the compact _enemy_units
    -- roster, swap-remove maintained so 1..#enemy_units has no holes).
    local enemy_units = side.enemy_units and side:enemy_units()
    if not enemy_units then return false end

    -- Advanced conditions (#320), live-read each scan.
    local on_boss    = mod:get("gt_bot_drink_on_boss")
    local on_special = mod:get("gt_bot_drink_on_special")
    local on_patrol  = mod:get("gt_bot_drink_on_patrol")
    local on_horde   = mod:get("gt_bot_drink_on_horde")

    -- Every trigger off -> the feature can never fire; bail before the scan.
    if not (on_boss or on_special or on_patrol or on_horde) then
        return false
    end

    local range = tonumber(mod:get("gt_bot_drink_range_m")) or _GT_BOT_DANGER_RANGE
    local range_sq = range * range
    -- Disabled cluster conditions use an unreachable threshold so their tallies
    -- never trip (math.huge is never <= a finite count).
    local patrol_threshold = on_patrol and (tonumber(mod:get("gt_bot_drink_patrol_count")) or _GT_BOT_PATROL_ELITE_THRESHOLD) or math.huge
    local horde_threshold  = on_horde  and (tonumber(mod:get("gt_bot_drink_horde_count"))  or _GT_BOT_HORDE_TRASH_THRESHOLD) or math.huge

    local elite_count, trash_count = 0, 0
    for i = 1, #enemy_units do
        local enemy = enemy_units[i]
        if ALIVE[enemy] then
            local ep = POSITION_LOOKUP[enemy]
            if ep and Vector3.distance_squared(self_pos, ep) <= range_sq then
                local breed = Unit.get_data(enemy, "breed")
                if breed then
                    -- Class priority: boss > special > elite > trash. A boss with
                    -- its trigger off simply does nothing (it is not "trash").
                    if breed.boss then
                        if on_boss then return true end       -- a monster/lord in range
                    elseif breed.special then
                        if on_special then return true end     -- a disabler/ranged special in range
                    elseif breed.elite then
                        elite_count = elite_count + 1
                        if elite_count >= patrol_threshold then
                            return true                        -- elite cluster -> patrol
                        end
                    else
                        trash_count = trash_count + 1
                        if trash_count >= horde_threshold then
                            return true                        -- trash cluster -> horde
                        end
                    end
                end
            end
        end
    end
    return false
end

local function _gt_drink_potion_tick(self, unit, blackboard, t)
    local inventory_extension = blackboard.inventory_extension
    if not inventory_extension then
        blackboard._gt_drinking = nil
        return
    end

    -- If we latched a drink, keep holding the use input until the potion slot
    -- empties (consumed), then release the latch. This survives the BT trying to
    -- re-wield a combat weapon for the few frames the drink takes.
    if blackboard._gt_drinking then
        local still_have = inventory_extension:get_slot_data("slot_potion")
        local input_ext = blackboard.input_extension
        if still_have and input_ext then
            input_ext:wield("slot_potion")
            input_ext:hold_attack()
            -- Safety timeout: never hold longer than ~1.5s.
            if t < (blackboard._gt_drinking_until or 0) then
                return
            end
        end
        blackboard._gt_drinking = nil
        blackboard._gt_drinking_until = nil
        return
    end

    -- Throttle the danger scan (once a second is plenty).
    local next_t = blackboard._gt_drink_scan_t or 0
    if t < next_t then
        return
    end
    blackboard._gt_drink_scan_t = t + 1.0

    -- Must actually hold a usable potion in slot_potion. can_give_other gates out
    -- the Necromancer skull and other non-potion slot_potion occupants.
    local potion = inventory_extension:get_slot_data("slot_potion")
    if not potion then return end
    local template = inventory_extension:get_item_template(potion)
    if not (template and template.can_give_other) then return end

    local self_pos = POSITION_LOOKUP[unit]
    if not _gt_danger_near(unit, self_pos) then return end

    -- Latch the drink for up to ~1.5s of held use input.
    blackboard._gt_drinking = true
    blackboard._gt_drinking_until = t + 1.5

    mod:debug("[gt:bot] bot drinking its potion (danger in range)")
end

mod._gt_instant_pickup_tick = _gt_instant_pickup_tick
mod._gt_drink_potion_tick = _gt_drink_potion_tick
