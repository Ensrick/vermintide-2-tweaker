-- _gt_prioritize_specials.lua (v0.2.100-dev)
-- ============================================================
-- Three independent, default-OFF, CLIENT-SIDE "prioritize specials" toggles.
-- Each biases a target picker toward `breed.special` enemies in the aim
-- direction. All are per-local-player decisions (no host install, no RPC, no
-- version-sync) -- they only change what YOUR tag/shot points at.
--
--   gt_prio_special_tag         -> ContextAwarePingExtension._check_raycast
--   gt_prio_special_deepwood    -> PlayerUnitSmartTargetingExtension.update_opt2
--                                  (Sister of Thorn "Deepwood Staff" = staff_life)
--   gt_prio_special_soulstealer -> ActionTrueFlightBowAim.client_owner_post_update
--                                  (Necromancer "Soulstealer Staff" = staff_death)
--
-- Source-verified 2026-06-18 against Vermintide-2-Source-Code. Every hook body
-- is pcall-guarded so a bad assumption degrades to vanilla, never a crash.
-- Single-hook pre-flight (CLAUDE.md): grep confirmed gt has 0 existing hooks on
-- _check_raycast / update_opt2 / client_owner_post_update before adding these.
-- ============================================================

local mod = get_mod("gt_dev")

local Unit = Unit
local Actor = Actor
local Quaternion = Quaternion
local Vector3 = Vector3
local ScriptUnit = ScriptUnit

-- Master gate (2026-06-30): "Prioritize Specials" is now a master toggle with three
-- context sub-toggles. A context applies only when BOTH the master (gt_prio_specials_enabled)
-- and that context's sub-toggle are on.
local function _prio_on(sub_id)
    return mod:get("gt_prio_specials_enabled") and mod:get(sub_id)
end

-- breed.special is the canonical flag (breed_skaven_gutter_runner.lua:45 etc.).
local function _is_special_enemy(self_unit, hit_unit)
    if not (hit_unit and rawget(_G, "HEALTH_ALIVE") and HEALTH_ALIVE[hit_unit]) then return false end
    local breed = Unit.get_data(hit_unit, "breed")
    if not (breed and breed.special) then return false end
    local side = Managers.state and Managers.state.side
    if side and side.is_enemy and self_unit then
        local ok, enemy = pcall(side.is_enemy, side, self_unit, hit_unit)
        if ok and not enemy then return false end
    end
    return true
end

-- Wielded weapon-template name of a player unit (e.g. "staff_life"/"staff_death").
-- Used to gate the two staff toggles so they're inert on every other weapon.
local function _wielded_template_name(player_unit)
    if not (player_unit and Unit.alive(player_unit)) then return nil end
    local inv = ScriptUnit.has_extension(player_unit, "inventory_system")
    if not inv then return nil end
    local ok, name = pcall(function()
        local slot = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
        local sd = slot and inv.get_slot_data and inv:get_slot_data(slot)
        local item = sd and sd.item_data
        return item and item.template
    end)
    return ok and name or nil
end

-- ============================================================
-- Toggle 1: Prioritize Specials when Tagging
-- ============================================================
-- _check_raycast (context_aware_ping_extension.lua:208) gathers ALL hits along
-- the crosshair ray (filter_ray_ping) and picks the most-centered one -- a pickup
-- or elite the ray passes through (utility=math.huge "direct hit") beats a special
-- further along the ray. We re-walk the SAME ray and, if any alive enemy SPECIAL
-- is on it, return the nearest such special instead -- so it tags the special even
-- when it's behind an elite/item. Runs only while a tag input is held, and only
-- when the toggle is on.
if rawget(_G, "ContextAwarePingExtension") then
    mod:hook("ContextAwarePingExtension", "_check_raycast", function(func, self, unit)
        local ping_unit, social_unit, ping_dist, social_dist, position = func(self, unit)
        if not _prio_on("gt_prio_special_tag") then
            return ping_unit, social_unit, ping_dist, social_dist, position
        end
        -- If the vanilla pick is already a special, keep it.
        local self_unit = self._unit or unit
        if ping_unit and _is_special_enemy(self_unit, ping_unit) then
            return ping_unit, social_unit, ping_dist, social_dist, position
        end
        local ok, best_unit, best_dist = pcall(function()
            local fpe = self._first_person_extension
            local pw = self._physics_world
            if not (fpe and pw and fpe.current_position) then return nil end
            local cam_pos = fpe:current_position()
            local cam_fwd = Quaternion.forward(fpe:current_rotation())
            local hits = pw:immediate_raycast(cam_pos, cam_fwd, 50, "all", "collision_filter", "filter_ray_ping")
            if not hits then return nil end
            local found, found_d
            for i = 1, #hits do
                local hit = hits[i]
                local actor = hit and hit[4]
                local hu = actor and Actor.unit(actor)
                if hu and ScriptUnit.has_extension(hu, "ping_system") and _is_special_enemy(self_unit, hu) then
                    local d = hit[2] or 0
                    if not found_d or d < found_d then found, found_d = hu, d end
                end
            end
            return found, found_d
        end)
        if ok and best_unit then
            return best_unit, social_unit, best_dist or ping_dist, social_dist, position
        end
        return ping_unit, social_unit, ping_dist, social_dist, position
    end)
end

-- ============================================================
-- Toggle 2: Prioritize Specials — Deepwood Staff (staff_life)
-- ============================================================
-- The Deepwood Staff seeking bolt is aim-assist smart-targeting (always_auto_aim),
-- NOT trueflight. update_opt2 (player_unit_smart_targeting_extension.lua:45) is
-- the active picker (OPTIMIZED_AIM_ASSIST=true) and writes the winner to
-- self.targeting_data.unit. It ranks by nearest-to-crosshair with NO special
-- preference. After it runs, if the toggle is on, the wielded weapon is staff_life,
-- and the current target isn't a special, we look for an alive enemy special in the
-- aim cone (broadphase) and, if one exists, redirect targeting_data to it. Smart
-- targeting already ignores pickups (enemy-only broadphase), so this also makes a
-- special win over a closer elite. hook_safe = post, fires once per frame.
if rawget(_G, "PlayerUnitSmartTargetingExtension") then
    mod:hook_safe("PlayerUnitSmartTargetingExtension", "update_opt2", function(self, unit, input, dt, context, t)
        if not _prio_on("gt_prio_special_deepwood") then return end
        local td = self.targeting_data
        if not td then return end
        if _wielded_template_name(unit) ~= "staff_life" then return end
        if td.unit and _is_special_enemy(unit, td.unit) then return end
        pcall(function()
            local fpe = self.first_person_extension or self._first_person_extension
            if not (fpe and fpe.current_position) then return end
            local own_pos = fpe:current_position()
            local look_dir = Quaternion.forward(fpe:current_rotation())
            local ai = Managers.state.entity and Managers.state.entity:system("ai_system")
            local bp = ai and ai.broadphase or (ai and ai:broadphase())
            if not bp then return end
            local results = {}
            local n = Broadphase.query(bp, own_pos, 50, results)
            local min_dot = math.cos(math.pi * 0.2) -- ~36deg cone, mirrors trueflight
            local best, best_dot
            for i = 1, n do
                local hu = results[i]
                if _is_special_enemy(unit, hu) then
                    local to = Vector3.normalize(Unit.local_position(hu, 0) - own_pos)
                    local d = Vector3.dot(look_dir, to)
                    if d >= min_dot and (not best_dot or d > best_dot) then
                        best, best_dot = hu, d
                    end
                end
            end
            if best then
                td.unit = best
                td.target_position = Unit.local_position(best, 0) + Vector3(0, 0, 1.0)
            end
        end)
    end)
end

-- ============================================================
-- Toggle 3: Prioritize Specials — Soulstealer Staff (staff_death)
-- ============================================================
-- The Soulstealer homing soul (action_two, kind=true_flight_bow_aim, 1 projectile)
-- locks via client_owner_post_update's single ray + prioritized_breeds table
-- (action_true_flight_bow_aim.lua:131/270). We overlay self.current_action's
-- prioritized_breeds with a metatable that returns a HIGH priority for any
-- breed.special (above the static 1s), for the duration of the call, then restore.
-- So any special on the aim ray outranks a closer non-special. GATED to staff_death
-- via the wielded weapon, because ActionCareerTrueFlightAim (Kerillian Waywatcher's
-- career arrows) INHERITS this same method -- we must not bias that.
local _SPECIAL_PRIO = 1000
if rawget(_G, "ActionTrueFlightBowAim") then
    mod:hook("ActionTrueFlightBowAim", "client_owner_post_update", function(func, self, dt, t, world, can_damage)
        if not _prio_on("gt_prio_special_soulstealer") then
            return func(self, dt, t, world, can_damage)
        end
        local owner = self.owner_unit
        if _wielded_template_name(owner) ~= "staff_death" then
            return func(self, dt, t, world, can_damage)
        end
        local action = self.current_action
        local base = action and action.prioritized_breeds
        if type(base) ~= "table" then
            return func(self, dt, t, world, can_damage)
        end
        -- Temporary special-biased view of prioritized_breeds: any Breeds[name]
        -- that is .special returns a high priority; everything else falls through
        -- to the static table.
        local Breeds = rawget(_G, "Breeds")
        local overlay = setmetatable({}, {
            __index = function(_, k)
                local b = Breeds and Breeds[k]
                if b and b.special then return _SPECIAL_PRIO end
                return base[k]
            end,
        })
        action.prioritized_breeds = overlay
        local r1, r2, r3 = func(self, dt, t, world, can_damage)
        action.prioritized_breeds = base
        return r1, r2, r3
    end)
end
