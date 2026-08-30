-- Issue #1156: `dormant_boons_NOT_registered` and `dormant_boons_NOT_in_pool` were lying in two
-- independent ways (BUG_CLASSES 85 sub-pattern (a), stale expectation).
--
--   1. Both iterated a disabled list that still carried `ct_kill_heal`, which #406 deliberately
--      RE-ENABLED in v0.7.240-dev. `test_ct_boon_catalog` asserts that boon's PRESENCE, so the
--      two suites contradicted each other and the checks failed permanently.
--   2. `dormant_boons_NOT_registered` asserted the 9 vanilla dormants were ABSENT from
--      `NetworkLookup.deus_power_up_templates`. Vanilla builds that lookup wholesale from
--      `DeusPowerUpTemplates` (morris_common_settings.lua:823-829), where all 9 are top-level
--      keys, and ct never removes them -- so the assertion could not pass on any install.
--
-- The repair points both checks at surfaces ct actually owns: its own injection registry
-- (reached through `mod._ct_is_modded_power_up`), the `power_up_*` BuffTemplates entries the
-- injection path writes, and the pickable pool. These cases prove the repair three ways: the
-- checks pass in a world where vanilla has populated its lookup exactly as it really does; they
-- still FAIL on a genuine ct-side re-enable; and re-planting `ct_kill_heal` in the disabled list
-- brings the permanent failure straight back.
return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local ct_root = repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(ct_root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local entry = read("chaos_wastes_tweaker_dev.lua")

    -- Ground truth is the list the entry ACTUALLY ships, parsed out of it -- not a copy kept
    -- here, which would drift and quietly stop testing the shipped constant.
    local function authored_disabled_names()
        local block = entry:match("local CT_DISABLED_DORMANT_BOON_NAMES = {(.-)\n}")
        H.truthy(block, "CT_DISABLED_DORMANT_BOON_NAMES is no longer declared in the ct entry")
        local names = {}
        for name in block:gmatch('"([^"]+)"') do names[#names + 1] = name end
        H.truthy(#names > 0)
        return names
    end

    local function authored_disabled_rarities()
        local block = entry:match("local CT_DISABLED_DORMANT_RARITIES = {(.-)\n}")
        H.truthy(block, "CT_DISABLED_DORMANT_RARITIES is no longer declared in the ct entry")
        local rarities = {}
        for name, rarity in block:gmatch('([%w_]+)%s*=%s*"([^"]+)"') do rarities[name] = rarity end
        return rarities
    end

    -- Load the production check module and hand back its registrations.
    local function load_checks(overrides)
        overrides = overrides or {}
        local registrations = {}
        local mod = {
            get = function() return true end,
            localize = function(_, key) return key end,
            echo = function() end, info = function() end,
            warning = function() end, debug = function() end,
        }
        mod.dofile = function(_, path)
            if path == "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression_resource_safety" then
                return assert(loadfile(ct_root .. "_ct_regression_resource_safety.lua"))()
            end
            error("unexpected CT regression dofile: " .. tostring(path))
        end
        mod._ct_rt_register = function(name, fn) registrations[name] = fn end
        if overrides.accessor ~= false then
            local injected = overrides.injected or {}
            mod._ct_is_modded_power_up = function(name) return injected[name] == true end
        end

        local names = overrides.names or authored_disabled_names()
        local rarities = overrides.rarities or authored_disabled_rarities()

        local saved = {}
        local function set_global(key, value)
            saved[key] = { _G[key] }
            _G[key] = value
        end

        -- Vanilla reality: every disabled dormant IS in the lookup, on every install. The
        -- repaired checks must pass anyway -- that is the whole point of the repair.
        local lookup = {}
        if overrides.vanilla_lookup ~= false then
            for _, name in ipairs(names) do lookup[name] = true end
        end
        set_global("NetworkLookup", { deus_power_up_templates = lookup, buff_templates = {} })
        set_global("BuffTemplates", overrides.buff_templates ~= false
            and (overrides.buff_templates or {}) or nil)
        set_global("DeusPowerUpRarityPool", overrides.pool ~= false and (overrides.pool or {}) or nil)
        set_global("DeusPowerUps", overrides.power_ups ~= false and (overrides.power_ups or {}) or nil)
        set_global("printf", function() end)

        local factory = assert(loadfile(ct_root .. "_ct_regression.lua"))()
        local ok, err = pcall(factory, mod, {
            dbg = function() end,
            dbg_alert = function() end,
            mod_version = "0.7.320-dev",
            rpc_schema = 1,
            meta_ammo_max_stacks = 30,
            meta_ammo_cost_multiplier = function() return 1 end,
            clamp_network_bounded_max = function(v) return v end,
            dump_pickup_system_state = function() end,
            dump_pickup_spawners_verbose = function() end,
            disabled_dormant_boon_names = names,
            disabled_dormant_rarities = rarities,
            dormant_purge_verified = "CT_DORMANT_PURGE_VERIFIED_v0.7.100",
            adventure_incompatible_pack_mutators = {},
            starting_coins_mode_marker = "",
            variadic_arity_marker = "",
            open_chest_consolidated_marker = "",
            meta_ammo_hyperbolic_marker = "",
            cot_enemy_mult_marker = "",
            altar_reuse_hook_marker = "",
            career_exclusive_pickups_blocklist = {},
            mutex = {},
        })

        local function restore()
            for key, box in pairs(saved) do _G[key] = box[1] end
        end
        H.truthy(ok, "_ct_regression.lua failed to install: " .. tostring(err))
        return registrations, restore
    end

    local function verdict(name, overrides)
        local registrations, restore = load_checks(overrides)
        local check = registrations[name]
        H.equal(type(check), "function", name .. " is not registered by _ct_regression.lua")
        local ok, result = pcall(check)
        restore()
        H.truthy(ok, name .. " raised instead of returning a verdict: " .. tostring(result))
        return result
    end

    local NOT_REGISTERED = "dormant_boons_NOT_registered"
    local NOT_IN_POOL = "dormant_boons_NOT_in_pool"

    H.test("CT dormant disable list no longer contradicts the #406 kill-heal re-enable", function()
        for _, name in ipairs(authored_disabled_names()) do
            H.equal(name == "ct_kill_heal", false,
                "ct_kill_heal is back in CT_DISABLED_DORMANT_BOON_NAMES; #406 re-enabled it and "
                    .. "test_ct_boon_catalog asserts its presence")
        end
        H.equal(authored_disabled_rarities().ct_kill_heal, nil)
        -- The other half of the contradiction: the registration really is unconditional.
        local boons = read("_ct_meta_trait_boons.lua")
        H.truthy(boons:find('register_power_up_in_network_lookup("ct_kill_heal")', 1, true))
        H.truthy(boons:find('inject_dormant_boon("ct_kill_heal", "exotic")', 1, true))
    end)

    H.test("CT dormant checks pass while vanilla owns the lookup entries", function()
        -- This is the world every install is actually in: all 9 names present in
        -- NetworkLookup.deus_power_up_templates because vanilla put them there.
        H.equal(verdict(NOT_REGISTERED), nil)
        H.equal(verdict(NOT_IN_POOL), nil)
    end)

    H.test("CT dormant checks catch a re-enable through ct's own injection path", function()
        -- Registry half: the boon is back in _injected_dormants.
        local injected = verdict(NOT_REGISTERED, { injected = { squats = true } })
        H.equal(type(injected), "string")
        H.truthy(injected:find("squats", 1, true))
        H.truthy(injected:find("injection registry", 1, true))

        -- BuffTemplates half: the injection path wrote the power_up_* template.
        local rarity = authored_disabled_rarities().deus_larger_clip
        H.equal(rarity, "rare")
        local buffed = verdict(NOT_REGISTERED, {
            buff_templates = { ["power_up_deus_larger_clip_rare"] = {} },
        })
        H.equal(type(buffed), "string")
        H.truthy(buffed:find("power_up_deus_larger_clip_rare", 1, true))

        -- Pool half, both surfaces `_add_dormant_to_pool` writes.
        local pooled = verdict(NOT_IN_POOL, { pool = { rare = { { "squats", "always", {} } } } })
        H.equal(type(pooled), "string")
        H.truthy(pooled:find("DeusPowerUpRarityPool", 1, true))

        local offered = verdict(NOT_IN_POOL, { power_ups = { rare = { squats = {} } } })
        H.equal(type(offered), "string")
        H.truthy(offered:find("DeusPowerUps", 1, true))
    end)

    H.test("CT dormant registry check fails loudly when its accessor is unresolved", function()
        -- Rule 2: reading nil and reporting a verdict anyway is reporting on nothing. With the
        -- accessor gone the check must say so rather than agree that nothing is injected.
        local result = verdict(NOT_REGISTERED, { accessor = false })
        H.equal(type(result), "string")
        H.truthy(result:find("_ct_is_modded_power_up", 1, true))
        H.equal(result:sub(1, 5) == "skip:", false,
            "an unresolved accessor is a broken instrument, not a wrong context")
    end)

    H.test("CT dormant checks skip rather than fail when keep-only globals are absent", function()
        local registry = verdict(NOT_REGISTERED, { buff_templates = false })
        H.equal(registry:sub(1, 5), "skip:")
        local pool = verdict(NOT_IN_POOL, { pool = false })
        H.equal(pool:sub(1, 5), "skip:")
    end)

    H.test("CT re-planting ct_kill_heal in the disabled list reproduces the permanent failure", function()
        -- The stale expectation this change removed. In the real runtime ct_kill_heal is
        -- injected, buff-templated and pooled, so listing it as disabled fails both checks on
        -- every install -- which is exactly what the 2026-08-09 replay observed.
        local names = authored_disabled_names()
        names[#names + 1] = "ct_kill_heal"
        local rarities = authored_disabled_rarities()
        rarities.ct_kill_heal = "exotic"

        local registry = verdict(NOT_REGISTERED, {
            names = names,
            rarities = rarities,
            injected = { ct_kill_heal = true },
            buff_templates = { ["power_up_ct_kill_heal_exotic"] = {} },
        })
        H.equal(type(registry), "string")
        H.truthy(registry:find("ct_kill_heal", 1, true))

        local pool = verdict(NOT_IN_POOL, {
            names = names,
            rarities = rarities,
            pool = { exotic = { { "ct_kill_heal", "always", {} } } },
        })
        H.equal(type(pool), "string")
        H.truthy(pool:find("ct_kill_heal", 1, true))
    end)

    H.test("CT dormant registry check no longer asserts on the vanilla-owned lookup", function()
        -- Independence proof: the verdict must not move when the vanilla lookup does, because
        -- ct neither writes nor removes those entries. Same verdict populated and empty.
        H.equal(verdict(NOT_REGISTERED, { vanilla_lookup = true }), nil)
        H.equal(verdict(NOT_REGISTERED, { vanilla_lookup = false }), nil)
        local checks = read("_ct_regression.lua")
        local from = checks:find('_rt_register("' .. NOT_REGISTERED .. '", function()', 1, true)
        local to = checks:find("\nend)\n", from, true)
        local body = checks:sub(from, to)
        H.equal(body:find("deus_power_up_templates", 1, true), nil,
            "the repaired check reads the vanilla-populated lookup again; vanilla owns those "
                .. "entries and ct cannot remove them, so absence there is not assertable")
    end)
end
