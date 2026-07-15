return function(Harness, repo_root)
    local policy = dofile(repo_root .. "/character_dialogue/scripts/mods/character_dialogue/_cd_policy.lua")

    local dialogue = { sound_events_n = 3, sound_events = { "a", "b", "c" } }

    Harness.test("cd policy leaves unmodified groups on vanilla path", function()
        local index, used = policy.choose_index(dialogue, {}, function() return 1 end, function() return true end)
        Harness.equal(nil, index)
        Harness.equal(false, used)
    end)

    Harness.test("cd policy bounds rejection and skips disabled lines", function()
        local order, cursor = { 1, 2, 3 }, 0
        local index, used = policy.choose_index(dialogue, { a = false }, function()
            cursor = cursor + 1
            return order[cursor]
        end, function(i) return i == 3 end)
        Harness.equal(3, index)
        Harness.equal(true, used)
        Harness.equal(3, cursor)
    end)

    Harness.test("cd explicit enable bypasses vanilla line filter", function()
        local cursor = 0
        local index = policy.choose_index(dialogue, { b = true }, function()
            cursor = cursor + 1
            return cursor
        end, function() return false end)
        Harness.equal(2, index)
    end)

    Harness.test("cd all-disabled groups are suppressible", function()
        Harness.equal(true, policy.all_disabled(dialogue, { a = false, b = false, c = false }))
        Harness.equal(false, policy.all_disabled(dialogue, { a = false, b = true, c = false }))
        Harness.equal(false, policy.all_disabled(dialogue, { a = false, c = false }))
    end)

    Harness.test("cd catalogue contains unique stable events", function()
        local path = repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue_catalogue.lua"
        local f = assert(io.open(path, "rb"))
        local source = f:read("*a")
        f:close()
        local seen, count = {}, 0
        for event in source:gmatch('{"([^"]+)",') do
            Harness.equal(nil, seen[event], "duplicate dialogue event: " .. event)
            seen[event], count = true, count + 1
        end
        Harness.equal(34327, count)
    end)

    Harness.test("cd Mod Tweaker integration is lazy and action-based", function()
        local view_path = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua"
        local f = assert(io.open(view_path, "rb")); local source = f:read("*a"); f:close()
        Harness.truthy(source:find('type%(options_provider%) == "function"'), "lazy options provider missing")
        Harness.truthy(source:find('wtype == "action"'), "action row support missing")
        Harness.truthy(source:find('get_mod%("character_dialogue"%)'), "preview cleanup missing")
    end)

    Harness.test("cd resolves Fatshark module-local hook targets before VMF hook install", function()
        local path = repo_root .. "/character_dialogue/scripts/mods/character_dialogue/character_dialogue.lua"
        local f = assert(io.open(path, "rb")); local source = f:read("*a"); f:close()
        local require_pos = source:find('local DialogueQueries = require%("scripts/entity_system/systems/dialogues/dialogue_queries"%)')
        local hook_pos = source:find('mod:hook%(DialogueQueries, "get_filtered_dialogue_event_index"')
        Harness.truthy(require_pos, "DialogueQueries module require missing")
        Harness.truthy(hook_pos, "DialogueQueries hook missing")
        Harness.truthy(require_pos < hook_pos, "DialogueQueries must resolve before VMF hook install")
    end)
end
