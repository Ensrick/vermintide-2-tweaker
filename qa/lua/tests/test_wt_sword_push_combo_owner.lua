-- #348 retained entry DI and real producer reentry; no cached-dofile assumption.
return function(H, root)
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local Shared = assert(loadfile(root .. "/qa/lua/tests/test_cwv_sword_donor_envelope.lua"))()(quiet, root)
    local SWORD, RECORD = "one_handed_swords_template_1", "_wt348_sword_push_combo"
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
    end
    local function fixture(id, enabled, missing)
        local c = Shared.setup({ early = true, stream = id, combo = enabled, emit = false })
        local r = c.records[id]
        local source = read(root .. "/" .. r.dir .. "/scripts/mods/" .. r.dir .. "/_wt_weapon_balance_patches.lua")
        local a = assert(source:find("local function _patch_kruber_1h_sword_push_combo_revert()", 1, true))
        local b = assert(source:find("\n-- ============================================================\n-- Warrior Priest punch buff", a, true))
        local actual = c.T.run("return function(mod, _dbg)\n" .. source:sub(a, b - 1)
            .. "\nreturn rawget(mod, \"_wt348_sword_push_combo\") end", c.env, "actual348-producer")
        if missing then c.env.Weapons[SWORD] = nil end
        return c, r, function() return actual(r.mod, r.mod._wt.dbg) end
    end
    local function capture(c, record)
        return assert(c.graph.capture({ c.env.Weapons, record or {} }, 8192, 131072))
    end
    local function refused(c, r, expected, original)
        local apply = rawget(r.mod._wt, "apply_sword_push_combo")
        H.equal(type(apply), "function", "real retained entry capability resolves")
        local weapons, public, reads = c.env.Weapons, rawget(r.mod, RECORD), r.calls.combo_get
        local before = capture(c, { public = public, original = original })
        local callbacks = 0
        local value, reason = apply(weapons, function()
            callbacks = callbacks + 1; error("refused producer callback must not run", 0)
        end)
        H.equal(value, nil, "unknown authority cannot report installed success")
        H.equal(reason, expected, "exact retained-entry refusal reason")
        H.equal(callbacks, 0); H.equal(r.calls.combo_get, reads, "refusal never reads a pending checkbox")
        H.truthy(rawequal(c.env.Weapons, weapons), "refusal preserves the Weapons root")
        H.truthy(rawequal(rawget(r.mod, RECORD), public), "refusal never publishes or repairs a record")
        H.truthy(c.graph.intact(before), "refusal preserves current and retained native/record graphs")
    end
    for _, stream in ipairs({ "wt", "wt_dev" }) do
        local id = stream
        for _, flag in ipairs({ false, true }) do
            local enabled = flag
            H.test(id .. " #348 healthy reentry ignores both pending checkbox directions", function()
                local c, r, produce = fixture(id, enabled)
                local original = c.env.Weapons[SWORD].actions.action_one.light_attack_bopp.allowed_chain_actions
                local record = assert(produce())
                H.equal(record.boot_enabled, enabled)
                H.truthy(rawequal(record.before, original))
                if enabled then H.equal(rawequal(record.before, record.applied), false)
                else H.truthy(rawequal(record.before, record.applied)) end
                Shared.actual_combo(c, r, enabled)
                local before = capture(c, record)
                local path = "scripts/mods/" .. r.dir .. "/_wt_sword_push_combo_owner"
                H.equal(r.loads[path], 1, "actual entry loads private owner once")
                for _, pending in ipairs({ not enabled, enabled }) do
                    r.saved.wt_revert_1h_sword_push_combo = pending
                    H.truthy(rawequal(produce(), record), "same exact public record")
                    H.equal(r.calls.combo_get, 1, "no reentry setting read or patch replay")
                    H.equal(r.loads[path], 1, "producer never reloads its owner")
                    H.truthy(c.graph.intact(before))
                end
            end)
            H.test(id .. " #348 missing Sword has stable closed boot record enabled=" .. tostring(enabled), function()
                local c, r, produce = fixture(id, enabled, true)
                local record = assert(produce())
                H.equal(record.source, nil); H.equal(record.action, nil)
                H.equal(record.before, nil); H.equal(record.applied, nil)
                H.truthy(rawequal(record.weapons, c.env.Weapons))
                local before = capture(c, record)
                H.truthy(rawequal(produce(), record)); H.equal(r.calls.combo_get, 1)
                H.truthy(c.graph.intact(before))
                c.env.Weapons[SWORD] = c.env.table.clone(c.current.empire_on_elf.template, true)
                local changed = capture(c, record)
                H.truthy(rawequal(produce(), record), "late source cannot recapture the boot record")
                H.equal(record.source, nil); H.equal(r.calls.combo_get, 1)
                H.truthy(c.graph.intact(changed))
                refused(c, r, "producer-authority-lost", record)
            end)
        end
        for _, fault in ipairs({ "replace_record", "remove_record", "record_drift", "record_metatable",
            "replace_weapons", "remove_weapons", "replace_source", "remove_source",
            "replace_action", "remove_action", "replace_chain", "remove_chain",
            "before_chain_drift", "chain_drift", "chain_metatable" }) do
            local mode = fault
            H.test(id .. " #348 unknown " .. mode .. " refuses without repair", function()
                local c, r, produce = fixture(id, true)
                local record = assert(produce())
                if mode == "replace_record" then
                    local replacement = {}; for key, value in next, record do replacement[key] = value end
                    r.mod[RECORD] = replacement
                elseif mode == "remove_record" then r.mod[RECORD] = nil
                elseif mode == "record_drift" then record.boot_enabled = false
                elseif mode == "record_metatable" then setmetatable(record, {})
                elseif mode == "replace_weapons" then c.env.Weapons = c.env.table.clone(c.env.Weapons, true)
                elseif mode == "remove_weapons" then c.env.Weapons = nil
                elseif mode == "replace_source" then c.env.Weapons[SWORD] = c.env.table.clone(record.source, true)
                elseif mode == "remove_source" then c.env.Weapons[SWORD] = nil
                elseif mode == "replace_action" then
                    record.source.actions.action_one.light_attack_bopp = c.env.table.clone(record.action, true)
                elseif mode == "remove_action" then record.source.actions.action_one.light_attack_bopp = nil
                elseif mode == "replace_chain" then record.action.allowed_chain_actions = c.env.table.clone(record.applied, true)
                elseif mode == "remove_chain" then record.action.allowed_chain_actions = nil
                elseif mode == "before_chain_drift" then record.before[1].start_time = .123
                elseif mode == "chain_metatable" then setmetatable(record.applied, {})
                else record.applied[1].start_time = .123 end
                local public = rawget(r.mod, RECORD)
                local before = capture(c, { public = public, original = record })
                produce()
                H.truthy(rawequal(rawget(r.mod, RECORD), public))
                H.equal(r.calls.combo_get, 1); H.truthy(c.graph.intact(before))
                refused(c, r, "producer-authority-lost", record)
            end)
        end
        H.test(id .. " #348 foreign preexisting record never becomes boot authority", function()
            local c, r, produce = fixture(id, true)
            local foreign = { schema = 1, setting_id = "wt_revert_1h_sword_push_combo" }
            r.mod[RECORD] = foreign
            local before = capture(c, foreign)
            H.truthy(rawequal(produce(), foreign))
            H.equal(r.calls.combo_get, 0); H.truthy(c.graph.intact(before))
            refused(c, r, "record-without-private-authority", foreign)
        end)
        H.test(id .. " #348 private module cache loss cannot adopt public record", function()
            local c, r, produce = fixture(id, true)
            local record = assert(produce()); local before = capture(c, record)
            local fresh = c.T.run(read(root .. "/" .. r.dir .. "/scripts/mods/" .. r.dir
                .. "/_wt_sword_push_combo_owner.lua"), c.env, "fresh348-module-cache-loss")
            local calls = 0
            local function forbidden() calls = calls + 1; error("unknown callback must not run", 0) end
            local value, reason = fresh.install(r.mod, c.env.Weapons, forbidden, forbidden)
            H.equal(value, nil); H.equal(reason, "record-without-private-authority")
            H.equal(calls, 0); H.truthy(rawequal(rawget(r.mod, RECORD), record))
            H.truthy(c.graph.intact(before))
        end)
        H.test(id .. " #348 lost entry handoff cannot recapture or replay", function()
            local c, r, produce = fixture(id, true)
            local record = assert(produce()); local before = capture(c, record)
            local retained = r.mod._wt.apply_sword_push_combo
            r.mod._wt.apply_sword_push_combo = nil
            produce()
            local called = 0
            local value, reason = retained(c.env.Weapons, function() called = called + 1 end)
            H.equal(value, nil); H.equal(reason, "entry-capability-replaced")
            H.equal(called, 0); H.equal(r.calls.combo_get, 1)
            H.truthy(rawequal(rawget(r.mod, RECORD), record)); H.truthy(c.graph.intact(before))
        end)
        H.test(id .. " #348 failed boot getter stays closed without native repair", function()
            local c, r, produce = fixture(id, true)
            local getter = r.mod.get
            r.mod.get = function() error("qa348-setting-read", 0) end
            local before = capture(c)
            local ok, problem = pcall(produce)
            H.equal(ok, false); H.equal(problem, "qa348-setting-read")
            H.truthy(c.graph.intact(before))
            r.mod.get = getter
            H.equal(produce(), nil); H.equal(r.calls.combo_get, 0)
            H.truthy(c.graph.intact(before))
            refused(c, r, "producer-authority-lost")
        end)
        H.test(id .. " #348 throwing actual patch preserves error and never grants authority", function()
            local c, r, produce = fixture(id, true)
            local action = c.env.Weapons[SWORD].actions.action_one.light_attack_bopp
            local original, marker, calls = action.allowed_chain_actions, {}, 0
            local dbg = r.mod._wt.dbg
            r.mod._wt.dbg = function() calls = calls + 1; error(marker, 0) end
            local ok, problem = pcall(produce)
            H.equal(ok, false); H.truthy(rawequal(problem, marker), "exact original producer error object")
            H.equal(calls, 1); H.equal(rawget(r.mod, RECORD), nil)
            H.equal(rawequal(action.allowed_chain_actions, original), false,
                "actual patch assigned its native chain before the debug fault; no rollback claim")
            local after_failure = capture(c)
            r.mod._wt.dbg = dbg
            H.equal(produce(), nil); H.equal(calls, 1); H.equal(r.calls.combo_get, 1)
            H.equal(rawget(r.mod, RECORD), nil); H.truthy(c.graph.intact(after_failure))
            refused(c, r, "producer-authority-lost")
        end)
    end
end
