-- Two reviewed registration owners through real balance/default/431 boot paths.
-- Private tables/classes/VMF bus only: this does not simulate a live attack.
return function(H, root)
    local Json = assert(loadfile(root .. "/qa/lua/fixtures/restricted_json.lua"))()
    local KEY, SOURCE = "wt_priest_punch_buffed", "light_blunt_smiter_stab"
    local TEMPLATE = "two_handed_hammer_priest_template"
    local function clone(value)
        if type(value) ~= "table" then return value end
        local out = {}; for key, item in next, value do out[key] = clone(item) end; return out
    end
    local function pack(...) return { n = select("#", ...), ... } end
    for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
        local prefix = root .. "/" .. namespace .. "/scripts/mods/" .. namespace .. "/"
        local function load(name) return assert(loadfile(prefix .. name .. ".lua"))() end
        local Fixture = assert(loadfile(root .. "/qa/lua/fixtures/wt_fire_sword_heat_network.lua"))()
        local Lookup, Contract = load("_lib_network_lookup"), load("_wt431_wire_contract")
        for _, priest_on in ipairs({ false, true }) do
            for _, heat_on in ipairs({ false, true }) do
                H.test(namespace .. " Priest/thermal real composition " .. tostring(priest_on) .. "/" .. tostring(heat_on), function()
                    local net = Fixture.network(load, Json)
                    local function install(mod, heavy, balance, deps, node)
                        local powers = { armor_modifier_linesman_H = deps.armor_reference }
                        local donor = { charge_value = "light_attack", default_target = {
                            power_distribution = { attack = 0.125, impact = 0.25 } }, targets = {
                            { power_distribution = { attack = 0.375, impact = 0.5 } } } }
                        node.profiles[SOURCE] = donor
                        node.profiles.shot_sniper = { default_target = {
                            power_distribution_near = { attack = 1, impact = 0.5 } },
                            cleave_distribution = { attack = 0.3, impact = 0.3 } }
                        H.equal(Lookup.register(node.lookup, SOURCE), 4)
                        H.equal(Lookup.register(node.lookup, "shot_sniper"), 5)
                        local punch = { damage_profile = SOURCE }
                        node.weapons[TEMPLATE] = { actions = { action_one = { punch = punch } } }
                        node.priest_punch, node.priest_donor = punch, donor
                        local environment = setmetatable({}, { __index = _G })
                        environment._G = environment
                        environment.get_mod = function(id)
                            if id == (namespace == "weapon_tweaker" and "wt" or "wt_dev") then return mod end
                        end
                        environment.Weapons, environment.DamageProfileTemplates = node.weapons, node.profiles
                        environment.NetworkLookup, environment.PowerLevelTemplates = { damage_profiles = node.lookup }, powers
                        environment.ALIVE = { [node.unit] = true }
                        environment.ScriptUnit = { has_extension = deps.extension }
                        environment.Managers = { player = { human_players = deps.humans } }
                        environment.Network = { peer_id = deps.local_peer }
                        environment.Application = { guid = deps.guid }
                        environment.AiUtils = { unit_breed = deps.breed }
                        environment.DamageUtils = node.classes.damage
                        environment.DamageUtils.get_breed_damage_multiplier_type = deps.multiplier
                        environment.ActionSweep, environment.ActionShieldSlam = node.classes.sweep, node.classes.slam
                        environment.ActionUtils, environment.GameNetworkManager = node.classes.utils, node.classes.network
                        environment.table = setmetatable({ clone = deps.clone }, { __index = table })
                        environment.printf = deps.log
                        mod._wt.dbg = function() end
                        mod.warning = function() end
                        mod.is_enabled = function() return node.enabled end
                        mod.get_name = function() return namespace == "weapon_tweaker" and "wt" or "wt_dev" end
                        mod._wt431_custom_profile_fallback = deps.fallbacks
                        mod.dofile = function(_, path)
                            local name = assert(path:match("/([%w_]+)$"))
                            local chunk = assert(loadfile(prefix .. name .. ".lua"))
                            setfenv(chunk, environment); return chunk()
                        end
                        local wire = { send_rpc_attack_hit = function(...) return ... end }
                        mod.hook = function(_, class, method, callback)
                            if class == "WeaponSystem" then
                                H.equal(method, "send_rpc_attack_hit"); class = wire
                            end
                            return deps.hook(class, method, callback)
                        end
                        mod.hook_safe = function(_, class, method, callback)
                            H.equal(class, "GameNetworkManager"); H.equal(method, "remove_peer")
                            deps.hook(node.classes.network, method, function(func, ...)
                                local result = pack(func(...)); callback(...); return unpack(result, 1, result.n)
                            end)
                        end
                        local before_native = clone(donor)
                        local source_powers = clone(powers)
                        -- Execute the entire actual balance owner at its real registration position.
                        local balance_chunk = assert(loadfile(prefix .. "_wt_weapon_balance_patches.lua"))
                        setfenv(balance_chunk, environment); balance_chunk()
                        H.equal(node.lookup.wt_authentic_pistol, 6)
                        H.equal(node.lookup[KEY], 7)
                        H.equal(node.lookup[7], KEY)
                        H.equal(punch.damage_profile, SOURCE, "no gate has been installed yet")
                        H.truthy(mod._wt428_priest_punch_owner.validate())
                        local profile = node.profiles[KEY]
                        H.equal(profile.default_target.power_distribution.attack, 0.25)
                        H.equal(profile.default_target.power_distribution.impact, 0.75)
                        H.equal(profile.targets[1].power_distribution.attack, 0.75)
                        H.equal(profile.targets[1].power_distribution.impact, 1.5)
                        local prefix_rows, prefix_fallback = clone(node.lookup), clone(deps.fallbacks)
                        local prefix_profile = clone(profile)
                        local prefix_identity = assert(Contract.build_wire_identity(prefix_fallback, node.lookup, node.profiles))
                        local prefix_catalog = assert(Contract.capture_catalog(prefix_fallback, node.lookup, node.profiles))
                        -- Use the actual thermal installer DEFAULT dependencies, not a synthetic gate.
                        local owner_chunk = assert(loadfile(prefix .. "_wt_fire_sword_owner.lua"))
                        setfenv(owner_chunk, environment)
                        local owner = owner_chunk().install(mod, heavy, balance)
                        H.equal(owner.prepared, true); H.equal(owner.committed, false)
                        H.truthy(node.lookup.wt942_direct_direct > 7, "thermal append must follow Priest")
                        for key, value in next, prefix_rows do H.equal(rawget(node.lookup, key), value, "existing numeric/reverse prefix") end
                        H.deep_equal(node.profiles[KEY], prefix_profile)
                        H.deep_equal(donor, before_native); H.deep_equal(powers, source_powers)
                        H.equal(Contract.build_wire_identity(prefix_fallback, node.lookup, node.profiles), prefix_identity)
                        H.deep_equal(Contract.capture_catalog(prefix_fallback, node.lookup, node.profiles), prefix_catalog)
                        node.composition_prefix_identity = prefix_identity
                        node.composition_environment = environment
                        node.composition_finalized = 0
                        local finish = owner.finish_install
                        owner.finish_install = function(current)
                            H.equal(mod._wt_peer_parity:is_installed(), true)
                            H.equal(mod._wt431_disconnect_epoch_guard, true)
                            H.equal(mod._wt431_wire_floor_installed, true)
                            H.equal(mod._wt431_parity_gated, true)
                            H.equal(mod._wt_peer_parity:feature_count(), 1)
                            node.composition_finalized = node.composition_finalized + 1
                            return finish(current)
                        end
                        return owner
                    end
                    local function options()
                        return { prepare_only = true, install = install, mod_setup = function(_, node)
                            node.settings.wt_priest_punch_buff = priest_on
                            node.settings.wt_fire_sword_heat = heat_on
                        end }
                    end
                    local a, b = net:add("host", options()), net:add("client", options())
                    for _, node in ipairs({ a, b }) do
                        local chunk = assert(loadfile(prefix .. "_wt431_damage_profile_parity.lua"))
                        setfenv(chunk, node.composition_environment)
                        H.equal(type(chunk()), "table", "the complete actual catalog module must return")
                        H.equal(node.composition_finalized, 1)
                        H.equal(node.owner.committed, true)
                        node.catalog_identity = node.mod._wt431_wire_catalog_identity
                    end
                    H.equal(a.composition_prefix_identity, b.composition_prefix_identity)
                    net:connect("host", "client"); net:settle()
                    for _, node in ipairs({ a, b }) do
                        H.equal(node.mod._wt431_profiles_allowed(), true)
                        H.equal(node.priest_punch.damage_profile, priest_on and KEY or SOURCE)
                        H.equal(node:damage(node.profiles.wt942_direct_direct), heat_on and 13 or 10)
                        H.equal(node.mod._wt428_priest_punch_owner.validate(), true)
                        H.equal(node.lookup[KEY], 7)
                    end
                    a.on_join = function(id)
                        H.equal(id, "late")
                        H.equal(a.mod._wt_peer_parity:applied_state(), "disabled")
                        H.equal(a.priest_punch.damage_profile, SOURCE, "existing Priest gate closes before native join")
                        H.equal(a:damage(a.profiles.wt942_direct_direct), 10)
                    end
                    a.classes.network.hot_join_sync({}, "late")
                    a.classes.network.remove_peer({}, "late")
                    H.equal(a.owner.transport.pending.late, nil)
                end)
            end
        end
    end
end
