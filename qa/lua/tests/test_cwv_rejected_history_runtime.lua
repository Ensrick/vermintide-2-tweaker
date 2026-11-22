-- WP-CWV-13: CWV construction survives a rejected wt_dev history runtime.
-- With both WT streams loaded, wt_dev's actual profile transaction refuses the
-- private names public wt already published ("private history tuple partial or
-- foreign", _wt_history_profile_transaction.lua:121-123), yet wt_dev still
-- publishes the inert runtime (_wt_history_owner.lua:57). The shared producer
-- binding must report that stream as absent so the Javelin family takes its
-- no-history path (_cwv_javelin_history_envelope.lua:138 rejected it before),
-- in both load orders. Uses the actual WT runtimes from both trees.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_javelin_history_owner.lua")
    local Binding = dofile(root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_history_producer_binding.lua")
    local function both(install, wt_state)
        install("wt", wt_state or "current")
        return install("wt_dev", "current", nil, "rejected")
    end
    local function construct_after(wt_state)
        return F.new(H, root, { before = function(_, install) both(install, wt_state) end }):install()
    end

    H.test("WP-CWV-13 cwv after wt + rejected wt_dev (Current) constructs Javelin", function()
        local c = construct_after("current")
        H.truthy(c.env.Weapons.tuskgor_javelin_template, "tuskgor_javelin_template built")
        F.admitted(H, c)
        H.equal(#(c.histories.wt.runtime.ledgers.javelin or {}), 0)
    end)
    H.test("WP-CWV-13 cwv after historical wt + rejected wt_dev keeps wt authority", function()
        local c = construct_after("5_1_1")
        H.truthy(c.env.Weapons.tuskgor_javelin_template, "tuskgor_javelin_template built")
        F.admitted(H, c)
        H.equal(#c.histories.wt.runtime.ledgers.javelin, 7)
        H.equal(c.histories.wt.owner:restore(), true); F.admitted(H, c)
    end)
    H.test("WP-CWV-13 cwv before wt + rejected wt_dev retains Javelin", function()
        local c = F.new(H, root):install(); F.admitted(H, c)
        c.install_history("wt", "5_1_1"); F.admitted(H, c)
        c.install_history("wt_dev", "current", nil, "rejected"); F.admitted(H, c)
        H.equal(c.histories.wt.owner:reconcile("wp-cwv-13"), true); F.admitted(H, c)
    end)

    -- Fail closed: only an inert rejected runtime counts as absent.
    local present = {
        { "recorded ledger row", function(row) row.runtime.ledgers.javelin = { {} } end },
        { "recorded active row", function(row) row.runtime.active.javelin = { state = "5_1_1", parity = true } end },
        { "cleared fatal_error", function(row) row.runtime.fatal_error = nil end },
        { "runtime metatable", function(row) setmetatable(row.runtime, {}) end },
        { "foreign runtime mod", function(row) row.runtime.mod = {} end },
    }
    for _, case in ipairs(present) do
        H.test("WP-CWV-13 rejected runtime with " .. case[1] .. " is not absent", function()
            local c = construct_after("current"); F.admitted(H, c)
            case[2](c.histories.wt_dev); F.denied(H, c)
        end)
    end

    H.test("WP-CWV-13 binding resolve reports only an inert rejected runtime as absent", function()
        local mods = {}
        local graph = { capture = function() return {} end, intact = function() return true end }
        local b = Binding.bind(graph, function(id) return mods[id] end)
        local rejected = { }
        rejected._wt_history_runtime = { mod = rejected, fatal_error = "rejected", ledgers = {}, active = {} }
        local healthy = { }
        healthy._wt_history_runtime = { mod = healthy, ledgers = {}, active = {} }
        mods.wt, mods.wt_dev = healthy, rejected
        local ok, mod = b.resolve("wt"); H.equal(ok, true); H.truthy(rawequal(mod, healthy))
        ok, mod = b.resolve("wt_dev"); H.equal(ok, true); H.equal(mod, nil)
        H.equal(Binding.rejected(nil), false); H.equal(Binding.rejected({}), false)
        H.equal(Binding.rejected(healthy), false); H.equal(Binding.rejected(rejected), true)
        ok = b.resolve("other"); H.equal(ok, false)
    end)
end
