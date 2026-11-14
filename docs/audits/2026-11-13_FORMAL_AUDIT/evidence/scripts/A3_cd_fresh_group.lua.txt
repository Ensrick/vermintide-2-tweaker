-- A3 repro (read-only): real vanilla DialogueQueries + real _cd_policy on a FRESH dialogue group.
-- Mirrors the hook body in character_dialogue.lua (get_filtered_dialogue_event_index).
local REPO = "<repos>/vermintide-2-tweaker"
local SRC  = "<repos>/Vermintide-2-Source-Code"
DialogueSettings = { sound_event_default_length = 4.5 }
TagQuery = { FilterOP = {} }
local f = assert(io.open(SRC .. "/scripts/entity_system/systems/dialogues/dialogue_queries.lua", "rb"))
local src = f:read("*a"); f:close()
src = src:gsub("^\239\187\191", "")
local DialogueQueries = assert(loadstring(src, "dialogue_queries"))()
local Policy = dofile(REPO .. "/character_dialogue/scripts/mods/character_dialogue/_cd_policy.lua")

local function fresh()
    -- shape copied from dialogues/generated/*.lua: randomize_indexes_n = 0, randomize_indexes = {}
    return { sound_events_n = 3, sound_events = { "a", "b", "c" }, randomize_indexes_n = 0, randomize_indexes = {} }
end
local function hook(dialogue, overrides)
    local index, used = Policy.choose_index(dialogue, overrides,
        function() return DialogueQueries.get_dialogue_event_index(dialogue, true) end,
        function(i) return DialogueQueries.filter_sound_event(dialogue, i, {}, {}) end)
    if not used then return "vanilla" end
    return index or 1, index
end
math.randomseed(1)
for _, case in ipairs({
    { "line a disabled", { a = false } },
    { "line c force-enabled", { c = true } },
    { "a,b disabled (only c eligible)", { a = false, b = false } },
}) do
    local counts = {}
    for _ = 1, 200 do
        local d = fresh()
        local chosen, raw = hook(d, case[2])
        local k = tostring(chosen) .. " (raw=" .. tostring(raw) .. ")"
        counts[k] = (counts[k] or 0) + 1
    end
    io.write(case[1], " -> ")
    for k, v in pairs(counts) do io.write(k, " x", v, "  ") end
    io.write("\n")
end
-- Same but the group was primed once by vanilla (randomize table built) before overrides apply.
local d = fresh(); DialogueQueries.get_dialogue_event_index(d)
local counts = {}
for _ = 1, 300 do local c = hook(d, { a = false }); counts[c] = (counts[c] or 0) + 1 end
io.write("primed group, a disabled -> ")
for k, v in pairs(counts) do io.write(tostring(k), " x", v, "  ") end
io.write("\n")
