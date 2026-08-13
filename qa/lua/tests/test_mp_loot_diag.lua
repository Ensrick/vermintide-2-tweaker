return function(H, repo_root)
local function load_module()
    return dofile(repo_root .. "/modded_progression/scripts/mods/modded_progression/_mp_loot_diag.lua")
end

local function load_runtime()
    return dofile(repo_root
        .. "/modded_progression/scripts/mods/modded_progression/_mp_loot_diag_runtime.lua")
end

local function read_source(relative_path)
    local path = repo_root .. relative_path
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function count_plain(value, needle)
    local count, start = 0, 1
    while true do
        local found = value:find(needle, start, true)
        if not found then return count end
        count = count + 1
        start = found + #needle
    end
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

H.test("MP #607 arms only while active on the modded realm", function()
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

H.test("MP #607 attributes only the two native loot requests", function()
    local D = load_module()
    H.equal(D.request_flow("generateEndOfLevelLoot"), "end_level")
    H.equal(D.request_flow("generateLootChestRewards"), "open")
    H.equal(D.request_flow("generateQuestRewards"), nil)
    H.equal(D.is_target_request("generateEndOfLevelLoot"), true)
    H.equal(D.is_target_request("generateQuestRewards"), false)

    local queue = { _active_entry = {
        request = { FunctionName = "generateEndOfLevelLoot" },
        eac_challenge_success = false,
    } }
    H.equal(D.active_request_name(queue), "generateEndOfLevelLoot")
    H.equal(D.rejection_reason(queue), "eac_unavailable")
    queue._active_entry.eac_challenge_success = true
    H.equal(D.rejection_reason(queue), "eac_failed_verification")
    queue._active_entry.request.FunctionName = "generateQuestRewards"
    H.equal(D.active_request_name(queue), nil)
end)

H.test("MP #607 names the first missing local layer without backend success", function()
    local D = load_module()
    local ledger = D.record(nil, "end_level", {
        flow = "end_level", request_name = "generateEndOfLevelLoot",
    }, 1)
    H.equal(D.diagnose(ledger), "request_enqueue")
    ledger = D.record(ledger, "pre_request", {
        flow = "end_level", request_name = "generateEndOfLevelLoot",
    }, 2)
    H.equal(D.diagnose(ledger), "local_container_award")
    ledger = D.record(ledger, "rejection", {
        flow = "end_level", request_name = "generateEndOfLevelLoot",
        reason = "eac_failed_verification",
    }, 3)
    H.equal(D.diagnose(ledger), "local_container_award")
    H.equal(ledger.records[3].reason, "eac_failed_verification")
end)

H.test("MP #607 local ledger census ignores backend ids and counts container uses", function()
    local D = load_module()
    local inventory = {
        ["sensitive-backend-id"] = { ItemId = "loot_chest_03_04", RemainingUses = 2 },
        other = { ItemId = "es_sword" },
        empty = { ItemId = "loot_chest_01_01", RemainingUses = 0 },
    }
    local facts = D.local_ledger_facts(inventory)
    H.equal(facts.items, 3)
    H.equal(facts.containers, 2)
    H.equal(facts.container_uses, 2)
    H.equal(facts.award_capable, false)
    H.equal(facts.open_capable, false)
    H.equal(contains(facts, "sensitive-backend-id"), false)
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

H.test("MP #607 production instruments actual local seams with bounded printf", function()
    local source = read_source(
        "/modded_progression/scripts/mods/modded_progression/_mp_loot_diag_runtime.lua")
    local main = read_source(
        "/modded_progression/scripts/mods/modded_progression/modded_progression.lua")
    H.equal(count_plain(source,
        'mod:hook("BackendInterfaceLootPlayfab", "generate_end_of_level_loot"'), 1)
    H.equal(count_plain(source,
        'mod:hook("BackendInterfaceLootPlayfab", "open_loot_chest"'), 1)
    H.equal(count_plain(source,
        'mod:hook("PlayFabRequestQueue", "enqueue"'), 1)
    H.equal(count_plain(source,
        'mod:hook("BackendManagerPlayFab", "playfab_eac_error"'), 1)
    H.equal(count_plain(source,
        'mod:hook("BackendManagerPlayFab", "playfab_api_error"'), 1)
    H.equal(count_plain(source,
        'mod:hook("BackendInterfaceLootPlayfab", "loot_chest_rewards_request_cb"'), 1)
    H.truthy(source:find("_mp607_consolidated_loot_layer_diagnostics", 1, true))
    H.truthy(source:find('print_log("[mp:607] event=%s', 1, true))
    H.equal(source:find('_dbg_alert("[mp:607]', 1, true), nil)
    H.truthy(source:find(
        'rt_register("issue607_local_loot_layer_diagnostic_contract"', 1, true))
    H.truthy(source:find('emit_local_ledger("end_level"', 1, true))
    H.truthy(source:find("emit_rejection(self)", 1, true))
    H.equal(count_plain(main,
        'mod:dofile("scripts/mods/modded_progression/_mp_loot_diag_runtime").install'), 1)
end)

H.test("MP #607 runtime adapters delegate and diagnose a rejected mission request", function()
    local D = load_module()
    local hooks, commands, checks, saved, logs, echoes = {}, {}, {}, {}, {}, {}
    local inventory = {
        ["sensitive-local-id"] = { ItemId = "es_sword" },
    }
    local mod = {}
    function mod:hook(class_name, method_name, callback)
        hooks[class_name .. "." .. method_name] = callback
    end
    function mod:command(name, _, callback) commands[name] = callback end
    function mod:get(key) return saved[key] end
    function mod:set(key, value) saved[key] = value end
    function mod:echo(fmt, ...)
        echoes[#echoes + 1] = string.format(fmt, ...)
    end

    local tick = 100
    load_runtime().install(mod, {
        loot_diag = D,
        get_inventory_store = function() return inventory end,
        rt_register = function(name, callback) checks[name] = callback end,
        realm_state = function() return { ["eac-untrusted"] = true } end,
        print_log = function(fmt, ...)
            logs[#logs + 1] = string.format(fmt, ...)
        end,
        item_master_list = function() return {} end,
        capture = function(...) return select("#", ...), { ... } end,
        unpack_results = unpack,
        now = function() tick = tick + 1 return tick end,
    })

    local enqueue = assert(hooks["PlayFabRequestQueue.enqueue"])
    local delegated_count, delegated_last
    local function native_end(...)
        delegated_count = select("#", ...)
        delegated_last = select(delegated_count, ...)
        local queue_id, hole, queue_tail = enqueue(function()
            return 91, nil, "queue-tail"
        end, {}, { FunctionName = "generateEndOfLevelLoot" }, function() end,
            true, function() end, "future-queue-arg")
        H.equal(queue_id, 91)
        H.equal(hole, nil)
        H.equal(queue_tail, "queue-tail")
        return "native-end", nil, "end-tail"
    end

    local end_hook = assert(hooks[
        "BackendInterfaceLootPlayfab.generate_end_of_level_loot"])
    local first, hole, last = end_hook(native_end, {}, true, false, "cataclysm",
        "level_key", "empire_soldier", 1, 2, 3, 4, "loot_profile", nil,
        nil, "adventure", 123, { score = 1 }, "future-end-arg")
    H.equal(first, "native-end")
    H.equal(hole, nil)
    H.equal(last, "end-tail")
    H.equal(delegated_count, 17)
    H.equal(delegated_last, "future-end-arg")

    local diagnostic = saved.issue607_loot_diag_v1
    H.equal(diagnostic.records[1].event, "end_level")
    H.equal(diagnostic.records[2].event, "pre_request")
    H.equal(diagnostic.records[3].event, "local_ledger")
    H.equal(D.diagnose(diagnostic), "local_container_award")

    local queue = { _active_entry = {
        request = { FunctionName = "generateEndOfLevelLoot" },
        eac_challenge_success = true,
    } }
    local backend = { _backend_mirror = {
        request_queue = function() return queue end,
    } }
    local rejection = assert(hooks["BackendManagerPlayFab.playfab_eac_error"])
    H.equal(rejection(function(_, marker) return marker end, backend, "native-error"),
        "native-error")
    diagnostic = saved.issue607_loot_diag_v1
    H.equal(diagnostic.records[4].event, "rejection")
    H.equal(diagnostic.records[4].reason, "eac_failed_verification")
    H.equal(diagnostic.records[5].event, "local_ledger")
    H.equal(contains(diagnostic, "sensitive-local-id"), false)

    local joined = table.concat(logs, "\n")
    H.truthy(joined:find("event=end_level", 1, true))
    H.truthy(joined:find("event=pre_request", 1, true))
    H.truthy(joined:find("event=rejection", 1, true))
    H.truthy(joined:find("first_missing=local_container_award", 1, true))
    H.equal(checks.issue607_local_loot_layer_diagnostic_contract(), nil)
    commands.mp_loot_diag()
    H.truthy(echoes[1]:find("first_missing=local_container_award", 1, true))
end)
end
