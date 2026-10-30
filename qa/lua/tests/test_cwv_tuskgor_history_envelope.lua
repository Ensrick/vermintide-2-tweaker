-- Detached typed producer proof only. No catalogue/actor/receiver activation.
return function(H, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_tuskgor_style_construction_harness.lua"))()
    local available = F.available(root)
    local function native_test(name, body)
        H.test_if(available, name, body, "optional sibling6.13 native Tuskgor/Elf inputs absent")
    end
    local KEY, SETTING, STATE = "block_fatigue_point_multiplier", "wt_history_tuskgor_spear", "pre_3_1_delta"
    local function private_snapshot(c, owner)
        local _, template = owner.template(); local profiles = {}
        for _, name in ipairs(F.names) do profiles[name] = c.env.DamageProfileTemplates[F.prefix .. name] end
        return assert(c.graph.capture({ template, profiles, c.lookup, c.state._cwv_damage_profile_wire_source,
            c.audit() }, 8192, 131072))
    end
    local function refusal(c, owner, message, authority)
        local before = F.snapshot(c)
        local foreign = authority and assert(c.graph.capture(authority, 8192, 65536))
        H.equal(owner.construct(), false, message); H.equal(owner.template(), nil); H.truthy(owner.check())
        H.truthy(c.graph.intact(before), "typed refusal preserves every observed owned/foreign cell")
        if foreign then H.truthy(c.graph.intact(foreign), "typed refusal never repairs foreign authority") end
    end
    native_test("#645 Tuskgor typed baseline allows absent or actual Current WT without getter polling", function()
        for _, id in ipairs({ false, "wt", "wt_dev" }) do
            local c = F.new(H, root, id and { history = "current", stream = id } or nil)
            local r = id and c.history.records[id]
            local calls = r and r.getter_calls
            local donor = c.env.Weapons[F.donor]
            local before = assert(c.graph.capture(donor, 16384, 262144))
            local owner = c.create(); H.truthy(owner.construct()); F.verify(H, c, owner)
            H.truthy(rawequal(c.env.Weapons[F.donor], donor) and c.graph.intact(before), "baseline donor unchanged")
            H.equal(c.env.Weapons[F.donor][KEY], .5)
            if r then H.equal(r.getter_calls, calls, "history admission reads applied tuple, not menu") end
        end
    end)
    native_test("#645 Tuskgor actual WT restore and reapply preserve typed independent receiver block policy", function()
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local c = F.new(H, root, { history = STATE, stream = id })
            local r, owner = c.history.records[id], c.create()
            H.equal(c.env.Weapons[F.donor][KEY], .25); H.truthy(owner.construct()); F.verify(H, c, owner)
            local before, generation, calls = private_snapshot(c, owner), c.state._cwv_damage_profile_generation, r.getter_calls
            H.equal(r.owner:restore(), true); H.equal(c.env.Weapons[F.donor][KEY], .5)
            H.equal(owner.check(), nil, "actual WT restore must not revoke independent Elf block policy")
            F.verify(H, c, owner)
            H.equal(r.owner:reconcile("tuskgor-typed-test"), true); H.equal(c.env.Weapons[F.donor][KEY], .25)
            H.equal(owner.check(), nil, "actual WT reapply must preserve the same typed constructor")
            F.verify(H, c, owner); H.truthy(c.graph.intact(before), "lifecycle changes no custom graph audit or lookup")
            local _, template = owner.template(); H.equal(template[KEY], .5)
            H.equal(c.state._cwv_damage_profile_generation, generation); H.equal(r.getter_calls, calls)
        end
    end)
    native_test("#645 Tuskgor pending dropdown is not applied history authority", function()
        for _, id in ipairs({ "wt", "wt_dev" }) do
            local c = F.new(H, root, { history = STATE, stream = id })
            local r, owner = c.history.records[id], c.create(); H.truthy(owner.construct())
            local before = F.snapshot(c)
            r.pending("current"); H.equal(r.runtime.pending[SETTING], true)
            local calls = r.getter_calls
            H.equal(c.env.Weapons[F.donor][KEY], .25); H.equal(r.runtime.boot_selections[SETTING], STATE)
            F.verify(H, c, owner); H.equal(r.getter_calls, calls)
            H.truthy(c.graph.intact(before), "pending UI choice cannot alter the donor or private result")
        end
    end)
    native_test("#645 Tuskgor naked historical scalar refuses without late authority repair", function()
        local c = F.new(H, root); c.env.Weapons[F.donor][KEY] = .25
        local owner = c.create()
        refusal(c, owner, "naked historical scalar must never construct")
        c.env.Weapons[F.donor][KEY] = .5
        H.equal(owner.construct(), false, "failed first history capture cannot later recapture baseline")
        H.equal(owner.template(), nil)
    end)
    native_test("#645 Tuskgor malformed WT presence cannot be treated as absent Current", function()
        local bad = {
            function(c, id) c.history.mods[id] = false end,
            function(c, id) c.history.mods[id] = {} end,
            function(c, id) c.history.mods[id] = { _wt_history_runtime = false } end,
            function(c, id) c.history.mods[id] = { _wt_history_runtime = {} } end,
        }
        for _, id in ipairs({ "wt", "wt_dev" }) do for _, change in ipairs(bad) do
            local c = F.new(H, root); change(c, id); refusal(c, c.create(), "malformed present authority must refuse")
        end end
    end)
    native_test("#645 Tuskgor replaced retained producer authority cannot revive by restoring old references", function()
        local changes = {
            function(c, r, id) local old = c.history.mods[id]; c.history.mods[id] = {}; return function() c.history.mods[id] = old end end,
            function(_, r) local old = r.mod._wt_history_runtime; r.mod._wt_history_runtime = {}; return function() r.mod._wt_history_runtime = old end end,
            function(_, r) local old = r.runtime.catalog; r.runtime.catalog = {}; return function() r.runtime.catalog = old end end,
            function(_, r) local old = r.runtime.policy; r.runtime.policy = {}; return function() r.runtime.policy = old end end,
            function(_, r) local old = r.runtime.ledgers; r.runtime.ledgers = {}; return function() r.runtime.ledgers = old end end,
            function(_, r) local old = r.runtime.active; r.runtime.active = {}; return function() r.runtime.active = old end end,
            function(_, r) local old = r.runtime.boot_selections; r.runtime.boot_selections = {}; return function() r.runtime.boot_selections = old end end,
            function(_, r) local old = r.runtime.roots.Weapons; r.runtime.roots.Weapons = {}; return function() r.runtime.roots.Weapons = old end end,
            function(_, r) local old = r.runtime.verify; r.runtime.verify = function() end; return function() r.runtime.verify = old end end,
        }
        for _, id in ipairs({ "wt", "wt_dev" }) do for _, change in ipairs(changes) do
            local c = F.new(H, root, { history = STATE, stream = id })
            local r, owner = c.history.records[id], c.create(); H.truthy(owner.construct())
            local restore = change(c, r, id)
            refusal(c, owner, "replaced retained authority must close admission", { r.mod, r.runtime, c.history.mods })
            restore(); H.equal(owner.construct(), false, "restoring authority cannot revive poisoned capability")
            H.equal(owner.template(), nil)
        end end
    end)
    native_test("#645 Tuskgor actual ledger proof cannot exempt unrelated cells or forged ownership", function()
        local changes = {
            function(c) c.env.Weapons[F.donor].block_angle = 99 end,
            function(c) c.env.Weapons[F.receiver].actions.action_inspect.default.total_time = 99 end,
            function(c, r) r.runtime.ledgers.tuskgor_spear[1].parent = {} end,
            function(c, r) r.runtime.ledgers.tuskgor_spear[1].applied_snapshot = .5 end,
            function(c, r) r.runtime.family_by_id.tuskgor_spear.states[STATE].operations[1].result = .125 end,
        }
        for _, id in ipairs({ "wt", "wt_dev" }) do for _, change in ipairs(changes) do
            local c = F.new(H, root, { history = STATE, stream = id })
            local r, owner = c.history.records[id], c.create(); H.truthy(owner.construct())
            change(c, r); refusal(c, owner, "typed one-cell exception cannot forgive foreign graph or ledger drift", { r.mod, r.runtime })
        end end
    end)
    native_test("#645 Tuskgor captured WT loss or resolver error refuses even after actual Current restore", function()
        for _, id in ipairs({ "wt", "wt_dev" }) do for _, mode in ipairs({ "missing_mod", "missing_runtime", "resolver_error" }) do
            local c = F.new(H, root, { history = STATE, stream = id })
            local r, owner = c.history.records[id], c.create(); H.truthy(owner.construct())
            H.equal(r.owner:restore(), true); H.equal(c.env.Weapons[F.donor][KEY], .5)
            H.equal(owner.check(), nil)
            if mode == "missing_runtime" then r.mod._wt_history_runtime = nil
            else
                c.history.mods[id] = nil
                if mode == "resolver_error" then setmetatable(c.history.mods, { __index = function(_, key)
                    if key == id then error("actual resolver boundary unavailable", 0) end
                end }) end
            end
            refusal(c, owner, "captured authority loss at Current must fail closed", { r.mod, r.runtime, c.history.mods })
            setmetatable(c.history.mods, nil); c.history.mods[id] = r.mod; r.mod._wt_history_runtime = r.runtime
            H.equal(owner.construct(), false, "returning a lost producer cannot recapture authority")
            H.equal(owner.template(), nil)
        end end
    end)
    native_test("#645 Tuskgor typed constructor binding has no unproved fallback path", function()
        local c = F.new(H, root)
        local module = assert(loadfile(root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_tuskgor_spear_style_construction.lua"))()
        local before = F.snapshot(c); local ok = pcall(module.bind, c.helper, c.graph)
        H.equal(ok, false, "private history dependency is mandatory, never a test-only/native bypass")
        H.truthy(c.graph.intact(before))
    end)
end
