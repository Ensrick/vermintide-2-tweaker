-- WP-WT-02: the in-mod regression suite must be runnable by a function call
-- that returns rows and prints one engine printf line per check, while
-- /wt_regression_test keeps its exact chat output. Loads the production
-- _wt_regression.lua of both trees in a sandbox.

return function(H, repo_root)
    local trees = {
        { mod_name = "wt", path = repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_regression.lua" },
        { mod_name = "wt_dev", path = repo_root
            .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_regression.lua" },
    }

    local function load_tree(tree)
        local chat, printed, commands = {}, {}, {}
        local mod = { _wt = { MOD_VERSION = "0.0.0-test" } }
        function mod.get_name() return "wt" end
        function mod.command(_, name, _, fn) commands[name] = fn end
        local function chat_line(_, fmt, ...) chat[#chat + 1] = string.format(fmt, ...) end
        mod.echo, mod.info, mod.warning = chat_line, chat_line, chat_line
        local env = setmetatable({
            get_mod = function(name)
                if name == "wt" or name == "wt_dev" then return mod end
                return nil
            end,
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
        }, { __index = _G })
        local chunk = assert(loadfile(tree.path))
        setfenv(chunk, env)
        chunk()
        return mod, chat, printed, commands
    end

    local function register_fixture_checks(mod)
        mod._wt.rt_register("a_pass", function() return nil end)
        mod._wt.rt_register("b_fail", function() return "boom" end)
        mod._wt.rt_register("c_skip", function() return "skip: no engine" end)
        mod._wt.rt_register("d_raise", function() error("kaput") end)
    end

    for _, tree in ipairs(trees) do
        H.test(tree.mod_name .. " run_regression returns rows and prints one RT line per check", function()
            local mod, _, printed = load_tree(tree)
            register_fixture_checks(mod)
            H.equal(type(mod._wt.run_regression), "function", "run_regression is not exported")
            local rows, pass, fail, skip = mod._wt.run_regression()
            -- WP-WT-08 registers wt_no_swallowed_errors when the module loads,
            -- so it is row 1; with no counters in this stub it PASSes.
            H.equal(#rows, 5)
            local want = {
                { "wt_no_swallowed_errors", "PASS" },
                { "a_pass", "PASS" }, { "b_fail", "FAIL" },
                { "c_skip", "SKIP" }, { "d_raise", "FAIL" },
            }
            for i, row in ipairs(rows) do
                H.equal(row.name, want[i][1], "row " .. i .. " name")
                H.equal(row.result, want[i][2], "row " .. i .. " result")
            end
            H.equal(rows[1].detail, nil)
            H.equal(rows[2].detail, nil)
            H.equal(rows[3].detail, "boom")
            H.equal(rows[4].detail, "skip: no engine")
            H.truthy(type(rows[5].detail) == "string" and rows[5].detail:find("kaput", 1, true),
                "raise detail lost the error text")
            H.equal(pass, 2); H.equal(fail, 2); H.equal(skip, 1)

            H.equal(#printed, 6)
            H.equal(printed[1], "[wt:RT] check=wt_no_swallowed_errors result=PASS")
            H.equal(printed[2], "[wt:RT] check=a_pass result=PASS")
            H.equal(printed[3], "[wt:RT] check=b_fail result=FAIL detail=boom")
            H.equal(printed[4], "[wt:RT] check=c_skip result=SKIP detail=skip: no engine")
            local prefix = "[wt:RT] check=d_raise result=FAIL detail="
            H.equal(printed[5]:sub(1, #prefix), prefix)
            H.equal(printed[6], "[wt:RT] summary pass=2 fail=2 skip=1 total=5 version=0.0.0-test")
        end)

        H.test(tree.mod_name .. " /wt_regression_test keeps its exact chat output", function()
            local mod, chat, _, commands = load_tree(tree)
            register_fixture_checks(mod)
            local command = commands.wt_regression_test
            H.equal(type(command), "function", "/wt_regression_test is not registered")
            for i = #chat, 1, -1 do chat[i] = nil end
            command()
            local want = {
                "=== wt regression_test (v0.0.0-test) ===",
                "  PASS: wt_no_swallowed_errors",
                "  PASS: a_pass",
                "  FAIL: b_fail -- boom",
                "  SKIP: c_skip -- skip: no engine",
                "=== 2 passed, 2 failed, 1 skipped ===",
            }
            local at = 1
            for _, line in ipairs(chat) do
                if line == want[at] then at = at + 1 end
                if at > #want then break end
            end
            H.equal(at, #want + 1, "missing chat line in order: " .. tostring(want[at]))
        end)
    end
end
