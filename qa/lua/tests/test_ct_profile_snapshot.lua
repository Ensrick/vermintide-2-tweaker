return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_profile_snapshot.lua"
    local Snapshot = assert(loadfile(path))()

    H.test("CT profile snapshot separates local profile from host-effective state", function()
        local entries = {
            { name = "boon_z" }, { name = "boon_a" }, { name = "boon_z" },
        }
        local local_values = {
            starting_coins = 300,
            disable_curse_rotten_miasma = false,
            start_boon_boon_a = true,
            start_boon_boon_z = false,
        }
        local effective_values = {
            starting_coins = 3000,
            disable_curse_rotten_miasma = true,
            start_boon_boon_a = false,
            start_boon_boon_z = true,
        }
        local snapshot = Snapshot.capture({
            phase = "setup_run", role = "client", profile = 2,
            effective_source = "host_sync", entries = entries,
            local_get = function(key) return local_values[key] end,
            effective_get = function(key) return effective_values[key] end,
            boon_label = function(name) return name == "boon_a" and "Alpha Boon" or "Zulu Boon" end,
            selected_curse = "curse_rotten_miasma",
            curse_label = function() return "Rotten Miasma" end,
        })
        H.equal(snapshot.profile, 2)
        H.equal(snapshot.coins_local, 300)
        H.equal(snapshot.coins_effective, 3000)
        H.equal(snapshot.miasma_disabled_local, false)
        H.equal(snapshot.miasma_disabled_effective, true)
        H.equal(snapshot.selected_conflict, true)
        H.deep_equal(snapshot.boon_local, { "Alpha Boon" })
        H.deep_equal(snapshot.boon_effective, { "Zulu Boon" })
        local line = Snapshot.format(snapshot, 7)
        H.truthy(string.find(line, "[ct:919] seq=7", 1, true))
        H.truthy(string.find(line, "effective_source=host_sync", 1, true))
        H.truthy(string.find(line, 'selected_curse="Rotten Miasma"', 1, true))
        H.equal(string.find(line, "\n", 1, true), nil, "snapshot must be exactly one log line")
    end)

    H.test("CT profile snapshot bounds and sanitizes user-facing boon names", function()
        local entries, enabled = {}, {}
        for i = 1, 20 do
            local name = "boon_" .. tostring(i)
            entries[#entries + 1] = { name = name }
            enabled["start_boon_" .. name] = true
        end
        local snapshot = Snapshot.capture({
            entries = entries,
            local_get = function(key) return enabled[key] end,
            effective_get = function(key) return enabled[key] end,
            boon_label = function(name)
                return name .. '\n"' .. string.rep("x", 80)
            end,
        })
        H.equal(snapshot.boon_local_count, 20)
        H.equal(#snapshot.boon_local, 12)
        H.equal(snapshot.boon_local_truncated, 8)
        local line = Snapshot.format(snapshot, 1)
        H.equal(string.find(line, "\n", 1, true), nil)
        H.truthy(#line < 1800, "bounded snapshot unexpectedly exceeded 1800 bytes")
    end)

    H.test("CT #919 diagnostic is wired at each empirical boundary without a new hook", function()
        local source = CTSource.expanded(repo_root)
        -- #1159 wave 14 moved the setup_run hook into _ct_run_creation_owner, so
        -- the setup_run boundary is asserted against that file. The needle is
        -- byte-identical; only the file moved. Every boundary is still wired
        -- exactly once across the two files, and the combined-source hook count
        -- below is what keeps "#919 must reuse the existing hook" honest.
        local run_creation_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua"
        local rc_file = assert(io.open(run_creation_path, "rb"))
        local run_creation = rc_file:read("*a")
        rc_file:close()
        for _, marker in ipairs({
            '_ct919_profile_tick(dt)',
            '_ct919_log_profile_snapshot("host_sync")',
            '_ct919_profile_setting_changed(setting_id)',
            '_ct_profile_snapshot").install(mod)',
        }) do
            H.truthy(string.find(source, marker, 1, true), "missing #919 boundary: " .. marker)
        end
        H.truthy(string.find(run_creation,
            '_ct919_log_profile_snapshot("setup_run")', 1, true),
            "missing #919 boundary: the setup_run snapshot")
        H.equal(string.find(source,
            '_ct919_log_profile_snapshot("setup_run")', 1, true), nil,
            "the setup_run snapshot must not also remain in the entry")
        local module_file = assert(io.open(path, "rb"))
        local module_source = module_file:read("*a")
        module_file:close()
        H.truthy(string.find(module_source,
            '_ct_rt_register("issue919_profile_snapshot_installed"', 1, true))
        -- Cardinality is asserted over entry AND owner together: VMF silently
        -- drops a second registration on the pair, so counting only one file
        -- would pass vacuously the moment the hook moved.
        local hook_count, cursor = 0, 1
        local hook_text = 'mod:hook("DeusRunController", "setup_run"'
        local combined = source .. "\n" .. run_creation
        while true do
            local found = string.find(combined, hook_text, cursor, true)
            if not found then break end
            hook_count = hook_count + 1
            cursor = found + #hook_text
        end
        H.equal(hook_count, 1, "#919 must reuse the existing setup_run hook")
        H.equal(string.find(source, hook_text, 1, true), nil,
            "the entry must not re-register the setup_run pair")
    end)
end
