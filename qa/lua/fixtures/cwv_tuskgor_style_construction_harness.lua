-- Actual-source Tuskgor construction/bootstrap fixture; no native corpus copy.
-- Existing required Old Musket harness supplies the real private core handoff.
local M = {}
local P = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
M.key, M.prefix = "cwv_645_tuskgor_spear_style", "cwv_645_tuskgor_spear_"
M.donor, M.receiver = "two_handed_heavy_spears_template", "two_handed_spears_elf_template_1"
M.names = { "heavy_slashing_tank", "heavy_slashing_smiter_stab_polearm", "medium_spear_smiter_stab",
    "medium_slashing_linesman_spear", "medium_push", "light_push" }
M.attacks = { "default", "default_left", "default_last_1", "default_last_2", "heavy_attack_tank",
    "heavy_attack_left", "light_attack_left", "light_attack_right", "light_attack_stab_1", "light_attack_stab_2", "light_attack_bopp" }
-- These exact literal list members come from the eleven pinned DLC settings
-- statements, not a claim about a player's loaded/owned DLCSettings global.
local DLC = {
    { "anvil", "scripts/settings/equipment/damage_profile_templates_dlc_anvil" },
    { "carousel", "scripts/settings/equipment/damage_profile_templates_dlc_vs" },
    { "belladonna", "scripts/settings/equipment/damage_profile_templates_scorpion" },
    { "bless", "scripts/settings/equipment/damage_profile_templates_dlc_bless" },
    { "cog", "scripts/settings/equipment/damage_profile_templates_dlc_cog" },
    { "mutators_batch_01", "scripts/settings/equipment/damage_profile_templates_dlc_mutators_batch_01" },
    { "mutators_batch_02", "scripts/settings/equipment/damage_profile_templates_dlc_mutators_batch_02" },
    { "lake", "scripts/settings/equipment/damage_profile_templates_dlc_lake" },
    { "shovel", "scripts/settings/equipment/damage_profile_templates_dlc_shovel" },
    { "woods", "scripts/settings/equipment/damage_profile_templates_dlc_woods" },
    { "morris", "scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris" },
}
local function between(source, first, following)
    local a = assert(source:find(first, 1, true), "exact native begin missing")
    assert(not source:find(first, a + 1, true), "exact native begin repeated")
    local b = assert(source:find(following, a + #first, true), "exact native end missing")
    return source:sub(a, b - 1)
end
function M.same(a, b, forward, reverse)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return rawequal(a, b) end
    forward, reverse = forward or {}, reverse or {}
    if forward[a] then return rawequal(forward[a], b) end
    if reverse[b] or not rawequal(getmetatable(a), getmetatable(b)) then return false end
    forward[a], reverse[b] = b, a
    local count, other = 0, 0
    for k, v in next, a do if type(k) == "table" or not M.same(v, rawget(b, k), forward, reverse) then return false end; count = count + 1 end
    for _ in next, b do other = other + 1 end
    return count == other
end
local function native(c, root, native_root, preserve_shared)
    local T, env = c.T, c.env
    local function read(path) return T.read(native_root .. "/" .. path) end
    local private = setmetatable({ table = env.table, DLCSettings = {}, DLCUtils = {},
        fassert = function(ok, message, ...) assert(ok, string.format(message, ...)) end }, { __index = env })
    private._G = private
    local allowed = {}
    for _, row in ipairs(DLC) do
        private.DLCSettings[row[1]] = { damage_profile_template_files_names = { row[2] } }; allowed[row[2]] = true
    end
    private.DLCSettings.anvil.power_level_template_files_names = { "scripts/settings/equipment/power_level_templates_dlc_anvil" }
    local merge = between(read("foundation/scripts/util/table.lua"), "table.merge = function (dest, source)", "table.merge_recursive = function")
    T.run(merge, private, "exact-native-table-merge")
    T.run(read("scripts/helpers/dlc_utils.lua"), private, "complete-native-finite-DLC-map")
    private.require = function(name)
        if name == "scripts/settings/equipment/power_level_templates" then return end
        assert(name == "scripts/settings/equipment/power_level_templates_dlc_anvil", "undeclared native require")
        return T.run(read(name .. ".lua"), private, name)
    end
    private.local_require = function(name)
        assert(allowed[name], "undeclared native DLC profile read")
        return T.run(read(name .. ".lua"), private, name)
    end
    T.run(read("scripts/settings/equipment/power_level_templates.lua"), private, "complete-native-power-and-Anvil-merge")
    T.run(read("scripts/settings/equipment/damage_profile_templates.lua"), private, "complete-native-profiles-all11-DLC-merges-resolution-names")
    env.PowerLevelTemplates = private.PowerLevelTemplates
    for _, name in ipairs(M.names) do
        env.DamageProfileTemplates[name] = assert(private.DamageProfileTemplates[name])
        local id = rawget(c.lookup, name)
        if id == nil then local inserted; id, inserted = c.helper.register(c.lookup, name); assert(inserted) end
        assert(rawget(c.lookup, id) == name)
    end
    local actions = read("scripts/settings/action_templates.lua")
    if preserve_shared then
        -- The combined fixture already executed the verbatim native definitions
        -- into these aliases, before any retained Sword/Mace proof.
        for _, name in ipairs({ "wield", "action_inspect" }) do
            local shared = rawget(assert(env.ActionTemplates), name)
            assert(type(shared) == "table" and type(rawget(shared, "default")) == "table",
                "actual shared native action prerequisite missing")
        end
    else
        T.run("ActionTemplates = {}\n" .. between(actions, "ActionTemplates.wield = {", "ActionTemplates.wield_left =")
            .. between(actions, "ActionTemplates.action_inspect = {", "ActionTemplates.action_inspect_left ="), env, "exact-native-shared-wield-inspect")
    end
    local linking = read("scripts/settings/attachment_node_linking.lua")
    local polearm = between(linking, "\tpolearm = {", "\tflail = {")
    if preserve_shared then
        local target = rawget(assert(env.AttachmentNodeLinking), "polearm")
        assert(type(target) == "table" and getmetatable(target) == nil and next(target) == nil,
            "actual polearm alias is not the empty pre-proof seed")
        local definitions = T.run("return {\n" .. polearm .. "}\n", env, "actual-native-polearm-fields")
        for key, value in next, definitions.polearm do rawset(target, key, value) end
    else
        T.run("AttachmentNodeLinking = {\n" .. polearm .. "}\n", env, "exact-native-polearm-attachment")
    end
    T.run(read("scripts/settings/equipment/hit_mass_counts.lua"), env, "complete-native-hit-mass-globals")
    T.run(between(read("scripts/settings/equipment/weapons.lua"), "DamageTypes = {", "Weapons = Weapons or {}"), env, "exact-native-damage-type-keys")
    local portable = assert(loadfile(root .. "/qa/lua/fixtures/cwv_old_musket_native_6_13.lua"))()
    assert(portable.tuskgor == read("scripts/settings/equipment/weapon_templates/2h_heavy_spears.lua"), "tracked Tuskgor/native source mismatch")
    local donor = T.run(portable.tuskgor, env, "required-reused-complete-native-Tuskgor")
    local receiver = T.run(read("scripts/settings/equipment/weapon_templates/spears_wood_elf.lua"), env, "complete-native-Elf-Spear")
    env.Weapons[M.donor], env.Weapons[M.receiver] = assert(donor[M.donor]), assert(receiver[M.receiver])
    local iml = read("scripts/settings/equipment/item_master_list_exported.lua")
    T.run(between(iml, "ItemMasterList.we_spear = {", "ItemMasterList.we_dual_wield_daggers = {"), env, "exact-native-physical-Elf-Spear-item")
    c.native_root, c.native_selected = native_root, private
end
function M.prepare_core(c, root)
    local entry = c.T.read(root .. P .. "character_weapon_variants.lua")
    local core_at = assert(entry:find("local _core_template_construction = mod:dofile(", 1, true))
    local prerequisite = '_om.combat_style_policy = mod:dofile("scripts/mods/character_weapon_variants/_cwv_combat_styles")'
    local policy_at = assert(entry:find(prerequisite, 1, true), "actual core policy prerequisite missing")
    assert(not entry:find(prerequisite, policy_at + 1, true), "actual core policy prerequisite repeated")
    assert(policy_at < core_at, "actual core policy prerequisite must precede core bind")
    local prepare = c.T.run("return function(mod, _om)\n"
        .. entry:sub(policy_at, policy_at + #prerequisite - 1) .. "\nend", c.env,
        "actual-entry-core-policy-prerequisite")
    prepare(c.mod, c.state)
end
function M.available(root)
    local native_root = os.getenv("VT2_SOURCE_ROOT") or root .. "/../Vermintide-2-Source-Code"
    for _, path in ipairs({ "scripts/settings/equipment/power_level_templates.lua",
            "scripts/settings/equipment/weapon_templates/spears_wood_elf.lua" }) do
        local file = io.open(native_root .. "/" .. path, "rb")
        if not file then return false end
        file:close()
    end
    return true
end
function M.prepare_native(c, root, native_root)
    return native(c, root, native_root, true)
end
function M.snapshot(c)
    return assert(c.graph.capture({ c.env.Weapons, c.env.DamageProfileTemplates, c.env.PowerLevelTemplates,
        c.lookup, c.state, c.env.ItemMasterList, c.audit() }, 16384, 262144))
end
function M.new(H, root, config)
    config = config or {}
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local T = assert(loadfile(root .. "/qa/lua/tests/test_cwv_old_musket_shot_owner.lua"))()(quiet, root)
    local c = T.installed(function(current)
        current.T = T
        current.before_musket = function(helper, graph, career)
            current.helper, current.graph = helper, graph
            local entry = T.read(root .. P .. "character_weapon_variants.lua")
            local a = assert(entry:find("local _core_template_construction = mod:dofile(", 1, true))
            M.prepare_core(current, root)
            local b = assert(entry:find("\nlocal _clone_damage_profile = _core_template_construction.clone_damage_profile", a, true))
            local bind = T.run("return function(mod, _om, _cwv_network_lookup, _cwv_profile_graph, _cwv_career_envelope)\n"
                .. entry:sub(a, b - 1) .. "\nreturn _core_template_construction end", current.env, "actual-private-core-return")
            current.core = bind(current.mod, current.state, helper, graph, career)
            native(current, root, config.native_root or os.getenv("VT2_SOURCE_ROOT") or (root .. "/../Vermintide-2-Source-Code"))
            local producer = assert(loadfile(root .. "/qa/lua/fixtures/cwv_tuskgor_history_producer.lua"))()
            current.history = producer.bind(H, root, current)
            if config.history then current.history.install(config.stream or "wt", config.history) end
            local factory = assert(loadfile(root .. P .. "_cwv_tuskgor_spear_style_construction.lua"))().bind(
                helper, graph, current.history.envelope)
            function current.audit()
                for i = 1, 20 do
                    local name, value = debug.getupvalue(current.state._cwv_profile_multiplier_check, i)
                    if name == "multiplier_audit" then return value end; if not name then break end
                end
                error("actual private core audit unavailable")
            end
            function current.create(options)
                options = options or {}
                return factory({ state = current.state, clone = options.clone or function(v) return current.env.table.clone(v, true) end,
                    profiles = function() return current.env.DamageProfileTemplates end,
                    power_levels = function() return current.env.PowerLevelTemplates end,
                    lookup = function() return current.env.NetworkLookup.damage_profiles end,
                    weapons = function() return current.env.Weapons end,
                    scalar_factory = options.scalar or current.core.detached_scalar_factory, read = options.read, write = options.write })
            end
        end
    end)
    return c
end
function M.expected_template(c)
    local e = c.env.table.clone(c.env.Weapons[M.receiver], true)
    local donor = c.env.Weapons[M.donor]
    e.actions.action_one = c.env.table.clone(donor.actions.action_one, true)
    e.state_machine, e.wield_anim = donor.state_machine, donor.wield_anim
    for _, name in ipairs(M.attacks) do
        local a = e.actions.action_one[name]; a.anim_time_scale = (rawget(a, "anim_time_scale") or 1) * 1.15
        if a.kind == "sweep" then a.damage_profile = M.prefix .. a.damage_profile end
    end
    local push = e.actions.action_one.push
    push.damage_profile_inner, push.damage_profile_outer = M.prefix .. push.damage_profile_inner, M.prefix .. push.damage_profile_outer
    push.push_radius = c.env.Weapons[M.receiver].actions.action_one.push.push_radius
    return e
end
function M.expected_profile(c, name)
    local e = c.env.table.clone(c.env.DamageProfileTemplates[name], true)
    local function impact(row) if row and row.power_distribution then row.power_distribution.impact = row.power_distribution.impact * .85 end end
    e.cleave_distribution.attack = e.cleave_distribution.attack * .85
    e.cleave_distribution.impact = e.cleave_distribution.impact * .85
    impact(e.default_target); for _, row in pairs(e.targets or {}) do impact(row) end
    return e
end
function M.verify(H, c, owner)
    local name, template = owner.template(); H.equal(name, M.key, "prepared template name")
    H.truthy(M.same(template, M.expected_template(c)), "complete Tuskgor attack graph with exact Elf non-attack retention")
    for _, key in ipairs(M.names) do
        H.truthy(M.same(c.env.DamageProfileTemplates[M.prefix .. key], M.expected_profile(c, key)), "complete once-only source profile " .. key)
    end
    H.equal(owner.check(), nil)
end
return M
