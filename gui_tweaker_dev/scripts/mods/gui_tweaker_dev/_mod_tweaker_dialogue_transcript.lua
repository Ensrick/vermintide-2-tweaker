-- #880 Dialogue browser transcript preview popups. Pure binding policy:
-- resolve a catalogue subtitle key (tuple field 2, delivered on every
-- browser_page item as item.subtitle) into displayable transcript prose and
-- bind it onto one built dialogue line row. Presentation then rides the
-- shared #207 hover-popup pipeline untouched: the view's ONE reusable
-- self._tooltip widget, the is_hover capture in the twin _draw cull loops,
-- and _update_tooltip's fade/hide-on-leave. Binding runs at virtual-window
-- build time only - never per frame and never per hover - so the hover path
-- allocates nothing (issue 880 constraint).
--
-- Owned by: _mod_tweaker_dialogue.lua (lazy dofile). No engine globals are
-- touched at load time; the unit suite dofiles this module directly.
local Transcript = {}

-- A subtitle key "resolves" only when the localizer returns real prose.
-- Vermintide ships localized subtitles for VO lines, so most hero keys
-- resolve; enemy barks often do not. Suppress the popup (return nil) for:
-- absent/empty keys, a missing localizer, a localizer error, a non-string
-- result, an echo of the raw key, or a "<...>" missing-string marker
-- (issue 880: no popup rather than a raw-key popup).
function Transcript.resolve(subtitle_key, localize)
    if type(subtitle_key) ~= "string" or subtitle_key == "" then return nil end
    if type(localize) ~= "function" then return nil end
    local ok, text = pcall(localize, subtitle_key)
    if not ok or type(text) ~= "string" then return nil end
    if text == "" or text == subtitle_key then return nil end
    if text:sub(1, 1) == "<" then return nil end
    return text
end

-- Popup BODY = transcript prose, then one metadata line: the speaker's
-- display label and the vanilla dialogue group. The body never restates the
-- event id - the popup TITLE names the row (Mod Tweaker popup rule, #222).
-- Explicit branches, no and/or pseudo-ternaries (bug class 26 / #275).
function Transcript.compose(transcript, speaker_label, dialogue_group)
    local parts = {}
    if type(speaker_label) == "string" and speaker_label ~= "" then
        parts[#parts + 1] = speaker_label
    end
    if type(dialogue_group) == "string" and dialogue_group ~= "" then
        parts[#parts + 1] = dialogue_group
    end
    if #parts == 0 then return transcript end
    return transcript .. "\n\n" .. table.concat(parts, " - ")
end

-- Bind (or suppress) the hover-popup fields on one built dialogue line row.
-- Idempotent per (row, event): a repeat call for the already-bound event is
-- a no-op, so no string is ever rebuilt for an unchanged hover target.
-- Fields consumed by the shared pipeline:
--   _tip_title         popup title (the row's event id, per #222)
--   _tip_desc          popup body; ABSENT = the capture loop never targets
--                      this row, so no popup can appear (suppression)
--   _tip_prefer_below  anchors the popup directly under the hovered row
--                      (issue 880), flipping above only at the screen bottom
function Transcript.bind_row(row, item, speaker_label, localize)
    if type(row) ~= "table" or type(item) ~= "table" then return false end
    if row._transcript_bound_event ~= nil and row._transcript_bound_event == item.event then
        return row._tip_desc ~= nil
    end
    row._transcript_bound_event = item.event
    row._tip_title = item.event
    local transcript = Transcript.resolve(item.subtitle, localize)
    if not transcript then
        row._tip_desc = nil
        row._tip_prefer_below = nil
        return false
    end
    row._tip_desc = Transcript.compose(transcript, speaker_label, item.dialogue_group)
    row._tip_prefer_below = true
    return true
end

-- Production localizer: the game's global Localize (the vanilla subtitle
-- table target). Resolved lazily via rawget so this module stays engine-free
-- at load time. Returns nil when unavailable - resolve() then suppresses.
function Transcript.default_localizer()
    local localize = rawget(_G, "Localize")
    if type(localize) ~= "function" then return nil end
    return localize
end

return Transcript
