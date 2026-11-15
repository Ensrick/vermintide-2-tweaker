-- qa/runtime/character_dialogue/issue_605_line_override_selection.lua
-- WP-COS-03 rig case (audit finding A3-F01, advances #605): with one line of a
-- dialogue group disabled, the overridden selection never returns that line
-- and still reaches the other lines. Solo keep: the local player is the
-- server, and selection runs only on the server
-- (Vermintide-2-Source-Code/scripts/entity_system/systems/dialogues/dialogue_system.lua:957-959).
-- Groups live in DialogueSystem._dialogues (dialogue_system.lua:100); the
-- vanilla selector is DialogueQueries.get_filtered_dialogue_event_index
-- (scripts/entity_system/systems/dialogues/dialogue_queries.lua:110-132),
-- which character_dialogue hooks.

local MOD_ID = "character_dialogue"
local state = {}

local function restore()
    if state.event and not state.restored then
        state.restored = true
        pcall(state.T.cmd, "cd_line", state.event, "default")
    end
end

return {
    id = "cd-605-line-override-selection",
    issue = 605,
    class = "R",
    covers = "WP-COS-03 RIG acceptance: a disabled line is never selected, other lines still are",
    arena = "keep",
    mods = { MOD_ID },
    timeout = 60,

    run = function(T)
        for k in pairs(state) do state[k] = nil end
        state.T = T
        T.step("preconditions")
        T.require(get_mod(MOD_ID) ~= nil, "character_dialogue loaded")
        local entity = Managers.state and Managers.state.entity
        local system = entity and entity:system("dialogue_system")
        local dialogues = system and system._dialogues
        T.require(type(dialogues) == "table", "dialogue_system._dialogues available")
        local name, dialogue
        for group_name, group in pairs(dialogues) do
            if type(group) == "table" and (group.sound_events_n or 0) >= 3 and group.sound_event_filters == nil
                    and type(group.sound_events) == "table" and type(group.sound_events[1]) == "string" then
                name, dialogue = group_name, group
                break
            end
        end
        T.require(dialogue ~= nil, "a group with at least three unfiltered lines")
        T.note("group", tostring(name))
        local event = dialogue.sound_events[1]
        T.note("disabled_event", event)

        T.step("disable line 1")
        state.event = event
        T.cmd("cd_line", event, "disable")

        T.step("select 100 times through the hooked vanilla selector")
        local queries = require("scripts/entity_system/systems/dialogues/dialogue_queries")
        local context = { query_context = {}, global_context = {}, user_context = {},
            user_memory = {}, faction_memory = {} }
        local seen, distinct, picked_first = {}, 0, 0
        for _ = 1, 100 do
            local ok, index = pcall(queries.get_filtered_dialogue_event_index, dialogue, context, {})
            if ok and index == 1 then picked_first = picked_first + 1 end
            if ok and index and not seen[index] then seen[index] = true; distinct = distinct + 1 end
        end
        restore()
        T.note("picked_disabled", tostring(picked_first))
        T.note("distinct", tostring(distinct))
        T.expect_eq(picked_first, 0, "the disabled line 1 is never selected")
        T.expect(distinct >= 2, "at least two distinct lines are selected")
    end,

    cleanup = function()
        restore()
    end,
}
