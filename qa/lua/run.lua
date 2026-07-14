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
    "test_mod_tweaker_tab_labels",
    "test_mod_tweaker_disabled_sections",
    "test_gut_video_profiles",
    "test_gut_cutscene_probe",
    "test_et_settings_queue",
    "test_mod_tweaker_search",
    "test_mod_tweaker_numeric_editor",
    "test_mp_dailies",
    "test_mp_quest_boundary",
    "test_mp_shilling_ui_policy",
    "test_wt_passive_charge",
    "test_wt_longbow_zoom_probe",
    "test_wt_cwv_ownership",
    "test_wt_native_ownership",
    "test_cwv_remote_audio",
    "test_cwv_remote_identity",
    "test_cwv_old_musket_presentation",
    "test_cwv_acquisition",
    "test_cwv_javelin_pickup",
    "test_cwv_exact_pair_state",
    "test_cim_skin_persistence",
    "test_cim_bulk_cleanup",
    "test_cim_tab_preview",
    "test_cos_score_identity",
    "test_gut_native_loadout_policy",
    "test_gt_dummy_collision_policy",
    "test_gut_simple_ui_bounds",
    "test_gt_chest_pickup_probe",
    "test_cos_glow_lifecycle",
    "test_peer_parity_transition",
    "test_ct_boon_catalog",
    "test_ct_parry_cooldown_contract",
    "test_cos_offhand_preload_lifecycle",
    "test_cos_dual_offhands",
    "test_cos_la_shield_parity",
    "test_gt_disconnect_grace",
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
