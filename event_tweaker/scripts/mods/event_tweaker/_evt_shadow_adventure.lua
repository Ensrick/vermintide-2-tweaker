local mod = get_mod("event_tweaker")

-- _evt_shadow_adventure.lua -- issue 413 Adventure Shadow adapter
--
-- Vanilla Shadow cannot be activated outside a Weave: every local client
-- spawns wpn_shadow_gargoyle_head and immediately calls Unit.light on it, while
-- the server receives no wind-settings radius. Adventure does not keep the
-- gargoyle or vfx_static_shadow_01 resident. A host-only pcall cannot contain
-- either engine-resource failure.
--
-- The gameplay itself needs neither asset. Fatshark's server path gives enemies
-- outside six metres of every hero mutator_shadow_damage_reduction (-80% damage
-- taken, the WindSettings.shadow value); its client path fades enemies outside
-- the same radius. This adapter
-- preserves those mechanics using only boot-registered code/buff identities and
-- deliberately omits the non-resident lantern and shadow VFX.
--
-- The stock mutator name is still broadcast, so every peer must run THIS
-- capability before the host may inject it. A dedicated parity channel proves
-- the adapter rather than merely proving some older event_tweaker version. The
-- common pre-session pending-peer fence and hot-join lock remain unconditional.

local ET = mod._evt
local rt_register = ET.rt_register
local Policy = require("scripts/mods/event_tweaker/event_tweaker_shadow_policy")

local SHADOW_CHANNEL = "et_shadow_adventure_v1"
local SHADOW_SCHEMA = 1
local shadow_template
local adapter_ready = false

local function _in_native_weave()
    return ET.weave_wind_active and ET.weave_wind_active() == true
end

-- Issues 413 + 1123: the damage-reduction value is session-scoped AND is never
-- written onto the SHARED vanilla table. Vanilla ships the
-- mutator_shadow_damage_reduction sub-buff with NO multiplier (only stat_buff +
-- wind_mutator, buff_templates.lua:6322-6330), so outside a Weave BuffExtension
-- resolves "multiplier or 0" and the buff is a zero-effect marker - exactly
-- what Chaos Wastes' mutator_curse_belakors_shadows expects when it adds the
-- SAME shared template by name (mutator_curse_belakors_shadows.lua:87). An
-- earlier in-place template write leaked 90 percent damage reduction into
-- every CW Be'lakor run. The adapter therefore keeps a private CLONE with the
-- vanilla Ulgu value (WindSettings.shadow.damage_taken = -0.8 at every
-- difficulty and wind strength, wind_settings.lua:1615-1669) baked in, and
-- swaps the BuffTemplates ENTRY to that clone only while an Adventure Shadow
-- session runs. This is safe because BuffExtension resolves templates by NAME
-- at add time (buff_extension.lua:173 -> buff_utils.lua:257-261) and captures
-- both the multiplier and a direct sub-buff-table reference on the buff
-- INSTANCE (buff_extension.lua:~300 / _remove_stat_buff:1118-1121), so buffs
-- added during the session subtract correctly even after the swap-back. The
-- vanilla table itself is NEVER mutated. Restore runs at session stop AND on
-- mod disable. Real Weaves are unaffected either way: the wind_mutator branch
-- overwrites the multiplier from active wind settings at both add and remove
-- time (buff_extension.lua:649-657 / 1127-1135).
local vanilla_shadow_buff_template
local adventure_shadow_buff_template
local template_swapped = false

local function _clone_shadow_buff_template(template)
    local clone = {}
    for k, v in pairs(template) do
        clone[k] = v
    end
    local buffs = {}
    for i = 1, #template.buffs do
        local sub = {}
        for k, v in pairs(template.buffs[i]) do
            sub[k] = v
        end
        buffs[i] = sub
    end
    clone.buffs = buffs
    return clone
end

local function _swap_in_adventure_template()
    local buff_templates = rawget(_G, "BuffTemplates")
    if template_swapped or not buff_templates
        or not vanilla_shadow_buff_template or not adventure_shadow_buff_template then
        return
    end
    buff_templates.mutator_shadow_damage_reduction = adventure_shadow_buff_template
    template_swapped = true
    pcall(printf, "[et:413] shadow damage-reduction entry swapped to Adventure clone (damage_taken "
        .. tostring(Policy.ADVENTURE_DAMAGE_TAKEN) .. "; vanilla table untouched)")
end

local function _restore_vanilla_template()
    if not template_swapped then
        return
    end
    template_swapped = false
    local buff_templates = rawget(_G, "BuffTemplates")
    if not buff_templates then
        return
    end
    if buff_templates.mutator_shadow_damage_reduction == adventure_shadow_buff_template then
        buff_templates.mutator_shadow_damage_reduction = vanilla_shadow_buff_template
        pcall(printf, "[et:413] shadow damage-reduction entry restored to the vanilla template")
    else
        -- A third party replaced the entry after our swap; writing vanilla
        -- back would clobber THEIR state. The vanilla table was never
        -- mutated, so no et residue remains either way.
        pcall(printf, "[et:413] WARNING shadow damage-reduction entry was replaced mid-session by another mod; left as found")
    end
end

local function _position(unit)
    local lookup = rawget(_G, "POSITION_LOOKUP")
    return unit and lookup and lookup[unit] or nil
end

local function _alive(unit)
    local health_alive = rawget(_G, "HEALTH_ALIVE")
    return unit and health_alive and health_alive[unit] == true
end

local function _server_start(context, data)
    if _in_native_weave() then
        return shadow_template._et413_original_server_start(context, data)
    end
    local managers = rawget(_G, "Managers")
    local state = managers and managers.state
    local entity = state and state.entity
    local side = state and state.side
    data.et413_adventure_shadow = true
    data.et413_light_radius = Policy.ADVENTURE_RADIUS
    data.et413_server_index = 0
    data.et413_buffs = {}
    data.buff_system = entity and entity:system("buff_system") or nil
    data.hero_side = side and side:get_side_from_name("heroes") or nil
    _swap_in_adventure_template()
end

local function _remove_server_buff(data, unit)
    local id = data.et413_buffs and data.et413_buffs[unit]
    if id and data.buff_system then
        pcall(data.buff_system.remove_server_controlled_buff, data.buff_system, unit, id)
    end
    if data.et413_buffs then data.et413_buffs[unit] = nil end
end

local function _server_update(context, data, dt, t)
    if not data.et413_adventure_shadow then
        return shadow_template._et413_original_server_update(context, data, dt, t)
    end
    local hero_side = data.hero_side
    local enemies = hero_side and hero_side:enemy_units()
    local players = hero_side and hero_side.PLAYER_UNITS
    local buff_system = data.buff_system
    if type(enemies) ~= "table" or type(players) ~= "table" or not buff_system then return end

    for _ = 1, 5 do
        data.et413_server_index = data.et413_server_index + 1
        local unit = enemies[data.et413_server_index]
        if not unit then
            data.et413_server_index = 0
            break
        end

        if _alive(unit) and ScriptUnit.has_extension(unit, "buff_system") then
            local unit_pos = _position(unit)
            local revealed = false
            if unit_pos then
                for _, player_unit in pairs(players) do
                    local player_pos = _position(player_unit)
                    if player_pos and Vector3.distance_squared(player_pos, unit_pos)
                        <= Policy.ADVENTURE_RADIUS * Policy.ADVENTURE_RADIUS then
                        revealed = true
                        break
                    end
                end
            end

            local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
            local has_buff = buff_extension
                and buff_extension:has_buff_type("mutator_shadow_damage_reduction")
            if revealed then
                if has_buff and data.et413_buffs[unit] then
                    _remove_server_buff(data, unit)
                end
            else
                -- Match native Shadow: a concealed enemy cannot remain pinged.
                -- The ping system owns removal; this adapter only requests it.
                local ping_extension = ScriptUnit.has_extension(unit, "ping_system")
                if ping_extension and ping_extension:pinged() then
                    local managers = rawget(_G, "Managers")
                    local entity = managers and managers.state and managers.state.entity
                    local ping_system = entity and entity:system("ping_system")
                    if ping_system then ping_system:remove_ping_from_unit(unit) end
                end
                if not has_buff then
                    local id = buff_system:add_buff(
                        unit, "mutator_shadow_damage_reduction", unit, true)
                    if id then data.et413_buffs[unit] = id end
                end
            end
        end
    end

    for unit in pairs(data.et413_buffs) do
        if not _alive(unit) then data.et413_buffs[unit] = nil end
    end
end

local function _server_stop(context, data, is_destroy)
    if data.et413_adventure_shadow then
        for unit in pairs(data.et413_buffs or {}) do
            _remove_server_buff(data, unit)
        end
        -- Safe before pending client-side removals: BuffExtension removal
        -- subtracts the multiplier captured on the buff INSTANCE at add time
        -- (buff_extension.lua _remove_stat_buff:1118-1121), and the instance
        -- keeps its own reference to the clone's sub-buff table, so the
        -- swap-back cannot orphan or re-price an outstanding buff.
        _restore_vanilla_template()
    end
    return shadow_template._et413_original_server_stop(context, data, is_destroy)
end

local function _client_start(context, data)
    if _in_native_weave() then
        return shadow_template._et413_original_client_start(context, data)
    end
    local managers = rawget(_G, "Managers")
    local side = managers and managers.state and managers.state.side
    data.et413_adventure_shadow = true
    data.et413_client_index = 0
    data.et413_faded_units = {}
    data.hero_side = side and side:get_side_from_name("heroes") or nil
    _swap_in_adventure_template()
end

local function _client_update(context, data, dt, t)
    if not data.et413_adventure_shadow then
        return shadow_template._et413_original_client_update(context, data, dt, t)
    end
    local managers = rawget(_G, "Managers")
    local state = managers and managers.state
    local player_manager = managers and managers.player
    local entity = state and state.entity
    local fade_system = entity and entity:system("fade_system")
    local hero_side = data.hero_side
    local enemies = hero_side and hero_side:enemy_units()
    local local_player = player_manager and player_manager:local_player()
    if type(enemies) ~= "table" or not fade_system or not local_player then return end

    local observed = local_player:observed_unit()
    local alive_lookup = rawget(_G, "ALIVE")
    if not (alive_lookup and alive_lookup[observed]) then observed = local_player.player_unit end
    local observer_pos = _position(observed)

    for _ = 1, 5 do
        data.et413_client_index = data.et413_client_index + 1
        local unit = enemies[data.et413_client_index]
        if not unit then
            data.et413_client_index = 0
            break
        end
        if _alive(unit) then
            local unit_pos = _position(unit)
            local outside = observer_pos and unit_pos
                and Vector3.distance_squared(observer_pos, unit_pos)
                    >= Policy.ADVENTURE_RADIUS * Policy.ADVENTURE_RADIUS
            local scalar = outside and 1 or 0
            if data.et413_faded_units[unit] ~= scalar then
                fade_system:set_min_fade(unit, scalar)
                data.et413_faded_units[unit] = scalar
            end
        end
    end

    for unit in pairs(data.et413_faded_units) do
        if not _alive(unit) then data.et413_faded_units[unit] = nil end
    end
end

local function _client_respawn(context, data, spawned_unit)
    if not data.et413_adventure_shadow then
        return shadow_template._et413_original_client_respawn(context, data, spawned_unit)
    end
    -- Adventure adapter has no linked lantern unit to respawn.
end

local function _client_stop(context, data, is_destroy)
    if data.et413_adventure_shadow then
        local managers = rawget(_G, "Managers")
        local entity = managers and managers.state and managers.state.entity
        local fade_system = entity and entity:system("fade_system")
        if fade_system then
            for unit in pairs(data.et413_faded_units or {}) do
                local ok_alive, alive = pcall(Unit.alive, unit)
                if ok_alive and alive then
                    pcall(fade_system.set_min_fade, fade_system, unit, 0)
                end
            end
        end
        _restore_vanilla_template()
    end
    return shadow_template._et413_original_client_stop(context, data, is_destroy)
end

do
    local templates = rawget(_G, "MutatorTemplates")
    shadow_template = templates and rawget(templates, "shadow")
    local buffs = rawget(_G, "BuffTemplates")
    local shadow_buff = buffs and rawget(buffs, "mutator_shadow_damage_reduction")
    local sub_buff = shadow_buff and shadow_buff.buffs and shadow_buff.buffs[1]
    if shadow_template and shadow_template.server and shadow_template.client
        and type(shadow_template.server_start_function) == "function"
        and type(shadow_template.server_update_function) == "function"
        and type(shadow_template.client_start_function) == "function"
        and type(shadow_template.client_update_function) == "function"
        and type(shadow_template.client_player_respawned_function) == "function"
        and type(shadow_template.server.stop_function) == "function"
        and type(shadow_template.client.stop_function) == "function"
        and sub_buff then
        -- Preserve the native dispatch only once. VMF developer reloads can
        -- evaluate this module again in the same Lua state; capturing our prior
        -- wrapper as "original" would recurse on the next real Weave.
        shadow_template._et413_vanilla_server_start =
            shadow_template._et413_vanilla_server_start or shadow_template.server_start_function
        shadow_template._et413_vanilla_server_update =
            shadow_template._et413_vanilla_server_update or shadow_template.server_update_function
        shadow_template._et413_vanilla_server_stop =
            shadow_template._et413_vanilla_server_stop or shadow_template.server.stop_function
        shadow_template._et413_vanilla_client_start =
            shadow_template._et413_vanilla_client_start or shadow_template.client_start_function
        shadow_template._et413_vanilla_client_update =
            shadow_template._et413_vanilla_client_update or shadow_template.client_update_function
        shadow_template._et413_vanilla_client_respawn =
            shadow_template._et413_vanilla_client_respawn or shadow_template.client_player_respawned_function
        shadow_template._et413_vanilla_client_stop =
            shadow_template._et413_vanilla_client_stop or shadow_template.client.stop_function

        shadow_template._et413_original_server_start = shadow_template._et413_vanilla_server_start
        shadow_template._et413_original_server_update = shadow_template._et413_vanilla_server_update
        shadow_template._et413_original_server_stop = shadow_template._et413_vanilla_server_stop
        shadow_template._et413_original_client_start = shadow_template._et413_vanilla_client_start
        shadow_template._et413_original_client_update = shadow_template._et413_vanilla_client_update
        shadow_template._et413_original_client_respawn = shadow_template._et413_vanilla_client_respawn
        shadow_template._et413_original_client_stop = shadow_template._et413_vanilla_client_stop

        shadow_template.server_start_function = _server_start
        shadow_template.server_update_function = _server_update
        shadow_template.client_start_function = _client_start
        shadow_template.client_update_function = _client_update
        shadow_template.client_player_respawned_function = _client_respawn
        shadow_template.server.update = _server_update
        shadow_template.client.update = _client_update
        shadow_template.server.stop_function = _server_stop
        shadow_template.client.stop_function = _client_stop
        -- Issues 413 + 1123: never write onto the shared vanilla buff table.
        -- Capture the vanilla template reference (stashed on shadow_template
        -- so a VMF developer reload during an active session cannot mistake
        -- our still-installed clone for vanilla), build the Adventure clone
        -- once, and let the session start/stop functions above swap the
        -- BuffTemplates ENTRY between the two.
        shadow_template._et413_vanilla_shadow_buff_template =
            shadow_template._et413_vanilla_shadow_buff_template or shadow_buff
        vanilla_shadow_buff_template = shadow_template._et413_vanilla_shadow_buff_template
        adventure_shadow_buff_template = _clone_shadow_buff_template(vanilla_shadow_buff_template)
        adventure_shadow_buff_template.buffs[1].multiplier = Policy.ADVENTURE_DAMAGE_TAKEN
        adventure_shadow_buff_template._et413_adventure_clone = true
        -- A VMF developer reload mid-session resets this module's bookkeeping;
        -- if a PRIOR instance's clone is still installed, put vanilla back now
        -- (the clone marker distinguishes our stale clone from a third party's
        -- legitimate replacement, which is left as found).
        local stale = buffs.mutator_shadow_damage_reduction
        if stale ~= vanilla_shadow_buff_template and type(stale) == "table"
            and stale._et413_adventure_clone then
            buffs.mutator_shadow_damage_reduction = vanilla_shadow_buff_template
            pcall(printf, "[et:413] stale Adventure clone from a prior module instance restored to vanilla")
        end
        adapter_ready = true
    else
        pcall(printf, "[et:413] Adventure Shadow adapter unavailable: vanilla template/buff contract changed")
    end
end

local shadow_parity
do
    local ok_lib, factory = pcall(function()
        return mod:dofile("scripts/mods/event_tweaker/_lib_peer_parity")
    end)
    if ok_lib and type(factory) == "function" then
        local ok_inst, instance = pcall(factory, mod, {
            channel = SHADOW_CHANNEL,
            schema = SHADOW_SCHEMA,
            mod_label = "Tweaker: Events with Adventure Shadow support",
            echo_prefix = "[Events]",
        })
        if ok_inst and type(instance) == "table" then
            shadow_parity = instance
            -- #1158 install-transaction fanout (LANDED): install() runs receiver
            -- registration and mod.update ownership in ONE pcall and returns the
            -- commit boolean. The capability floor below already re-checks
            -- is_installed(), and the lib hard-gates every peer query on the same
            -- commit, so this consumes the boolean as log evidence.
            local ok_install, committed = pcall(function() return shadow_parity:install() end)
            if not (ok_install and committed == true) then
                pcall(printf, "[et:413] WARNING Adventure Shadow beacon install did not commit (%s); capability stays unproven",
                    tostring(committed))
            end
            pcall(function()
                shadow_parity:register_gated_feature("et_shadow_adventure", {
                    label = "peer_parity_shadow_feature_label",
                    on_enable = function()
                        pcall(printf, "[et:413] Adventure Shadow peer capability established")
                    end,
                    on_disable = function()
                        pcall(printf, "[et:413] Adventure Shadow disabled: a peer lacks capability v1")
                    end,
                })
            end)
        end
    end
end
mod._et_shadow_parity = shadow_parity

local function _wire_safe()
    if not adapter_ready or not shadow_parity or not ET.peer_feature_wire_safe then return false end
    return ET.peer_feature_wire_safe(shadow_parity) == true
end

local function _plan()
    return Policy.plan(true, _in_native_weave(), _wire_safe(), adapter_ready)
end

local notified = {}
local function _notify_drop(reason)
    reason = tostring(reason or "unsafe")
    if notified[reason] then return end
    notified[reason] = true
    pcall(function()
        mod:echo("[Events] Shadow skipped: every player needs the current Adventure Shadow-capable Tweaker: Events build.")
    end)
end

ET.shadow_adventure_wire_safe = _wire_safe
ET.shadow_adventure_plan = _plan
ET.notify_shadow_drop = _notify_drop
ET.shadow_adventure_adapter_ready = function() return adapter_ready end

-- VMF lifecycle: et is is_togglable, so disabling it mid-session must not
-- leave the Adventure clone installed in BuffTemplates. This is et's ONLY
-- mod.on_disabled (grep-verified 2026-08-15; VMF keeps exactly one - merge
-- here instead of assigning a second).
mod.on_disabled = function()
    _restore_vanilla_template()
end

rt_register("issue413_shadow_adventure_adapter", function()
    if not adapter_ready then return "Adventure Shadow template adapter was not installed" end
    local vanilla_sub = vanilla_shadow_buff_template and vanilla_shadow_buff_template.buffs
        and vanilla_shadow_buff_template.buffs[1]
    if vanilla_sub and vanilla_sub.multiplier ~= nil then
        return "vanilla shadow buff template was mutated in place (issues 413/1123: it must stay multiplier-free for Chaos Wastes)"
    end
    local buff_templates = rawget(_G, "BuffTemplates")
    local live = buff_templates and buff_templates.mutator_shadow_damage_reduction
    if not template_swapped and live == adventure_shadow_buff_template then
        return "Adventure clone left installed outside a Shadow session (issue 413 restore failed)"
    end
    if template_swapped and live ~= adventure_shadow_buff_template then
        return "Shadow session marked active but the BuffTemplates entry is not the Adventure clone (issue 413)"
    end
    local adv_sub = adventure_shadow_buff_template and adventure_shadow_buff_template.buffs
        and adventure_shadow_buff_template.buffs[1]
    if not adv_sub or adv_sub.multiplier ~= Policy.ADVENTURE_DAMAGE_TAKEN then
        return "Adventure clone lost the vanilla Ulgu damage_taken value (issue 413)"
    end
    if Policy.ADVENTURE_DAMAGE_TAKEN ~= -0.8 then
        return "Adventure Shadow damage_taken constant drifted from the vanilla wind value -0.8 (wind_settings.lua:1615)"
    end
    if not shadow_parity or not shadow_parity:is_installed() then
        return "Adventure Shadow capability beacon was not installed"
    end
    if Policy.plan(true, false, true, true) ~= "adventure_adapter" then
        return "Shadow policy no longer allows a proven all-capability Adventure lobby"
    end
    if Policy.plan(true, false, false, true) ~= "drop_peer_capability" then
        return "Shadow policy no longer fails closed for an unproven peer"
    end
    if Policy.plan(true, true, false, true) ~= "native_weave" then
        return "Shadow policy interferes with native Weaves"
    end
end)
