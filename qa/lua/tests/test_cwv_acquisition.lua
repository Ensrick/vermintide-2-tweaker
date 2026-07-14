return function(H, repo_root)
    local helper = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_acquisition.lua")

    H.test("CWV migration removes only authored legacy auto-grants", function()
        local ids = helper.legacy_auto_grant_ids({
            { item_key = "cwv_one" },
            { item_key = "cwv_two", instances = 2 },
            { item_key = "cwv_skin", skin_only = true, instances = 9 },
        })
        H.truthy(ids.cwv_one_001)
        H.truthy(ids.cwv_two_001)
        H.truthy(ids.cwv_two_002)
        H.equal(ids.cwv_two_100, nil)
        H.equal(ids.cwv_skin_001, nil)
    end)

    H.test("CWV migration preserves exact CIM persistence", function()
        local ids = { cwv_one_001 = true }
        H.truthy(helper.should_remove("cwv_one_001", ids, function() return false end))
        H.equal(helper.should_remove("cwv_one_001", ids, function(id)
            return id == "cwv_one_001"
        end), false)
        H.equal(helper.should_remove("cwv_one_100", ids, function() return false end), false)
        H.equal(helper.should_remove("cwv_one_uuid", ids, function() return false end), false)
    end)

    H.test("CWV source separates registration from acquisition", function()
        local path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(source:find('add_mod_items_to_local_backend(entries, "character_weapon_variants")', 1, true), nil)
        H.truthy(source:find("entry.cwv_definition = backend_id == nil", 1, true))
        H.truthy(source:find("legacy_auto_grant_ids(_variant_definitions)", 1, true))
    end)
end
