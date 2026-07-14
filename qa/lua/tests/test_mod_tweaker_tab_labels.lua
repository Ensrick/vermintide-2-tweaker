return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Labels = assert(loadfile(root .. "_mod_tweaker_tab_labels.lua"))()

    H.test("Modded Progression uses the exact Progression tab label", function()
        H.equal(Labels.exact("mp"), "PROGRESSION")
    end)

    H.test("existing compact tab labels remain centralized", function()
        H.equal(Labels.exact("cim"), "CRAFTING")
        H.equal(Labels.exact("cim_dev"), "CRAFTING")
        H.equal(Labels.exact("character_weapon_variants"), "CWV")
        H.equal(Labels.exact("character_weapon_variants_dev"), "CWV")
        H.equal(Labels.exact("unknown_mod"), nil)
    end)

    H.test("Progression tab policy exposes a passing runtime check", function()
        H.equal(#Labels.rt_checks, 1)
        H.equal(Labels.rt_checks[1].name, "issue525_progression_tab_label")
        H.equal(Labels.rt_checks[1].fn(), nil)
    end)

    H.test("both Mod Tweaker presentations use the shared tab-label policy", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(string.find(source, "_mod_tweaker_tab_labels", 1, true))
            local _, calls = string.gsub(source, "tab_labels%.exact%(", "")
            H.equal(calls, 2, name .. " must resolve measurement and rendered labels identically")
        end
    end)
end
