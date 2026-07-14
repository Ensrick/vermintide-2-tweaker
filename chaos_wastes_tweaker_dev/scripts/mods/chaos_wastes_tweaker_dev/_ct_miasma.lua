-- _ct_miasma.lua - Rotten Miasma customization for issue #361.
--
-- Mutates the existing vanilla buff template for radius/exposure timing and
-- wraps the live mutator's server update exactly once. Vanilla still creates,
-- updates, and removes the sole networked safe-area unit; CT only remembers a
-- living carrier and repositions that same unit after vanilla has updated it.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: mod:dofile.

local mod = get_mod("ct_dev")
local policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_miasma_policy")
mod._ct_miasma_policy = policy

local function effective(name)
    local getter = mod._ct_effective_setting
    return getter and getter(name) or mod:get(name)
end

local function live_template()
    local templates = rawget(_G, "BuffTemplates")
    local parent = templates and templates.curse_rotten_miasma
    return parent and parent.buffs and parent.buffs[1]
end

local function sync_template()
    local template = live_template()
    if not template then return false end
    local radius = policy.radius(effective("miasma_safe_radius"))
    local interval = policy.interval(effective("miasma_stack_interval"))
    local radii = template.safe_area_radius
    if type(radii) ~= "table" then
        radii = {}
        template.safe_area_radius = radii
    end
    for i = 1, 5 do radii[i] = radius end
    template.buff_exposure_tick_rate = interval
    return true
end

mod._ct_sync_miasma = sync_template
sync_template()

local log_count = 0
local function evidence(fmt, ...)
    if log_count >= 32 then return end
    log_count = log_count + 1
    pcall(printf, "[ct:361] " .. fmt, ...)
end

local carrier_results = {}
local function carriers()
    for i = #carrier_results, 1, -1 do carrier_results[i] = nil end
    local side_manager = Managers.state.side
    local side = side_manager and side_manager:get_side_from_name("heroes")
    local units = side and side.PLAYER_UNITS
    if not units then return carrier_results end
    for i = 1, #units do
        local unit = units[i]
        local inventory = ScriptUnit.has_extension(unit, "inventory_system")
        if inventory and inventory:has_inventory_item("slot_level_event", "wpn_deus_relic_01") then
            carrier_results[#carrier_results + 1] = unit
        end
    end
    return carrier_results
end

local function refresh_live_radius(safe_area)
    local buff_extension = ScriptUnit.has_extension(safe_area, "buff_system")
    local buff = buff_extension and buff_extension:get_buff_type("curse_rotten_miasma")
    if not buff then return end
    local radius = policy.radius(effective("miasma_safe_radius"))
    if buff.radius ~= radius then
        buff.radius = radius
        Unit.set_data(safe_area, "radius", radius)
        Unit.flow_event(safe_area, "update_radius")
        evidence("live radius applied radius=%.1f", radius)
    end
end

local mutators = rawget(_G, "MutatorTemplates")
local miasma = mutators and mutators.curse_rotten_miasma
local server = miasma and miasma.server
_G.__ct_miasma361_hook_installed = false
if server and type(server.update) == "function" then
    -- CT_MIASMA361_CONSOLIDATED_SERVER_UPDATE
    mod:hook(server, "update", function(func, context, data, dt, t)
        sync_template()
        func(context, data, dt, t)

        local safe_area = data.rotten_miasma_safe_area
        if not (safe_area and Unit.alive(safe_area)) then return end
        refresh_live_radius(safe_area)

        if not effective("miasma_permanent_carrier") then
            data._ct_miasma_owner = nil
            return
        end

        local owner, changed = policy.select_owner(data._ct_miasma_owner, carriers(),
            function(unit) return unit and HEALTH_ALIVE[unit] end)
        data._ct_miasma_owner = owner
        if changed then evidence("permanent carrier changed owner_alive=%s", tostring(owner ~= nil)) end
        local position = owner and POSITION_LOOKUP[owner]
        if position then
            Unit.set_local_position(safe_area, 0, position)
        end
    end)
    _G.__ct_miasma361_hook_installed = true
    evidence("installed radius=%.1f interval=%.1f permanent=%s",
        policy.radius(effective("miasma_safe_radius")),
        policy.interval(effective("miasma_stack_interval")),
        tostring(effective("miasma_permanent_carrier")))
end
