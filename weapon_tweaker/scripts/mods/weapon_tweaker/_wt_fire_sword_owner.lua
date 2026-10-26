-- #943/#942 composition: immutable policies and bounded injected engine edges.
local M = {}
local function pack(...) return { n = select("#", ...), ... } end
local function results(t) return unpack(t, 1, t.n) end
local function defaults(mod)
    local root = "scripts/mods/weapon_tweaker/"
    local lookup = mod:dofile(root .. "_lib_network_lookup")
    return {
        load = function(name) return mod:dofile(root .. name) end,
        heat = mod:dofile(root .. "_wt_fire_sword_heat"),
        application = mod:dofile(root .. "_wt_fire_sword_heat_runtime"),
        protocol = mod:dofile(root .. "_wt_fire_sword_heat_config_proof"),
        transport = mod:dofile(root .. "_wt_fire_sword_heat_transport"),
        get_weapons = function() return rawget(_G, "Weapons") end,
        profiles = rawget(_G, "DamageProfileTemplates"),
        fallbacks = mod._wt431_custom_profile_fallback or {},
        armor_reference = rawget(_G, "PowerLevelTemplates")
            and rawget(PowerLevelTemplates, "armor_modifier_linesman_H"),
        clone = function(value) return table.clone(value, true) end,
        register = function(name)
            local index, _, reason = lookup.register(NetworkLookup and NetworkLookup.damage_profiles, name)
            assert(index, "#942 profile registration failed: " .. tostring(reason))
        end,
        alive = function(unit) return ALIVE[unit] == true end,
        extension = function(unit, system) return ScriptUnit.has_extension(unit, system) end,
        humans = function() return Managers.player:human_players() end,
        local_peer = function() return Network.peer_id() end,
        guid = function() return Application.guid() end,
        enabled = function() return mod:is_enabled() == true end,
        breed = function(unit) return AiUtils.unit_breed(unit) end,
        multiplier = function(breed, zone) return DamageUtils.get_breed_damage_multiplier_type(breed, zone) end,
        log = function(...) return printf(...) end,
        classes = { sweep = rawget(_G, "ActionSweep"), slam = rawget(_G, "ActionShieldSlam"),
            utils = rawget(_G, "ActionUtils"), damage = rawget(_G, "DamageUtils"),
            network = rawget(_G, "GameNetworkManager") },
        hook = function(class, method, callback)
            if class == DamageUtils and method == "calculate_damage" then
                return mod:hook(DamageUtils, "calculate_damage", callback)
            elseif class == ActionSweep and method == "client_owner_start_action" then
                return mod:hook(ActionSweep, "client_owner_start_action", callback)
            elseif class == ActionShieldSlam and method == "client_owner_start_action" then
                return mod:hook(ActionShieldSlam, "client_owner_start_action", callback)
            elseif class == ActionUtils and method == "get_max_targets" then
                return mod:hook(ActionUtils, "get_max_targets", callback)
            elseif class == GameNetworkManager and method == "hot_join_sync" then
                return mod:hook(GameNetworkManager, "hot_join_sync", callback)
            end
            error("#942 unexpected native hook target", 0)
        end,
        register_receiver = function(channel, callback)
            assert(channel == "wt_fire_sword_heat_config_v1", "#942 unexpected receiver channel")
            return mod:network_register("wt_fire_sword_heat_config_v1", callback)
        end,
        send = function(channel, id, ...)
            assert(channel == "wt_fire_sword_heat_config_v1", "#942 unexpected send channel")
            return mod:network_send("wt_fire_sword_heat_config_v1", id, ...)
        end,
    }
end

function M.install(mod, heavy_policy, balance_policy, dependencies)
    local previous_owner = rawget(mod, "_wt942_owner")
    if previous_owner ~= nil then return previous_owner end -- never re-register, even after failure
    local deps = dependencies or defaults(mod)
    local owner = { committed = false, prepared = false, terminal = false,
        disabled = false, suspended = false, forced = false, hooks = {} }
    rawset(mod, "_wt942_owner", owner)
    local previous943 = heavy_policy.install(mod, { weapons = deps.get_weapons, log = deps.log })
    owner.heavy = previous943
    local previous_apply = mod._wt_apply_fire_sword
    local runtime, transport
    local function configuration()
        local config = deps.heat.config(function(id) return mod:get(id) end)
        if config and (owner.disabled or owner.suspended or owner.forced or deps.enabled() ~= true) then
            config.enabled = false
        end
        return config
    end
    function owner:reconcile()
        if runtime then
            local readable, weapons = pcall(deps.get_weapons)
            local replaced = not readable or weapons ~= self.weapons
                or rawget(self.weapons, deps.heat.TEMPLATE) ~= self.template
            if replaced then
                self.terminal = true; self.committed = false
                self.error = readable and "Fire Sword template replaced" or "Weapons reader failed"
            end
            return runtime:apply(not self.committed or self.terminal or self.disabled or self.suspended or self.forced)
        end
    end
    function owner:settings_changed(id)
        if id ~= nil and not self.settings[id] then return false end
        self.setting_refresh = true
        local refreshed, problem = true, nil
        if transport then refreshed, problem = pcall(transport.settings_changed, transport) end
        self.setting_refresh = false
        if not refreshed then self.committed, self.terminal, self.error = false, true, tostring(problem) end
        self:reconcile()
        return true
    end
    function owner:disconnect(id)
        if transport then transport:disconnect(id) end
        self:reconcile()
    end
    local function native_damage(func, damage_output, target, attacker, zone, power, curve, boost, critical, profile, ...)
        local values = pack(func(damage_output, target, attacker, zone, power, curve, boost, critical, profile, ...))
        if type(values[1]) == "number" and target then
            values[1] = balance_policy.scale_executioner_headshot_damage(values[1],
                deps.multiplier(deps.breed(target), zone), profile)
        end
        return results(values)
    end
    local function damage(func, ...)
        if runtime then
            return runtime:calculate_damage(function(...) return native_damage(func, ...) end, ...)
        end
        return native_damage(func, ...)
    end
    -- The old singleton #664 behavior survives even if heat initialization fails.
    local damage_ok, damage_error = pcall(deps.hook, deps.classes.damage, "calculate_damage", damage)
    owner.hooks.damage = damage_ok
    if not damage_ok then owner.terminal, owner.error = true, tostring(damage_error); return owner end

    local owned_fields, saved_fields = {}, {}
    local function assign(key, value)
        saved_fields[key] = { rawget(mod, key) }
        owned_fields[key] = value
        mod[key] = value
    end
    local ok, failure = pcall(function()
        for _, key in ipairs({ "load", "get_weapons", "clone", "register", "alive", "extension", "humans",
                "local_peer", "guid", "enabled", "register_receiver", "send" }) do
            assert(type(deps[key]) == "function", "#942 dependency missing: " .. key)
        end
        owner.weapons = assert(deps.get_weapons(), "#942 Weapons missing")
        owner.template = assert(rawget(owner.weapons, deps.heat.TEMPLATE), "#942 Fire Sword missing")
        mod._wt431_custom_profile_fallback = deps.fallbacks
        owner.settings = { [deps.heat.ENABLED] = true, [deps.heat.ARMOR] = true,
            [deps.heat.CLEAVE] = true, [deps.heat.DAMAGE] = true, [deps.heat.THRESHOLD] = true }
        runtime = deps.application.new(mod, {
            policy = deps.heat, weapons = owner.weapons, profiles = deps.profiles,
            clone = deps.clone, register = deps.register, fallbacks = deps.fallbacks,
            armor_reference = deps.armor_reference, alive = deps.alive, extension = deps.extension,
            catalog_allows = function()
                return owner.committed and not owner.terminal
                    and type(mod._wt431_profiles_allowed) == "function" and mod._wt431_profiles_allowed() == true
            end,
            configuration_agrees = function(config) return transport ~= nil and transport:allows(config) end,
        })
        owner.runtime = runtime
        -- Complete toggle-independent registration BEFORE any transport/GUID failure.
        local epoch = deps.transport.epoch(deps.guid())
        assert(epoch and epoch ~= deps.transport.epoch(string.rep("0", 32))
            and epoch ~= rawget(mod, "_wt942_last_epoch"), "#942 fresh GUID unavailable")
        rawset(mod, "_wt942_last_epoch", epoch)
        transport = deps.transport.new({ protocol = deps.protocol, epoch = epoch,
            read_config = configuration, humans = deps.humans, local_peer = deps.local_peer,
            committed = function() return owner.committed and not owner.terminal end,
            send = deps.send, changed = function() if not owner.setting_refresh then owner:reconcile() end end })
        owner.transport = transport
        for _, row in ipairs({ { "sweep", "client_owner_start_action" },
                { "slam", "client_owner_start_action" }, { "utils", "get_max_targets" },
                { "network", "hot_join_sync" } }) do
            assert(type(deps.classes[row[1]]) == "table"
                and type(deps.classes[row[1]][row[2]]) == "function", "#942 native seam missing: " .. row[1])
        end
        local function start(func, ...)
            if not owner.committed then return func(...) end
            return runtime:start_action(func, ...)
        end
        deps.hook(deps.classes.sweep, "client_owner_start_action", start); owner.hooks.sweep = true
        deps.hook(deps.classes.slam, "client_owner_start_action", start); owner.hooks.slam = true
        deps.hook(deps.classes.utils, "get_max_targets", function(func, ...)
            if not owner.committed then return func(...) end
            return runtime:max_targets(func, ...)
        end); owner.hooks.utils = true
        deps.hook(deps.classes.network, "hot_join_sync", function(func, manager, id, ...)
            if owner.committed then
                local fenced, problem = pcall(function()
                    transport:require_peer(id)
                    assert(not transport.poisoned, "#942 pending join fence invalid/over capacity")
                    local parity = mod._wt_peer_parity
                    assert(parity and type(parity.require_peer) == "function", "#942 catalog join fence missing")
                    parity:require_peer(id)
                    owner:reconcile()
                end)
                if not fenced then owner.committed = false; owner.terminal = true; owner.error = tostring(problem); owner:reconcile() end
            end
            return func(manager, id, ...)
        end); owner.hooks.join = true
        deps.register_receiver(deps.transport.CHANNEL, function(sender, ...)
            if owner.committed then return transport:receive(sender, ...) end
        end)
        local previous_update = mod.update
        assign("update", function(dt, ...)
            if owner.committed then
                local ticked, problem = pcall(transport.tick, transport, dt)
                if not ticked then owner.committed = false; owner.terminal = true; owner.error = tostring(problem); owner:reconcile() end
            end
            if previous_update then return previous_update(dt, ...) end
        end)
        assign("_wt_apply_fire_sword", function(id, force_off)
            local values = pack(previous_apply(id, force_off))
            if id == nil or owner.settings[id] then
                owner.forced = force_off == true
                owner:settings_changed(id)
            end
            return results(values)
        end)
        for _, event in ipairs({ "on_enabled", "on_disabled", "on_game_state_changed" }) do
            local name, previous = event, mod[event]
            assign(name, function(...)
                local status, state_name = ...
                if name == "on_disabled" then owner.disabled = true
                elseif name == "on_enabled" then owner.disabled, owner.forced = false, false
                else owner.suspended = true end
                owner:settings_changed()
                local values = pack(pcall(function(...) if previous then return previous(...) end end, ...))
                if values[1] and name == "on_game_state_changed" and status == "enter" and state_name == "StateIngame" then
                    owner.suspended = false; owner:settings_changed()
                end
                if not values[1] then owner.suspended = true; owner:settings_changed(); error(values[2], 0) end
                return unpack(values, 2, values.n)
            end)
        end
        assign("_wt942_on_setting_changed", function(id) return owner:settings_changed(id) end)
        assert(mod._wt and type(mod._wt.rt_register) == "function", "#942 regression registrar missing")
        mod._wt.rt_register("issue942_fire_sword_heat_boundary", function()
            if not owner.committed or owner.terminal or not transport or transport.poisoned then
                return "#942 production adapter is not committed/healthy"
            end
            local checked, problem = pcall(function()
                local checks = deps.load("_wt_fire_sword_heat_checks")
                assert(type(checks) == "table" and type(checks.run) == "function", "#942 detached check missing")
                checks.run(deps.load)
            end)
            if not checked then return "#942 detached installed-adapter proof failed: " .. tostring(problem) end
        end)
        owner.prepared = true
    end)
    if not ok then
        owner.committed, owner.terminal, owner.error = false, true, tostring(failure)
        for key, value in pairs(owned_fields) do
            if rawget(mod, key) == value then rawset(mod, key, saved_fields[key][1]) end
        end
        owner:reconcile()
        if type(deps.log) == "function" then pcall(deps.log, "[wt:942] inert: %s", owner.error) end
    end
    function owner:finish_install()
        if self.terminal or not self.prepared then return false end
        if self.committed then return true end
        local parity = mod._wt_peer_parity
        local ready, installed = pcall(function()
            return parity and parity:is_installed() == true
                and mod._wt431_disconnect_epoch_guard == true
                and type(mod._wt431_profiles_allowed) == "function"
        end)
        if not ready or installed ~= true then self.terminal = true; self.error = "catalog lifecycle not committed"; self:reconcile(); return false end
        self.committed = true
        local applied, problem = pcall(self.settings_changed, self)
        if not applied then
            self.committed, self.terminal, self.error = false, true, tostring(problem)
            self:reconcile(); return false
        end
        return true
    end
    return owner
end
return M
