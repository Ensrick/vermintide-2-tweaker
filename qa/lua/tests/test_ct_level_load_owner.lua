-- Guards the #1159 level-load owner extraction: everything ct does between "a
-- Chaos Wastes mission's level begins loading" and "the local player's mission
-- has started" - the two vanilla crash guards that only fire in that window, the
-- per-curse Light.set_color palette, and the census that reports what the load
-- produced - moved out of the ct_dev entry into _ct_level_load_owner.lua.
--
-- ONE contiguous chunk moved (old entry lines 3946-4539, MD5
-- e45bf3e32d6175ef2740fb899beb576b, zero deviations) and the installer sits at
-- the exact line it occupied, so there is no load-order deviation to argue about:
-- the ordering assertion here is that the install site is still between the
-- consolidated _G.Localize hook above it and the NetworkedFlowStateManager leak
-- fix below it.
--
-- The interesting crossings are the three census slots. They were entry
-- forward-declarations whose bodies - `function _name(...)`, deliberately WITHOUT
-- `local` - were assigned inside the moved region. The pattern is preserved, not
-- removed: the owner re-declares the slots at ITS chunk scope, so each definition
-- line stayed byte-identical, nothing leaks to _G, and the two `_dump_*` bodies
-- travel back through the exports table into the entry's own slots because two
-- consumers still read the entry local by name. Almost everything below is
-- executable rather than textual - the module is loaded for real and installed
-- against a recording stub - so a lost export, a hook that stopped stripping, a
-- palette that stopped being deterministic, or a slot that leaked to _G fails
-- here instead of in a Chaos Wastes mission.
return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_level_load_owner.lua"

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
    local owner = read("_ct_level_load_owner.lua")
    local owner_code = code_only(owner)

    -- ------------------------------------------------------------------
    -- Executable fixture. The module registers three hooks at load time, sets
    -- two marker globals and publishes one mod field; it touches nothing else,
    -- so nothing here reaches the engine.
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
            error("the level-load owner must not load any module: " .. tostring(path))
        end

        function mod:echo(line) logs[#logs + 1] = { "echo", line } end
        function mod:info(fmt) logs[#logs + 1] = { "info", fmt } end
        function mod:warning(fmt) logs[#logs + 1] = { "warning", fmt } end

        local dbg_lines = {}
        local ctx = {
            dbg = function(fmt, ...)
                dbg_lines[#dbg_lines + 1] = select("#", ...) > 0
                    and string.format(fmt, ...) or fmt
            end,
            on_injected_adventure_level = function() return false end,
            adventure_base_from_level_key = function() return nil end,
        }
        for key, value in pairs(overrides) do
            if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
        end

        local installer = assert(loadfile(module_path))()
        local exports = installer(mod, ctx)
        return {
            mod = mod, hooks = hooks, order = order, dofiles = dofiles,
            logs = logs, dbg = dbg_lines, exports = exports, ctx = ctx,
        }
    end

    -- Engine globals swapped in for the duration of a test and always restored,
    -- so the suite stays order-independent. The marker globals the module assigns
    -- are saved and restored here too, otherwise installing the module would leak
    -- them into every later suite in the same process.
    local function with_globals(globals, body)
        local names = {
            "LevelHelper", "LevelSettings", "Managers", "Level", "Light", "Unit",
            "Vector3", "printf",
            "CT_NO_ROAMERS_DEUS_FIX_MARKER", "CT_NO_ROAMERS_ARITY_FIX_MARKER",
        }
        local saved, had = {}, {}
        for _, name in ipairs(names) do
            saved[name] = rawget(_G, name)
            had[name] = rawget(_G, name) ~= nil
        end
        _G.printf = function() end
        _G.Managers = {}
        for name, value in pairs(globals) do _G[name] = value end
        local ok, err = pcall(body)
        for _, name in ipairs(names) do
            _G[name] = had[name] and saved[name] or nil
        end
        if not ok then error(err, 0) end
    end

    -- ------------------------------------------------------------------
    -- Module shape
    -- ------------------------------------------------------------------
    H.test("level-load owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner"), 1)
    end)

    H.test("owner owns no command, no RPC and no regression check", function()
        -- Checked against code only: the header names `mod:command` and
        -- `_rt_register` on purpose, to record that neither moved with the slice.
        H.equal(count_plain(owner_code, "mod:command"), 0)
        H.equal(count_plain(owner_code, "mod:network_register"), 0)
        H.equal(count_plain(owner_code, "mod:network_send"), 0)
        H.equal(count_plain(owner_code, "_rt_register("), 0)
    end)

    H.test("the install site kept the position the moved code occupied", function()
        local localize_at = assert(entry:find('mod:hook(_G, "Localize"', 1, true))
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner", 1, true))
        local flowstate_at = assert(entry:find(
            "NetworkedFlowStateManager._num_states leak", 1, true))
        H.truthy(localize_at < install_at,
            "the consolidated Localize hook must still register before the owner")
        H.truthy(install_at < flowstate_at,
            "the owner must still install before the NetworkedFlowStateManager leak fix")
    end)

    H.test("install site sits between the two consumers of the census slots", function()
        -- _ct_pickup_population_owner installs ABOVE and takes late-binding
        -- wrappers over the entry locals, which is why those wrappers are still
        -- mandatory. _ct_regression installs BELOW and takes them BY VALUE, which
        -- only works because this owner filled the slots first.
        local population_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_pickup_population_owner", 1, true))
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_level_load_owner", 1, true))
        local regression_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_regression", 1, true))
        H.truthy(population_at < install_at,
            "the population owner installs above, so its wrappers must stay late-binding")
        H.truthy(install_at < regression_at,
            "the regression module binds the dumps by value, so it must install below")
        H.truthy(entry:find(
            "_dump_pickup_system_state     = _ct_level_load_owner.dump_pickup_system_state",
            1, true), "entry must fill its own forward-declared dump slot from the owner")
        H.truthy(entry:find(
            "_dump_pickup_spawners_verbose = _ct_level_load_owner.dump_pickup_spawners_verbose",
            1, true), "entry must fill its own verbose-dump slot from the owner")
    end)

    -- ------------------------------------------------------------------
    -- Hook cardinality and exclusivity
    -- ------------------------------------------------------------------
    H.test("owner registers exactly its three hooks, with the original verbs and order", function()
        with_globals({}, function()
            local f = fixture()
            H.deep_equal(f.order, {
                "hook:EnemyPackageLoader.setup_startup_enemies",
                "hook:MutatorHandler.tweak_pack_spawning_settings",
                "safe:GameModeDeus.local_player_game_starts",
            })
            H.deep_equal(f.dofiles, {})
        end)
    end)

    H.test("the three hooks left the entry and live only in the owner", function()
        for _, needle in ipairs({
            'mod:hook("EnemyPackageLoader", "setup_startup_enemies"',
            'mod:hook("MutatorHandler", "tweak_pack_spawning_settings"',
            'mod:hook_safe("GameModeDeus", "local_player_game_starts"',
        }) do
            H.equal(count_plain(entry, needle), 0, "entry must not re-register " .. needle)
            H.equal(count_plain(owner, needle), 1, "owner must register " .. needle .. " once")
        end
    end)

    H.test("owner stays off every neighbouring seam", function()
        -- VMF silently drops a second registration on a (Class, method) pair, so a
        -- hook here on a neighbour's method would ship one of the two features dead.
        -- CameraManager.shading_callback is _ct_curse_lighting_owner's single hook -
        -- the curse SKY - and is the nearest boundary to this owner's light tint.
        for _, needle in ipairs({
            "CameraManager", '"populate_pickups"', '"_spawn_pickup"',
            '"_spawn_guaranteed_pickup"', '"_can_spawn"', "DeusChestExtension",
            '"get_object_sets"', "deus_populate_graph",
        }) do
            H.equal(count_plain(owner_code, needle), 0,
                "owner code must not touch " .. needle)
        end
    end)

    H.test("owner is load-seam only: no boon, no price, no coin, no graph node", function()
        for _, needle in ipairs({
            "_ct_boon", "DeusShopView", "DeusPowerUp", "add_power_ups",
            "on_soft_currency_picked_up", "_ct_host_settings",
            "_ct_host_graph_snapshot", "_ct_peer_manifests", "effective_setting",
        }) do
            H.equal(count_plain(owner_code, needle), 0, "owner code must not mention " .. needle)
        end
        -- `deus_soft_currency` IS present and must stay: it is one of the pickup
        -- CATEGORY names the census counts, not a read of anyone's coin balance.
        H.truthy(count_plain(owner_code, '"deus_soft_currency"') > 0,
            "the census must still count the Pilgrim's Coin pickup category")
        -- The stripper must actually be stripping, or every line above is vacuous.
        H.truthy(count_plain(owner_code, "no_roamers") > 0, "code_only must keep real code")
    end)

    H.test("no sibling ct file registers any pair this owner owns, and vice versa", function()
        -- The mod-wide singleton invariant, asserted against EVERY ct_dev script
        -- rather than the handful of neighbours the header happens to name. VMF
        -- silently drops a second registration on a (Class, method) pair, so a
        -- collision here would ship one of the two features dead with no warning.
        local names = {
            "chaos_wastes_tweaker_dev", "_adventure_pool", "_ct_altar_reuse_owner",
            "_ct_ammo_guard_core", "_ct_blessed_bots", "_ct_bomb_cooldown_display",
            "_ct_boon_balance", "_ct_boon_grant_owner", "_ct_boon_offer_view_owner",
            "_ct_boon_preview_helpers", "_ct_boon_preview_runtime",
            "_ct_boon_preview_tooltip", "_ct_boon_pricing_audit",
            "_ct_boon_pricing_policy", "_ct_boon_pricing_runtime", "_ct_boon_registry",
            "_ct_boss_grudge_marks", "_ct_bot_coin_pickup", "_ct_bot_economy",
            "_ct_bot_weapon_chest_owner", "_ct_campaign_graph_owner",
            "_ct_chest_count_audit_core", "_ct_chest_revive_owner",
            "_ct_chest_revive_policy", "_ct_collectible_policy", "_ct_combat_hooks",
            "_ct_command_owner", "_ct_cot_cost", "_ct_cot_cost_policy",
            "_ct_cot_early_reward", "_ct_cot_early_reward_core",
            "_ct_cot_placement_policy", "_ct_curse_lighting_owner", "_ct_dev_mission",
            "_ct_dev_mission_catalog", "_ct_diag_cursed_chest132", "_ct_diag_freeze487",
            "_ct_diag_skull52", "_ct_diag_tab_native533", "_ct_dup_vote_chips",
            "_ct_journey_difficulty_guard", "_ct_mechanic_tweaks", "_ct_meta_trait_boons",
            "_ct_miasma", "_ct_miasma_policy", "_ct_modifier_stack_audit",
            "_ct_modifier_stack_policy", "_ct_parry_cooldown_policy",
            "_ct_pickup_population_owner", "_ct_pickup_spawn_owner",
            "_ct_pilgrimage_context", "_ct_profile_snapshot", "_ct_progressive_difficulty",
            "_ct_progressive_elite_audit", "_ct_progressive_elite_policy",
            "_ct_regression", "_ct_replacement_compensation", "_ct_replacement_runtime",
            "_ct_resume_audit", "_ct_resume_policy", "_ct_run_creation_owner",
            "_ct_spawn_eligibility_owner",
            "_ct_start_shrine_policy", "_ct_start_shrine_runtime",
            "_ct_starting_coins_policy", "_ct_tab_collectibles_layout",
            "_ct_tab_panel_owner", "_ct_umbrella_policy", "_ct_weapon_trait_generation",
            "_ct_weave_curse_audit", "_ct_weave_curse_policy", "_ct_wire_policy",
            "_lib_peer_parity", "_lib_wire_catalog", "chaos_wastes_tweaker_dev_data",
            "chaos_wastes_tweaker_dev_localization", "chaos_wastes_tweaker_mutex",
        }
        -- This roster is every ct_dev script EXCEPT the owner under test, so a new
        -- sibling that starts hooking is caught the moment someone adds it here -
        -- and the floor below makes a silently shrinking roster fail instead of
        -- passing vacuously.
        -- Statement-position scan: a line whose first token opens a mod:hook call.
        local function pairs_in(source)
            local found = {}
            for line in source:gmatch("[^\n]+") do
                local s = line:match("^%s*(.*)$")
                if s:sub(1, 2) ~= "--" then
                    local target, method = s:match('^mod:hook[_a-z]*%(%s*"([%w_]+)",%s*"([%w_]+)"')
                    if target then found[target .. "." .. method] = true end
                end
            end
            return found
        end
        local mine = pairs_in(owner)
        H.deep_equal(mine, {
            ["EnemyPackageLoader.setup_startup_enemies"] = true,
            ["MutatorHandler.tweak_pack_spawning_settings"] = true,
            ["GameModeDeus.local_player_game_starts"] = true,
        })
        local checked = 0
        for _, name in ipairs(names) do
            local file = io.open(root .. name .. ".lua", "rb")
            H.truthy(file, "expected ct_dev script " .. name .. ".lua to exist")
            local source = file:read("*a")
            file:close()
            checked = checked + 1
            for key in pairs(pairs_in(source)) do
                H.equal(mine[key], nil,
                    name .. " also registers " .. key .. " - VMF drops one of them")
            end
        end
        -- If the roster ever silently shrinks, the loop above passes vacuously.
        H.truthy(checked >= 75, "the sibling roster must still cover the whole mod")
    end)

    -- ------------------------------------------------------------------
    -- ctx contract - all three keys are load-time asserted
    -- ------------------------------------------------------------------
    H.test("install refuses a missing or malformed ctx at load time", function()
        with_globals({}, function()
            local installer = assert(loadfile(module_path))()
            H.equal(pcall(installer, {}, nil), false, "nil ctx must assert")
            H.equal(pcall(installer, {}, "nope"), false, "non-table ctx must assert")
            for _, key in ipairs({
                "dbg", "on_injected_adventure_level", "adventure_base_from_level_key",
            }) do
                H.equal(pcall(function() return fixture({ [key] = "\0drop" }) end), false,
                    "a dropped ctx." .. key .. " must assert")
            end
        end)
    end)

    -- ------------------------------------------------------------------
    -- Exports and the forward-declaration pattern
    -- ------------------------------------------------------------------
    H.test("install returns the two dump bodies and the live strip list", function()
        with_globals({}, function()
            local f = fixture()
            H.equal(type(f.exports), "table")
            H.equal(type(f.exports.dump_pickup_system_state), "function")
            H.equal(type(f.exports.dump_pickup_spawners_verbose), "function")
            H.equal(type(f.exports.adventure_incompatible_pack_mutators), "table")
            H.equal(f.exports.adventure_incompatible_pack_mutators.no_roamers, true)
        end)
    end)

    H.test("the strip list crosses as the SAME table the hook reads, not a copy", function()
        with_globals({}, function()
            local f = fixture()
            local list = f.exports.adventure_incompatible_pack_mutators
            -- Add a second entry through the exported reference; if the hook read a
            -- copy, the strip below would not see it and `mutator_x` would survive.
            list.mutator_x = true
            local seen
            local function vanilla(zone_list, mutator_list) seen = { zone_list, mutator_list } end
            f.hooks["MutatorHandler.tweak_pack_spawning_settings"](
                vanilla, { "mutator_x" }, { "no_roamers" }, "chaos_light", {})
            H.deep_equal(seen, { {}, {} },
                "a mutation through the exported list must be visible to the hook")
        end)
    end)

    H.test("no census slot leaks to _G, on either side of the move", function()
        with_globals({}, function()
            fixture()
            for _, name in ipairs({
                "_dump_pickup_system_state", "_dump_pickup_spawners_verbose",
                "_ct_book_spawner_census", "_palette_slot", "_PICKUP_CATEGORIES",
                "_CURSE_LIGHT_PALETTES", "ADVENTURE_INCOMPATIBLE_PACK_MUTATORS",
            }) do
                H.equal(rawget(_G, name), nil, name .. " must not leak to _G")
            end
        end)
        -- And the definitions kept the no-`local` forward-assignment form, which is
        -- what let them move byte-identically into the owner's own declared slots.
        H.equal(count_plain(owner, "\nlocal _dump_pickup_system_state\n"), 1)
        H.equal(count_plain(owner, "\nlocal _dump_pickup_spawners_verbose\n"), 1)
        H.equal(count_plain(owner, "\nlocal _ct_book_spawner_census\n"), 1)
        H.equal(count_plain(owner, "\nfunction _dump_pickup_system_state(prefix, also_echo)"), 1)
        H.equal(count_plain(owner, "\nfunction _dump_pickup_spawners_verbose(prefix)"), 1)
        H.equal(count_plain(owner, "\nfunction _ct_book_spawner_census(ps_sys, level_key)"), 1)
    end)

    H.test("the book-spawner census is published off mod, and its entry slot is retired", function()
        with_globals({}, function()
            local f = fixture()
            H.equal(type(f.mod._ct_book_spawner_census), "function",
                "the owner must still publish mod._ct_book_spawner_census")
        end)
        -- Its only consumer resolves it off `mod` at call time, so the entry keeps
        -- no local for it. A stray forward-declaration would be a dead slot that a
        -- future edit could start assigning in parallel with the owner.
        H.equal(count_plain(entry, "local _ct_book_spawner_census"), 0)
        H.equal(count_plain(entry, "_ct_book_spawner_census"), 0)
    end)

    H.test("both marker globals keep their frozen values, set by the owner", function()
        with_globals({}, function()
            fixture()
            H.equal(rawget(_G, "CT_NO_ROAMERS_DEUS_FIX_MARKER"),
                "no_roamers_strip_keys_on_missing_difficulty_overrides_v0.7.231")
            H.equal(rawget(_G, "CT_NO_ROAMERS_ARITY_FIX_MARKER"),
                "no_roamers_hook_static_arity_no_self_v0.7.241")
        end)
        H.equal(count_plain(entry, "CT_NO_ROAMERS_DEUS_FIX_MARKER = "), 0,
            "the entry must not also set the marker _ct_regression reads")
        H.equal(count_plain(entry, "CT_NO_ROAMERS_ARITY_FIX_MARKER = "), 0)
    end)

    -- ------------------------------------------------------------------
    -- Crash guard 1: random directors on adventure-authored levels
    -- ------------------------------------------------------------------
    local function drive_startup_enemies(f, level_key)
        local seen
        local function vanilla(self, key, seed, failed, use_random, conflict, difficulty, tweak)
            seen = use_random
        end
        f.hooks["EnemyPackageLoader.setup_startup_enemies"](
            vanilla, {}, level_key, 1234, {}, false, "chaos_light", "hardest", 0)
        return seen
    end

    H.test("random directors are forced for an injected adventure base", function()
        with_globals({}, function()
            local f = fixture({
                adventure_base_from_level_key = function(key)
                    if key == "magnus_tzeentch_path1" then return "magnus" end
                    return nil
                end,
            })
            H.equal(drive_startup_enemies(f, "magnus_tzeentch_path1"), true)
        end)
    end)

    H.test("random directors are forced for the native _belakor_path family", function()
        -- These are NOT matched by adventure_base_from_level_key; the substring is
        -- the signature. Dropping this branch is the cemetery_belakor_path1 host CTD.
        with_globals({}, function()
            local f = fixture()
            H.equal(drive_startup_enemies(f, "cemetery_belakor_path1"), true)
        end)
    end)

    H.test("an ordinary CW level keeps vanilla's use_random_directors", function()
        with_globals({}, function()
            local f = fixture()
            H.equal(drive_startup_enemies(f, "dlc_castle"), false)
        end)
    end)

    -- ------------------------------------------------------------------
    -- Crash guard 2: the no_roamers strip, including its #356 arity
    -- ------------------------------------------------------------------
    local function drive_pack_settings(f, zone_list, mutator_list, settings)
        local seen
        local function vanilla(zone, mutators, conflict, pack)
            seen = { zone = zone, mutators = mutators, conflict = conflict, pack = pack }
        end
        f.hooks["MutatorHandler.tweak_pack_spawning_settings"](
            vanilla, zone_list, mutator_list, "chaos_light", settings)
        return seen
    end

    H.test("no_roamers is stripped from BOTH lists when difficulty_overrides is missing", function()
        -- The pre-#356 hook declared a spurious leading `self`, so the real
        -- zone_mutator_list rode in as the dropped positional and was never
        -- filtered - the SIGNATURE-zone path no_roamers actually rides on. Both
        -- lists are asserted here, so a self-shift regression fails.
        with_globals({}, function()
            local f = fixture()
            local seen = drive_pack_settings(f,
                { "no_roamers", "keep_zone" }, { "no_roamers", "keep_mut" }, {})
            H.deep_equal(seen.zone, { "keep_zone" })
            H.deep_equal(seen.mutators, { "keep_mut" })
            H.equal(seen.conflict, "chaos_light")
        end)
    end)

    H.test("a healthy CW level passes through untouched, same table identity", function()
        with_globals({}, function()
            local f = fixture()
            local zone = { "no_roamers" }
            local mutators = { "deus_less_roamers" }
            local settings = { difficulty_overrides = {} }
            local seen = drive_pack_settings(f, zone, mutators, settings)
            H.equal(seen.zone, zone, "pass-through must forward the ORIGINAL zone list")
            H.equal(seen.mutators, mutators)
            H.equal(seen.pack, settings)
        end)
    end)

    H.test("the injected-level predicate still strips even with difficulty_overrides present", function()
        -- The v0.7.41 aesthetic exemption is OR-ed with the crash predicate, so
        -- this build never strips LESS than before.
        with_globals({}, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            local seen = drive_pack_settings(f,
                { "no_roamers" }, {}, { difficulty_overrides = {} })
            H.deep_equal(seen.zone, {})
        end)
    end)

    H.test("the strip hook takes vanilla's four positional args, with no leading self", function()
        H.equal(count_plain(owner,
            'mod:hook("MutatorHandler", "tweak_pack_spawning_settings", function(func, zone_mutator_list, mutator_list, conflict_director_name, pack_spawning_settings)'),
            1)
        H.equal(count_plain(owner_code, "function(func, self, zone_mutator_list"), 0)
    end)

    -- ------------------------------------------------------------------
    -- The curse light tint
    -- ------------------------------------------------------------------
    -- A level of `count` units, each carrying one Light handle, so the tint loop
    -- walks a predictable global light index.
    local function light_world(count)
        local units, colours = {}, {}
        for i = 1, count do units[i] = { id = i } end
        return units, colours, {
            Level = { units = function() return units end },
            Unit = {
                alive = function() return true end,
                num_lights = function() return 1 end,
                light = function(unit, idx) return { unit = unit, idx = idx } end,
                get_data = function() return nil end,
            },
            Light = {
                set_color = function(light, colour)
                    colours[#colours + 1] = { light.unit.id, colour }
                end,
            },
            Vector3 = function(r, g, b) return { r, g, b } end,
            LevelHelper = { current_level = function() return { "level" } end },
        }
    end

    local function mission_start(f, theme, world_self)
        f.hooks["GameModeDeus.local_player_game_starts"](world_self, {}, {})
        return theme
    end

    local function deus_self(theme)
        return {
            _world = {},
            _deus_run_controller = {
                get_current_node_key = function() return "node_1" end,
                get_current_node = function()
                    return { theme = theme, level = "magnus_khorne_path1" }
                end,
            },
        }
    end

    H.test("a cursed injected level tints every light from the god's palette", function()
        local units, colours, globals = light_world(20)
        with_globals(globals, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            mission_start(f, "khorne", deus_self("khorne"))
            H.equal(#colours, #units, "every light in the level must be tinted")
            for _, entry_pair in ipairs(colours) do
                H.equal(#entry_pair[2], 3, "each tint must be an r,g,b Vector3")
            end
        end)
    end)

    H.test("the palette slot is deterministic per light index, not random", function()
        local _, colours_a, globals_a = light_world(24)
        local first
        with_globals(globals_a, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            mission_start(f, "nurgle", deus_self("nurgle"))
            first = {}
            for i, pair in ipairs(colours_a) do first[i] = table.concat(pair[2], ",") end
        end)
        local _, colours_b, globals_b = light_world(24)
        with_globals(globals_b, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            mission_start(f, "nurgle", deus_self("nurgle"))
            local second = {}
            for i, pair in ipairs(colours_b) do second[i] = table.concat(pair[2], ",") end
            H.deep_equal(second, first,
                "the same light index must get the same slot on every load")
        end)
    end)

    H.test("the tzeentch palette is all-blue and the others are not monochrome", function()
        -- Per the v0.7.16 user directive tzeentch dropped its neutral slot, so every
        -- Light component is some shade of deep magic blue: blue dominates red and
        -- green in every slot. The other gods deliberately mix hues.
        local _, tz, tz_globals = light_world(40)
        with_globals(tz_globals, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            mission_start(f, "tzeentch", deus_self("tzeentch"))
            for _, pair in ipairs(tz) do
                local c = pair[2]
                H.truthy(c[3] > c[1] and c[3] > c[2], "every tzeentch light must be blue-dominant")
            end
        end)
        local _, sl, sl_globals = light_world(40)
        with_globals(sl_globals, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            mission_start(f, "slaanesh", deus_self("slaanesh"))
            local distinct = {}
            for _, pair in ipairs(sl) do distinct[table.concat(pair[2], ",")] = true end
            local n = 0
            for _ in pairs(distinct) do n = n + 1 end
            H.truthy(n > 1, "slaanesh must use more than one palette slot")
        end)
    end)

    H.test("an uncursed or non-injected mission tints nothing", function()
        local _, colours, globals = light_world(10)
        with_globals(globals, function()
            local f = fixture({ on_injected_adventure_level = function() return true end })
            mission_start(f, "wastes", deus_self("wastes"))
            H.equal(#colours, 0, "the wastes theme carries no curse, so no tint")
        end)
        local _, colours2, globals2 = light_world(10)
        with_globals(globals2, function()
            local f = fixture()  -- on_injected_adventure_level returns false
            mission_start(f, "khorne", deus_self("khorne"))
            H.equal(#colours2, 0, "a native CW level is left to vanilla's probe tint")
        end)
    end)

    H.test("mission start dumps pickup state before it decides whether to tint", function()
        -- The dump is unconditional: it is the signal that tells a logging-OFF host
        -- an injected map spawned nothing, so it must not sit behind the tint gate.
        local _, _, globals = light_world(4)
        with_globals(globals, function()
            local f = fixture()  -- NOT injected: the tint path bails immediately
            mission_start(f, "khorne", deus_self("khorne"))
            local dumped = false
            for _, line in ipairs(f.dbg) do
                if line:find("[pickups:mission_start]", 1, true) then dumped = true end
            end
            H.truthy(dumped, "the pickup dump must run even when the tint path bails")
        end)
    end)

    -- ------------------------------------------------------------------
    -- The exported census still works after crossing the boundary
    -- ------------------------------------------------------------------
    H.test("the exported pickup dump reports level, difficulty and spawner counts", function()
        local globals = {
            Managers = {
                state = {
                    game_mode = { level_key = function() return "magnus_khorne_path1" end },
                    difficulty = { get_difficulty = function() return "hardest" end },
                    entity = {
                        system = function(_, name)
                            H.equal(name, "pickup_system")
                            return {
                                primary_pickup_spawners = {},
                                secondary_pickup_spawners = {},
                                specified_pickup_spawners = {},
                                guaranteed_pickup_spawners = {},
                            }
                        end,
                    },
                },
            },
            LevelSettings = {},
        }
        with_globals(globals, function()
            local f = fixture()
            f.exports.dump_pickup_system_state("[probe]", false)
            local joined = table.concat(f.dbg, "\n")
            H.truthy(joined:find("level=magnus_khorne_path1", 1, true))
            H.truthy(joined:find("difficulty=hardest", 1, true))
            H.truthy(joined:find("PickupSystem.primary_pickup_spawners", 1, true))
        end)
    end)
end
