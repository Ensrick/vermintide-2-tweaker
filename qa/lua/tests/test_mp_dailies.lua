return function(H, repo_root)
    local function load_module()
        local storage = {}
        local fake_mod = {
            get = function(_, key) return storage[key] end,
            set = function(_, key, value) storage[key] = value end,
        }
        local old_get_mod = _G.get_mod
        local old_settings = _G.QuestSettings
        local old_printf = _G.printf
        local preload_key = "scripts/managers/quest/quest_templates"
        local old_preload = package.preload[preload_key]
        local old_loaded = package.loaded[preload_key]

        local objective_names = {
            "daily_collect_grimoires", "daily_collect_loot_die", "daily_collect_painting_scrap",
            "daily_collect_tomes", "daily_complete_levels_hero_bright_wizard",
            "daily_complete_levels_hero_dwarf_ranger", "daily_complete_levels_hero_empire_soldier",
            "daily_complete_levels_hero_witch_hunter", "daily_complete_levels_hero_wood_elf",
            "daily_complete_quickplay_missions", "daily_kill_bosses", "daily_kill_critters",
            "daily_kill_elites", "daily_score_headshots",
        }
        local quest_settings = { stat_mappings = {} }
        local quest_templates = { quests = {} }
        for _, name in ipairs(objective_names) do
            quest_settings[name] = 2
            quest_templates.quests[name] = {
                name = name,
                stat_mappings = {{ qualifying_event = true }},
            }
        end

        _G.get_mod = function() return fake_mod end
        _G.QuestSettings = quest_settings
        _G.printf = function() end
        package.loaded[preload_key] = nil
        package.preload[preload_key] = function() return quest_templates end
        local path = repo_root .. "/modded_progression/scripts/mods/modded_progression/mp_dailies.lua"
        local module = assert(loadfile(path))()

        local function restore()
            _G.get_mod = old_get_mod
            _G.QuestSettings = old_settings
            _G.printf = old_printf
            package.preload[preload_key] = old_preload
            package.loaded[preload_key] = old_loaded
        end
        return module, storage, restore
    end

    H.test("MP daily roster is deterministic and independent of official quests", function()
        local D, storage, restore = load_module()
        local ok, failure = pcall(function()
            local now = os.time()
            local first = D.ensure(now)
            local first_ids = {}
            for key, entry in pairs(first.entries) do first_ids[key] = entry.id end
            storage[D.STATE_KEY] = nil
            local second = D.ensure(now)
            for key, id in pairs(first_ids) do H.equal(second.entries[key].id, id) end
            local count = 0
            for _ in pairs(second.entries) do count = count + 1 end
            H.equal(count, 3)
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("MP daily progress persists and claim credits exactly once", function()
        local D, storage, restore = load_module()
        local ok, failure = pcall(function()
            local state = D.ensure(os.time())
            local quest_slice = D.quest_slice()
            D.increment(quest_slice, "qualifying_event")
            D.increment(quest_slice, "qualifying_event")
            local completed = D.ensure()
            local id
            for _, entry in pairs(completed.entries) do
                H.equal(entry.progress, 2)
                id = id or entry.id
            end
            local granted, amount = D.claim({ id })
            H.truthy(granted)
            H.equal(amount, 5)
            H.equal(D.balance(), 5)
            local duplicate = D.claim({ id })
            H.equal(duplicate, nil)
            H.equal(D.balance(), 5)
            H.truthy(storage[D.STATE_KEY].ledger.transactions[id])
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("MP shilling ledger publishes bounded UI revisions", function()
        local D, _, restore = load_module()
        local ok, failure = pcall(function()
            D.ensure(os.time())
            local initial = D.ui_revision()
            H.truthy(initial > 0)
            H.truthy(D.credit(7))
            local credited = D.ui_revision()
            H.truthy(credited > initial)
            H.truthy(D.spend(2))
            H.truthy(D.ui_revision() > credited)
            local before_reset = D.ui_revision()
            H.truthy(D.reset())
            H.truthy(D.ui_revision() > before_reset)
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("MP daily clock rollback retains the high-water roster", function()
        local D, _, restore = load_module()
        local ok, failure = pcall(function()
            local now = os.time()
            local state = D.ensure(now)
            local original_period = state.period
            local rolled_back = D.ensure(now - 3 * 86400)
            H.equal(rolled_back.period, original_period)
            local advanced = D.ensure(now + 3 * 86400)
            H.equal(advanced.period, original_period + 3)
            H.equal(advanced.ledger.balance, 0)
        end)
        restore()
        if not ok then error(failure, 0) end
    end)

    H.test("MP daily UI data bypasses synthetic StatisticsDatabase mappings", function()
        local D, _, restore = load_module()
        local ok, failure = pcall(function()
            local state = D.ensure(os.time())
            local entry
            for _, candidate in pairs(state.entries) do entry = candidate break end
            H.truthy(entry)
            H.equal(QuestSettings.stat_mappings[entry.key], nil)
            local data = D.quest_data(entry.id)
            H.equal(data.id, entry.id)
            H.equal(data.progress[1], 0)
            H.equal(data.progress[2], entry.target)
            H.equal(data.completed, false)
            H.equal(data.reward.currency_code, "SM")
        end)
        restore()
        if not ok then error(failure, 0) end
    end)
end
