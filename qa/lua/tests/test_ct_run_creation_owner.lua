-- Guards the #1159 run-creation owner extraction: everything ct does at the
-- moment a Chaos Wastes run is CREATED - the v0.7.95 starting-coins SETTER on
-- both the setup_run argument and the host-side
-- rpc_deus_set_initial_soft_currency handler, the per-controller
-- progressive-difficulty base with the get_run_difficulty ramp that reads it,
-- the per-run ledgers wiped at run start, the run-start reporting, and the
-- generate_random_power_ups roll whose boon-altar no-repeat ledger setup_run
-- creates - moved out of the ct_dev entry into _ct_run_creation_owner.lua.
--
-- ONE contiguous chunk moved (old entry lines 2210-2709, 500 raw / 466 non-empty
-- lines, MD5 e0b45d545562537671135c60e7882085 over the pristine `git archive`
-- bytes) and the installer sits at the exact line it occupied, between the
-- settings-dump block above and the _ct_boon_offer_view_owner install below, so
-- there is no load-order deviation to argue about. The chunk carries three
-- sibling loads (_ct_progressive_difficulty, _ct_replacement_runtime,
-- _ct_journey_difficulty_guard) because they were interleaved BETWEEN the hooks
-- and splitting them out would have reordered seven hook registrations; the
-- executable fixture below pins that they are still requested, once each, in the
-- original order.
--
-- There is exactly ONE code deviation and this file is what pins it. setup_run
-- used to record which run its coin setter fired for by assigning the entry local
-- `_starting_coins_applied_for_run`; the inline
-- `starting_coins_value_matches_setting` regression check reads that same slot as
-- an upvalue and deliberately stays in the entry. Re-declaring the local here
-- would split one slot into two, and the failure mode is SILENT: the inline check
-- returns nil (no-op PASS) whenever the slot does not match the live run id, so a
-- disconnected write disarms the verify instead of failing it. The owner
-- therefore calls an injected accessor over the entry's single slot, and the
-- deviation test below carries a MUTATION CONTROL: the same setup_run drive is
-- repeated against a no-op accessor, and the two outcomes must differ. Without
-- that control the positive assertion could pass against a dead wire
-- (PROJECT_STANDARDS.md 5.1d rule 2).
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_run_creation_owner.lua"

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

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_run_creation_owner.lua")

    local coins_policy = assert(loadfile(root .. "_ct_starting_coins_policy.lua"))()

    -- ------------------------------------------------------------------
    -- Executable fixture. The module registers three hooks, loads three
    -- siblings, defines two mod._ct_* helpers and writes one marker global at
    -- install time. Nothing here reaches the engine: the three siblings are
    -- stubbed so this file guards THIS seam, not theirs.
    -- ------------------------------------------------------------------
    local GLOBAL_KEYS = {
        "Managers", "printf", "DeusPowerUpAvailabilityTypes", "DeusPowerUpsArray",
        "DeusPowerUpsArrayByRarity", "Difficulties", "DifficultyLookup",
        "CT_PROGRESSIVE_DIFFICULTY_MARKER", "_ct_cursed_chest_seq",
        "_ct_cot_block_last", "_ct_cot_trial_last",
    }

    local function with_globals(overrides, body)
        local saved = {}
        for _, key in ipairs(GLOBAL_KEYS) do saved[key] = rawget(_G, key) end
        rawset(_G, "Managers", { player = { is_server = true } })
        rawset(_G, "printf", function() end)
        rawset(_G, "DeusPowerUpAvailabilityTypes",
            { cursed_chest = "cursed_chest", weapon_chest = "weapon_chest" })
        rawset(_G, "Difficulties", {})
        rawset(_G, "DifficultyLookup", {})
        rawset(_G, "_ct_cursed_chest_seq", 7)
        rawset(_G, "_ct_cot_block_last", { stale = true })
        rawset(_G, "_ct_cot_trial_last", { stale = true })
        for key, value in pairs(overrides or {}) do rawset(_G, key, value) end
        local ok, failure = xpcall(body, debug.traceback)
        for _, key in ipairs(GLOBAL_KEYS) do rawset(_G, key, saved[key]) end
        if not ok then error(failure, 0) end
    end

    -- Builds a stub `mod` plus a ctx, installs the module for real, and returns
    -- everything the assertions need. `ctx_overrides` replaces individual ctx
    -- values (the sentinel "\0drop" removes the key so the load-time assert can
    -- be exercised).
    local function fixture(ctx_overrides, settings)
        settings = settings or {}
        local hooks, order, dofiles, warnings, resyncs = {}, {}, {}, {}, {}
        local recorded_run = { value = nil }

        local progressive = {
            install_hot_join = function(m, schema)
                order[#order + 1] = "install_hot_join:" .. tostring(schema)
            end,
            difficulty = function(start_key, completed)
                return tostring(start_key) .. "+" .. tostring(completed)
            end,
        }
        local replacement = {}
        replacement.install = function(m, install_ctx)
            order[#order + 1] = "replacement_install"
            replacement.seen_ctx = install_ctx
        end

        local mod = {}
        function mod:dofile(path)
            local name = path:match("([^/]+)$")
            dofiles[#dofiles + 1] = name
            order[#order + 1] = "dofile:" .. name
            if name == "_ct_progressive_difficulty" then return progressive end
            if name == "_ct_replacement_runtime" then return replacement end
            if name == "_ct_journey_difficulty_guard" then
                return function() order[#order + 1] = "journey_guard_installed" end
            end
            error("unexpected dofile: " .. tostring(path))
        end
        function mod:hook(class_name, method_name, callback)
            local key = class_name .. "." .. method_name
            hooks[key] = callback
            order[#order + 1] = "hook:" .. key
        end
        function mod:get(key) return settings[key] end
        function mod:warning(fmt, ...) warnings[#warnings + 1] = string.format(fmt, ...) end
        mod._ct_starting_coins_policy = coins_policy
        mod._ct_boon_price_audit_once = function() end
        mod._ct_bot_economy_active = function() return false end
        mod._ct_bot_economy_seed_all = function() end
        mod._ct_broadcast_host_settings = function() end
        mod._ct128_strip_parry_cooldowns = function() resyncs[#resyncs + 1] = "parry" end

        -- The three sync_ helpers are the by-value regression control: each target
        -- is assigned only AFTER install, exactly as the entry assigns them ~2400
        -- lines below the install site. A by-value capture would freeze nil here.
        local late = {}
        local ctx = {
            altar_reuse = { reset_uses = function() resyncs[#resyncs + 1] = "reset_uses" end },
            bomb_boon_names = { deus_bomb_a = true, deus_bomb_b = true },
            build_local_manifest = function() return { manifest = true } end,
            chest_default = 3,
            dbg = function() end,
            dbg_alert = function() end,
            effective_setting = function(key) return settings[key] end,
            log_peer_manifest = function(peer) resyncs[#resyncs + 1] = "manifest:" .. tostring(peer) end,
            real_player_local_id = 1,
            rpc_schema = 1,
            shrine_default = 4,
            starting_coins_applied_for_run = function(value)
                if value ~= nil then recorded_run.value = value end
                return recorded_run.value
            end,
            sync_bomb_cooldown = function() return late.bomb() end,
            sync_boon_movespeed = function() return late.move() end,
            sync_reckless_swings = function() return late.reckless() end,
        }
        for key, value in pairs(ctx_overrides or {}) do
            if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
        end

        local installer = assert(loadfile(module_path))()
        installer(mod, ctx)

        -- Filled only now, so the wrappers must resolve at CALL time.
        late.bomb = function() resyncs[#resyncs + 1] = "bomb_cooldown" end
        late.move = function() resyncs[#resyncs + 1] = "boon_movespeed" end
        late.reckless = function() resyncs[#resyncs + 1] = "reckless_swings" end

        return {
            mod = mod, ctx = ctx, hooks = hooks, order = order, dofiles = dofiles,
            warnings = warnings, resyncs = resyncs, recorded_run = recorded_run,
            replacement = replacement,
        }
    end

    -- A minimal run controller. setup_run reads self._run_state for the run id
    -- and the bot-economy gate; get_run_difficulty reads the ramp state it wrote.
    local function controller(run_id)
        return {
            _run_state = {
                get_run_id = function() return run_id end,
                is_server = function() return true end,
                get_completed_level_count = function() return 0 end,
            },
        }
    end

    -- Vanilla setup_run signature:
    -- (run_seed, difficulty, journey_name, dominant_god, initial_own_soft_currency,
    --  telemetry_id, with_belakor, mutators, boons)
    -- The trailing `mutators` (args[8]) and `boons` (args[9]) are passed as
    -- explicit nils here because that is the real shape at most call sites and the
    -- exact reason the hook captures select("#", ...) instead of using bare
    -- unpack: a bare unpack stops at the first nil hole and silently drops the
    -- rest of the forwarded arguments.
    local function drive_setup_run(f, self, initial_coins, difficulty)
        local seen
        local function vanilla(_, ...) seen = { n = select("#", ...), ... } return "a", "b" end
        local a, b = f.hooks["DeusRunController.setup_run"](
            vanilla, self, 4242, difficulty or "hardest", "journey_citadel",
            "khorne", initial_coins, "telemetry", false, nil, nil)
        return seen, a, b
    end

    -- ------------------------------------------------------------------
    -- Install-time shape: hooks, load order, published surface
    -- ------------------------------------------------------------------
    H.test("install registers exactly its three hooks in the original order", function()
        with_globals({}, function()
            local f = fixture()
            H.deep_equal(f.order, {
                "dofile:_ct_progressive_difficulty",
                "install_hot_join:1",
                "hook:DeusRunController.get_run_difficulty",
                "dofile:_ct_replacement_runtime",
                "replacement_install",
                "dofile:_ct_journey_difficulty_guard",
                "journey_guard_installed",
                "hook:DeusRunController.setup_run",
                "hook:DeusRunController.rpc_deus_set_initial_soft_currency",
                "hook:DeusPowerUpUtils.generate_random_power_ups",
            })
            -- Each sibling is loaded exactly once. mod:dofile is not a singleton,
            -- so a second request would re-execute a module and double-register
            -- the seven hooks those three own.
            H.deep_equal(f.dofiles, {
                "_ct_progressive_difficulty",
                "_ct_replacement_runtime",
                "_ct_journey_difficulty_guard",
            })
        end)
    end)

    H.test("install publishes the two shared mod._ct_* helpers and the marker", function()
        with_globals({}, function()
            local f = fixture()
            H.equal(type(f.mod._ct_boon_disabled), "function")
            H.equal(type(f.mod._ct_extend_arity_for_forced_rarity), "function")
            H.equal(type(f.mod._ct_progdiff_step), "function")
            H.equal(rawget(_G, "CT_PROGRESSIVE_DIFFICULTY_MARKER"),
                "progressive_difficulty:per_controller_start_hotjoin_sync_contiguous_tiers_v3")
            -- The replacement runtime still receives the two values it always did.
            H.equal(f.replacement.seen_ctx.real_player_local_id, 1)
            H.equal(type(f.replacement.seen_ctx.effective_setting), "function")
        end)
    end)

    H.test("install refuses a missing or malformed ctx at load time", function()
        with_globals({}, function()
            local installer = assert(loadfile(module_path))()
            H.equal(pcall(installer, {}, nil), false, "nil ctx must assert")
            H.equal(pcall(installer, {}, "nope"), false, "non-table ctx must assert")
            for _, key in ipairs({
                "dbg", "dbg_alert", "effective_setting", "altar_reuse",
                "build_local_manifest", "log_peer_manifest",
                "starting_coins_applied_for_run", "sync_reckless_swings",
                "sync_bomb_cooldown", "sync_boon_movespeed", "bomb_boon_names",
                "shrine_default", "chest_default", "real_player_local_id",
                "rpc_schema",
            }) do
                H.equal(pcall(function() return fixture({ [key] = "\0drop" }) end), false,
                    "a dropped ctx." .. key .. " must assert")
            end
            -- reset_uses is called once per RUN, so a ledger table that lost the
            -- export must fail at LOAD, not mid-expedition.
            H.equal(pcall(function() return fixture({ altar_reuse = {} }) end), false,
                "an altar_reuse table without reset_uses must assert at install")
        end)
    end)

    -- ------------------------------------------------------------------
    -- THE ONE DEVIATION, with its mutation control
    -- ------------------------------------------------------------------
    H.test("the run-start coin marker is written through the entry's single slot", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 300 })
            H.equal(f.recorded_run.value, nil, "nothing recorded before a run starts")
            drive_setup_run(f, controller("run-abc"), 200)
            H.equal(f.recorded_run.value, "run-abc",
                "setup_run must drive the injected accessor with the live run id")

            -- MUTATION CONTROL: the same drive against an accessor that ignores
            -- writes. If this ALSO reported "run-abc" the assertion above would be
            -- measuring the fixture, not the wire; if the owner re-declared its own
            -- local the entry slot would look exactly like this - permanently nil -
            -- and the inline starting_coins_value_matches_setting check would
            -- silently degrade to a no-op PASS.
            local dead = { value = nil }
            local g = fixture({
                starting_coins_applied_for_run = function() return dead.value end,
            }, { starting_coins = 300 })
            drive_setup_run(g, controller("run-abc"), 200)
            H.equal(dead.value, nil, "the control must NOT record")
            H.truthy(f.recorded_run.value ~= dead.value,
                "positive and control outcomes must differ, or the test is vacuous")
        end)
    end)

    -- ------------------------------------------------------------------
    -- Starting coins: a SETTER, never an adder (v0.7.95)
    -- ------------------------------------------------------------------
    H.test("a configured starting-coins value replaces the vanilla argument exactly", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 300 })
            -- Vanilla rolls 200 over from the prior run. The bug this fix closed
            -- displayed 500; the setter must hand vanilla exactly 300.
            local seen, a, b = drive_setup_run(f, controller("r1"), 200)
            H.equal(seen[5], 300)
            H.equal(seen.n, 9, "explicit arity must survive so trailing nils stay positional")
            H.equal(seen[7], false, "the with_belakor flag must not be eaten by a nil hole")
            H.equal(seen[8], nil)
            H.equal(seen[9], nil)
            H.equal(a, "a")
            H.equal(b, "b", "both vanilla returns must be forwarded")
        end)
    end)

    H.test("zero is a real configured total, not a sentinel for rollover", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 0 })
            local seen = drive_setup_run(f, controller("r2"), 175)
            H.equal(seen[5], 0)
            H.equal(f.recorded_run.value, "r2")
        end)
    end)

    H.test("an invalid setting fails open to vanilla and records nothing", function()
        with_globals({}, function()
            for _, bad in ipairs({ "nope", -1, 3001, 12.5 }) do
                local f = fixture(nil, { starting_coins = bad })
                local seen = drive_setup_run(f, controller("r3"), 175)
                H.equal(seen[5], 175, "invalid value must preserve the vanilla argument")
                H.equal(f.recorded_run.value, nil,
                    "an unapplied setter must not claim the run")
            end
        end)
    end)

    H.test("the host RPC handler enforces the host setting for a joining peer", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 250 })
            local seen
            local function vanilla(_, channel, coins) seen = { channel, coins } end
            f.hooks["DeusRunController.rpc_deus_set_initial_soft_currency"](
                vanilla, {}, 11, 40)
            H.deep_equal(seen, { 11, 250 })

            -- Invalid host setting: the client's own value survives untouched.
            local g = fixture(nil, { starting_coins = "nope" })
            g.hooks["DeusRunController.rpc_deus_set_initial_soft_currency"](
                vanilla, {}, 11, 40)
            H.deep_equal(seen, { 11, 40 })
        end)
    end)

    -- ------------------------------------------------------------------
    -- Progressive difficulty: per-controller base, hot-join handoff
    -- ------------------------------------------------------------------
    H.test("setup_run captures the run's true starting tier onto the controller", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 100 })
            local rc = controller("r4")
            drive_setup_run(f, rc, 0, "cataclysm")
            H.equal(rc._ct_progdiff_start, "cataclysm")
            H.equal(rc._ct_progdiff_last_logged, nil)
        end)
    end)

    H.test("a hot-join base outranks the setup_run argument and is consumed once", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 100 })
            f.mod._ct_progdiff_pending_host_start = "harder"
            local rc = controller("r5")
            drive_setup_run(f, rc, 0, "cataclysm")
            H.equal(rc._ct_progdiff_start, "harder")
            H.equal(f.mod._ct_progdiff_pending_host_start, nil,
                "the parked value must be cleared so a later run cannot inherit it")
        end)
    end)

    H.test("the ramp reads the captured base and both toggles gate it", function()
        with_globals({}, function()
            local f = fixture(nil, {
                progressive_difficulty = true, progressive_difficulty_increase = true,
            })
            local rc = controller("r6")
            rc._ct_progdiff_start = "hard"
            local function vanilla() return "normal" end
            H.equal(f.hooks["DeusRunController.get_run_difficulty"](vanilla, rc), "hard+0")

            -- Either toggle off returns vanilla untouched.
            for _, off in ipairs({
                { progressive_difficulty = false, progressive_difficulty_increase = true },
                { progressive_difficulty = true, progressive_difficulty_increase = false },
            }) do
                local g = fixture(nil, off)
                local grc = controller("r6")
                grc._ct_progdiff_start = "hard"
                H.equal(g.hooks["DeusRunController.get_run_difficulty"](vanilla, grc), "normal")
            end
        end)
    end)

    -- ------------------------------------------------------------------
    -- Run-start resets
    -- ------------------------------------------------------------------
    H.test("run start wipes every per-run ledger", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 100 })
            f.mod._ct_boon_altar_taken_boons = { deus_old = true }
            drive_setup_run(f, controller("r7"), 0)
            H.deep_equal(f.mod._ct_boon_altar_taken_boons, {})
            H.deep_equal(f.mod._ct_replacement_cache, {})
            H.deep_equal(f.mod._ct_replacement_pending_humans, {})
            H.equal(f.mod._ct_replacement_log_count, 0)
            H.equal(f.mod._ct_bot_economy_log_count, 0)
            H.deep_equal(f.mod._ct_bot_economy_initialized, {})
            -- The three per-mission trackers are GLOBALS shared with
            -- _ct_combat_hooks and _ct_node_entry_owner, so the wipe must land on
            -- _G, not on a module-local shadow.
            H.equal(rawget(_G, "_ct_cursed_chest_seq"), 0)
            H.deep_equal(rawget(_G, "_ct_cot_block_last"), {})
            H.deep_equal(rawget(_G, "_ct_cot_trial_last"), {})
            -- The altar ledger is rebound through the injected accessor.
            local saw_reset = false
            for _, tag in ipairs(f.resyncs) do
                if tag == "reset_uses" then saw_reset = true end
            end
            H.truthy(saw_reset, "the altar reuse ledger must be rebound at run start")
        end)
    end)

    H.test("the host logs its own manifest baseline; a client does not", function()
        with_globals({}, function()
            local f = fixture(nil, { starting_coins = 100 })
            drive_setup_run(f, controller("r8"), 0)
            local saw = false
            for _, tag in ipairs(f.resyncs) do
                if tag == "manifest:self (host)" then saw = true end
            end
            H.truthy(saw, "the host baseline manifest must still be logged")
        end)
        with_globals({ Managers = { player = { is_server = false } } }, function()
            local f = fixture(nil, { starting_coins = 100 })
            drive_setup_run(f, controller("r9"), 0)
            for _, tag in ipairs(f.resyncs) do
                H.truthy(tag:sub(1, 9) ~= "manifest:",
                    "a client must not log a host manifest baseline")
            end
        end)
    end)

    -- ------------------------------------------------------------------
    -- The boon roll
    -- ------------------------------------------------------------------
    local function roll_fixture(settings, pool)
        local f = fixture(nil, settings)
        rawset(_G, "DeusPowerUpsArray", pool.main)
        rawset(_G, "DeusPowerUpsArrayByRarity", pool.by_rarity)
        return f
    end

    local function boon(name) return { name = name } end

    H.test("the shrine and chest defaults are the only counts overridden", function()
        with_globals({}, function()
            local f = roll_fixture({ shrine_boon_count = 6, chest_boon_count = 2 },
                { main = {}, by_rarity = {} })
            local seen
            local function vanilla(...) seen = { ... } return "seed", {} end
            local hook = f.hooks["DeusPowerUpUtils.generate_random_power_ups"]
            hook(vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.equal(seen[2], 6)
            hook(vanilla, 999999, 3, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.equal(seen[2], 2)
            -- A non-default count belongs to some other call site: leave it alone.
            hook(vanilla, 999999, 7, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.equal(seen[2], 7)
        end)
    end)

    H.test("the disabled-boon strip removes and then EXACTLY restores both arrays", function()
        with_globals({}, function()
            local keep_a, drop, keep_b = boon("deus_keep_a"), boon("deus_banned"), boon("deus_keep_b")
            local rare = { keep_a, drop, keep_b }
            local pool = {
                main = { keep_a, drop, keep_b },
                by_rarity = { rare = rare },
            }
            local f = roll_fixture({ disable_boon_deus_banned = true }, pool)
            local during
            local function vanilla()
                during = {}
                for i, b in ipairs(rawget(_G, "DeusPowerUpsArray")) do during[i] = b.name end
                return "seed", {}
            end
            f.hooks["DeusPowerUpUtils.generate_random_power_ups"](
                vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.deep_equal(during, { "deus_keep_a", "deus_keep_b" },
                "the banned boon must be absent while vanilla samples")
            -- Restored by identity AND position, in both arrays.
            H.deep_equal(rawget(_G, "DeusPowerUpsArray"), { keep_a, drop, keep_b })
            H.deep_equal(rare, { keep_a, drop, keep_b })
        end)
    end)

    H.test("a vanilla error restores the arrays before re-raising", function()
        with_globals({}, function()
            local keep, drop = boon("deus_keep"), boon("deus_banned")
            local rare = { keep, drop }
            local f = roll_fixture({ disable_boon_deus_banned = true },
                { main = { keep, drop }, by_rarity = { rare = rare } })
            local function vanilla() error("vanilla exploded") end
            local ok = pcall(f.hooks["DeusPowerUpUtils.generate_random_power_ups"],
                vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.equal(ok, false, "the error must be re-raised, not swallowed")
            H.deep_equal(rawget(_G, "DeusPowerUpsArray"), { keep, drop },
                "a partial strip must never outlive the failed roll")
            H.deep_equal(rare, { keep, drop })
            H.equal(#f.warnings >= 1, true)
        end)
    end)

    H.test("the boon-altar no-repeat set filters only weapon_chest rolls", function()
        with_globals({}, function()
            local fresh, taken = boon("deus_fresh"), boon("deus_taken")
            local pool = { main = { fresh, taken }, by_rarity = {} }
            local f = roll_fixture({}, pool)
            f.mod._ct_boon_altar_taken_boons = { deus_taken = true }
            local during
            local function vanilla()
                during = {}
                for i, b in ipairs(rawget(_G, "DeusPowerUpsArray")) do during[i] = b.name end
                return "seed", {}
            end
            local hook = f.hooks["DeusPowerUpUtils.generate_random_power_ups"]
            hook(vanilla, 999999, 4, {}, "hard", 0.5, "weapon_chest", "es_huntsman")
            H.deep_equal(during, { "deus_fresh" })
            -- A shrine roll from the same altar-taken state is untouched.
            hook(vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.deep_equal(during, { "deus_fresh", "deus_taken" })
        end)
    end)

    H.test("bomb-boon exclusivity strips the rest once the player owns one", function()
        with_globals({}, function()
            local bomb_a, bomb_b, other = boon("deus_bomb_a"), boon("deus_bomb_b"), boon("deus_other")
            local pool = { main = { bomb_a, bomb_b, other }, by_rarity = {} }
            local f = roll_fixture({ bomb_boon_exclusive = true }, pool)
            local during
            local function vanilla()
                during = {}
                for i, b in ipairs(rawget(_G, "DeusPowerUpsArray")) do during[i] = b.name end
                return "seed", {}
            end
            local hook = f.hooks["DeusPowerUpUtils.generate_random_power_ups"]
            hook(vanilla, 999999, 4, { bomb_a }, "hard", 0.5, "shrine", "es_huntsman")
            H.deep_equal(during, { "deus_other" })
            -- Owning no bomb boon leaves the pool whole.
            hook(vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.deep_equal(during, { "deus_bomb_a", "deus_bomb_b", "deus_other" })
        end)
    end)

    H.test("the Belakor temple forces unique AND extends the arity that carries it", function()
        with_globals({}, function()
            local f = roll_fixture({}, { main = {}, by_rarity = {} })
            -- #134: the cursed-chest call site passes only 7 args, so writing
            -- args[8] without extending n drops the forced rarity at the forward
            -- unpack. Assert the ARGUMENT vanilla received, not the write.
            local seen
            local function vanilla(...) seen = { n = select("#", ...), ... } return "seed", {} end
            rawset(_G, "Managers", {
                player = { is_server = true },
                mechanism = {
                    game_mechanism = function()
                        return {
                            get_deus_run_controller = function()
                                return {
                                    _run_state = {
                                        get_arena_belakor_node = function() return "node_9" end,
                                        get_current_node_key = function() return "node_9" end,
                                    },
                                }
                            end,
                        }
                    end,
                },
            })
            f.hooks["DeusPowerUpUtils.generate_random_power_ups"](
                vanilla, 999999, 3, {}, "hard", 0.5, "cursed_chest")
            H.equal(seen.n, 8, "n must be extended to carry args[8]")
            H.equal(seen[8], "unique")
            H.equal(f.mod._ct_extend_arity_for_forced_rarity(7), 8)
            H.equal(f.mod._ct_extend_arity_for_forced_rarity(9), 9,
                "a longer real arity must never be truncated")
        end)
    end)

    H.test("every post-roll re-sync resolves through its late-binding wrapper", function()
        with_globals({}, function()
            local f = roll_fixture({}, { main = {}, by_rarity = {} })
            local function vanilla() return "seed", {} end
            f.hooks["DeusPowerUpUtils.generate_random_power_ups"](
                vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.deep_equal(f.resyncs,
                { "reckless_swings", "bomb_cooldown", "boon_movespeed", "parry" })
        end)
    end)

    H.test("a missing parry-cooldown strip warns instead of crashing the roll", function()
        with_globals({}, function()
            local f = roll_fixture({}, { main = {}, by_rarity = {} })
            f.mod._ct128_strip_parry_cooldowns = nil
            local function vanilla() return "seed", {} end
            local seed = f.hooks["DeusPowerUpUtils.generate_random_power_ups"](
                vanilla, 999999, 4, {}, "hard", 0.5, "shrine", "es_huntsman")
            H.equal(seed, "seed", "the roll must still return its result")
            H.equal(#f.warnings, 1)
            H.truthy(f.warnings[1]:find("parry-cooldown strip unavailable", 1, true))
        end)
    end)

    H.test("the shared disable predicate truthy-normalizes and tolerates nil", function()
        with_globals({}, function()
            local f = fixture(nil, {
                disable_boon_deus_banned = true, disable_boon_deus_zero = 0,
            })
            H.equal(f.mod._ct_boon_disabled("deus_banned"), true)
            H.equal(f.mod._ct_boon_disabled("deus_zero"), true, "0 is truthy in Lua")
            H.equal(f.mod._ct_boon_disabled("deus_other"), false)
            H.equal(f.mod._ct_boon_disabled(nil), false)
        end)
    end)

    -- ------------------------------------------------------------------
    -- Boundaries: what this owner must NOT carry
    -- ------------------------------------------------------------------
    H.test("owner carries no command, no RPC registration and no regression check", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
        H.equal(count_plain(owner, "local _RT_CHECKS"), 0)
        -- Assignment form, not the bare name: the moved chunk's comments NAME
        -- mod.on_setting_changed on purpose (the host-settings broadcast helper is
        -- shared with it), and forbidding the word would forbid documenting the
        -- boundary. What must not exist is a second OWNER of the callback.
        H.equal(count_plain(owner, "mod.on_setting_changed = "), 0)
        H.equal(count_plain(owner, "mod.on_disabled = "), 0)
        H.equal(count_plain(owner, "mod.on_enabled = "), 0)
        H.equal(count_plain(owner, "mod.update = "), 0)
    end)

    H.test("the settings-sync / graph-snapshot / peer-manifest transports stay in the entry", function()
        -- Out of scope for this slice: they need a 2-player window to validate.
        -- Their mutable state is an entry file-local, so reading it from this chunk
        -- would capture a stale nil. The owner only CALLS the two manifest helpers,
        -- through injected by-value bindings.
        for _, needle in ipairs({
            "_ct_host_settings", "_ct_host_graph_snapshot", "_ct_peer_manifests",
            "_sync_inbound", "_ct_graph_inbound", "_ct_manifest_inbound",
            "ct_sync_host_settings_chunk", "ct_graph_snapshot_chunk",
            "ct_peer_manifest_chunk",
        }) do
            H.equal(count_plain(owner, needle), 0,
                needle .. " must not appear in the run-creation owner")
        end
        for _, needle in ipairs({
            'mod:network_register("ct_sync_host_settings_chunk"',
            'mod:network_register("ct_graph_snapshot_chunk"',
            'mod:network_register("ct_peer_manifest_chunk"',
        }) do
            H.equal(count_plain(entry, needle), 1, needle .. " stays in the entry")
        end
    end)

    H.test("the moved hooks and helpers left the entry entirely", function()
        for _, needle in ipairs({
            'mod:hook("DeusRunController", "setup_run"',
            'mod:hook("DeusRunController", "get_run_difficulty"',
            'mod:hook("DeusRunController", "rpc_deus_set_initial_soft_currency"',
            'mod:hook("DeusPowerUpUtils", "generate_random_power_ups"',
            "function mod._ct_boon_disabled(name)",
            "function mod._ct_extend_arity_for_forced_rarity(n)",
            "CT_PROGRESSIVE_DIFFICULTY_MARKER =",
        }) do
            H.equal(count_plain(entry, needle), 0, "entry must not keep " .. needle)
            H.equal(count_plain(owner, needle), 1, "owner must hold " .. needle .. " once")
        end
    end)

    H.test("no sibling ct_dev script re-registers any of the four moved pairs", function()
        -- VMF silently DROPS a second registration on a (Class, method) pair - that
        -- is how the v0.7.129/.130 altar-reuse fix shipped dead for two releases.
        -- The roster is every ct_dev script except this owner, so a future sibling
        -- that starts hooking one of these four is caught the moment it is added
        -- here, and the floor makes a silently shrinking roster fail rather than
        -- pass vacuously.
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
            "_ct_journey_difficulty_guard", "_ct_level_load_owner",
            "_ct_mechanic_tweaks", "_ct_meta_trait_boons", "_ct_miasma",
            "_ct_miasma_policy", "_ct_modifier_stack_audit", "_ct_modifier_stack_policy",
            "_ct_node_entry_owner", "_ct_parry_cooldown_policy",
            "_ct_pickup_population_owner", "_ct_pickup_spawn_owner",
            "_ct_pilgrimage_context", "_ct_profile_snapshot", "_ct_progressive_difficulty",
            "_ct_progressive_elite_audit", "_ct_progressive_elite_policy",
            "_ct_regression", "_ct_replacement_compensation", "_ct_replacement_runtime",
            "_ct_resume_audit", "_ct_resume_policy", "_ct_spawn_eligibility_owner",
            "_ct_start_shrine_policy", "_ct_start_shrine_runtime",
            "_ct_starting_coins_policy", "_ct_tab_collectibles_layout",
            "_ct_tab_panel_owner", "_ct_umbrella_policy", "_ct_weapon_trait_generation",
            "_ct_weave_curse_audit", "_ct_weave_curse_policy", "_ct_wire_policy",
            "_lib_peer_parity", "_lib_wire_catalog", "chaos_wastes_tweaker_dev_data",
            "chaos_wastes_tweaker_dev_localization", "chaos_wastes_tweaker_mutex",
        }
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
            ["DeusRunController.get_run_difficulty"] = true,
            ["DeusRunController.setup_run"] = true,
            ["DeusRunController.rpc_deus_set_initial_soft_currency"] = true,
            ["DeusPowerUpUtils.generate_random_power_ups"] = true,
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
        H.truthy(checked >= 76, "the sibling roster must still cover the whole mod")
    end)

    H.test("the entry crosses the late-filled slots as wrappers, never by value", function()
        -- The load-time ctx asserts catch a by-value capture of these five, but
        -- only IN GAME: offline nothing else reads the install site, so a
        -- `sync_reckless_swings = sync_reckless_swings` regression (nil at this
        -- position - the three sync_ slots are not filled until the boon-balance
        -- owner loads ~2400 lines below) would ship and only surface as a mod that
        -- refuses to load. Assert the wrapper form textually, scoped to this
        -- install block so the two sibling installs above cannot satisfy it.
        local at = assert(entry:find(
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner")',
            1, true))
        local close = assert(entry:find("\n})", at, true))
        local block = entry:sub(at, close + 2)
        for _, key in ipairs({
            "sync_reckless_swings", "sync_bomb_cooldown", "sync_boon_movespeed",
        }) do
            H.equal(count_plain(block,
                "    " .. key .. " = function() return " .. key .. "() end,"), 1,
                key .. " must cross as a late-binding wrapper")
            H.equal(count_plain(block, "    " .. key .. " = " .. key .. ","), 0,
                key .. " must not be captured by value")
        end
        H.equal(count_plain(block, "    dbg = function(...) return _dbg(...) end,"), 1)
        H.equal(count_plain(block, "    dbg_alert = function(...) return _dbg_alert(...) end,"), 1)
        -- The nine by-value crossings are assigned above this point and never
        -- reassigned, so the plain form is correct for them and a wrapper would be
        -- noise. Pin the two that would be easiest to get wrong.
        H.equal(count_plain(block, "    effective_setting = effective_setting,"), 1)
        H.equal(count_plain(block, "    altar_reuse = _ct_altar_reuse,"), 1)
    end)

    H.test("the installer is a named function called exactly once by the entry", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("return install", 1, true))
        H.equal(count_plain(owner, "return function("), 0,
            "an anonymous installer hides the contract from a reader and a grep")
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner")'), 1)
    end)
end
