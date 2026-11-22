-- qa/integration/run.lua (WP-T-03): the engine-free integration tier. Loads the real vanilla data tables from the
-- decompile in plain Lua 5.1 and runs every suite in qa/integration/suites/ against them.
--
-- Usage (qa/check_integration.ps1 runs it): lua5.1 run.lua <decompile root> <repo root> <mod map .lua> [selftest]
--   <mod map .lua> returns { dirs = { [VMF mod id] = "<mod folder>" }, files = { cwv_modules = { "<file>", ... } } },
--   written by qa/check_integration.ps1 from tools/mod-inventory.psd1 and the mod folders.
-- A suite is a Lua file returning function(ctx) -> { name, checked, problems = { text... }, notes = { text... } }.
-- ctx: repo, files (lists from the mod map), get_mod (qa/integration/fake_vmf.lua), plant (true in selftest), real(value, label) which returns the
-- value and records a problem when it came from an inert engine stub, count(t).
-- Exit codes: 0 every suite clean; 2 a suite reported a problem (or, in selftest, a planted defect went unseen);
-- 3 a vanilla file failed to load (card stop condition: the failing file and line are printed).
-- Reads the decompile and the repository only. Never copies vanilla source anywhere.
local decompile, repo, modmap_path, mode = arg[1], arg[2], arg[3], arg[4]
local here = (debug.getinfo(1, "S").source:sub(2)):gsub("[/\\][^/\\]*$", "")
local selftest = mode == "selftest"
local started = os.clock()

local L = assert(loadfile(here .. "/loader.lua"))()(decompile)
assert(loadfile(here .. "/stubs.lua"))()(L, here)

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local load_failures = {}
for _, f in ipairs(L.preamble_failures) do load_failures[#load_failures + 1] = f end
for _, name in ipairs({
    "scripts/settings/equipment/item_master_list", "scripts/settings/equipment/weapons",
    "scripts/unit_extensions/default_player_unit/buffs/buff_templates", "scripts/settings/breeds",
    "scripts/settings/profiles/career_settings", "scripts/settings/equipment/weapon_skins",
}) do
    local ok, err = pcall(L.load_module, name, false)
    if not ok then load_failures[#load_failures + 1] = name .. ": " .. tostring(err) end
end
io.write(string.format("vanilla files executed: %d\n", #L.order))
if #load_failures > 0 then
    for _, f in ipairs(load_failures) do io.write("LOAD FAILED ", (f:gsub("\n", "\n    ")), "\n") end
    io.write("STOP: a listed vanilla file no longer loads (WP-T-03 stop condition); record the file and line above\n")
    os.exit(3)
end
io.write(string.format("ItemMasterList=%d Weapons=%d BuffTemplates=%d Breeds=%d CareerSettings=%d\n",
    count(ItemMasterList), count(Weapons), count(BuffTemplates), count(Breeds), count(CareerSettings)))

local modmap = assert(loadfile(modmap_path))()
local get_mod, vmf_calls = assert(loadfile(here .. "/fake_vmf.lua"))()(repo, modmap.dirs)
rawset(_G, "get_mod", get_mod)

local leaks = {}
local ctx = {
    repo = repo,
    files = modmap.files or {},
    get_mod = get_mod,
    plant = selftest,
    count = count,
    real = function(value, label)
        if L.is_stub(value) then leaks[#leaks + 1] = tostring(label) .. " (stub " .. tostring(rawget(value, "__vt2_stub")) .. ")" end
        return value
    end,
}

local suite_dir = here .. "/suites"
local names = {}
for _, n in ipairs({ "vanilla_selfcheck", "wt_unlock_map", "cwv_variant_catalogs" }) do names[#names + 1] = n end

local failed = 0
for _, n in ipairs(names) do
    leaks = {}
    local fn = assert(loadfile(suite_dir .. "/" .. n .. ".lua"))()
    local ok, result = pcall(fn, ctx)
    if not ok then result = { name = n, checked = 0, problems = { "suite raised: " .. tostring(result) }, notes = {} } end
    for _, leak in ipairs(leaks) do result.problems[#result.problems + 1] = "a value from an inert engine stub reached an assertion: " .. leak end
    local bad = #result.problems > 0
    io.write(string.format("suite %-24s checked=%-5d problems=%d notes=%d%s\n", n, result.checked or 0, #result.problems,
        #(result.notes or {}), selftest and (bad and "  (planted defect seen)" or "  (PLANTED DEFECT MISSED)") or ""))
    for i = 1, math.min(#result.problems, selftest and 3 or 20) do io.write("  problem: ", result.problems[i], "\n") end
    if #result.problems > 20 and not selftest then io.write(string.format("  ... %d more\n", #result.problems - 20)) end
    for i = 1, math.min(#(result.notes or {}), 3) do io.write("  note: ", result.notes[i], "\n") end
    if selftest then
        if not bad then failed = failed + 1 end
    elseif bad then
        failed = failed + 1
    end
end

if selftest then -- the stub marker itself: a stub value reaching an assertion must be caught
    leaks = {}
    ctx.real(Unit.alive, "planted Unit.alive")
    local seen = #leaks == 1
    io.write(string.format("selftest stub marker: %s\n", seen and "a planted stub value was caught" or "A PLANTED STUB VALUE WAS NOT CAUGHT"))
    if not seen then failed = failed + 1 end
end

io.write(string.format("fake VMF calls: dofile=%d hook=%d hook_safe=%d command=%d get=%d\n", vmf_calls.dofile, vmf_calls.hook, vmf_calls.hook_safe, vmf_calls.command, vmf_calls.get))
io.write(string.format("engine stubs declared: %d; stub paths touched: %d; seconds: %.2f\n", #L.STUBS, count(L.stub_hits), os.clock() - started))
os.exit(failed > 0 and 2 or 0)
