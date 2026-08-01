return function(H, repo_root)
    local policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_godmode_vortex_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    H.test("GT Godmode blocks only the Blightstorm entering edge", function()
        H.equal(Policy.should_block_entry(true, true, true), true)
        H.equal(Policy.should_block_entry(true, true, false), false)
        H.equal(Policy.should_block_entry(true, false, true), false)
        H.equal(Policy.should_block_entry(false, true, true), false)
        H.equal(Policy.should_block_entry(false, false, true), false)
        H.equal(Policy.should_block_entry(nil, true, true), false)
        H.equal(Policy.should_block_entry(true, nil, true), false)
        H.equal(Policy.should_block_entry(true, true, nil), false)
        H.equal(Policy.should_block_entry(1, true, true), false)
        H.equal(Policy.should_block_entry(true, 1, true), false)
        H.equal(Policy.should_block_entry(true, true, 1), false)
    end)

    H.test("GT Godmode Blightstorm gate owns the authored server seam once", function()
        local module_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua"
        local file = assert(io.open(module_path, "rb"))
        local source = file:read("*a")
        file:close()

        local _, hook_count = source:gsub(
            'mod:hook%("StatusUtils", "set_in_vortex_network"', "")
        H.equal(hook_count, 1)
        H.truthy(source:find("_GT_1009_GODMODE_VORTEX_MARKER", 1, true))
        H.truthy(source:find(
            'ScriptUnit.has_extension%(%s+vortex_unit, "ai_supplementary_system"%)'))
        H.truthy(source:find("ALIVE%[vortex_unit%]"))
        H.truthy(source:find(
            "%[gt:1009%] blocked Blightstorm capture template=%%s"))
        H.truthy(source:find(
            "return func(affected_unit, in_vortex, vortex_unit)", 1, true))
    end)
end
