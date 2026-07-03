local mod = get_mod("gt")

-- _gt_item_spawner.lua — pickup spawner chat commands (/spawnitem, /nextitem, /previtem)
--
-- Spawns pickups (ammo, potions, tomes/grimoires, training dummies, grenades,
-- barrels, healing items, torches, oils, ...) at the local player via vanilla's
-- rpc_spawn_pickup(_with_physics). Ported from Vermintide-Mods/ItemSpawner
-- (MIT). Command-only (NO hooks). Cycles the live `AllPickups` table filtered
-- against the same crash-on-spawn exclusion list the upstream mod used.
-- Extracted from general_tweaker.lua (v0.2.132-dev, "refactor: extract dump
-- commands + item spawner to modules — no behavior change"). The pickup-lookup
-- rawget-hardening marker constant (CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48)
-- and its /gt_regression_test check stay in the main file; this module only
-- relies on `mod` + game globals and runs after the main chunk via mod:dofile.
--
-- Owned by: general_tweaker.lua entry point. Consumed via: mod:dofile.

-- ============================================================
-- Item Spawner (ported from Vermintide-Mods/ItemSpawner, MIT-licensed)
-- ============================================================
-- Spawns pickups (ammo, potions, tomes, grimoires, training dummies, grenades,
-- barrels, lorebook pages, healing items, door sticks, torches, oils) at the
-- player position via vanilla's `rpc_spawn_pickup_with_physics` (or
-- `rpc_spawn_pickup` for `all_ammo`). Cycles through the live `AllPickups`
-- table filtered against the same exclusion list the upstream mod used
-- (loot_die, lorebook_pages, beer_barrel — these crash on spawn). Training
-- dummies are host-only per vanilla restrictions.
--
-- `/spawnitem <substring>` fuzzy-matches against pickup_name or the
-- localised item name. Hotkey trio (`gt_is_next` / `gt_is_prev` /
-- `gt_is_spawn`) cycles + spawns the currently selected pickup.

local _gt_is_pickup_names = nil
local _gt_is_current = nil
local _gt_is_excluded = {
    loot_die = true,
    lorebook_pages = true,
    beer_barrel = true,
}

local function _gt_is_init_pickups()
    if _gt_is_pickup_names then return end
    if not AllPickups then return end
    local names = {}
    for k, v in pairs(AllPickups) do
        if not _gt_is_excluded[k] then
            -- Match upstream filter: skip any pickup whose unit template
            -- contains "_limited" or whose name contains "endurance_badge".
            local tmpl = v.unit_template_name or ""
            if not string.find(tmpl, "_limited", 1, true)
            and not string.find(k, "endurance_badge", 1, true) then
                names[#names + 1] = k
            end
        end
    end
    table.sort(names)
    _gt_is_pickup_names = names
    if not _gt_is_current and names[1] then
        _gt_is_current = names[1]
    end
end

local function _gt_is_index_of(name)
    if not _gt_is_pickup_names then return 0 end
    for i, n in ipairs(_gt_is_pickup_names) do
        if n == name then return i end
    end
    return 0
end

-- Vanilla spawn path. `all_ammo` uses the non-physics RPC because the
-- physics variant on a multi-pickup unit crashes the host's ammo-collector.
local function _gt_is_spawn(pickup_name)
    if not (Managers.player and Managers.state and Managers.state.network) then return end
    local lp = Managers.player:local_player()
    if not (lp and lp.player_unit and Unit.alive(lp.player_unit)) then
        mod:echo("No local player unit.")
        return
    end
    if not Managers.player.is_server then
        local dummy_set = {
            training_dummy = true,
            training_dummy_armored = true,
            training_dummy_skaven = true,
        }
        if dummy_set[pickup_name] then
            mod:echo("Need to be host to spawn training dummies.")
            return
        end
    end
    local spawn_method = (pickup_name == "all_ammo")
        and "rpc_spawn_pickup"
        or  "rpc_spawn_pickup_with_physics"
    local pos = Unit.local_position(lp.player_unit, 0)
    local rot = Unit.local_rotation(lp.player_unit, 0)
    local pickup_id = rawget(NetworkLookup.pickup_names, pickup_name)
    if not pickup_id then
        mod:echo("Unknown pickup name: " .. tostring(pickup_name))
        return
    end
    Managers.state.network.network_transmit:send_rpc_server(
        spawn_method,
        pickup_id,
        pos, rot,
        NetworkLookup.pickup_spawn_types.dropped)
end

mod.gt_is_next = function()
    _gt_is_init_pickups()
    if not _gt_is_pickup_names or #_gt_is_pickup_names == 0 then return end
    local idx = _gt_is_index_of(_gt_is_current) + 1
    if idx > #_gt_is_pickup_names then idx = 1 end
    _gt_is_current = _gt_is_pickup_names[idx]
    mod:echo("Selected pickup: " .. _gt_is_current)
end

mod.gt_is_prev = function()
    _gt_is_init_pickups()
    if not _gt_is_pickup_names or #_gt_is_pickup_names == 0 then return end
    local idx = _gt_is_index_of(_gt_is_current) - 1
    if idx < 1 then idx = #_gt_is_pickup_names end
    _gt_is_current = _gt_is_pickup_names[idx]
    mod:echo("Selected pickup: " .. _gt_is_current)
end

mod.gt_is_spawn = function()
    _gt_is_init_pickups()
    if not _gt_is_current then
        mod:echo("No pickup selected.")
        return
    end
    _gt_is_spawn(_gt_is_current)
    mod:echo("Spawned: " .. _gt_is_current)
end

mod.gt_is_switch = function(user_input)
    _gt_is_init_pickups()
    if not user_input or user_input == "" then
        mod:echo("Current pickup: " .. tostring(_gt_is_current))
        return
    end
    local q = string.lower(user_input)
    for _, name in ipairs(_gt_is_pickup_names) do
        local matches_key  = string.find(string.lower(name), q, 1, true)
        local localized    = AllPickups[name] and AllPickups[name].item_name
                             and Localize(AllPickups[name].item_name) or ""
        local matches_name = string.find(string.lower(localized), q, 1, true)
        if matches_key or matches_name then
            _gt_is_current = name
            mod:echo("Selected pickup: " .. name)
            return
        end
    end
    mod:echo("No pickup matches: " .. user_input)
end

mod:command("spawnitem", "Spawn or switch pickup (no arg = report current; with arg = fuzzy-match by key or localized name)", function(...)
    local args = { ... }
    mod.gt_is_switch(args[1])
    if args[1] then mod.gt_is_spawn() end
end)
mod:command("nextitem", "Cycle to next pickup in the spawn list", function() mod.gt_is_next() end)
mod:command("previtem", "Cycle to previous pickup in the spawn list", function() mod.gt_is_prev() end)
