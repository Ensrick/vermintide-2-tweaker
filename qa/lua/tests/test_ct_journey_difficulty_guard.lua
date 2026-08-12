return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local mod_root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local owner_path = mod_root .. "_ct_journey_difficulty_guard.lua"

local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function exists(path)
        local file = io.open(path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    local source_roots = {
        repo_root .. "/../Vermintide-2-Source-Code/scripts/",
        repo_root .. "/../../../../source/repos/Vermintide-2-Source-Code/scripts/",
    }
    local source_root = source_roots[1]
    for _, candidate in ipairs(source_roots) do
        if exists(candidate .. "managers/backend/statistics_util.lua") then
            source_root = candidate
            break
        end
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read(mod_root .. "chaos_wastes_tweaker_dev.lua")
    local owner = read(owner_path)
    local regression = read(mod_root .. "_ct_regression.lua")
    -- #1159 wave 14: the entry no longer loads this guard directly. The load moved
    -- into the run-creation owner along with the two neighbours it was interleaved
    -- with, so the ordering assertions below read that file.
    local run_creation = read(mod_root .. "_ct_run_creation_owner.lua")

    H.test("CT #291 guard has one owner at the preserved hook boundary", function()
        local load_needle =
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_journey_difficulty_guard"
        local hook_needle =
            'mod:hook("StatisticsUtil", "_register_completed_journey_difficulty"'
        -- #1159 wave 14: this guard's load sat BETWEEN the replacement-runtime
        -- install above it and the setup_run hook below it, so all three moved
        -- together into _ct_run_creation_owner rather than reordering seven hook
        -- registrations. The needles are byte-identical and only the file moved;
        -- the guard is still loaded exactly once, from exactly one place.
        H.equal(count_plain(run_creation, load_needle), 1)
        H.equal(count_plain(entry, load_needle), 0)
        H.equal(count_plain(owner, hook_needle), 1)
        H.equal(count_plain(entry, hook_needle), 0)
        H.equal(count_plain(run_creation, hook_needle), 0)

        local replacement_at = assert(run_creation:find(
            "mod._ct_replacement_runtime.install", 1, true))
        local owner_at = assert(run_creation:find(load_needle, 1, true))
        local setup_at = assert(run_creation:find(
            'mod:hook("DeusRunController", "setup_run"', 1, true))
        H.truthy(replacement_at < owner_at)
        H.truthy(owner_at < setup_at)

        -- The entry-side half of the same ordering: the run-creation owner (which
        -- now carries all three) still installs before the regression suite, so
        -- /ct_regression_test append order is unchanged.
        local run_creation_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner", 1, true))
        local regression_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression", 1, true))
        H.truthy(run_creation_at < regression_at)
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner"), 1)
    end)

    H.test("CT #291 owner retains its marker and no unrelated runtime surface", function()
        local marker = "CT_JOURNEY_DIFFICULTY_GUARD_MARKER"
        H.equal(count_plain(owner, marker .. " ="), 1)
        H.equal(count_plain(entry, marker .. " ="), 0)
        H.truthy(regression:find(marker, 1, true))
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "network_register"), 0)
        H.equal(count_plain(owner, "mod.on_"), 0)
        H.equal(count_plain(owner, "mod.update ="), 0)
        H.equal(count_plain(owner, "mod:hook("), 1)
        H.equal(count_plain(owner, "mod:hook_safe("), 0)
    end)

    H.test("CT #291 installer clamps only unsupported recorded difficulties", function()
        local old_managers = rawget(_G, "Managers")
        local old_printf = rawget(_G, "printf")
        local old_table_find = table.find
        local old_marker = rawget(_G, "CT_JOURNEY_DIFFICULTY_GUARD_MARKER")

        local function exercise()
            local defaults = { "normal", "hard", "harder", "hardest", "cataclysm" }
            local hooks, logs = {}, {}
            _G.Managers = {
                state = {
                    difficulty = {
                        get_default_difficulties = function() return defaults end,
                    },
                },
            }
            _G.printf = function(format_string, ...)
                logs[#logs + 1] = string.format(format_string, ...)
            end
            table.find = function(values, needle)
                for index, value in ipairs(values) do
                    if value == needle then return index end
                end
            end

            local fake_mod = {
                hook = function(_, class_name, method_name, callback)
                    hooks[#hooks + 1] = {
                        class_name = class_name,
                        method_name = method_name,
                        callback = callback,
                    }
                end,
            }
            local installer = assert(loadfile(owner_path))()
            installer(fake_mod)
            H.equal(#hooks, 1)
            H.equal(hooks[1].class_name, "StatisticsUtil")
            H.equal(hooks[1].method_name,
                "_register_completed_journey_difficulty")
            H.equal(CT_JOURNEY_DIFFICULTY_GUARD_MARKER,
                "journey_difficulty_clamp_to_default_max_v0.7.220")

            local forwarded = {}
            local function original(statistics_db, player, journey, god, difficulty)
                forwarded[#forwarded + 1] = {
                    statistics_db, player, journey, god, difficulty,
                }
                return "first", "second"
            end
            local callback = hooks[1].callback
            local a, b = callback(original, "db", "player", "journey_citadel",
                "khorne", "harder")
            H.equal(a, "first")
            H.equal(b, "second")
            H.deep_equal(forwarded[1], {
                "db", "player", "journey_citadel", "khorne", "harder",
            })
            H.equal(#logs, 0)

            callback(original, "db2", "player2", "journey_citadel",
                "slaanesh", "cataclysm_3")
            H.deep_equal(forwarded[2], {
                "db2", "player2", "journey_citadel", "slaanesh", "cataclysm",
            })
            H.equal(#logs, 1)
            H.truthy(logs[1]:find("recording as 'cataclysm'", 1, true))

            defaults = false
            callback(original, "db3", "player3", "journey_citadel",
                "nurgle", "cataclysm_3")
            H.equal(forwarded[3][5], "cataclysm_3")
            H.equal(#logs, 1)
        end

        local ok, failure = xpcall(exercise, debug.traceback)
        _G.Managers = old_managers
        _G.printf = old_printf
        table.find = old_table_find
        _G.CT_JOURNEY_DIFFICULTY_GUARD_MARKER = old_marker
        if not ok then error(failure, 0) end

        H.equal(rawget(_G, "Managers"), old_managers)
        H.equal(rawget(_G, "printf"), old_printf)
        H.equal(table.find, old_table_find)
        H.equal(rawget(_G, "CT_JOURNEY_DIFFICULTY_GUARD_MARKER"), old_marker)
    end)

    local statistics_path = source_root .. "managers/backend/statistics_util.lua"
    local difficulty_path = source_root .. "settings/difficulty_settings.lua"
    local has_vanilla_source = exists(statistics_path) and exists(difficulty_path)

    H.test_if(has_vanilla_source,
        "CT #291 guard matches the current vanilla nil-index crash contract", function()
        local statistics = read(statistics_path)
        local difficulty = read(difficulty_path)
        local function_start = assert(statistics:find(
            "StatisticsUtil._register_completed_journey_difficulty = function", 1, true))
        local function_end = assert(statistics:find("\nend", function_start, true))
        local body = statistics:sub(function_start, function_end)
        local defaults_at = assert(body:find(
            "Managers.state.difficulty:get_default_difficulties()", 1, true))
        local find_at = assert(body:find(
            "table.find(difficulties, difficulty_name)", 1, true))
        local compare_at = assert(body:find(
            "current_completed_difficulty < difficulty_index", 1, true))
        H.truthy(defaults_at < find_at and find_at < compare_at)

        local list_start = assert(difficulty:find("DefaultDifficulties = {", 1, true))
        local list_end = assert(difficulty:find("\n}", list_start, true))
        local list = difficulty:sub(list_start, list_end)
        local cursor = 1
        for _, name in ipairs({
            "normal", "hard", "harder", "hardest", "cataclysm",
        }) do
            local at = assert(list:find('"' .. name .. '"', cursor, true))
            cursor = at + #name + 2
        end
        H.equal(list:find('"cataclysm_2"', 1, true), nil)
        H.equal(list:find('"cataclysm_3"', 1, true), nil)
        end, "optional decompiled vanilla source is not present in this clean clone")
end
