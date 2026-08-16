-- Pure catalogue browser policy.  It deliberately owns no UI objects: Character
-- Dialogue supplies grouped, bounded pages and Mod Tweaker decides how to render
-- the small visible window.  Keeping this engine-free makes the 34k-entry path
-- regression-testable without launching Vermintide.
local Browser = {}

-- #605 48, not 32: every row now carries the codename AND a transcript line
-- beneath it. The virtual-window planner divides scroll offsets by ONE uniform
-- row height, so variable-height rows would desynchronise scrolling from the
-- logical index; a taller uniform row keeps that math exact.
Browser.ROW_HEIGHT = 48
Browser.PAGE_LIMIT = 32
Browser.GROUPS = {
    { id = "kruber", label = "Markus Kruber" },
    { id = "bardin", label = "Bardin Goreksson" },
    { id = "kerillian", label = "Kerillian" },
    { id = "saltzpyre", label = "Victor Saltzpyre" },
    { id = "sienna", label = "Sienna Fuegonasus" },
    { id = "npc", label = "Allies and NPCs" },
    { id = "enemy", label = "Enemies" },
    { id = "other", label = "Other" },
}

local HERO_PREFIX = {
    pes = "kruber", pdr = "bardin", pwe = "kerillian",
    pwh = "saltzpyre", pbw = "sienna",
}

local function normalized(value)
    return type(value) == "string" and value:lower() or ""
end

function Browser.speaker_for(tuple)
    local event = normalized(tuple and tuple[1])
    local group = normalized(tuple and tuple[3])
    local source = normalized(tuple and tuple[4])
    local hero = HERO_PREFIX[event:sub(1, 3)]
    if hero then return hero end
    -- Generated source filenames are containers, not speaker authority. For
    -- example dwarf_ranger_ground_zero contains enemy-lord events. Only the
    -- canonical player prefix may classify a hero; source fallback would put
    -- Skarrik/Nurgloth lines under Bardin.
    if source:find("enemies", 1, true) or source:find("enemy", 1, true)
       or source:find("beastmen", 1, true) or source:find("skaven", 1, true)
       or group:find("enemy", 1, true) or event:match("^e[%a%d][%a%d]_") then
        return "enemy"
    end
    if source:find("npc", 1, true) or source:find("hub", 1, true)
       or source:find("inn", 1, true) or source:find("narrator", 1, true)
       or event:match("^n[%a%d][%a%d]_") then
        return "npc"
    end
    return "other"
end

function Browser.speaker_label(id)
    for i = 1, #Browser.GROUPS do
        if Browser.GROUPS[i].id == id then return Browser.GROUPS[i].label end
    end
    return nil
end

function Browser.is_browsable(tuple)
    local event = normalized(tuple and tuple[1])
    -- The generated tables contain one literal Wwise sentinel named "dummy".
    -- It is query plumbing, not a playable/disable-able voice event. Longer
    -- real event names containing "dummy" remain valid.
    return event ~= "" and event ~= "dummy"
end

function Browser.matches(tuple, query, transcript)
    query = normalized(query):gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return true end
    for i = 1, 4 do
        if normalized(tuple and tuple[i]):find(query, 1, true) then return true end
    end
    -- #605 search the SPOKEN words too, not just the codename and the subtitle
    -- KEY. tuple[2] is a localization key (pwh_hub_conversation_01_a), so a
    -- player searching "does it tingle" never matched before this. The caller
    -- supplies already-resolved prose; this stays engine-free.
    if type(transcript) == "string" and transcript ~= "" then
        if transcript:lower():find(query, 1, true) then return true end
    end
    return false
end

-- #605 CONVERSATION grouping. A conversation is one event stem: the Wwise event
-- minus its trailing ordinal, so pbw_level_skaven_stronghold_taunt_warlord_02
-- belongs to pbw_level_skaven_stronghold_taunt_warlord. Grouping by stem (not
-- by character) is what puts a conversation's lines together in the order the
-- game plays them; searching the shared topic then surfaces every character's
-- stem as adjacent groups, which is how you find the other half of an exchange.
function Browser.conversation_for(tuple)
    local event = normalized(tuple and tuple[1])
    if event == "" then return "" end
    local stem = event:match("^(.-)_%d+$")
    if stem and stem ~= "" then return stem end
    return event
end

-- Play order within a conversation = the numeric ordinal. Events with no
-- ordinal sort first and keep catalogue order (stable, never reordered).
function Browser.line_order(tuple)
    local event = normalized(tuple and tuple[1])
    local ordinal = event:match("_(%d+)$")
    if ordinal then return tonumber(ordinal) end
    return 0
end

-- A scan returns only eight count records. It never manufactures one widget or
-- one option table per dialogue event.
function Browser.groups(entries, query)
    local counts = {}
    for i = 1, #Browser.GROUPS do counts[Browser.GROUPS[i].id] = 0 end
    for i = 1, #(entries or {}) do
        local tuple = entries[i]
        if Browser.is_browsable(tuple) and Browser.matches(tuple, query) then
            local speaker = Browser.speaker_for(tuple)
            counts[speaker] = (counts[speaker] or 0) + 1
        end
    end
    local out = {}
    for i = 1, #Browser.GROUPS do
        local group = Browser.GROUPS[i]
        out[i] = { id = group.id, label = group.label, count = counts[group.id] or 0 }
    end
    return out
end

-- Build once when the Dialogue tab is first opened. This retains only catalogue
-- tuple references (not cloned rows/widgets), so subsequent scroll-window page
-- requests never rescan unrelated speakers.
function Browser.build_index(entries)
    local index = { total = 0, by_event = {} }
    for i = 1, #Browser.GROUPS do index[Browser.GROUPS[i].id] = {} end
    for i = 1, #(entries or {}) do
        local tuple = entries[i]
        if Browser.is_browsable(tuple) then
            local speaker = Browser.speaker_for(tuple)
            local bucket = index[speaker] or index.other
            bucket[#bucket + 1] = tuple
            index.by_event[tuple[1]] = tuple
            index.total = index.total + 1
        end
    end
    return index
end

function Browser.index_groups(index, query)
    local out = {}
    for i = 1, #Browser.GROUPS do
        local group = Browser.GROUPS[i]
        local bucket, count = (index and index[group.id]) or {}, 0
        for j = 1, #bucket do if Browser.matches(bucket[j], query) then count = count + 1 end end
        out[i] = { id = group.id, label = group.label, count = count }
    end
    return out
end

-- Returns a bounded page plus the full filtered count. Row identity is the
-- stable Wwise event name, never the mutable result index.
function Browser.page(entries, speaker, query, offset, limit)
    offset = math.max(0, tonumber(offset) or 0)
    limit = math.max(1, math.min(Browser.PAGE_LIMIT, tonumber(limit) or Browser.PAGE_LIMIT))
    local total, out = 0, {}
    for i = 1, #(entries or {}) do
        local tuple = entries[i]
        if Browser.is_browsable(tuple) and Browser.speaker_for(tuple) == speaker and Browser.matches(tuple, query) then
            if total >= offset and #out < limit then
                out[#out + 1] = {
                    id = tuple[1], event = tuple[1], subtitle = tuple[2],
                    dialogue_group = tuple[3], source = tuple[4], duration = tuple[5], speaker = speaker,
                }
            end
            total = total + 1
        end
    end
    return out, total
end

function Browser.index_page(index, speaker, query, offset, limit)
    offset = math.max(0, tonumber(offset) or 0)
    limit = math.max(1, math.min(Browser.PAGE_LIMIT, tonumber(limit) or Browser.PAGE_LIMIT))
    local bucket = (index and index[speaker]) or {}
    local total, out = 0, {}
    for i = 1, #bucket do
        local tuple = bucket[i]
        if Browser.matches(tuple, query) then
            if total >= offset and #out < limit then
                out[#out + 1] = {
                    id = tuple[1], event = tuple[1], subtitle = tuple[2],
                    dialogue_group = tuple[3], source = tuple[4], duration = tuple[5], speaker = speaker,
                }
            end
            total = total + 1
        end
    end
    return out, total
end

-- #605 Conversation index. Built once beside the speaker index. `transcripts`
-- is an optional event -> resolved prose map; when present it makes the search
-- match spoken words. Stems are ordered by TOPIC (the stem minus its hero
-- prefix) so pes_/pdr_/pwe_/pwh_/pbw_ variants of one exchange land adjacent
-- instead of scattering alphabetically by character.
local function topic_of(stem)
    local rest = stem:match("^p[bdehw][srwe]_(.+)$")
    if rest then return rest end
    return stem
end

function Browser.build_conversation_index(entries, transcripts)
    local index = { by_stem = {}, order = {}, transcripts = transcripts or {}, total = 0 }
    for i = 1, #(entries or {}) do
        local tuple = entries[i]
        if Browser.is_browsable(tuple) then
            local stem = Browser.conversation_for(tuple)
            local bucket = index.by_stem[stem]
            if not bucket then
                bucket = {}
                index.by_stem[stem] = bucket
                index.order[#index.order + 1] = stem
            end
            bucket[#bucket + 1] = tuple
            index.total = index.total + 1
        end
    end
    for i = 1, #index.order do
        local bucket = index.by_stem[index.order[i]]
        -- Stable sort by ordinal; equal ordinals keep catalogue order.
        for a = 2, #bucket do
            local moving = bucket[a]
            local key = Browser.line_order(moving)
            local b = a - 1
            while b >= 1 and Browser.line_order(bucket[b]) > key do
                bucket[b + 1] = bucket[b]
                b = b - 1
            end
            bucket[b + 1] = moving
        end
    end
    table.sort(index.order, function(l, r)
        local lt, rt = topic_of(l), topic_of(r)
        if lt ~= rt then return lt < rt end
        return l < r
    end)
    return index
end

function Browser.conversation_matches(index, tuple, query)
    local transcript = index and index.transcripts and index.transcripts[tuple[1]]
    return Browser.matches(tuple, query, transcript)
end

function Browser.conversation_groups(index, query)
    local out = {}
    local order = (index and index.order) or {}
    for i = 1, #order do
        local stem = order[i]
        local bucket = index.by_stem[stem]
        local count = 0
        for j = 1, #bucket do
            if Browser.conversation_matches(index, bucket[j], query) then count = count + 1 end
        end
        if count > 0 then
            out[#out + 1] = { id = stem, label = stem, count = count }
        end
    end
    return out
end

function Browser.conversation_page(index, stem, query, offset, limit)
    offset = math.max(0, tonumber(offset) or 0)
    limit = math.max(1, math.min(Browser.PAGE_LIMIT, tonumber(limit) or Browser.PAGE_LIMIT))
    local bucket = (index and index.by_stem and index.by_stem[stem]) or {}
    local total, out = 0, {}
    for i = 1, #bucket do
        local tuple = bucket[i]
        if Browser.conversation_matches(index, tuple, query) then
            if total >= offset and #out < limit then
                out[#out + 1] = {
                    id = tuple[1], event = tuple[1], subtitle = tuple[2],
                    dialogue_group = tuple[3], source = tuple[4], duration = tuple[5],
                    speaker = Browser.speaker_for(tuple),
                    -- Groups are stems now, so the row no longer inherits a
                    -- character name from its header; carry it per line for the
                    -- hover popup's metadata footer.
                    speaker_label = Browser.speaker_label(Browser.speaker_for(tuple)),
                    transcript = index.transcripts and index.transcripts[tuple[1]],
                }
            end
            total = total + 1
        end
    end
    return out, total
end

-- Generated durations come from each dialogue group's sound_events_duration.
-- Fatshark uses DialogueSettings.sound_event_default_length when a generated
-- entry has no duration, so callers provide that exact engine fallback.
function Browser.duration_for(index, event, fallback)
    local tuple = index and index.by_event and index.by_event[event]
    local duration = tuple and tonumber(tuple[5]) or 0
    if duration <= 0 then duration = tonumber(fallback) or 0 end
    return math.max(0, duration)
end

-- Pure virtual-window planner used by the renderer and tests. Group headers are
-- always part of the logical list; only the expanded group's rows are inserted.
-- #998 `lead_rows` counts fixed control rows the renderer places ABOVE the
-- first group header (the automatic-isolation toggle); they share the uniform
-- row height so the scroll math stays exact. Omitted or 0 keeps the pre-#998
-- planner byte-for-byte.
function Browser.window(groups, expanded, line_count, scroll_y, viewport_h, overscan, lead_rows)
    scroll_y = math.max(0, tonumber(scroll_y) or 0)
    viewport_h = math.max(Browser.ROW_HEIGHT, tonumber(viewport_h) or (Browser.ROW_HEIGHT * 12))
    overscan = math.max(0, tonumber(overscan) or 2)
    lead_rows = math.max(0, tonumber(lead_rows) or 0)
    local expanded_before, found = 0, false
    for i = 1, #(groups or {}) do
        local group = groups[i]
        if group.count > 0 then
            if group.id == expanded then found = true; break end
            expanded_before = expanded_before + 1
        end
    end
    line_count = found and math.max(0, tonumber(line_count) or 0) or 0
    local group_count = 0
    for i = 1, #(groups or {}) do if groups[i].count > 0 then group_count = group_count + 1 end end
    local logical_count = lead_rows + group_count + line_count
    local first = math.max(1, math.floor(scroll_y / Browser.ROW_HEIGHT) + 1 - overscan)
    local visible = math.ceil(viewport_h / Browser.ROW_HEIGHT) + overscan * 2
    local last = math.min(logical_count, first + visible - 1)
    return {
        first = first, last = last, count = math.max(0, last - first + 1),
        logical_count = logical_count, expanded_line_start = lead_rows + expanded_before + 2,
        content_height = logical_count * Browser.ROW_HEIGHT + 30,
    }
end

-- Stable focus reconciliation for mouse/controller rebuilds.
function Browser.reconcile_focus(visible_ids, previous_id)
    for i = 1, #(visible_ids or {}) do
        if visible_ids[i] == previous_id then return i, previous_id end
    end
    return (#(visible_ids or {}) > 0) and 1 or nil, visible_ids and visible_ids[1] or nil
end

return Browser
