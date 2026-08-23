return function(H, repo_root)
    local module_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_pair_state.lua"
    local main_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function fixture()
        local handler, sent
        local mod = {
            network_register = function(_, _, callback) handler = callback end,
            network_send = function(_, channel, target, schema, op, slot, skin)
                sent = { channel, target, schema, op, slot, skin }
            end,
        }
        local om = {}
        assert(loadfile(module_path))().install(mod, om)
        return om, function() return handler end, function() return sent end
    end

    local function with_peer_globals(context, fn)
        local names = { "Managers", "Unit", "ScriptUnit" }
        local saved = {}
        for _, name in ipairs(names) do
            saved[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
        end
        rawset(_G, "Managers", { player = context.player_manager })
        rawset(_G, "Unit", {
            alive = function(unit) return unit ~= nil and context.dead[unit] ~= true end,
        })
        rawset(_G, "ScriptUnit", {
            extension = function(unit, extension_name)
                if extension_name ~= "inventory_system" then error("unexpected extension") end
                return assert(context.inventory_by_unit[unit], "inventory missing for unit")
            end,
        })
        local result = { pcall(fn) }
        for _, name in ipairs(names) do
            local prior = saved[name]
            rawset(_G, name, prior.present and prior.value or nil)
        end
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2)
    end

    local function make_inventory(unit, skin)
        local calls = {}
        local inv = {
            owner_unit = unit,
            _equipment = {
                wielded_slot = "slot_melee",
                slots = {
                    slot_melee = {
                        skin = skin,
                        item_data = { name = "es_dual_wield_hammer_sword" },
                    },
                },
            },
        }
        function inv:add_equipment(slot, item, applied_skin)
            calls[#calls + 1] = { "add", slot, item, applied_skin }
            self._equipment.slots[slot].skin = applied_skin
        end
        function inv:wield(slot)
            calls[#calls + 1] = { "wield", slot }
        end
        return inv, calls
    end

    local function two_peer_bus()
        local bus = { handlers = {}, messages = {}, enabled = false, peers = {} }

        local function add_peer(peer_id, local_skin)
            local local_unit = {}
            local local_inventory, local_calls = make_inventory(local_unit, local_skin)
            local context = {
                dead = {},
                inventory_by_unit = { [local_unit] = local_inventory },
                owner_by_unit = {},
                remote_players = {},
            }
            local local_player = { peer_id = peer_id, player_unit = local_unit }
            context.player_manager = {
                local_player = function() return local_player end,
                player_from_peer_id = function(_, remote_peer_id)
                    return context.remote_players[remote_peer_id]
                end,
                owner = function(_, unit) return context.owner_by_unit[unit] end,
            }
            local peer = {
                id = peer_id,
                context = context,
                local_unit = local_unit,
                local_inventory = local_inventory,
                local_calls = local_calls,
                om = {},
            }
            bus.peers[peer_id] = peer
            return peer
        end

        local function with_peer(peer_id, fn)
            return with_peer_globals(assert(bus.peers[peer_id]).context, fn)
        end

        local function make_mod(peer_id)
            return {
                network_register = function(_, channel, callback)
                    H.equal(channel, "cwv_exact_pair_state_v1")
                    bus.handlers[peer_id] = callback
                end,
                network_send = function(_, channel, target, schema, op, slot, skin)
                    bus.messages[#bus.messages + 1] = {
                        sender = peer_id, channel = channel, target = target,
                        schema = schema, op = op, slot = slot, skin = skin,
                    }
                    if not bus.enabled then return end
                    for target_peer_id, callback in pairs(bus.handlers) do
                        if target_peer_id ~= peer_id
                                and (target == "others" or target == target_peer_id) then
                            with_peer(target_peer_id, function()
                                callback(peer_id, schema, op, slot, skin)
                            end)
                        end
                    end
                end,
            }
        end

        local owner = add_peer("owner", "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1")
        local observer = add_peer("observer", nil)
        owner.context.remote_players.observer = { peer_id = "observer", player_unit = nil }
        observer.context.remote_players.owner = { peer_id = "owner", player_unit = nil }

        local module = assert(loadfile(module_path))()
        with_peer("owner", function() module.install(make_mod("owner"), owner.om) end)
        with_peer("observer", function() module.install(make_mod("observer"), observer.om) end)
        bus.messages = {}
        bus.enabled = true

        function bus:show_remote(viewer_id, sender_id)
            local viewer = assert(self.peers[viewer_id])
            local remote_player = assert(viewer.context.remote_players[sender_id])
            local unit = {}
            local inv, calls = make_inventory(unit, nil)
            remote_player.player_unit = unit
            viewer.context.inventory_by_unit[unit] = inv
            viewer.context.owner_by_unit[unit] = remote_player
            return inv, calls
        end

        bus.with_peer = with_peer
        return bus, owner, observer
    end

    H.test("CWV #567 exact-pair protocol is VMF-only and transition-driven", function()
        local source = read(module_path)
        H.truthy(source:find('local CHANNEL = "cwv_exact_pair_state_v1"', 1, true))
        H.equal(source:find("rawget(NetworkLookup", 1, true), nil)
        H.equal(source:find("NetworkLookup.weapon_skins", 1, true), nil)
        H.equal(source:find("mod.update", 1, true), nil)
        local om, _, sent = fixture()
        H.equal(om._exact_pair_schema, 1)
        H.truthy(om._exact_pair_skin_predicate(
            "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"))
        H.equal(sent()[4], "query")
    end)

    H.test("CWV #567 receiver restores exact skin and hand order to a live husk", function()
        local om, handler = fixture()
        local skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
        local unit = {}
        local calls = {}
        local inv = {
            owner_unit = unit,
            _equipment = {
                wielded_slot = "slot_melee",
                slots = {
                    slot_melee = {
                        skin = nil,
                        item_data = { name = "es_dual_wield_hammer_sword" },
                    },
                },
            },
            add_equipment = function(self, slot, item, applied_skin)
                calls[#calls + 1] = { "add", slot, item, applied_skin }
                self._equipment.slots[slot].skin = applied_skin
            end,
            wield = function(_, slot) calls[#calls + 1] = { "wield", slot } end,
        }

        local old_managers, old_unit, old_script_unit = Managers, Unit, ScriptUnit
        Managers = { player = {
            player_from_peer_id = function() return { player_unit = unit } end,
        } }
        Unit = { alive = function(candidate) return candidate == unit end }
        ScriptUnit = { extension = function() return inv end }
        handler()("remote-peer", 1, "state", "slot_melee", skin)
        Managers, Unit, ScriptUnit = old_managers, old_unit, old_script_unit

        H.equal(calls[1][1], "add")
        H.equal(calls[1][2], "slot_melee")
        H.equal(calls[1][3], "es_dual_wield_hammer_sword")
        H.equal(calls[1][4], skin)
        H.equal(calls[2][1], "wield")
        H.equal(om._exact_pair_state_by_peer["remote-peer"].slot_melee, skin)
        handler()("remote-peer", 1, "clear", "slot_melee", "")
        H.equal(om._exact_pair_state_by_peer["remote-peer"].slot_melee, nil)
    end)

    H.test("CWV #567 exact state is wired into every reconstruction surface", function()
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            '_exact_pair_publish_inventory(self, "wield")',
            '_exact_pair_publish_inventory(self, "game_object_initialized")',
            '_exact_pair_publish_inventory(self, "spawn_resynced_loadout")',
            '_exact_pair_on_hot_join_sync(peer_id)',
            '_exact_pair_on_gameplay_enter()',
            '_exact_pair_on_husk_wield(self, slot_name)',
            '_om.exact_appearance.resolve({',
        }) do
            H.truthy(source:find(marker, 1, true), "missing integration marker: " .. marker)
        end
    end)

    H.test("CWV #567 executes sender cache late-husk apply hot-join and clear across two peers", function()
        local bus, owner, observer = two_peer_bus()
        local skin = owner.local_inventory._equipment.slots.slot_melee.skin

        bus.with_peer("owner", function()
            owner.om._exact_pair_on_gameplay_enter()
        end)
        H.equal(observer.om._exact_pair_state_by_peer.owner.slot_melee, skin)

        local remote_inv, remote_calls = bus:show_remote("observer", "owner")
        bus.with_peer("observer", function()
            observer.om._exact_pair_on_husk_wield(remote_inv, "slot_melee")
        end)
        H.equal(remote_calls[1][1], "add")
        H.equal(remote_calls[1][4], skin)
        H.equal(remote_calls[2][1], "wield")

        bus.with_peer("owner", function()
            owner.om._exact_pair_publish_inventory(owner.local_inventory, "wield")
            owner.om._exact_pair_on_hot_join_sync("observer")
        end)
        H.equal(bus.messages[#bus.messages].target, "observer")

        owner.local_inventory._equipment.slots.slot_melee.skin = nil
        bus.with_peer("owner", function()
            owner.om._exact_pair_publish_inventory(owner.local_inventory, "wield")
        end)
        H.equal(observer.om._exact_pair_state_by_peer.owner.slot_melee, nil)

        local evidence = observer.om._exact_pair_live_evidence()
        H.truthy(evidence.rx_state)
        H.truthy(evidence.rx_cached_absent)
        H.truthy(evidence.apply_surfaces.husk_reconstruction)
        H.truthy(evidence.rx_clear)
    end)

    H.test("CWV #567 rejects foreign state and never calls a non-retained apply accepted", function()
        local om, handler = fixture()
        local skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
        handler()("remote-peer", 99, "state", "slot_melee", skin)
        handler()("remote-peer", 1, "state", "slot_melee", "foreign_skin")
        H.equal(om._exact_pair_state_by_peer["remote-peer"], nil)

        local unit = {}
        local wield_calls = 0
        local inv = {
            owner_unit = unit,
            _equipment = {
                wielded_slot = "slot_melee",
                slots = {
                    slot_melee = {
                        skin = nil,
                        item_data = { name = "es_dual_wield_hammer_sword" },
                    },
                },
            },
            add_equipment = function() end,
            wield = function() wield_calls = wield_calls + 1 end,
        }
        local context = {
            dead = {},
            inventory_by_unit = { [unit] = inv },
            player_manager = {
                player_from_peer_id = function() return { peer_id = "remote-peer", player_unit = unit } end,
                owner = function() return { peer_id = "remote-peer" } end,
            },
        }
        with_peer_globals(context, function()
            handler()("remote-peer", 1, "state", "slot_melee", skin)
        end)
        local evidence = om._exact_pair_live_evidence()
        H.truthy(evidence.rx_state)
        H.equal(evidence.apply_surfaces.remote_transition, nil)
        H.equal(wield_calls, 0)
        H.truthy(om._exact_pair_live_verdict():find("apply:accepted", 1, true))
    end)

    H.test("CWV #567 failed transport does not fabricate tx evidence", function()
        local mod = {
            network_register = function() end,
            network_send = function() error("transport unavailable") end,
        }
        local om = {}
        assert(loadfile(module_path))().install(mod, om)
        local inv = make_inventory({},
            "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1")
        H.equal(om._exact_pair_publish_inventory(inv, "wield"), 0)
        H.equal(om._exact_pair_live_evidence().tx_reasons.wield, nil)
    end)

    H.test("CWV #567 already-retained exact state is an accepted no-op", function()
        local om, handler = fixture()
        local skin = "cwv_es_sword_and_mace_wpn_emp_sword_02_t1_wpn_emp_mace_03_t1"
        local unit = {}
        local add_calls = 0
        local inv = {
            owner_unit = unit,
            _equipment = {
                wielded_slot = "slot_melee",
                slots = {
                    slot_melee = {
                        skin = skin,
                        item_data = { name = "es_dual_wield_hammer_sword" },
                    },
                },
            },
            add_equipment = function() add_calls = add_calls + 1 end,
            wield = function() error("retained state must not re-wield") end,
        }
        local context = {
            dead = {},
            inventory_by_unit = { [unit] = inv },
            player_manager = {
                player_from_peer_id = function() return { peer_id = "remote-peer", player_unit = unit } end,
            },
        }
        with_peer_globals(context, function()
            handler()("remote-peer", 1, "state", "slot_melee", skin)
        end)
        H.equal(add_calls, 0)
        H.truthy(om._exact_pair_live_evidence().apply_surfaces.remote_transition)
    end)
end
