-- Closed reciprocal one-handed Sword family. All construction dependencies are
-- private values from the actual entry/core handoff. No hook, RPC, package,
-- native mesh/scale/grip write, lazy reconstruction or saved-style mutation.
local M = {}
local FAMILY = "one_handed_swords"
local EMPIRE, ELVEN = "one_handed_swords_template_1", "we_one_hand_sword_template_1"
local RESOURCE = "units/beings/player/first_person_base/state_machines/melee/1h_sword"
local DIRECTIONS = {
    { id = "empire_on_elf", donor = EMPIRE, key = "we_1h_sword", style = "empire",
        template = "cwv_645_empire_sword_style" },
    { id = "elven_on_empire", donor = ELVEN, key = "es_1h_sword", style = "elven",
        template = "cwv_645_elven_sword_style" },
}
-- Derived from the sealed23-node/110-row source matrix (b74d5914...), not an
-- event-only inverse dictionary. Repeated native chain rows remain untouched;
-- each unique predecessor gets the same authored target. Empire H1/H3 differs
-- ONLY when the previous action is action_one.default_left.
-- Tuple: group, node, kind, 1P event, 3P base, native anim_end_event, incoming.
-- Each incoming tuple is previous group, previous node, selected3P event.
local ROUTES = {
    empire_on_elf = {
        { "action_one", "default", "melee_start", "attack_swing_charge_left", "attack_swing_charge_down", "attack_finished", {
            { "action_one", "heavy_attack_left", "attack_swing_charge_down" },
            { "action_one", "heavy_attack_right", "attack_swing_charge_down" },
            { "action_one", "light_attack_left", "attack_swing_charge_down" },
            { "action_one", "light_attack_right", "attack_swing_charge_down" },
            { "action_one", "light_attack_last", "attack_swing_charge_down" },
            { "action_one", "light_attack_bopp", "attack_swing_charge_down" },
            { "action_one", "push", "attack_swing_charge_down" },
            { "action_two", "default", "attack_swing_charge_down" },
        } },
        { "action_one", "default_right", "melee_start", "attack_swing_charge_right_pose", "attack_swing_charge_right_diagonal_pose", "attack_finished", {
            { "action_one", "heavy_attack_left", "attack_swing_charge_right_diagonal_pose" },
            { "action_one", "light_attack_left", "attack_swing_charge_right_diagonal_pose" },
        } },
        { "action_one", "default_left", "melee_start", "attack_swing_charge_left_pose", "attack_swing_charge_left", "attack_finished", {
            { "action_one", "heavy_attack_right", "attack_swing_charge_left" },
            { "action_one", "light_attack_right", "attack_swing_charge_left" },
            { "action_one", "light_attack_bopp", "attack_swing_charge_left" },
        } },
        { "action_one", "heavy_attack_left", "sweep", "attack_swing_heavy", "attack_swing_heavy_down", "attack_finished", {
            { "action_one", "default", "attack_swing_heavy_down" },
            { "action_one", "default_left", "attack_swing_heavy_left_up" },
        } },
        { "action_one", "heavy_attack_right", "sweep", "attack_swing_heavy_right", "attack_swing_heavy_down_right", "attack_finished", {
            { "action_one", "default_right", "attack_swing_heavy_down_right" },
        } },
        { "action_one", "light_attack_left", "sweep", "attack_swing_left_diagonal", "attack_swing_left_diagonal", "attack_finished", {
            { "action_one", "default", "attack_swing_left_diagonal" },
        } },
        { "action_one", "light_attack_right", "sweep", "attack_swing_right", "attack_swing_right_diagonal", "attack_finished", {
            { "action_one", "default_right", "attack_swing_right_diagonal" },
        } },
        { "action_one", "light_attack_last", "sweep", "attack_swing_down", "attack_swing_stab", "attack_finished", {
            { "action_one", "default_left", "attack_swing_stab" },
        } },
        { "action_one", "light_attack_bopp", "sweep", "attack_swing_right_diagonal", "attack_swing_left", "attack_finished", {
            { "action_one", "push", "attack_swing_left" },
        } },
        { "action_one", "push", "push_stagger", "attack_push", "attack_push", "attack_finished", {
            { "action_two", "default", "attack_push" },
        } },
        { "action_two", "default", "block", "parry_pose", "parry_pose", "parry_finished", {
            { "action_one", "default", "parry_pose" },
            { "action_one", "default_right", "parry_pose" },
            { "action_one", "default_left", "parry_pose" },
            { "action_one", "heavy_attack_left", "parry_pose" },
            { "action_one", "heavy_attack_right", "parry_pose" },
            { "action_one", "light_attack_left", "parry_pose" },
            { "action_one", "light_attack_right", "parry_pose" },
            { "action_one", "light_attack_last", "parry_pose" },
            { "action_one", "light_attack_bopp", "parry_pose" },
            { "action_one", "push", "parry_pose" },
        } },
    },
    elven_on_empire = {
        { "action_one", "default", "melee_start", "attack_swing_charge_down", "attack_swing_charge_left_diagonal", "attack_finished", {
            { "action_one", "heavy_attack_right", "attack_swing_charge_left_diagonal" },
            { "action_one", "light_attack_left", "attack_swing_charge_left_diagonal" },
            { "action_one", "light_attack_right", "attack_swing_charge_left_diagonal" },
            { "action_one", "light_attack_last", "attack_swing_charge_left_diagonal" },
            { "action_one", "light_attack_bopp", "attack_swing_charge_left_diagonal" },
            { "action_one", "push", "attack_swing_charge_left_diagonal" },
            { "action_two", "default", "attack_swing_charge_left_diagonal" },
        } },
        { "action_one", "default_right", "melee_start", "attack_swing_charge_right_diagonal_pose", "attack_swing_charge_left_diagonal", "attack_finished", {
            { "action_one", "heavy_attack_up", "attack_swing_charge_left_diagonal" },
            { "action_one", "light_attack_left", "attack_swing_charge_left_diagonal" },
            { "action_one", "light_attack_bopp", "attack_swing_charge_left_diagonal" },
        } },
        { "action_one", "default_left", "melee_start", "attack_swing_charge_left", "attack_swing_charge_right_pose", nil, {
            { "action_one", "heavy_attack_left", "attack_swing_charge_right_pose" },
            { "action_one", "light_attack_right", "attack_swing_charge_right_pose" },
        } },
        { "action_one", "heavy_attack_left", "sweep", "attack_swing_heavy_down", "attack_swing_heavy_down", "attack_finished", {
            { "action_one", "default", "attack_swing_heavy_down" },
        } },
        { "action_one", "heavy_attack_right", "sweep", "attack_swing_heavy_down_right", "attack_swing_heavy_down", "attack_finished", {
            { "action_one", "default_right", "attack_swing_heavy_down" },
        } },
        { "action_one", "heavy_attack_up", "sweep", "attack_swing_heavy_left_up", "attack_swing_heavy_right", "attack_finished", {
            { "action_one", "default_left", "attack_swing_heavy_right" },
        } },
        { "action_one", "light_attack_left", "sweep", "attack_swing_left_diagonal", "attack_swing_left_diagonal", "attack_finished", {
            { "action_one", "default", "attack_swing_left_diagonal" },
        } },
        { "action_one", "light_attack_right", "sweep", "attack_swing_right_diagonal", "attack_swing_right_diagonal", "attack_finished", {
            { "action_one", "default_right", "attack_swing_right_diagonal" },
        } },
        { "action_one", "light_attack_last", "sweep", "attack_swing_stab", "attack_swing_down", "attack_finished", {
            { "action_one", "default_left", "attack_swing_down" },
        } },
        { "action_one", "light_attack_bopp", "sweep", "attack_swing_left", "attack_swing_left", "attack_finished", {
            { "action_one", "push", "attack_swing_left" },
        } },
        { "action_one", "push", "push_stagger", "attack_push", "attack_push", "attack_finished", {
            { "action_two", "default", "attack_push" },
        } },
        { "action_two", "default", "block", "parry_pose", "parry_pose", "parry_finished", {
            { "action_one", "default", "parry_pose" },
            { "action_one", "default_right", "parry_pose" },
            { "action_one", "default_left", "parry_pose" },
            { "action_one", "heavy_attack_left", "parry_pose" },
            { "action_one", "heavy_attack_right", "parry_pose" },
            { "action_one", "heavy_attack_up", "parry_pose" },
            { "action_one", "light_attack_left", "parry_pose" },
            { "action_one", "light_attack_right", "parry_pose" },
            { "action_one", "light_attack_last", "parry_pose" },
            { "action_one", "light_attack_bopp", "parry_pose" },
            { "action_one", "push", "parry_pose" },
        } },
    },
}

local function decorate(template, direction)
    local routes = assert(ROUTES[direction], "#645 route direction missing")
    local actions = assert(rawget(template, "actions"), "#645 route actions missing")
    for _, route in ipairs(routes) do
        local group = rawget(actions, route[1])
        local node = type(group) == "table" and rawget(group, route[2])
        assert(type(node) == "table" and getmetatable(node) == nil
            and rawget(node, "kind") == route[3] and rawget(node, "anim_event") == route[4]
            and rawget(node, "anim_end_event") == route[6]
            and rawget(node, "anim_event_3p") == nil
            and rawget(node, "anim_event_from_chain") == nil, "#645 donor3P selector source drift")
        local from = {}
        for _, incoming in ipairs(route[7]) do
            local previous = from[incoming[1]]
            if previous == nil then previous = {}; from[incoming[1]] = previous end
            assert(previous[incoming[2]] == nil, "#645 duplicate predecessor")
            previous[incoming[2]] = { anim_event_3p = incoming[3] }
        end
        rawset(node, "anim_event_3p", route[5])
        rawset(node, "anim_event_from_chain", from)
    end
    return template
end
function M.install(mod, ctx)
    local policy, graph = assert(ctx.policy), assert(ctx.graph)
    local _rt_register = assert(ctx.rt_register)
    local families = assert(policy.FAMILIES)
    local catalogue = assert(rawget(families, FAMILY), "#645 authored Sword catalogue missing")
    local styles, members = assert(catalogue.styles), assert(catalogue.members)
    local empire, elven = assert(styles.empire), assert(styles.elven)
    local empire_member, elf_member = assert(members.es_1h_sword), assert(members.we_1h_sword)
    local empire_order = assert(empire_member.order)
    local catalogue_meta, styles_meta, members_meta = getmetatable(catalogue), getmetatable(styles), getmetatable(members)
    local empire_meta, order_meta = getmetatable(empire_member), getmetatable(empire_order)
    -- Only published reciprocal Sword-owned rows are sealed here. Mace owns its
    -- own row/order/construction and must not poison these two directions.
    local catalogue_snapshot = assert(graph.capture({ empire, elven, elf_member }, 64, 512),
        "#645 Sword catalogue unbounded")
    local package_for, member_for, style_for = policy.package, policy.member, policy.style
    local owner, constructors = {}, {}
    local donor = mod:dofile("scripts/mods/character_weapon_variants/_cwv_sword_donor_envelope").bind(
        graph, ctx.career, ctx.core.history_producer_binding,
        ctx.career_actions, ctx.action_templates)
    local factory = mod:dofile("scripts/mods/character_weapon_variants/_cwv_sword_style_construction").bind(
        ctx.network_lookup, graph, donor)
    -- Serial construction is essential: each private scalar planner captures
    -- its own live audit preimage AFTER the preceding direction commits.
    for _, spec in ipairs(DIRECTIONS) do
        local constructor = factory({
            direction = spec.id, state = ctx.om, scalar_factory = ctx.core.detached_scalar_factory,
            profiles = ctx.profiles, power_levels = ctx.power_levels,
            lookup = ctx.lookup, weapons = ctx.weapons,
            clone = function(source)
                local result = ctx.clone(source)
                if rawequal(source, rawget(ctx.weapons(), spec.donor)) then
                    -- BEFORE the frozen constructor captures the prepared graph.
                    decorate(result, spec.id)
                end
                return result
            end,
        })
        constructors[spec.id] = constructor
        constructor.construct()
    end
    local mace = ctx.mace_factory and ctx.mace_factory(ctx, donor) or nil
    function owner.before_style_commit(row, desired)
        if mace then return mace:before_style_commit(row, desired) end
    end
    function owner:install_mace_runtime(...)
        if mace then return mace:install_runtime(...) end
    end
    local function catalogue_intact()
        return rawequal(policy.FAMILIES, families) and rawget(families, FAMILY) == catalogue
            and rawequal(catalogue.styles, styles) and rawequal(catalogue.members, members)
            and rawequal(styles.empire, empire) and rawequal(styles.elven, elven)
            and rawequal(members.es_1h_sword, empire_member) and rawequal(members.we_1h_sword, elf_member)
            and empire_member.default == "empire" and rawequal(empire_member.order, empire_order)
            and empire_order[1] == "empire" and empire_order[2] == "elven"
            and rawequal(getmetatable(catalogue), catalogue_meta) and rawequal(getmetatable(styles), styles_meta)
            and rawequal(getmetatable(members), members_meta) and rawequal(getmetatable(empire_member), empire_meta)
            and rawequal(getmetatable(empire_order), order_meta)
            and policy.package == package_for and policy.member == member_for
            and policy.style == style_for and graph.intact(catalogue_snapshot)
    end
    local function weapons_now()
        local ok, value = pcall(ctx.weapons)
        if ok and type(value) == "table" then return value end
        return nil
    end
    local function retained_package(key, selected)
        if not catalogue_intact() then return nil end
        local weapons = weapons_now()
        if weapons == nil then return nil end
        local member = rawget(catalogue.members, key)
        if not member then return nil end
        local chosen = rawget(catalogue.styles, selected) and selected or member.default
        if chosen == "mace" then
            if mace then return mace:package(key, chosen) end
            return nil
        end
        local package = package_for(key, chosen)
        if type(package) ~= "table" or package.family_id ~= FAMILY
            or package.style_id ~= chosen or package.member ~= member
            or package.style ~= rawget(catalogue.styles, chosen)
            or package.resource ~= RESOURCE then return nil end
        if chosen == member.default then
            -- Native restoration is the ACTUAL live donor, including legitimate
            -- WT history/#348. It never writes captured Current over that donor.
            local name = key == "es_1h_sword" and EMPIRE or ELVEN
            local value = rawget(weapons, name)
            if package.template ~= name or type(value) ~= "table" then return nil end
            return name, value
        end
        local selected_name, selected_value
        for _, spec in ipairs(DIRECTIONS) do
            local name, value = constructors[spec.id].template(spec.id)
            if name ~= spec.template or type(value) ~= "table"
                or not rawequal(rawget(weapons, name), value) then return nil end
            if key == spec.key and chosen == spec.style then
                if package.template ~= name then return nil end
                selected_name, selected_value = name, value
            end
        end
        -- A reciprocal family is not exposed as one successful half. Native
        -- restoration above remains independent when either custom half drifts.
        return selected_name, selected_value
    end
    local function check()
        if not catalogue_intact() then return "#645 reciprocal Sword catalogue drifted" end
        if weapons_now() == nil then return "#645 reciprocal Sword registry unavailable" end
        for _, spec in ipairs(DIRECTIONS) do
            local name, value = retained_package(spec.key, spec.style)
            if name ~= spec.template or type(value) ~= "table" then
                return "#645 reciprocal Sword construction unavailable: " .. spec.id
            end
        end
    end
    function owner:package(key, selected) return retained_package(key, selected) end
    function owner:check() return check() end
    _rt_register("issue645_reciprocal_one_handed_sword_family", check)
    return owner
end
return M
