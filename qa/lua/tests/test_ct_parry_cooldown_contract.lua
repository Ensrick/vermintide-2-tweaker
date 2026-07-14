return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    H.test("CT #342 exports and invokes the deferred parry strip explicitly", function()
        local combat = read(base .. "_ct_combat_hooks.lua")
        local main = read(base .. "chaos_wastes_tweaker_dev.lua")

        H.truthy(combat:find("mod._ct128_strip_parry_cooldowns = function()", 1, true))
        H.truthy(main:find("local strip = mod._ct128_strip_parry_cooldowns", 1, true))
        H.equal(main:find("pcall(_ct128_strip_parry_cooldowns)", 1, true), nil)
        H.truthy(main:find("[ct:342] parry-cooldown strip failed", 1, true))
    end)
end
