-- test_rig_api_settings.lua: offline tests of the rig's helper groups lib/settings.lua (T.set) and lib/shot.lua
-- (T.shot: the WP-H-06 stub, the still request since WP-H-10), WP-H-06 steps 3 and 4.
--
-- Boots the real bootstrap and driver with the real helper groups in plan.libs (as New-RigProfile.ps1 -LibDir sends
-- them) inside the simulated game of _rig_driver_env.lua. A stub mod stands in for a VMF mod: its get/set follow
-- VMFMod:get/set (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:46-75) and set with
-- notify_mod calls its on_setting_changed (modules/core/events.lua:79-84). This proves the helpers' control flow and
-- evidence lines only, never that a real mod reacts: that is what qa/runtime/plans/api-selftest.json is for.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local tag, first, count = E.tag, E.first, E.count

    -- A stub VMF mod. changed records every on_setting_changed call and whether it ran in the case coroutine.
    local function stub_mod(name, settings)
        local mod = { settings = settings or {}, changed = {} }
        function mod:get_name()
            return name
        end
        function mod:get(id)
            return self.settings[id]
        end
        function mod:set(id, value, notify)
            self.settings[id] = value
            if notify and self.on_setting_changed then
                self.on_setting_changed(id)
            end
        end
        mod.on_setting_changed = function(id)
            mod.changed[#mod.changed + 1] = { id = id, value = mod.settings[id], in_coroutine = coroutine.running() ~= nil }
        end
        return mod
    end

    local function run(cases, mods, libs)
        local plan = E.make_plan(cases, { libs = libs or { E.lib_entry("settings"), E.lib_entry("shot") } })
        local object, env, lines = E.boot(plan)
        env.get_mod = function(name)
            return mods[name]
        end
        H.truthy(E.run_to_end(object, env), "run completed")
        return lines
    end

    H.test("rig T.set: the mod's own setter runs with its event in the main update, and the case end restores", function()
        local gt = stub_mod("gt_dev", { opt = false, level = 2 })
        local lines = run({
            { id = "set-twice", src = [[
return { run = function(T)
    local was = T.set("gt_dev", "opt", true)
    T.expect_eq(was, false, "first T.set returns the old value")
    T.expect_eq(get_mod("gt_dev"):get("opt"), true, "the option holds the new value")
    local again = T.set("gt_dev", "opt", "x")
    T.expect_eq(again, true, "second T.set returns the value of the first")
    T.set("gt_dev", "level", 5)
end }
]] },
            { id = "after", src = [[
return { run = function(T)
    T.expect_eq(get_mod("gt_dev"):get("opt"), false, "restored to the value before the first T.set")
    T.expect_eq(get_mod("gt_dev"):get("level"), 2, "second option restored too")
end }
]] },
        }, { gt_dev = gt })
        H.truthy(first(lines, tag .. "CASE END id=set%-twice verdict=PASS asserts=3 failed=0"), "set-twice passes")
        H.truthy(first(lines, tag .. "CASE END id=after verdict=PASS asserts=2 failed=0"), "the next case sees the restored values")
        H.truthy(first(lines, tag .. "SET id=set%-twice mod=gt_dev setting=opt value=\"true\" was=\"false\""), "SET line names value and old value")
        H.truthy(first(lines, tag .. "SET RESTORE id=set%-twice mod=gt_dev setting=opt value=\"false\""), "restore puts back the first old value")
        H.truthy(first(lines, tag .. "CLEANUP id=set%-twice actions=2 errors=0"), "one cleanup per option, not per call")
        H.equal(#gt.changed, 5, "on_setting_changed ran for three sets and two restores")
        for i, call in ipairs(gt.changed) do
            H.equal(call.in_coroutine, false, "on_setting_changed call " .. i .. " ran in the main update")
        end
        H.equal(gt.changed[4].id .. "=" .. tostring(gt.changed[4].value), "level=2", "restores run newest first")
        H.equal(gt.changed[5].id .. "=" .. tostring(gt.changed[5].value), "opt=false", "the first option is restored last")
    end)

    H.test("rig T.set: an ERROR after the change still restores; a missing mod is INCONCLUSIVE", function()
        local gt = stub_mod("gt_dev", { opt = false })
        local lines = run({
            { id = "boom", src = "return { run = function(T) T.set('gt_dev', 'opt', true) error('planted error after T.set') end }" },
            { id = "no-mod", src = "return { run = function(T) T.set('ct_dev', 'opt', true) end }" },
        }, { gt_dev = gt })
        H.truthy(first(lines, tag .. "CASE END id=boom verdict=ERROR .*planted error after T.set"), "ERROR reported")
        H.equal(gt.settings.opt, false, "option restored after the ERROR")
        H.truthy(first(lines, tag .. "CASE END id=no%-mod verdict=INCONCLUSIVE .*mod ct_dev loaded"), "missing mod is INCONCLUSIVE")
    end)

    -- WP-H-10: the request is one-way (the game cannot hear back): vt2_rig_shot saved in the main update, SHOT REQ,
    -- a hold, SHOT DONE; request numbers count across cases; at most five per case; a failed save returns nil.
    H.test("rig T.shot: saves the request, holds, returns its number; five per case; a failed save is nil", function()
        local plan = E.make_plan({
            { id = "shots", src = [[
return { run = function(T)
    local t0 = T.now and T.now() or 0
    T.expect_eq(T.shot("first still"), 1, "the first request is number 1")
    T.expect_eq(T.shot("second still", 2), 2, "the second is number 2")
    for i = 3, 5 do T.shot("more " .. i, 1) end
    T.expect_eq(T.shot("sixth"), nil, "a sixth still in one case is refused")
end }
]] },
            { id = "next-case", src = "return { run = function(T) T.expect_eq(T.shot('other case', 1), 6, 'numbers continue in the next case') end }" },
        }, { libs = { E.lib_entry("shot") } })
        local object, env, lines, settings = E.boot(plan)
        local saved = {}
        local save = env.Application.save_user_settings
        env.Application.save_user_settings = function()
            local s = settings.vt2_rig_shot
            if s and saved[#saved] ~= s then
                saved[#saved + 1] = s
            end
            return save()
        end
        H.truthy(E.run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=shots verdict=PASS"), "shots passes: " .. tostring(first(lines, tag .. "CASE END id=shots")))
        H.truthy(first(lines, tag .. "CASE END id=next%-case verdict=PASS"), "next-case passes: " .. tostring(first(lines, tag .. "CASE END id=next%-case")))
        H.equal(#saved, 6, "six requests saved")
        H.equal(saved[1].nonce .. "/" .. saved[1].seq .. "/" .. saved[1].case .. "/" .. saved[1].n .. "/" .. saved[1].label, E.NONCE .. "/1/shots/1/first still", "the saved request")
        H.equal(saved[6].case .. "/" .. saved[6].n .. "/" .. saved[6].seq, "next-case/1/6", "the next case's first request")
        H.truthy(first(lines, tag .. "SHOT REQ id=shots n=1 seq=1 label=\"first still\" hold=3 saved=true"), "SHOT REQ line")
        H.truthy(first(lines, tag .. "SHOT REQ id=shots n=2 seq=2 label=\"second still\" hold=2 saved=true"), "hold given by the case")
        H.truthy(first(lines, tag .. "SHOT id=shots n=6 label=\"sixth\" captured=false refused=\"more than 5 stills in one case\""), "the refusal line")
        local req_t = tonumber((first(lines, tag .. "SHOT REQ id=shots n=1 ") or ""):match("t=([%d%.]+)$"))
        local done_t = tonumber((first(lines, tag .. "SHOT DONE id=shots n=1 seq=1") or ""):match("t=([%d%.]+)$"))
        H.truthy(req_t and done_t and done_t - req_t >= 2.9, "SHOT DONE comes after the hold (" .. tostring(req_t) .. " -> " .. tostring(done_t) .. ")")

        local plan2 = E.make_plan({ { id = "nosave", src = "return { run = function(T) T.expect_eq(T.shot('x'), nil, 'a request that could not be saved is nil') end }" } }, { libs = { E.lib_entry("shot") } })
        local object2, env2, lines2 = E.boot(plan2)
        env2.Application.set_user_setting = function(key, value)
            if key == "vt2_rig_shot" then
                error("planted save error")
            end
        end
        H.truthy(E.run_to_end(object2, env2), "run completed (save fails)")
        H.truthy(first(lines2, tag .. "SHOT REQ id=nosave n=1 seq=1 label=\"x\" hold=3 saved=false"), "saved=false")
        H.truthy(first(lines2, tag .. "CASE END id=nosave verdict=PASS"), "the case goes on")
        H.equal(count(lines2, tag .. "SHOT DONE"), 0, "no hold for an unsaved request")
    end)

    -- The three cases of qa/runtime/plans/api-selftest.json, in its order, against stubs: catches a script defect
    -- before the plan costs a rig run. A PASS here says nothing about the game.
    H.test("rig api-selftest cases: pass in the simulated game, the VMF marker option restored", function()
        local plan = E.make_plan({
            { id = "api-core", src = E.read(repo_root .. "/qa/runtime/_rig/api_core.lua") },
            { id = "api-set", src = E.read(repo_root .. "/qa/runtime/_rig/api_set.lua") },
            { id = "api-set-restored", src = E.read(repo_root .. "/qa/runtime/_rig/api_set_restored.lua") },
        }, {
            libs = { E.lib_entry("settings"), E.lib_entry("shot") },
            shared = { { id = "official_mirror", hex = E.hex(E.read(repo_root .. "/qa/runtime/_shared/official_mirror.lua")) } },
        })
        local object, env, lines = E.boot(plan, { backend = { get_backend_mirror = function() return {} end } })
        local hero = env.Managers.player:local_player().player_unit
        env.ScriptUnit = {
            has_extension = function(unit, system)
                if unit == hero and system == "health_system" then
                    return {}
                end
            end,
        }
        local vmf = stub_mod("VMF", {})
        vmf.get_commands_list = function()
            return { { name = "vmf_command" } }
        end
        env.get_mod = function(name)
            return name == "VMF" and vmf or nil
        end
        H.truthy(E.run_to_end(object, env), "run completed")
        for _, id in ipairs({ "api%-core", "api%-set", "api%-set%-restored" }) do
            H.truthy(first(lines, tag .. "CASE END id=" .. id .. " verdict=PASS"), id .. " passes: " .. tostring(first(lines, tag .. "CASE END id=" .. id)))
        end
        H.truthy(first(lines, tag .. "SET RESTORE id=api%-set mod=VMF setting=vt2_rig_api_selftest"), "the plan's host_expect_log restore line is printed")
        H.truthy(first(lines, tag .. "SHOT REQ id=api%-core n=1 seq=1 label=\"api selftest still\" hold=3 saved=true"), "the plan's host_expect_log shot line is printed")
        H.equal(vmf.settings.vt2_rig_api_selftest, nil, "marker option back to nil")
    end)

    H.test("rig helper groups: loaded in plan order; a broken group is named and its helpers stay absent", function()
        local lines = run({
            { id = "uses-set", src = "return { run = function(T) T.set('gt_dev', 'opt', true) end }" },
            { id = "uses-shot", src = "return { run = function(T) T.expect_eq(T.shot('x', 1), 1, 'shot still works') end }" },
        }, { gt_dev = stub_mod("gt_dev", {}) }, {
            { id = "settings", hex = E.hex("return function(T, ctx) error('planted install error') end") },
            { id = "broken", hex = E.hex("this is not lua") },
            { id = "table", hex = E.hex("return {}") },
            E.lib_entry("shot"),
        })
        H.truthy(first(lines, tag .. "LIB id=settings ok=true"), "a group that compiles is loaded")
        H.truthy(first(lines, tag .. "LIB id=broken ok=false err="), "a group that does not compile is named")
        H.truthy(first(lines, tag .. "LIB id=table ok=false err=\"returned table, not an install function\""), "a group must return its install function")
        H.truthy(first(lines, tag .. "LIB ERROR id=settings case=uses%-set err=.*planted install error"), "an install error is named per case")
        H.truthy(first(lines, tag .. "CASE END id=uses%-set verdict=ERROR"), "a case calling a helper of the failed group ends as ERROR")
        H.truthy(first(lines, tag .. "CASE END id=uses%-shot verdict=PASS"), "the other groups still install")
        H.equal(count(lines, tag .. "LIB id="), 4, "one LIB line per group")
    end)
end
