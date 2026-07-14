local script_path = arg[0]:gsub("\\", "/")
local lua_root = script_path:match("^(.*)/run%.lua$") or "."
local repo_root = lua_root:match("^(.*)/qa/lua$") or "."

package.path = table.concat({
    lua_root .. "/?.lua",
    lua_root .. "/tests/?.lua",
    package.path,
}, ";")

local Harness = require("harness")

local function run_harness_self_test()
    Harness.test("self-test pass sentinel", function()
        Harness.equal("Lua 5.1", _VERSION)
    end)
    local passed, total, failed = Harness.run({ quiet = true })
    if not passed or total ~= 1 or failed ~= 0 then
        error("harness positive-path self-test failed")
    end

    Harness.test("self-test planted failure", function()
        Harness.equal("actual", "expected", "planted failure")
    end)
    local original_stderr = io.stderr
    io.stderr = { write = function() end }
    local negative_passed, negative_total, negative_failed = Harness.run({ quiet = true })
    io.stderr = original_stderr
    if negative_passed or negative_total ~= 1 or negative_failed ~= 1 then
        error("harness did not detect a planted failure")
    end

    io.write("[lua_unit_tests] SELF-TEST OK -- pass and planted-failure paths verified.\n")
end

if arg[1] == "--self-test" then
    run_harness_self_test()
    os.exit(0)
end

local suites = {
    "test_attack_labeler",
    "test_mod_tweaker_transaction",
    "test_mod_tweaker_profiles",
    "test_et_settings_queue",
    "test_mod_tweaker_search",
    "test_mod_tweaker_numeric_editor",
    "test_mp_dailies",
    "test_wt_passive_charge",
    "test_cwv_remote_audio",
    "test_cwv_acquisition",
    "test_cim_skin_persistence",
    "test_cos_score_identity",
    "test_gut_native_loadout_policy",
}

for _, suite in ipairs(suites) do
    local register = require(suite)
    if type(register) ~= "function" then
        error(suite .. " must return a registration function")
    end
    register(Harness, repo_root)
end

local passed, total, failed = Harness.run()
if passed then
    io.write(string.format("[lua_unit_tests] OK -- %d tests passed under %s.\n", total, _VERSION))
    os.exit(0)
end

io.stderr:write(string.format("[lua_unit_tests] FAILED -- %d/%d tests failed.\n", failed, total))
os.exit(2)
