-- Guards the #1159 chest-revive owner extraction: everything ct does to the
-- PARTY when a Chest of Trials completes moved VERBATIM out of the ct_dev entry
-- into _ct_chest_revive_owner.lua.
--
-- Two chunks moved (old entry lines 5781-5803 and 5814-6222) with a deliberate
-- gap: the six-line #350 block that dofiles _ct_cot_cost / _ct_cot_early_reward
-- sat between them and STAYED in the entry, because activation cost and reward
-- presentation are not completion recovery. That leaves exactly ONE load-order
-- deviation - the first chunk now runs after that block instead of before it -
-- and it is pinned twice below: `#350 block still loads first` fixes the entry
-- ordering, and `moved state is invisible to the #350 modules` proves nothing
-- on either side of the swap can observe it.
--
-- Everything else is executable rather than textual: the module is loaded for
-- real and installed against a recording stub, so a dropped hook, a by-value
-- effective_setting bind, a swallowed vanilla call, or an unbounded rescue job
-- fails here instead of in a Chaos Wastes run.
return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_chest_revive_owner.lua"

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

    local entry = read("chaos_wastes_tweaker_dev.lua")
    local owner = read("_ct_chest_revive_owner.lua")

    -- ------------------------------------------------------------------
    -- Executable fixture: load the real module and install it against a
    -- recording mod stub. The module only registers callbacks and assigns mod
    -- fields at load time, so nothing here reaches the engine.
    -- ------------------------------------------------------------------
    local POLICY_PATH = "scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_policy"

    local function fixture(overrides)
        overrides = overrides or {}
        local hooks, order, dofiles = {}, {}, {}
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
            H.equal(path, POLICY_PATH,
                "the owner may only load the pure lifecycle policy, not " .. tostring(path))
            return assert(loadfile(root .. "_ct_chest_revive_policy.lua"))()
        end

        local ctx = { effective_setting = function() return nil end }
        for key, value in pairs(overrides) do
            if value == "\0drop" then ctx[key] = nil else ctx[key] = value end
        end

        local installer = assert(loadfile(module_path))()
        local returned = installer(mod, ctx)
        return mod, hooks, order, dofiles, returned
    end

    -- The moved code reads engine globals. Swap in stubs for the duration of a
    -- test and always restore, so the suite stays order-independent.
    local function with_globals(globals, body)
        local names = { "Managers", "printf", "StatusUtils", "ScriptUnit", "Unit" }
        local saved = {}
        for _, name in ipairs(names) do saved[name] = rawget(_G, name) end
        for name, value in pairs(globals) do _G[name] = value end
        local ok, err = pcall(body)
        for _, name in ipairs(names) do _G[name] = saved[name] end
        if not ok then error(err, 0) end
    end

    -- ------------------------------------------------------------------
    -- Module shape
    -- ------------------------------------------------------------------
    H.test("chest-revive owner is a named ctx installer, not an anonymous chunk", function()
        H.truthy(owner:find("local function install(mod, ctx)", 1, true))
        H.truthy(owner:find("\nreturn install\n", 1, true))
        H.equal(count_plain(owner, "return function("), 0)
    end)

    H.test("owner is dofile'd exactly once by the entry", function()
        H.equal(count_plain(entry,
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_owner"), 1)
    end)

    H.test("owner owns no command, no RPC and no regression check", function()
        H.equal(count_plain(owner, "mod:command"), 0)
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, "_rt_register("), 0)
    end)

    -- ------------------------------------------------------------------
    -- The one load-order deviation, pinned from both sides
    -- ------------------------------------------------------------------
    H.test("#350 block still loads before the completion-only OPEN hook", function()
        local cost_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost", 1, true))
        local early_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_early_reward", 1, true))
        local owner_at = assert(entry:find(
            "scripts/mods/chaos_wastes_tweaker_dev/_ct_chest_revive_owner", 1, true))
        H.truthy(cost_at < owner_at, "_ct_cot_cost must install before the OPEN hook")
        H.truthy(early_at < owner_at, "_ct_cot_early_reward must install before the OPEN hook")
    end)

    H.test("moved state is invisible to the #350 modules, so the reorder is inert", function()
        -- The first moved chunk used to run BEFORE the #350 block and now runs
        -- after it. That is only safe while none of those modules can observe
        -- the state the chunk publishes.
        local moved_state = {
            "pending_chest_respawn",
            "CURSED_CHEST_STATE_OPEN",
            "DIFFICULTY_RECRUIT",
            "_ct_pending_team_teleport",
            "_ct_chest_revive_policy",
            "_ct299_",
        }
        for _, name in ipairs({
            "_ct_cot_cost.lua", "_ct_cot_early_reward.lua",
            "_ct_cot_cost_policy.lua", "_ct_cot_early_reward_core.lua",
        }) do
            local source = read(name)
            for _, token in ipairs(moved_state) do
                H.equal(count_plain(source, token), 0,
                    name .. " must not reference " .. token)
            end
        end
        -- And the policy the chunk loads is inert in the other direction: a
        -- pure table cannot perturb modules that loaded before it.
        local policy_source = read("_ct_chest_revive_policy.lua")
        H.equal(count_plain(policy_source, "mod:"), 0)
        H.equal(count_plain(policy_source, "hook"), 0)
    end)

    -- ------------------------------------------------------------------
    -- Hook cardinality and placement
    -- ------------------------------------------------------------------
    H.test("owner registers exactly its three hooks, with the original verbs", function()
        local _, hooks, order = fixture()
        H.deep_equal(order, {
            "safe:DeusCursedChestExtension._set_state",
            "hook:PlayerUnitHealthExtension.sync_health_state",
            "safe:RespawnHandler._respawn_player",
        })
        H.truthy(hooks["DeusCursedChestExtension._set_state"])
        H.truthy(hooks["PlayerUnitHealthExtension.sync_health_state"])
        H.truthy(hooks["RespawnHandler._respawn_player"])
    end)

    H.test("the three hooks left the entry and live only in the owner", function()
        for _, needle in ipairs({
            'mod:hook_safe("DeusCursedChestExtension", "_set_state"',
            'mod:hook("PlayerUnitHealthExtension", "sync_health_state"',
            'mod:hook_safe("RespawnHandler", "_respawn_player"',
        }) do
            H.equal(count_plain(entry, needle), 0, "entry must not re-register " .. needle)
            H.equal(count_plain(owner, needle), 1, "owner must register " .. needle .. " once")
        end
    end)

    H.test("the moved file-locals left the entry entirely", function()
        -- All three had ZERO references outside the moved region before the
        -- split. A copy left behind would shadow nothing and drift silently.
        for _, name in ipairs({
            "CURSED_CHEST_STATE_OPEN", "DIFFICULTY_RECRUIT", "pending_chest_respawn",
        }) do
            H.equal(count_plain(entry, name), 0, "entry must not still declare " .. name)
            H.truthy(owner:find("local " .. name, 1, true), "owner must declare " .. name)
        end
    end)

    -- ------------------------------------------------------------------
    -- The mod._ct* seams the entry reads across the chunk boundary
    -- ------------------------------------------------------------------
    H.test("install publishes every seam the entry resolves off mod", function()
        local mod, _, _, dofiles, returned = fixture()
        H.equal(returned, nil, "the owner deliberately returns nothing")
        H.deep_equal(dofiles, { POLICY_PATH })
        H.equal(type(mod._ct_pending_team_teleport), "table")
        H.equal(type(mod._ct_chest_revive_policy), "table")
        H.equal(mod._ct_chest_revive_policy.MARKER, "ct299:move_before_free_v1")
        H.equal(type(mod._ct299_arm), "function")
        H.equal(type(mod._ct299_process), "function")
        H.equal(type(mod._ct_chest_teleport_tick), "function")
    end)

    H.test("the entry still consumes those seams from both of its readers", function()
        -- mod.update tick + the regression check that stayed behind. If either
        -- reader is dropped the rescue silently never runs.
        H.equal(count_plain(entry, "mod._ct_chest_teleport_tick(dt)"), 1)
        H.equal(count_plain(entry,
            '_rt_register("issue299_chest_revive_team_teleport_ordered"'), 1)
        H.truthy(entry:find("mod._ct_chest_revive_policy", 1, true))
        H.truthy(entry:find("mod._ct299_arm", 1, true))
    end)

    -- ------------------------------------------------------------------
    -- ctx contract
    -- ------------------------------------------------------------------
    H.test("install refuses a missing or malformed ctx at load time", function()
        local installer = assert(loadfile(module_path))()
        H.equal(pcall(installer, {}, nil), false, "nil ctx must assert")
        H.equal(pcall(installer, {}, "nope"), false, "non-table ctx must assert")
        local ok = pcall(function() return fixture({ effective_setting = "\0drop" }) end)
        H.equal(ok, false, "a dropped ctx.effective_setting must assert")
    end)

    H.test("effective_setting is late-bound, so a by-value regression fails", function()
        -- The wrapper's target is assigned only AFTER install. A by-value bind
        -- would freeze nil here and every setting read would come back nil.
        local target
        local seen = {}
        local mod, hooks = fixture({
            effective_setting = function(id) return target(id) end,
        })
        target = function(id)
            seen[#seen + 1] = id
            return false
        end
        with_globals({ Managers = { player = { is_server = false } }, printf = nil }, function()
            hooks["DeusCursedChestExtension._set_state"](mod, 3)
        end)
        H.truthy(#seen > 0, "the OPEN hook must read the setting through the late binding")
        H.equal(seen[1], "respawn_on_chest_complete")
    end)

    -- ------------------------------------------------------------------
    -- Behaviour of the moved code
    -- ------------------------------------------------------------------
    H.test("only STATES.OPEN (3) triggers recovery", function()
        local reads = 0
        local mod, hooks = fixture({
            effective_setting = function() reads = reads + 1; return false end,
        })
        with_globals({ Managers = { player = { is_server = false } } }, function()
            for _, state in ipairs({ 0, 1, 2, 4 }) do
                hooks["DeusCursedChestExtension._set_state"](mod, state)
            end
            H.equal(reads, 0, "non-OPEN states must return before reading any setting")
            -- 4 is HOTJOIN_OPEN: a hot-joining client must never fire recovery.
            hooks["DeusCursedChestExtension._set_state"](mod, 3)
            H.truthy(reads > 0, "state 3 must reach the setting gate")
        end)
    end)

    H.test("the toggle gates recovery even on the host", function()
        local mod, hooks = fixture({ effective_setting = function() return false end })
        local touched = false
        with_globals({
            Managers = {
                player = { is_server = true },
                state = setmetatable({}, { __index = function() touched = true end }),
            },
        }, function()
            hooks["DeusCursedChestExtension._set_state"](mod, 3)
        end)
        H.equal(touched, false, "a disabled toggle must return before reading game state")
    end)

    H.test("the wrapping health hook always calls vanilla (guard is not bail)", function()
        local mod, hooks = fixture()
        local calls = 0
        local inner = function() calls = calls + 1 end
        local self_stub = {
            player = {
                network_id = function() return "peer-1" end,
                local_player_id = function() return 1 end,
            },
        }
        with_globals({ Managers = {} }, function()
            hooks["PlayerUnitHealthExtension.sync_health_state"](inner, self_stub)
        end)
        H.equal(calls, 1, "vanilla sync_health_state must run exactly once regardless")
    end)

    H.test("the respawn hook tolerates an absent player without throwing", function()
        local mod, hooks = fixture()
        with_globals({ Managers = {} }, function()
            hooks["RespawnHandler._respawn_player"](nil, nil, 1, 1, nil)
            hooks["RespawnHandler._respawn_player"](nil, {}, 1, 1, nil)
        end)
    end)

    -- ------------------------------------------------------------------
    -- The #299 rescue transaction
    -- ------------------------------------------------------------------
    H.test("arming rejects a job with no scalar chest anchor", function()
        local mod = fixture()
        with_globals({ Managers = {} }, function()
            H.equal(mod._ct299_arm("peer-1", 1, {}, nil, false), nil)
            H.equal(mod._ct299_arm("peer-1", 1, {}, { x = 1 }, false), nil)
            H.equal(next(mod._ct_pending_team_teleport), nil,
                "a rejected arm must not leave a pending job behind")
        end)
    end)

    H.test("an armed job is keyed by peer and local player", function()
        local mod = fixture()
        with_globals({ Managers = {} }, function()
            local entry_a = mod._ct299_arm("peer-1", 1, {}, { x = 1, y = 2, z = 3 }, false)
            local entry_b = mod._ct299_arm("peer-1", 2, {}, { x = 1, y = 2, z = 3 }, false)
            H.equal(entry_a.key, "peer-1/1")
            H.equal(entry_b.key, "peer-1/2")
            H.equal(mod._ct_pending_team_teleport["peer-1/1"], entry_a)
            H.equal(mod._ct_pending_team_teleport["peer-1/2"], entry_b)
        end)
    end)

    H.test("a client drops every pending rescue job on tick", function()
        -- The whole transaction is host-authoritative. A client that somehow
        -- armed one must not keep processing it.
        local mod = fixture()
        with_globals({ Managers = {} }, function()
            mod._ct299_arm("peer-1", 1, {}, { x = 1, y = 2, z = 3 }, false)
            H.truthy(next(mod._ct_pending_team_teleport))
            _G.Managers = { player = { is_server = false } }
            mod._ct_chest_teleport_tick(0)
            H.equal(next(mod._ct_pending_team_teleport), nil)
        end)
    end)

    H.test("the host keeps waiting for a unit that has not spawned yet", function()
        local mod = fixture()
        with_globals({
            Managers = { player = { is_server = true, player = function() return nil end } },
        }, function()
            mod._ct299_arm("peer-1", 1, {}, { x = 1, y = 2, z = 3 }, false)
            mod._ct_chest_teleport_tick(0)
            H.truthy(mod._ct_pending_team_teleport["peer-1/1"],
                "a dead player still awaiting RespawnHandler must be retained, not dropped")
        end)
    end)

    H.test("a rescue job is bounded by the policy timeout", function()
        local mod = fixture()
        with_globals({
            Managers = { player = { is_server = true, player = function() return nil end } },
        }, function()
            mod._ct299_arm("peer-1", 1, {}, { x = 1, y = 2, z = 3 }, false)
            mod._ct_chest_teleport_tick(mod._ct_chest_revive_policy.TIMEOUT_SECONDS + 1)
            H.equal(mod._ct_pending_team_teleport["peer-1/1"], nil,
                "a timed-out job must be dropped, never retried forever")
        end)
    end)

    H.test("repeated exceptions retire a job instead of spinning", function()
        local mod = fixture()
        local policy = mod._ct_chest_revive_policy
        with_globals({ Managers = {} }, function()
            -- next_action raising is the generic "something went wrong" path.
            local broken = { key = "k", peer_id = "p", lpid = 1, anchor = {}, errors = 0 }
            local saved = policy.next_action
            policy.next_action = function() error("boom") end
            local dropped
            for _ = 1, policy.MAX_ERRORS do
                dropped = mod._ct299_process("k", broken, 0)
            end
            policy.next_action = saved
            H.equal(dropped, true, "the job must retire at MAX_ERRORS, not loop")
            H.equal(broken.errors, policy.MAX_ERRORS)
        end)
    end)

    -- ------------------------------------------------------------------
    -- Boundaries against the other ct owners
    -- ------------------------------------------------------------------
    H.test("owner stays inside its engine class and out of its neighbours", function()
        -- A Chest of TRIALS is DeusCursedChestExtension. DeusChestExtension is
        -- the altar class and belongs to _ct_altar_reuse_owner /
        -- _ct_bot_weapon_chest_owner; a hook here would be a responsibility leak
        -- and VMF would silently drop whichever registration lost the race.
        H.equal(count_plain(owner, 'mod:hook("DeusChestExtension"'), 0)
        H.equal(count_plain(owner, 'mod:hook_safe("DeusChestExtension"'), 0)
        -- Activation cost and early reward stay with their own modules.
        H.equal(count_plain(owner, "cot_cost_amount"), 0)
        H.equal(count_plain(owner, "cot_open_at_trial_start"), 0)
        H.equal(count_plain(owner, "_reward_collected"), 0)
        -- Placement and the #132 census belong to other owners.
        H.equal(count_plain(owner, "populate_pickups"), 0)
        H.equal(count_plain(owner, "extensions_ready"), 0)
    end)

    H.test("the #299 POSITION_LOOKUP discipline moved intact", function()
        -- These needles used to be pinned against the entry. They follow the
        -- code; the entry-side absence assertions below stop a stray copy.
        H.truthy(owner:find(
            "if lookup and lookup[unit] then lookup[unit] = Vector3(x, y, z) end", 1, true),
            "#299 must refresh an EXISTING POSITION_LOOKUP entry before teleport_to")
        H.equal(owner:find("if lookup then lookup[unit] =", 1, true), nil,
            "#299 must not seed POSITION_LOOKUP entries the engine does not maintain")
        H.equal(entry:find("POSITION_LOOKUP", 1, true), nil,
            "the entry no longer touches POSITION_LOOKUP at all")
        -- Move strictly before free, in the moved text.
        local move_at = assert(owner:find("entry.moved = true", 1, true))
        local free_at = assert(owner:find(
            "StatusUtils.set_respawned_network(unit, true, unit)", move_at, true))
        H.truthy(move_at < free_at)
    end)
end
