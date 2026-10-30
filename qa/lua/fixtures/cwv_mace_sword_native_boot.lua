-- Offline source-order proof only. Complete native methods are read in memory;
-- no source bodies, VMF implementation, engine units or spawn algorithm copied.
local M = {}
local PM = "/scripts/managers/player/player_manager.lua"
local BP = "/scripts/managers/player/bulldozer_player.lua"
local US = "/scripts/network/unit_spawner.lua"
local EM = "/scripts/managers/entity/entity_manager2.lua"
local SI = "/scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua"
local function pack(...) return { n = select("#", ...), ... } end
function M.available(root)
    for _, path in ipairs({ PM, BP, US, EM, SI }) do
        local file = io.open(root .. path, "rb")
        if not file then return false end
        file:close()
    end
    return true
end
local function read(root, path)
    local file = assert(io.open(root .. path, "rb"))
    local text = file:read("*a"); file:close()
    text = text:gsub("\r\n", "\n")
    if text:sub(1, 3) == string.char(239, 187, 191) then text = text:sub(4) end
    return text
end
local function block(text, first, next_method)
    local a = assert(text:find(first, 1, true), "native method start")
    assert(not text:find(first, a + 1, true), "native method start unique")
    local b = assert(text:find(next_method, a + #first, true), "native method end")
    return text:sub(a, b - 1)
end
local function evaluate(text, env, name)
    local chunk = assert(loadstring(text, name))
    setfenv(chunk, env); return chunk()
end
local function prepare(H, root, s)
    local pm, bp = read(root, PM), read(root, BP)
    local manager, party, trace = s.managers.player, {}, {}
    local spawner = s.managers.state.unit_spawner or {}
    s.managers.state.unit_spawner = spawner
    manager._unit_owners, manager._player_units_owners = {}, {}
    s.player.owned_units = {}
    s.player.network_id = function() return "local" end
    s.player.local_player_id = function() return 1 end
    s.managers.party = { get_party_from_player_id = function(_, peer, id)
        H.equal(peer, "local"); H.equal(id, 1); return party
    end }
    s.managers.state.side = {
        side_by_party = { [party] = { side_id = 7 } },
        add_player_unit_to_side = function(_, unit, side)
            H.equal(unit, s.unit); H.equal(side, 7); H.equal(s.player.player_unit, s.unit)
            trace[#trace + 1] = "native_ownership_side"
        end,
    }
    spawner.add_destroy_listener = function(_, unit, key)
        H.equal(unit, s.unit); H.equal(key, "player_manager")
    end
    local env = setmetatable({ PlayerManager = {}, BulldozerPlayer = {},
        Managers = s.managers, script_data = { network_debug_connections = false },
        callback = function(owner, name)
            H.equal(owner, manager); H.equal(name, "unit_destroy_callback"); return function() end
        end }, { __index = _G })
    evaluate(block(bp, "BulldozerPlayer.set_player_unit = function", "\nBulldozerPlayer.type = function")
        .. block(pm, "PlayerManager.assign_unit_ownership = function", "\nPlayerManager.unit_destroy_callback = function")
        .. block(pm, "PlayerManager.unit_owner = function", "\nPlayerManager.player_from_unique_id = function"),
        env, "actual-native-player-ownership-methods")
    s.player.set_player_unit = env.BulldozerPlayer.set_player_unit
    -- Real native owner-map reader, rather than the older fixture's flag.
    manager.owner = env.PlayerManager.unit_owner
    manager.assign_unit_ownership = function(self, unit, player, is_player_unit)
        H.equal(self, manager)
        env.PlayerManager.assign_unit_ownership(self, unit, player, is_player_unit)
        trace[#trace + 1] = "native_ownership_returned"
        s.hooks.assign_unit_ownership(self, unit, player, is_player_unit)
    end
    return env, trace
end
function M.assign(H, root, s)
    local _, trace = prepare(H, root, s)
    s.managers.player:assign_unit_ownership(s.unit, s.player, true)
    return trace
end
function M.spawn(H, root, s, make_slot, init_hook)
    local env, trace = prepare(H, root, s)
    local bp, us, em, si = read(root, BP), read(root, US), read(root, EM), read(root, SI)
    env.UnitSpawner, env.EntityManager2, env.SimpleInventoryExtension = {}, {}, {}
    env.LEVEL_EDITOR_TEST = false
    local rotation, vector = {}, {}
    env.Quaternion = { forward = function() return vector end, look = function() return rotation end }
    env.Vector3 = { flat = function() return vector end, up = function() return vector end }
    env.NetworkUnit = { add_unit = function(unit) H.equal(unit, s.unit) end,
        set_is_husk_unit = function(unit, husk) H.equal(unit, s.unit); H.equal(husk, false) end }
    env.GameSession = { create_game_object = function() return 77 end }
    env.NetworkLookup = { equipment_slots = { slot_melee = 1, slot_ranged = 2 },
        item_names = { es_1h_sword = 1 }, weapon_skins = { ["n/a"] = 1 } }
    env.BLACKBOARDS, env.SwapFromStorageType = { [s.unit] = {} }, { UnwieldPrio = "source_unwield" }
    env.ScriptUnit = { extension = function(unit, system)
        H.equal(unit, s.unit); H.equal(system, "health_system")
        return { sync_health_state = function()
            H.equal(s.player.player_unit, nil); trace[#trace + 1] = "native_health_before_ownership"
        end }
    end }
    evaluate(block(bp, "BulldozerPlayer._spawn_unit_at_pos_rot = function", "\nBulldozerPlayer.spawn_unit = function")
        .. block(bp, "BulldozerPlayer.spawn_unit = function", "\nBulldozerPlayer.spawn = function")
        .. block(us, "UnitSpawner.spawn_network_unit = function", "\nUnitSpawner.queue_spawn_network_unit = function")
        .. block(em, "EntityManager2.sync_unit_extensions = function", "\nEntityManager2.hot_join_sync = function")
        .. block(si, "SimpleInventoryExtension.game_object_initialized = function", "\nSimpleInventoryExtension._send_rpc_add_equipment_buffs = function"),
        env, "actual-native-spawn-sync-inventory-methods")
    local spawner = s.managers.state.unit_spawner
    spawner.spawn_network_unit = env.UnitSpawner.spawn_network_unit
    spawner.unit_template_lut = { source_player = { go_type = "player" } }
    spawner.gameobject_initializers = { player = function() return {} end }
    spawner.unit_storage = { add_unit_info = function(_, unit, id) H.equal(unit, s.unit); H.equal(id, 77) end }
    spawner.spawn_local_unit_with_extensions = function()
        H.equal(s.player.player_unit, nil); trace[#trace + 1] = "native_local_spawn"
        s.equipment.slots[s.equipment.wielded_slot] = make_slot()
        return s.unit, "source_player"
    end
    local entity = {
        _units = { [s.unit] = { inventory = s.inventory } },
        _extension_to_system_map = { inventory = "inventory" }, _systems = { inventory = {} },
        sync_unit_extensions = env.EntityManager2.sync_unit_extensions,
    }
    spawner.entity_manager = entity
    s.managers.state.network.network_transmit = { send_rpc_clients = function()
        H.equal(s.player.player_unit, nil)
    end }
    s.inventory.is_server, s.inventory._additional_items = true, {}
    s.inventory.swap_equipment_from_storage = function() H.equal(s.player.player_unit, nil) end
    s.inventory.get_weapon_unit = function() return nil end
    s.inventory.game_object_initialized = function(self, unit, id)
        H.equal(s.player.player_unit, nil); trace[#trace + 1] = "native_GO_before_ownership"
        local result = pack(init_hook(env.SimpleInventoryExtension.game_object_initialized, self, unit, id))
        H.equal(s.player.player_unit, nil); H.equal(s.speed(), 4, "GO completion is still pre-ownership")
        return unpack(result, 1, result.n)
    end
    s.player.spawn_unit, s.player._spawn_unit_at_pos_rot = env.BulldozerPlayer.spawn_unit, env.BulldozerPlayer._spawn_unit_at_pos_rot
    s.player.is_server, s.player.player_unit = true, nil
    local first = "\tlocal unit = self:spawn_unit(unit_name, extension_init_data, profile.unit_template_name, optional_position, optional_rotation)"
    local last = "\tplayer_manager:assign_unit_ownership(unit, self, is_player_unit)"
    local a, b = assert(bp:find(first, 1, true)), assert(bp:find(last, 1, true))
    H.truthy(a < b, "actual Bulldozer spawn calls network spawn before ownership")
    H.equal(bp:find(first, a + 1, true), nil); H.equal(bp:find(last, b + 1, true), nil)
    -- Execute the two exact caller statements, not unrelated spawn cosmetics/
    -- telemetry. Every intervening relevant callee above is its complete body.
    local caller = evaluate("return function(self, player_manager, unit_name, extension_init_data, profile, optional_position, optional_rotation)\n"
        .. first .. "\nlocal is_player_unit = true\n" .. last .. "\nreturn unit end", env, "actual-native-ordered-spawn-call-sites")
    H.equal(caller(s.player, s.managers.player, "source_player", {}, { unit_template_name = "source_player" }, vector, rotation), s.unit)
    return trace
end
return M
