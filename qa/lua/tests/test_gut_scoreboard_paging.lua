return function(H, repo_root)
    local policy_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function make_topics(count)
        local topics = {}
        for i = 1, count do
            topics[i] = {
                name = "topic_" .. tostring(i),
                display_text = "topic_label_" .. tostring(i),
                stat_type = "topic_stat_" .. tostring(i),
            }
        end
        return topics
    end

    local function make_native_topics()
        local names = {
            "kills_elites", "kills_specials", "kills_total", "kills_melee",
            "kills_ranged", "damage_taken", "damage_dealt",
            "damage_dealt_bosses", "headshots", "saves", "revives",
        }
        local topics = {}
        for i, name in ipairs(names) do
            topics[i] = {
                name = name,
                display_text = "scoreboard_topic_" .. name,
                stat_type = name,
            }
        end
        return topics
    end

    local function make_player(stats_id, name, scores)
        local entries = {}
        for stat_name, score in pairs(scores or {}) do
            entries[#entries + 1] = { stat_name = stat_name, score = score }
        end
        table.sort(entries, function(a, b) return a.stat_name < b.stat_name end)
        return {
            stats_id = stats_id,
            name = name,
            group_scores = { offense = entries },
        }
    end

    local function build_count(count, selected_page)
        return Policy.build_native_model({}, make_topics(count), {
            selected_page = selected_page or 1,
            sort_topic = "player_name",
        })
    end

    H.test("GUT #1414 topic counts 0, 1, and 11 form bounded pages", function()
        local zero = build_count(0)
        H.equal(zero.page_count, 0)
        H.equal(zero.selected_page, 0)
        H.truthy(zero.all_hidden)
        H.equal(#zero.pages, 0)

        local one = build_count(1)
        H.equal(one.page_count, 1)
        H.equal(#one.pages[1].topics, 1)
        H.equal(one.pages[1].topics[1].name, "topic_1")

        local eleven = build_count(11)
        H.equal(eleven.page_count, 1)
        H.equal(#eleven.pages[1].topics, 11)
        H.equal(eleven.overflow_count, 0)
    end)

    H.test("GUT #1414 topic counts 12 and 13 preserve page two", function()
        local twelve = build_count(12, 2)
        H.equal(twelve.page_count, 2)
        H.equal(#twelve.pages[2].topics, 1)
        H.equal(twelve.pages[2].topics[1].name, "topic_12")

        local thirteen = build_count(13, 2)
        H.equal(thirteen.page_count, 2)
        H.equal(#thirteen.pages[2].topics, 2)
        H.equal(thirteen.pages[2].topics[1].name, "topic_12")
        H.equal(thirteen.pages[2].topics[2].name, "topic_13")
    end)

    H.test("GUT #1414 44-topic ceiling reports every overflow", function()
        local exact = build_count(44, 4)
        H.equal(exact.page_count, 4)
        H.equal(#exact.topics, 44)
        H.equal(#exact.pages[4].topics, 11)
        H.equal(exact.overflow_count, 0)

        local overflow = build_count(47, 9)
        H.equal(overflow.page_count, 4)
        H.equal(overflow.selected_page, 4)
        H.equal(#overflow.topics, 44)
        H.equal(overflow.overflow_count, 3)
        H.equal(table.concat(overflow.overflow_topics, ","),
            "topic_45,topic_46,topic_47")
    end)

    H.test("GUT #1414 duplicate and malformed topics are explicit", function()
        local model = Policy.build_native_model({}, {
            { name = "valid", display_text = "valid_label" },
            { name = "valid", display_text = "duplicate_label" },
            { name = "", display_text = "empty_name" },
            { name = "missing_display" },
            "not_a_topic",
        }, {})
        H.equal(#model.topics, 1)
        H.equal(model.duplicate_count, 1)
        H.equal(model.malformed_count, 3)
        H.equal(model.topics[1].display_text, "valid_label")
    end)

    H.test("GUT #1414 all-hidden state has no phantom page", function()
        local topics = make_topics(13)
        local visibility = {}
        for _, topic in ipairs(topics) do visibility[topic.name] = false end
        local model = Policy.build_native_model({}, topics, {
            visibility = visibility,
            selected_page = 4,
        })
        H.truthy(model.all_hidden)
        H.equal(#model.visible_topics, 0)
        H.equal(model.page_count, 0)
        H.equal(model.selected_page, 0)
        H.equal(model.selected, nil)
    end)

    H.test("GUT #1414 hidden sort falls back without mutating preference", function()
        local visibility = { damage_dealt = false }
        local options = {
            sort_topic = "damage_dealt",
            visibility = visibility,
            selected_page = 1,
        }
        local players = {
            z = make_player("z", "Zulu", { damage_dealt = 999 }),
            a = make_player("a", "Alpha", { damage_dealt = 1 }),
        }
        local model = Policy.build_native_model(players, {
            { name = "damage_dealt", display_text = "damage" },
            { name = "revives", display_text = "revives" },
        }, options)
        H.equal(model.preferred_sort, "damage_dealt")
        H.equal(model.effective_sort, "player_name")
        H.equal(model.players[1].name, "Alpha")
        H.equal(options.sort_topic, "damage_dealt")
        H.equal(visibility.damage_dealt, false)
    end)

    H.test("GUT #1414 saved page clamps and cycles deterministically", function()
        H.equal(Policy.clamp_page(-8, 2), 1)
        H.equal(Policy.clamp_page(99, 2), 2)
        H.equal(Policy.clamp_page("bad", 2), 1)
        H.equal(Policy.clamp_page(2, 0), 0)
        H.equal(Policy.next_page(1, 2), 2)
        H.equal(Policy.next_page(2, 2), 1)
        H.equal(Policy.next_page(9, 2), 1)
        H.equal(Policy.next_page(1, 0), 1)
    end)

    H.test("GUT #1414 registry adds two detached native scalar topics", function()
        local native = make_native_topics()
        local registry = Policy.build_topic_registry(native)
        H.equal(#native, 11)
        H.equal(#registry, 13)
        H.equal(registry[12].name, "aidings")
        H.equal(registry[12].stat_type, "aidings")
        H.truthy(registry[12].supplemental)
        H.truthy(registry[12].mod_localized)
        H.equal(registry[13].name, "times_revived")
        local model = Policy.build_native_model({}, registry, { selected_page = 2 })
        H.equal(model.pages[2].topics[1].name, "aidings")
        H.equal(model.pages[2].topics[2].name, "times_revived")
        registry[1].name = "mutated"
        H.equal(native[1].name, "kills_elites")
    end)

    H.test("GUT #1414 missing supplemental values fail closed per scalar", function()
        local rows = {
            { stats_id = "ok" },
            { stats_id = "partial" },
            { stats_id = "throwing" },
        }
        local reads = 0
        local values = Policy.read_supplemental_scores(rows,
            function(stats_id, stat_type)
                reads = reads + 1
                if stats_id == "throwing" then error("database unavailable") end
                if stats_id == "partial" and stat_type == "times_revived" then
                    return "missing"
                end
                return stat_type == "aidings" and 4 or 2
            end, 4)
        H.equal(reads, 6)
        H.equal(values.ok.aidings, 4)
        H.equal(values.ok.times_revived, 2)
        H.equal(values.partial.aidings, 4)
        H.equal(values.partial.times_revived, nil)
        H.equal(next(values.throwing), nil)
    end)

    H.test("GUT #1414 supplement and native snapshot stay detached", function()
        local players = {
            one = make_player("one", "One", { kills_total = 8 }),
        }
        local supplement = {
            one = { aidings = 3, times_revived = 1 },
        }
        local model = Policy.build_native_model(players,
            Policy.build_topic_registry(make_native_topics()), {
                supplemental_scores = supplement,
                selected_page = 2,
            })
        H.equal(model.players[1].scores.aidings, 3)
        model.players[1].scores.aidings = 99
        model.players[1].scores.kills_total = 77
        model.topics[1].name = "changed"
        H.equal(supplement.one.aidings, 3)
        H.equal(players.one.group_scores.offense[1].score, 8)
        H.equal(make_native_topics()[1].name, "kills_elites")
    end)

    H.test("GUT #1414 model fingerprint is deterministic and complete", function()
        local topics = Policy.build_topic_registry(make_native_topics())
        local supplement = {
            alpha = { aidings = 2, times_revived = 1 },
            zulu = { aidings = 5, times_revived = 0 },
        }
        local first_players = {
            zulu = make_player("zulu", "Zulu", { kills_total = 9 }),
            alpha = make_player("alpha", "Alpha", { kills_total = 4 }),
        }
        local second_players = {
            alpha = make_player("alpha", "Alpha", { kills_total = 4 }),
            zulu = make_player("zulu", "Zulu", { kills_total = 9 }),
        }
        local options = {
            sort_topic = "kills_total",
            selected_page = 2,
            supplemental_scores = supplement,
        }
        local first = Policy.build_native_model(first_players, topics, options)
        local second = Policy.build_native_model(second_players, topics, options)
        H.equal(first.fingerprint, second.fingerprint)
        H.truthy(first.fingerprint:match("^[0-9a-f]+$") ~= nil)
        H.equal(#first.fingerprint, 8)

        second_players.alpha.group_scores.offense[1].score = 40
        local changed_score = Policy.build_native_model(second_players, topics, options)
        H.truthy(changed_score.fingerprint ~= first.fingerprint)
        options.selected_page = 1
        local changed_page = Policy.build_native_model(first_players, topics, options)
        H.truthy(changed_page.fingerprint ~= first.fingerprint)
    end)

    H.test("GUT #1414 retention includes Aidings and Times Revived", function()
        local paths = Policy.collect_stat_paths(
            Policy.build_topic_registry(make_native_topics()), 64)
        local found = {}
        for _, path in ipairs(paths) do found[table.concat(path, "/")] = true end
        H.truthy(found.aidings)
        H.truthy(found.times_revived)
        H.truthy(#paths <= 64)

        local records = Policy.capture_stat_values(paths, function(path)
            if path[1] == "aidings" then return 6 end
            if path[1] == "times_revived" then return 2 end
            return 0
        end, 64)
        local restored = {}
        local count = Policy.restore_stat_values(records, function(path, value)
            restored[table.concat(path, "/")] = value
        end, 64)
        H.equal(count, #records)
        H.equal(restored.aidings, 6)
        H.equal(restored.times_revived, 2)
    end)

    H.test("GUT #1414 settings expose every topic and an unbound page key", function()
        local data = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/gui_tweaker_dev_data.lua")
        for _, topic in ipairs(Policy.build_topic_registry(make_native_topics())) do
            local id = "gut_scoreboard_topic_" .. topic.name .. "_visible"
            local pattern = 'setting_id%s*=%s*"' .. id
                .. '"[^\r\n]-default_value%s*=%s*true'
            H.truthy(data:find(pattern) ~= nil, "missing default-visible setting " .. id)
        end
        H.truthy(data:find('setting_id%s*=%s*"gut_scoreboard_live_page"') ~= nil)
        local key_start = assert(data:find(
            'setting_id%s*=%s*"gut_scoreboard_next_page_hotkey"'))
        local key_block = data:sub(key_start, key_start + 500)
        H.truthy(key_block:find(
            'function_name%s*=%s*"gut_scoreboard_next_page"') ~= nil)
        H.truthy(key_block:find('default_value%s*=%s*{%s*}') ~= nil)

        local live = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")
        local callback = live:match(
            "mod%.gut_scoreboard_next_page%s*=%s*function%(%)%s*(.-)%s*end")
        H.truthy(callback ~= nil)
        H.truthy(callback:find('mod:set%("gut_scoreboard_live_page"') ~= nil)
        H.equal(callback:find("cached_", 1, true), nil)
        H.equal(callback:find("hook", 1, true), nil)
    end)

    H.test("GUT #1414 reuses two draw hooks and owns no transport", function()
        local live = read(repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua")
        local _, tab_hooks = live:gsub(
            'mod:hook_safe%("IngamePlayerListUI", "_draw"', "")
        local _, end_hooks = live:gsub(
            'mod:hook_safe%("EndViewStateScore", "draw"', "")
        H.equal(tab_hooks, 1)
        H.equal(end_hooks, 1)
        H.equal(live:find('mod:hook_safe%("IngamePlayerListUI", "update"'), nil)
        H.equal(live:find("network_register", 1, true), nil)
        H.equal(live:find("NetworkLookup", 1, true), nil)
        H.equal(live:find("rpc_", 1, true), nil)
        H.truthy(live:find("Policy.build_topic_registry", 1, true) ~= nil)
        H.truthy(live:find("Policy.read_supplemental_scores", 1, true) ~= nil)
    end)
end
