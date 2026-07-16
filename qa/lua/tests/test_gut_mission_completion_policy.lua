return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mission_completion_policy.lua"
    local Policy = assert(loadfile(path))()

    local native = { display_name = "native" }
    local custom = { display_name = "late_custom" }
    local difficulties = { "normal", "hard" }

    local function complete_definitions()
        return {
            native = { military = { normal = {}, hard = {} } },
            late_custom = { military = { normal = {}, hard = {} } },
        }
    end

    H.test("GUT issue 649 preserves fully defined profile identity", function()
        local profile = { careers = { native, custom }, marker = "unchanged" }
        local filtered, safe_count, missing = Policy.filtered_profile(profile, "military",
            difficulties, complete_definitions())

        H.equal(filtered, profile, "all-defined path must delegate the original profile")
        H.equal(safe_count, 2)
        H.equal(#missing, 0)
    end)

    H.test("GUT issue 649 skips only undefined custom career leaves", function()
        local definitions = complete_definitions()
        definitions.late_custom = nil
        local profile = { careers = { native, custom } }
        local missing = Policy.missing_careers(profile, "military", difficulties, definitions)
        H.equal(#missing, 1)
        H.equal(missing[1], "late_custom")

        local filtered, safe_count = Policy.filtered_profile(profile, "military",
            difficulties, definitions)
        H.truthy(filtered ~= profile, "missing path must use a shallow profile copy")
        H.equal(safe_count, 1)
        H.equal(filtered.careers[1], native)
        H.equal(profile.careers[2], custom, "source profile must remain unchanged")
    end)

    H.test("GUT issue 649 detects an exact missing difficulty leaf", function()
        local definitions = complete_definitions()
        definitions.late_custom.military.hard = nil
        local missing = Policy.missing_careers({ careers = { native, custom } },
            "military", difficulties, definitions)

        H.equal(#missing, 1)
        H.equal(missing[1], "late_custom")
        H.equal(Policy.definition_exists(definitions, "late_custom", "military", "normal"), true)
        H.equal(Policy.definition_exists(definitions, "late_custom", "military", "hard"), false)
    end)

    H.test("GUT issue 649 preserves all profile fields and metatable", function()
        local meta = { __index = { inherited = true } }
        local profile = setmetatable({ careers = { native, custom }, marker = "kept" }, meta)
        local definitions = complete_definitions()
        definitions.late_custom = nil
        local filtered = Policy.filtered_profile(profile, "military", difficulties, definitions)

        H.equal(filtered.marker, "kept")
        H.equal(filtered.inherited, true)
        H.equal(getmetatable(filtered), meta)
    end)
end
