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

    H.test("#1125 particle census pins the exact Moonfire native owner packages", function()
        local manifest = read("qa/native_resource_contracts.psd1")
        local checker = read("qa/check_native_resource_contracts.ps1")
        local oracle = dofile(repo_root
            .. "/qa/lua/tests/fixtures/moonfire_native_resource_oracle.lua")
        H.truthy(checker:find("particle = [regex]", 1, true))
        H.equal(oracle.source_commit,
            "c5e4968b1fbb00c49884e56d640ef990a9c04dd0")
        H.equal(oracle.unpacker_commit,
            "73ad7c295c0495ca6686397d5f3014b27c6cc885")
        H.equal(oracle.effect, "fx/wpnfx_we_deus_01_impact")
        H.equal(oracle.effect_hash, "D44D88664CFC5FD1")
        H.equal(oracle.canonical_owner.package, "resource_packages/dlcs/morris")
        H.equal(oracle.canonical_owner.bundle_hash, "2e2f2b4d974d1c9f")
        H.equal(oracle.canonical_owner.installed_sha256,
            "F1D0191100019D07AF5167B6AE44B6180F9F29BDCCF933549C6A4A988033661B")
        H.equal(oracle.canonical_owner.load_reference, "boot")
        H.equal(oracle.additional_owner.package,
            "units/weapons/player/wpn_we_deus_01/wpn_we_deus_01")
        H.equal(oracle.additional_owner.bundle_hash, "3a3e55a7e74d5d2e")
        H.equal(oracle.additional_owner.installed_sha256,
            "5E0C7EC6B26F9B3E135AD686A08746A8B93606494B7C417BC3D0341E4818764C")
        H.equal(#oracle.not_owners, 2)
        H.equal(oracle.not_owners[1].package,
            "units/weapons/player/wpn_we_deus_01/wpn_we_deus_01_3p")
        H.equal(oracle.not_owners[1].bundle_hash, "180b628657a5c3d3")
        H.equal(oracle.not_owners[1].installed_sha256,
            "0A76D688FFF7BD6880C998E780F352D74B63D3F433CFBA08BD7BCDE546BB1E8D")
        H.equal(oracle.not_owners[2].package, "resource_packages/dlcs/morris_ingame")
        H.equal(oracle.not_owners[2].bundle_hash, "f5b9c97431b34ca6")
        H.equal(oracle.not_owners[2].installed_sha256,
            "FAA2D43EEC80E070E19CA5FD210C6A89ED27C9AB035F6DF63CD7A9844779089B")
        for _, path in ipairs({
            "weapon_tweaker/scripts/mods/weapon_tweaker/_wt_moonfire_aoe.lua",
            "weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_moonfire_aoe.lua",
            "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_moonfire_puff_runtime.lua",
        }) do
            local row = "File='" .. path .. "'; Kind='particle'; Count=1; "
                .. "Policy='owned-world-existing'; "
                .. "Evidence='qa/lua/tests/fixtures/moonfire_native_resource_oracle.lua'"
            H.truthy(manifest:find(row, 1, true), "missing exact Moonfire row: " .. path)
        end
    end)

    H.test("#1125 shared texture writers census descriptor reachability", function()
        local manifest = read("qa/native_resource_contracts.psd1")
        local checker = read("qa/check_native_resource_contracts.ps1")
        H.truthy(checker:find("Get-WeaponAppearanceDescriptorRows", 1, true))
        H.truthy(checker:find("texture_descriptor", 1, true))
        H.truthy(checker:find(
            "planted consumer texture descriptor fails without an exact reachability row",
            1, true))
        local path = "character_weapon_variants/scripts/mods/"
            .. "character_weapon_variants/_cwv_old_musket_appearance.lua"
        H.truthy(manifest:find("File='" .. path
            .. "'; Kind='texture_descriptor'; Count=2", 1, true), path)
        H.equal(manifest:find(
            "cosmetics_tweaker_data.lua'; Kind='texture_descriptor'", 1, true), nil,
            "VMF GUI texture tables are not shared-writer descriptor reachability")
    end)
end
