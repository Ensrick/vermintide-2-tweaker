-- WP-COS-02 (audit finding A3-F12): the cosmetics regression runner counted
-- any nil return as PASS and any string as FAIL, so a check that could not
-- inspect its subject reported PASS. A returned "skip: <reason>" is now a SKIP,
-- and every verdict also reaches the engine log as "[cos-regression] ...".
-- Loads the real _cos_command_owner.lua with a fake mod and runs the command.
return function(H, repo_root)
    local path = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_command_owner.lua"

    local function run_checks(defs)
        local echoes, printfs, commands = {}, {}, {}
        local function fmt(f, ...)
            if select("#", ...) == 0 then return tostring(f) end
            return string.format(tostring(f), ...)
        end
        local mod = {
            command = function(_, name, _, fn) commands[name] = fn end,
            echo = function(_, f, ...) echoes[#echoes + 1] = fmt(f, ...) end,
            info = function() end,
            warning = function() end,
            get = function() return nil end,
            set = function() end,
        }
        local owner_module = assert(loadfile(path))()
        local register = owner_module.install(mod, {
            version = "0.9.test-dev",
            local_player_safe = function(pm) return pm and pm:local_player_safe() end,
            la_persist = {},
            printf = function(f, ...) printfs[#printfs + 1] = fmt(f, ...) end,
        })
        for _, def in ipairs(defs) do register(def[1], def[2]) end
        commands.cos_regression_test()
        return echoes, printfs
    end

    local function count_prefix(lines, prefix)
        local n = 0
        for _, line in ipairs(lines) do
            if line:sub(1, #prefix) == prefix then n = n + 1 end
        end
        return n
    end

    local function find_line(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    H.test("COS A3-F12 runner scores nil, a reason and skip: as PASS, FAIL and SKIP", function()
        local echoes, printfs = run_checks({
            { "synth_passes", function() return nil end },
            { "synth_fails", function() return "boom" end },
            { "synth_skips", function() return "skip: no context" end },
        })
        H.truthy(find_line(echoes, "  PASS: synth_passes"))
        H.truthy(find_line(echoes, "  FAIL: synth_fails -- boom"))
        local skip_line = find_line(echoes, "  SKIP: synth_skips")
        H.truthy(skip_line, "a skip: return must render as SKIP")
        H.truthy(skip_line:find("context absent: no context", 1, true), "same echo format as the precondition SKIP")
        H.equal(find_line(echoes, "PASS: synth_skips"), nil, "a skip is never a PASS")
        H.equal(find_line(echoes, "FAIL: synth_skips"), nil, "a skip is never a FAIL")
        -- One PASS, one FAIL, one SKIP among the synthetic checks (the owner
        -- registers one check of its own, which passes under this fake mod).
        H.equal(count_prefix(echoes, "  SKIP: "), 1)
        H.equal(count_prefix(echoes, "  FAIL: "), 1)
        H.truthy(find_line(printfs, "[cos-regression] PASS synth_passes"))
        H.truthy(find_line(printfs, "[cos-regression] FAIL synth_fails -- boom"))
        H.truthy(find_line(printfs, "[cos-regression] SKIP synth_skips -- no context"))
    end)
end
