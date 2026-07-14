return function(H, repo_root)
    local Policy = assert(loadfile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_career_hud_holder_policy.lua"))()

    H.test("GUT career holder census separates dedicated art from fallback", function()
        local result = Policy.inspect({ "base_a", "special", "base_b" }, {
            default = { texture_id = "generic", texture_size = { 624, 66 } },
            special = { texture_id = "special_art", texture_size = { 630, 73 } },
        })
        H.equal(result.career_count, 3)
        H.equal(result.dedicated_count, 1)
        H.equal(result.fallback_count, 2)
        H.equal(table.concat(result.dedicated, ","), "special")
        H.equal(table.concat(result.fallback, ","), "base_a,base_b")
        H.equal(table.concat(result.texture_ids, ","), "special_art")
    end)

    H.test("GUT career holder census rejects malformed explicit art", function()
        local result = Policy.inspect({ "bad", "fallback" }, {
            default = { texture_id = "generic", texture_size = { 624, 66 } },
            bad = { texture_id = "", texture_size = { 0, 66 } },
        })
        H.equal(result.malformed_count, 1)
        H.equal(result.dedicated_count, 0)
        H.equal(result.fallback_count, 1)
        H.equal(result.missing_default, false)
    end)

    H.test("GUT career holder census fails closed without a usable default", function()
        local result = Policy.inspect({ "one" }, { default = {} })
        H.equal(result.missing_default, true)
        H.equal(result.fallback_count, 1)
    end)
end
