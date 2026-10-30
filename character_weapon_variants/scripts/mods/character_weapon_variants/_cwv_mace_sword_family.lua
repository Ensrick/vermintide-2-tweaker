-- _cwv_mace_sword_family.lua -- Mace admission independent of reciprocal Sword.
-- #645 Mace is a separate retained failure domain, not a third reciprocal
-- Sword constructor. The entry binds every private module once by value.
-- Owned by: character_weapon_variants.lua. Consumed via its Sword family owner.
local M = {}
local KEY, STYLE = "es_1h_sword", "mace"
local TEMPLATE, DIRECTION = "cwv_645_mace_sword_style", "mace_on_empire_sword"
local RESOURCE = "units/beings/player/first_person_base/state_machines/melee/1h_hammer"
local REFERENCE = "cwv_mace_sword_fp"
function M.bind(envelope_module, construction_module, runtime_module, movement_module)
    local envelope_bind, construction_bind = envelope_module.bind, construction_module.bind
    local runtime_install = runtime_module.install
    local movement_bind = movement_module.bind
    return function(ctx, sword_donor)
        local owner, constructor, runtime_owner, runtime_snapshot, lease_map = {}
        local failure, catalogue_snapshot, catalogue, families, members, member, styles, style, order
        local catalogue_meta, families_meta, styles_meta, members_meta
        local policy, graph = ctx.policy, ctx.graph
        local package_for, member_for, style_for = policy.package, policy.member, policy.style
        local function catalogue_intact()
            return catalogue_snapshot and rawequal(policy.FAMILIES, families)
                and rawequal(rawget(families, "one_handed_swords"), catalogue)
                and rawequal(rawget(catalogue, "styles"), styles)
                and rawequal(rawget(catalogue, "members"), members)
                and rawequal(rawget(styles, STYLE), style)
                and rawequal(rawget(members, KEY), member) and rawequal(member.order, order)
                and rawequal(getmetatable(catalogue), catalogue_meta)
                and rawequal(getmetatable(families), families_meta)
                and rawequal(getmetatable(styles), styles_meta)
                and rawequal(getmetatable(members), members_meta)
                and policy.package == package_for and policy.member == member_for
                and policy.style == style_for and graph.intact(catalogue_snapshot)
        end
        local function resident(managers)
            local packages = managers and managers.package
            return type(packages) == "table" and type(packages.has_loaded) == "function"
                and type(lease_map) == "table"
                and rawequal(rawget(ctx.om, "_dual_weapon_fp_residency_held"), lease_map)
                and rawget(lease_map, RESOURCE) == true
                and packages:has_loaded(RESOURCE, REFERENCE) == true
        end
        local managers_for
        local function retained_template()
            if failure or not catalogue_intact() or not constructor then return nil end
            local name, value = constructor.template(DIRECTION)
            local ok, weapons = pcall(ctx.weapons)
            if not ok or name ~= TEMPLATE or type(value) ~= "table"
                    or type(weapons) ~= "table" or not rawequal(rawget(weapons, name), value) then return nil end
            return name, value
        end
        local function runtime_intact()
            return runtime_owner and runtime_snapshot and graph.intact(runtime_snapshot)
                and runtime_owner:check() == nil
        end
        function owner:package(key, selected)
            if key ~= KEY or selected ~= STYLE or not runtime_intact() then return nil end
            local ok, loaded = pcall(function() return resident(managers_for()) end)
            if not ok or not loaded then return nil end
            local package = package_for(key, selected)
            if type(package) ~= "table" or package.style_id ~= STYLE
                    or package.template ~= TEMPLATE or package.resource ~= RESOURCE
                    or not rawequal(package.member, member) or not rawequal(package.style, style) then return nil end
            return retained_template()
        end
        function owner:before_style_commit(row, desired)
            if runtime_intact() then return runtime_owner:before_style_commit(row, desired) end
        end
        function owner:install_runtime(runtime_mod, runtime, actor, helper, units, script, managers)
            if runtime_owner or failure then return nil end
            lease_map = rawget(ctx.om, "_dual_weapon_fp_residency_held")
            if type(lease_map) ~= "table" then failure = "#645 Mace586 owner disconnected"; return nil end
            managers_for = managers
            local ok, result = pcall(runtime_install, runtime_mod, {
                runtime = runtime, actor = actor, constructor = constructor,
                helper = helper, units = units, script = script, managers = managers,
                movement_bind = movement_bind, weapons = ctx.weapons,
            })
            if not ok or type(result) ~= "table" then
                failure = "#645 Mace runtime install failed: " .. tostring(result)
                return nil
            end
            runtime_owner = result
            runtime_snapshot = graph.capture(runtime_owner, 32, 256)
            if not runtime_snapshot then
                failure = "#645 Mace runtime owner unbounded"
                runtime_owner:set_enabled(false)
                return nil
            end
            runtime_owner:set_enabled(true)
            return runtime_owner
        end
        function owner:check()
            if failure then return failure end
            if not retained_template() then return "#645 Mace retained construction unavailable" end
            if not runtime_intact() then return "#645 Mace runtime owner disconnected" end
            local ok, loaded = pcall(function() return resident(managers_for()) end)
            if not ok or not loaded then return "#645 Mace first-person resource unavailable" end
        end
        -- A missing/unknown #599 owner remains closed. Never recapture it on
        -- selection and never repair native templates or the published Sword pair.
        local ok, result = pcall(function()
            families = assert(policy.FAMILIES)
            catalogue = assert(rawget(families, "one_handed_swords"))
            styles, members = assert(catalogue.styles), assert(catalogue.members)
            style, member = assert(styles.mace), assert(members[KEY])
            catalogue_meta, families_meta = getmetatable(catalogue), getmetatable(families)
            styles_meta, members_meta = getmetatable(styles), getmetatable(members)
            order = assert(member.order)
            assert(#order == 3 and order[1] == "empire" and order[2] == "elven"
                and order[3] == STYLE and member.default == "empire", "Mace member order drift")
            assert(catalogue.members.we_1h_sword.order[3] == nil, "Mace leaked to Elf order")
            local package = assert(package_for(KEY, STYLE))
            assert(package.template == TEMPLATE and package.resource == RESOURCE, "Mace row drift")
            catalogue_snapshot = assert(graph.capture({ style = style, member = member }, 64, 512))
            local envelope = envelope_bind(graph, ctx.career, ctx.core.history_producer_binding,
                ctx.career_actions, ctx.action_templates, function()
                    return ctx.om.mace_hammer_identity, ctx.om.mace_hammer_identity_policy
                end, sword_donor)
            local factory = construction_bind(ctx.network_lookup, graph, envelope)
            constructor = factory({
                direction = DIRECTION, state = ctx.om, scalar_factory = ctx.core.detached_scalar_factory,
                profiles = ctx.profiles, power_levels = ctx.power_levels, lookup = ctx.lookup,
                weapons = ctx.weapons, clone = ctx.clone,
            })
            assert(constructor.construct() == true, constructor.check() or "Mace construction refused")
            assert(retained_template() ~= nil, "Mace retained construction refused")
        end)
        if not ok then failure = "#645 Mace construction unavailable: " .. tostring(result) end
        ctx.rt_register("issue645_mace_on_kruber_sword_family", function() return owner:check() end)
        return owner
    end
end
return M
