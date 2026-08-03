return function(H, repo_root)
local function load_module()
    return dofile(repo_root .. "/modded_progression/scripts/mods/modded_progression/_mp_loot_diag.lua")
end

local function contains(value, needle)
    if type(value) == "string" then return value:find(needle, 1, true) ~= nil end
    if type(value) ~= "table" then return false end
    for key, child in pairs(value) do
        if contains(key, needle) or contains(child, needle) then return true end
    end
    return false
end

H.test("MP #607 summarizes native loot without retaining backend ids", function()
    local D = load_module()
    local result = { FunctionResult = {
        items = {
            { ItemId = "es_sword", ItemInstanceId = "sensitive-instance-id",
                CustomData = { rarity = "rare", power_level = "211",
                    properties = "[{\"x\":1}]", traits = "[]" } },
        },
        consumed_chest = { ItemInstanceId = "sensitive-chest-id", RemainingUses = 0 },
        unlocked_weapon_skins = { "skin_a" },
    } }
    local ledger, record = D.capture(nil, {
        chest_key = "loot_chest_03_04", hero_name = "empire_soldier",
        game_mode = "adventure", amount = 1,
        rarity_row = { rare = 75.5, exotic = 24.5 },
    }, result, 123)
    H.equal(ledger.serial, 1)
    H.equal(record.items[1].item_key, "es_sword")
    H.equal(record.items[1].rarity, "rare")
    H.equal(record.items[1].power, 211)
    H.truthy(record.items[1].has_properties)
    H.equal(record.items[1].has_traits, false)
    H.equal(record.unlocked_weapon_skins, 1)
    H.equal(contains(ledger, "sensitive-instance-id"), false)
    H.equal(contains(ledger, "sensitive-chest-id"), false)
end)

H.test("MP #607 captures only while active on the modded realm", function()
    local D = load_module()
    -- Modded realm (eac_untrusted == true) is the ONLY realm where this mod
    -- can load (decompile mod_manager.lua:275: unapproved Workshop mods are
    -- excluded from the official-realm scan), so the gate must open there.
    H.equal(D.should_capture(true, true), true)
    -- Official realm and unknown realm state both fail closed.
    H.equal(D.should_capture(false, true), false)
    H.equal(D.should_capture(nil, true), false)
    -- Retirement flag wins regardless of realm.
    H.equal(D.should_capture(true, false), false)
    H.equal(D.should_capture(nil, false), false)
    -- Omitted `active` defaults to M.ACTIVE (currently armed).
    H.equal(D.should_capture(true), D.ACTIVE)
    H.equal(D.is_mission_chest("loot_chest_01_01"), true)
    H.equal(D.is_mission_chest("loot_chest_04_06"), true)
    H.equal(D.is_mission_chest("loot_chest_05_01"), false)
    H.equal(D.is_mission_chest("commendation_chest"), false)
end)

H.test("MP #607 capture is deterministic and bounded", function()
    local D = load_module()
    local result = { FunctionResult = { items = {} } }
    local ledger
    for i = 1, 30 do
        ledger = D.capture(ledger, {
            chest_key = "loot_chest_01_01", rarity_row = { rare = 90, exotic = 10 },
        }, result, i)
    end
    H.equal(#ledger.records, D.MAX_RECORDS)
    H.equal(ledger.records[1].serial, 30 - D.MAX_RECORDS + 1)
    H.equal(ledger.records[#ledger.records].serial, 30)
    H.equal(ledger.records[1].rarity_row[1].rarity, "exotic")
    H.equal(ledger.records[1].rarity_row[2].rarity, "rare")
end)

H.test("MP #607 truncates oversized callback item lists", function()
    local D = load_module()
    local items = {}
    for i = 1, 20 do
        items[i] = { ItemId = "item_" .. i, CustomData = { rarity = "common" } }
    end
    local _, record = D.capture(nil, { chest_key = "loot_chest_01_01" },
        { FunctionResult = { items = items } }, 1)
    H.equal(#record.items, D.MAX_ITEMS)
    H.equal(record.item_count, 20)
    H.equal(record.truncated_items, 20 - D.MAX_ITEMS)
end)

H.test("MP #607 catalogue census is static and slot-bounded", function()
    local D = load_module()
    local facts = D.catalogue_facts({
        a = { slot_type = "melee" },
        b = { slot_type = "ranged", required_dlc = "woods" },
        c = { slot_type = "hat" },
    })
    H.equal(facts.total, 3)
    H.equal(facts.gear, 2)
    H.equal(facts.dlc_gated, 1)
    H.equal(facts.by_slot.melee, 1)
    H.equal(facts.by_slot.ranged, 1)
end)

H.test("MP #607 bounds rarity rows and tolerates crashifying catalogue rows", function()
    local D = load_module()
    local row = {}
    for i = 1, 30 do row["rarity_" .. i] = i end
    local _, record = D.capture(nil, {
        chest_key = "loot_chest_01_01", rarity_row = row,
    }, { FunctionResult = { items = {} } }, 1)
    H.equal(#record.rarity_row, D.MAX_RARITIES)

    local crashifying = setmetatable({ slot_type = "melee" }, {
        __index = function(_, key) error("unexpected missing-key read: " .. tostring(key)) end,
    })
    local facts = D.catalogue_facts({ weapon = crashifying })
    H.equal(facts.gear, 1)
    H.equal(facts.dlc_gated, 0)
end)

H.test("MP #607 normalizes persisted ledgers field by field", function()
    local D = load_module()
    local huge_items, huge_rarities = {}, {}
    for i = 1, 30 do
        huge_items[i] = { item_key = "item_" .. i, rarity = "rare" }
        huge_rarities[i] = { rarity = "rarity_" .. i, chance = i }
    end
    local cyclic = { serial = 9999999, records = {} }
    cyclic.self = cyclic
    for i = 1, 20 do
        cyclic.records[i] = {
            serial = i, chest_key = "loot_chest_01_01", items = huge_items,
            rarity_row = huge_rarities, injected = cyclic,
        }
    end
    local normalized = D.normalize(cyclic)
    H.equal(normalized.serial, 9999999)
    H.equal(#normalized.records, D.MAX_RECORDS)
    H.equal(#normalized.records[1].items, D.MAX_ITEMS)
    H.equal(#normalized.records[1].rarity_row, D.MAX_RARITIES)
    H.equal(normalized.records[1].injected, nil)
end)
end
