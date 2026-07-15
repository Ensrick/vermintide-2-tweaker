return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_policy274.lua"
    local Policy = assert(loadfile(path))()

    H.test("issue 274 skips only the authored mission intro event", function()
        H.equal(Policy.classify("cs_01_skip"), "intro")
        H.truthy(Policy.is_intro("cs_01_skip"))

        local never_skip = {
            "cs_02_skip",
            "cs_outro_skip",
            "mission_end_skip",
            "boss_phase_skip",
            "well_of_dreams_outro",
            "dlc_dwarf_whaling_outro",
            "",
        }
        for i = 1, #never_skip do
            H.equal(Policy.is_intro(never_skip[i]), false, never_skip[i])
            H.equal(Policy.classify(never_skip[i]), "non_intro", never_skip[i])
        end
        H.equal(Policy.is_intro(nil), false)
        H.equal(Policy.classify(nil), "locked")
    end)

    H.test("issue 274 post-intro camera guard expires deterministically", function()
        local owner, other = {}, {}
        H.truthy(Policy.guard_is_active(owner, owner, Policy.POST_INTRO_GUARD_SECONDS))
        H.equal(Policy.guard_is_active(owner, other, Policy.POST_INTRO_GUARD_SECONDS), false)
        H.equal(Policy.guard_is_active(owner, owner, 0), false)

        local remaining = Policy.tick_guard(Policy.POST_INTRO_GUARD_SECONDS, 11)
        H.equal(remaining, 4)
        remaining = Policy.tick_guard(remaining, 4)
        H.equal(remaining, 0)
        H.equal(Policy.guard_is_active(owner, owner, remaining), false)
        H.equal(Policy.tick_guard(3, -10), 3)
    end)
end
