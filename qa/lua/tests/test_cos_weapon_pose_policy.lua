return function(H, repo_root)
    local path = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_weapon_pose_policy.lua"
    local Policy = dofile(path)

    H.test("Cosmetics authored pose catalog is parent-scoped and sorted", function()
        local master = {
            pose_b = { item_type = "weapon_pose", parent = "sword", pose_index = 2, data = { anim_event = "anim_pose_02" } },
            pose_a = { item_type = "weapon_pose", parent = "sword", pose_index = 1, data = { anim_event = "anim_pose_01" } },
            axe_pose = { item_type = "weapon_pose", parent = "axe", pose_index = 1, data = { anim_event = "anim_pose_01" } },
            malformed = { item_type = "weapon_pose", parent = "sword", pose_index = 3 },
            ordinary = { item_type = "weapon_skin", parent = "sword", pose_index = 4, data = { anim_event = "bad" } },
        }
        local catalog = Policy.build_catalog(master)
        local sword = Policy.for_parent(catalog, "sword")
        H.equal(#sword, 2)
        H.equal(sword[1].ItemId, "pose_a")
        H.equal(sword[2].ItemId, "pose_b")
        H.equal(#Policy.for_parent(catalog, "axe"), 1)
        H.equal(Policy.for_parent(catalog, "missing"), nil)
    end)

    H.test("Cosmetics pose catalog wrappers do not mutate authored data", function()
        local data = { item_type = "weapon_pose", parent = "sword", pose_index = 1, data = { anim_event = "pose" } }
        local catalog = Policy.build_catalog({ pose = data })
        local row = Policy.for_parent(catalog, "sword")[1]
        H.equal(row.data, data)
        H.equal(data.backend_id, nil)
        H.equal(row.backend_id, "cos_pose:pose")
    end)

    H.test("Cosmetics pose production stays local and exact-parent wired", function()
        local module_path = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_weapon_poses.lua"
        local f = assert(io.open(module_path, "rb")); local source = f:read("*a"); f:close()
        H.truthy(source:find('mod:hook("SocialWheelUI", "_gather_weapon_poses_by_parent_item"', 1, true))
        H.truthy(source:find('mod:hook("SocialWheelUI", "_is_dirty"', 1, true))
        H.truthy(source:find('script_data["eac-untrusted"] == true', 1, true))
        H.truthy(source:find('Policy.for_parent(get_catalog(), parent_item)', 1, true))
        H.equal(source:find("set_read_only_data", 1, true), nil)
        H.equal(source:find("add_unlocked_weapon_pose", 1, true), nil)
        H.equal(source:find("network_send", 1, true), nil)
    end)
end
