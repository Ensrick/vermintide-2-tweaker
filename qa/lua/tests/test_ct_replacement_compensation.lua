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
        function s:set_player_power_ups(_, _, _, _, value) self.applied_power_ups = value end
        function s:set_player_persistent_buffs(_, _, _, _, value) self.applied_buffs = value end
        function s:set_player_loadout(_, _, _, _, slot, value) self["applied_" .. slot] = value end
        function s:set_player_soft_currency(_, _, value) self.applied_coins = value end
        function s:set_profile_initialized(...) self.profile_initialized = { ... } end
        function s:set_peer_initialized(...) self.peer_initialized = { ... } end
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

    H.test("CT #465 production uses exact host lifecycle seams", function()
        local path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        H.truthy(source:find('mod:hook("GameModeDeus", "player_left_game_session"', 1, true))
        H.truthy(source:find('mod:hook_safe("GameModeDeus", "_add_bot"', 1, true))
        H.truthy(source:find('mod:hook("GameModeDeus", "remove_bot"', 1, true))
        H.truthy(source:find('effective_setting("replacement_player_compensation")', 1, true))
        H.truthy(source:find("run_state:get_server_peer_id()", 1, true))
        H.truthy(source:find("mod._ct_replacement_filtered(snapshot)", 1, true))

        local data_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data.lua"
        local df = assert(io.open(data_path, "rb"))
        local data = df:read("*a")
        df:close()
        H.truthy(data:find('setting_id = "replacement_player_compensation", type = "checkbox", default_value = true', 1, true))
    end)
end
