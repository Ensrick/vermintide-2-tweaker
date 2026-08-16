return function(H, repo_root)
    local policy_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_personal_handicap_policy.lua"
    local Policy = assert(loadfile(policy_path))()
    local units_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_personal_handicap_units.lua"
    local UnitPolicy = assert(loadfile(units_path))()

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

    H.test("Enemy Tweaker host gate denies client handicaps unless allowed", function()
        -- Gate off (the default): any client-requested preset resolves to off.
        H.equal(Policy.effective_preset(false, false, "cataclysm"), "off")
        H.equal(Policy.effective_preset(false, false, "hardest"), "off")
        H.equal(Policy.effective_preset(false, nil, "cataclysm"), "off")
        -- Gate on: the sanitized client preset passes through.
        H.equal(Policy.effective_preset(false, true, "cataclysm"), "cataclysm")
        H.equal(Policy.effective_preset(false, true, "not_a_preset"), "off")
        -- The host's own preset is the host's own setting: never gated.
        H.equal(Policy.effective_preset(true, false, "cataclysm"), "cataclysm")
        H.equal(Policy.effective_preset(true, true, "hardest"), "hardest")
        H.equal(Policy.effective_preset(true, false, "garbage"), "off")
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
        H.truthy(runtime:find("issue640_personal_handicap_unit_lifetime", 1, true))
        H.equal(runtime:find("NetworkLookup", 1, true), nil)
        H.equal(runtime:find("BuffTemplates", 1, true), nil)
    end)

    H.test("Enemy Tweaker unit boundary rejects nil and deleted units", function()
        local live_player = { state = "live", kind = "player" }
        local live_enemy = { state = "live", kind = "enemy" }
        local deleted_enemy = { state = "deleted", kind = "enemy" }
        local owner_marker = {}
        local calls = { alive = 0, owner = 0, breed = 0 }
        local access = UnitPolicy.new({
            unit_alive = function(unit)
                calls.alive = calls.alive + 1
                return unit.state == "live"
            end,
            owner = function(unit)
                calls.owner = calls.owner + 1
                return unit.kind == "player" and owner_marker or nil
            end,
            breed = function(unit)
                calls.breed = calls.breed + 1
                return unit.kind == "enemy" and { race = "skaven" } or nil
            end,
            is_hostile_breed = function(breed)
                return breed ~= nil and breed.race == "skaven"
            end,
        })

        H.equal(access.owner(nil), nil)
        H.equal(access.is_hostile_ai(nil), false)
        H.equal(calls.alive, 0, "nil must not reach Unit.alive")
        H.equal(access.owner(live_player), owner_marker)
        H.equal(access.is_hostile_ai(live_enemy), true)

        local owner_before = calls.owner
        local breed_before = calls.breed
        H.equal(access.owner(deleted_enemy), nil)
        H.equal(access.is_hostile_ai(deleted_enemy), false)
        H.equal(calls.owner, owner_before, "deleted unit must not reach owner")
        H.equal(calls.breed, breed_before, "deleted unit must not reach Unit.get_data")
    end)

    H.test("Enemy Tweaker lingering Globadier source is lifetime safe", function()
        local area_proxy = { state = "live", breed = nil }
        local deleted_globadier = {
            state = "deleted",
            breed = { race = "skaven" },
        }
        local live_globadier = {
            state = "live",
            breed = { race = "skaven" },
        }
        local calls = { alive = 0, breed = 0 }
        local access = UnitPolicy.new({
            unit_alive = function(unit)
                calls.alive = calls.alive + 1
                return unit.state == "live"
            end,
            owner = function() return nil end,
            breed = function(unit)
                calls.breed = calls.breed + 1
                return unit.breed
            end,
            is_hostile_breed = function(breed)
                return breed ~= nil and breed.race == "skaven"
            end,
        })

        local alive_before_off = calls.alive
        H.equal(UnitPolicy.scale_if_hostile(40, 1, access, area_proxy,
            deleted_globadier, Policy.scale_damage), 40)
        H.equal(calls.alive, alive_before_off,
            "Auto/off must bypass attacker classification")

        local breed_before_deleted = calls.breed
        H.equal(UnitPolicy.scale_if_hostile(40, 1.25, access, area_proxy,
            deleted_globadier, Policy.scale_damage), 40)
        H.equal(calls.breed, breed_before_deleted + 1,
            "only the live area proxy may reach breed lookup")

        H.equal(UnitPolicy.scale_if_hostile(40, 1.25, access, area_proxy,
            live_globadier, Policy.scale_damage), 50)
    end)

    H.test("Enemy Tweaker personal handicap lives in a gated dedicated category", function()
        local data = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_data.lua")
        local loc = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_localization.lua")
        H.truthy(data:find('setting_id%s*=%s*"personal_handicap_group"'),
            "personal handicap category group missing from data file")
        H.truthy(data:find('setting_id%s*=%s*"personal_difficulty"'))
        H.truthy(data:find('default_value%s*=%s*"off"'))
        -- The host gate must exist and default OFF (hosts opt in).
        local gate = data:match('setting_id%s*=%s*"personal_handicap_allow".-default_value%s*=%s*(%a+)')
        H.equal(gate, "false", "personal_handicap_allow must default to false")
        -- Every new player-facing string has a loc row.
        for _, key in ipairs({
            "personal_handicap_group",
            "personal_handicap_allow",
            "personal_handicap_allow_tooltip",
            "personal_difficulty",
            "personal_difficulty_tooltip",
        }) do
            H.truthy(loc:find(key .. "%s*=%s*{"), "missing loc row: " .. key)
        end
    end)
end
