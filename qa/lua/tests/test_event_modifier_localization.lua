return function(H, repo_root)
    -- Issue 1149 (localization half): the options menu showed raw mutator keys
    -- next to the dynamically discovered modifiers, and several managed curses
    -- resolve no icon. These tests drive the REAL shipped localization file,
    -- curse catalog, and mutator catalog under a stubbed engine surface.
    local base = repo_root .. "/event_tweaker/scripts/mods/event_tweaker/"
    local Curses = assert(loadfile(base .. "event_tweaker_curses.lua"))()
    local Catalog = assert(loadfile(base .. "event_tweaker_catalog.lua"))()

    -- Engine stub: one package-free dynamic mutator (surfaces in the "Other
    -- Mutators" group), one managed curse without a template icon, and one
    -- whose display_name deliberately misses localization.
    local mutator_templates = {
        curse_change_of_tzeentch = {
            display_name = "curse_change_of_tzeentch_name",
            description = "curse_change_of_tzeentch_desc",
            icon = "deus_curse_tzeentch_01",
        },
        curse_corrupted_flesh = {
            display_name = "curse_corrupted_flesh_name",
            description = "curse_corrupted_flesh_desc",
            packages = { "resource_packages/curse_corrupted_flesh" },
        },
        blessing_of_shallya = {
            display_name = "blessing_of_shallya_name",
            description = "blessing_of_shallya_desc",
        },
    }
    local localized = {
        curse_change_of_tzeentch_name = "Tzeentch Twins",
        curse_change_of_tzeentch_desc = "Slain enemies have a 25% chance to split.",
        curse_corrupted_flesh_name = "Corrupted Flesh",
        curse_corrupted_flesh_desc = "Enemies burst on death.",
    }
    local function fake_localize(key)
        return localized[key] or ("<" .. tostring(key) .. ">")
    end

    local function load_localization()
        local env = {
            require = function(path)
                if path == "scripts/mods/event_tweaker/event_tweaker_curses" then
                    return Curses
                end
                error("unexpected require: " .. tostring(path))
            end,
            _G = { MutatorTemplates = mutator_templates, Localize = fake_localize },
            rawget = rawget, pairs = pairs, ipairs = ipairs, next = next,
            type = type, tostring = tostring, string = string, table = table,
        }
        local chunk = assert(loadfile(base .. "event_tweaker_localization.lua"))
        setfenv(chunk, env)
        return chunk()
    end

    H.test("Event Tweaker curated mutator catalog is fully localized", function()
        local loc = load_localization()
        for i = 1, #Catalog.CATEGORIES do
            local cat = Catalog.CATEGORIES[i]
            H.truthy(loc[cat.id], cat.id .. " group label missing")
            for j = 1, #cat.mutators do
                local id = cat.mutators[j]
                H.truthy(loc["mut_" .. id], "mut_" .. id .. " label missing")
                H.truthy(loc["mut_" .. id .. "_tooltip"], "mut_" .. id .. " tooltip missing")
            end
        end
    end)

    H.test("Event Tweaker dynamic modifier labels carry no raw mutator keys", function()
        local loc = load_localization()
        local title = loc.mut_curse_change_of_tzeentch
        H.truthy(title, "dynamic label missing for curse_change_of_tzeentch")
        H.equal(title.en, "Tzeentch Twins")
        H.equal(title.en:find("curse_change_of_tzeentch", 1, true), nil)
        local tooltip = loc.mut_curse_change_of_tzeentch_tooltip
        H.equal(tooltip.en:find("[curse_change_of_tzeentch]", 1, true), nil)
        H.truthy(tooltip.en:find("split", 1, true))
        -- Literal % survives as %% for VMF's string.format tooltip path.
        H.truthy(tooltip.en:find("25%%", 1, true))
    end)

    H.test("Event Tweaker managed curse labels localize from the game's display_name", function()
        local loc = load_localization()
        local title = loc.mut_curse_corrupted_flesh
        H.equal(title.en, "Curse: Corrupted Flesh")
        local tooltip = loc.mut_curse_corrupted_flesh_tooltip
        H.equal(tooltip.en:find("[curse_corrupted_flesh]", 1, true), nil)
        H.equal(tooltip.en:find("Enemies burst on death.", 1, true), 1)
        H.truthy(tooltip.en:find("god: nurgle", 1, true))
        -- Every managed curse gets BOTH rows even when the template is absent.
        for i = 1, #Curses.MANAGED_CURSES do
            local id = Curses.MANAGED_CURSES[i].id
            H.truthy(loc["mut_" .. id], "managed label missing for " .. id)
            H.truthy(loc["mut_" .. id .. "_tooltip"], "managed tooltip missing for " .. id)
        end
    end)

    H.test("Event Tweaker unlocalized display names fall back humanized, never raw", function()
        local loc = load_localization()
        local title = loc.mut_blessing_of_shallya
        H.truthy(title, "dynamic label missing for blessing_of_shallya")
        H.equal(title.en, "Blessing Of Shallya")
        H.equal(title.en:find("_", 1, true), nil)
        H.equal(title.en:find("<", 1, true), nil)
    end)

    H.test("Event Tweaker icon resolver covers every managed curse", function()
        -- Template icon wins; god-theme icon (the one vanilla's Deus curse UI
        -- shows) covers templates that ship none; non-curses stay name-only.
        H.equal(Curses.icon_for("curse_change_of_tzeentch",
            mutator_templates.curse_change_of_tzeentch), "deus_curse_tzeentch_01")
        H.equal(Curses.icon_for("curse_corrupted_flesh",
            mutator_templates.curse_corrupted_flesh), "icon_nurgle")
        H.equal(Curses.icon_for("curse_corrupted_flesh", nil), "icon_nurgle")
        H.equal(Curses.icon_for("no_ammo", nil), nil)
        for i = 1, #Curses.MANAGED_CURSES do
            local entry = Curses.MANAGED_CURSES[i]
            H.truthy(Curses.GOD_ICONS[entry.god],
                "no god icon mapped for " .. tostring(entry.god))
            H.truthy(Curses.icon_for(entry.id, nil),
                "no icon resolves for managed curse " .. entry.id)
        end
    end)
end
