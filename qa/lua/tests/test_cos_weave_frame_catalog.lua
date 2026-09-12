-- #1000: the data-only Weave Season 5-10 frame provider and its bounded
-- census command. Optional decompiled atlas sources prove the exact sprite
-- names without becoming a required CI dependency.
return function(H, repo_root)
    local base = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local path = base .. "_cos_weave_frame_catalog.lua"
    local Catalog = assert(loadfile(path))()

    local function read(file_path)
        local file = assert(io.open(file_path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    H.test("#1000 catalog covers six seasons and four guide tiers", function()
        local entries = Catalog.entries()
        H.equal(Catalog.api_version, 1)
        H.equal(Catalog.count(), 24)
        H.equal(#entries, 24)
        H.equal(#Catalog.seasons(), 6)
        H.equal(#Catalog.tiers(), 4)
        H.equal(entries[1].key, "frame_season_05_quickplay")
        H.equal(entries[#entries].key, "frame_season_10_tier_3")
        H.equal(entries[2].tier_display, "40")
        H.equal(entries[4].weave_threshold, 120)
        H.equal(entries[1].weave_threshold, nil)
    end)

    H.test("#1000 guide wind order is explicit and deterministic", function()
        local winds = {}
        for _, season in ipairs(Catalog.seasons()) do
            winds[#winds + 1] = season.wind .. ":" .. season.number
        end
        H.equal(table.concat(winds, ","), "Ghyran:5,Azyr:6,Ulgu:7,Shyish:8,Ghur:9,Chamon:10")
    end)

    H.test("#1000 provider derives exact atlas and vanilla-convention keys", function()
        local seen = {}
        for _, entry in ipairs(Catalog.entries()) do
            H.equal(seen[entry.key], nil, "duplicate key " .. entry.key)
            seen[entry.key] = true
            H.truthy(entry.key:match("^frame_season_%d%d_[%w_]+$"), entry.key)
            H.equal(entry.inventory_icon, "icon_portrait_" .. entry.key)
            H.equal(entry.hud_texture, "portrait_" .. entry.key)
            H.equal(entry.vanilla_display_name_key, "portrait_" .. entry.key .. "_name")
            H.equal(entry.vanilla_description_key, "portrait_" .. entry.key .. "_description")
            H.equal(entry.source_kind, "vanilla_atlas")
            H.equal(Catalog.get(entry.key).key, entry.key)
        end
        H.equal(Catalog.get("frame_season_04_quickplay"), nil)
        H.equal(Catalog.source_kind, "vanilla_atlas")
        H.equal(Catalog.registered, false)
        H.equal(Catalog.native_wire_safe, false)
    end)

    H.test("#1000 provider returns snapshots instead of shared mutable rows", function()
        local first = Catalog.entries()[1]
        first.wind = "mutated"
        H.equal(Catalog.get(first.key).wind, "Ghyran")
        local fetched = Catalog.get(first.key)
        fetched.inventory_icon = "mutated"
        H.equal(Catalog.entries()[1].inventory_icon, "icon_portrait_frame_season_05_quickplay")
        local seasons = Catalog.seasons()
        seasons[1].wind = "mutated"
        H.equal(Catalog.seasons()[1].wind, "Ghyran")
        local tiers = Catalog.tiers()
        tiers[2].display = "mutated"
        H.equal(Catalog.tiers()[2].display, "40")
    end)

    H.test("#1000 census keeps registration and wire identity separate", function()
        local report = Catalog.census({}, {}, {}, {})
        H.deep_equal(report, { total = 24, item_master_missing = 24, cosmetics_missing = 24,
            frame_settings_missing = 24, network_lookup_missing = 24 })
        H.deep_equal(Catalog.census(nil, 7, "x", false), report)
        local item_master, cosmetics, settings, lookup = {}, {}, {}, {}
        local first = Catalog.entries()[1]
        item_master[first.key] = true
        cosmetics[first.key] = true
        settings[first.key] = true
        lookup[first.key] = 1
        report = Catalog.census(item_master, cosmetics, settings, lookup)
        H.equal(report.item_master_missing, 23)
        H.equal(report.cosmetics_missing, 23)
        H.equal(report.frame_settings_missing, 23)
        H.equal(report.network_lookup_missing, 23)
        -- rawget: an erroring __index (vanilla ItemMasterList) is never invoked.
        local strict = setmetatable({}, { __index = function() error("strict lookup") end })
        H.equal(Catalog.census(strict, strict, strict, strict).item_master_missing, 24)
    end)

    H.test("#1000 atlas census counts exact inventory and HUD sprites", function()
        local present = {}
        for _, entry in ipairs(Catalog.entries()) do
            present[entry.inventory_icon] = true
            present[entry.hud_texture] = true
        end
        local report = Catalog.atlas_census(function(name) return present[name] == true end)
        H.deep_equal(report, { total = 24, inventory_present = 24, hud_present = 24 })
        present.icon_portrait_frame_season_07_tier_2 = nil
        present.portrait_frame_season_10_quickplay = nil
        report = Catalog.atlas_census(function(name)
            if name == "portrait_frame_season_09_tier_1" then error("atlas failure") end
            return present[name] and true or "yes"
        end)
        H.equal(report.inventory_present, 23)
        H.equal(report.hud_present, 22)
        H.deep_equal(Catalog.atlas_census(nil), { total = 24, inventory_present = 0, hud_present = 0 })
    end)

    H.test("#1000 localization census accepts only resolved vanilla text", function()
        local resolved = {
            portrait_frame_season_05_quickplay_name = "Ghyran Quickplay",
            portrait_frame_season_05_quickplay_description = "",
            portrait_frame_season_06_tier_1_name = "<portrait_frame_season_06_tier_1_name>",
            portrait_frame_season_06_tier_1_description = "portrait_frame_season_06_tier_1_description",
            portrait_frame_season_07_tier_2_description = "Azure text",
        }
        local report = Catalog.localization_census(function(key)
            if key == "portrait_frame_season_08_tier_3_name" then error("localize failure") end
            return resolved[key] or ("<" .. key .. ">")
        end)
        H.deep_equal(report, { total = 24, names_resolved = 1, descriptions_resolved = 1 })
        H.deep_equal(Catalog.localization_census(nil),
            { total = 24, names_resolved = 0, descriptions_resolved = 0 })
    end)

    H.test("#1000 provider does not mutate engine, network or inventory tables", function()
        local source = read(path):gsub("%-%-[^\n]*", "")
        for _, needle in ipairs({ "NetworkLookup", "ItemMasterList", "rawset", "network_send",
            "mod:hook", "mod:set", "Cosmetics[", "_G" }) do
            H.equal(source:find(needle, 1, true), nil, "catalog references " .. needle)
        end
        local unlocks = read(base .. "_cos_unlocks.lua")
        H.truthy(unlocks:find('COS.weave_frames = mod:dofile("scripts/mods/cosmetics_tweaker/_cos_weave_frame_catalog")', 1, true))
    end)

    H.test("#1000 diagnostic command prints one finite census line", function()
        local source = read(base .. "_cos_diagnostics.lua"):gsub("\r\n", "\n")
        local block = assert(source:match('(local function _issue1000_frame_census%(%).-\nmod:command%("cos_1000_diag".-\nend%))'))
        local callback = assert(block:match('\nmod:command%("cos_1000_diag".-\nend%)$'))
        H.equal(callback:find("for ", 1, true), nil, "census emitter stays loop-free")
        H.equal(callback:find("\n%s*local%s+[%w_]+%s*,"), nil, "callback keeps a simple body")
        local registered, logs, flushed, echoed = {}, {}, 0, 0
        local present = {}
        for _, entry in ipairs(Catalog.entries()) do
            present[entry.inventory_icon] = true
            present[entry.hud_texture] = true
        end
        local env = {
            pcall = pcall, type = type, rawget = rawget,
            _flush_log = function() flushed = flushed + 1 end,
            printf = function(format, ...) logs[#logs + 1] = string.format(format, ...) end,
        }
        env._G = env
        env.COS = { weave_frames = Catalog }
        env.mod = {
            command = function(_, name, description, fn)
                registered[name] = { description = description, callback = fn }
            end,
            echo = function() echoed = echoed + 1 end,
        }
        env.ItemMasterList = { frame_season_05_quickplay = {} }
        env.Cosmetics = {}
        env.UIPlayerPortraitFrameSettings = {}
        env.NetworkLookup = { cosmetics = {} }
        env.UIAtlasHelper = { has_atlas_settings_by_texture_name = function(name)
            return present[name] == true
        end }
        env.Localize = function(key) return "<" .. key .. ">" end
        setfenv(assert(loadstring(block)), env)()
        local command = assert(registered.cos_1000_diag)
        H.equal(command.description, "Census the resident Weave Season 5-10 portrait frames")
        command.callback()
        command.callback()
        local expected = "[cos:1000:diag] census frames=24 inventory_atlas=24 hud_atlas=24 "
            .. "vanilla_names=0 vanilla_descriptions=0 unregistered_items=23 "
            .. "unregistered_cosmetics=24 unregistered_templates=24 unregistered_lookup=24"
        H.equal(logs[1], expected)
        H.equal(logs[2], expected)
        env.COS.weave_frames = nil
        command.callback()
        H.equal(logs[3], "[cos:1000:diag] census frames=0 inventory_atlas=0 hud_atlas=0 "
            .. "vanilla_names=0 vanilla_descriptions=0 unregistered_items=-1 "
            .. "unregistered_cosmetics=-1 unregistered_templates=-1 unregistered_lookup=-1")
        H.equal(#logs, 3)
        H.equal(flushed, 3)
        H.equal(echoed, 3)
    end)

    local source_root = (os.getenv("VT2_SOURCE_ROOT")
        or ((os.getenv("USERPROFILE") or "") .. "/source/repos/Vermintide-2-Source-Code"))
    local items_atlas = source_root .. "/scripts/ui/atlas_settings/gui_items_atlas.lua"
    local hud_atlas = source_root .. "/scripts/ui/atlas_settings/gui_hud_atlas.lua"
    local function exists(file_path)
        local file = io.open(file_path, "rb")
        if not file then return false end
        file:close()
        return true
    end
    H.test_if(exists(items_atlas) and exists(hud_atlas),
        "#1000 optional decompiled atlases declare every provider sprite", function()
            local items = read(items_atlas)
            local hud = read(hud_atlas)
            for _, entry in ipairs(Catalog.entries()) do
                H.truthy(items:find("\n\t" .. entry.inventory_icon .. " = {", 1, true), entry.inventory_icon)
                H.truthy(hud:find("\n\t" .. entry.hud_texture .. " = {", 1, true), entry.hud_texture)
            end
            -- Vanilla registers Season 4 but no Season 5-10 identity.
            H.truthy(items:find("\n\ticon_portrait_frame_season_04_quickplay = {", 1, true))
        end, "optional decompiled vanilla atlas sources unavailable")
end
