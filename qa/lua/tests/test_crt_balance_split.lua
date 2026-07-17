return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CRT balance hook extraction preserves one load and four owners", function()
        local root = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
        local balance = read(root .. "career_tweaker_balance.lua")
        local hooks = read(root .. "_career_tweaker_balance_hooks.lua")

        H.truthy(balance:find(
            'mod:dofile("scripts/mods/career_tweaker/_career_tweaker_balance_hooks")',
            1, true))
        H.equal(balance:find('mod:hook("TalentExtension", "has_talent_perk"', 1, true), nil)
        H.equal(balance:find('mod:hook(_G, "Localize"', 1, true), nil)
        H.equal(balance:find('mod:hook("BuffSystem", "hot_join_sync"', 1, true), nil)

        H.truthy(hooks:find('mod:hook("TalentExtension", "has_talent_perk"', 1, true))
        H.truthy(hooks:find('mod:hook(ActionUtils, "get_critical_strike_chance"', 1, true))
        H.truthy(hooks:find('mod:hook(_G, "Localize"', 1, true))
        H.truthy(hooks:find('mod:hook("BuffSystem", "hot_join_sync"', 1, true))
        H.truthy(hooks:find("mod._crt_hellborgs_crit_hook_installed = true", 1, true))
    end)
end
