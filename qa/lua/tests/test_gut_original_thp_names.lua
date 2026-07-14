return function(H, repo_root)
    local module_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_original_thp_names.lua"

    local function load_api(enabled)
        local registered = {}
        _G.Managers = {
            localizer = {
                append_backend_localizations = function(_, entries)
                    for key, value in pairs(entries) do
                        registered[key] = value
                    end
                end,
            },
        }
        _G.Talents = {}
        _G.get_mod = function()
            return {
                get = function(_, setting_id)
                    return setting_id == "gut_original_thp_names" and enabled
                end,
            }
        end
        return assert(loadfile(module_path))(), registered
    end

    H.test("GUT #352 supplies 60 explicit legacy THP localizations", function()
        local api, registered = load_api(false)
        local count = 0
        for key, value in pairs(api.backend_localizations) do
            count = count + 1
            H.equal(registered[key], value)
            H.truthy(key:find("gut_original_thp_name_", 1, true) == 1)
            H.truthy(value:find("_", 1, true) == nil)
            H.truthy(value:find("<", 1, true) == nil)
        end
        H.equal(count, 60)
        H.equal(api.expected_count, 60)
        H.equal(registered.gut_original_thp_name_markus_mercenary_thp_linesman, "Drillmaster")
        H.equal(registered.gut_original_thp_name_sienna_necromancer_thp_ninjafencer, "Life Leeching")
    end)

    H.test("GUT #352 applies resolvable keys and restores shared names", function()
        local api, registered = load_api(false)
        local records = {}
        for display_key in pairs(api.backend_localizations) do
            local talent_name = display_key:sub(#"gut_original_thp_name_" + 1)
            records[#records + 1] = {
                name = talent_name,
                display_name = "shared_thp_name",
            }
        end
        _G.Talents = { test_hero = records }

        api.apply(true)
        H.equal(api.validate(true), nil)
        for _, talent in ipairs(records) do
            H.equal(registered[talent.display_name], api.backend_localizations[talent.display_name])
        end

        api.apply(false)
        H.equal(api.validate(false), nil)
        for _, talent in ipairs(records) do
            H.equal(talent.display_name, "shared_thp_name")
        end
    end)

    H.test("GUT #352 re-supplies legacy names after localizer reset", function()
        local api = load_api(false)
        local refreshed = {}
        _G.Managers.localizer = {
            append_backend_localizations = function(_, entries)
                for key, value in pairs(entries) do refreshed[key] = value end
            end,
        }
        H.truthy(api.register_backend_localizations())
        H.equal(refreshed.gut_original_thp_name_victor_zealot_thp_smiter, "Repent! Repent!")
    end)
end
