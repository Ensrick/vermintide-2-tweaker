return function(H, repo_root)
    local policy_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_personal_handicap_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("Enemy Tweaker personal handicap is inert at or below host difficulty", function()
        H.deep_equal({ Policy.factors("hardest", "off") }, { 1, 1, 0 })
        H.deep_equal({ Policy.factors("hardest", "harder") }, { 1, 1, 0 })
        H.deep_equal({ Policy.factors("hardest", "hardest") }, { 1, 1, 0 })
        H.deep_equal({ Policy.factors(nil, "cataclysm") }, { 1, 1, 0 })
    end)

    H.test("Enemy Tweaker personal handicap has bounded graduated factors", function()
        H.deep_equal({ Policy.factors("harder", "hardest") }, { 1.08, 0.95, 1 })
        H.deep_equal({ Policy.factors("harder", "cataclysm") }, { 1.25, 0.85, 2 })
        H.deep_equal({ Policy.factors("normal", "cataclysm_3") }, { 1.25, 0.85, 3 })
        H.equal(Policy.scale_damage(40, 1.25), 50)
        H.equal(Policy.scale_damage(40, 0.85), 34)
        H.equal(Policy.scale_damage(0, 1.25), 0)
    end)

    H.test("Enemy Tweaker personal handicap uses authenticated host authority", function()
        local runtime = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_personal_handicap.lua")
        local _, hooks = runtime:gsub('mod:hook%(DamageUtils, "apply_buffs_to_damage"', "")
        H.equal(hooks, 1)
        H.truthy(runtime:find("sender_peer_id", 1, true))
        H.truthy(runtime:find("requested_by_peer[sender_peer_id]", 1, true))
        H.truthy(runtime:find("schema ~= ET.rpc_schema", 1, true))
        H.truthy(runtime:find("Managers.player.is_server", 1, true))
        H.truthy(runtime:find("HostilePolicy.is_hostile_breed", 1, true))
        H.equal(runtime:find("NetworkLookup", 1, true), nil)
        H.equal(runtime:find("BuffTemplates", 1, true), nil)
    end)

    H.test("Enemy Tweaker personal handicap setting is explicit about bounded scope", function()
        local data = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_data.lua")
        local loc = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_localization.lua")
        H.truthy(data:find('setting_id%s*=%s*"personal_difficulty"'))
        H.truthy(data:find('default_value%s*=%s*"off"'))
        H.truthy(loc:find("host must run the same Enemy Tweaker version", 1, true))
        H.truthy(loc:find("does not change spawns", 1, true))
    end)
end
