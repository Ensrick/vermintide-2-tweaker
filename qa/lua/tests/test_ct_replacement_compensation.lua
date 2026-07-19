return function(H, repo_root)
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

    H.test("CT #465 production uses exact host lifecycle seams", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(path, "rb"))
        local entry_source = f:read("*a")
        f:close()
        local runtime_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_runtime.lua"
        local rf = assert(io.open(runtime_path, "rb"))
        local source = rf:read("*a")
        rf:close()
        H.truthy(entry_source:find('mod._ct_replacement_runtime.install(mod, {', 1, true))
        H.truthy(source:find('mod:hook("GameModeDeus", "player_left_game_session"', 1, true))
        H.truthy(source:find('mod:hook_safe("GameModeDeus", "_add_bot"', 1, true))
        H.truthy(source:find('mod:hook("GameModeDeus", "remove_bot"', 1, true))
        H.truthy(source:find('mod:hook("DeusRunController", "rpc_deus_set_initial_setup"', 1, true))
        H.truthy(source:find('effective_setting("replacement_player_compensation")', 1, true))
        H.truthy(source:find("run_state:get_server_peer_id()", 1, true))
        H.truthy(source:find("mod._ct_replacement_filtered(prepared)", 1, true))
        H.truthy(source:find("mod._ct_replacement_policy.prepare_for_target", 1, true))
        H.truthy(entry_source:find("mod._ct_bot_equip_weapon = _bot_equip_weapon", 1, true))
        H.truthy(source:find("awaiting=rpc_deus_set_initial_setup", 1, true))

        local data_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua"
        local df = assert(io.open(data_path, "rb"))
        local data = df:read("*a")
        df:close()
        H.truthy(data:find('setting_id = "replacement_player_compensation", type = "checkbox", default_value = true', 1, true))
    end)
end
