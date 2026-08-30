return function(H, repo_root)
    local streams = {
        {
            name = "stable",
            root = repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/",
        },
        {
            name = "dev",
            root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/",
        },
    }

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function register_stream_tests(stream)
        local Policy = assert(loadfile(stream.root .. "_mod_tweaker_label_policy.lua"))()

        H.test(stream.name .. " Mod Tweaker strips stale verification labels", function()
            H.equal(Policy.clean("[working] [Issue 694] Feature"), "Feature")
            H.equal(Policy.clean("[verify-fix-coop] Feature"), "Feature")
            H.equal(Policy.clean("[diagnostics-armed] Feature"), "Feature")
            H.equal(Policy.clean("[Needs Animations -> elf_sword] Feature"), "Feature")
            H.equal(Policy.clean("[WIP] Feature"), "Feature")
            H.equal(Policy.clean("(Work in Progress) Feature"), "Feature")
            H.equal(Policy.clean("Feature (Experimental)"), "Feature")
            H.equal(Policy.clean("(Testing) Feature (Unverified)"), "Feature")
        end)

        H.test(stream.name .. " Mod Tweaker preserves functional label qualifiers", function()
            for _, label in ipairs({
                "(CWV) Axe",
                "[Host Only] Reset",
                "[Client] Preview",
                "[WARNING] Unsafe",
                "[Big Rebalance] Axe",
                "[Events] Maps",
                "[EXP] 12",
                "Axe (CWV)",
                "Cooldown (seconds)",
            }) do
                H.equal(Policy.clean(label), label)
            end
        end)

        H.test(stream.name .. " Mod Tweaker twins use only the menu-label boundary", function()
            for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
                local source = read_all(stream.root .. name)
                H.truthy(string.find(source, "_mod_tweaker_label_policy", 1, true))
                H.truthy(string.find(source, "return label_policy.clean(s)", 1, true),
                    name .. " must clean successful localization")
                H.truthy(string.find(source, "return label_policy.clean(key)", 1, true),
                    name .. " must clean the fallback label")
                local _, calls = string.gsub(source, "label_policy%.clean%(", "")
                H.equal(calls, 2,
                    name .. " must not clean tooltips or source localization")
            end
        end)
    end

    for _, stream in ipairs(streams) do
        register_stream_tests(stream)
    end

    H.test("stable and dev Mod Tweaker label policies are byte-identical", function()
        local stable = read_all(streams[1].root .. "_mod_tweaker_label_policy.lua")
        local dev = read_all(streams[2].root .. "_mod_tweaker_label_policy.lua")
        H.equal(stable, dev)
    end)
end
