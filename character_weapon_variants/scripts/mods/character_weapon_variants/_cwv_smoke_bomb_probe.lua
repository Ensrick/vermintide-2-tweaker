-- Issue #343: observation-only preflight for a bomb-slot Ranger smoke grenade.
-- No ItemMasterList, NetworkLookup, pickup-pool, buff, projectile, or unit writes
-- occur here. The existing Tuskgor bomb-slot experiment remains quarantined.
local M = { MAX_RUNS = 3, _runs = 0, _auto_done = false }

local function finite_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function M.classify(snapshot)
    snapshot = type(snapshot) == "table" and snapshot or {}
    local pool_sum = snapshot.pool_sum
    local pool_healthy = finite_number(pool_sum) and pool_sum >= 0.999
        and pool_sum <= 1.001 and (snapshot.pool_count or 0) > 0
    local base_ready = snapshot.grenade_template == true
        and snapshot.grenade_projectile == true
        and snapshot.ranger_template == true
        and snapshot.ranger_item == true
        and snapshot.smoke_explosion == true
    local area_ready = snapshot.ranger_area_buff == true
        and snapshot.buff_area_position_contract == true

    return {
        base_ready = base_ready,
        area_ready = area_ready,
        pool_healthy = pool_healthy,
        exact_z_scale_ready = false,
        registration_quarantined = true,
        status = base_ready and area_ready and pool_healthy
            and "runtime_prereqs_ready_exact_fx_and_registration_blocked"
            or "runtime_prereq_missing",
    }
end

function M.collect_snapshot()
    local weapons = rawget(_G, "Weapons")
    local projectiles = rawget(_G, "Projectiles")
    local explosions = rawget(_G, "ExplosionTemplates")
    local items = rawget(_G, "ItemMasterList")
    local pickups = rawget(_G, "Pickups")
    local smoke = explosions and explosions.bardin_ranger_activated_ability_stagger
    local smoke_data = smoke and smoke.explosion
    local ranger_buff
    local buff_utils = rawget(_G, "BuffUtils")
    if buff_utils and type(buff_utils.get_buff_template) == "function" then
        local ok, value = pcall(buff_utils.get_buff_template, "bardin_ranger_activated_ability")
        if ok then ranger_buff = value end
    end
    local area
    if ranger_buff and type(ranger_buff.buffs) == "table" then
        for i = 1, #ranger_buff.buffs do
            local candidate = ranger_buff.buffs[i]
            if candidate and candidate.buff_area then area = candidate break end
        end
    end
    local pool = pickups and pickups.grenades
    local count, sum = 0, 0
    if type(pool) == "table" then
        for _, settings in pairs(pool) do
            if type(settings) == "table" then
                count = count + 1
                sum = sum + (tonumber(settings.spawn_weighting) or 0)
            end
        end
    end

    return {
        grenade_template = weapons and weapons.grenade ~= nil or false,
        grenade_projectile = projectiles and projectiles.grenade ~= nil or false,
        ranger_template = weapons and weapons.bardin_ranger_career_skill_weapon ~= nil or false,
        ranger_item = items and rawget(items, "bardin_ranger_career_skill_weapon") ~= nil or false,
        smoke_explosion = smoke_data ~= nil
            and smoke_data.effect_name == "fx/wpnfx_smoke_grenade_impact"
            and smoke_data.sound_event_name == "Play_bardin_ranger_smoke_grenade_ability",
        ranger_area_buff = area ~= nil and area.area_radius == 8
            and area.buff_area_buff == "bardin_ranger_activated_ability_buff",
        -- Verified in vanilla BuffExtension.add_buff: params.buff_area_position
        -- is preferred over POSITION_LOOKUP[self._unit] at buff_extension.lua:379.
        buff_area_position_contract = true,
        pool_count = count,
        pool_sum = sum,
    }
end

function M.format(snapshot, result)
    return string.format(
        "[cwv:343] status=%s base=%s area=%s pool=%d/%.6f healthy=%s exact_z_scale=%s registration_quarantined=%s",
        tostring(result.status), tostring(result.base_ready), tostring(result.area_ready),
        tonumber(snapshot.pool_count) or 0, tonumber(snapshot.pool_sum) or -1,
        tostring(result.pool_healthy), tostring(result.exact_z_scale_ready),
        tostring(result.registration_quarantined))
end

function M.run(mod, silent)
    if M._runs >= M.MAX_RUNS then
        return false, "probe_cap_reached"
    end
    M._runs = M._runs + 1
    local snapshot = M.collect_snapshot()
    local result = M.classify(snapshot)
    local line = M.format(snapshot, result)
    pcall(printf, "%s", line)
    if not silent and mod and type(mod.echo) == "function" then
        mod:echo("[cwv] Smoke Bomb probe recorded in the log (%d/%d).", M._runs, M.MAX_RUNS)
    end
    return true, line
end

function M.auto_run(mod)
    if M._auto_done then return false, "auto_already_recorded" end
    M._auto_done = true
    return M.run(mod, true)
end

function M.install(mod)
    mod:command("cwv_smoke_bomb_probe",
        "Record the source/runtime prerequisites for issue #343 Smoke Bomb",
        function() M.run(mod, false) end)
end

return M
