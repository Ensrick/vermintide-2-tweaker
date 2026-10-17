return function(H, repo_root)
local MOD_DIR = "/modded_progression/scripts/mods/modded_progression/"
local ENTRY = MOD_DIR .. "modded_progression.lua"
local MODULE = MOD_DIR .. "_mp_hook_targets.lua"

local function read_source(relative_path)
    local file = io.open(repo_root .. relative_path, "rb")
    if not file then return nil end
    local source = file:read("*a")
    file:close()
    return source
end

-- Every mp source file the entry loads: the entry itself plus each
-- "scripts/mods/modded_progression/<name>" literal it names.
local function mp_sources()
    local entry = assert(read_source(ENTRY), "mp entry file missing")
    local sources, seen = { { path = ENTRY, text = entry } }, {}
    for name in entry:gmatch('"scripts/mods/modded_progression/([%w_]+)"') do
        if not seen[name] then
            seen[name] = true
            local path = MOD_DIR .. name .. ".lua"
            local text = read_source(path)
            if text then sources[#sources + 1] = { path = path, text = text } end
        end
    end
    return sources
end

-- Literal mod:hook / hook_safe / hook_origin ("Class", "method") targets.
local function literal_targets()
    local found = {}
    for _, source in ipairs(mp_sources()) do
        for class_name, method in source.text:gmatch(
                'mod:hook[%w_]*%s*%(%s*"([%w_]+)"%s*,%s*"([%w_]+)"') do
            found[#found + 1] = { key = class_name .. "." .. method, path = source.path }
        end
    end
    return found
end

local function key_set(rows)
    local set = {}
    for _, row in ipairs(rows) do set[row.key or (row[1] .. "." .. row[2])] = true end
    return set
end

local function missing_from(left, right)
    local out = {}
    for key in pairs(left) do
        if not right[key] then out[#out + 1] = key end
    end
    table.sort(out)
    return table.concat(out, ",")
end

H.test("MP #1671 registers no hook on the removed IngameUI.not_in_modded", function()
    for _, row in ipairs(literal_targets()) do
        H.truthy(row.key ~= "IngameUI.not_in_modded",
            "dead IngameUI.not_in_modded hook still registered in " .. row.path)
        -- 6.12+ gates the loot hotkey on read_only_backend; mp leaves it
        -- vanilla because the loot screen has nothing to open (#1671, #1684).
        H.truthy(row.key ~= "IngameUI.can_open_loot",
            "mp hooks IngameUI.can_open_loot in " .. row.path)
    end
end)

H.test("MP #1671 hook-target inventory matches every literal mp hook site", function()
    local M = dofile(repo_root .. MODULE)
    local in_source = key_set(literal_targets())
    local in_module = key_set(M.TARGETS)
    H.equal(missing_from(in_source, in_module), "", "hook sites missing from _mp_hook_targets.TARGETS")
    H.equal(missing_from(in_module, in_source), "", "TARGETS rows with no hook site")
    for key in pairs(in_module) do
        H.equal(M.RETIRED[key], nil, "TARGETS lists retired method " .. key)
    end
    H.truthy(M.RETIRED["IngameUI.not_in_modded"], "retired-method record missing")
end)

H.test("MP #1671 live census fails on a missing method, defers unloaded classes", function()
    local M = dofile(repo_root .. MODULE)
    local live = {
        IngameUI = { can_open_loot = function() return false end },
        QuestManager = { get_data_by_id = function() end },
    }
    local function lookup(name) return live[name] end

    local ok_report = M.census(lookup, { { "QuestManager", "get_data_by_id" }, { "LevelEndViewBase", "init" } })
    H.equal(ok_report.resolved, 1)
    H.equal(#ok_report.missing, 0)
    H.equal(table.concat(ok_report.deferred, ","), "LevelEndViewBase")
    H.equal(M.failure(ok_report), nil)

    local gone = M.census(lookup, { { "QuestManager", "_increment_quest_stats" } })
    H.equal(M.failure(gone), "hook target missing: QuestManager._increment_quest_stats")

    local retired = M.census(lookup, { { "IngameUI", "not_in_modded" } })
    local message = M.failure(retired)
    H.truthy(message and message:find("IngameUI.not_in_modded (removed by game 6.12.0", 1, true), message)
end)

H.test("MP #1671 installs one regression check that logs its census", function()
    local M = dofile(repo_root .. MODULE)
    local checks, lines = {}, {}
    local live = {}
    for _, row in ipairs(M.TARGETS) do
        live[row[1]] = live[row[1]] or {}
        live[row[1]][row[2]] = function() end
    end
    M.install({
        rt_register = function(name, fn) checks[#checks + 1] = { name = name, fn = fn } end,
        print_log = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
        lookup = function(name) return live[name] end,
    })
    H.equal(#checks, 1)
    H.equal(checks[1].name, "mp1671_hook_targets_resolve")
    H.equal(checks[1].fn(), nil)
    H.truthy(lines[1] and lines[1]:find(string.format(
        "[mp:1671] hook targets resolved=%d missing=0 deferred=0 deferred_classes=none",
        #M.TARGETS), 1, true), lines[1])

    live.PlayFabRequestQueue = nil
    H.equal(checks[1].fn(), nil, "an unloaded class is deferred, not failed")
    H.truthy(lines[2]:find("deferred_classes=PlayFabRequestQueue", 1, true), lines[2])

    local entry = assert(read_source(ENTRY))
    local _, installs = entry:gsub('mod:dofile%("scripts/mods/modded_progression/_mp_hook_targets"%)', "")
    H.equal(installs, 1)
end)
end
