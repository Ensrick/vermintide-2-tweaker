return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("Ranger dual preview keeps vanilla family wield events distinct", function()
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

    H.test("Ranger dual preview diagnostic is bounded and reuses preview hook", function()
        local main = read(repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua")
        H.truthy(main:find("[wt:603] Ranger preview weapon=", 1, true))
        H.truthy(main:find("mod._wt603_preview_diag_seen[diag_key]", 1, true))
        H.equal(main:find('mod:hook("HeroPreviewer", "_spawn_item_unit"', 1, true), nil)
    end)
end
