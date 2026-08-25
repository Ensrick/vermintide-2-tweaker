return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. relative, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function exists(relative)
        local file = io.open(repo_root .. relative, "rb")
        if not file then return false end
        file:close()
        return true
    end

    local function count_literal(source, needle)
        local count, cursor = 0, 1
        while true do
            local found = source:find(needle, cursor, true)
            if not found then return count end
            count = count + 1
            cursor = found + #needle
        end
    end

    H.test("WT #499 retires the consumed Longbow observer without retiring #316 coverage", function()
        H.equal(false, exists(
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_longbow_zoom_probe.lua"))
        H.equal(false, exists(
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_diag_longbow_zoom.lua"))

        local owner = read(
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua")
        for _, retired in ipairs({
            "_WT316_ZOOM_PROBE",
            "_wt316_zoom_probe",
            "_wt316_zoom_records",
            "_wt316_post_update_observer",
            "longbow-live-probe-owner",
            "longbow-live-probe-hooks",
            "[wt:316]",
        }) do
            H.equal(0, count_literal(owner, retired), retired .. " must stay retired")
        end
        H.equal(0, count_literal(owner,
            'mod:hook_safe("ActionAim", "client_owner_start_action"'))
        H.equal(0, count_literal(owner,
            'mod:hook_safe("ActionAim", "finish"'))

        local runtime = read(
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_runtime_checks.lua")
        H.equal(0, count_literal(runtime, "zoom_probe"))
        H.equal(1, count_literal(runtime,
            '_rt_register("issue316_kruber_longbow_zoom_contract"'))
        H.equal(1, count_literal(runtime,
            '_rt_register("issue316_empire_longbow_cross_career_variable_zoom"'))

        local registry = read("/qa/diagnostic_ownership.psd1")
        H.equal(0, count_literal(registry, "_wt_longbow_zoom_probe.lua"))
        H.equal(0, count_literal(registry, "_wt_diag_longbow_zoom.lua"))
        H.equal(0, count_literal(registry, "Issues=@(316)"))

        local public_policy = read(
            "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_longbow_variable_zoom.lua")
        local dev_policy = read(
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_longbow_variable_zoom.lua")
        H.equal(public_policy, dev_policy)
        H.equal(0, count_literal(public_policy, "_wt316_post_update_observer"))
        H.equal(1, count_literal(public_policy,
            'mod:hook_safe("ActionAim", "client_owner_post_update"'))
    end)

    H.test("WT #316 preserves Kruber draw_bow on owner and husk while retaining Saltz crossbow", function()
        -- #1159 moved the source-template patchers out of the entry into their
        -- own owner; this gate follows the code.
        local main = read(
            "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_cross_char_template_patches.lua")
        local core = read("/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap.lua")
        for _, career in ipairs({ "es_mercenary", "es_knight", "es_questingknight" }) do
            H.truthy(main:find("longbow_empire_template." .. career .. "%s*=%s*false"),
                career .. " must explicitly preserve the native draw event")
        end
        H.truthy(main:find(
            "longbow_empire_template.wh_%s*=%s*_SALTZ_LONGBOW_CROSSBOW_ANIM_REMAP_3P"),
            "Saltzpyre crossbow substitution was removed")
        H.truthy(core:find('mod:traced_hook("SimpleInventoryExtension", "wield"', 1, true),
            "owner 3P state seam missing")
        H.truthy(core:find('mod:safe_hook("SimpleHuskInventoryExtension", "wield"', 1, true),
            "remote husk state seam missing")
        H.truthy(core:find("if _local_fp_unit and unit == _local_fp_unit then", 1, true),
            "first-person bypass missing")
    end)
end
