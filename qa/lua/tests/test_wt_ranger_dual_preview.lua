return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("Ranger Dual Axes preview keeps its vanilla event distinct from Dual Hammers", function()
        local patches = dofile(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_wield_patches.lua")
        H.equal(patches.bulk.dual_wield_hammers_template.dr_ranger, nil)
        H.equal(patches.bulk.dual_wield_axes_template_1.dr_ranger, nil)

        local source_root = repo_root .. "/../Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/"
        local axes = read(source_root .. "dual_wield_axes.lua")
        local hammers = read(source_root .. "dual_wield_hammers.lua")
        H.truthy(axes:find('weapon_template.wield_anim = "to_dual_axes"', 1, true))
        H.truthy(hammers:find('weapon_template.wield_anim = "to_dual_hammers"', 1, true))
    end)

    H.test("Ranger Dual Axes reasserts the native event only after preview spawn", function()
        local main = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua")
        H.truthy(main:find("[wt:603] Ranger preview weapon=", 1, true))
        H.truthy(main:find("mod._wt603_preview_diag_seen[diag_key]", 1, true))
        H.truthy(main:find('weapon_key == "dr_dual_wield_axes"', 1, true))
        H.truthy(main:find('career_name == "dr_ranger"', 1, true))
        H.truthy(main:find('fired_event == "to_dual_axes"', 1, true))
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
