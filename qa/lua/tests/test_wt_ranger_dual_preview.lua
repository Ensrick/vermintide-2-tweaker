return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function exists(path)
        local file = io.open(path, "rb")
        if file then file:close() end
        return file ~= nil
    end

    local source_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/"

    H.test_if(exists(source_root .. "dual_wield_axes.lua"),
        "Ranger Dual Axes preview uses the non-Slayer dual-wield stance", function()
        local patches = dofile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_wield_patches.lua")
        H.equal(patches.bulk.dual_wield_hammers_template.dr_ranger, nil)
        H.equal(patches.bulk.dual_wield_axes_template_1.dr_ranger, nil)

        local axes = read(source_root .. "dual_wield_axes.lua")
        local hammers = read(source_root .. "dual_wield_hammers.lua")
        H.truthy(axes:find('weapon_template.wield_anim = "to_dual_axes"', 1, true))
        H.truthy(hammers:find('weapon_template.wield_anim = "to_dual_hammers"', 1, true))
        end, "optional decompiled vanilla source is not present in this clean clone")

    H.test("Ranger Dual Axes corrects only the exact preview tuple", function()
        local main = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua")
        H.truthy(main:find("[wt:603] Ranger preview weapon=", 1, true))
        H.truthy(main:find("mod._wt603_preview_diag_seen[diag_key]", 1, true))
        H.truthy(main:find('weapon_key == "dr_dual_wield_axes"', 1, true))
        H.truthy(main:find('career_name == "dr_ranger"', 1, true))
        H.truthy(main:find('fired_event == "to_dual_axes"', 1, true))
        H.truthy(main:find('return "to_dual_hammers"', 1, true))
        H.truthy(main:find('"dr_dual_wield_hammers", "dr_ranger", "to_dual_hammers") == nil', 1, true))
        H.truthy(main:find('"dr_dual_wield_axes", "dr_slayer", "to_dual_axes") == nil', 1, true))
        H.truthy(main:find('pcall(Unit.animation_event, preview_body, post_spawn_event)', 1, true))
        H.truthy(main:find('issue603_ranger_dual_axes_inventory_preview_pose', 1, true))
        H.equal(main:find('mod:hook("HeroPreviewer", "_spawn_item_unit"', 1, true), nil)
    end)

    H.test("appearance standard makes every 3P model and pose surface explicit", function()
        local standard = read(repo_root .. "/docs/WEAPON_APPEARANCE_STANDARD.md")
        for _, surface in ipairs({
            "Owner, mission local 3P",
            "Bot, keep + mission",
            "Client/remote husk, keep + mission",
            "Inventory-screen character preview (path 3)",
            "Lobby character presentation",
            "End-of-mission score/team preview",
        }) do
            H.truthy(standard:find(surface, 1, true), "missing appearance surface: " .. surface)
        end
        H.truthy(standard:find("| **Pose/animation** |", 1, true))
        H.truthy(standard:find("Model correctness does not prove pose correctness.", 1, true))
    end)
end
