local mod = get_mod("gt_dev")

-- ============================================================================
-- Improved Bot Combat  (master toggle + issue #298 advanced controls)
-- ============================================================================
-- A from-scratch reimplementation of the non-conflicting combat improvements
-- from the "Bot Improvements - Combat Returns" Workshop mod (3560390486), folded
-- into ONE host-side toggle (default OFF). Reimplemented in gt's idiom -- not a
-- copy. Each feature reads game-mechanic state (threat values, positions, breed
-- flags) the same way the engine's own bot AI does and is heavily nil-guarded
-- (bot AI ticks every frame; a nil deref is a hard crash).
--
-- INCLUDED (don't conflict with gt's existing Bot Options):
--   * Smarter melee attack choice (+ the nil-guard that fixes the standalone
--     mod's `slot_data` crash when a bot's wielded slot is transient/empty --
--     e.g. a just-swapped AI-Takeover bot).
--   * Bots ping the attacking elite that's on them.
--   * Bots don't path after specials that are too far away.
--   * Bots ignore distant gunner line-of-fire (only take cover from close ones).
--   * Bots don't over-focus bosses (engage only when close / few other threats).
--   * Smarter active-ability (ult) timing for six careers.
--
-- DELIBERATELY EXCLUDED (conflict with gt, or no-op as a single toggle):
--   * Ironbreaker ult timing  -> gt's gt_bot_ironbreaker_revive_in_ult owns it.
--   * Better-revive (can_revive + behaviour-tree edit) -> overlaps gt's
--     revive-priority / rescue-awaiting / ironbreaker-revive logic.
--   * Heal-threshold dropdowns -> preference settings that are no-ops at their
--     defaults, and the other/zealot ones hook PlayerBotBase._select_ally_by_utility
--     which gt already owns.
--
-- NOTE: when this toggle is on, DISABLE the standalone "Bot Improvements -
-- Combat Returns" mod, or both will double-apply (they hook the same methods).
-- ============================================================================

local POSITION_LOOKUP = POSITION_LOOKUP
local BLACKBOARDS = BLACKBOARDS
local ALIVE = ALIVE
local HEALTH_ALIVE = HEALTH_ALIVE
local Unit = Unit
local Vector3 = Vector3
local ScriptUnit = ScriptUnit
local Managers = Managers
local policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_improved_bot_combat_policy")
mod._gt_ibc_policy = policy

local function _on()
    return mod:get("gt_improved_bot_combat")
end

local function _feature_on(setting_id)
    return policy.feature_enabled(_on(), mod:get(setting_id))
end

local function _distance_sq(setting_id, fallback)
    return policy.distance_sq(mod:get(setting_id), fallback)
end

-- Sum the threat value of alive enemies within `max_dist_sq` of `self_pos`,
-- weighting elites / enemies actually targeting the bot higher. Used by the
-- per-career ult heuristics. `bias` is a flat starting value (e.g. a low-stamina
-- nudge). Returns the accumulated threat.
local function _nearby_threat(blackboard, self_pos, max_dist_sq, weight_mult, bias)
    local total = bias or 0
    local enemies = blackboard.proximite_enemies
    if not (enemies and self_pos) then return total end
    local self_unit = blackboard.unit
    for i = 1, #enemies do
        local e = enemies[i]
        local ep = ALIVE[e] and POSITION_LOOKUP[e]
        if ep and Vector3.distance_squared(self_pos, ep) <= max_dist_sq then
            local ebb = BLACKBOARDS[e]
            local breed = ebb and ebb.breed
            if breed then
                local tv = breed.threat_value or 0
                local hot = breed.elite or (ebb.target_unit == self_unit)
                total = total + tv * (hot and (weight_mult or 1.25) or 1)
            end
        end
    end
    return total
end

local function _low_stamina(blackboard)
    local se = blackboard.status_extension
    return se and se.current_fatigue and se:current_fatigue() >= 90
end

-- ----------------------------------------------------------------------------
-- 1) Smarter melee attack choice  (+ the slot_data crash fix)
-- ----------------------------------------------------------------------------
-- Vanilla picks tap vs hold/heavy per weapon. The improvement: when the bot is
-- outnumbered or facing armour, prefer the wider / penetrating attack; otherwise
-- the faster single-target attack. The standalone mod read
-- `inventory:get_slot_data(wielded_slot):item_data` with no nil-check and fataled
-- when the wielded slot had no data (mid weapon-swap, utility slot, freshly
-- swapped AI-Takeover bot) -- we nil-guard and fall back to vanilla there.
mod:hook("BTBotMeleeAction", "_choose_attack", function(func, self, blackboard, target_unit)
    if not _feature_on("gt_ibc_smarter_attacks") then return func(self, blackboard, target_unit) end

    local item_template = blackboard.wielded_item_template
    local meta = item_template and item_template.attack_meta_data
    if not meta then
        -- No per-weapon attack metadata -> let vanilla decide (also the safe path
        -- when the wielded slot is transient/empty: the crash the standalone mod hit).
        return func(self, blackboard, target_unit)
    end

    local enemies = blackboard.proximite_enemies
    local outnumbered = enemies and #enemies > 1
    local breed = target_unit and Unit.get_data(target_unit, "breed")
    local armoured = breed and breed.armor_category == 2

    local best_input, best_meta, best_score
    for input, m in pairs(meta) do
        local score = 0
        -- Faster single-target attacks (non-wide) are good when not swarmed.
        if not outnumbered and m.arc ~= 1 then score = score + 1 end
        -- Penetrating/wide is needed against armour and crowds.
        if (not armoured) or m.penetrating then score = score + 8 end
        if not best_score or score > best_score then
            best_score, best_input, best_meta = score, input, m
        end
    end

    if best_input then return best_input, best_meta end
    return func(self, blackboard, target_unit)
end)

-- ----------------------------------------------------------------------------
-- 2) Bots ping the elite that's attacking them
-- ----------------------------------------------------------------------------
local _pinged_by_bot = {}  -- bot_unit -> { unit = elite_unit, t = time }
local PING_COOLDOWN = 2.0

-- Clear our record when the engine clears a ping, so the bot can re-ping later.
mod:hook_safe("PingTargetExtension", "set_pinged", function(self, pinged)
    if pinged then return end
    for _, rec in pairs(_pinged_by_bot) do
        if rec.unit == self._unit then rec.unit = nil end
    end
end)

-- Straight, static-geometry line-of-sight test from bot eye to enemy chest.
local function _los_clear(world, from_unit, to_unit)
    if not (world and Unit.alive(from_unit) and Unit.alive(to_unit)) then return false end
    local from = Unit.world_position(from_unit, 0)
    local to = Unit.world_position(to_unit, 0)
    from = Vector3(from.x, from.y, from.z + 1.5)
    to = Vector3(to.x, to.y, to.z + 1.4)
    local physics_world = World.get_data(world, "physics_world")
    if not physics_world then return false end
    local dir = to - from
    local dist = Vector3.length(dir)
    if dist <= 0 then return true end
    dir = Vector3.normalize(dir)
    PhysicsWorld.prepare_actors_for_raycast(physics_world, from, dir, 0.01, 10, dist * dist)
    local hits = PhysicsWorld.immediate_raycast(physics_world, from, dir, dist, "all", "collision_filter", "filter_player_ray_projectile")
    if not hits then return true end
    for i = 1, #hits do
        local actor = hits[i][4]
        local hit_unit = Actor.unit(actor)
        if hit_unit == to_unit then return true end
        if hit_unit ~= from_unit and Actor.is_static(actor) then return false end
    end
    return true
end

local function _try_ping_elite(blackboard)
    local self_unit = blackboard.unit
    if not self_unit then return end
    local rec = _pinged_by_bot[self_unit]
    if not rec then rec = {}; _pinged_by_bot[self_unit] = rec end

    -- Drop a stale record (our pinged elite died).
    if rec.unit then
        local he = ScriptUnit.has_extension(rec.unit, "health_system")
        if not he or he:current_health_percent() <= 0 then rec.unit = nil end
    end
    if rec.unit then return end  -- already tracking a live ping

    local now = Managers.time:time("main")
    if rec.t and (rec.t + PING_COOLDOWN) > now then return end

    local enemies = blackboard.proximite_enemies
    if not enemies then return end
    for i = 1, #enemies do
        local e = enemies[i]
        local ebb = ALIVE[e] and BLACKBOARDS[e]
        local breed = ebb and ebb.breed
        if breed and breed.elite and ebb.target_unit == self_unit then
            local he = ScriptUnit.has_extension(e, "health_system")
            local ping_ext = ScriptUnit.has_extension(e, "ping_system")
            if he and he:current_health_percent() > 0
               and (not ping_ext or not ping_ext:pinged())
               and _los_clear(blackboard.world, self_unit, e) then
                rec.unit = e
                rec.t = now
                local nm = Managers.state.network
                local sid = nm:unit_game_object_id(self_unit)
                local eid = nm:unit_game_object_id(e)
                nm.network_transmit:send_rpc_server("rpc_ping_unit", sid, eid, false, false, PingTypes.PING_ONLY, 1)
                return
            end
        end
    end
end

-- CONSOLIDATED hook on (BTBotMeleeAction, "run"). This is the ONLY gt_dev hook
-- on this pair (VMF drops a 2nd) -- it carries BOTH:
--   (a) the UNGATED nil-weapon crash guard (see _gt_bot_fixes.lua's BTBotMeleeAction.enter
--       hook): if the melee node entered a frame where the bot's wielded slot was
--       transient/empty (e.g. just given a weapon), blackboard.wielded_item_template
--       is nil and _update_melee would fatal dereferencing it (defense_meta_data:499,
--       actions:562, attack_meta_data/.actions/.name:584-600, _choose_attack:220).
--       Bail the node as "done","evaluate" so the BT re-selects next frame once the
--       slot is populated -- this MUST run regardless of the gt_improved_bot_combat
--       toggle, since the crash is toggle-independent.
--   (b) the gated "ping the attacking elite" feature.
mod:hook("BTBotMeleeAction", "run", function(func, self, unit, blackboard, t, dt)
    -- (a) Ungated crash guard: never let _update_melee deref a nil wielded weapon.
    if blackboard.wielded_item_template == nil then
        return "done", "evaluate"
    end

    local result, evaluate = func(self, unit, blackboard, t, dt)

    -- (b) Gated feature.
    if _feature_on("gt_ibc_ping_attackers") then mod:pcall(function() _try_ping_elite(blackboard) end) end

    return result, evaluate
end)
mod:hook_safe("BTBotShootAction", "run", function(self, unit, blackboard, t, dt)
    if _feature_on("gt_ibc_ping_attackers") then mod:pcall(function() _try_ping_elite(blackboard) end) end
end)

-- ----------------------------------------------------------------------------
-- 3) Don't chase specials that are too far away
-- ----------------------------------------------------------------------------
-- Cap the distance at which a bot will commit to pathing toward an enemy, so it
-- stops sprinting off after a far gutter runner / leech and abandoning the team.
mod:hook("PlayerBotBase", "_enemy_path_allowed", function(func, self, enemy_unit)
    if not _feature_on("gt_ibc_limit_special_chase") then return func(self, enemy_unit) end
    local ep = POSITION_LOOKUP[enemy_unit]
    local sp = POSITION_LOOKUP[self._unit]
    if ep and sp and Vector3.distance_squared(ep, sp)
            > _distance_sq("gt_ibc_special_chase_distance", math.sqrt(50)) then
        return false
    end
    return func(self, enemy_unit)
end)

-- ----------------------------------------------------------------------------
-- 4) Ignore distant gunner line-of-fire
-- ----------------------------------------------------------------------------
-- Vanilla makes bots scurry out of any ranged enemy's firing lane, which wastes
-- positioning. Only take cover from a shooter whose lane the bot is genuinely in
-- AND who is reasonably close. Maintains the engine's `taking_cover_from` set and
-- returns (in_line_of_fire, changed) like the original.
local LOF_WIDTH = 2.5
local LOF_WIDTH_STICKY = 6.0
local LOF_LENGTH = 40.0
local _lof_scratch = {}

local function _point_in_lane(from, to, p, width, length)
    if not (from and to and p) then return false end
    local dir = to - from
    local dlen = Vector3.length(dir)
    if dlen <= 0 then return false end
    dir = Vector3.normalize(dir)
    local diff = p - from
    local along = Vector3.dot(diff, dir)
    if along <= 0 or along > length then return false end
    local lateral = Vector3.length(diff - dir * along)
    return lateral <= math.min(along, width)
end

mod:hook("PlayerBotBase", "_in_line_of_fire", function(func, self, self_unit, self_pos, take_cover_targets, taking_cover_from)
    if not _feature_on("gt_ibc_ignore_distant_gunners") then
        return func(self, self_unit, self_pos, take_cover_targets, taking_cover_from)
    end

    local in_lof = false
    local changed = false
    table.clear(_lof_scratch)

    for attacker, victim in pairs(take_cover_targets) do
        local ap = POSITION_LOOKUP[attacker]
        local vp = POSITION_LOOKUP[victim]
        if ALIVE[victim] and ap and vp
           and Vector3.distance_squared(ap, vp)
                < _distance_sq("gt_ibc_gunner_cover_distance", math.sqrt(140)) then
            local already = taking_cover_from[attacker]
            local width = already and LOF_WIDTH_STICKY or LOF_WIDTH
            if victim == self_unit or _point_in_lane(ap, vp, self_pos, width, LOF_LENGTH) then
                _lof_scratch[attacker] = victim
                in_lof = true
                changed = changed or not already
            end
        end
    end

    -- Anyone we WERE taking cover from but no longer should -> changed.
    for attacker in pairs(taking_cover_from) do
        if not _lof_scratch[attacker] then changed = true; break end
    end

    table.clear(taking_cover_from)
    for attacker, victim in pairs(_lof_scratch) do
        taking_cover_from[attacker] = victim
    end
    table.clear(_lof_scratch)

    return in_lof, changed
end)

-- ----------------------------------------------------------------------------
-- 5) Don't over-focus bosses
-- ----------------------------------------------------------------------------
-- Bots normally treat monsters as top-priority urgent targets and tunnel them.
-- Keep urgent targeting as vanilla, but only ADD a boss as an urgent target when
-- the bot is close to it AND isn't busy with a crowd (or the boss is on the bot).
mod:hook("AIBotGroupSystem", "_update_urgent_targets", function(func, self, dt, t)
    if not _feature_on("gt_ibc_limit_boss_focus") then return func(self, dt, t) end

    local conflict = Managers.state.conflict
    local alive_bosses = conflict and conflict:alive_bosses()
    local urgent = self._urgent_targets
    local bot_ai_data = self._bot_ai_data
    if not (alive_bosses and urgent and bot_ai_data) then return func(self, dt, t) end

    for side_id = 1, #bot_ai_data do
        for bot_unit, data in pairs(bot_ai_data[side_id]) do
            local blackboard = data.blackboard
            local self_pos = POSITION_LOOKUP[bot_unit]
            local old_target = blackboard.urgent_target_enemy
            local best_target, best_utility, best_distance = nil, -math.huge, math.huge

            -- Non-boss urgent targets exactly as vanilla scores them.
            for target_unit, until_t in pairs(urgent) do
                if until_t <= t or not HEALTH_ALIVE[target_unit] then
                    urgent[target_unit] = nil
                else
                    local u, d = self:_calculate_opportunity_utility(bot_unit, blackboard, self_pos, old_target, target_unit, t, false, false)
                    if u > best_utility then best_utility, best_target, best_distance = u, target_unit, d end
                end
            end

            -- Only consider a boss when nothing else is urgent AND the boss is
            -- close, not invincible/defensive, and the bot isn't mid-crowd
            -- (unless the boss is targeting this bot).
            if not best_target and self_pos then
                for j = 1, #alive_bosses do
                    local boss = alive_bosses[j]
                    local bp = POSITION_LOOKUP[boss]
                    local bbb = BLACKBOARDS[boss]
                    local crowd = blackboard.proximite_enemies and #blackboard.proximite_enemies or 0
                    if bp and bbb and HEALTH_ALIVE[boss]
                       and not AiUtils.unit_invincible(boss)
                       and Vector3.distance_squared(bp, self_pos)
                            < _distance_sq("gt_ibc_boss_engage_distance", 15)
                       and not bbb.defensive_mode_duration
                       and (crowd < 2 or bbb.target_unit == bot_unit) then
                        local u, d = self:_calculate_opportunity_utility(bot_unit, blackboard, self_pos, old_target, boss, t, false, false)
                        if u > best_utility then best_utility, best_target, best_distance = u, boss, d end
                    end
                end
            end

            blackboard.revive_with_urgent_target = best_target and self:_can_revive_with_urgent_target(bot_unit, self_pos, blackboard, best_target, t)
            blackboard.urgent_target_enemy = best_target
            blackboard.urgent_target_distance = best_distance

            local hbp = blackboard.hit_by_projectile
            if hbp then
                for attacker in pairs(hbp) do
                    if not HEALTH_ALIVE[attacker] then hbp[attacker] = nil end
                end
            end
        end
    end
end)

-- ----------------------------------------------------------------------------
-- 6) Smarter active-ability (ult) timing  (6 careers; NOT Ironbreaker)
-- ----------------------------------------------------------------------------
-- Each career's bot can_activate gate gets a threat/opportunity heuristic so the
-- ult is spent when it actually helps. Ironbreaker is intentionally left to gt's
-- gt_bot_ironbreaker_revive_in_ult feature. All gated on the toggle; fall back to
-- vanilla when off. Hooked on the BTConditions.can_activate function table.
local function _ult_ready(blackboard)
    local ce = blackboard.career_extension
    local ab = ce and ce._abilities and ce._abilities[1]
    return ab and ab.is_ready
end

local function _prioritized_rescue(blackboard)
    local need = blackboard.target_ally_need_type
    if need ~= "knocked_down" and need ~= "hook" and need ~= "ledge" then return false end
    local group = Managers.state.entity:system("ai_bot_group_system")
    return group and group:is_prioritized_ally(blackboard.unit, blackboard.target_ally_unit)
end

if BTConditions and BTConditions.can_activate then
    local CA = BTConditions.can_activate

    -- Mercenary: pop sooner the more the nearby group is hurt; threshold scales
    -- down as allies drop, so the morale heal lands when it matters.
    if CA.es_mercenary then
        mod:hook(CA, "es_mercenary", function(func, blackboard)
            if not _feature_on("gt_ibc_ability_timing") then return func(blackboard) end
            local self_pos = POSITION_LOOKUP[blackboard.unit]
            local side = blackboard.side
            local units = side and side.PLAYER_AND_BOT_UNITS
            if not (self_pos and units) then return func(blackboard) end
            local hurt_factor = 0
            for i = 1, #units do
                local pu = units[i]
                local he = ScriptUnit.has_extension(pu, "health_system")
                local hp = he and he:current_health_percent() or 1
                hurt_factor = hurt_factor + (1 - hp)
            end
            local threshold = math.max(40 - hurt_factor * 25, 8)
            return _nearby_threat(blackboard, self_pos, 49, 1.25, _low_stamina(blackboard) and 15 or 0) >= threshold
        end)
    end

    -- Huntsman: pop for a high-threat target, when low on stamina, or to free a
    -- prioritized ally.
    if CA.es_huntsman then
        mod:hook(CA, "es_huntsman", function(func, blackboard)
            if not _feature_on("gt_ibc_ability_timing") then return func(blackboard) end
            if _prioritized_rescue(blackboard) then return true end
            if _low_stamina(blackboard) then return true end
            local tu = blackboard.target_unit
            local tbb = tu and BLACKBOARDS[tu]
            local tv = tbb and tbb.breed and tbb.breed.threat_value or 0
            return tv >= 8
        end)
    end

    -- Maidenguard: dash to a knocked/hooked prioritized ally or a threat target
    -- that's within dash range and reachable on the navmesh.
    if CA.we_maidenguard then
        mod:hook(CA, "we_maidenguard", function(func, blackboard)
            if not _feature_on("gt_ibc_ability_timing") then return func(blackboard) end
            local self_pos = POSITION_LOOKUP[blackboard.unit]
            if not self_pos then return func(blackboard) end
            local dash_target, dist_sq
            if _prioritized_rescue(blackboard) and blackboard.target_ally_unit then
                dash_target = blackboard.target_ally_unit
                dist_sq = (blackboard.ally_distance or 0) ^ 2
            else
                local tu = blackboard.target_unit
                local tbb = tu and BLACKBOARDS[tu]
                local tv = tbb and tbb.breed and tbb.breed.threat_value or 0
                if tu and (tv >= 8 or _low_stamina(blackboard)) then
                    local tp = POSITION_LOOKUP[tu]
                    if tp then dash_target, dist_sq = tu, Vector3.distance_squared(self_pos, tp) end
                end
            end
            if dash_target and dist_sq and dist_sq > 81 and dist_sq < 144 then
                local tp = POSITION_LOOKUP[dash_target]
                local dir = Vector3.normalize(tp - self_pos)
                local check = self_pos + dir * 14
                if blackboard.nav_world
                   and LocomotionUtils.ray_can_go_on_mesh(blackboard.nav_world, self_pos, check, nil, 1, 1) then
                    if blackboard.activate_ability_data and blackboard.activate_ability_data.aim_position then
                        blackboard.activate_ability_data.aim_position:store(tp)
                    end
                    return true
                end
            end
            return false
        end)
    end

    -- Shade: pop on a prioritized rescue, low stamina, or a heavy single target.
    if CA.we_shade then
        mod:hook(CA, "we_shade", function(func, blackboard)
            if not _feature_on("gt_ibc_ability_timing") then return func(blackboard) end
            if _prioritized_rescue(blackboard) then return true end
            if _low_stamina(blackboard) then return true end
            local tu = blackboard.target_unit
            local tbb = tu and BLACKBOARDS[tu]
            local tv = tbb and tbb.breed and tbb.breed.threat_value or 0
            return tv >= 12
        end)
    end

    -- Captain: pop when the close-range weighted threat is high.
    if CA.wh_captain then
        mod:hook(CA, "wh_captain", function(func, blackboard)
            if not _feature_on("gt_ibc_ability_timing") then return func(blackboard) end
            local self_pos = POSITION_LOOKUP[blackboard.unit]
            if not self_pos then return func(blackboard) end
            return _nearby_threat(blackboard, self_pos, 49, 1.25, _low_stamina(blackboard) and 15 or 0) >= 30
        end)
    end

    -- Unchained: vent on critical overcharge, or when surrounded by enemies that
    -- are on the bot (lower bar when the bot itself is near death).
    if CA.bw_unchained then
        mod:hook(CA, "bw_unchained", function(func, blackboard)
            if not _feature_on("gt_ibc_ability_timing") then return func(blackboard) end
            local oc = blackboard.overcharge_extension
            if oc and oc:is_above_critical_limit() then return true end
            local self_pos = POSITION_LOOKUP[blackboard.unit]
            if not self_pos then return func(blackboard) end
            local he = blackboard.health_extension
            local critical = he and he:current_health_percent() <= 0.2
            -- Only count enemies actually targeting the bot (weight 1, others 0).
            local total = 0
            local enemies = blackboard.proximite_enemies
            for i = 1, (enemies and #enemies or 0) do
                local e = enemies[i]
                local ep = ALIVE[e] and POSITION_LOOKUP[e]
                if ep and Vector3.distance_squared(self_pos, ep) <= 16 then
                    local ebb = BLACKBOARDS[e]
                    if ebb and ebb.target_unit == blackboard.unit and ebb.breed then
                        total = total + (ebb.breed.threat_value or 0)
                    end
                end
            end
            return total >= (critical and 10 or 35)
        end)
    end
end
