-- _cwv_shortsword_history_envelope.lua -- Finite native dagger history axis.
--
-- Delegates only native dagger heavy-right damage_profile semantics to the real
-- WT history runtime/ledger. Every other source/clone cell stays graph-owned.
-- This is not cryptographic producer-origin or canonical gameplay-body proof.
-- No mutation, registry, module load, hook, repair, or graph resnapshot occurs.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load and private fourth Shortsword bind argument.
local M = {}
local DONOR, FAMILY, SETTING = "one_handed_daggers_template_1", "sienna_dagger", "wt_history_sienna_dagger"
local STATE, KEY = "6_11_1", "damage_profile"
local CURRENT, HISTORICAL = "medium_burning_smiter_stab_H", "dagger_h1_medium_smiter_diag"
function M.bind(graph, producer)
    local capture, intact, disjoint = assert(graph.capture), assert(graph.intact), assert(graph.disjoint)
    local make_binding, binding_intact, resolve = assert(producer.capture_runtime), assert(producer.intact_runtime), assert(producer.resolve)
    local plain, dense = assert(producer.plain), assert(producer.dense)
    local function operation_ok(row)
        if not plain(row) or rawget(row, "root") ~= "Weapons" or rawget(row, "template") ~= DONOR
                or rawget(row, "family_id") ~= FAMILY or rawget(row, "state_id") ~= STATE
                or rawget(row, "expected_present") ~= true or rawget(row, "result_present") ~= true
                or rawget(row, "expected_current") ~= CURRENT or rawget(row, "result") ~= HISTORICAL
                or rawget(row, "change_class") ~= "official_weapon_balance"
                or rawget(row, "official_change_id") ~= "P6112-SIENNA-DAGGER-H2"
                or rawget(row, "source_path") ~= "scripts/settings/equipment/weapon_templates/1h_dagger_wizard.lua"
                or rawget(row, "source_revision") ~= "1a0a4e0caf5c119bfe8d42a4d1bc23b34a7b005e"
                or rawget(row, "source_blob") ~= "656ef0ffac628d707d13adbf3c4a8950aec7fca7"
                or rawget(row, "current_source_blob") ~= "fcfeecee65342ae8b3bb4a75a57e248c3a677b1e" then return false end
        local path = rawget(row, "path")
        return dense(path, 4) == 4 and rawget(path, 1) == "actions" and rawget(path, 2) == "action_one"
            and rawget(path, 3) == "heavy_attack_right" and rawget(path, 4) == KEY
    end
    local function binding(mod, runtime)
        local common = make_binding(mod, runtime)
        if not common then return nil end
        local catalog, policy, families = common.catalog, common.policy, common.families
        local family = rawget(families, FAMILY)
        local list, source = rawget(catalog, "families"), rawget(catalog, "current_source")
        local count, found = dense(list, 128), 0
        if not count or not plain(source) or rawget(source, "revision") ~= "93dea911a4cc464a0eb51cfdc3a443297bfc4550"
                or not plain(family) or rawget(family, "id") ~= FAMILY or rawget(family, "setting_id") ~= SETTING then return nil end
        for index = 1, count do if rawequal(rawget(list, index), family) then found = found + 1 end end
        if found ~= 1 then return nil end
        local templates, states = rawget(family, "templates"), rawget(family, "states")
        local state = plain(states) and rawget(states, STATE)
        local operations = plain(state) and rawget(state, "operations")
        local operation = plain(operations) and rawget(operations, 1)
        if dense(templates, 1) ~= 1 or rawget(templates, 1) ~= DONOR or dense(operations, 1) ~= 1
                or not operation_ok(operation) or dense(rawget(state, "profile_names"), 0) ~= 0
                or dense(rawget(state, "direct_profile_names"), 0) ~= 0 then return nil end
        local operation_snapshot = capture(operation, 32, 128)
        if not operation_snapshot then return nil end
        common.family, common.templates, common.states, common.state = family, templates, states, state
        common.operations, common.operation, common.operation_snapshot = operations, operation, operation_snapshot
        return common
    end
    local function bound(p, b)
        local r, c, f = b.runtime, b.catalog, b.family
        if not binding_intact(b, p.weapons) or not rawequal(rawget(b.families, FAMILY), f) or not plain(f)
                or rawget(f, "id") ~= FAMILY or rawget(f, "setting_id") ~= SETTING
                or not rawequal(rawget(f, "templates"), b.templates) or dense(b.templates, 1) ~= 1 or rawget(b.templates, 1) ~= DONOR
                or not rawequal(rawget(f, "states"), b.states) or not plain(b.states) or not rawequal(rawget(b.states, STATE), b.state)
                or not plain(b.state) or not rawequal(rawget(b.state, "operations"), b.operations)
                or dense(b.operations, 1) ~= 1 or not rawequal(rawget(b.operations, 1), b.operation)
                or not intact(b.operation_snapshot) then return false end
        local count, found = dense(b.list, 128), 0
        if not count then return false end
        for index = 1, count do if rawequal(rawget(b.list, index), f) then found = found + 1 end end
        local roots, ledgers, active, boot = rawget(r, "roots"), rawget(r, "ledgers"), rawget(r, "active"), rawget(r, "boot_selections")
        return found == 1 and plain(roots) and rawequal(rawget(roots, "Weapons"), p.weapons)
            and plain(ledgers) and plain(active) and plain(boot)
            and (rawget(boot, SETTING) == "current" or rawget(boot, SETTING) == STATE)
    end
    local function historical(p, b)
        local r = b.runtime
        local ledger = rawget(rawget(r, "ledgers"), FAMILY)
        local row = plain(ledger) and rawget(ledger, 1)
        local active = rawget(rawget(r, "active"), FAMILY)
        if dense(ledger, 1) ~= 1 or not plain(row) or not plain(active) or rawget(active, "state") ~= STATE
                or type(rawget(active, "parity")) ~= "boolean"
                or rawget(rawget(r, "boot_selections"), SETTING) ~= STATE then return false end
        local allowed = { applied_snapshot = true, applied_value = true, key = true, operation = true,
            original_present = true, original_value = true, owner_object = true, parent = true,
            root_name = true, root_object = true, template_name = true }
        for key in next, row do if not allowed[key] then return false end end
        if not rawequal(rawget(row, "operation"), b.operation) or not rawequal(rawget(row, "parent"), p.action)
                or not rawequal(rawget(row, "root_object"), p.weapons) or not rawequal(rawget(row, "owner_object"), p.source)
                or rawget(row, "key") ~= KEY or rawget(row, "root_name") ~= "Weapons" or rawget(row, "template_name") ~= DONOR
                or rawget(row, "original_present") ~= true or rawget(row, "original_value") ~= CURRENT
                or rawget(row, "applied_value") ~= HISTORICAL or rawget(row, "applied_snapshot") ~= HISTORICAL then return false end
        local ok, problem = pcall(b.verify)
        return ok and problem == nil
    end
    local function valid(p)
        if not p or not rawequal(rawget(p.weapons, DONOR), p.source)
                or not rawequal(rawget(p.source, "actions"), p.actions)
                or not rawequal(rawget(p.actions, "action_one"), p.action_one)
                or not rawequal(rawget(p.action_one, "heavy_attack_right"), p.action) then return false end
        local value, authorized = rawget(p.action, KEY), false
        if value ~= CURRENT and value ~= HISTORICAL then return false end
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local ok, mod = resolve(id)
            local prior = p.bindings[id]
            if ok and mod ~= nil then
                if type(mod) ~= "table" then return false end
                local runtime = rawget(mod, "_wt_history_runtime")
                if runtime ~= nil then
                    if prior and not rawequal(prior.mod, mod) then return false end
                    local b = prior or binding(mod, runtime)
                    if not b or not bound(p, b) then return false end
                    if not prior then p.bindings[id] = b end
                    local ledger = rawget(rawget(runtime, "ledgers"), FAMILY)
                    local active = rawget(rawget(runtime, "active"), FAMILY)
                    if value == HISTORICAL then
                        if historical(p, b) then authorized = true end
                    elseif (ledger ~= nil and dense(ledger, 0) ~= 0) or active ~= nil then return false end
                elseif prior then
                    return false
                end
            end
        end
        -- CURRENT is the exact native/restored scalar. An identical authorized
        -- scalar write has no observable provenance: finite semantics, not a
        -- writer attestation. Historical state requires one live pinned ledger.
        return value == CURRENT or authorized
    end
    local function make(source, weapons)
        local actions = type(source) == "table" and rawget(source, "actions")
        local one = type(actions) == "table" and rawget(actions, "action_one")
        local action = type(one) == "table" and rawget(one, "heavy_attack_right")
        if type(action) ~= "table" then return nil end
        local nodes = capture(source, 4096, 32768)
        if not nodes then return nil end
        local p = { source = source, weapons = weapons, actions = actions, action_one = one, action = action, bindings = {}, nodes = nodes }
        -- #428 observed actual WT 6.11.1 history invalidates donor ownership,
        -- not the clone. No native mutation is skipped: this only authorizes
        -- that one producer scalar while all immediate/full graphs stay strict.
        -- Failure still denies new item/seed; no repair or partial adoption.
        if not valid(p) then return nil end
        return p
    end
    local function prepare_clone(p, template)
        if not valid(p) or type(template) ~= "table" or rawequal(template, p.source) then return false end
        local actions = rawget(template, "actions")
        local one = type(actions) == "table" and rawget(actions, "action_one")
        local action = type(one) == "table" and rawget(one, "heavy_attack_right")
        local before = rawget(p.action, KEY)
        local nodes = capture(template, 4096, 32768)
        if type(action) ~= "table" or rawget(action, KEY) ~= before or not nodes or not disjoint(p.nodes, nodes) then return false end
        -- A historical native donor must not add a sixth CWV scalar source.
        -- Normalize this detached cell only, before the unchanged seven/five
        -- preparation recipe. No live donor or cloned gameplay body is adopted.
        if before == HISTORICAL then rawset(action, KEY, CURRENT) end
        return rawget(action, KEY) == CURRENT and rawget(p.action, KEY) == before
    end
    return { capture = make, intact = valid, prepare_clone = prepare_clone, include = function(p, t, key)
        return not (rawequal(t, p.action) and key == KEY)
    end }
end
return M
