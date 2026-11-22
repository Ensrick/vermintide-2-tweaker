-- test_rig_driver.lua: offline run of the test rig driver (WP-H-01) and its backend write shield (WP-H-14).
--
-- Loads the real bootstrap (tools/harness/bootstrap/vt2_rig_driver.mod) and lets it compile the real driver
-- (tools/harness/driver/vt2_rig_driver.lua) from a plan that a stub Application.user_setting returns, exactly as
-- the game does. Every engine global the two files read is a stub inside a private environment, so nothing
-- leaks into the shared test process. The driver's callbacks are called the way the game's mod manager calls
-- them (pcall(cb, object, ...), Vermintide-2-Source-Code/scripts/managers/mod/mod_manager.lua:208-216).
--
-- This proves the driver's control flow and evidence lines only. It does not prove that any engine call
-- behaves like the stub: that is what rig runs are for.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local NONCE, tag = E.NONCE, E.tag
    local read, hex, make_plan, boot, callback, run_to_end, count, first =
        E.read, E.hex, E.make_plan, E.boot, E.callback, E.run_to_end, E.count, E.first

    local PASS_CASE = [[
return {
    issue = 0,
    timeout = 30,
    run = function(T)
        T.step("read the stub world")
        T.expect(T.local_player() ~= nil, "local player exists")
        T.expect_eq(T.level_key(), "inn_level", "level is the keep")
        T.wait(0.5)
        T.expect_near(1.0, 1.0004, 0.001, "near")
    end,
}
]]
    local FAIL_CASE = [[
return {
    issue = 0,
    run = function(T)
        T.expect(true, "this one holds")
        T.expect(false, "planted expect failure")
        T.expect(true, "the case continues after a failure")
    end,
}
]]

    H.test("rig driver: bootstrap compiles the driver from the plan and the run reaches RUN END", function()
        local plan = make_plan({ { id = "pass", src = PASS_CASE }, { id = "fail", src = FAIL_CASE } })
        local object, env, lines, settings = boot(plan)
        H.truthy(type(object.update) == "function" and type(object.on_game_state_changed) == "function",
            "bootstrap returns the driver object")
        H.truthy(first(lines, tag .. "BOOTSTRAP OK"), "BOOTSTRAP OK printed")
        H.truthy(first(lines, tag .. "RUN BEGIN driver=%S+ plan=\"offline\" cases=2"), "RUN BEGIN printed with two cases")
        H.truthy(run_to_end(object, env), "the driver asked the game to quit")
        H.equal(env.Boot.quit_game, true, "Boot.quit_game set")
        H.equal(count(lines, tag .. "KEEP READY level=inn_level"), 1, "KEEP READY once")
        H.equal(count(lines, tag .. "CASE END id=pass verdict=PASS asserts=3 failed=0"), 1, "one PASS case end")
        H.equal(count(lines, tag .. "CASE END id=fail verdict=FAIL asserts=3 failed=1"), 1, "one FAIL case end")
        H.equal(count(lines, tag .. "CASE END id=%S+ verdict=PASS"), 1, "exactly one PASS")
        H.equal(count(lines, tag .. "CASE END id=%S+ verdict=FAIL"), 1, "exactly one FAIL")
        H.truthy(first(lines, tag .. "CASE END id=fail verdict=FAIL .* detail=\"planted expect failure\""),
            "FAIL names the first failed assertion")
        H.truthy(first(lines, tag .. "ASSERT id=fail n=%d+ FAIL label=\"planted expect failure\""), "failed ASSERT line printed")
        H.equal(count(lines, tag .. "RUN END reason=\"plan complete\" cases=2 pass=1 fail=1 error=0 timeout=0 inconclusive=0"), 1,
            "RUN END with the counts")
        for _, line in ipairs(lines) do
            H.truthy(line:find(tag), "every printed line carries the run tag: " .. line)
        end
        local results = settings.vt2_rig_results
        H.truthy(type(results) == "table" and results.nonce == NONCE and #results.cases == 2, "vt2_rig_results saved with both cases")
        H.equal(results.cases[1].verdict, "PASS")
        H.equal(results.cases[2].verdict, "FAIL")
        H.truthy(type(settings.vt2_rig_progress) == "table" and settings.vt2_rig_progress.phase == "QUIT", "progress checkpoint ends in QUIT")
    end)

    H.test("rig driver: a script that throws ends as ERROR and the run continues", function()
        local plan = make_plan({
            { id = "boom", src = "return { run = function(T) T.step('about to throw') error('planted script error') end }" },
            { id = "after", src = PASS_CASE },
        })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=boom verdict=ERROR .*planted script error"), "ERROR with the message")
        H.equal(count(lines, tag .. "CASE END id=after verdict=PASS"), 1, "next case still runs")
        H.equal(count(lines, tag .. "RUN END .* error=1"), 1, "RUN END counts the error")
    end)

    H.test("rig driver: a script that does not compile ends as ERROR", function()
        local plan = make_plan({ { id = "syntax", src = "return { run = function(T) T.step( end }" } })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=syntax verdict=ERROR .*compile:"), "compile error reported as ERROR")
    end)

    H.test("rig driver: a script that outlives its timeout ends as TIMEOUT", function()
        local plan = make_plan({ { id = "slow", src = "return { timeout = 1, run = function(T) T.wait(30) end }" } })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=slow verdict=TIMEOUT .*exceeded 1 s"), "TIMEOUT reported")
        H.equal(count(lines, tag .. "RUN END .* timeout=1"), 1, "RUN END counts the timeout")
    end)

    H.test("rig driver: a failed precondition ends as INCONCLUSIVE, not FAIL", function()
        local plan = make_plan({
            { id = "pre", src = "return { run = function(T) T.require(false, 'precondition absent') T.expect(false, 'never reached') end }" },
        })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "REQUIRE id=pre FAILED label=\"precondition absent\""), "REQUIRE line printed")
        H.truthy(first(lines, tag .. "CASE END id=pre verdict=INCONCLUSIVE asserts=0 failed=0 .*precondition absent"),
            "INCONCLUSIVE with the label")
        H.equal(count(lines, "never reached"), 0, "nothing after the precondition ran")
        H.equal(count(lines, tag .. "RUN END .* fail=0 .* inconclusive=1"), 1, "RUN END counts it as inconclusive")
    end)

    -- A case file's own cleanup field: once per started case, every verdict, in the main update, error as a NOTE.
    H.test("rig driver: a case's own cleanup runs once after every verdict, outside the coroutine, errors as a NOTE", function()
        local function with_cleanup(id, body, cleanup_body)
            return { id = id, src = "return { timeout = 1, run = function(T) " .. body .. " end, cleanup = function(T) "
                .. "vt2_cleanups[#vt2_cleanups + 1] = { id = '" .. id .. "', in_coroutine = coroutine.running() ~= nil, has_T = T ~= nil and T.case_id == '" .. id .. "' } "
                .. (cleanup_body or "") .. " end }" }
        end
        local plan = make_plan({
            with_cleanup("c-pass", "T.expect(true, 'ok')"),
            with_cleanup("c-fail", "T.expect(false, 'planted failure')"),
            with_cleanup("c-error", "error('planted script error')"),
            with_cleanup("c-inconclusive", "T.require(false, 'planted precondition')"),
            with_cleanup("c-timeout", "T.wait(30)"),
            with_cleanup("c-cleanup-raises", "T.expect(true, 'ok')", "error('planted cleanup error')"),
            { id = "no-cleanup", src = PASS_CASE },
            { id = "c-never-started", arena = "deus", src = "return { run = function(T) end, cleanup = function() vt2_cleanups[#vt2_cleanups + 1] = { id = 'c-never-started' } end }" },
        })
        local object, env, lines = boot(plan)
        env.vt2_cleanups = {}
        H.truthy(run_to_end(object, env), "run completed")
        local ran = {}
        for _, row in ipairs(env.vt2_cleanups) do
            ran[#ran + 1] = row.id
            H.equal(row.in_coroutine, false, row.id .. ": cleanup ran in the main update")
            H.equal(row.has_T, true, row.id .. ": cleanup got the case's T")
        end
        H.equal(table.concat(ran, ","), "c-pass,c-fail,c-error,c-inconclusive,c-timeout,c-cleanup-raises",
            "each started case's cleanup ran once, in case order; the never-started case's did not")
        for id, verdict in pairs({ ["c-pass"] = "PASS", ["c-fail"] = "FAIL", ["c-error"] = "ERROR", ["c-inconclusive"] = "INCONCLUSIVE",
            ["c-timeout"] = "TIMEOUT", ["c-cleanup-raises"] = "PASS" }) do
            H.truthy(first(lines, tag .. "CASE END id=" .. id:gsub("%-", "%%-") .. " verdict=" .. verdict), id .. " keeps verdict " .. verdict)
        end
        H.truthy(first(lines, tag .. "NOTE id=c%-cleanup%-raises key=case_cleanup_error value=\".*planted cleanup error"), "cleanup error recorded as a NOTE")
        H.truthy(first(lines, tag .. "CASE CLEANUP id=c%-cleanup%-raises ok=false"), "CASE CLEANUP ok=false line")
        H.equal(count(lines, tag .. "CASE CLEANUP id=c%-pass ok=true"), 1, "CASE CLEANUP line once")
        H.equal(count(lines, tag .. "CASE CLEANUP id=no%-cleanup"), 0, "no line for a case without cleanup")
    end)

    H.test("rig bootstrap: inert unless the command line nonce matches the plan", function()
        local plan = make_plan({ { id = "pass", src = PASS_CASE } })
        local object, _, lines = boot(plan, { command_line_nonce = "ffffffff" })
        H.equal(next(object), nil, "bootstrap returns an empty object")
        H.equal(#lines, 0, "nothing printed")
        local realm_object, _, realm_lines = boot(plan, { modded_realm = false })
        H.equal(next(realm_object), nil, "bootstrap is inert outside the modded realm")
        H.equal(#realm_lines, 0, "nothing printed outside the modded realm")
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- WP-H-14: backend write shield. Stub classes stand in for PlayFabMirrorBase, PlayFabRequestQueue and the
    -- keep_decorations interface; the shield must override the live INSTANCES only.
    -- Engine shapes: _check_career_data(self, careers_data, career_data_mirror) returns dirty first
    -- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:2885, :3409);
    -- _commit_user_data(self, new_data, commit, commit_id) (:2111, called at :2911); the keep-decoration
    -- comparison is a string compare against _read_only_data_mirror.keep_decorations (:2877-2883).
    -- -----------------------------------------------------------------------------------------------------
    local ACKED_DECORATIONS = '{"keep_painting_1":"painting_a","keep_painting_2":"painting_b"}'

    local function flat_json_decode(text)
        local out = {}
        for key, value in text:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do
            out[key] = value
        end
        return out
    end

    local function new_backend()
        local classes = { mirror = {}, queue = {}, keep = {} }
        for _, class in pairs(classes) do
            class.__index = class
        end
        local originals = {
            check = function()
                return true, {}, { dirty = true }
            end,
            commit_user_data = function(self)
                self.class_user_data_sent = true
            end,
            enqueue = function(self, request)
                self.enqueued[#self.enqueued + 1] = request
                return #self.enqueued
            end,
            keep_json = function()
                return "class encoder ran"
            end,
        }
        classes.mirror._check_career_data = originals.check
        classes.mirror._commit_user_data = originals.commit_user_data
        classes.queue.enqueue = originals.enqueue
        classes.keep.get_keep_decorations_json = originals.keep_json

        local function new_mirror()
            return setmetatable({
                _request_queue = setmetatable({ enqueued = {} }, classes.queue),
                _characters_data_key = "characters_data",
                _career_data = { es_mercenary = { { slot_melee = "id_a", slot_ranged = "id_r", talents = "1,1" } } },
                _career_data_mirror = { es_mercenary = { { slot_melee = "id_a", slot_ranged = "id_r", talents = "1,1" } } },
                _user_data = { tutorial = "done" },
                _user_data_mirror = { tutorial = "done" },
                _read_only_data_mirror = { keep_decorations = ACKED_DECORATIONS },
                _inventory_items = { id_a = {}, id_r = {}, id_b = {} },
            }, classes.mirror)
        end
        local mirror = new_mirror()
        local keep = setmetatable({ _keep_decorations = { keep_painting_1 = "painting_a", keep_painting_2 = "painting_b" } }, classes.keep)
        local backend = {
            _interfaces = { keep_decorations = keep },
            get_backend_mirror = function()
                return mirror
            end,
        }
        return { backend = backend, mirror = mirror, queue = mirror._request_queue, keep = keep,
            classes = classes, originals = originals, new_mirror = new_mirror }
    end

    local function shield_opts(world)
        return { backend = world.backend, cjson = { decode = flat_json_decode } }
    end

    local function shared_entry(name)
        return { id = name, hex = hex(read(repo_root .. "/qa/runtime/_shared/" .. name .. ".lua")) }
    end

    H.test("rig shield: a changed career row is held back and reported", function()
        local world = new_backend()
        local object, env, lines = boot(make_plan({ { id = "pass", src = PASS_CASE } }), shield_opts(world))
        callback(object, "update", 0.1)
        H.equal(count(lines, tag .. "SHIELD installed t=0%.1 "), 1, "shield up on the first tick the mirror exists")
        world.mirror._career_data.es_mercenary[1].slot_melee = "id_b"
        local results = { world.mirror:_check_career_data(world.mirror._career_data, world.mirror._career_data_mirror) }
        H.equal(#results, 1, "one return value")
        H.equal(results[1], false, "_check_career_data answers not dirty")
        H.equal(count(lines, tag .. "SHIELD blocked=characters_data changed_fields=1 case=%-"), 1, "SHIELD blocked=characters_data printed")
        world.mirror._user_data.tutorial = "changed"
        local new_data = { keep_decorations = "left over from the caller" }
        world.mirror:_commit_user_data(new_data, {}, 7)
        H.equal(next(new_data), nil, "user data request table emptied")
        H.equal(world.mirror.class_user_data_sent, nil, "the class sender did not run")
        H.equal(count(lines, tag .. "SHIELD blocked=user_data changed_keys=1"), 1, "SHIELD blocked=user_data printed")
        H.truthy(run_to_end(object, env), "run still completes")
    end)

    H.test("rig shield: a changed painting slot is answered with the acknowledged layout", function()
        local world = new_backend()
        local object, _, lines = boot(make_plan({ { id = "pass", src = PASS_CASE } }), shield_opts(world))
        callback(object, "update", 0.1)
        H.equal(count(lines, tag .. "SHIELD keep_decorations installed"), 1, "keep decorations shield installed")
        H.equal(world.keep:get_keep_decorations_json(), ACKED_DECORATIONS, "unchanged layout: acknowledged string")
        H.equal(count(lines, "SHIELD blocked=keep_decorations"), 0, "nothing reported while unchanged")
        world.keep._keep_decorations.keep_painting_2 = "painting_c"
        H.equal(world.keep:get_keep_decorations_json(), ACKED_DECORATIONS, "changed layout: still the acknowledged string")
        H.equal(count(lines, tag .. "SHIELD blocked=keep_decorations changed_slots=1 case=%-"), 1,
            "SHIELD blocked=keep_decorations changed_slots=1 printed")
    end)

    H.test("rig shield: overrides live on the instances, the class tables are untouched", function()
        local world = new_backend()
        local object, env = boot(make_plan({ { id = "pass", src = PASS_CASE } }), shield_opts(world))
        H.truthy(run_to_end(object, env), "run completed")
        local c, o = world.classes, world.originals
        H.equal(c.mirror._check_career_data, o.check, "mirror class _check_career_data untouched")
        H.equal(c.mirror._commit_user_data, o.commit_user_data, "mirror class _commit_user_data untouched")
        H.equal(c.queue.enqueue, o.enqueue, "request queue class enqueue untouched")
        H.equal(c.keep.get_keep_decorations_json, o.keep_json, "keep decorations class encoder untouched")
        H.truthy(rawget(world.mirror, "_check_career_data") ~= nil, "instance override on the mirror")
        H.truthy(rawget(world.mirror, "_commit_user_data") ~= nil, "instance override for user data")
        H.truthy(rawget(world.queue, "enqueue") ~= nil, "instance wrapper on the request queue")
        H.truthy(rawget(world.keep, "get_keep_decorations_json") ~= nil, "instance override on keep decorations")
        local other = world.new_mirror()
        H.equal(other:_check_career_data(), true, "another instance of the class still runs the class method")
    end)

    H.test("rig shield: backend_shield = false replaces nothing", function()
        local world = new_backend()
        local plan = make_plan({ { id = "pass", src = PASS_CASE } }, { backend_shield = false, shared = { shared_entry("official_mirror") } })
        local object, env, lines = boot(plan, shield_opts(world))
        H.truthy(run_to_end(object, env), "run completed")
        H.equal(rawget(world.mirror, "_check_career_data"), nil, "no mirror override")
        H.equal(rawget(world.mirror, "_commit_user_data"), nil, "no user data override")
        H.equal(rawget(world.queue, "enqueue"), nil, "no request queue wrapper")
        H.equal(rawget(world.keep, "get_keep_decorations_json"), nil, "no keep decorations override")
        H.equal(count(lines, tag .. "SHIELD "), 0, "no SHIELD line at all")
    end)

    H.test("rig shield: requests are observed and passed through; others are named after KEEP READY", function()
        local world = new_backend()
        local object, env, lines = boot(make_plan({ { id = "pass", src = PASS_CASE } }), shield_opts(world))
        callback(object, "on_game_state_changed", "enter", "StateTitleScreen")
        callback(object, "update", 0.1)
        local hero_request = { FunctionName = "updateHeroAttributes",
            FunctionParameter = { hero_attributes = { keep_decorations = "v1", characters_data = "secret value" } } }
        H.equal(world.queue:enqueue(hero_request, nil, false), 1, "request passed through to the queue")
        world.queue:enqueue({ FunctionName = "earlyCloudScript" }, nil, true)
        H.equal(count(lines, tag .. "SHIELD saw request=updateHeroAttributes keys=\"characters_data,keep_decorations\""), 1,
            "key names of updateHeroAttributes printed")
        H.equal(count(lines, "secret value"), 0, "values never printed")
        H.equal(count(lines, "earlyCloudScript"), 0, "other requests before KEEP READY are not named")
        callback(object, "on_game_state_changed", "enter", "StateIngame")
        callback(object, "update", 0.1)
        H.equal(count(lines, tag .. "KEEP READY"), 1, "keep ready")
        world.queue:enqueue({ FunctionName = "lateCloudScript" }, nil, true)
        H.equal(count(lines, tag .. "SHIELD saw request=lateCloudScript case=%-"), 1, "other requests after KEEP READY are named")
        H.equal(#world.queue.enqueued, 3, "every request reached the queue")
        H.truthy(run_to_end(object, env), "run completed")
    end)

    H.test("rig shield: the driver restores the official rows from the KEEP READY snapshot before quitting", function()
        local world = new_backend()
        local LEAVE_CHANGED = [[
return {
    run = function(T)
        local OM = T.shared("official_mirror")
        T.expect(type(OM.snapshot) == "function" and type(OM.restore) == "function", "OM helper delivered")
        local shield = T.shield()
        T.expect(shield.installed, "T.shield reports the shield installed")
        T.expect_eq(shield.blocked_characters_data, 0, "nothing blocked yet")
        local mirror = Managers.backend:get_backend_mirror()
        mirror._career_data.es_mercenary[1].slot_melee = "id_b"
        T.wait(0.3)
    end,
}
]]
        local plan = make_plan({ { id = "leave", src = LEAVE_CHANGED } }, { shared = { shared_entry("official_mirror") } })
        local object, env, lines = boot(plan, shield_opts(world))
        H.truthy(run_to_end(object, env), "run completed")
        H.equal(count(lines, tag .. "SHARED id=official_mirror ok=true"), 1, "shared helper loaded")
        H.equal(count(lines, tag .. "SHIELD snapshot careers=1"), 1, "snapshot at KEEP READY")
        H.equal(count(lines, tag .. "CASE END id=leave verdict=PASS"), 1, "case passed")
        H.equal(count(lines, tag .. "SHIELD restore changed_fields=1 extra_fields=0 ok=true"), 1, "restore reports one changed field")
        H.equal(world.mirror._career_data.es_mercenary[1].slot_melee, "id_a", "row restored to the snapshot")
        local restore_at, end_at
        for i, line in ipairs(lines) do
            if line:find(tag .. "SHIELD restore") then restore_at = i end
            if line:find(tag .. "RUN END") then end_at = i end
        end
        H.truthy(restore_at and end_at and restore_at < end_at, "restore runs before RUN END and the quit")
    end)

    H.test("rig driver: T.shared names a missing helper as INCONCLUSIVE", function()
        local plan = make_plan({ { id = "need", src = "return { run = function(T) local OM = T.shared('official_mirror') T.expect(OM ~= nil, 'x') end }" } })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=need verdict=INCONCLUSIVE .*shared helper official_mirror"), "INCONCLUSIVE names the helper")
    end)

    -- WP-H-02: the real smoke case asserts every VMF mod id of the plan's expect_mods, read from the plan block in
    -- user settings (the table the bootstrap handed the driver).
    local function run_smoke(expect_mods, expect_versions)
        local plan = make_plan({ { id = "smoke-keep", src = read(repo_root .. "/qa/runtime/_rig/smoke_keep.lua") } },
            { expect_mods = expect_mods, expect_versions = expect_versions })
        local object, env, lines = boot(plan)
        local hero = env.Managers.player:local_player().player_unit
        env.Managers.player.local_player = function()
            return {
                player_unit = hero,
                profile_index = function() return 5 end,
                career_index = function() return 1 end,
            }
        end
        env.ScriptUnit = {
            has_extension = function(unit, system)
                if unit == hero and system == "health_system" then
                    return { current_health = function() return 150 end }
                end
            end,
        }
        local mods = {
            VMF = { get_commands_list = function() return {} end },
            gt_dev = { MOD_VERSION = "0.2.300-dev" },
        }
        env.get_mod = function(name)
            return mods[name]
        end
        H.truthy(run_to_end(object, env), "smoke run completed")
        return lines
    end

    H.test("rig smoke case: every expect_mods id loaded is a PASS with versions noted", function()
        local lines = run_smoke({ "VMF", "gt_dev" })
        H.equal(count(lines, tag .. "CASE END id=smoke%-keep verdict=PASS"), 1, "smoke case passes")
        H.equal(count(lines, tag .. "ASSERT id=smoke%-keep n=%d+ PASS label=\"mod gt_dev is loaded\""), 1, "gt_dev asserted")
        H.equal(count(lines, tag .. "NOTE id=smoke%-keep key=version:gt_dev value=\"0.2.300%-dev\""), 1, "gt_dev version noted")
        H.equal(count(lines, tag .. "NOTE id=smoke%-keep key=expect_mods value=\"2\""), 1, "two expected mods")
    end)

    H.test("rig smoke case: an expect_mods id that is not loaded is a FAIL naming it", function()
        local lines = run_smoke({ "VMF", "missing_mod" })
        H.truthy(first(lines, tag .. "CASE END id=smoke%-keep verdict=FAIL .*detail=\"mod missing_mod is loaded\""), "FAIL names the missing mod")
    end)

    -- WP-H-07: a staged local build must be the version that runs
    H.test("rig smoke case: the staged version of a local build is asserted", function()
        local same = run_smoke({ "VMF" }, { gt_dev = "0.2.300-dev" })
        H.equal(count(same, tag .. "ASSERT id=smoke%-keep n=%d+ PASS label=\"mod gt_dev runs the staged version\""), 1, "matching MOD_VERSION passes")
        H.equal(count(same, tag .. "CASE END id=smoke%-keep verdict=PASS"), 1, "smoke case passes")
        local other = run_smoke({ "VMF" }, { gt_dev = "9.9.9-marker" })
        H.truthy(first(other, tag .. "CASE END id=smoke%-keep verdict=FAIL .*detail=\"mod gt_dev runs the staged version\""), "a different version FAILs")
        local banner = run_smoke({ "VMF" }, { VMF = "2.0.0" })
        H.equal(count(banner, tag .. "NOTE id=smoke%-keep key=staged:VMF value=\"2%.0%.0 %(checked against the load banner by run%.ps1%)\""), 1,
            "a mod without MOD_VERSION is left to the host banner check")
    end)

    -- OM.minted judges each slot the way vanilla's broken-slot rule does
    -- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:1600-1631):
    -- cosmetic slots (cosmetic_utils.lua:77-81,104) hold keys in _unlocked_cosmetics, slot_pose a key unlocked under
    -- ItemMasterList[key].parent in _unlocked_weapon_poses, every other slot a backend id in _inventory_items.
    local function load_om(mirror_state, forged)
        local env = setmetatable({}, { __index = _G })
        env.Managers = { backend = { get_backend_mirror = function() return mirror_state end } }
        env.ItemMasterList = { pose_ok = { parent = "es_1h_sword" }, pose_locked = { parent = "es_1h_sword" } }
        env.get_mod = function(mod_id)
            if mod_id == "cim" then
                return { get = function(_, key) return key == "forged_weapons" and forged or nil end }
            end
        end
        local chunk = assert(loadfile(repo_root .. "/qa/runtime/_shared/official_mirror.lua"))
        setfenv(chunk, env)
        return chunk()
    end

    local function om_world()
        local row = { slot_hat = "hat_ok", slot_frame = "frame_ok", slot_skin = "skin_ok", slot_pose = "pose_ok",
            slot_melee = "id_ok", talents = "1,1,1" }
        local acked = {}
        for key, value in pairs(row) do
            acked[key] = value
        end
        return {
            _career_data = { es_mercenary = { row } },
            _career_data_mirror = { es_mercenary = { acked } },
            _unlocked_cosmetics = { hat_ok = true, frame_ok = true, skin_ok = true, cwv_es_hat_001 = true },
            _unlocked_weapon_poses = { es_1h_sword = { pose_ok = true } },
            _inventory_items = { id_ok = { CustomData = {} }, id_cim = { CustomData = { cim_provider = "forge" } }, id_forged = {} },
        }
    end

    local function set_slot(world, slot, value)
        world._career_data.es_mercenary[1][slot] = value
        world._career_data_mirror.es_mercenary[1][slot] = value
    end

    H.test("rig OM: cosmetic, pose and inventory slots are judged the way the game does", function()
        local world = om_world()
        local OM = load_om(world, { id_forged = {} })
        H.equal(OM.baseline_clean(), true, "owned cosmetic keys, an unlocked pose and an inventory id are clean")
        for slot, value in pairs({ slot_hat = "hat_ok", slot_frame = "frame_ok", slot_skin = "skin_ok", slot_pose = "pose_ok", slot_melee = "id_ok" }) do
            H.equal(OM.minted(value, slot), false, slot .. " " .. value .. " is owned")
        end
        H.equal(OM.minted("id_ok"), false, "no slot means a backend id")

        local bad = {
            { slot = "slot_hat", value = "hat_locked", why = "not in _unlocked_cosmetics" },
            { slot = "slot_frame", value = "frame_locked", why = "not in _unlocked_cosmetics" },
            { slot = "slot_skin", value = "skin_locked", why = "not in _unlocked_cosmetics" },
            { slot = "slot_pose", value = "pose_locked", why = "pose not unlocked" },
            { slot = "slot_pose", value = "pose_unknown", why = "unknown item key" },
            { slot = "slot_melee", value = "id_missing", why = "not in _inventory_items" },
            { slot = "slot_hat", value = "cwv_es_hat_001", why = "cwv id" },
            { slot = "slot_melee", value = "id_cim", why = "cim row" },
            { slot = "slot_melee", value = "id_forged", why = "cim forged_weapons" },
        }
        for _, case in ipairs(bad) do
            local w = om_world()
            set_slot(w, case.slot, case.value)
            local om = load_om(w, { id_forged = {} })
            local minted, why = om.minted(case.value, case.slot)
            H.equal(minted, true, case.slot .. " " .. case.value .. " is minted")
            H.equal(why, case.why, case.slot .. " " .. case.value .. " reason")
            H.equal(om.baseline_clean(), false, case.slot .. " " .. case.value .. " makes the baseline dirty")
        end
        H.equal(OM.minted("hat_ok"), true, "a cosmetic key judged as a backend id is not in _inventory_items")
    end)

    H.test("rig OM: assert_clean passes the slot to OM.minted", function()
        local world = om_world()
        local OM = load_om(world, {})
        local failed = {}
        local T = {
            expect = function(cond, label)
                if not cond then
                    failed[#failed + 1] = label
                end
            end,
        }
        OM.assert_clean(T, "clean")
        H.equal(#failed, 0, "no INV-A or INV-B failure on owned keys: " .. table.concat(failed, " | "))
        set_slot(world, "slot_skin", "skin_locked")
        OM.assert_clean(T, "dirty")
        H.equal(#failed, 1, "one failure for the locked skin")
        H.truthy(failed[1] and failed[1]:find("INV%-A dirty es_mercenary%[1%]%.slot_skin .*not in _unlocked_cosmetics"), "INV-A names the slot and reason: " .. tostring(failed[1]))
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- WP-H-04: arena sequencing with a stub mechanism whose level changes a number of updates after
    -- debug_load_level (game_mechanism_manager.lua:880-892), and the actor helpers with a stub conflict director.
    -- -----------------------------------------------------------------------------------------------------
    local KEEP_CASE = [[
return { arena = "keep", run = function(T) T.expect_eq(T.level_key(), "inn_level", "in the keep") end }
]]

    local function mission_world(env)
        local world = { level = "inn_level", loads = {}, pending = nil, alive = {}, spawned = {}, queued = {} }
        local hero = env.Managers.player:local_player().player_unit
        local bot = { name = "stub bot unit" }
        world.hero = hero
        world.alive[hero] = true
        world.alive[bot] = true
        world.health = { is_invincible = false }
        -- engine stubs that take a unit record a call made inside a coroutine (the real engine fails there)
        world.in_coroutine = {}
        local function main_only(name)
            if coroutine.running() then
                world.in_coroutine[#world.in_coroutine + 1] = name
            end
        end
        env.HEALTH_ALIVE = {}
        env.Unit = {
            alive = function(unit) return unit ~= nil and world.alive[unit] == true end,
            local_position = function() main_only("Unit.local_position"); return env.Vector3(0, 0, 0) end,
        }
        local vector_mt = {}
        vector_mt.__add = function(a, b) return setmetatable({ a[1] + b[1], a[2] + b[2], a[3] + b[3] }, vector_mt) end
        env.Vector3 = function(x, y, z) return setmetatable({ x, y, z }, vector_mt) end
        env.Vector3Box = function(v) return { v } end
        env.QuaternionBox = function(q) return { q } end
        env.Quaternion = { identity = function() return {} end }
        env.Breeds = { skaven_slave = { name = "skaven_slave" } }
        env.AiUtils = {
            kill_unit = function(unit)
                main_only("AiUtils.kill_unit")
                env.HEALTH_ALIVE[unit] = nil
                world.alive[unit] = nil
            end,
        }
        env.ScriptUnit = {
            has_extension = function(unit, system)
                main_only("ScriptUnit.has_extension")
                if unit == hero and system == "health_system" then return world.health end
                if unit == hero and system == "buff_system" then
                    return { has_buff_type = function() main_only("buff:has_buff_type"); return false end }
                end
            end,
        }
        env.Managers.player.bots = function() return { { player_unit = bot } } end
        env.Managers.mechanism = {
            debug_load_level = function(_, level, variation)
                world.loads[#world.loads + 1] = level .. ":" .. tostring(variation)
                world.pending = { level = level, left = 20 }
            end,
        }
        env.Managers.state.game_mode = { level_key = function() return world.level end }
        env.Managers.state.conflict = {
            spawned_units_by_breed = function(_, name) return world.spawned[name] end,
            spawn_queued_unit = function(_, breed, position_box, rotation_box)
                main_only("spawn_queued_unit")
                world.queued[#world.queued + 1] = { breed = breed, position = position_box[1] }
            end,
        }
        -- one update of the stub game: queued enemies appear, a pending level change progresses
        function world.tick(object)
            for _, q in ipairs(world.queued) do
                local unit = { breed = q.breed.name }
                world.spawned[q.breed.name] = world.spawned[q.breed.name] or {}
                world.spawned[q.breed.name][#world.spawned[q.breed.name] + 1] = unit
                world.alive[unit] = true
                env.HEALTH_ALIVE[unit] = true
            end
            world.queued = {}
            local p = world.pending
            if p then
                p.left = p.left - 1
                if p.left == 15 then callback(object, "on_game_state_changed", "enter", "StateLoading") end
                if p.left == 0 then
                    world.level = p.level
                    world.pending = nil
                    callback(object, "on_game_state_changed", "enter", "StateIngame")
                end
            end
        end
        return world
    end

    local function run_mission(plan)
        local object, env, lines = boot(plan)
        local world = mission_world(env)
        callback(object, "on_game_state_changed", "enter", "StateIngame")
        for _ = 1, 30000 do
            world.tick(object)
            callback(object, "update", 0.1)
            if env.Boot.quit_game then break end
        end
        H.truthy(env.Boot.quit_game, "the driver asked the game to quit")
        return lines, world, env
    end

    local function index_of(lines, pattern, from)
        for i = from or 1, #lines do
            if lines[i]:find(pattern) then return i end
        end
    end

    H.test("rig arenas: keep, mission:military, back to the keep, then quit", function()
        local plan = make_plan({
            { id = "keep-case", arena = "keep", src = KEEP_CASE },
            { id = "mission-military", arena = "mission:military", src = read(repo_root .. "/qa/runtime/_rig/mission_military.lua") },
        }, { arenas = { "keep", "mission:military", "keep" } })
        local lines, world = run_mission(plan)
        H.deep_equal(world.loads, { "military:0", "inn_level:0" }, "debug_load_level to the mission, then to the keep")
        local order = {
            "KEEP READY level=inn_level",
            "CASE END id=keep%-case verdict=PASS",
            "LOAD arena=mission:military level=military from=inn_level",
            "LEVEL READY level=military t=[%d%.]+ load_seconds=[%d%.]+",
            "CASE END id=mission%-military verdict=PASS",
            "LOAD arena=keep level=inn_level from=military",
            "LEVEL READY level=inn_level",
            "RUN END reason=\"plan complete\" cases=2 pass=2",
        }
        local at = 1
        for _, pattern in ipairs(order) do
            local found = index_of(lines, tag .. pattern, at)
            H.truthy(found, "in order: " .. pattern)
            at = (found or at) + 1
        end
        H.truthy(first(lines, tag .. "CLEANUP id=mission%-military actions=2 errors=0"), "the mission case's helper changes were cleaned up")
        H.equal(world.health.is_invincible, false, "invincibility restored after the case")
        H.equal(table.concat(world.in_coroutine, ","), "", "spawn, kill, invincible and the buff read ran in the main update, not in the case coroutine")
    end)

    H.test("rig helpers: cleanup kills a spawned enemy and restores invincibility after an ERROR", function()
        local plan = make_plan({
            { id = "boom", arena = "keep", src = [[
return { run = function(T)
    T.invincible(true)
    local u = T.spawn("skaven_slave", { 1, 0, 0 })
    T.expect(u ~= nil, "spawned")
    T.note("spawned", tostring(u ~= nil))
    error("planted error after spawning")
end }
]] },
        })
        local lines, world, env = run_mission(plan)
        H.truthy(first(lines, tag .. "CASE END id=boom verdict=ERROR .*planted error after spawning"), "ERROR reported")
        H.truthy(first(lines, tag .. "CLEANUP id=boom actions=2 errors=0"), "two cleanups ran")
        local unit = world.spawned.skaven_slave and world.spawned.skaven_slave[1]
        H.truthy(unit ~= nil, "the enemy was spawned")
        H.equal(env.HEALTH_ALIVE[unit], nil, "the enemy left alive by the case was killed at cleanup")
        H.equal(world.health.is_invincible, false, "invincibility restored")
        H.equal(table.concat(world.in_coroutine, ","), "", "no unit-taking engine call ran inside the case coroutine")
    end)

    H.test("rig arenas: an arena the driver cannot load ends its cases as INCONCLUSIVE", function()
        local plan = make_plan({ { id = "deus-case", arena = "deus", src = "return { run = function(T) T.expect(true, 'x') end }" } })
        local lines = run_mission(plan)
        H.truthy(first(lines, tag .. "CASE END id=deus%-case verdict=INCONCLUSIVE .*arena not supported by this driver: deus"), "INCONCLUSIVE names the arena")
        H.truthy(first(lines, tag .. "RUN END"), "run still ends")
    end)

    H.test("rig T.main: runs the function outside the case coroutine and hands back its results and errors", function()
        local plan = make_plan({
            { id = "main-ok", src = [[
return { run = function(T)
    T.expect(coroutine.running() ~= nil, "the case itself runs in a coroutine")
    local outside, a, b, c = T.main(function(x, y) return coroutine.running() == nil, x, nil, y end, 1, 3)
    T.expect(outside, "T.main ran the function in the main update")
    T.expect_eq(a, 1, "first result")
    T.expect_eq(b, nil, "a nil result keeps its place")
    T.expect_eq(c, 3, "third result")
end }
]] },
            { id = "main-err", src = "return { run = function(T) T.main(function() error('planted main error') end) end }" },
            { id = "main-require", src = "return { run = function(T) T.main(function() T.require(false, 'precondition inside main') end) end }" },
        })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.equal(count(lines, tag .. "CASE END id=main%-ok verdict=PASS asserts=5 failed=0"), 1, "results returned in order")
        H.truthy(first(lines, tag .. "CASE END id=main%-err verdict=ERROR .*planted main error"), "an error in main is the case's ERROR")
        H.truthy(first(lines, tag .. "CASE END id=main%-require verdict=INCONCLUSIVE .*precondition inside main"), "a failed T.require in main stays INCONCLUSIVE")
    end)

    -- -----------------------------------------------------------------------------------------------------
    -- WP-H-03: T.cmd runs a regression suite in the main update; the rows it echoes feed T.expect_rt.
    -- The stub suite echoes rows the way every runner does ("  <VERDICT>: <check>[ -- <detail>]").
    -- -----------------------------------------------------------------------------------------------------
    local function boot_with_suite()
        local calls = {}
        local plan = make_plan({
            { id = "rt-asserts", src = [[
return { run = function(T)
    local lines = T.cmd("gt_regression_test")
    T.note("lines", #lines)
    T.expect_rt("gt_dev", "gt_a")
    T.expect_rt("gt_dev", "gt_b")
    T.expect_rt("gt_dev", "gt_x")
end }
]] },
            { id = "rt-skip", src = "return { run = function(T) T.expect_rt('gt_dev', 'gt_s') end }" },
            { id = "rt-missing-suite", src = "return { run = function(T) T.expect_rt('ct_dev', 'ct_a') end }" },
            { id = "rt-missing-check", src = "return { run = function(T) T.expect_rt('gt_dev', 'nope') end }" },
        })
        local object, env, lines = boot(plan)
        local VMFMod = {}
        for _, method in ipairs({ "echo", "info", "warning", "error", "debug" }) do
            VMFMod[method] = function() end
        end
        env.VMFMod = VMFMod
        local gt = setmetatable({ get_name = function() return "gt_dev" end }, { __index = VMFMod })
        local vmf = {
            run_command = function(name)
                calls[#calls + 1] = { name = name, in_coroutine = coroutine.running() ~= nil }
                gt:echo("=== gt regression_test (v%s) ===", "0.2.300-dev")
                gt:echo("  PASS: %s", "gt_a")
                gt:info("[regression] PASS %s", "gt_a")
                gt:echo("  FAIL: %s -- %s", "gt_b", "expected 1, got 2")
                gt:echo("  XPASS: %s -- %s", "gt_x", "open issue 9 no longer reproduces")
                gt:echo("  SKIP: %s -- %s", "gt_s", "no mission")
                gt:echo("=== %d passed, %d failed, %d skipped ===", 1, 2, 1)
            end,
            get_commands_list = function() return { { name = "gt_regression_test" } } end,
        }
        env.get_mod = function(name) return name == "VMF" and vmf or nil end
        return object, env, lines, calls
    end

    H.test("rig T.cmd / T.expect_rt: the suite runs in the main update and its rows decide the asserts", function()
        local object, env, lines, calls = boot_with_suite()
        H.truthy(run_to_end(object, env), "run completed")
        H.equal(#calls, 1, "the suite ran once")
        H.equal(calls[1].in_coroutine, false, "VMF.run_command ran in the main update, not in the case coroutine")
        H.truthy(first(lines, tag .. "OUT mod=gt_dev via=echo text=\"  FAIL: gt_b %-%- expected 1, got 2\""), "rows are printed as OUT lines for Parse-Sweep")
        H.truthy(first(lines, tag .. "ASSERT id=rt%-asserts n=%d+ PASS label=\"rt gt_dev gt_a\" got=\"PASS\""), "PASS row passes")
        H.truthy(first(lines, tag .. "ASSERT id=rt%-asserts n=%d+ FAIL label=\"rt gt_dev gt_b\" got=\"FAIL\" detail=\"expected 1, got 2\""), "FAIL row fails with its detail")
        H.truthy(first(lines, tag .. "ASSERT id=rt%-asserts n=%d+ PASS label=\"rt gt_dev gt_x\" got=\"XPASS\""), "XPASS counts as passed")
        H.truthy(first(lines, tag .. "CASE END id=rt%-asserts verdict=FAIL asserts=3 failed=1"), "the case FAILs on the FAIL row")
        H.truthy(first(lines, tag .. "CASE END id=rt%-skip verdict=INCONCLUSIVE .*not skipped %(no mission%)"), "a SKIP row is INCONCLUSIVE")
        H.truthy(first(lines, tag .. "CASE END id=rt%-missing%-suite verdict=INCONCLUSIVE .*regression suite of ct_dev ran earlier in this boot"), "a suite not run in this boot is INCONCLUSIVE")
        H.truthy(first(lines, tag .. "CASE END id=rt%-missing%-check verdict=INCONCLUSIVE .*check nope reported by gt_dev"), "an unknown check is INCONCLUSIVE")
    end)
end
