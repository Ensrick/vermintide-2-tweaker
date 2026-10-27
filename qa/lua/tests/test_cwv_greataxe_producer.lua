-- #428 persistent real installer/constructor/item/seed producer cases.
-- Owned by: qa/lua/run.lua. Consumed via: its ordered suite manifest.
return function(H, root)
    local function read(file)
        local input = assert(io.open(file, "rb")); local value = assert(input:read("*a")); input:close(); return value
    end
    local private = { dofile = dofile, READ = read }
    -- Immutable case source group 1; only first/next helper path retargeted.
    do
        local function register(...)
-- ONE new installer-boundary falsifier, not the preserved uninstalled M.new case.
local H, root, private = ...
local F = private.dofile(root .. "/qa/lua/fixtures/cwv_greataxe_construction_harness.lua")
H.test("#428 Greataxe actual public WT default-on install must retain item and seed", function()
    local mods = {}
    local c = F.new(H, root, { get_mod = function(id) return rawget(mods, id) end })
    H.equal(c.greataxe_owner.check(), nil)
    local _, item, seed = c.greataxe_items()
    H.truthy(item, "healthy actual private item control")
    H.truthy(seed, "healthy actual Blacksmith/CIM acquisition seed control")
    local key = "additional_critical_strike_chance"
    local names = { "light_attack_left", "light_attack_right", "light_attack_up", "light_attack_bopp" }
    local templates = { native = c.greataxe_source, owned = c.greataxe_template }
    local before = {}
    for _, role in ipairs({ "native", "owned" }) do
        local template = templates[role]
        local actions = assert(rawget(template, "actions"))
        local one = assert(rawget(actions, "action_one"))
        before[role] = { template = template, actions = actions, one = one, rows = {} }
        for _, name in ipairs(names) do
            local action = assert(rawget(one, name))
            H.equal(rawget(action, "kind"), "sweep", "source-qualified real light action")
            local value = rawget(action, key)
            before[role].rows[name] = { action = action, present = value ~= nil, value = value }
            io.write("BEFORE_ACTION|", role, "|", name, "|ref=", tostring(action),
                "|present=", tostring(value ~= nil), "|value=", tostring(value), "\n")
        end
    end
    io.write("BEFORE_ADMISSION|item=", tostring(item ~= nil), "|seed=", tostring(seed ~= nil), "\n")
    local requested = {}
    local mod = { get = function(_, setting)
        requested[setting] = (requested[setting] or 0) + 1
        return nil -- Actual install's documented nil-setting default, no true stub.
    end }
    mods.wt = mod
    local policy = c.T.run(private.READ(root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_axe_balance.lua"),
        c.env, "complete-actual-public-WT-balance-install")
    H.equal(type(rawget(policy, "install")), "function")
    -- Complete unmodified production install creates its own real M.new state,
    -- publishes the real setter/reset closures and invokes default apply itself.
    local runtime = policy.install(mod)
    H.equal(type(mod._wt_apply_axe_balance), "function")
    H.equal(type(mod._wt_reset_axe_balance_baselines), "function")
    H.equal(runtime.greataxe_crit_enabled, true)
    H.truthy(requested.wt_greataxe_light_crit, "real install consulted the setting")
    local registry = c.env.Weapons
    H.truthy(rawequal(rawget(registry, "two_handed_axes_template_1"), before.native.template))
    H.truthy(rawequal(rawget(registry, "cwv_greataxe_template"), before.owned.template))
    for _, role in ipairs({ "native", "owned" }) do
        local proof = before[role]
        H.truthy(rawequal(rawget(proof.template, "actions"), proof.actions))
        H.truthy(rawequal(rawget(proof.actions, "action_one"), proof.one))
        for _, name in ipairs(names) do
            local selected = proof.rows[name]
            local action = rawget(proof.one, name)
            H.truthy(rawequal(action, selected.action), "actual action reference remains unchanged")
            local row = assert(rawget(runtime.greataxe_crit_originals, action), "real private install ledger row missing")
            H.equal(rawget(row, "had_value"), selected.present)
            H.equal(rawget(row, "value"), selected.value)
            H.equal(rawget(action, key), 0.10, "actual install applied the real native crit floor")
            io.write("AFTER_ACTION|", role, "|", name, "|same_ref=true|ref=", tostring(action),
                "|value=", tostring(rawget(action, key)), "|baseline_present=", tostring(rawget(row, "had_value")),
                "|baseline=", tostring(rawget(row, "value")), "\n")
        end
    end
    local verdict = c.greataxe_owner.check()
    _, item, seed = c.greataxe_items()
    io.write("INSTALLED|public=wt|default_on=true|setter=function|reset=function|check=", tostring(verdict), "\n")
    io.write("AFTER_ADMISSION|item=", tostring(item ~= nil), "|seed=", tostring(seed ~= nil), "\n")
    H.truthy(item and seed, "actual default-on WT M.install must retain BOTH private item and seed")
    H.equal(verdict, nil)
end)
        end
        register(H, root, private)
    end
    -- Immutable case source group 2; only first/next helper path retargeted.
    do
        local function register(...)
-- FOUR new affected cases; the fifth is the exact unchanged accepted installer
-- oracle178de983, loaded separately with its original test body and assertions.
local H, root, private = ...
local C = private.dofile(root .. "/qa/lua/fixtures/cwv_greataxe_producer_harness.lua")
H.test("#428 Greataxe first batch keeps unchanged no-WT Current item and seed", function()
    local c = C.new(H, root, private, false)
    C.output(H, c, true, "no-WT-Current")
    for _, template in ipairs({ c.greataxe_source, c.greataxe_template }) do
        local actions = C.actions(template)
        H.equal(rawget(actions.light_attack_left, C.field), nil)
        H.equal(rawget(actions.light_attack_right, C.field), nil)
        H.equal(rawget(actions.light_attack_up, C.field), 0.10)
        H.equal(rawget(actions.light_attack_bopp, C.field), nil)
    end
end)
H.test("#428 Greataxe real install before construction keeps late clone and distinct disable baselines", function()
    local c = C.new(H, root, private, true)
    C.output(H, c, true, "WT-before-construction")
    local source = C.query(H, c, "two_handed_axes_template_1")
    local clone = C.query(H, c, "cwv_greataxe_template")
    for i = 1, 4 do
        H.equal(source.rows[i].claimed, true, "native was present at actual install")
        H.equal(clone.rows[i].claimed, false, "detached clone was absent at install")
        H.equal(clone.rows[i].value, 0.10, "clone keeps inherited scalar")
    end
    local mod = c.first_producer.mod
    mod._wt_apply_axe_balance("wt_greataxe_light_crit", false)
    clone = C.query(H, c, "cwv_greataxe_template")
    for i = 1, 4 do
        H.equal(clone.rows[i].claimed, true)
        H.equal(clone.rows[i].baseline_present, true)
        H.equal(clone.rows[i].baseline_value, 0.10, "late clone owns its inherited baseline")
    end
    C.output(H, c, true, "actual-late-clone-apply")
    mod._wt_apply_axe_balance("wt_greataxe_light_crit", true)
    source, clone = C.query(H, c, "two_handed_axes_template_1"), C.query(H, c, "cwv_greataxe_template")
    H.equal(source.enabled, false); H.equal(clone.enabled, false)
    for i = 1, 4 do
        H.equal(source.rows[i].claimed, false); H.equal(clone.rows[i].claimed, false)
        H.equal(source.rows[i].value, i == 3 and 0.10 or nil, "native exact original presence/value restored")
        H.equal(clone.rows[i].value, 0.10, "clone exact distinct baseline restored")
    end
    C.output(H, c, true, "actual-disable-distinct-baselines")
end)
H.test("#428 Greataxe real repeated enabled apply cannot repair foreign post-claim crit drift", function()
    local c = C.new(H, root, private, false)
    C.install(H, c, private, c.first_mods)
    C.output(H, c, true, "drift-before")
    local action = C.actions(c.greataxe_source).light_attack_left
    rawset(action, C.field, 0.15) -- Adversarial writer only, never a positive producer surrogate.
    local value, why = c.first_producer.mod._wt_query_greataxe_light_crit(
        c.env.Weapons, "two_handed_axes_template_1", c.greataxe_source)
    H.equal(value, nil); H.equal(why, "greataxe_claimed_value_changed")
    C.output(H, c, false, "foreign-post-claim-drift")
    c.first_producer.mod._wt_apply_axe_balance("wt_greataxe_light_crit", false)
    H.equal(rawget(action, C.field), 0.15, "real repeated-enabled policy does not repair/recapture")
    C.output(H, c, false, "drift-after-real-repeated-apply")
end)
H.test("#428 Greataxe producer cannot authorize a same-value foreign action reference", function()
    local c = C.new(H, root, private, false)
    C.install(H, c, private, c.first_mods)
    C.output(H, c, true, "foreign-reference-before")
    local actions = C.actions(c.greataxe_template)
    local original = rawget(actions, "light_attack_left")
    local foreign = c.env.table.clone(original, true)
    H.equal(rawequal(original, foreign), false)
    H.equal(rawget(foreign, C.field), rawget(original, C.field))
    rawset(actions, "light_attack_left", foreign)
    C.output(H, c, false, "same-value-foreign-action-reference")
    H.truthy(rawequal(rawget(actions, "light_attack_left"), foreign), "guard never repairs the external replacement")
end)
        end
        register(H, root, private)
    end
    -- Immutable case source group 3; only first/next helper path retargeted.
    do
        local function register(...)
-- Genuinely affected next cases only. Original first5 and old91/217 not replayed.
local H, root, private = ...
local Q = private.dofile(root .. "/qa/lua/fixtures/cwv_greataxe_producer_harness.lua")
H.test("#428 Greataxe actual off reset and re-enable preserve cached original roles", function()
    local c = Q.ready(H, root, private)
    local p = c.next_producers.wt
    local old = p.state.greataxe_crit_originals
    Q.off_all(c, "wt"); Q.admission(H, c, true, "before-real-reset")
    H.equal(p.mod._wt_reset_axe_balance_baselines(), true)
    H.equal(rawequal(old, p.state.greataxe_crit_originals), false)
    H.equal(next(p.state.greataxe_crit_originals), nil)
    Q.admission(H, c, true, "real-reset-empty-originals")
    Q.apply(c, "wt", true)
    Q.admission(H, c, true, "real-re-enable-same-baseline")
end)
H.test("#428 Greataxe actual reset cannot authorize foreign later baseline recapture", function()
    local c = Q.ready(H, root, private)
    Q.off_all(c, "wt")
    H.equal(c.next_producers.wt.mod._wt_reset_axe_balance_baselines(), true)
    local action = Q.actions(c.greataxe_source).light_attack_left
    rawset(action, Q.field, 0.25) -- Foreign writer AFTER the CWV baseline was pinned.
    Q.admission(H, c, false, "foreign-restored-baseline-before-recapture")
    Q.apply(c, "wt", true)
    local result = Q.query(H, c, "wt")
    H.equal(result.rows[1].baseline_value, 0.25, "actual WT really captured a new tuple")
    Q.admission(H, c, false, "real-owner-recapture-does-not-rebaseline-CWV")
    H.equal(rawget(action, Q.field), 0.25)
end)
H.test("#428 Greataxe stronger controlled preexisting baseline permits real coactive agreeing producers", function()
    -- Supported scalar-input parameter, not a claim that vanilla authors0.25.
    -- All native graph/callback/profile data remains the real tracked fixture.
    local c = Q.new(H, root, private, { before = function(x)
        local actions = Q.actions(x.greataxe_source)
        for _, name in ipairs(Q.names) do rawset(actions[name], Q.field, 0.25) end
    end })
    Q.install(H, c, private, "wt", nil)
    Q.install(H, c, private, "wt_dev", nil)
    Q.admission(H, c, true, "coactive-agreeing-stronger-baselines")
    local a, b = Q.query(H, c, "wt"), Q.query(H, c, "wt_dev")
    H.equal(rawequal(a.installation, b.installation), false)
    for i = 1, 4 do
        H.equal(a.rows[i].baseline_value, 0.25); H.equal(b.rows[i].baseline_value, 0.25)
        H.equal(a.rows[i].value, 0.25); H.equal(b.rows[i].value, 0.25)
    end
    Q.off_all(c, "wt"); Q.admission(H, c, true, "agreeing-first-off")
    Q.off_all(c, "wt_dev"); Q.admission(H, c, true, "agreeing-both-off")
end)
for _, order in ipairs({ "later-first", "earlier-first" }) do
    local selected = order
    H.test("#428 Greataxe real co-installed conflicting baselines restore order " .. selected, function()
        local c = Q.ready(H, root, private)
        Q.install(H, c, private, "wt_dev", nil)
        Q.admission(H, c, false, "conflicting-second-install:" .. selected)
        local a, b = Q.query(H, c, "wt"), Q.query(H, c, "wt_dev")
        H.equal(a.rows[1].baseline_present, false)
        H.equal(b.rows[1].baseline_present, true); H.equal(b.rows[1].baseline_value, 0.10)
        if selected == "later-first" then
            Q.off_all(c, "wt_dev")
            Q.admission(H, c, true, "later-off-leaves-original-owner")
            Q.off_all(c, "wt")
            Q.admission(H, c, true, "later-first-restores-cached-native")
        else
            Q.off_all(c, "wt")
            Q.admission(H, c, false, "earlier-off-breaks-later-live-claim")
            Q.off_all(c, "wt_dev")
            H.equal(rawget(Q.actions(c.greataxe_source).light_attack_left, Q.field), 0.10)
            Q.admission(H, c, false, "earlier-first-leaves-conflicting-restored-value")
        end
    end)
end
H.test("#428 Greataxe returned copies never expose actual private originals or grant authority", function()
    local c = Q.ready(H, root, private)
    local a, b = Q.query(H, c, "wt"), Q.query(H, c, "wt")
    H.equal(rawequal(a, b), false); H.equal(rawequal(a.rows, b.rows), false)
    H.equal(rawequal(a.rows[1], b.rows[1]), false)
    local action = a.rows[1].action
    local original = rawget(c.next_producers.wt.state.greataxe_crit_originals, action)
    H.equal(rawequal(original, a.rows[1]), false)
    a.rows[1].baseline_value = 999; a.rows[1].action = {}; a.rows[1].claimed = false
    a.installation = function() end; a.rows[5] = {}
    H.equal(rawget(original, "had_value"), false); H.equal(rawget(original, "value"), nil)
    local current = Q.query(H, c, "wt")
    H.equal(current.rows[1].baseline_present, false); H.equal(current.rows[1].baseline_value, nil)
    Q.admission(H, c, true, "returned-copy-mutation-isolated")
end)
H.test("#428 Greataxe missing provider authorizes only the exact restored baseline", function()
    local c = Q.ready(H, root, private)
    local mod = c.next_mods.wt
    c.next_mods.wt = nil
    Q.admission(H, c, false, "missing-active-provider")
    c.next_mods.wt = mod
    Q.admission(H, c, true, "same-provider-return")
    Q.off_all(c, "wt"); c.next_mods.wt = nil
    Q.admission(H, c, true, "missing-provider-after-proven-restoration")
end)
H.test("#428 Greataxe throwing fixed resolver cannot authorize changed active fields", function()
    local throwing = false
    local c = Q.ready(H, root, private, { resolve = function(id, mods)
        if throwing then error("bounded resolver fault") end
        return rawget(mods, id)
    end })
    throwing = true
    Q.admission(H, c, false, "throwing-active-provider-resolver")
end)
H.test("#428 Greataxe replacing a real installed mod is refused even at restored values", function()
    local c = Q.ready(H, root, private)
    Q.off_all(c, "wt"); Q.admission(H, c, true, "real-replacement-before")
    local old = c.next_mods.wt
    Q.install(H, c, private, "wt", false, true)
    H.equal(rawequal(old, c.next_mods.wt), false)
    Q.admission(H, c, false, "new-real-installation-same-fixed-slot")
end)
for _, kind in ipairs({ "missing", "replaced" }) do
    local selected = kind
    H.test("#428 Greataxe known query identity " .. selected .. " is refused", function()
        local c = Q.ready(H, root, private)
        local mod = c.next_mods.wt
        local query = mod._wt_query_greataxe_light_crit
        if selected == "missing" then mod._wt_query_greataxe_light_crit = nil
        else mod._wt_query_greataxe_light_crit = function(...) return query(...) end end
        Q.admission(H, c, false, "known-query-identity:" .. selected)
    end)
end
H.test("#428 Greataxe a throwing query before first binding is not a readiness signal", function()
    local c = Q.new(H, root, private)
    local p = Q.install(H, c, private, "wt", nil)
    local query = p.mod._wt_query_greataxe_light_crit
    p.mod._wt_query_greataxe_light_crit = function() error("bounded first-query fault") end
    Q.admission(H, c, false, "throwing-unbound-query")
    p.mod._wt_query_greataxe_light_crit = query
    Q.admission(H, c, true, "real-query-first-valid-binding")
end)
H.test("#428 Greataxe raw foreign root is denied despite shared equality metamethod", function()
    local meta = { __eq = function() return true end }
    local c = Q.ready(H, root, private, { before = function(x) setmetatable(x.env.Weapons, meta) end })
    local root_before = c.env.Weapons
    local foreign = {}; for k, value in next, root_before do rawset(foreign, k, value) end
    setmetatable(foreign, meta)
    H.equal(root_before == foreign, true); H.equal(rawequal(root_before, foreign), false)
    c.env.Weapons = foreign
    Q.admission(H, c, false, "equal-comparing-foreign-root")
end)
H.test("#428 Greataxe new observable action metatable cannot hide in crit exclusions", function()
    local c = Q.ready(H, root, private)
    local action = Q.actions(c.greataxe_template).light_attack_left
    local meta = {}; setmetatable(action, meta)
    Q.admission(H, c, false, "foreign-action-observable-meta")
    H.truthy(rawequal(getmetatable(action), meta), "no metatable repair")
end)
for _, kind in ipairs({ "sparse", "hash-extra" }) do
    local selected = kind
    H.test("#428 Greataxe query copied-row shape rejects " .. selected, function()
        local c = Q.new(H, root, private)
        local p = Q.install(H, c, private, "wt", nil)
        local query = p.mod._wt_query_greataxe_light_crit
        p.mod._wt_query_greataxe_light_crit = function(...)
            local value, why = query(...)
            if not value then return value, why end
            if selected == "sparse" then value.rows[2] = nil else value.rows.foreign = true end
            return value
        end
        Q.admission(H, c, false, "bad-query-row-shape:" .. selected)
    end)
end
for _, role in ipairs({ "source", "clone" }) do
    local selected = role
    H.test("#428 Greataxe unrelated " .. selected .. " field remains strict with real producer", function()
        local c = Q.ready(H, root, private)
        local template = selected == "source" and c.greataxe_source or c.greataxe_template
        local action = Q.actions(template).light_attack_left
        rawset(action, "anim_event", "bounded-foreign-animation")
        Q.query(H, c, "wt", selected == "source" and "two_handed_axes_template_1" or "cwv_greataxe_template")
        Q.admission(H, c, false, "unrelated-graph-field:" .. selected)
    end)
end
H.test("#428 Greataxe real producer mutation during preparation denies before publication", function()
    local c = Q.new(H, root, private, { after_prepare = function(x)
        Q.install(H, x, private, "wt", nil)
    end })
    H.equal(c.greataxe_constructed, false)
    H.equal(rawget(c.env.Weapons, "cwv_greataxe_template"), nil)
    H.equal(rawget(Q.actions(c.greataxe_source).light_attack_left, Q.field), 0.10)
    Q.admission(H, c, false, "real-install-during-prepare-no-partial-template")
end)
H.test("#428 Greataxe real producer mutation at precommit denies without source repair", function()
    local c = Q.new(H, root, private, { mechanics = function(graph, x)
        return { capture = graph.capture, intact = graph.intact, disjoint = graph.disjoint,
            commit = function(changes, before, after, read, write)
                return graph.commit(changes, function()
                    Q.install(H, x, private, "wt", nil)
                    before()
                end, after, read, write)
            end }
    end })
    H.equal(c.greataxe_constructed, false)
    H.equal(rawget(c.env.Weapons, "cwv_greataxe_template"), nil)
    H.equal(rawget(Q.actions(c.greataxe_source).light_attack_left, Q.field), 0.10)
    Q.admission(H, c, false, "real-install-at-precommit-no-partial-template")
end)
        end
        register(H, root, private)
    end
    -- Immutable case source group 4; only first/next helper path retargeted.
    do
        local function register(...)
-- One new positive+negative constructor-capture case, not a fake producer.
local H, root, private = ...
local Q = private.dofile(root .. "/qa/lua/fixtures/cwv_greataxe_producer_harness.lua")
H.test("#428 Greataxe constructor rejects present invalid provider at unchanged baseline", function()
    local good = Q.new(H, root, private, { before = function(c)
        Q.install(H, c, private, "wt", false) -- Complete real install, genuinely off.
    end })
    Q.admission(H, good, true, "capture-real-present-off-provider")
    H.equal(good.greataxe_constructed, true)
    local current = Q.query(H, good, "wt")
    H.equal(current.enabled, false)
    for i = 1, 4 do H.equal(current.rows[i].claimed, false) end

    local bad = Q.new(H, root, private, { before = function(c)
        local p = Q.install(H, c, private, "wt", false)
        -- Failure injection only: real owner/state remains installed and all
        -- native values still match Current. This query grants no authority.
        p.mod._wt_query_greataxe_light_crit = function() return nil, "bounded invalid present provider" end
    end })
    -- Compute/log both actual routes BEFORE assertions, including on the old
    -- source control where publication/admission will unexpectedly succeed.
    Q.admission(H, bad, false, "capture-invalid-present-baseline-provider")
    H.equal(bad.greataxe_constructed, false)
    H.equal(rawget(bad.env.Weapons, "cwv_greataxe_template"), nil)
    H.equal(rawget(Q.actions(bad.greataxe_source).light_attack_left, Q.field), nil)
    H.equal(rawget(Q.actions(bad.greataxe_source).light_attack_up, Q.field), 0.10)
end)
        end
        register(H, root, private)
    end
    -- Three separately proven real lifecycle cases; original bodies unchanged.
    do
        local function register(...)
local H, root, private = ...
local Q = private.dofile(root .. "/qa/lua/fixtures/cwv_greataxe_producer_harness.lua")
local L = {
    membership = Q.lifecycle_metadata, new = Q.lifecycle_new,
    admission = function(H, c, phase) return Q.admission(H, c, true, phase) end,
    crit = Q.lifecycle_crit, dagger = Q.lifecycle_dagger, setting = Q.setting,
}
H.test("#428 actual default13 metadata merge has no Greataxe history family", function()
    L.membership(H, root, private)
end)
H.test("#428 actual settings callback preserves Greataxe item and seed through real Current history", function()
    local c = L.new(H, root, private, "current")
    local p = c.lifecycle
    H.equal(p.runtime:is_setting(L.setting), false, "actual history declines nonfamily leaf")
    H.equal(p.rework_policy.is_member(L.setting), true, "actual rework membership")
    L.admission(H, c, "settings-installed-default")
    L.crit(H, c, true, "settings-installed-default")
    p.settings[L.setting] = false -- Actual persisted VMF boundary before callback.
    p.mod.on_setting_changed(L.setting)
    L.admission(H, c, "actual-settings-off")
    L.crit(H, c, false, "actual-settings-off")
    H.equal(p.verify(), nil)
    p.settings[L.setting] = true
    p.mod.on_setting_changed(L.setting)
    L.admission(H, c, "actual-settings-on")
    L.crit(H, c, true, "actual-settings-on")
    H.equal(p.verify(), nil)
    H.equal(p.rework:is_batching(), false)
    H.equal(#p.writes, 0, "real partial-family master remains false without fabricated sync writes")
    H.truthy(p.reads[p.rework_policy.MASTER_ID], "real rework master snapshot was queried")
    io.write("LIFECYCLE_SETTINGS|callback=real|history=current|query_identity=preserved\n")
end)
H.test("#428 actual history owner reconcile restore reconcile preserves Greataxe item and seed", function()
    local c = L.new(H, root, private, "6_11_1")
    local p, dagger = c.lifecycle, L.dagger(c)
    H.equal(rawget(dagger, "damage_profile"), "dagger_h1_medium_smiter_diag")
    H.equal(#p.runtime.ledgers.sienna_dagger, 1, "real historical operation was committed")
    L.admission(H, c, "historical-installed")
    L.crit(H, c, true, "historical-installed")
    local good, result = p.mod._wt_reconcile_history_owner_stack("game_state")
    H.equal(good, true)
    H.equal(result.refused, 0)
    H.equal(p.verify(), nil)
    H.equal(rawget(dagger, "damage_profile"), "dagger_h1_medium_smiter_diag")
    L.admission(H, c, "real-owner-reconciled")
    L.crit(H, c, true, "real-owner-reconciled")
    H.equal(p.owner:restore(), true)
    H.equal(rawget(dagger, "damage_profile"), "medium_burning_smiter_stab_H")
    H.equal(next(p.runtime.ledgers.sienna_dagger), nil, "real restored ledger is raw empty")
    H.equal(rawget(p.runtime.active, "sienna_dagger"), nil)
    local caveat = p.verify()
    H.equal(caveat, "sienna_dagger historical selection has no ledger",
        "preserve real verifier caveat, not false success after restore")
    L.admission(H, c, "real-owner-restored")
    L.crit(H, c, false, "real-owner-restored")
    local reapplied, projection = p.owner:reconcile("game_state-after-restore")
    H.equal(reapplied, true)
    H.equal(projection.refused, 0)
    H.equal(p.verify(), nil)
    H.equal(rawget(dagger, "damage_profile"), "dagger_h1_medium_smiter_diag")
    H.equal(#p.runtime.ledgers.sienna_dagger, 1)
    L.admission(H, c, "real-owner-reapplied-after-restore")
    L.crit(H, c, true, "real-owner-reapplied-after-restore")
    io.write("LIFECYCLE_OWNER|genuine_other_family=sienna_dagger|restore_verifier=missing-ledger|reconciled=real\n")
end)
        end
        register(H, root, private)
    end
end
