-- #1696: every Ranald's Gift catalogue career and weapon value must be a GAME
-- key. The site's own codeNames for the Necromancer ("bw_necro") and her two
-- weapons ("bw_reaper", "bw_soulsteal") were copied verbatim, so every import
-- touching them failed with "item unavailable: bw_reaper" / "career
-- unavailable". The deterministic cases use the generated vanilla census; the
-- optional case re-reads the decompiled 6.13.0 source when it is present.
return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local catalog = assert(loadfile(root .. "_cim_ranalds_catalog.lua"))()
    local census = assert(loadfile(repo_root
        .. "/qa/lua/fixtures/vanilla_weapon_master_list.lua"))()

    -- The census reads only `ItemMasterList.<key> = {` rows. The five Chaos
    -- Wastes weapons live in a local table in item_master_list_morris.lua
    -- (:6 dr, :190 es, :411 we, :641 bw, :874 wh; slot_type at :20, :203,
    -- :425, :654, :887) merged into ItemMasterList at :1576.
    local CHAOS_WASTES = {
        dr_deus_01 = "ranged", es_deus_01 = "melee", we_deus_01 = "ranged",
        bw_deus_01 = "ranged", wh_deus_01 = "ranged",
    }

    local function live_tables()
        local item_master_list, career_settings = {}, {}
        for key, row in pairs(census.weapons) do
            item_master_list[key] = { slot_type = row.slot_type, can_wield = row.can_wield }
        end
        for key, slot_type in pairs(CHAOS_WASTES) do
            item_master_list[key] = { slot_type = slot_type }
        end
        for i = 1, #census.hero_careers do
            career_settings[census.hero_careers[i]] = { name = census.hero_careers[i] }
        end
        return item_master_list, career_settings
    end

    local function contains(list, value)
        for i = 1, #(list or {}) do if list[i] == value then return true end end
        return false
    end

    H.test("#1696 every catalogue career and weapon names a live game row", function()
        local item_master_list, career_settings = live_tables()
        local missing = {}
        for id, key in pairs(catalog.CAREERS) do
            if not career_settings[key] then
                missing[#missing + 1] = "career " .. id .. "=" .. key
            end
        end
        for id, key in pairs(catalog.WEAPONS) do
            local row = item_master_list[key]
            if not row or (row.slot_type ~= "melee" and row.slot_type ~= "ranged") then
                missing[#missing + 1] = "weapon " .. id .. "=" .. key
            end
        end
        table.sort(missing)
        H.deep_equal(missing, {}, "catalogue keys the game does not define")
    end)

    H.test("#1696 Necromancer ids map to the shovel career and weapons", function()
        H.equal(catalog.CAREERS[20], "bw_necromancer")
        H.equal(catalog.WEAPONS[82], "bw_ghost_scythe")
        H.equal(catalog.WEAPONS[83], "bw_necromancy_staff")
        local item_master_list = live_tables()
        -- Site: 82 Ensorcelled Reaper is melee for every Sienna career, 83
        -- Soulstealer Staff is ranged for the Necromancer only.
        H.equal(item_master_list.bw_ghost_scythe.slot_type, "melee")
        H.equal(item_master_list.bw_necromancy_staff.slot_type, "ranged")
        H.truthy(contains(item_master_list.bw_ghost_scythe.can_wield, "bw_necromancer"))
        H.truthy(contains(item_master_list.bw_ghost_scythe.can_wield, "bw_unchained"))
        H.truthy(contains(item_master_list.bw_necromancy_staff.can_wield, "bw_necromancer"))
        local seen = {}
        for id, key in pairs(catalog.CAREERS) do
            H.equal(seen[key], nil, "duplicate career key " .. key)
            seen[key] = id
        end
        seen = {}
        for id, key in pairs(catalog.WEAPONS) do
            H.equal(seen[key], nil, "duplicate weapon key " .. key)
            seen[key] = id
        end
    end)

    H.test("#1696 runtime resolver reports exactly the unresolved keys", function()
        H.equal(type(catalog.unresolved_game_keys), "function")
        local item_master_list, career_settings = live_tables()
        H.deep_equal(catalog.unresolved_game_keys(item_master_list, career_settings), {})

        item_master_list.bw_ghost_scythe = nil
        item_master_list.dr_crossbow = { slot_type = "weapon_skin" }
        career_settings.bw_necromancer = nil
        H.deep_equal(catalog.unresolved_game_keys(item_master_list, career_settings), {
            "career 20=bw_necromancer", "weapon 50=dr_crossbow", "weapon 82=bw_ghost_scythe",
        })

        -- A strict __index like ItemMasterListMeta (item_master_list.lua:133)
        -- must never be consulted.
        local strict = setmetatable({}, { __index = function(_, key)
            error("strict lookup of " .. tostring(key))
        end })
        local missing = catalog.unresolved_game_keys(strict, strict)
        H.equal(#missing, 103)
        missing = catalog.unresolved_game_keys(nil, nil)
        H.equal(#missing, 103)
    end)

    local source_root = (os.getenv("VT2_DECOMPILE_ROOT")
        or (repo_root .. "/../Vermintide-2-Source-Code")) .. "/scripts/settings/"
    local function read(path)
        local file = io.open(source_root .. path, "rb")
        if not file then return nil end
        local text = file:read("*a")
        file:close()
        return (text:gsub("\r\n", "\n"))
    end
    local item_files = {
        "equipment/item_master_list_exported.lua", "equipment/item_master_list_anvil.lua",
        "equipment/item_master_list_paperweight.lua", "dlcs/lake/item_master_list_lake.lua",
        "dlcs/cog/item_master_list_cog.lua", "dlcs/woods/item_master_list_woods.lua",
        "dlcs/bless/item_master_list_bless.lua", "dlcs/shovel/item_master_list_shovel.lua",
    }
    local career_files = {
        "profiles/career_settings.lua", "dlcs/lake/career_settings_lake.lua",
        "dlcs/cog/career_settings_cog.lua", "dlcs/woods/career_settings_woods.lua",
        "dlcs/bless/career_settings_bless.lua", "dlcs/shovel/career_settings_shovel.lua",
    }
    local morris = read("equipment/item_master_list_morris.lua")

    H.test_if(morris ~= nil, "#1696 catalogue keys resolve in the decompiled source", function()
        local items, careers = {}, {}
        for i = 1, #item_files do items[#items + 1] = assert(read(item_files[i]), item_files[i]) end
        for i = 1, #career_files do careers[#careers + 1] = assert(read(career_files[i]), career_files[i]) end
        local item_text = "\n" .. table.concat(items, "\n")
        local career_text = "\n" .. table.concat(careers, "\n")
        H.truthy(morris:find("\ntable.merge(ItemMasterList, item_master_list)\n", 1, true),
            "morris rows are no longer merged into ItemMasterList")

        local missing = {}
        for id, key in pairs(catalog.WEAPONS) do
            local body = item_text:match("\nItemMasterList%." .. key .. " = {\n(.-)\n}")
            local slot = body and body:match("\n\tslot_type = \"([a-z_]+)\"")
            if not body then
                body = morris:match("\n\t" .. key .. " = {\n(.-)\n\t},")
                slot = body and body:match("\n\t\tslot_type = \"([a-z_]+)\"")
            end
            if slot ~= "melee" and slot ~= "ranged" then
                missing[#missing + 1] = "weapon " .. id .. "=" .. key
            end
        end
        for id, key in pairs(catalog.CAREERS) do
            if not (career_text:find("\n\t" .. key .. " = {\n", 1, true)
                    or career_text:find("\nCareerSettings." .. key .. " = {\n", 1, true)) then
                missing[#missing + 1] = "career " .. id .. "=" .. key
            end
        end
        table.sort(missing)
        H.deep_equal(missing, {}, "catalogue keys absent from the decompiled source")
    end, "decompiled Vermintide-2-Source-Code checkout not found (set VT2_DECOMPILE_ROOT)")
end
