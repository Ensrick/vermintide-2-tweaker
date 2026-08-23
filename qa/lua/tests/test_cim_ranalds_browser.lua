return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local file = assert(io.open(root .. "_cim_ranalds_browser.lua", "rb"))
    local source = file:read("*a"); file:close()

    H.test("Ranald browser is hook-free and driven by the existing forge UI owner", function()
        H.equal(source:find("mod:hook", 1, true), nil)
        H.truthy(source:find("COMMUNITY BUILDS", 1, true))
        H.truthy(source:find("IMPORT SELECTED BUILD", 1, true))
        H.truthy(source:find("SORT: LIKES", 1, true))
        H.truthy(source:find("SORT: RECENT", 1, true))
        H.truthy(source:find("career_prev", 1, true))
        H.truthy(source:find("page_next", 1, true))
    end)

    H.test("Ranald browser opens on the current career and cancels on close", function()
        local old_get_mod = _G.get_mod
        _G.get_mod = function() return {} end
        local browser = assert(loadfile(root .. "_cim_ranalds_browser.lua"))()
        _G.get_mod = old_get_mod
        local fetched, cancelled = nil, 0
        browser.configure({
            catalog = { CAREERS = { [8] = "we_maidenguard" }, PAGE_SIZE = 5,
                sort = function(rows) return rows end },
            fetcher = { fetch = function(career, callback)
                fetched = career; callback({}, nil, { rejected=0 }); return true
            end, cancel = function() cancelled = cancelled + 1 end },
            current_career_id = function() return 8 end,
            career_label = function() return "Handmaiden" end,
            import_build = function() return true end,
        })
        H.equal(browser.open(), true); H.equal(browser.is_open(), true); H.equal(fetched, 8)
        browser.close(); H.equal(browser.is_open(), false); H.equal(cancelled, 1)
    end)
end
