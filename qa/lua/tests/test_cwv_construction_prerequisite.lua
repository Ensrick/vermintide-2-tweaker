-- #428 prerequisite: actual core/owner equivalence across new private seams.
-- Complete tracked historical producers are required by the actual old/new oracle.
-- Missing references fail; outside review paths/globals are not test authority.
return function(H, root)
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local T = dofile(root .. "/qa/lua/tests/test_cwv_old_musket_shot_owner.lua")(quiet, root)
    local prefix = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local old_core = T.read(root .. "/qa/lua/fixtures/cwv_construction_prerequisite_prior_core.lua")
    local old_owner = T.read(root .. "/qa/lua/fixtures/cwv_construction_prerequisite_prior_melee.lua")
    local function clone(value)
        if type(value) ~= "table" then return value end
        local result = {}; for key, item in pairs(value) do result[key] = clone(item) end
        return result
    end
    local function audit_state(check)
        for index = 1, 20 do
            local name, value = debug.getupvalue(check, index)
            if not name then break end
            if name == "multiplier_audit" then return clone(value) end
        end
        error("actual audit ledger upvalue missing")
    end
    local function scalar_context(source, representation, detached)
        local levels = {
            cleave = { attack = 2, impact = 4 },
            default = { power_distribution = { attack = 10, impact = 20 } },
            targets = { [2] = { power_distribution = { attack = 5, impact = 7 } },
                [5] = { power_distribution = { attack = 0, impact = 0 } } },
            critical = { power_distribution = { attack = 3, impact = 4 } },
        }
        local profile = {
            charge_value = "light_attack", cleave_distribution = clone(levels.cleave),
            default_target = clone(levels.default), targets = clone(levels.targets),
            critical_strike = clone(levels.critical),
            armor_modifier = { attack = { 1, 0.5 }, impact = { 1, 1 } },
            untouched = { metadata = true },
        }
        if representation == "legacy" then
            profile.cleave_distribution, profile.default_target = "cleave", "default"
            profile.targets, profile.critical_strike = "targets", "critical"
        elseif representation == "mixed" then profile.cleave_distribution = "cleave" end
        local profiles, lookup, events = { source = profile }, {}, {}
        local om = { combat_style_policy = {},
            _record_cwv_dp_source = function(name, donor) events[#events + 1] = { name, donor } end }
        local env = setmetatable({ table = setmetatable({ clone = clone }, { __index = table }) }, { __index = _G })
        local owner = T.run(source, env, "actual-core-before-or-after")({ warning=function() end, info=function() end }, {
            om=om, Weapons={}, ItemMasterList={}, DamageProfileTemplates=profiles,
            PowerLevelTemplates=levels, NetworkLookup={damage_profiles=lookup}, printf=function() end,
        })
        local make, check = owner.clone_damage_profile, om._cwv_profile_multiplier_check
        if detached then
            local live_profiles, live_lookup, live_events = profiles, lookup, events
            profiles, lookup, events = clone(profiles), {}, {}
            levels = clone(levels)
            local options = { profiles=profiles, power_levels=levels,
                record_source=function(name, donor) events[#events + 1] = { name, donor } end,
                register=function(name, value)
                    profiles[name] = value
                    if not rawget(lookup, name) then
                        local index = #lookup + 1; rawset(lookup,index,name); rawset(lookup,name,index)
                    end
                    return true
                end }
            local planner = assert(owner.detached_scalar_factory)(options)
            options.record_source, options.register = function() error("mutable source dependency used") end,
                function() error("mutable publication dependency used") end
            make, check = planner.clone_damage_profile, planner.check
            H.equal(next(live_lookup), nil); H.equal(#live_events, 0)
            H.equal(live_profiles.cwv_probe_source, nil)
        end
        if representation == "cached" then profiles.cwv_probe_source = clone(profile) end
        for _ = 1, 2 do H.equal(make("source","cwv_probe_",{damage=2,stagger=3,cleave=1.5}),"cwv_probe_source") end
        H.equal(make("absent","cwv_probe_",{damage=2}),"absent")
        return { profiles=profiles, lookup=lookup, levels=levels, events=events,
            verdict=check(), audit=audit_state(check), live_audit=audit_state(om._cwv_profile_multiplier_check) }
    end
    for _, kind in ipairs({ "resolved", "legacy", "mixed", "cached" }) do
        local representation = kind
        H.test("#428 prerequisite actual core live detached equivalence " .. kind, function()
            local before = scalar_context(old_core, representation, false)
            local after = scalar_context(T.read(prefix .. "_cwv_core_templates.lua"), representation, false)
            H.deep_equal(after, before, "ordinary live helper and audit remain exact")
            local planned = scalar_context(T.read(prefix .. "_cwv_core_templates.lua"), representation, true)
            planned.live_audit = before.live_audit
            H.deep_equal(planned, before, "same actual math/audit with detached registries")
            local isolated = scalar_context(T.read(prefix .. "_cwv_core_templates.lua"), representation, true)
            H.equal(isolated.live_audit.profiles, 0, "detached planning never mutates live audit")
            H.equal(isolated.live_audit.comparisons, 0)
        end)
    end
    local function installed(before, edge, mutate_bound_functions)
        return T.installed(function(c)
            local original = c.mod.dofile
            c.mod.dofile = function(self, path)
                local value
                if before and path:match("/_cwv_old_musket_melee_owner$") then
                    value = T.run(old_owner, c.env, "immutable-before-melee-owner")
                else value = original(self,path) end
                if path:match("/_cwv_old_musket_melee_owner$") then
                    local bind = value.bind
                    return { bind=function(helper, mechanics, sweep_guard_factory)
                        local make = bind(helper,mechanics,sweep_guard_factory)
                        if mutate_bound_functions then
                            for _, name in ipairs({"capture","intact","disjoint","commit"}) do
                                mechanics[name] = function() error("mutable graph dependency used") end
                            end
                        end
                        return function(options)
                            local write, done = rawset, false
                            options.write = function(t,k,v,tag)
                                write(t,k,v)
                                if not done and edge=="intervening" and tag:find("profile:",1,true)==1 then
                                    done=true; rawset(c.state,"_cwv_damage_profile_generation",99)
                                elseif tag=="numeric:heavy_slashing_tank" and edge=="write" then error("actual seam write rejection") end
                            end
                            if edge=="readback" then options.read=function(t,k,tag)
                                if tag=="template" then return false end; return rawget(t,k)
                            end end
                            local owner = make(options); c.prerequisite_owner=owner
                            if before then
                                -- Historical comparison is construction-only:
                                -- this immutable owner predates retained hooks.
                                -- Its exact old constructor/math still executes;
                                -- no retained-runtime acceptance uses this shim.
                                owner.install_sweep_guard = function() return false end
                                owner.runtime_admitted = owner.ready
                                owner.register_sweep_check = function() end
                            end
                            return owner
                        end
                    end }
                end
                return value
            end
        end)
    end
    local function comparable(value)
        if type(value)=="function" then return "<callback tested by existing whole-installer oracle>" end
        if type(value)~="table" then return value end
        local result={}; for key,item in pairs(value) do result[key]=comparable(item) end; return result
    end
    local function outcome(c)
        return { profiles=c.env.DamageProfileTemplates, lookup=c.lookup,
            map=c.state._cwv_damage_profile_wire_source, generation=c.state._cwv_damage_profile_generation,
            fallback=c.state._cwv_wire_fallback_profile_id,
            template=comparable(c.env.Weapons.old_musket_template_melee),
            ready=c.prerequisite_owner.ready(), verdict=c.capsule.check_old_musket() }
    end
    for _, name in ipairs({"healthy","write","readback","intervening"}) do
        local edge=name
        H.test("#428 prerequisite actual Musket before after " .. edge, function()
                local before,after=installed(true,edge),installed(false,edge)
                H.deep_equal(outcome(after),outcome(before),"actual owner outcomes unchanged")
                if edge=="intervening" then
                    H.equal(after.state._cwv_damage_profile_generation,99,"foreign generation survives stale-cell rejection")
                    H.equal(after.env.DamageProfileTemplates.cwv_old_musket_melee_heavy_slashing_tank,nil)
                end
                if edge=="healthy" then
                    after.lookup.cwv_old_musket_melee_heavy_slashing_tank=nil
                    before.lookup.cwv_old_musket_melee_heavy_slashing_tank=nil
                    H.deep_equal(outcome(after),outcome(before),"retained authority loss remains fail closed")
                    H.equal(after.prerequisite_owner.ready(),false)
                end
            end)
    end
    H.test("#428 prerequisite graph function references captured before public module mutation",function()
        local c=installed(false,"healthy",true)
        H.truthy(c.prerequisite_owner.ready()); H.equal(c.capsule.check_old_musket(),nil)
    end)
    H.test("#428 prerequisite entry owns shared mechanics and private scalar capsule",function()
        local entry=T.read(prefix.."character_weapon_variants.lua")
        local kernel=T.read(prefix.."_cwv_profile_graph_transaction.lua")
        local owner=T.read(prefix.."_cwv_old_musket_melee_owner.lua")
        local function count(s,n) local _,x=s:gsub(n:gsub("([^%w])","%%%1"),"");return x end
        H.equal(count(entry,'mod:dofile("scripts/mods/character_weapon_variants/_cwv_profile_graph_transaction")'),1)
        H.equal(count(kernel,"mod:dofile"),1,"only required header mentions the entry load")
        H.equal(count(kernel,"mod:hook"),0)
        H.truthy(kernel:find("-- Owned by:",1,true)); H.truthy(kernel:find("-- Consumed via:",1,true))
        H.equal(count(owner,"local function capture("),0); H.equal(count(owner,"local function rollback("),0)
        H.truthy(owner:find("captured[name] = value",1,true))
        H.truthy(entry:find("local _core_template_construction = mod:dofile(",1,true))
        H.truthy(entry:find("local _clone_damage_profile = _core_template_construction.clone_damage_profile",1,true))
        H.equal(count(entry,"detached_scalar_factory"),1,"one private Javelin consumer binding")
    end)
end
