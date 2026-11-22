-- Characterization of the modded loadout writers in gui_tweaker_dev/_gut_native_loadouts.lua
-- (WP-GUT-02 step 0, before the store extraction; the oracle for WP-GUT-03's routing).
-- Each case drives the REAL hook bodies through _gut_native_owner_fixture.lua and pins the
-- literal saved tables, the save count, the vanilla call count, and that the fake official
-- tables (_career_data, _career_data_mirror, _career_loadouts) are never mutated.
return function(H, repo_root)
    local tests = repo_root .. "/qa/lua/tests/"
    local Fixture = assert(loadfile(tests .. "_gut_native_owner_fixture.lua"))()
    local Policy = assert(loadfile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua"))()
    local cases, reads = assert(loadfile(tests .. "_gut_loadout_writer_cases.lua"))()(Fixture, Policy)
    local PREFIX = "[gut_dev:NATIVE_LOADOUTS] "

    for _, c in ipairs(cases) do
        H.test("writer characterization: " .. c.name, function()
            local s = Fixture.new(repo_root, "gui_tweaker_dev", c.options)
            c.old(s)
            H.deep_equal(s:saved("native_loadouts"), c.expected, "saved store")
            if c.expected_overlay ~= nil then
                H.deep_equal(s:saved("native_cosmetic_overlay"), c.expected_overlay, "saved overlay")
            end
            H.equal(s.saves.native_loadouts or 0, c.saves, "store save count")
            if c.overlay_saves ~= nil then
                H.equal(s.saves.native_cosmetic_overlay or 0, c.overlay_saves, "overlay save count")
            end
            if c.vanilla_calls ~= nil then
                H.equal(s.vanilla_calls, c.vanilla_calls, "vanilla call count")
            end
            if c.log ~= nil then
                local found = false
                for _, line in ipairs(s.lines) do if line == PREFIX .. c.log then found = true end end
                H.truthy(found, "log line missing: " .. c.log)
            end
            H.truthy(s:official_untouched(), "official tables were mutated")
        end)
    end

    H.test("writer characterization: get_character_data read decision", function()
        local s = Fixture.new(repo_root, "gui_tweaker_dev", reads.options)
        for _, r in ipairs(reads.rows) do
            local served = s:hook("PlayFabMirrorAdventure.get_character_data", reads.career, r.key, r.index)
            H.equal(served, r.served, "served " .. r.key .. " index " .. tostring(r.index))
        end
        H.truthy(s:official_untouched(), "a read mutated official tables")
        H.truthy(#s.vanilla_args > 0, "no official fallback read happened")
        for _, args in ipairs(s.vanilla_args) do
            H.equal(args[4], nil, "an official fallback read must pass a nil index, never the store index")
        end
        H.equal(s.saves.native_loadouts or 0, 0, "reads of a seeded store save nothing")
    end)
end
