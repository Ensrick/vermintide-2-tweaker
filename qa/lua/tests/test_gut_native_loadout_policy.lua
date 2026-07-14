return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("native-loadout readonly preserves exact CWV instances", function()
        H.equal(Policy.readonly_action("slot_melee", "cwv_es_dual_axes_001"), "preserve")
        H.equal(Policy.readonly_action("slot_melee", "cwv_es_dual_maces_001"), "preserve")
        H.equal(Policy.readonly_action("slot_ranged", "cwv_es_crossbow_100"), "preserve")
        H.equal(Policy.is_cwv_backend_id("cwv_es_dual_axes"), false)
        H.equal(Policy.is_cwv_backend_id("D12DB867521442B3"), false)
    end)

    H.test("native-loadout readonly keeps official realm isolation policy", function()
        H.equal(Policy.mode(false, false), Policy.MODE_OFF)
        H.equal(Policy.mode(false, true), Policy.MODE_OFF)
        H.equal(Policy.mode(true, false), Policy.MODE_STORE)
        H.equal(Policy.mode(true, true), Policy.MODE_READONLY)
        H.equal(Policy.readonly_action("slot_hat", "mod_hat_instance"), "preserve")
        H.equal(Policy.readonly_action("slot_melee", "D12DB867521442B3"), "clear")
        H.equal(Policy.readonly_action("slot_necklace", "cwv_fake_001"), "block")
        H.equal(Policy.readonly_action("talents", "1,2,3,4,5,6"), "block")
    end)
end
