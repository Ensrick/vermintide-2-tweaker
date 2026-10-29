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
    -- Modded realm (realm query answered exactly true) is the ONLY realm where
    -- this mod can load (decompile 6.13.0 mod_manager.lua:273: unapproved
    -- Workshop mods are excluded from the official-realm scan), so the gate
    -- must open there.
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
    H.equal(D.is_positive_request_id(1), true)
    H.equal(D.is_positive_request_id(0), false)
    H.equal(D.is_positive_request_id(-1), false)
    H.equal(D.is_positive_request_id("1"), false)
    H.equal(D.is_positive_request_id(0 / 0), false)
    H.equal(D.is_positive_request_id(math.huge), false)

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
        'mod:hook("StateInGameRunning", "gm_event_end_conditions_met"'), 1)
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
        is_modded_realm = function() return true end,
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

    local records_before_invalid_ids = #diagnostic.records
    enqueue(function() return nil, "not-enqueued" end, {},
        { FunctionName = "generateEndOfLevelLoot" }, function() end,
        true, function() end)
    for _, invalid_id in ipairs({ 0, -1, "91", math.huge }) do
        enqueue(function() return invalid_id end, {},
            { FunctionName = "generateEndOfLevelLoot" }, function() end,
            true, function() end)
    end
    H.equal(#saved.issue607_loot_diag_v1.records, records_before_invalid_ids)

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

H.test("MP #607 observer throws cannot alter any of the six native wrappers", function()
    local D = load_module()
    local hooks, saved, logs = {}, {}, {}
    local fail = {}
    local mod = {}
    function mod:hook(class_name, method_name, callback)
        hooks[class_name .. "." .. method_name] = callback
    end
    function mod:command() end
    function mod:get(key)
        if fail.persist_read then error("planted persistence read") end
        return saved[key]
    end
    function mod:set(key, value)
        if fail.persist_write then error("planted persistence write") end
        saved[key] = value
    end
    function mod:echo() end

    load_runtime().install(mod, {
        loot_diag = D,
        get_inventory_store = function()
            if fail.inventory then error("planted inventory read") end
            return {}
        end,
        rt_register = function() end,
        is_modded_realm = function()
            if fail.realm then error("planted realm read") end
            return true
        end,
        print_log = function(fmt, ...)
            if fail.log then error("planted printf") end
            logs[#logs + 1] = string.format(fmt, ...)
        end,
        item_master_list = function() return {} end,
        now = function() return 1 end,
    })

    local native_calls = 0
    local function nil_hole_native()
        native_calls = native_calls + 1
        return nil, "native-second", nil, "native-fourth", nil
    end
    local function assert_nil_hole_tuple(callback, ...)
        local function pack(...)
            return { n = select("#", ...), ... }
        end
        local results = pack(callback(nil_hole_native, ...))
        H.equal(results.n, 5)
        H.equal(results[1], nil)
        H.equal(results[2], "native-second")
        H.equal(results[3], nil)
        H.equal(results[4], "native-fourth")
        H.equal(results[5], nil)
    end

    -- Realm read throws before mission-entry capture; native still receives the
    -- call and all first/middle/trailing nil results survive.
    fail.realm = true
    assert_nil_hole_tuple(assert(hooks[
        "BackendInterfaceLootPlayfab.generate_end_of_level_loot"]), {})
    fail.realm = nil
    local first_logs = table.concat(logs, "\n")
    H.truthy(first_logs:find("reason=observer_failed", 1, true))
    H.equal(first_logs:find("planted realm read", 1, true), nil)

    -- Chest-context getter throws before the open observation.
    local throwing_context = { _backend_mirror = {
        get_all_inventory_items = function() error("planted chest context") end,
    } }
    assert_nil_hole_tuple(assert(hooks[
        "BackendInterfaceLootPlayfab.open_loot_chest"]), throwing_context,
        "empire_soldier", "private-id", "adventure", 1)

    -- A printf failure occurs after a proven positive enqueue id. The native
    -- tuple has a middle and trailing nil and is returned byte-for-byte.
    fail.log = true
    local enqueue_calls = 0
    local function enqueue_native()
        enqueue_calls = enqueue_calls + 1
        return 17, nil, "queue-third", nil
    end
    local function pack(...)
        return { n = select("#", ...), ... }
    end
    local enqueue_results = pack(assert(hooks["PlayFabRequestQueue.enqueue"])(
        enqueue_native, {}, { FunctionName = "generateEndOfLevelLoot" },
        function() end, true, function() end))
    H.equal(enqueue_results.n, 4)
    H.equal(enqueue_results[1], 17)
    H.equal(enqueue_results[2], nil)
    H.equal(enqueue_results[3], "queue-third")
    H.equal(enqueue_results[4], nil)
    H.equal(enqueue_calls, 1)
    fail.log = nil

    -- Rejection context is observer-only; a throwing queue accessor cannot
    -- prevent either native error owner.
    local throwing_queue = { _backend_mirror = {
        request_queue = function() error("planted queue read") end,
    } }
    assert_nil_hole_tuple(assert(hooks[
        "BackendManagerPlayFab.playfab_eac_error"]), throwing_queue)

    fail.inventory = true
    local target_queue = { _active_entry = {
        request = { FunctionName = "generateEndOfLevelLoot" },
        eac_challenge_success = false,
    } }
    local valid_backend = { _backend_mirror = {
        request_queue = function() return target_queue end,
    } }
    assert_nil_hole_tuple(assert(hooks[
        "BackendManagerPlayFab.playfab_api_error"]), valid_backend,
        {}, 500)
    fail.inventory = nil

    -- Callback context succeeds, but diagnostic persistence can fail on either
    -- read or write without becoming a dependency of native delegation.
    local callback_self = { _backend_mirror = {
        get_all_inventory_items = function()
            return { chest = { ItemId = "loot_chest_01_01" } }
        end,
        get_rarity_tables = function() return {} end,
    } }
    fail.persist_read = true
    assert_nil_hole_tuple(assert(hooks[
        "BackendInterfaceLootPlayfab.loot_chest_rewards_request_cb"]),
        callback_self, { playfab_id = "chest" },
        { FunctionResult = { items = {} } })
    fail.persist_read = nil

    fail.persist_write = true
    assert_nil_hole_tuple(assert(hooks[
        "BackendInterfaceLootPlayfab.loot_chest_rewards_request_cb"]),
        callback_self, { playfab_id = "chest" },
        { FunctionResult = { items = {} } })
    fail.persist_write = nil

    H.equal(native_calls, 6)
    H.equal(table.concat(logs, "\n"):find("planted", 1, true), nil)
end)

-- Complete native end-condition body + actual installed observer. These caller
-- globals/commit storage are recording fixtures, never a backend dispatcher.
local function native_end_rig(options)
    options = options or {}
    local D, saved, logs, hooks = load_module(), {}, {}, {}
    if options.inactive then D.ACTIVE = false end
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local realm = assert(loadfile(repo_root .. "/qa/lua/tests/test_mp_loot_diag_realm_gate.lua"))()(quiet, repo_root)
    local realm_query = realm.shipped_realm_query()
    local c = { D = D, saved = saved, logs = logs, hooks = hooks, native_calls = 0,
        commits = 0, awards = 0, queue = {}, errors = 0, screens = 0, effects = {},
        commands = {}, echoes = {}, print_attempts = 0, attempted_formats = {} }
    local read_only = options.read_only
    if read_only == nil then read_only = true end
    local env = setmetatable({}, { __index = _G }); env._G = env
    env.MODDED_REALM = not options.official
    env.GameSettingsDevelopment = { read_only_backend = read_only, achievements_disabled = true }
    env.script_data = { ["eac-untrusted"] = "unchanged-legacy-flag" }
    env.GameSettings = { transition_fade_in_speed = 1 }
    env.GameModeSettings = { adventure = { end_mission_rewards = true }, versus = { end_mission_rewards = true } }
    env.DialogueSystem = { stateless_global_context = {} }
    env.IS_PS4, env.IS_XB1 = false, false
    env.print = function() end
    local function effect(key) c.effects[key] = (c.effects[key] or 0) + 1 end
    env.LevelUnlockUtils = { completed_level_difficulty_index = function() return 0 end }
    env.StatisticsUtil = {
        register_complete_level = function() effect("complete_stat") end,
        reset_mission_streak = function() effect("reset_streak") end,
    }
    env.LoreBookHelper = { save_new_pages = function() effect("lore") end }
    env.callback = function(self, name, ...)
        c.deferred = { self = self, name = name, n = select("#", ...), ... }
        return function() end
    end
    local ui = { handle_transition = function(_, name) H.equal(name, "close_active"); effect("close") end,
        activate_end_screen_ui = function() c.screens = c.screens + 1 end }
    local mission = { set_percentage_completed = function(_, value) H.equal(value, c.percentages); effect("percentage") end }
    local stats = { save = function() effect("save") end }
    local backend = {
        get_interface = function(_, name) H.equal(name, "statistics"); return stats end,
        commit = function(_, force, fn) H.equal(force, true); c.commits = c.commits + 1; c.commit_callback = fn end,
        commit_error = function() c.errors = c.errors + 1 end,
    }
    env.Managers = {
        transition = { hide_loading_icon = function() effect("hide") end, fade_out = function() effect("fade") end },
        mechanism = { is_final_round = function() return true end, load_end_screen_resources = function() effect("resources") end },
        ui = { temporary_get_ingame_ui_called_from_state_ingame_running = function() return ui end },
        backend = backend,
        state = { difficulty = { get_difficulty = function() return "hard" end },
            game_mode = { level_key = function() return "level_key" end,
                evaluate_end_condition_outcome = function(_, reason, player)
                    H.equal(reason, c.reason); H.equal(player, c.player)
                    if options.native_error then error(options.native_error, 0) end
                    return true, false
                end,
                get_end_screen_config = function() return "win", "config", {} end },
            entity = { system = function(_, name) H.equal(name, "mission_system"); return mission end },
            achievement = { evaluate_end_of_level_achievements = function() effect("achievement") end } },
    }
    c.env, c.percentages, c.reason = env, { private = "sensitive_percentage" }, "sensitive_reason"
    c.player = { stats_id = function() return "sensitive_stats_id" end }
    c.state = { is_server = true, game_mode_key = "adventure", _game_has_started = true,
        player = c.player, statistics_db = {}, parent = { parent = { loading_context = {} } },
        _award_end_of_level_rewards = function(_, ...)
            c.awards = c.awards + 1
            -- Records the continuation the actual native guard admits, no IO.
            c.queue[#c.queue + 1] = { name = "native_award_continuation", n = select("#", ...) }
        end }
    if options.early then c.state.is_server = false; c.state.game_mode_key = "versus" end
    local native_chunk = assert(loadfile(repo_root .. "/qa/lua/fixtures/mp607_end_conditions_native.lua"))
    setfenv(native_chunk, env)
    local class = native_chunk()
    local native = class.gm_event_end_conditions_met
    class.gm_event_end_conditions_met = function(self, ...)
        c.native_calls = c.native_calls + 1
        return native(self, ...)
    end
    local mod = {}
    function mod:hook(name, method, fn)
        H.equal(hooks[name .. "." .. method], nil, "one installed hook per target")
        hooks[name .. "." .. method] = fn
        if name == "StateInGameRunning" and type(class[method]) == "function" then
            local original = class[method]
            class[method] = function(...) return fn(original, ...) end
        end
    end
    function mod:command(name, _, fn) c.commands[name] = fn end
    function mod:echo(fmt, ...) c.echoes[#c.echoes + 1] = string.format(fmt, ...) end
    function mod:get(key)
        if options.observer_throw == "read" then error("sensitive observer read", 0) end
        return saved[key]
    end
    function mod:set(key, value)
        if options.observer_throw == "write" then error("sensitive observer write", 0) end
        saved[key] = value
    end
    local runtime_source = read_source("/modded_progression/scripts/mods/modded_progression/_mp_loot_diag_runtime.lua")
    if options.disconnect then
        local needle = 'mod:hook("StateInGameRunning", "gm_event_end_conditions_met",'
        H.equal(count_plain(runtime_source, needle), 1, "one actual production hook mutation")
        local at = assert(runtime_source:find(needle, 1, true))
        runtime_source = runtime_source:sub(1, at - 1)
            .. 'mod:hook("StateInGameRunning", "_mp607_disconnected_end_conditions",'
            .. runtime_source:sub(at + #needle)
    end
    if options.disconnect_budget then
        local needle = "if automatic_print_attempts >= 12 then return false end"
        H.equal(count_plain(runtime_source, needle), 1, "one actual print admission guard")
        local at = assert(runtime_source:find(needle, 1, true))
        runtime_source = runtime_source:sub(1, at - 1)
            .. "if false then return false end" .. runtime_source:sub(at + #needle)
    end
    local runtime_chunk = assert(loadstring(runtime_source, "@mp607_actual_runtime"))
    setfenv(runtime_chunk, env)
    if not options.no_observer then runtime_chunk().install(mod, {
        loot_diag = D, get_inventory_store = function()
            if options.observer_throw == "inventory" then error("sensitive inventory read", 0) end
            return { sensitive_inventory_id = { ItemId = "es_sword" } }
        end,
        rt_register = function() end,
        is_modded_realm = function()
            if options.observer_throw == "realm" then error("sensitive realm read", 0) end
            return realm_query(D, env, function() return false end)
        end,
        print_log = function(fmt, ...)
            c.print_attempts = c.print_attempts + 1
            c.attempted_formats[#c.attempted_formats + 1] = fmt
            if options.observer_throw == "log" then error("sensitive log", 0) end
            logs[#logs + 1] = string.format(fmt, ...)
        end,
        item_master_list = function() return {} end,
        now = function()
            if options.observer_throw == "clock" then error("sensitive clock", 0) end
            return 1
        end,
    }) end
    local function pack(...) return { n = select("#", ...), ... } end
    function c.run()
        return pack(class.gm_event_end_conditions_met(c.state, c.reason, true, c.percentages))
    end
    function c.complete(status) return assert(c.commit_callback, "real native commit callback")(status or "commit_done") end
    function c.flags()
        H.equal(env.GameSettingsDevelopment.read_only_backend, read_only)
        H.equal(env.GameSettingsDevelopment.achievements_disabled, true)
        H.equal(env.MODDED_REALM, not options.official)
        H.equal(env.script_data["eac-untrusted"], "unchanged-legacy-flag")
    end
    return c
end

local function readonly_entry_case(disconnect)
    local c = native_end_rig({ disconnect = disconnect })
    H.equal(c.run().n, 0, "complete native function naturally returns no results")
    H.equal(c.native_calls, 1); H.equal(c.commits, 1)
    H.equal(c.awards, 0); H.equal(#c.queue, 0); H.equal(c.screens, 0)
    c.complete()
    H.equal(c.screens, 1); H.equal(c.awards, 0); H.equal(#c.queue, 0); c.flags()
    local rows = c.saved.issue607_loot_diag_v1 and c.saved.issue607_loot_diag_v1.records or {}
    H.truthy(rows[1] and rows[1].event == "end_condition_entry",
        "actual end-condition entry receipt before readonly award gate")
    H.equal(#rows, 1, "no fabricated completion/backend request")
    H.equal(rows[1].reason, "readonly_award_gate_at_entry")
    H.equal(rows[1].request_name, "unknown"); H.equal(rows[1].backend, "none")
    H.equal(rows[1].local_items, 1); H.equal(rows[1].local_containers, 0)
    H.equal(rows[1].local_award_capable, false); H.equal(rows[1].local_open_capable, false)
    H.equal(c.D.diagnose(c.saved.issue607_loot_diag_v1), "readonly_award_gate_at_entry")
    H.equal(contains(c.saved, "sensitive"), false)
    H.equal(contains(table.concat(c.logs, "\n"), "sensitive"), false)
    return c
end

H.test("MP #607 end-condition reasons and latest entry never imply completion", function()
    local D = load_module()
    H.equal(D.end_condition_reason(true), "readonly_award_gate_at_entry")
    H.equal(D.end_condition_reason(false), "award_gate_open_at_entry")
    H.equal(D.end_condition_reason(nil), "award_gate_unknown_at_entry")
    H.equal(D.end_condition_reason("true"), "award_gate_unknown_at_entry")
    local ledger = D.record(nil, "end_level", { flow = "end_level" }, 1)
    ledger = D.record(ledger, "pre_request", { flow = "end_level" }, 2)
    ledger = D.record(ledger, "end_condition_entry", { flow = "end_level",
        reason = D.end_condition_reason(true), ignored_player_id = "sensitive" }, 3)
    H.equal(D.diagnose(ledger), "readonly_award_gate_at_entry")
    H.equal(contains(ledger, "sensitive"), false); H.equal(D.MAX_RECORDS, 12)
    ledger = D.record(ledger, "end_condition_entry", { reason = D.end_condition_reason(nil) }, 4)
    H.equal(D.diagnose(ledger), "end_condition_entry_only")
end)

H.test("MP #607 actual native readonly commit path records entry without a loot request", function()
    readonly_entry_case(false)
end)

H.test("MP #607 same native receipt oracle rejects disconnected production entry hook", function()
    local ok, failure = pcall(readonly_entry_case, true)
    H.equal(ok, false, "disconnected observer must not fake a passing receipt")
    H.truthy(tostring(failure):find("actual end-condition entry receipt before readonly award gate", 1, true),
        "control must fail the same receipt oracle, not setup/native behavior")
end)

H.test("MP #607 native early return is observed as entry never completion", function()
    local c = native_end_rig({ early = true })
    H.equal(c.run().n, 0); H.equal(c.native_calls, 1); H.equal(c.commits, 0)
    H.equal(c.state.end_conditions_met, nil); H.equal(c.awards, 0); H.equal(#c.queue, 0)
    H.equal(c.deferred.name, "gm_event_end_conditions_met"); H.equal(c.deferred.n, 3)
    H.equal(c.deferred[1], c.reason); H.equal(c.deferred[2], true); H.equal(c.deferred[3], c.percentages)
    H.equal(c.D.diagnose(c.saved.issue607_loot_diag_v1), "readonly_award_gate_at_entry"); c.flags()
end)

H.test("MP #607 actual commit error remains native and entry is not success", function()
    local c = native_end_rig()
    c.run(); c.complete("commit_error")
    H.equal(c.errors, 1); H.equal(c.screens, 0); H.equal(c.awards, 0); H.equal(#c.queue, 0)
    H.equal(#c.saved.issue607_loot_diag_v1.records, 1)
    H.equal(c.saved.issue607_loot_diag_v1.records[1].event, "end_condition_entry"); c.flags()
end)

H.test("MP #607 official and retired capture preserve actual native callback behavior", function()
    for _, options in ipairs({ { official = true, read_only = false }, { inactive = true } }) do
        local direct_options = { official = options.official, read_only = options.read_only, no_observer = true }
        local baseline, c = native_end_rig(direct_options), native_end_rig(options)
        H.equal(c.run().n, baseline.run().n); c.complete(); baseline.complete()
        H.equal(c.native_calls, baseline.native_calls); H.equal(c.commits, baseline.commits)
        H.equal(c.awards, baseline.awards); H.equal(#c.queue, #baseline.queue)
        H.equal(c.screens, baseline.screens); c.flags()
        H.equal(c.saved.issue607_loot_diag_v1, nil); H.equal(#c.logs, 0)
    end
end)

H.test("MP #607 observer faults cannot alter complete native readonly path", function()
    for _, fault in ipairs({ "realm", "inventory", "read", "write", "clock", "log" }) do
        local c = native_end_rig({ observer_throw = fault })
        H.equal(c.run().n, 0, fault); c.complete()
        H.equal(c.native_calls, 1, fault); H.equal(c.commits, 1, fault); H.equal(c.screens, 1, fault)
        H.equal(c.awards, 0, fault); H.equal(#c.queue, 0, fault); c.flags()
        H.equal(contains(table.concat(c.logs, "\n"), "sensitive"), false, fault)
    end
end)

H.test("MP #607 entry wrapper preserves all arguments nil-hole tuples and exact native errors", function()
    local c, self, checkpoint, percentages, tail = native_end_rig(), {}, {}, {}, {}
    local hook = assert(c.hooks["StateInGameRunning.gm_event_end_conditions_met"])
    local calls, received = 0
    local function pack(...) return { n = select("#", ...), ... } end
    local values = pack(hook(function(...)
        calls = calls + 1; received = pack(...)
        return nil, "second", nil, false, nil
    end, self, "reason", checkpoint, percentages, nil, tail, nil))
    H.equal(calls, 1); H.equal(received.n, 7)
    H.equal(received[1], self); H.equal(received[2], "reason")
    H.equal(received[3], checkpoint); H.equal(received[4], percentages)
    H.equal(received[5], nil); H.equal(received[6], tail); H.equal(received[7], nil)
    H.equal(values.n, 5); H.equal(values[1], nil); H.equal(values[2], "second")
    H.equal(values[3], nil); H.equal(values[4], false); H.equal(values[5], nil)
    local sentinel = {}
    local failing = native_end_rig({ native_error = sentinel })
    local ok, failure = pcall(failing.run)
    H.equal(ok, false); H.equal(failure, sentinel); H.equal(failing.native_calls, 1)
    H.equal(failing.commits, 0); H.equal(failing.awards, 0); H.equal(#failing.queue, 0); failing.flags()
end)


local function bounded_native_entry_case(disconnect_budget)
    local c = native_end_rig({ disconnect_budget = disconnect_budget })
    for _ = 1, 13 do
        H.equal(c.run().n, 0)
        c.complete()
    end
    H.equal(c.native_calls, 13); H.equal(c.commits, 13); H.equal(c.screens, 13)
    H.equal(c.awards, 0); H.equal(#c.queue, 0); c.flags()
    local ledger = assert(c.saved.issue607_loot_diag_v1)
    H.equal(ledger.serial, 13, "printing exhaustion must not stop ledger capture")
    H.equal(#ledger.records, 12)
    for _, row in ipairs(ledger.records) do
        H.equal(row.event, "end_condition_entry")
        H.equal(row.reason, "readonly_award_gate_at_entry")
    end
    local before_prints = c.print_attempts
    c.commands.mp_loot_diag()
    H.equal(#c.echoes, 13, "explicit report remains available after automatic exhaustion")
    H.equal(c.print_attempts, before_prints, "explicit report must not consume automatic budget")
    -- Every native/callback/ledger/report assertion above is identical for the
    -- control. The one intended failure is too many logger attempts here.
    H.equal(c.print_attempts, 12, "automatic receipt print-attempt cap")
    H.equal(#c.logs, 12)
    return c
end

H.test("MP #607 repeated real native entries exhaust prints not ledger or native flow", function()
    bounded_native_entry_case(false)
end)

H.test("MP #607 existing explicit reset rearms exactly one automatic print window", function()
    local c = bounded_native_entry_case(false)
    c.commands.mp_loot_diag("reset")
    H.equal(c.saved.issue607_loot_diag_v1.serial, 0)
    H.equal(#c.saved.issue607_loot_diag_v1.records, 0)
    H.equal(c.print_attempts, 12, "reset reply is not an automatic logger call")
    for _ = 1, 13 do H.equal(c.run().n, 0); c.complete() end
    H.equal(c.native_calls, 26); H.equal(c.commits, 26); H.equal(c.screens, 26)
    H.equal(c.awards, 0); H.equal(#c.queue, 0); c.flags()
    H.equal(c.print_attempts, 24, "exactly twelve attempts in each explicit window")
    H.equal(#c.logs, 24)
    H.equal(c.saved.issue607_loot_diag_v1.serial, 13)
    H.equal(#c.saved.issue607_loot_diag_v1.records, 12)
end)

H.test("MP #607 shared attempt cap includes throwing logs and instrument errors", function()
    for _, fault in ipairs({ "realm", "inventory", "read", "write", "clock", "log" }) do
        local c = native_end_rig({ observer_throw = fault })
        for _ = 1, 13 do H.equal(c.run().n, 0, fault); c.complete() end
        H.equal(c.native_calls, 13, fault); H.equal(c.commits, 13, fault)
        H.equal(c.screens, 13, fault); H.equal(c.awards, 0, fault)
        H.equal(#c.queue, 0, fault); c.flags()
        H.equal(c.print_attempts, 12, "all automatic routes share attempts: " .. fault)
        if fault == "log" then
            H.equal(#c.logs, 0, "throwing logger has no successful receipt")
            H.equal(c.saved.issue607_loot_diag_v1.serial, 13)
            H.equal(#c.saved.issue607_loot_diag_v1.records, 12)
            H.truthy(c.attempted_formats[2]:find("event=instrument_error", 1, true),
                "logger failure must exercise the same capped observer-error sink")
        else
            H.equal(#c.logs, 12, fault)
            H.truthy(c.logs[1]:find("event=instrument_error", 1, true), fault)
        end
        H.equal(contains(table.concat(c.logs, "\n"), "sensitive"), false, fault)
    end
end)

H.test("MP #607 throwing reset cannot rearm prints before its existing ledger write returns", function()
    local options = { observer_throw = "log" }
    local c = native_end_rig(options)
    for _ = 1, 13 do c.run(); c.complete() end
    H.equal(c.print_attempts, 12)
    options.observer_throw = "write"
    local ok, failure = pcall(c.commands.mp_loot_diag, "reset")
    H.equal(ok, false); H.truthy(tostring(failure):find("sensitive observer write", 1, true))
    H.equal(c.native_calls, 13)
    options.observer_throw = nil
    c.run(); c.complete()
    H.equal(c.print_attempts, 12, "failed reset must not reopen the automatic sink")
    H.equal(c.saved.issue607_loot_diag_v1.serial, 14)
    c.commands.mp_loot_diag("reset")
    c.run(); c.complete()
    H.equal(c.print_attempts, 13)
    H.equal(c.saved.issue607_loot_diag_v1.serial, 1)
    H.equal(c.native_calls, 15); H.equal(c.commits, 15); H.equal(c.screens, 15)
    H.equal(c.awards, 0); H.equal(#c.queue, 0); c.flags()
end)

H.test("MP #607 disconnected actual print gate fails only the same attempted-receipt oracle", function()
    local ok, failure = pcall(bounded_native_entry_case, true)
    H.equal(ok, false, "disconnected print gate must not survive")
    H.truthy(tostring(failure):find("automatic receipt print-attempt cap: expected 12, got 13", 1, true),
        "control must fail the attempted-receipt count after native/ledger/report checks")
end)
end
