-- _gut_spawn_weapon_policy.lua -- pure career-default spawn weapon policy (#1637).
--
-- Engine-free: no VMF, Managers or ItemMasterList globals are touched. The
-- offline Lua harness runs it against qa/lua/fixtures/vanilla_weapon_master_list.lua
-- (generated from the decompiled vanilla source) and /gut_regression_test runs
-- the same functions against the live ItemMasterList / CareerSettings tables.
--
-- Why a synthetic item carries NO backend id: BackendUtils.get_item_units
-- (backend_utils.lua:144-190) only skips `backend_items:get_skin(backend_id)`
-- when `item_data.backend_id` is nil, and BackendInterfaceItemPlayfab.get_skin
-- (backend_interface_item_playfab.lua:344-348) indexes the looked-up item with
-- no nil check, so an id the item interface cannot resolve would fatal inside
-- GearUtils.create_equipment at the very spawn we are trying to save. Vanilla
-- itself equips master-list-only rows without an id for every
-- `self.initial_inventory[slot_name]` slot (simple_inventory_extension.lua:394),
-- and add_equipment then resolves `rawget(ItemMasterList, item_data.name)`
-- (simple_inventory_extension.lua:883). The one consumer that cannot take that
-- raw row is LoadoutUtils.sync_loadout_slot (loadout_utils.lua:13-42), which
-- puts `item.power_level` on rpc_sync_loadout_slot; `shadow_sync_item` below
-- supplies the shape it needs.
local P = {}

P.WEAPON_SLOTS = { slot_melee = 1, slot_ranged = 2 }
-- Power level carried on the sync RPC shadow. Matches the in-repo synthetic item
-- precedent (_cim_synthetic_item_contract.lua:249) and the external one below.
-- Pusfume _pusfume_weapons.lua:1529 uses the same value. -- pusfume-compat-reviewed: value precedent only, no runtime integration.
P.SYNTHETIC_POWER_LEVEL = 300
P.SYNTHETIC_RARITY = "plentiful"

-- Vanilla's only client-side per-career starting gear table:
-- scripts/settings/demo_settings.lua DemoOfflineBackendTitleInternalData
-- .character_starting_gear (:52-206). Demo backend ids such as
-- "dr_shield_hammer_0000" are reduced to their master-list key. The five DLC
-- careers have no client-side default (PlayFab serves theirs through
-- PlayFabMirrorBase.get_default_loadouts, playfab_mirror_base.lua:1955-1966),
-- so they always take the deterministic master-list scan below.
P.SEED_WEAPONS = {
    dr_ironbreaker = { slot_melee = "dr_shield_hammer", slot_ranged = "dr_rakegun" },
    dr_slayer = { slot_melee = "dr_2h_hammer", slot_ranged = "dr_2h_hammer" },
    dr_ranger = { slot_melee = "dr_2h_hammer", slot_ranged = "dr_crossbow" },
    es_huntsman = { slot_melee = "es_2h_sword", slot_ranged = "es_blunderbuss" },
    es_knight = { slot_melee = "es_2h_hammer", slot_ranged = "es_repeating_handgun" },
    es_mercenary = { slot_melee = "es_2h_sword", slot_ranged = "es_blunderbuss" },
    we_shade = { slot_melee = "we_spear", slot_ranged = "we_crossbow_repeater" },
    we_maidenguard = { slot_melee = "we_1h_sword", slot_ranged = "we_longbow" },
    we_waywatcher = { slot_melee = "we_1h_sword", slot_ranged = "we_longbow" },
    wh_zealot = { slot_melee = "wh_fencing_sword", slot_ranged = "wh_brace_of_pistols" },
    wh_bountyhunter = { slot_melee = "wh_1h_falchion", slot_ranged = "wh_repeating_pistols" },
    wh_captain = { slot_melee = "wh_fencing_sword", slot_ranged = "wh_brace_of_pistols" },
    bw_scholar = { slot_melee = "bw_sword", slot_ranged = "bw_skullstaff_fireball" },
    bw_adept = { slot_melee = "bw_sword", slot_ranged = "bw_skullstaff_fireball" },
    bw_unchained = { slot_melee = "bw_sword", slot_ranged = "bw_skullstaff_fireball" },
}

local RARITY_RANK = { plentiful = 0, common = 1, rare = 2, exotic = 3, unique = 4 }

-- The item types a career accepts in a weapon slot, in vanilla's own order:
-- CareerSettings[career].item_slot_types_by_slot_name[slot]
-- (career_settings.lua:45-51 gives dr_slayer slot_ranged = {"melee","ranged"};
-- career_settings_lake.lua:88-96 gives es_questingknight the same). The
-- fallback keeps the same shape for a career table that lacks the row.
function P.accepted_slot_types(career_settings, career_name, slot_name)
    local career = type(career_settings) == "table" and career_settings[career_name] or nil
    local by_slot = type(career) == "table" and career.item_slot_types_by_slot_name or nil
    local types = type(by_slot) == "table" and by_slot[slot_name] or nil
    if type(types) == "table" and #types > 0 then return types, "career_settings" end
    if slot_name == "slot_melee" then return { "melee" }, "fallback" end
    if slot_name == "slot_ranged" then return { "ranged", "melee" }, "fallback" end
    return {}, "not-a-weapon-slot"
end

local function type_index(accepted, slot_type)
    for i = 1, #accepted do
        if accepted[i] == slot_type then return i end
    end
    return nil
end

local function can_wield(entry, career_name)
    local list = entry.can_wield
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == career_name then return true end
    end
    return false
end

-- A master-list row is a spawnable default when it is a real adventure weapon
-- the career can wield in that slot and it carries what GearUtils.create_equipment
-- needs (a template and at least one hand unit, backend_utils.lua:144-190).
-- Versus variants (`vs_*`), career-skill previews (`*_preview`) and weave
-- (`rarity == "magic"`) rows are never defaults.
function P.is_default_candidate(key, entry, career_name, accepted)
    if type(key) ~= "string" or type(entry) ~= "table" then return false, "not-an-item" end
    if key:sub(1, 3) == "vs_" then return false, "versus-item" end
    if key:sub(-8) == "_preview" then return false, "preview-item" end
    if not type_index(accepted, entry.slot_type) then return false, "slot-type" end
    if entry.rarity == "magic" then return false, "weave-item" end
    if not can_wield(entry, career_name) then return false, "cannot-wield" end
    if type(entry.template) ~= "string" then return false, "no-template" end
    if type(entry.right_hand_unit) ~= "string" and type(entry.left_hand_unit) ~= "string" then
        return false, "no-units"
    end
    return true, "ok"
end

-- Deterministic default weapon key for (career, slot): the demo seed when it
-- still validates against the live master list, otherwise the first row by
-- (accepted type order, rarity rank, key). Returns key, how, entry or nil, why.
function P.select_default_weapon_key(master_list, career_settings, career_name, slot_name)
    if type(master_list) ~= "table" or type(career_name) ~= "string"
        or not P.WEAPON_SLOTS[slot_name] then
        return nil, "invalid"
    end
    local accepted = P.accepted_slot_types(career_settings, career_name, slot_name)
    local seeds = P.SEED_WEAPONS[career_name]
    local seed = seeds and seeds[slot_name] or nil
    if seed ~= nil then
        local entry = rawget(master_list, seed)
        if P.is_default_candidate(seed, entry, career_name, accepted) then
            return seed, "seed", entry
        end
    end
    local best_key, best_rank
    for key, entry in pairs(master_list) do
        if type(entry) == "table" and P.is_default_candidate(key, entry, career_name, accepted) then
            local rank = type_index(accepted, entry.slot_type) * 10
                + (RARITY_RANK[entry.rarity] or 9)
            if best_key == nil or rank < best_rank or (rank == best_rank and key < best_key) then
                best_key, best_rank = key, rank
            end
        end
    end
    if best_key ~= nil then
        return best_key, "scan", rawget(master_list, best_key)
    end
    return nil, "no-candidate"
end

-- The item table SimpleInventoryExtension.add_equipment_by_category consumes
-- (simple_inventory_extension.lua:388-391): `item.data` is cloned, `item.backend_id`
-- is copied onto the clone. No backend id on purpose (see the header).
function P.build_synthetic_item(key, entry)
    if type(key) ~= "string" or type(entry) ~= "table" then return nil end
    return {
        data = entry,
        backend_id = nil,
        key = key,
        ItemId = key,
        rarity = entry.rarity or P.SYNTHETIC_RARITY,
        gut_synthetic_default = true,
    }
end

-- Structural check used by the census: what add_equipment_by_category and
-- create_equipment read from a synthetic default must be present and typed.
function P.validate_synthetic_item(item, key, entry)
    if type(item) ~= "table" then return "item is not a table" end
    if item.data ~= entry then return "item.data is not the master-list entry" end
    if item.backend_id ~= nil then return "synthetic item must not carry a backend id" end
    if item.key ~= key or item.ItemId ~= key then return "item key/ItemId mismatch" end
    if type(item.rarity) ~= "string" then return "item rarity missing" end
    if item.gut_synthetic_default ~= true then return "synthetic marker missing" end
    if type(entry.template) ~= "string" then return "entry template missing" end
    if type(entry.right_hand_unit) ~= "string" and type(entry.left_hand_unit) ~= "string" then
        return "entry has no hand units"
    end
    return nil
end

-- The first owned backend instance of `key` in the live items table, so the
-- career default can spawn as a real, resolvable instance whenever the player
-- owns one. Deterministic: the lowest backend id wins.
function P.find_owned_instance(items, key)
    if type(items) ~= "table" or type(key) ~= "string" then return nil end
    local best
    for backend_id, item in pairs(items) do
        if type(backend_id) == "string" and type(item) == "table" then
            local data = item.data
            local item_key = item.ItemId or item.key or (type(data) == "table" and data.key) or nil
            if item_key == key and (best == nil or backend_id < best) then
                best = backend_id
            end
        end
    end
    return best
end

-- LoadoutUtils.sync_loadout_slot (loadout_utils.lua:13-42) reads key, rarity,
-- power_level, properties and traits from the item add_equipment resolved
-- (simple_inventory_extension.lua:883). For a synthetic default that item is the
-- raw master-list row, which has no power_level, so the RPC gets a shadow.
function P.needs_sync_shadow(slot_name, item, synthetic_keys)
    return P.WEAPON_SLOTS[slot_name] ~= nil
        and type(item) == "table"
        and item.power_level == nil
        and type(item.key) == "string"
        and type(synthetic_keys) == "table"
        and synthetic_keys[item.key] == true
end

function P.shadow_sync_item(item)
    return {
        key = item.key,
        ItemId = item.key,
        data = item.data or item,
        rarity = item.rarity or P.SYNTHETIC_RARITY,
        power_level = P.SYNTHETIC_POWER_LEVEL,
        properties = nil,
        traits = nil,
    }
end

-- Census: every (career, weapon slot) must yield a default whose synthetic
-- shape validates. `careers` is the hero career list; returns nil on success or
-- the first failure text, plus the per-pair results for callers that report.
function P.census(master_list, career_settings, careers)
    if type(master_list) ~= "table" or type(careers) ~= "table" then
        return "census inputs unavailable", {}
    end
    local results = {}
    for i = 1, #careers do
        local career_name = careers[i]
        for slot_name in pairs(P.WEAPON_SLOTS) do
            local key, how, entry = P.select_default_weapon_key(
                master_list, career_settings, career_name, slot_name)
            if key == nil then
                return string.format("no default weapon for %s %s (%s)",
                    tostring(career_name), tostring(slot_name), tostring(how)), results
            end
            local err = P.validate_synthetic_item(P.build_synthetic_item(key, entry), key, entry)
            if err then
                return string.format("%s %s -> %s: %s", career_name, slot_name, key, err), results
            end
            results[#results + 1] = { career = career_name, slot = slot_name, key = key, how = how }
        end
    end
    table.sort(results, function(a, b)
        if a.career ~= b.career then return a.career < b.career end
        return a.slot < b.slot
    end)
    return nil, results
end

return P
