-- Guards the #1159 node-entry owner extraction: everything ct does when a run
-- moves INTO a Chaos Wastes graph node - the runtime half of the curse-disable
-- policy, the two curse-display suppressions, the two DeusThemeSettings backfills
-- that exist only because this owner forces theme="wastes" onto a still-cursed
-- node, the #470 curse-sorcerer rank-8 backfill, and the four guards that decide
-- whether that node's weapon chest can produce a result at all - moved out of the
-- ct_dev entry into _ct_node_entry_owner.lua.
--
-- ONE contiguous chunk moved (old entry lines 2728-3221, 494 raw / 455 non-empty
-- lines, MD5 3309e60ddf14a3fce34c68b5f891fb81 over the pristine `git archive`
-- bytes) and the installer sits at the exact line it occupied, between the
-- _ct_boon_offer_view_owner install above and the _ct_weapon_trait_generation
-- install below, so there is no load-order deviation to argue about.
--
-- There is exactly ONE code deviation and this file is what pins it. The node
-- transition used to reset the entry local _defeat_recovery_triggered_this_round
-- by direct assignment; that flag is also read and written by the entry accessor
-- handed to _ct_combat_hooks, so the owner calls that SAME accessor instead of
-- re-declaring the local and splitting one flag into two slots. The executable
-- half below installs against a recording accessor and asserts the transition
-- still drives it to false.
--
-- Almost everything here is executable rather than textual: the module is loaded
-- for real and installed against a recording stub, so a lost hook, a curse that
-- stopped being suppressed, a theme that stopped being restored, a backfill that
-- stopped applying, or a global that leaked fails here instead of in a Chaos
-- Wastes run.
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_node_entry_owner.lua"

    local function read(name)
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

    -- Comment-stripped view. The header deliberately QUOTES the one deviation it
    -- documents, so the "this must appear exactly once in CODE" assertions have to
    -- run against code only or they would forbid documenting the very substitution
    -- they exist to pin.
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
    local owner = read("_ct_node_entry_owner.lua")
    local owner_code = code_only(owner)
    local campaign_graph = read("_ct_campaign_graph_owner.lua")

    -- ------------------------------------------------------------------
    -- Executable fixture. The module registers eight hooks and four
    -- regression checks at install time and mutates two vanilla data tables;
    -- it loads no module, registers no command and sends no RPC, so nothing
    -- here reaches the engine.
    -- ------------------------------------------------------------------
    local GLOBAL_KEYS = {
        "Breeds", "DeusThemeSettings", "WeaponProperties", "LevelSettings",
        "DEUS_CHEST_TYPES", "HashUtils", "Managers", "printf",
        "_ct_cursed_chest_seq", "_ct_cot_block_last", "_ct_cot_trial_last",
    }

    local function snapshot_globals()
        local saved = {}
        for _, key in ipairs(GLOBAL_KEYS) do saved[key] = rawget(_G, key) end
        saved.__table_shuffle = rawget(table, "shuffle")
        return saved
    end

    local function restore_globals(saved)
        for _, key in ipairs(GLOBAL_KEYS) do rawset(_G, key, saved[key]) end
        rawset(table, "shuffle", saved.__table_shuffle)
    end

    local function install_globals()
        rawset(_G, "Breeds", { curse_mutator_sorcerer = { max_health = { [6] = 120, [7] = 150 } } })
        rawset(_G, "DeusThemeSettings", {
            wastes = {},
            nurgle = { curse_description_color = { 255, 0, 0, 0 }, icon = "icon_nurgle" },
        })
        rawset(_G, "WeaponProperties", { combinations = { deus_ranged = { power = true } } })
        rawset(_G, "LevelSettings", { cemetery_tzeentch_path1 = {} })
        rawset(_G, "DEUS_CHEST_TYPES", {
            upgrade = "u", swap_melee = "m", swap_ranged = "r", power_up = "p",
        })
        rawset(_G, "HashUtils", { fnv32_hash = function() return 4242 end })
        rawset(_G, "Managers", { player = { is_server = true } })
        rawset(_G, "printf", function() end)
        -- table.shuffle is a Fatshark addition, not stock Lua 5.1. A recorded,
        -- deterministic stand-in keeps the distribution assertions exact.
        rawset(table, "shuffle", function(list) list.__shuffled = true return list end)
    end

    local function fixture(overrides)
        overrides = overrides or {}
        local hooks, order, checks, check_order, logs = {}, {}, {}, {}, {}
        local mod = {}
        local flag = false

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
            error("the node-entry owner must not load any module: " .. tostring(path))
        end

        function mod:command(name)
            error("the node-entry owner must not register a command: " .. tostring(name))
        end

        function mod:network_register(name)
            error("the node-entry owner must not register an RPC: " .. tostring(name))
        end

        function mod:network_send(name)
            error("the node-entry owner must not send an RPC: " .. tostring(name))
        end

        function mod:warning(fmt) logs[#logs + 1] = { "warning", fmt } end
        function mod:echo(line) logs[#logs + 1] = { "echo", line } end

        local settings = overrides.settings or {}
        local disabled_curses = overrides.disabled_curses or {}

        local ctx = {
            capture_returns = function(...) return select("#", ...), { ... } end,
            dbg = function() end,
            defeat_recovery_triggered = function(value)
                if value ~= nil then flag = value end
                return flag
            end,
            effective_setting = function(id) return settings[id] end,
            is_curse_disabled = function(curse_name)
                return disabled_curses[curse_name] == true
            end,
            rt_register = function(name, fn)
                H.equal(checks[name], nil, "duplicate regression check " .. name)
                checks[name] = fn
                check_order[#check_order + 1] = name
                order[#order + 1] = "check:" .. name
            end,
        }
        for key, value in pairs(overrides.ctx or {}) do ctx[key] = value end

        return {
            mod = mod, ctx = ctx, hooks = hooks, order = order,
            checks = checks, check_order = check_order, logs = logs,
            flag = function() return flag end,
            set_flag = function(value) flag = value end,
        }
    end

    local function load_install()
        local chunk = assert(loadfile(module_path))
        local install = chunk()
        H.equal(type(install), "function", "module must return the installer")
        return install
    end

    local function installed(overrides)
        local saved = snapshot_globals()
        install_globals()
        for key, value in pairs((overrides or {}).globals or {}) do rawset(_G, key, value) end
        for _, key in ipairs((overrides or {}).clear_globals or {}) do rawset(_G, key, nil) end
        local f = fixture(overrides)
        local ok, err = pcall(load_install(), f.mod, f.ctx)
        if not ok then
            restore_globals(saved)
            error(err, 0)
        end
        f.restore = function() restore_globals(saved) end
        return f
    end

    -- ------------------------------------------------------------------
    -- Shape and placement
    -- ------------------------------------------------------------------
    H.test("node-entry owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once, at the position the block occupied", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_node_entry_owner"), 1)
        local offer_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_offer_view_owner", 1, true))
        local install_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_node_entry_owner", 1, true))
        local trait_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_weapon_trait_generation", 1, true))
        H.truthy(offer_at < install_at,
            "the boon-offer view owner must still install above the node-entry owner")
        H.truthy(install_at < trait_at,
            "the weapon-trait owner must still install below the node-entry owner")
    end)

    H.test("every moved surface left the entry and landed in the owner", function()
        for _, needle in ipairs({
            'mod:hook("MutatorHandler", "_activate_mutator"',
            'mod:hook_safe("MutatorHandler", "initialize_mutators"',
            'mod:hook("DeusMechanism", "get_current_node_curse"',
            'mod:hook("DeusMechanism", "_transition_next_node"',
            'mod:hook("DeusMechanism", "start_next_round"',
            'mod:hook("DeusMapDecisionView", "_enable_hover"',
            'mod:hook("DeusRunController", "get_own_weapon_pool_excludes"',
            'mod:hook("DeusRunController", "get_deus_weapon_chest_type"',
            "local _VANILLA_RARITIES = {",
            "mod._ct_backfill_rank8_max_health = function(mh)",
            "mod._ct_deus_chest_needs_fallback = function(level_settings)",
            "mod._ct_build_deus_chest_fallback = function(chest_types)",
            "mod._ct_ensure_deus_chest_distribution = function(drc)",
            "combos.deus_trollhammer_torpedo = combos.deus_ranged",
            "theme.curse_description_color = { 255, 255, 255, 255 }",
            'theme.icon = "deus_icon_meta_01"',
        }) do
            H.equal(count_plain(owner, needle), 1, needle .. " must live in the owner")
            H.equal(count_plain(entry, needle), 0, needle .. " must have left the entry")
        end
    end)

    H.test("the owner did not absorb a neighbour's responsibility", function()
        -- Generation-time curse filtering belongs to _ct_campaign_graph_owner.
        H.equal(count_plain(owner_code, "filter_available_curses"), 0)
        H.equal(count_plain(owner_code, "restore_available_curses"), 0)
        H.equal(count_plain(campaign_graph, "local function filter_available_curses(config)"), 1)
        -- WHICH boons are offered, and the trait pool, stay with their owners.
        -- Code-only: the header names both neighbours on purpose.
        H.equal(count_plain(owner_code, "generate_random_power_ups"), 0)
        H.equal(count_plain(owner_code, "_ct_weapon_trait_generation"), 0)
        -- The altar unit itself belongs to _ct_altar_reuse_owner.
        H.equal(count_plain(owner, 'mod:hook("DeusChestExtension"'), 0)
        H.equal(count_plain(owner, 'mod:hook_safe("DeusChestExtension"'), 0)
        -- The predicate stays entry-owned and is handed to both curse owners.
        H.equal(count_plain(owner, "is_curse_disabled = function(curse_name)"), 0)
        H.equal(count_plain(entry, "is_curse_disabled = function(curse_name)"), 1)
    end)

    H.test("the owner registers no command, no RPC, no module load and no update", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "mod:network_send"), 0)
        H.equal(count_plain(owner, "mod:dofile("), 0)
        H.equal(count_plain(owner, "mod.update"), 0)
    end)

    H.test("the header records the extraction provenance and the one deviation", function()
        H.truthy(owner:find("3309e60ddf14a3fce34c68b5f891fb81", 1, true),
            "the moved chunk's pristine MD5 must be recorded in the header")
        H.truthy(owner:find("2728-3221", 1, true),
            "the moved entry line range must be recorded in the header")
        -- Exactly one substitution in CODE, and the flag it substitutes for is
        -- still an entry local with a single storage slot.
        H.equal(count_plain(owner_code, "defeat_recovery_triggered(false)"), 1)
        H.equal(count_plain(owner_code, "_defeat_recovery_triggered_this_round"), 0,
            "the owner must not declare or assign a flag of its own")
        H.equal(count_plain(entry, "local _defeat_recovery_triggered_this_round = false"), 1)
        H.equal(count_plain(entry, "            _defeat_recovery_triggered_this_round = value"), 2,
            "one accessor for _ct_combat_hooks and one for the node-entry owner, over ONE local")
    end)

    -- ------------------------------------------------------------------
    -- Install-time behaviour
    -- ------------------------------------------------------------------
    H.test("install registers exactly its eight hooks, with the original verbs and order", function()
        local f = installed()
        H.deep_equal(f.order, {
            "hook:MutatorHandler._activate_mutator",
            "safe:MutatorHandler.initialize_mutators",
            "check:curse_sorcerer_rank8_backfill",
            "hook:DeusMechanism.get_current_node_curse",
            "hook:DeusMechanism._transition_next_node",
            "hook:DeusMechanism.start_next_round",
            "hook:DeusMapDecisionView._enable_hover",
            "hook:DeusRunController.get_own_weapon_pool_excludes",
            "check:trollhammer_property_pool_aliased",
            "check:curse_theme_color_backfilled",
            "check:deus_chest_distribution_fallback",
            "hook:DeusRunController.get_deus_weapon_chest_type",
        }, "hook and regression-check registration order must be unchanged")
        f.restore()
    end)

    H.test("install applies both vanilla data backfills and its checks then pass", function()
        local f = installed()
        local combos = rawget(_G, "WeaponProperties").combinations
        H.equal(combos.deus_trollhammer_torpedo, combos.deus_ranged,
            "the torpedo property pool must alias the ranged pool by reference")
        local themes = rawget(_G, "DeusThemeSettings")
        H.deep_equal(themes.wastes.curse_description_color, { 255, 255, 255, 255 })
        H.equal(themes.wastes.icon, "deus_icon_meta_01")
        H.deep_equal(themes.nurgle.curse_description_color, { 255, 0, 0, 0 },
            "a theme that already had a colour must not be rewritten")
        H.equal(themes.nurgle.icon, "icon_nurgle")
        for _, name in ipairs(f.check_order) do
            H.equal(f.checks[name](), nil, "regression check " .. name .. " must pass after install")
        end
        f.restore()
    end)

    H.test("the property alias never overwrites an existing pool", function()
        local mine = { mine = true }
        local f = installed({ globals = {
            WeaponProperties = { combinations = {
                deus_ranged = { power = true },
                deus_trollhammer_torpedo = mine,
            } },
        } })
        H.equal(rawget(_G, "WeaponProperties").combinations.deus_trollhammer_torpedo, mine)
        f.restore()
    end)

    H.test("install degrades rather than errors when the vanilla tables are absent", function()
        local f = installed({ clear_globals = { "WeaponProperties", "DeusThemeSettings" } })
        H.equal(f.checks.trollhammer_property_pool_aliased():sub(1, 5), "skip:",
            "an absent WeaponProperties must SKIP, never FAIL (#1156 rule 2)")
        H.equal(f.checks.curse_theme_color_backfilled():sub(1, 5), "skip:",
            "an absent DeusThemeSettings must SKIP, never FAIL (#1156 rule 2)")
        f.restore()
    end)

    -- ------------------------------------------------------------------
    -- Curse runtime
    -- ------------------------------------------------------------------
    H.test("a disabled curse mutator is vetoed and an enabled one passes through", function()
        local f = installed({ disabled_curses = { curse_rotten_miasma = true } })
        local calls = {}
        local function vanilla(_, name) calls[#calls + 1] = name return "activated" end
        H.equal(f.hooks["MutatorHandler._activate_mutator"](vanilla, {}, "curse_rotten_miasma"), nil)
        H.equal(#calls, 0, "a disabled curse must never reach vanilla _activate_mutator")
        H.equal(f.hooks["MutatorHandler._activate_mutator"](vanilla, {}, "curse_bodyblock"), "activated")
        H.deep_equal(calls, { "curse_bodyblock" })
        f.restore()
    end)

    H.test("get_current_node_curse nulls only a disabled curse", function()
        local f = installed({ disabled_curses = { curse_rotten_miasma = true } })
        local hook = f.hooks["DeusMechanism.get_current_node_curse"]
        H.equal(hook(function() return "curse_rotten_miasma" end, {}), nil)
        H.equal(hook(function() return "curse_bodyblock" end, {}), "curse_bodyblock")
        f.restore()
    end)

    H.test("the node transition suppresses and RESTORES a disabled curse", function()
        local f = installed({ disabled_curses = { curse_rotten_miasma = true } })
        local node = { curse = "curse_rotten_miasma", theme = "nurgle" }
        local seen
        local self_ = { _deus_run_controller = {
            get_graph_data = function() return { next_node = node } end,
        } }
        local result = f.hooks["DeusMechanism._transition_next_node"](function(_, key)
            seen = node.curse
            return "next_state"
        end, self_, "next_node")
        H.equal(seen, nil, "vanilla must run with node.curse blanked")
        H.equal(node.curse, "curse_rotten_miasma", "node.curse must be restored after vanilla")
        H.equal(node.theme, "nurgle", "the transition must not touch node.theme")
        H.equal(result, "next_state", "the single vanilla return must survive")
        f.restore()
    end)

    H.test("the node transition drives the ENTRY's defeat-recovery accessor, not a copy", function()
        -- This is the extraction's one deviation. The owner has no flag of its
        -- own: it calls the entry accessor, which is the same closure over the
        -- same local that _ct_combat_hooks reads.
        local f = installed()
        f.set_flag(true)
        H.equal(f.flag(), true)
        f.hooks["DeusMechanism._transition_next_node"](function() return nil end,
            { _deus_run_controller = { get_graph_data = function() return {} end } }, "n")
        H.equal(f.flag(), false, "node transition must reset the defeat-recovery flag to false")
        f.restore()
    end)

    H.test("the node transition resets the per-mission Chest of Trials state", function()
        local f = installed()
        rawset(_G, "_ct_cursed_chest_seq", 7)
        local stale_block = rawget(_G, "_ct_cot_block_last")
        f.hooks["DeusMechanism._transition_next_node"](function() return nil end,
            { _deus_run_controller = { get_graph_data = function() return {} end } }, "n")
        H.equal(rawget(_G, "_ct_cursed_chest_seq"), 0)
        H.equal(type(rawget(_G, "_ct_cot_block_last")), "table")
        H.equal(next(rawget(_G, "_ct_cot_block_last")), nil)
        H.equal(type(rawget(_G, "_ct_cot_trial_last")), "table")
        H.truthy(rawget(_G, "_ct_cot_block_last") ~= stale_block)
        f.restore()
    end)

    H.test("start_next_round forces the wastes theme and restores both fields", function()
        local f = installed({ disabled_curses = { curse_rotten_miasma = true } })
        local node = { curse = "curse_rotten_miasma", theme = "nurgle" }
        local seen_curse, seen_theme
        local self_ = { _deus_run_controller = {
            get_current_node = function() return node end,
        } }
        local a, b, c = f.hooks["DeusMechanism.start_next_round"](function()
            seen_curse, seen_theme = node.curse, node.theme
            return "mode", nil, "settings"
        end, self_)
        H.equal(seen_curse, nil, "vanilla must run with the curse blanked")
        H.equal(seen_theme, "wastes", "vanilla must run with the theme forced to wastes")
        H.equal(node.curse, "curse_rotten_miasma")
        H.equal(node.theme, "nurgle")
        H.equal(a, "mode")
        H.equal(b, nil, "the interior nil return must survive _capture_returns")
        H.equal(c, "settings", "the third return must survive the interior nil")
        f.restore()
    end)

    H.test("start_next_round leaves an ENABLED curse alone", function()
        local f = installed()
        local node = { curse = "curse_bodyblock", theme = "khorne" }
        local seen_theme
        f.hooks["DeusMechanism.start_next_round"](function()
            seen_theme = node.theme
            return "mode"
        end, { _deus_run_controller = { get_current_node = function() return node end } })
        H.equal(seen_theme, "khorne", "an enabled curse must keep its theme through vanilla")
        H.equal(node.curse, "curse_bodyblock")
        f.restore()
    end)

    H.test("the map hover suppresses and restores the theme of a disabled-curse node", function()
        local f = installed({ disabled_curses = { curse_rotten_miasma = true } })
        local node = { curse = "curse_rotten_miasma", theme = "nurgle" }
        local other = { curse = "curse_bodyblock", theme = "khorne" }
        local self_ = { _deus_run_controller = {
            get_graph_data = function() return { cursed = node, plain = other } end,
        } }
        local seen
        local hook = f.hooks["DeusMapDecisionView._enable_hover"]
        H.equal(hook(function() seen = node.theme end, self_, "cursed"), nil)
        H.equal(seen, nil, "the hover preview must run with the theme cleared")
        H.equal(node.theme, "nurgle", "the node theme must be restored")
        hook(function() seen = other.theme return "hovered" end, self_, "plain")
        H.equal(seen, "khorne", "an enabled-curse node must hover with its own theme")
        f.restore()
    end)

    H.test("the #470 rank-8 backfill fires once and never rewrites live values", function()
        local f = installed()
        local breed = rawget(_G, "Breeds").curse_mutator_sorcerer
        f.hooks["MutatorHandler.initialize_mutators"]({}, {})
        H.equal(breed.max_health[8], 150)
        H.equal(breed.max_health[6], 120, "the existing band must not be re-keyed")
        H.equal(breed.max_health[7], 150)
        -- Re-running the safe hook is a no-op: the predicate only fires on a
        -- table that has [7] and no [8].
        H.equal(f.mod._ct_backfill_rank8_max_health(breed.max_health), false)
        H.equal(f.mod._ct_backfill_rank8_max_health({ 30, 30, 40, 60, 90, 90, 90, 90 }), false)
        H.equal(f.mod._ct_backfill_rank8_max_health(nil), false)
        H.equal(f.mod._ct_backfill_rank8_max_health({}), false)
        f.restore()
    end)

    -- ------------------------------------------------------------------
    -- Node weapon chest
    -- ------------------------------------------------------------------
    H.test("unknown rarities are stripped from the weapon pool excludes", function()
        local f = installed()
        local excludes = { plentiful = true, modded = true, unique = true }
        local out = f.hooks["DeusRunController.get_own_weapon_pool_excludes"](
            function() return excludes end, {})
        H.deep_equal(out, { plentiful = true, unique = true })
        H.equal(f.hooks["DeusRunController.get_own_weapon_pool_excludes"](
            function() return "not a table" end, {}), "not a table",
            "a non-table return must pass through untouched")
        f.restore()
    end)

    H.test("a level with no chest distribution gets a balanced fallback, once", function()
        local f = installed()
        local level = rawget(_G, "LevelSettings").cemetery_tzeentch_path1
        local drc = {
            _run_state = { get_current_node_key = function() return "n1" end },
            _get_graph_data = function()
                return { n1 = { level = "cemetery_tzeentch_path1", level_seed = 9 } }
            end,
        }
        f.mod._ct_ensure_deus_chest_distribution(drc)
        H.deep_equal(level.deus_weapon_chest_distribution, { u = 1, m = 1, r = 1, p = 1 })
        local first = level.deus_weapon_chest_distribution
        f.mod._ct_ensure_deus_chest_distribution(drc)
        H.equal(level.deus_weapon_chest_distribution, first,
            "the fallback must be idempotent, never re-injected over itself")
        f.restore()
    end)

    H.test("the custom altar mix is built, seeded and shuffled off the node level_seed", function()
        local f = installed({ settings = {
            chest_upgrade_count = 2,
            chest_swap_melee_count = -1,
            chest_swap_ranged_count = 1,
            chest_power_up_count = 0,
        } })
        local drc = {
            _deus_weapon_chest_distribution = nil,
            _run_state = { get_current_node_key = function() return "n1" end },
            _get_graph_data = function()
                return { n1 = { level = "cemetery_tzeentch_path1", level_seed = 9 } }
            end,
        }
        local vanilla_called = false
        local chest = f.hooks["DeusRunController.get_deus_weapon_chest_type"](
            function() vanilla_called = true return "vanilla" end, drc)
        H.equal(vanilla_called, false, "a custom mix must not fall through to vanilla")
        -- 2 upgrade + 0 melee (Default) + 1 ranged + 0 power_up = { u, u, r }.
        H.equal(chest, "r", "the last shuffled entry must be popped and returned")
        H.equal(drc._deus_weapon_chest_distribution.__shuffled, true,
            "the distribution must be shuffled before the pop")
        H.deep_equal(drc._deus_weapon_chest_distribution, { "u", "u", __shuffled = true },
            "Default (-1) contributes zero; the popped entry is removed")
        f.restore()
    end)

    H.test("an all-Default altar mix falls through to vanilla", function()
        local f = installed({ settings = {
            chest_upgrade_count = -1,
            chest_swap_melee_count = -1,
            chest_swap_ranged_count = -1,
            chest_power_up_count = -1,
        } })
        local drc = {
            _run_state = { get_current_node_key = function() return "n1" end },
            _get_graph_data = function()
                return { n1 = { level = "cemetery_tzeentch_path1", level_seed = 9 } }
            end,
        }
        H.equal(f.hooks["DeusRunController.get_deus_weapon_chest_type"](
            function() return "vanilla" end, drc), "vanilla")
        f.restore()
    end)

    -- ------------------------------------------------------------------
    -- Contract: every injected dependency is load-bearing
    -- ------------------------------------------------------------------
    H.test("dropping any ctx key fails at install, not silently at runtime", function()
        local keys = {
            "capture_returns", "dbg", "defeat_recovery_triggered",
            "effective_setting", "is_curse_disabled", "rt_register",
        }
        for _, key in ipairs(keys) do
            local saved = snapshot_globals()
            install_globals()
            local f = fixture()
            f.ctx[key] = nil
            local ok, err = pcall(load_install(), f.mod, f.ctx)
            restore_globals(saved)
            H.equal(ok, false, "install must reject a context missing " .. key)
            H.truthy(tostring(err):find("ctx." .. key, 1, true),
                "the assert for " .. key .. " must name the missing key")
        end
        local saved = snapshot_globals()
        install_globals()
        local ok = pcall(load_install(), {}, nil)
        restore_globals(saved)
        H.equal(ok, false, "install must reject a missing context table")
    end)

    H.test("installing leaves no test global behind and the module leaks nothing", function()
        local before = {}
        for key in pairs(_G) do before[key] = true end
        local f = installed()
        f.restore()
        local leaked = {}
        for key in pairs(_G) do
            if not before[key] then leaked[#leaked + 1] = key end
        end
        table.sort(leaked)
        H.deep_equal(leaked, {}, "the owner must not leak a name into _G")
    end)
end
