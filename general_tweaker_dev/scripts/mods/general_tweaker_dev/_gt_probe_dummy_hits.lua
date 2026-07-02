local mod = get_mod("gt_dev")

-- ============================================================================
-- Issue #198 probe -- "Training Dummy Gets Hit Many Times by Same Attack"
-- ============================================================================
-- PASSIVE, DEFAULT-ON diagnostic. No gameplay change, no setting gate. Writes
-- via engine `printf` so it is visible with mod-logging OFF (the user plays
-- with VMF logging off and hands over the log afterward).
--
-- WHAT IT WATCHES
--   Every damage event applied to a keep training dummy funnels through
--   TrainingDummyHealthExtension.add_damage (vanilla
--   scripts/unit_extensions/generic/training_dummy_health_extension.lua:56).
--   That function is ALSO where the dummy's floating damage number is drawn
--   (DamageUtils.add_unit_floating_damage_numbers, :70), so one call == one
--   number the user sees stacked in the report screenshot. Hooking it observes
--   exactly the reported symptom: how many separate damage events one melee
--   swing produces on the single dummy unit.
--
-- HOW IT AGGREGATES
--   A melee swing can fire add_damage several times within a few frames. We
--   bucket events per (dummy unit, attacker, damage_source) and flush one
--   summary line per swing once no further hit for that bucket arrives within a
--   short window (_WINDOW seconds). One swing => one [198:dummy] line carrying
--   the hit count, the distinct hit zones, and the summed damage.
--
-- READ THE LOG
--   Grep `[198:dummy]`. A line with hits_this_swing > 1 is a single swing that
--   landed multiple times on the one dummy -- the bug. `zones=` shows whether
--   the repeats hit the same hit zone (a re-application bug) or different actors
--   (a sweep across multiple dummy hitboxes). `attacker=`/`attack=` name the
--   culprit weapon/career.
--
-- gt_dev does NOT hook TrainingDummyHealthExtension anywhere else (grep
-- confirmed), so this is a fresh singleton hook -- no VMF duplicate-hook drop.
-- The hook is hook_safe (observe only): it never reads or alters the damage.

local TAG = "[198:dummy]"
local _WINDOW = 0.2   -- seconds; hits within this of the last count as one swing

-- bucket key -> { count, dmg, first_t, last_t, career, source, zones = {set}, crit }
local _buckets = {}

local function _career_of(attacker_unit)
    if not attacker_unit then return "n/a" end
    local ce = ScriptUnit.has_extension(attacker_unit, "career_system")
    if ce and ce.career_name then
        local ok, name = pcall(ce.career_name, ce)
        if ok and name then return name end
    end
    return "non-career"
end

local function _now()
    local tm = Managers.time
    if tm and tm:has_timer("game") then return tm:time("game") end
    return 0
end

local function _flush(key)
    local b = _buckets[key]
    if not b then return end
    _buckets[key] = nil
    if not rawget(_G, "printf") then return end
    local zlist = {}
    for z in pairs(b.zones) do zlist[#zlist + 1] = z end
    table.sort(zlist)
    printf("%s attacker=%s attack=%s hits_this_swing=%d zones=%s dmg_total=%.1f crit=%s t=%.2f",
        TAG, b.career, b.source, b.count, table.concat(zlist, ","), b.dmg,
        tostring(b.crit), b.first_t)
end

-- Observe every damage event on a training dummy. Signature mirrors vanilla
-- TrainingDummyHealthExtension.add_damage (:56) exactly. hook_safe gives us
-- (self, ...) with no `func` (it never wraps the return).
mod:hook_safe("TrainingDummyHealthExtension", "add_damage", function (self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit, hit_react_type, is_critical_strike, added_dot, first_hit, total_hits, attack_type, backstab_multiplier, target_index)
    local t = _now()
    local source = damage_source_name or attack_type or "n/a"
    -- Key by the dummy unit + attacker + source so two dummies, two players, or
    -- two weapons don't merge into one bucket. tostring(unit) is stable per-unit.
    local key = tostring(self.unit) .. "|" .. tostring(attacker_unit) .. "|" .. tostring(source)
    local b = _buckets[key]
    if b and (t - b.last_t) <= _WINDOW then
        b.count = b.count + 1
        b.dmg = b.dmg + (damage_amount or 0)
        b.last_t = t
        b.zones[hit_zone_name or "n/a"] = true
        if is_critical_strike then b.crit = true end
    else
        -- New swing: flush the previous bucket (if any) then start fresh.
        if b then _flush(key) end
        _buckets[key] = {
            count = 1,
            dmg = damage_amount or 0,
            first_t = t,
            last_t = t,
            career = _career_of(attacker_unit),
            source = tostring(source),
            zones = { [hit_zone_name or "n/a"] = true },
            crit = is_critical_strike and true or false,
        }
    end
end)

-- Idle-flush: emit a bucket's summary once its swing has gone quiet for _WINDOW
-- seconds. Guarantees the LAST swing prints even if no further hit follows.
-- Registered on gt's shared per-frame dispatcher so it never clobbers mod.update;
-- the loop is a no-op unless a dummy is actively being hit. Setting a key to nil
-- during pairs() traversal is permitted in Lua 5.1 (removal, not insertion).
if type(mod._gt_register_update) == "function" then
    mod._gt_register_update("gt_probe_dummy_hits_flush", function (_dt)
        if not next(_buckets) then return end
        local t = _now()
        for key, b in pairs(_buckets) do
            if (t - b.last_t) > _WINDOW then
                _flush(key)
            end
        end
    end)
end
