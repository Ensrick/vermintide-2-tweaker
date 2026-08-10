return function(H, repo_root)
    local path = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_longbow_zoom_probe.lua"
    local Probe = assert(loadfile(path))()

    H.test("WT longbow zoom probe targets only non-Huntsman Kruber", function()
        for _, career in ipairs({ "es_mercenary", "es_knight", "es_questingknight" }) do
            H.truthy(Probe.is_target("longbow_empire_template", career))
        end
        H.truthy(not Probe.is_target("longbow_empire_template", "es_huntsman"))
        H.truthy(not Probe.is_target("longbow_empire_template", "wh_captain"))
        H.truthy(not Probe.is_target("longbow_template_1", "es_mercenary"))
    end)

    H.test("WT longbow zoom probe observes once at the authored due time", function()
        local probe = Probe.new()
        local rec = probe:arm("longbow_empire_template", "es_mercenary", "es_longbow", 10, 10.22)
        H.truthy(rec)
        H.equal(nil, probe:observe(rec, 10.21, false, nil))
        local result = probe:observe(rec, 10.22, true, "zoom_in")
        H.equal("camera_zoomed", result.outcome)
        H.equal("zoom_in", result.zoom_mode)
        H.equal("unverified", result.visible_draw)
        H.equal(nil, probe:observe(rec, 10.30, true, "zoom_in"))
    end)

    H.test("WT longbow zoom probe records early finish and caps attempts", function()
        local probe = Probe.new(2)
        local one = probe:arm("longbow_empire_template", "es_knight", "es_longbow", 1, 1.22)
        local result = probe:finish(one, 1.1, "action_complete")
        H.equal("finished_before_observation", result.outcome)
        H.equal(nil, probe:finish(one, 1.2, "duplicate"))
        H.truthy(probe:arm("longbow_empire_template", "es_knight", "es_longbow", 2, 2.22))
        H.equal(nil, probe:arm("longbow_empire_template", "es_knight", "es_longbow", 3, 3.22))
    end)

    H.test("WT #316 preserves Kruber draw_bow on owner and husk while retaining Saltz crossbow", function()
        local function read(relative)
            local file = assert(io.open(repo_root .. relative, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        -- #1159 moved the source-template patchers out of the entry into their
        -- own owner; this gate follows the code.
        local main = read(
            "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_char_template_patches.lua")
        local core = read("/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua")
        for _, career in ipairs({ "es_mercenary", "es_knight", "es_questingknight" }) do
            H.truthy(main:find("longbow_empire_template." .. career .. "%s*=%s*false"),
                career .. " must explicitly preserve the native draw event")
        end
        H.truthy(main:find("longbow_empire_template.wh_%s*=%s*_SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P"),
            "Saltzpyre crossbow substitution was removed")
        H.truthy(core:find('mod:traced_hook("SimpleInventoryExtension", "wield"', 1, true),
            "owner 3P state seam missing")
        H.truthy(core:find('mod:safe_hook("SimpleHuskInventoryExtension", "wield"', 1, true),
            "remote husk state seam missing")
        H.truthy(core:find("if _local_fp_unit and unit == _local_fp_unit then", 1, true),
            "first-person bypass missing")
    end)
end
