return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    H.test("#749 census gate is wired and owns an exact manifest", function()
        local manifest = read("qa/native_resource_contracts.psd1")
        local checker = read("qa/check_native_resource_contracts.ps1")
        local runner = read("qa/run_all.ps1")
        H.truthy(manifest:find("SchemaVersion = 1", 1, true))
        H.truthy(manifest:find("Issue = 749", 1, true))
        H.truthy(checker:find("uncensused native boundary", 1, true))
        H.truthy(checker:find("count drift", 1, true))
        H.truthy(runner:find("check_native_resource_contracts.ps1", 1, true))
    end)

    H.test("#749 shared seams are strict while global GUT preserves unknown resources", function()
        local manifest = read("qa/native_resource_contracts.psd1")
        for _, path in ipairs({
            "_cwv_old_musket_preview.lua",
            "_cos_custom_hats.lua",
            "_la_bridge.lua",
            "cosmetics_tweaker.lua",
            -- #1159: carries the shading + residency_proof pair the entry used
            -- to own, so the manifest rows citing this test stay real evidence.
            "_cos_customization_view_lifecycle.lua",
            "_cim_athanor_icon_policy.lua",
            "_cim_mission_forge_safety.lua",
            "_gt_bot_teleport_lab.lua",
            "_gt_debug_highlights.lua",
            "_woc_blightreaper_pulse.lua",
        }) do
            H.truthy(manifest:find(path, 1, true), path)
        end
        H.truthy(manifest:find("shared-v2-strict", 1, true))
        H.truthy(manifest:find("shared-v2-global-preserve-unknown", 1, true))
        H.truthy(manifest:find("deferred-legacy", 1, true))
    end)
end
