return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local policy = dofile(repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_compensation.lua")

    local function state()
        local s = {
            power_ups = { { name = "vanilla_boon", rarity = "rare" }, { name = "ct_boon", rarity = "exotic" } },
            persistent_buffs = { "vanilla_buff", "ct_buff" },
            coins = 73,
            slot_melee = "melee-rare",
            slot_ranged = "ranged-exotic",
        }
        function s:get_player_power_ups() return self.power_ups end
        function s:get_player_persistent_buffs() return self.persistent_buffs end
        function s:get_player_soft_currency() return self.coins end
        function s:get_player_loadout(_, _, _, _, slot) return self[slot] end
        function s:set_player_power_ups(_, _, _, _, value)
            self.power_ups, self.applied_power_ups = value, value
        end
        function s:set_player_persistent_buffs(_, _, _, _, value)
            self.persistent_buffs, self.applied_buffs = value, value
        end
        function s:set_player_loadout(_, _, _, _, slot, value)
            self[slot], self["applied_" .. slot] = value, value
        end
        function s:set_player_soft_currency(_, _, value)
            self.coins, self.applied_coins = value, value
        end
        function s:get_profile_initialized() return self.profile_initialized == true end
        function s:get_peer_initialized() return self.peer_initialized == true end
        function s:set_profile_initialized(_, _, _, _, value) self.profile_initialized = value end
        function s:set_peer_initialized(_, value) self.peer_initialized = value end
        return s
    end

    H.test("CT #465 snapshot is bounded and detached from source state", function()
        local s = state()
        local snapshot = assert(policy.capture(s, "peer", 1, 2, 3))
        H.equal(snapshot.coins, 73)
        H.equal(snapshot.slot_melee, "melee-rare")
        H.equal(#snapshot.power_ups, 2)
        s.power_ups[1].name = "mutated"
        H.equal(snapshot.power_ups[1].name, "vanilla_boon")
        H.equal(policy.profile_key(2, 3), "2:3")
        H.equal(policy.profile_key(0, 3), nil)
        H.truthy(policy.same_identity(2, 3, 2, 3))
        H.equal(policy.same_identity(2, 3, 2, 4), false)
        H.equal(policy.same_identity(0, 3, 0, 3), false)
    end)

    H.test("CT #465 rejects oversized progression instead of truncating it", function()
        local oversized = state()
        oversized.power_ups = {}
        for i = 1, 300 do
            oversized.power_ups[i] = { name = "boon_" .. tostring(i) }
        end
        local snapshot, reason = policy.capture(oversized, "peer", 1, 4, 1)
        H.equal(snapshot, nil)
        H.truthy(tostring(reason):find("bounded snapshot", 1, true))
    end)

    H.test("CT #465 parity filter removes only CT-owned wire identifiers", function()
        local snapshot = assert(policy.capture(state(), "peer", 1, 2, 3))
        local filtered, removed_power_ups, removed_buffs = policy.wire_safe_copy(snapshot, false,
            function(name) return name == "ct_boon" end,
            function(name) return name == "ct_buff" end)
        H.equal(#filtered.power_ups, 1)
        H.equal(filtered.power_ups[1].name, "vanilla_boon")
        H.equal(#filtered.persistent_buffs, 1)
        H.equal(removed_power_ups, 1)
        H.equal(removed_buffs, 1)

        local safe = policy.wire_safe_copy(snapshot, true)
        H.equal(#safe.power_ups, 2)
        H.equal(#safe.persistent_buffs, 2)
    end)

    H.test("CT #465 apply copies progression and honors host coin override", function()
        local source = state()
        local snapshot = assert(policy.capture(source, "bot", 2, 4, 1))
        local target = state()
        local ok = policy.apply(target, "joiner", 1, 4, 1, snapshot, 999)
        H.truthy(ok)
        H.equal(#target.applied_power_ups, 2)
        H.equal(#target.applied_buffs, 2)
        H.equal(target.applied_slot_melee, "melee-rare")
        H.equal(target.applied_slot_ranged, "ranged-exotic")
        H.equal(target.applied_coins, 999)
        H.truthy(target.profile_initialized)
        H.truthy(target.peer_initialized)
    end)

    H.test("CT #465 cross-career handoff projects tiers onto target weapons", function()
        local source = assert(policy.capture(state(), "bot", 2, 4, 1))
        local target = assert(policy.capture(state(), "joiner", 1, 4, 2))
        target.slot_melee = "target-melee"
        target.slot_ranged = "target-ranged"
        local calls = {}
        local prepared, failures = policy.prepare_for_target(source, target, 4, 2,
            function(source_weapon, target_weapon, slot)
                calls[#calls + 1] = { source_weapon, target_weapon, slot }
                return target_weapon .. "-at-source-tier"
            end)
        H.equal(#failures, 0)
        H.equal(#calls, 2)
        H.equal(prepared.slot_melee, "target-melee-at-source-tier")
        H.equal(prepared.slot_ranged, "target-ranged-at-source-tier")
        H.equal(prepared.profile_index, 4)
        H.equal(prepared.career_index, 2)
        H.equal(#prepared.power_ups, #source.power_ups)
    end)

    H.test("CT #465 failed projection preserves target weapon", function()
        local source = assert(policy.capture(state(), "bot", 2, 4, 1))
        local target = assert(policy.capture(state(), "joiner", 1, 4, 2))
        target.slot_melee = "safe-target-melee"
        target.slot_ranged = "safe-target-ranged"
        local prepared, failures = policy.prepare_for_target(source, target, 4, 2,
            function(_, _, slot) return nil, slot .. " unavailable" end)
        H.equal(#failures, 2)
        H.equal(prepared.slot_melee, "safe-target-melee")
        H.equal(prepared.slot_ranged, "safe-target-ranged")
    end)

    H.test("CT #465 failed readback rolls back without a second grant", function()
        local target = state()
        local original_coins = target.coins
        local source = assert(policy.capture(state(), "bot", 2, 4, 1))
        local real_set_coins = target.set_player_soft_currency
        local writes = 0
        function target:set_player_soft_currency(_, _, value)
            writes = writes + 1
            if writes == 1 then
                self.coins = value + 1
            else
                real_set_coins(self, nil, nil, value)
            end
        end
        local ok, reason = policy.apply(target, "joiner", 1, 4, 1, source, 999)
        H.equal(ok, false)
        H.truthy(tostring(reason):find("apply/readback failed", 1, true))
        H.equal(target.coins, original_coins)
        H.equal(target.slot_melee, "melee-rare")
        H.equal(#target.power_ups, 2)
        H.equal(writes, 2)
    end)


    -- Execute the installed hooks with the real copy/filter/readback policy.
    -- The environment is private: neither successful nor failing cases rewrite
    -- process globals. Backend/live-unit refresh is an explicit stub boundary.
    local function runtime_fixture(options)
        options = options or {}
        local f = {
            hooks = {}, hooks_count = 0, logs = {}, legacy_reads = 0,
            legacy_writes = 0, refresh = { bot = 0, human = 0 },
            native_left = 0, native_remove = 0, native_setup = 0, native_inits = 0,
            writes = {}, coin_values = {},
        }
        local function row(profile, initialized, rich)
            local value = state()
            value.profile, value.career = profile, 1
            value.profile_initialized, value.peer_initialized = initialized, initialized
            if not rich then
                value.power_ups, value.persistent_buffs = {}, {}
                value.coins = 5
                value.slot_melee, value.slot_ranged = "target-melee", "target-ranged"
            end
            return value
        end
        f.rows = {
            ["human:1"] = row(4, true, true),
            ["bot:2"] = row(4, false, false),
            ["joiner:1"] = row(4, options.initialized ~= false, false),
            ["host:1"] = row(1, true, false),
        }
        f.rows["host:1"].coins = 999
        f.departing = f.rows["human:1"]
        local rs = {}
        local function key(peer, local_id) return tostring(peer) .. ":" .. tostring(local_id) end
        local function get(peer, local_id)
            return assert(f.rows[key(peer, local_id)], "missing fixture row")
        end
        local function wrote(peer, local_id)
            local k = key(peer, local_id)
            f.writes[k] = (f.writes[k] or 0) + 1
        end
        function rs:is_server() return options.server ~= false end
        function rs:get_server_peer_id() return "host" end
        function rs:get_player_profile(peer, local_id)
            local r = get(peer, local_id)
            return r.profile, r.career
        end
        function rs:get_player_power_ups(peer, local_id) return get(peer, local_id).power_ups end
        function rs:get_player_persistent_buffs(peer, local_id) return get(peer, local_id).persistent_buffs end
        function rs:get_player_soft_currency(peer, local_id) return get(peer, local_id).coins end
        function rs:get_player_loadout(peer, local_id, _, _, slot) return get(peer, local_id)[slot] end
        function rs:get_profile_initialized(peer, local_id) return get(peer, local_id).profile_initialized end
        function rs:get_peer_initialized(peer)
            return get(peer, peer == "bot" and 2 or 1).peer_initialized
        end
        function rs:set_player_power_ups(peer, local_id, _, _, value)
            wrote(peer, local_id)
            get(peer, local_id).power_ups = value
        end
        function rs:set_player_persistent_buffs(peer, local_id, _, _, value)
            get(peer, local_id).persistent_buffs = value
        end
        function rs:set_player_loadout(peer, local_id, _, _, slot, value)
            get(peer, local_id)[slot] = value
        end
        function rs:set_player_soft_currency(peer, local_id, value)
            local k = key(peer, local_id)
            f.coin_values[k] = f.coin_values[k] or {}
            f.coin_values[k][#f.coin_values[k] + 1] = value
            if f.corrupt_next_coin == k then
                f.corrupt_next_coin = nil
                value = value + 1
            end
            get(peer, local_id).coins = value
        end
        function rs:set_profile_initialized(peer, local_id, _, _, value)
            get(peer, local_id).profile_initialized = value
        end
        function rs:set_peer_initialized(peer, value)
            get(peer, peer == "bot" and 2 or 1).peer_initialized = value
        end
        f.rs, f.controller = rs, { _run_state = rs }
        f.bot = {
            network_id = function() return "bot" end,
            local_player_id = function() return 2 end,
            profile_index = function() return 4 end,
            career_index = function() return 1 end,
        }
        f.gm = {
            _is_server = options.server ~= false,
            _deus_run_controller = f.controller,
            _bot_players = { f.bot },
            _profile_synchronizer = { profile_by_peer = function() return 4 end },
        }
        f.manager = { _game_mode = f.gm }
        local env = setmetatable({
            Managers = { state = { game_mode = f.manager } },
            CHANNEL_TO_PEER_ID = { [77] = "joiner" },
            printf = function(fmt, ...) f.logs[#f.logs + 1] = string.format(fmt, ...) end,
        }, { __index = _G })
        env._G = env
        local mod = {}
        function mod:dofile(path)
            assert(path:find("_ct_replacement_compensation", 1, true))
            return policy
        end
        function mod:hook(class, method, callback)
            local name = class .. "." .. method
            assert(f.hooks[name] == nil, "duplicate fixture hook")
            f.hooks[name], f.hooks_count = callback, f.hooks_count + 1
        end
        mod.hook_safe = mod.hook
        function mod:command(name, _, callback) f.command = callback end
        -- Both persisted and host-synchronized legacy values are false. Any
        -- attempt to consult either value is observable, not silently stubbed.
        function mod:get(name)
            assert(name == "replacement_player_compensation")
            f.legacy_reads = f.legacy_reads + 1
            return false
        end
        function mod:set()
            f.legacy_writes = f.legacy_writes + 1
            error("implicit policy must not rewrite settings")
        end
        mod._ct_wire_safe = function() return options.parity ~= false end
        mod._ct_is_modded_power_up = function(name) return name == "ct_boon" end
        mod._ct_is_ct_buff_template = function(name) return name == "ct_buff" end
        mod._ct_bot_economy_active = function() return options.bot_economy == true end
        mod._ct_bot_economy_initialized = {}
        mod._ct_bot_economy_log = function() end
        local deps = { real_player_local_id = 1 }
        if not options.omit_reader then
            deps.effective_setting = function(name) return mod:get(name) end
        end
        local chunk = assert(loadfile(repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_runtime.lua"))
        setfenv(chunk, env)
        chunk().install(mod, deps)
        f.mod = mod
        mod._ct_replacement_refresh_bot = function()
            f.refresh.bot = f.refresh.bot + 1
            return true, "fixture backend boundary"
        end
        mod._ct_replacement_refresh_status = function()
            f.refresh.human = f.refresh.human + 1
            return true, "fixture live-status boundary"
        end
        function f:depart()
            return self.hooks["GameModeManager.player_left_game_session"](
                function(_, peer, local_id)
                    return self.hooks["GameModeDeus.player_left_game_session"](
                        function()
                            self.native_left = self.native_left + 1
                            self.rows["human:1"] = nil -- native teardown follows capture
                            return "native", nil, "third"
                        end, self.gm, peer, local_id)
                end, self.manager, "human", 1)
        end
        function f:add_bot() self.hooks["GameModeDeus._add_bot"](self.gm) end
        function f:remove()
            return self.hooks["GameModeManager.remove_bot"](
                function(_, party, peer, local_id, update_safe)
                    return self.hooks["GameModeDeus.remove_bot"](
                        function(_, actual_party, actual_peer, actual_local, actual_safe)
                            H.equal(actual_party, 1)
                            H.equal(actual_peer, "joiner")
                            H.equal(actual_local, 1)
                            H.equal(actual_safe, true)
                            self.native_remove = self.native_remove + 1
                            self.rows["bot:2"] = nil -- proves pre-removal capture
                            self.gm._bot_players = {}
                            return options.return_other and {} or self.bot
                        end, self.gm, party, peer, local_id, update_safe)
                end, self.manager, 1, "joiner", 1, true)
        end
        function f:setup()
            return self.hooks["DeusRunController.rpc_deus_set_initial_setup"](
                function(_, channel, profile, career, talents, melee, ranged)
                    self.native_setup = self.native_setup + 1
                    H.equal(channel, 77)
                    H.equal(profile, 4)
                    H.equal(career, 1)
                    H.equal(talents, "native-talents")
                    local r = self.rows["joiner:1"]
                    if not r.profile_initialized then
                        self.native_inits = self.native_inits + 1
                        r.power_ups = { { name = "native-initial-boon" } }
                        r.slot_melee, r.slot_ranged = melee, ranged
                        r.profile_initialized = true
                    end
                    return nil, "setup-return"
                end, self.controller, 77, 4, 1, "native-talents", "native-melee", "native-ranged")
        end
        return f
    end

    local function pack(...) return { n = select("#", ...), ... } end
    local function bot_handoff(f)
        f:depart()
        f:add_bot()
    end

    H.test("CT #465 intrinsic runtime installs without a setting-reader dependency", function()
        local f = runtime_fixture({ omit_reader = true })
        H.equal(f.hooks_count, 6)
        bot_handoff(f)
        H.equal(f.mod._ct465_edges.applied, 1)
        H.equal(f.legacy_reads, 0)
        H.equal(f.legacy_writes, 0)
    end)

    H.test("CT #465 false legacy controls cannot suppress departure or bot handoff", function()
        local f = runtime_fixture()
        local ret = pack(f:depart())
        H.equal(ret.n, 3)
        H.equal(ret[1], "native")
        H.equal(ret[2], nil)
        H.equal(ret[3], "third")
        H.equal(f.native_left, 1)
        H.equal(#f.mod._ct_replacement_cache["4:1"], 1)
        f:add_bot()
        local bot = f.rows["bot:2"]
        H.equal(#bot.power_ups, 2)
        H.equal(bot.coins, 73)
        H.equal(bot.slot_melee, "melee-rare")
        H.equal(bot.slot_ranged, "ranged-exotic")
        H.equal(f.mod._ct_replacement_cache["4:1"], nil)
        H.equal(f.refresh.bot, 1)
        f:add_bot()
        H.equal(f.writes["bot:2"], 1, "consumed departure must not grant twice")
        H.equal(f.legacy_reads, 0)
        H.equal(f.legacy_writes, 0)
        H.truthy(table.concat(f.logs, "\n"):find("policy=implicit", 1, true))
    end)

    H.test("CT #465 immediate return captures selected bot before native teardown", function()
        local f = runtime_fixture()
        local host_before = assert(policy.capture(f.rs, "host", 1, 1, 1))
        bot_handoff(f)
        -- Native removal selects by joining profile, not simply the last bot.
        local foreign_bot = {
            network_id = function() return "other" end,
            local_player_id = function() return 3 end,
            profile_index = function() return 2 end,
            career_index = function() return 1 end,
        }
        f.gm._bot_players[2] = foreign_bot
        H.equal(f:remove(), f.bot)
        H.equal(f.native_remove, 1)
        local human = f.rows["joiner:1"]
        H.equal(#human.power_ups, 2)
        H.equal(#human.persistent_buffs, 2)
        H.equal(human.coins, 999)
        H.equal(human.slot_melee, "melee-rare")
        H.equal(human.slot_ranged, "ranged-exotic")
        H.equal(f.refresh.human, 1)
        H.equal(f.mod._ct_replacement_pending_humans["joiner:1"], nil)
        H.truthy(f.mod._ct465_report())
        H.deep_equal(policy.capture(f.rs, "host", 1, 1, 1), host_before)
        H.equal(f.legacy_reads, 0)
        H.equal(f.legacy_writes, 0)
    end)

    H.test("CT #465 deferred return runs native setup first and finishes exactly once", function()
        local f = runtime_fixture({ initialized = false })
        bot_handoff(f)
        H.equal(f:remove(), f.bot)
        H.truthy(f.mod._ct_replacement_pending_humans["joiner:1"])
        H.equal(f.writes["joiner:1"], nil)
        f.rows["host:1"].coins = 1200
        local ret = pack(f:setup())
        H.equal(ret.n, 2)
        H.equal(ret[1], nil)
        H.equal(ret[2], "setup-return")
        H.equal(f.native_inits, 1)
        H.equal(f.rows["joiner:1"].coins, 1200, "coin override is read at completion")
        H.equal(#f.rows["joiner:1"].power_ups, 2)
        H.equal(f.rows["joiner:1"].slot_melee, "melee-rare")
        H.equal(f.mod._ct_replacement_pending_humans["joiner:1"], nil)
        f:setup()
        H.equal(f.native_setup, 2)
        H.equal(f.native_inits, 1)
        H.equal(f.writes["joiner:1"], 1)
        H.equal(f.refresh.human, 1)
        H.equal(f.mod._ct465_edges.applied, 2)
        H.equal(f.legacy_reads, 0)
    end)

    H.test("CT #465 non-server callbacks retain native calls without transfers", function()
        local f = runtime_fixture({ server = false })
        f:depart()
        f:add_bot()
        H.equal(f:remove(), f.bot)
        H.equal(f.native_left, 1)
        H.equal(f.native_remove, 1)
        H.equal(next(f.mod._ct_replacement_cache), nil)
        H.equal(next(f.mod._ct_replacement_pending_humans), nil)
        H.equal(next(f.writes), nil)
        H.equal(f.mod._ct465_edges.applied, 0)
        H.equal(f.refresh.bot + f.refresh.human, 0)
        H.equal(f.legacy_reads, 0)
    end)

    H.test("CT #465 returned-bot mismatch fails closed after one native removal", function()
        local f = runtime_fixture({ return_other = true })
        bot_handoff(f)
        local human_before = assert(policy.capture(f.rs, "joiner", 1, 4, 1))
        H.truthy(f:remove() ~= f.bot)
        H.equal(f.native_remove, 1)
        H.deep_equal(policy.capture(f.rs, "joiner", 1, 4, 1), human_before)
        H.equal(f.mod._ct465_edges.applied, 1)
        H.equal(f.refresh.human, 0)
    end)

    H.test("CT #465 callback parity filtering preserves vanilla progression and source", function()
        local f = runtime_fixture({ parity = false })
        f:depart()
        local snapshot = f.mod._ct_replacement_cache["4:1"][1]
        f:add_bot()
        H.equal(#f.rows["bot:2"].power_ups, 1)
        H.equal(f.rows["bot:2"].power_ups[1].name, "vanilla_boon")
        H.deep_equal(f.rows["bot:2"].persistent_buffs, { "vanilla_buff" })
        H.equal(f.rows["bot:2"].coins, 73)
        H.equal(#snapshot.power_ups, 2, "filter must not mutate cached source")
        H.equal(#snapshot.persistent_buffs, 2)
        H.equal(#f.departing.power_ups, 2)
    end)

    H.test("CT #465 callback rollback retains the snapshot for one successful retry", function()
        local f = runtime_fixture()
        f:depart()
        local before = assert(policy.capture(f.rs, "bot", 2, 4, 1))
        f.corrupt_next_coin = "bot:2"
        f:add_bot()
        H.deep_equal(policy.capture(f.rs, "bot", 2, 4, 1), before)
        H.equal(f.rows["bot:2"].profile_initialized, false)
        H.equal(f.rows["bot:2"].peer_initialized, false)
        H.equal(f.writes["bot:2"], 2, "failed write plus rollback, not a second grant")
        H.equal(#f.mod._ct_replacement_cache["4:1"], 1)
        H.equal(f.mod._ct465_edges.applied, 0)
        H.equal(f.refresh.bot, 0)
        f:add_bot()
        f:add_bot()
        H.equal(f.writes["bot:2"], 3)
        H.equal(f.mod._ct_replacement_cache["4:1"], nil)
        H.equal(f.mod._ct465_edges.applied, 1)
        H.equal(f.refresh.bot, 1)
    end)


    H.test("CT #465 deferred readback failure keeps pending until a successful retry", function()
        local f = runtime_fixture({ initialized = false })
        bot_handoff(f)
        f:remove()
        f.corrupt_next_coin = "joiner:1"
        f:setup()
        H.truthy(f.mod._ct_replacement_pending_humans["joiner:1"])
        H.equal(f.rows["joiner:1"].power_ups[1].name, "native-initial-boon")
        H.equal(f.rows["joiner:1"].slot_melee, "native-melee")
        H.equal(f.rows["joiner:1"].coins, 5)
        H.equal(f.writes["joiner:1"], 2)
        H.equal(f.refresh.human, 0)
        H.equal(f.mod._ct465_edges.applied, 1)
        f:setup()
        f:setup()
        H.equal(f.native_inits, 1)
        H.equal(f.writes["joiner:1"], 3)
        H.equal(f.rows["joiner:1"].coins, 999)
        H.equal(f.mod._ct_replacement_pending_humans["joiner:1"], nil)
        H.equal(f.refresh.human, 1)
        H.equal(f.mod._ct465_edges.applied, 2)
    end)

    H.test("CT #465 setup receiver cannot apply a pending handoff off-server", function()
        local f = runtime_fixture({ server = false, initialized = false })
        f.mod._ct_replacement_pending_humans["joiner:1"] = {
            game_mode = f.gm,
            snapshot = assert(policy.capture(f.rs, "human", 1, 4, 1)),
        }
        f:setup()
        H.equal(f.native_setup, 1)
        H.equal(f.native_inits, 1)
        H.truthy(f.mod._ct_replacement_pending_humans["joiner:1"])
        H.equal(f.writes["joiner:1"], nil)
        H.equal(f.refresh.human, 0)
        H.equal(f.mod._ct465_edges.applied, 0)
    end)

    H.test("CT #465 departing balance supersedes the independent bot-economy seed", function()
        local f = runtime_fixture({ bot_economy = true })
        bot_handoff(f)
        H.deep_equal(f.coin_values["bot:2"], { 999, 73 })
        H.equal(f.mod._ct_bot_economy_initialized["bot:2"], true)
        H.equal(f.rows["bot:2"].coins, 73)
        H.equal(f.mod._ct465_edges.applied, 1)
    end)

    H.test("CT #465 production uses exact host lifecycle seams", function()
        local entry_source = CTSource.expanded(repo_root)
        local owner_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_weapon_chest_owner.lua"
        local owner_file = assert(io.open(owner_path, "rb"))
        local owner_source = owner_file:read("*a")
        owner_file:close()
        local runtime_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_runtime.lua"
        local rf = assert(io.open(runtime_path, "rb"))
        local source = rf:read("*a")
        rf:close()
        -- #1159 wave 14: the install sat between the get_run_difficulty hook above
        -- it and the setup_run hook below it, so it moved into
        -- _ct_run_creation_owner rather than reordering those registrations. Same
        -- needle, new file, plus an entry-side absence so a stray second install
        -- (which would re-register six hooks VMF would silently drop) fails here.
        local run_creation_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner.lua"
        local rc_file = assert(io.open(run_creation_path, "rb"))
        local run_creation = rc_file:read("*a")
        rc_file:close()
        H.truthy(run_creation:find('mod._ct_replacement_runtime.install(mod, {', 1, true))
        H.equal(entry_source:find('mod._ct_replacement_runtime.install', 1, true), nil)
        H.truthy(entry_source:find(
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_run_creation_owner")',
            1, true))
        H.truthy(source:find('mod:hook("GameModeDeus", "player_left_game_session"', 1, true))
        H.truthy(source:find('mod:hook("GameModeManager", "player_left_game_session"', 1, true))
        H.truthy(source:find('mod:hook_safe("GameModeDeus", "_add_bot"', 1, true))
        H.truthy(source:find('mod:hook("GameModeDeus", "remove_bot"', 1, true))
        H.truthy(source:find('mod:hook("GameModeManager", "remove_bot"', 1, true))
        H.truthy(source:find('mod:hook("DeusRunController", "rpc_deus_set_initial_setup"', 1, true))
        H.equal(source:find("effective_setting", 1, true), nil,
            "intrinsic handoff must not read a saved or synchronized opt-out")
        H.truthy(source:find("policy=implicit", 1, true))
        H.truthy(source:find("run_state:get_server_peer_id()", 1, true))
        H.truthy(source:find("mod._ct_replacement_filtered(prepared)", 1, true))
        H.truthy(source:find("mod._ct_replacement_policy.prepare_for_target", 1, true))
        H.truthy(owner_source:find(
            "mod._ct_bot_equip_weapon = state.public_bot_equip_weapon", 1, true))
        H.truthy(source:find("awaiting=rpc_deus_set_initial_setup", 1, true))
        H.truthy(source:find("bot->human pre-remove selected=", 1, true))
        H.truthy(source:find('mod:command("ct_report_465"', 1, true))
        H.truthy(source:find("selected_bot ~= bot", 1, true))

        local data_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua"
        local df = assert(io.open(data_path, "rb"))
        local data = df:read("*a")
        df:close()
        H.equal(data:find('setting_id = "replacement_player_compensation"', 1, true), nil)
        local lf = assert(io.open(repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_localization.lua", "rb"))
        local localization = lf:read("*a")
        lf:close()
        H.equal(localization:find("replacement_player_compensation =", 1, true), nil)
        H.equal(localization:find("replacement_player_compensation_tooltip =", 1, true), nil)
    end)
end
