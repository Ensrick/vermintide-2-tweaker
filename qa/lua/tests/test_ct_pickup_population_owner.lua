-- Guards the #1159 pickup-population owner extraction: everything ct does at
-- PickupSystem.populate_pickups - the per-mission BUDGET, the two pool mutations
-- the spread pass samples from, the #58/#156 spawn census, the entry probes, and
-- the #132 extensions_ready chest ground truth - moved out of the ct_dev entry
-- into _ct_pickup_population_owner.lua.
--
-- ONE contiguous chunk moved (old entry lines 3566-4065) and the installer sits
-- at the exact line it occupied, so there is no load-order deviation to argue
-- about: the ordering assertion here is simply that the install site is still
-- between the round-end hook above it and the tome/grimoire substitution below.
--
-- This cluster failed three earlier extraction attempts on THREE forward-declared
-- entry locals that are assigned BELOW the install site. Two of them survive here
-- as late-binding ctx wrappers and the third was never a real crossing (it is
-- reached as mod._ct_book_spawner_census, off `mod`, at call time). Almost
-- everything below is executable rather than textual - the module is loaded for
-- real and installed against a recording stub - so a by-value bind, a lost
-- restore, a census that stops counting, or a career-counter reset that mutates
-- instead of rebinding fails here instead of in a Chaos Wastes mission.
return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_pickup_population_owner.lua"

local function read(name)
        if tostring(name):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    -- Comment-stripped view, for the "this vocabulary must not appear in CODE"
    -- assertions. The owner's header names its neighbours on purpose - that is
    -- the point of the header - so those checks have to run against code only or
    -- they would forbid documenting the boundary they exist to protect.
    local function code_only(source)
        local out, i, n = {}, 1, #source
        while i <= n do
            local c = source:sub(i, i)
            if source:sub(i, i + 3) == "--[[" then
                local close = source:find("]]", i + 4, true)
                i = close and (close + 2) or (n + 1)
            elseif source:sub(i, i + 1) == "--" then
                local nl = source:find("\n", i, true)
                i = nl or (n + 1)
            elseif c == '"' or c == "'" then
                local quote = c
                out[#out + 1] = c
                i = i + 1
                while i <= n do
                    local ch = source:sub(i, i)
                    out[#out + 1] = ch
                    if ch == "\\" then
                        out[#out + 1] = source:sub(i + 1, i + 1)
                        i = i + 2
                    elseif ch == quote or ch == "\n" then
                        i = i + 1
                        break
                    else
                        i = i + 1
                    end
                end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_pickup_population_owner.lua")
    local owner_code = code_only(owner)

    -- ------------------------------------------------------------------
    -- Executable fixture. The module registers two callbacks at load time and
    -- touches nothing else, so nothing here reaches the engine.
    -- ------------------------------------------------------------------
    local function fixture(overrides)
        overrides = overrides or {}
        local hooks, order, dofiles, logs = {}, {}, {}, {}
        local mod = {}

        function mod:hook(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate hook " .. key)
            hooks[key] = callback
            order[#order + 1] = "hook:" .. key
        end

        function mod:hook_safe(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            H.equal(hooks[key], nil, "duplicate safe hook " .. key)
            hooks[key] = callback
            order[#order + 1] = "safe:" .. key
        end

        function mod:dofile(path)
            dofiles[#dofiles + 1] = path
            error("the pickup-population owner must not load any module: " .. tostring(path))
        end

        function mod:info(fmt) logs[#logs + 1] = { "info", fmt } end
        function mod:warning(fmt) logs[#logs + 1] = { "warning", fmt } end

        local ctx = {
            effective_setting = function() return nil end,
            dump_pickup_system_state = function() end,
            dump_pickup_spawners_verbose = function() end,
            set_career_exclusive_denial_counts = function() end,
            set_career_exclusive_logged_this_run = function() end,
        }
        for key, value in pairs(overrides) do
            if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
        end

        local installer = assert(loadfile(module_path))()
        local returned = installer(mod, ctx)
        return mod, hooks, order, dofiles, logs, returned
    end

    -- Engine globals + VT2's table extensions, swapped in for the duration of a
    -- test and always restored, so the suite stays order-independent.
    local function with_globals(globals, body)
        local names = { "LevelHelper", "Managers", "Pickups", "printf" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
        local saved_clear, saved_clone = table.clear, table.clone

        _G.LevelHelper = { current_level_settings = function() return nil end }
        _G.Managers = {}
        _G.Pickups = {}
        _G.printf = function() end
        table.clear = function(t) for k in pairs(t) do t[k] = nil end end
        table.clone = function(t)
            local copy = {}
            for k, v in pairs(t) do copy[k] = v end
            return copy
        end

        for name, value in pairs(globals) do _G[name] = value end
        local ok, err = pcall(body)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        table.clear, table.clone = saved_clear, saved_clone
        if not ok then error(err, 0) end
    end

    -- A LevelHelper whose current_level_settings returns one shared table, so a
    -- test can inspect the SAME pickup_settings the hook mutated.
    local function level_helper(settings)
        return { current_level_settings = function() return settings end }
    end

    local function normal_level(cursed, altars, ammo)
        return {
            level_id = "dlc_castle",
            mechanism = "deus",
            pickup_settings = {
                hardest = {
                    primary = {
                        deus_weapon_chest = altars or 5,
                        deus_cursed_chest = cursed or 1,
                        ammo = ammo or 4,
                    },
                },
            },
        }
    end

    local function pickup_system()
        return {
            is_server = true,
            primary_pickup_spawners = { {}, {} },
            secondary_pickup_spawners = { {} },
            guaranteed_pickup_spawners = { {}, {}, {} },
        }
    end

    -- Drives the populate hook with a recording vanilla body. `inspect` runs
    -- while vanilla is "inside" the call, i.e. while the budget is patched.
    local function run_populate(hooks, self, inspect)
        local calls = 0
        local inner = function()
            calls = calls + 1
            if inspect then inspect() end
        end
        hooks["PickupSystem.populate_pickups"](inner, self)
        return calls
    end

    -- Count settings default to the -1 "Default" sentinel; the one BOOLEAN
    -- setting the hook reads defaults to false. Getting that wrong matters: -1 is
    -- truthy in Lua, so a boolean defaulting to -1 would silently keep the hook
    -- off its early-bail path and make the pass-through tests vacuous.
    local BOOLEAN_SETTINGS = { enable_campaign_potions = true }
    local function settings_reader(values)
        return function(name)
            local v = values[name]
            if v ~= nil then return v end
            if BOOLEAN_SETTINGS[name] then return false end
            return -1
        end
    end

    -- ------------------------------------------------------------------
    -- Module shape
    -- ------------------------------------------------------------------
    H.test("pickup-population owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_population_owner"), 1)
    end)

    H.test("owner owns no command, no RPC and no regression check", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
    end)

    H.test("the install site kept the position the moved code occupied", function()
        local round_end_at = assert(entry:find(
            'mod:hook("DeusMechanism", "game_round_ended"', 1, true))
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_population_owner", 1, true))
        local grenade_at = assert(entry:find(
            "Holy Hand Grenade spawn rate", 1, true))
        H.truthy(round_end_at < install_at,
            "the round-end hook must still register before the owner")
        H.truthy(install_at < grenade_at,
            "the owner must still install before the Holy Hand Grenade section")
        -- And still ABOVE the point where the entry's two dump slots are FILLED,
        -- which is the whole reason those two cross as wrappers rather than by
        -- value. v0.7.333-dev (#1159) moved the bodies themselves into
        -- _ct_level_load_owner.lua; the entry now assigns its forward-declared
        -- slots from that owner's exports, at the same place in the file the
        -- definitions used to sit. The premise is unchanged - the slots are still
        -- nil while this installer runs - so the assertion just follows the code.
        local dump_fill_at = assert(entry:find(
            "_dump_pickup_system_state     = _ct_level_load_owner.dump_pickup_system_state",
            1, true))
        H.truthy(install_at < dump_fill_at,
            "the dump slots must still be FILLED below the install site (the late-binding premise)")
    end)

    -- ------------------------------------------------------------------
    -- Hook cardinality and exclusivity
    -- ------------------------------------------------------------------
    H.test("owner registers exactly its two hooks, with the original verbs and order", function()
        local _, hooks, order, dofiles = fixture()
        H.deep_equal(order, {
            "safe:DeusCursedChestExtension.extensions_ready",
            "hook:PickupSystem.populate_pickups",
        })
        H.deep_equal(dofiles, {})
        H.truthy(hooks["DeusCursedChestExtension.extensions_ready"])
        H.truthy(hooks["PickupSystem.populate_pickups"])
    end)

    H.test("the two hooks left the entry and live only in the owner", function()
        for _, needle in ipairs({
            'mod:hook_safe("DeusCursedChestExtension", "extensions_ready"',
            'mod:hook("PickupSystem", "populate_pickups"',
        }) do
            H.equal(count_plain(entry, needle), 0, "entry must not re-register " .. needle)
            H.equal(count_plain(owner, needle), 1, "owner must register " .. needle .. " once")
        end
    end)

    H.test("owner stays off every neighbouring pickup seam", function()
        -- VMF silently drops a second registration on a (Class, method) pair, so
        -- a hook here on a neighbour's method would ship one of the two features
        -- dead. _spawn_pickup / _spawn_guaranteed_pickup belong to
        -- _ct_pickup_spawn_owner; _can_spawn belongs to _ct_spawn_eligibility_owner.
        for _, needle in ipairs({ '"_spawn_pickup"', '"_spawn_guaranteed_pickup"', '"_can_spawn"' }) do
            H.equal(count_plain(owner, 'mod:hook("PickupSystem", ' .. needle), 0)
            H.equal(count_plain(owner, 'mod:hook_safe("PickupSystem", ' .. needle), 0)
        end
        H.equal(count_plain(owner, '"_set_state"'), 0,
            "the cursed-chest state machine belongs to _ct_chest_revive_owner")
        H.equal(count_plain(owner_code, "_get_coins_amount_and_type"), 0)
    end)

    H.test("owner is population only: no boon, no price, no curse", function()
        -- The pickup population pass is independent of the boon economy and must
        -- stay that way. Checked against comment-stripped code.
        -- `chest_power_up_count` is deliberately NOT on this list: it is one of
        -- the four ALTAR-type sliders that make up the altar budget, not a boon
        -- offer count.
        for _, needle in ipairs({
            "_ct_boon", "DeusShopView", "DeusCursedChestView",
            "shrine_boon_count", "chest_boon_count", "DeusPowerUp",
        }) do
            H.equal(count_plain(owner_code, needle), 0, "owner code must not mention " .. needle)
        end
        -- The stripper must actually be stripping, or every line above is vacuous.
        H.truthy(count_plain(owner, "cursed_chest_count") > 0, "code_only must keep real code")
    end)

    -- ------------------------------------------------------------------
    -- ctx contract - all five keys are load-time asserted
    -- ------------------------------------------------------------------
    H.test("install refuses a missing or malformed ctx at load time", function()
        local installer = assert(loadfile(module_path))()
        H.equal(pcall(installer, {}, nil), false, "nil ctx must assert")
        H.equal(pcall(installer, {}, "nope"), false, "non-table ctx must assert")
        for _, key in ipairs({
            "effective_setting", "dump_pickup_system_state", "dump_pickup_spawners_verbose",
            "set_career_exclusive_denial_counts", "set_career_exclusive_logged_this_run",
        }) do
            H.equal(pcall(function() return fixture({ [key] = "\0drop" }) end), false,
                "a dropped ctx." .. key .. " must assert")
        end
    end)

    -- ------------------------------------------------------------------
    -- The crossing that sank three earlier attempts
    -- ------------------------------------------------------------------
    H.test("both post-populate dumps are LATE bound, so a by-value regression fails", function()
        -- The entry assigns `function _dump_pickup_system_state(...)` BELOW the
        -- install site. A by-value ctx bind would freeze nil and both dumps would
        -- silently no-op forever - which is exactly the failure this owner exists
        -- to avoid. Here the wrapper targets are assigned only AFTER install.
        local state_target, verbose_target
        local seen = {}
        local _, hooks = fixture({
            dump_pickup_system_state = function(...) return state_target(...) end,
            dump_pickup_spawners_verbose = function(...) return verbose_target(...) end,
            effective_setting = settings_reader({ cursed_chest_count = 2 }),
        })
        state_target = function(prefix) seen[#seen + 1] = "state:" .. tostring(prefix) end
        verbose_target = function(prefix) seen[#seen + 1] = "verbose:" .. tostring(prefix) end

        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            run_populate(hooks, pickup_system())
        end)
        H.deep_equal(seen, {
            "state:[ct_dbg][pickups:post_populate]",
            "verbose:[ct_dbg][pickup_units:post_populate]",
        })
    end)

    H.test("a still-nil dump slot costs the dump, never the mission", function()
        -- Both dump calls are pcall'd in the moved code. If a wrapper's target is
        -- somehow still nil, vanilla populate must run to completion regardless
        -- (PROJECT_STANDARDS 4.2 guard-is-not-bail).
        local _, hooks = fixture({
            dump_pickup_system_state = function(...) return (nil)(...) end,
            dump_pickup_spawners_verbose = function(...) return (nil)(...) end,
            effective_setting = settings_reader({ cursed_chest_count = 2 }),
        })
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            H.equal(run_populate(hooks, pickup_system()), 1)
        end)
    end)

    H.test("effective_setting is late-bound too", function()
        local target
        local _, hooks = fixture({
            effective_setting = function(...) return target(...) end,
        })
        local asked = {}
        target = function(name) asked[name] = (asked[name] or 0) + 1; return -1 end
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            run_populate(hooks, pickup_system())
        end)
        H.truthy(asked.cursed_chest_count and asked.cursed_chest_count > 0)
        H.truthy(asked.enable_campaign_potions and asked.enable_campaign_potions > 0)
    end)

    -- ------------------------------------------------------------------
    -- The two WRITE crossings (the documented deviation)
    -- ------------------------------------------------------------------
    H.test("the career-exclusive reset REBINDS to fresh tables, it does not clear in place", function()
        -- The entry hands _ct_spawn_eligibility_owner getter closures precisely
        -- because this reset reassigns. Mutating in place would keep table
        -- identity, which is a real semantic difference for any direct holder -
        -- so the setter path is asserted by identity, not by emptiness.
        local denial, logged = { stale = 3 }, { stale = true }
        local set_denial = function(value) denial = value end
        local set_logged = function(value) logged = value end
        local first_denial, first_logged = denial, logged

        local _, hooks = fixture({
            set_career_exclusive_denial_counts = set_denial,
            set_career_exclusive_logged_this_run = set_logged,
            effective_setting = settings_reader({}),
        })
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            run_populate(hooks, pickup_system())
            H.truthy(denial ~= first_denial, "denial counts must be a NEW table after populate")
            H.truthy(logged ~= first_logged, "the once-per-run log gate must be a NEW table")
            H.equal(next(denial), nil, "the new denial table starts empty")
            H.equal(next(logged), nil, "the new log-gate table starts empty")

            local second_denial = denial
            run_populate(hooks, pickup_system())
            H.truthy(denial ~= second_denial, "every populate rebinds again (per-mission reset)")
        end)
    end)

    H.test("the reset happens before any early bail, so a vanilla level still resets", function()
        -- A fully-default, non-injected level takes the early `return func(...)`
        -- path. The per-run counters must STILL have been reset by then, because
        -- populate_pickups is the mod's only per-mission run-boot seam.
        local denial = { stale = 1 }
        local mod, hooks = fixture({
            set_career_exclusive_denial_counts = function(value) denial = value end,
            effective_setting = settings_reader({}),
        })
        local rebuilt = 0
        mod._ct_rebuild_coin_reserved_set = function() rebuilt = rebuilt + 1 end
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            H.equal(run_populate(hooks, pickup_system()), 1)
        end)
        H.equal(next(denial), nil, "counters reset even on the early-bail path")
        H.equal(rebuilt, 0, "and the bail really was taken")
    end)

    H.test("the two deviating lines exist exactly once each, and nowhere else", function()
        -- Once in CODE. The header quotes both lines verbatim in its DEVIATIONS
        -- block, which is the point of that block, so the code count runs against
        -- the comment-stripped source and the header presence is asserted too.
        H.equal(count_plain(owner_code, "_set_career_exclusive_denial_counts({})"), 1)
        H.equal(count_plain(owner_code, "_set_career_exclusive_logged_this_run({})"), 1)
        H.equal(count_plain(owner, "_set_career_exclusive_denial_counts({})"), 2,
            "the header must keep documenting the deviation it introduced")
        H.equal(count_plain(owner, "_set_career_exclusive_logged_this_run({})"), 2)
        -- The old in-entry form must be gone: a survivor would reset a local the
        -- owner no longer touches and split the state silently.
        -- Indent-anchored, or the entry's own `local ... = {}` declarations (which
        -- must survive) would match and make these two vacuous.
        H.equal(count_plain(entry, "\n    _career_exclusive_denial_counts = {}"), 0)
        H.equal(count_plain(entry, "\n    _career_exclusive_logged_this_run = {}"), 0)
        -- ...but the entry must still DECLARE them and still hand the eligibility
        -- owner its call-time getters, or the setters would write into a void.
        H.equal(count_plain(entry, "local _career_exclusive_denial_counts"), 1)
        H.equal(count_plain(entry, "local _career_exclusive_logged_this_run"), 1)
        H.equal(count_plain(entry,
            "get_denial_counts           = function() return _career_exclusive_denial_counts end"), 1)
        H.equal(count_plain(entry,
            "get_logged_this_run         = function() return _career_exclusive_logged_this_run end"), 1)
    end)

    -- ------------------------------------------------------------------
    -- The BUDGET: patched for the duration of vanilla's call, then restored
    -- ------------------------------------------------------------------
    H.test("configured counts are patched in place and fully restored afterwards", function()
        local _, hooks = fixture({
            effective_setting = settings_reader({
                cursed_chest_count = 3,
                chest_upgrade_count = 2,
                chest_swap_melee_count = 1,
                chest_swap_ranged_count = 1,
                chest_power_up_count = 2,
            }),
        })
        local level = normal_level(1, 5, 4)
        local primary = level.pickup_settings.hardest.primary
        with_globals({ LevelHelper = level_helper(level) }, function()
            local inside = {}
            run_populate(hooks, pickup_system(), function()
                inside.cursed = primary.deus_cursed_chest
                inside.altars = primary.deus_weapon_chest
            end)
            H.equal(inside.cursed, 3, "the cursed-chest cap must be live during vanilla's pass")
            H.equal(inside.altars, 6, "altar total is the sum of the four altar sliders")
        end)
        H.equal(primary.deus_cursed_chest, 1, "vanilla value restored after the pass")
        H.equal(primary.deus_weapon_chest, 5, "vanilla value restored after the pass")
        H.equal(primary.ammo, 4, "an untouched field is never written at all")
    end)

    H.test("the -1 sentinel means Default and mutates nothing; 0 means literally zero", function()
        local level = normal_level(1, 5, 4)
        local primary = level.pickup_settings.hardest.primary
        local _, hooks = fixture({ effective_setting = settings_reader({}) })
        with_globals({ LevelHelper = level_helper(level) }, function()
            run_populate(hooks, pickup_system(), function()
                H.equal(primary.deus_cursed_chest, 1, "Default must leave vanilla's own count alone")
            end)
        end)

        local _, zero_hooks = fixture({
            effective_setting = settings_reader({ cursed_chest_count = 0 }),
        })
        with_globals({ LevelHelper = level_helper(level) }, function()
            run_populate(zero_hooks, pickup_system(), function()
                H.equal(primary.deus_cursed_chest, 0, "an explicit 0 IS an override")
            end)
        end)
        H.equal(primary.deus_cursed_chest, 1)
    end)

    H.test("arena levels are detected by the missing chest key and take the ammo path", function()
        local level = {
            level_id = "dlc_arena",
            pickup_settings = { hardest = { primary = { ammo = 2 } } },
        }
        local primary = level.pickup_settings.hardest.primary
        local _, hooks = fixture({
            effective_setting = settings_reader({ arena_ammo_count = 7, cursed_chest_count = 3 }),
        })
        with_globals({ LevelHelper = level_helper(level) }, function()
            run_populate(hooks, pickup_system(), function()
                H.equal(primary.ammo, 7)
                H.equal(primary.deus_cursed_chest, nil,
                    "an arena entry must never grow a chest key it did not have")
            end)
        end)
        H.equal(primary.ammo, 2, "restored")
    end)

    H.test("a fully default, non-injected level is a pure pass-through", function()
        local level = normal_level(1, 5, 4)
        local mod, hooks = fixture({ effective_setting = settings_reader({}) })
        local rebuilt = 0
        mod._ct_rebuild_coin_reserved_set = function() rebuilt = rebuilt + 1 end
        with_globals({ LevelHelper = level_helper(level) }, function()
            H.equal(run_populate(hooks, pickup_system()), 1)
        end)
        -- The coin reservation rebuild sits BELOW the early bail, so it is the
        -- cheap observable proof the bail was taken.
        H.equal(rebuilt, 0, "the early bail must skip the reservation rebuild")
    end)

    -- ------------------------------------------------------------------
    -- The POOLS the spread pass samples from
    -- ------------------------------------------------------------------
    H.test("campaign potions are injected, the whole group renormalizes to 1.0, then unwinds", function()
        local pickups = {
            potions = {
                damage_boost_potion = { spawn_weighting = 0.33 },
                speed_boost_potion = { spawn_weighting = 0.33 },
                cooldown_reduction_potion = { spawn_weighting = 0.34 },
            },
            deus_potions = {
                deus_potion_a = { spawn_weighting = 0.5 },
                deus_potion_b = { spawn_weighting = 0.5 },
            },
        }
        local _, hooks = fixture({
            effective_setting = settings_reader({ enable_campaign_potions = true }),
        })
        with_globals({ LevelHelper = level_helper(normal_level()), Pickups = pickups }, function()
            run_populate(hooks, pickup_system(), function()
                local total, n = 0, 0
                for _, s in pairs(pickups.deus_potions) do total = total + s.spawn_weighting; n = n + 1 end
                H.equal(n, 5, "three campaign clones join the two CW potions")
                H.truthy(math.abs(total - 1.0) < 1e-9,
                    "the sampler is unreachable past cumulative 1.0, so the group must sum to 1")
            end)
        end)
        H.equal(pickups.deus_potions.damage_boost_potion, nil, "clones are dropped after the pass")
        H.equal(pickups.deus_potions.deus_potion_a.spawn_weighting, 0.5, "CW weights restored")
        H.equal(pickups.deus_potions.deus_potion_b.spawn_weighting, 0.5, "CW weights restored")
        H.equal(pickups.potions.damage_boost_potion.spawn_weighting, 0.33,
            "the campaign source table is never renormalized")
    end)

    H.test("potions OFF scrubs any clone a previous errored pass leaked", function()
        local pickups = {
            potions = {},
            deus_potions = {
                deus_potion_a = { spawn_weighting = 1.0 },
                damage_boost_potion = { spawn_weighting = 0.33 },
                speed_boost_potion = { spawn_weighting = 0.33 },
                cooldown_reduction_potion = { spawn_weighting = 0.34 },
            },
        }
        local _, hooks = fixture({ effective_setting = settings_reader({ cursed_chest_count = 2 }) })
        with_globals({ LevelHelper = level_helper(normal_level()), Pickups = pickups }, function()
            run_populate(hooks, pickup_system())
        end)
        H.equal(pickups.deus_potions.damage_boost_potion, nil)
        H.equal(pickups.deus_potions.speed_boost_potion, nil)
        H.equal(pickups.deus_potions.cooldown_reduction_potion, nil)
        H.truthy(pickups.deus_potions.deus_potion_a, "a real CW potion is never scrubbed")
    end)

    H.test("#143 grenade redistribution preserves the pool SUM exactly, then restores", function()
        -- v0.7.143 crashed because it LOWERED the pool total below the sampler's
        -- [0,1) roll. Sum-preservation is what makes the current fix safe, so it
        -- is asserted numerically rather than trusted.
        local pickups = {
            grenades = {
                holy_hand_grenade = { spawn_weighting = 0.8 },
                frag_grenade = { spawn_weighting = 0.6 },
                fire_grenade = { spawn_weighting = 0.6 },
            },
        }
        local before = 0.8 + 0.6 + 0.6
        local mod, hooks = fixture({ effective_setting = settings_reader({}) })
        mod._ct_on_injected_adventure_level = function() return true end
        with_globals({ LevelHelper = level_helper(normal_level()), Pickups = pickups }, function()
            run_populate(hooks, pickup_system(), function()
                local total = 0
                for _, s in pairs(pickups.grenades) do total = total + s.spawn_weighting end
                H.truthy(math.abs(total - before) < 1e-9, "the pool sum must not move")
                H.truthy(math.abs(pickups.grenades.holy_hand_grenade.spawn_weighting - 0.4) < 1e-9,
                    "Morgrim's is halved")
                H.truthy(pickups.grenades.frag_grenade.spawn_weighting > 0.6,
                    "the freed half goes to the others proportionally")
            end)
        end)
        H.equal(pickups.grenades.holy_hand_grenade.spawn_weighting, 0.8, "restored for the next level")
        H.equal(pickups.grenades.frag_grenade.spawn_weighting, 0.6, "restored for the next level")
    end)

    H.test("a vanilla (non-injected) level never touches the grenade pool", function()
        local pickups = { grenades = { holy_hand_grenade = { spawn_weighting = 0.8 } } }
        local mod, hooks = fixture({ effective_setting = settings_reader({ cursed_chest_count = 2 }) })
        mod._ct_on_injected_adventure_level = function() return false end
        with_globals({ LevelHelper = level_helper(normal_level()), Pickups = pickups }, function()
            run_populate(hooks, pickup_system(), function()
                H.equal(pickups.grenades.holy_hand_grenade.spawn_weighting, 0.8)
            end)
        end)
    end)

    H.test("holy_hand as the only grenade is skipped, not shrunk", function()
        -- Halving with nowhere to move the freed weight would LOWER the total and
        -- reintroduce the v0.7.143 sampler crash. The guard is the fix.
        local pickups = { grenades = { holy_hand_grenade = { spawn_weighting = 0.8 } } }
        local mod, hooks = fixture({ effective_setting = settings_reader({}) })
        mod._ct_on_injected_adventure_level = function() return true end
        with_globals({ LevelHelper = level_helper(normal_level()), Pickups = pickups }, function()
            run_populate(hooks, pickup_system(), function()
                H.equal(pickups.grenades.holy_hand_grenade.spawn_weighting, 0.8)
            end)
        end)
    end)

    -- ------------------------------------------------------------------
    -- The coin-reservation rebuild seam (owned by the eligibility owner)
    -- ------------------------------------------------------------------
    H.test("the reservation set is rebuilt on the host and cleared off it", function()
        local mod, hooks = fixture({ effective_setting = settings_reader({ cursed_chest_count = 2 }) })
        local rebuilt, cleared = 0, 0
        mod._ct_rebuild_coin_reserved_set = function(lists)
            rebuilt = rebuilt + 1
            H.equal(#lists, 2, "primary + secondary spawner lists")
        end
        mod._ct_clear_coin_reserved_set = function() cleared = cleared + 1 end
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            run_populate(hooks, pickup_system())
            H.equal(rebuilt, 1)
            H.equal(cleared, 0)

            local client = pickup_system()
            client.is_server = false
            run_populate(hooks, client)
            H.equal(rebuilt, 1, "a client must never build a reservation set")
            H.equal(cleared, 1)
        end)
    end)

    -- ------------------------------------------------------------------
    -- The census
    -- ------------------------------------------------------------------
    H.test("the census publishes its four mod seams plus the consolidation marker", function()
        local mod = fixture()
        for _, field in ipairs({
            "_ct_tally_reset", "_ct_tally_count", "_ct_tally_tick", "_ct_tally_cursed_count",
        }) do
            H.equal(type(mod[field]), "function", field .. " must be published on mod")
        end
        H.equal(mod._CT_SPAWN_TALLY_MARKER, "CT_SPAWN_TALLY_v1_unconditional_census")
    end)

    H.test("the census counts armed spawns only, and emits once after the 8s delay", function()
        local emitted = {}
        local mod = fixture()
        with_globals({ printf = function(fmt, ...) emitted[#emitted + 1] = string.format(fmt, ...) end },
            function()
                mod._ct_tally_count("deus_cursed_chest", {})
                H.equal(mod._ct_tally_cursed_count(), 0, "an unarmed census counts nothing")

                mod._ct_tally_reset("dlc_castle", true, "magnus", "hardest")
                mod._ct_tally_count("deus_cursed_chest", {})
                mod._ct_tally_count("deus_cursed_chest", {})
                mod._ct_tally_count("deus_soft_currency", {})
                mod._ct_tally_count("deus_soft_currency", nil)
                H.equal(mod._ct_tally_cursed_count(), 2,
                    "a nil spawned unit is a failed spawn and must not be counted")

                mod._ct_tally_tick(4.0)
                H.equal(#emitted, 0, "nothing before the delay elapses")
                mod._ct_tally_tick(4.0)
                H.equal(#emitted, 1, "exactly one summary line")
                mod._ct_tally_tick(100.0)
                H.equal(#emitted, 1, "and it disarms, so it never repeats")
            end)
        H.truthy(emitted[1]:find("[ct-spawn-tally]", 1, true))
        H.truthy(emitted[1]:find("level=dlc_castle", 1, true))
        H.truthy(emitted[1]:find("injected=true", 1, true))
        H.truthy(emitted[1]:find("total=3", 1, true))
        H.truthy(emitted[1]:find("ZERO=false", 1, true))
        H.truthy(emitted[1]:find("cursed=2", 1, true))
    end)

    H.test("an empty mission emits the unambiguous ZERO=true signal", function()
        local emitted = {}
        local mod = fixture()
        with_globals({ printf = function(fmt, ...) emitted[#emitted + 1] = string.format(fmt, ...) end },
            function()
                mod._ct_tally_reset("magnus", true, "magnus", "hardest")
                mod._ct_tally_tick(9.0)
            end)
        H.equal(#emitted, 1)
        H.truthy(emitted[1]:find("total=0 ZERO=true", 1, true),
            "total=0 on an injected level is the whole point of the census")
    end)

    H.test("a reset re-arms and clears the previous mission's counts", function()
        local mod = fixture()
        with_globals({}, function()
            mod._ct_tally_reset("a", false, nil, "hardest")
            mod._ct_tally_count("deus_cursed_chest", {})
            H.equal(mod._ct_tally_cursed_count(), 1)
            mod._ct_tally_reset("b", false, nil, "hardest")
            H.equal(mod._ct_tally_cursed_count(), 0)
        end)
    end)

    H.test("populate arms the census with the level's identity", function()
        local mod, hooks = fixture({ effective_setting = settings_reader({}) })
        local armed
        mod._ct_on_injected_adventure_level = function() return true end
        mod._ct_adventure_base_from_level_key = function() return "magnus" end
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            local real_reset = mod._ct_tally_reset
            mod._ct_tally_reset = function(level_key, injected, adv_base, difficulty)
                armed = { level_key, injected, adv_base, difficulty }
                return real_reset(level_key, injected, adv_base, difficulty)
            end
            run_populate(hooks, pickup_system())
        end)
        H.deep_equal(armed, { "dlc_castle", true, "magnus", nil })
    end)

    -- ------------------------------------------------------------------
    -- The #132 ground truth
    -- ------------------------------------------------------------------
    H.test("extensions_ready feeds the #132 ledger with cap, census, unit and role", function()
        local mod, hooks = fixture()
        local seen
        mod._ct_chest132 = {
            chest_appeared = function(level_id, cap, census, is_server, unit)
                seen = { level_id, cap, census, is_server, unit }
            end,
        }
        mod._ct_effective_setting = function() return 3 end
        local unit = {}
        with_globals({
            LevelHelper = level_helper(normal_level()),
            Managers = { player = { is_server = true } },
        }, function()
            -- _ct_tally_reset uses VT2's table.clear extension, so it has to run
            -- inside the stubbed-globals window.
            mod._ct_tally_reset("dlc_castle", false, nil, "hardest")
            mod._ct_tally_count("deus_cursed_chest", {})
            hooks["DeusCursedChestExtension.extensions_ready"](mod, {}, unit)
        end)
        H.deep_equal(seen, { "dlc_castle", 3, 1, true, unit })
    end)

    H.test("the Default cap resolves to 1 for the #132 comparison", function()
        local mod, hooks = fixture()
        local cap
        mod._ct_chest132 = { chest_appeared = function(_, c) cap = c end }
        mod._ct_effective_setting = function() return -1 end
        with_globals({
            LevelHelper = level_helper(normal_level()),
            Managers = { player = { is_server = false } },
        }, function()
            hooks["DeusCursedChestExtension.extensions_ready"](mod, {}, {})
        end)
        H.equal(cap, 1, "the -1 Default sentinel is vanilla's single chest")
    end)

    H.test("extensions_ready is inert when the #132 module has not loaded", function()
        local mod, hooks = fixture()
        H.equal(mod._ct_chest132, nil)
        with_globals({}, function()
            hooks["DeusCursedChestExtension.extensions_ready"](mod, {}, {})
        end)
    end)

    -- ------------------------------------------------------------------
    -- The per-level counters shared with _ct_pickup_spawn_owner
    -- ------------------------------------------------------------------
    H.test("the owner resets the two shared counters but never increments them", function()
        -- _ct_pickup_spawn_owner owns every increment; this owner owns the single
        -- per-mission reset, consolidated into this one hook so VMF never sees a
        -- second registration on populate_pickups.
        local mod, hooks = fixture({ effective_setting = settings_reader({}) })
        mod._ct_chest_conversions_this_level = 7
        mod._ct_belakor_altar_spawned_this_level = true
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            run_populate(hooks, pickup_system())
        end)
        H.equal(mod._ct_chest_conversions_this_level, 0)
        H.equal(mod._ct_belakor_altar_spawned_this_level, false)
        H.equal(count_plain(owner_code, "mod._ct_chest_conversions_this_level = mod._ct_chest_conversions_this_level"), 0,
            "increments belong to _ct_pickup_spawn_owner")
    end)

    H.test("the book-spawner census is dispatched off mod at call time, only on injected levels", function()
        local mod, hooks = fixture({ effective_setting = settings_reader({}) })
        local calls = 0
        mod._ct_book_spawner_census = function() calls = calls + 1 end
        with_globals({ LevelHelper = level_helper(normal_level()) }, function()
            mod._ct_adventure_base_from_level_key = nil
            run_populate(hooks, pickup_system())
            H.equal(calls, 0, "no injected-catalog answer means no census")

            mod._ct_adventure_base_from_level_key = function() return nil end
            run_populate(hooks, pickup_system())
            H.equal(calls, 0, "a vanilla CW level is not an injected catalog level")

            mod._ct_adventure_base_from_level_key = function() return "magnus" end
            run_populate(hooks, pickup_system())
            H.equal(calls, 1)
        end)
    end)

    H.test("a missing LevelHelper degrades to vanilla instead of throwing", function()
        local _, hooks = fixture({ effective_setting = settings_reader({ cursed_chest_count = 3 }) })
        with_globals({ LevelHelper = false }, function()
            H.equal(run_populate(hooks, pickup_system()), 1)
        end)
    end)
end
