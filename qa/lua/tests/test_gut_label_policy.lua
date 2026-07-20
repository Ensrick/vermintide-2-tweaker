return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_mod_tweaker_label_policy.lua"))()

    H.test("Mod Tweaker strips stale leading verification prefixes", function()
        H.equal(Policy.clean("[working] [Issue 694] Feature"), "Feature")
        H.equal(Policy.clean("[verify-fix] Feature"), "Feature")
        -- verify-fix-coop is a retired lifecycle label (now verify-fix +
        -- coop-required), but an older sibling bundle can still emit it.
        H.equal(Policy.clean("[verify-fix-coop] Feature"), "Feature")
        H.equal(Policy.clean("[diagnostics-armed] Feature"), "Feature")
        H.equal(Policy.clean("[Needs Animations -> elf_sword] Feature"), "Feature")
        H.equal(Policy.clean("[WIP] Feature"), "Feature")
        H.equal(Policy.clean("(Work in Progress) Feature"), "Feature")
        H.equal(Policy.clean("Feature (Experimental)"), "Feature")
        H.equal(Policy.clean("(Testing) Feature (Unverified)"), "Feature")
    end)

    H.test("Mod Tweaker preserves functional label qualifiers", function()
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

    H.test("both dev presentations use the shared label policy", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(string.find(source, "_mod_tweaker_label_policy", 1, true))
            local _, calls = string.gsub(source, "label_policy%.clean%(", "")
            H.equal(calls, 2, name .. " must normalize localized and fallback labels")
        end
    end)
end
