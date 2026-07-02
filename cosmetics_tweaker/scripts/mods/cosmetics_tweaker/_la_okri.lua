-- ============================================================
-- LA Okri's-Challenges disable — GitHub issue #186
-- ============================================================
-- Removes Loremaster's Armoury's quest line (its "main_quest" entry plus the
-- 12 sub-quests: sub_quest_prologue, sub_quest_01..10, sub_quest_crate_tracker)
-- from Okri's Book of Grudges / the achievement menu — display, tracking AND
-- the completion-notification pop-ups — behind the VMF toggle
-- `la_disable_okri_challenges`. That toggle DEFAULTS TO true (= challenges
-- DISABLED): LA's quest line is hidden, untracked and silent until the user
-- opts back in.
--
-- LA registers its challenges as DIRECT table writes
-- (`AchievementTemplates.achievements.main_quest = {...}`, etc. — see LA's
-- achievements/achievements.lua) and appends a `loremasters`/`name="mod_name"`
-- category into the achievements outline. Those writes vary by LA version and
-- are not hookable, so we DON'T intercept LA's registration. Instead we act at
-- the VANILLA read points, which are version-independent:
--
--   (1) DISPLAY — hook `AchievementManager.outline` and return a shallow-cloned
--       outline whose `.categories` omits LA's category. Identified by shape
--       (name == "mod_name", or any entry / sub-entry that is an LA quest key),
--       never a hardcoded index. The shared outline module is never mutated.
--
--   (2) TRACKING / COMPLETION POP-UPS — a deferred one-time scrub (driven from
--       mod.update) walks `AchievementTemplates.achievements` once LA is loaded
--       and makes every LA quest template INERT: `completed` -> a function that
--       always returns false (must stay CALLABLE — vanilla
--       get_challenge_progression() invokes it when `progress` is absent),
--       `progress`/`requirements` -> nil, `display_completion_ui` -> false (so
--       AchievementManager.setup_incompleted_achievements never enqueues it and
--       _display_completion_ui never fires "finish the level to complete the
--       challenge"). We deliberately do NOT nil the global key:
--       AchievementManager._achievement_completed reads the template back out
--       of the global table by id, so a vanished key would nil-deref an
--       already-initialized manager. Inert-in-place is crash-safe for every
--       vanilla code path.
--
-- The LA quest-letter NEWS-FEED banner ("LA_unread_letter") is suppressed
-- separately, by extending the existing condition_func wrapper inside the
-- single NewsFeedUI.init hook in _la_prefix_embedded.lua (VMF silently drops a
-- second hook on the same Class.method, so we never add another one here).
--
-- Side effect to be aware of (documented for the maintainer): LA's
-- sub_quest_prologue / main_quest `completed` callbacks, as a side effect of
-- being evaluated, unlock a handful of KOTBS weapon skins
-- (mod.locked_skins.Kruber_KOTBS_*). Neutralizing tracking means those
-- specific skins are no longer auto-unlocked via the quest. That is inherent
-- to disabling the challenge — LA's OTHER cosmetics (weapons/skins/pickups)
-- are untouched.
--
-- Flipping the toggle OFF restores LA's challenges on the next restart; the
-- inert mutation is not reversed live (per #186 scope — no live re-add needed).

local mod = get_mod("cosmetics_tweaker")

local M = {}

local SETTING = "la_disable_okri_challenges"

-- LA's achievement keys are `main_quest` plus the `sub_quest_*` family. Detect
-- by key shape so we stay version-independent (the installed LA may register a
-- different subset than the reference clone).
local function _is_la_key(key)
    if type(key) ~= "string" then return false end
    return key == "main_quest" or key:find("^sub_quest") ~= nil
end

-- A category in the achievements outline is LA's if it is named "mod_name"
-- (LA's literal placeholder loc key) OR it (or any of its sub-categories) lists
-- an LA achievement key in its `entries`.
local function _category_is_la(category)
    if type(category) ~= "table" then return false end
    if category.name == "mod_name" then return true end
    local entries = category.entries
    if type(entries) == "table" then
        for _, e in ipairs(entries) do
            if _is_la_key(e) then return true end
        end
    end
    local subs = category.categories
    if type(subs) == "table" then
        for _, sub in ipairs(subs) do
            if _category_is_la(sub) then return true end
        end
    end
    return false
end

-- Log the outline-filter result only once per session (the book calls
-- :outline() several times when it opens; one line is enough).
local _outline_logged = false

-- Shallow-clone the outline, replacing `.categories` with a new array that
-- omits LA's category. All other fields (`name`, `type`) are preserved. We do
-- NOT mutate the shared outline module — the UI only reads `.categories`
-- (ipairs / #) and `.type`. When nothing LA is present we hand back the
-- original table untouched (zero overhead, identity preserved) for
-- vanilla-only / LA-not-loaded installs.
local function _build_filtered(outline)
    local src_categories = outline.categories
    if type(src_categories) ~= "table" then return outline end

    local kept = {}
    local dropped = 0
    for i = 1, #src_categories do
        local cat = src_categories[i]
        if _category_is_la(cat) then
            dropped = dropped + 1
        else
            kept[#kept + 1] = cat
        end
    end

    if dropped == 0 then
        return outline
    end

    local clone = {}
    for k, v in pairs(outline) do clone[k] = v end
    clone.categories = kept

    if not _outline_logged then
        _outline_logged = true
        mod:debug("[cosmetics:dbg] [la-okri] outline filter MATCHED: dropped %d LA category(ies), %d remain", dropped, #kept)
    end
    return clone
end

-- (1) DISPLAY hook. String-form so it lazily resolves AchievementManager
-- (the book opens long after LA loads). Capture BOTH returns (vanilla returns
-- `outline` when initialized, or `nil, "<reason>"` when not) so we never
-- collapse the error tuple.
mod:hook("AchievementManager", "outline", function(func, self)
    local outline, err = func(self)
    if not outline then return outline, err end
    if not mod:get(SETTING) then return outline, err end
    -- pcall the build so a malformed/foreign outline can never crash the book.
    local ok, result = pcall(_build_filtered, outline)
    if ok and result then return result, err end
    if not ok then
        mod:warning("[cosmetics:dbg] [la-okri] outline filter errored: %s", tostring(result))
    end
    return outline, err
end)

-- (2) TRACKING / COMPLETION-POP-UP scrub --------------------------------------
local _scrub_done = false

-- Make a single LA quest template inert (see file header for the why of each
-- field). Idempotent via the `_la_okri_inert` marker.
local function _make_inert(key, t)
    if type(t) ~= "table" then return end
    if t._la_okri_inert then return end
    t.completed = function() return false end  -- stays callable; never completes
    t.progress = nil
    t.requirements = nil
    t.display_completion_ui = false            -- keep out of the incompleted list
    t.id = t.id or key                         -- guard vanilla's fassert(id) path
    t._la_okri_inert = true
end

function M.scrub()
    if _scrub_done then return end
    if not mod:get(SETTING) then return end

    local AT = rawget(_G, "AchievementTemplates")
    local achievements = AT and AT.achievements
    if type(achievements) ~= "table" then return end

    -- Only act once LA itself is loaded — keeps us from neutralizing a
    -- same-named key some other system might own when LA is absent, and means
    -- the templates have actually been registered.
    if not get_mod("Loremasters-Armoury") then return end

    local present = false
    for key in pairs(achievements) do
        if _is_la_key(key) then present = true; break end
    end
    if not present then return end

    local n = 0
    for key, tmpl in pairs(achievements) do
        if _is_la_key(key) then
            local ok, err = pcall(_make_inert, key, tmpl)
            if ok then
                n = n + 1
            else
                mod:warning("[cosmetics:dbg] [la-okri] inert mutation failed for %s: %s", tostring(key), tostring(err))
            end
        end
    end

    _scrub_done = true
    mod:debug("[cosmetics:dbg] [la-okri] template scrub FIRED: neutralized %d LA quest template(s)", n)
end

-- Deferred one-time pass, called every frame from mod.update; cheap no-op once
-- the scrub has run (or while the toggle is off / LA not yet present).
function M.tick(dt)
    if _scrub_done then return end
    M.scrub()
end

return M
