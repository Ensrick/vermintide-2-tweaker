-- Cluster C regression (issues 288 / 464): the Anath Raema's Swiftness
-- permanent-reload rework. Mechanism (decompile-verified): wield applies trait
-- buffs via SimpleInventoryExtension.apply_buffs -> buff_extension:add_buff
-- (simple_inventory_extension.lua:824), BuffExtension.add_buff resolves the
-- template AT CALL TIME through BuffUtils.get_buff_template
-- (buff_extension.lua:165,173) which reads the live BuffTemplates global
-- (buff_utils.lua:256-262) - so enforcing the template swap inside the CT
-- BuffExtension.add_buff hook, BEFORE calling vanilla, guarantees the
-- replacement lands regardless of load order. The issue 464 root (a +0.5
-- multiplier on the INVERSE reload_speed stat = 50 percent SLOWER) is pinned
-- as a sign contract.

return function(H, repo_root)
    local balance_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
        .. "_ct_boon_balance.lua"
    local f = assert(io.open(balance_path, "rb"))
    local balance_src = f:read("*a")
    f:close()

    H.test("CT Anath Raema replacement is a faster-reload (negative) stat buff", function()
        local name_pos = assert(string.find(balance_src,
            'name        = "deus_ammo_pickup_reload_speed_permanent"', 1, true),
            "permanent replacement child buff missing")
        local block = string.sub(balance_src, name_pos, name_pos + 300)
        H.truthy(string.find(block, 'stat_buff   = "reload_speed"', 1, true))
        H.truthy(string.find(block, "multiplier  = %-0%.5") ~= nil,
            "issue 464 sign contract broken: reload_speed is inverse, the permanent buff must be -0.5")
        H.truthy(string.find(block, "max_stacks  = 1", 1, true))
    end)

    H.test("CT Anath Raema dual-registry swap and marker intact", function()
        H.truthy(string.find(balance_src,
            'CT_ANATH_RAEMA_RETRY_MARKER = "anath_raema:enforce_at_add_buff_v0.7.268"', 1, true),
            "issue 288 marker drifted; update rt + this test together")
        H.truthy(string.find(balance_src,
            'wt.buff_templates.deus_ammo_pickup_reload_speed', 1, true),
            "WeaponTraits.buff_templates entry no longer handled")
        H.truthy(string.find(balance_src,
            'bt.deus_ammo_pickup_reload_speed', 1, true),
            "BuffTemplates entry no longer handled")
    end)

    local meta_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
        .. "_ct_meta_trait_boons.lua"
    local f2 = assert(io.open(meta_path, "rb"))
    local meta_src = f2:read("*a")
    f2:close()

    H.test("CT Anath Raema enforced at the native add_buff lookup boundary", function()
        local hook_head = 'mod:hook("BuffExtension", "add_buff"'
        local hook_pos = assert(string.find(meta_src, hook_head, 1, true),
            "BuffExtension.add_buff hook missing")
        H.equal(string.find(meta_src, hook_head, hook_pos + 1, true), nil,
            "second BuffExtension.add_buff hook would be silently dropped by VMF")
        local guard = assert(string.find(meta_src,
            'if template_name == "deus_ammo_pickup_reload_speed" and effective_setting("tweak_anath_raema_permanent") then',
            hook_pos, true), "issue 288 add-boundary enforcement missing from the hook body")
        local enforce_zone = string.sub(meta_src, guard, guard + 400)
        H.truthy(string.find(enforce_zone, "apply_anath_raema_permanent_tweak()", 1, true),
            "enforcement no longer re-applies the template swap before vanilla resolves it")
    end)
end
