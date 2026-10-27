-- #428 raw reference authority: Lua __eq never attests retained identity.
return function(H, root)
    local prefix = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local graph = dofile(prefix .. "_cwv_profile_graph_transaction.lua")
    local quiet = setmetatable({ test = function() end }, { __index = H })
    local C = dofile(root .. "/qa/lua/tests/test_cwv_career_envelope.lua")(quiet, root)
    local KEY, CLAIMS = "action_career_wh_2", "__vt2_tweaker_career_action_claims"
    local function pair(a, b)
        local meta = { __eq = function() return true end }
        setmetatable(a, meta); setmetatable(b, meta)
        H.equal(rawequal(a, b), false)
        H.equal(a == b, true, "counterfactual __eq is active")
        return a, b
    end
    H.test("#428 graph exact healthy aliases functions metatable and transaction remain accepted", function()
        local shared, fn, meta = {}, function() end, {}
        local root = setmetatable({ a = shared, b = shared, callback = fn, flag = false }, meta)
        local proof = assert(graph.capture(root, 8, 16))
        H.truthy(graph.intact(proof)); H.truthy(graph.intact(proof, true))
        H.equal(rawequal(root.a, root.b), true); H.equal(rawequal(root.callback, fn), true)
        local target, before, after = {}, {}, {}
        target.value = before
        H.truthy(graph.commit({ { target, "value", after, before = before } }, function() end,
            function() end, rawget, rawset))
        H.equal(rawequal(target.value, after), true)
    end)
    H.test("#428 graph refuses equal-comparing foreign child", function()
        local original, foreign = pair({}, {})
        local root = { child = original }
        local proof = assert(graph.capture(root, 8, 16)); H.truthy(graph.intact(proof))
        root.child = foreign
        H.equal(graph.intact(proof), false); H.equal(graph.intact(proof, true), false)
    end)
    H.test("#428 graph refuses equal-comparing foreign metatable", function()
        local original, foreign = pair({}, {})
        local root = setmetatable({}, original)
        local proof = assert(graph.capture(root, 8, 16)); H.truthy(graph.intact(proof))
        setmetatable(root, foreign)
        H.equal(graph.intact(proof), false); H.equal(graph.intact(proof, true), false)
    end)
    H.test("#428 graph stale equal-comparing preimage cannot write", function()
        local expected, foreign = pair({}, {})
        local root, writes = { value = foreign }, 0
        local ok = graph.commit({ { root, "value", {}, before = expected } }, function() end,
            function() end, rawget, function(t, k, v) writes = writes + 1; rawset(t, k, v) end)
        H.equal(ok, false); H.equal(writes, 0); H.equal(rawequal(root.value, foreign), true)
    end)
    H.test("#428 graph equal-comparing foreign readback rolls back exact before", function()
        local intended, foreign = pair({}, {})
        local before, root, writes = {}, {}, 0
        root.value = before
        local ok = graph.commit({ { root, "value", intended, before = before } }, function() end,
            function() end, function() return foreign end,
            function(t, k, v) writes = writes + 1; rawset(t, k, v) end)
        H.equal(ok, false); H.equal(writes, 1); H.equal(rawequal(root.value, before), true)
    end)
    for _, kind in ipairs({ "short", "javelin" }) do
        local family = kind
        H.test("#428 raw identity " .. family .. " actual target canonical replacement denies item and seed", function()
            local c = C.context(family); C.wt(c, "wt_dev", c.template); C.healthy(c)
            local canonical = c.env.ActionTemplates[KEY]
            -- Same-object content is deliberately delegated, not gameplay proof.
            canonical.default.kind = "same-canonical-content-LIMIT"
            C.healthy(c)
            local _, foreign = pair(canonical, { default = { kind = "foreign" } })
            c.template.actions[KEY] = foreign
            C.denied(c)
        end)
        H.test("#428 raw identity " .. family .. " actual foreign claim value denies item and seed", function()
            local c = C.context(family); C.wt(c, "wt_dev", c.template); C.healthy(c)
            local canonical = c.env.ActionTemplates[KEY]
            local _, foreign = pair(canonical, { default = { kind = "foreign-claim" } })
            c.template[CLAIMS][KEY].value = foreign
            H.equal(rawequal(c.template.actions[KEY], canonical), true)
            C.denied(c)
        end)
    end
    H.test("#428 raw identity actual replaced canonical root denies item and seed", function()
        local c = C.context("short"); C.wt(c, "wt_dev", c.template); C.healthy(c)
        local canonical, replacement = c.env.ActionTemplates, {}
        for k, v in next, canonical do replacement[k] = v end
        pair(canonical, replacement); c.env.ActionTemplates = replacement
        C.denied(c)
    end)
    H.test("#428 raw identity initial noncanonical native row remains exact", function()
        local initial, foreign = pair({ default = { kind = "native-private" } }, { default = { kind = "foreign" } })
        local c = C.context("short", { before = function(c)
            c.source.actions.action_career_native_private = initial
        end })
        C.healthy(c); c.source.actions.action_career_native_private = foreign; C.denied(c)
    end)
    H.test("#428 raw identity include filter cannot exclude equal-comparing unrelated node", function()
        local nested
        local c = C.context("short", { before = function(c)
            nested = { action_career_hidden = { value = "pinned" } }
            pair(c.source.actions, nested); c.source.review_nested = nested
        end })
        C.healthy(c); nested.action_career_hidden = { value = "foreign" }; C.denied(c)
    end)
    H.test("#428 exact original prefixed unknown WT token is denied", function()
        local c = C.context("javelin")
        C.shared(c, c.source, "weapon_tweaker:outside-private-fixture")
        C.denied(c)
    end)
    H.test("#428 raw identity real source and target public dev release controls remain accepted", function()
        local c = C.context("short")
        local _, public = C.wt(c, "wt", c.source); C.healthy(c)
        local _, dev = C.wt(c, "wt_dev", c.template); C.healthy(c)
        c.integration.release(c.source, public); C.healthy(c)
        c.integration.release(c.template, dev); C.healthy(c)
    end)
end
