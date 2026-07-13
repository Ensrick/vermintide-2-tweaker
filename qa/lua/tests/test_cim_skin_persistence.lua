return function(H, repo_root)
    local path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/illusion_swap.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    H.test("CIM observes shared Apply Skin completion", function()
        H.truthy(source:find(
            'mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete"',
            1, true
        ))
        H.truthy(source:find(
            '"item_customization_complete"', 1, true
        ))
        H.truthy(source:find("local skin_key = pending_skin or item.skin", 1, true))
    end)

    H.test("CIM uses one exact-ID persistence entry point", function()
        H.truthy(source:find("mod._cim563_commit_explicit_skin_choice = function", 1, true))
        H.truthy(source:find("mod._cim563_plan_explicit_skin_choice = function", 1, true))
        H.truthy(source:find("saved, backend_id, skin_key, not is_modded", 1, true))
    end)
end
