-- Pure, engine-free per-cutscene-instance skip-window state machine
-- (issues 257 + 274; supersedes the boolean post-skip guard half of
-- _gut_cutscene_policy274.lua - the intro-identity policy there is untouched).
--
-- WHY (order-independence): the flow graph gives CutsceneSystem callbacks NO
-- per-cutscene grouping - fx_fade effects, camera activations, and logic
-- activations arrive in map-authored order, and the proven orderings differ
-- per map (issue 140: on dlc_dwarf_whaling fx_fade fires ~97 ms BEFORE its own
-- camera node in every post-skip straggler group; ENGINE_SURFACE surface 1c).
-- The old guard was keyed to the CutsceneSystem INSTANCE (one per level,
-- cutscene_system.lua:11-24), so the intro, mid-mission, and outro cutscenes
-- of one level all shared one guard, and the guard's arm/clear points assumed
-- an arrival order. This module instead models cutscene EPISODES per system:
--   * flow_cb_activate_cutscene_logic opens a NEW episode (generation + 1) and
--     carries the authored identity (event_on_skip param, stored by vanilla at
--     cutscene_system.lua:183).
--   * a proven executed skip marks the CURRENT episode skipped and opens its
--     straggler window.
--   * every later callback CLASSIFIES against the live episode: fades and
--     camera activations belonging to a skipped episode are swallowed or
--     suppressed regardless of the order they arrive in.
-- ONE release condition, checked in one place (window_active + the release
-- paths that reset the episode): a skipped episode's window ends when a new
-- episode opens on that system (logic activation, or a camera activation
-- carrying a DIFFERENT non-nil identity) or when its deadline passes. The
-- deadline is a rolling grace (each classified straggler proves the flow
-- timeline is still replaying the skipped cutscene, so it re-grants GRACE)
-- under a hard cap from the skip moment, so a legitimate later cutscene (the
-- issue-274 Parting of the Waves ENDING, minutes after the intro skip) can
-- never be suppressed: its window is long dead.
--
-- Pre-identity intro watch (issue 257): a mission-intro fade can fire BEFORE
-- both activation callbacks, i.e. before any identity is knowable (the level
-- key for Well of Dreams is dlc_termite_3; for A Parting of the Waves it is
-- dlc_dwarf_whaling - verified against level_settings/logs, never titles).
-- While the caller reports auto-skip intent, a fade arriving on a system whose
-- FIRST episode identity has not yet resolved is swallowed, bounded to
-- INTRO_WATCH_SECONDS from the system's first observed callback. Trade-off
-- (documented in _gut_cutscenes.lua + CHANGELOG): if a mission's FIRST
-- cutscene is a locked/non-intro cinematic, its opening fade is also swallowed
-- (a cosmetic pop; the cinematic itself still plays - the issue-275 skip
-- policy in _gut_cutscene_policy274.lua is not consulted for fades and is
-- unchanged for skips).
--
-- The state holds engine tables (CutsceneSystem instances) as WEAK keys so a
-- dead system never leaks an episode record. Time is an absolute monotonic
-- clock supplied by the caller (the mod accumulates dt; tests pass literals).

local M = {}

-- Rolling straggler grace: each swallowed fade / suppressed camera re-grants
-- this much window, because a straggler arriving proves the skipped cutscene's
-- flow timeline is still replaying (issue 140 trace: groups at +3.5 s and +9 s).
M.GRACE_SECONDS = 15
-- Hard cap measured from the skip moment. dlc_dwarf_whaling's skipped intro
-- timeline runs ~35.5 s of natural duration; nothing may be suppressed past
-- this, so a genuinely new cutscene minutes later always passes (issue 274).
M.MAX_WINDOW_SECONDS = 45
-- Pre-identity fade watch bound, from the system's first observed callback.
M.INTRO_WATCH_SECONDS = 30

function M.new()
    return { episodes = setmetatable({}, { __mode = "k" }) }
end

local function _episode(state, system)
    local ep = state.episodes[system]
    if not ep then
        ep = {
            gen = 0,
            identity = nil,
            skipped = false,
            skip_at = nil,
            deadline = nil,
            hard_deadline = nil,
            first_contact = nil,
            first_identity_resolved = false,
        }
        state.episodes[system] = ep
    end
    return ep
end

local function _touch(ep, now)
    if ep.first_contact == nil then
        ep.first_contact = now
    end
end

local function _reset_to_new_episode(ep, identity)
    ep.gen = ep.gen + 1
    ep.identity = identity
    ep.skipped = false
    ep.skip_at = nil
    ep.deadline = nil
    ep.hard_deadline = nil
end

local function _refresh(ep, now)
    local deadline = now + M.GRACE_SECONDS
    if ep.hard_deadline and deadline > ep.hard_deadline then
        deadline = ep.hard_deadline
    end
    ep.deadline = deadline
end

-- Record that a callback touched this system without classifying anything
-- (used by observation-only callbacks so first_contact stays accurate).
function M.note_contact(state, system, now)
    if system == nil then return end
    _touch(_episode(state, system), now)
end

-- Is the skipped-episode straggler window live for this system right now?
function M.window_active(state, system, now)
    if system == nil then return false end
    local ep = state.episodes[system]
    return ep ~= nil and ep.skipped == true
        and now < (ep.deadline or 0)
        and now < (ep.hard_deadline or 0)
end

-- flow_cb_activate_cutscene_logic: the authoritative "new cutscene instance"
-- signal. Always opens a fresh episode; releases a live window if one existed.
function M.note_logic_activate(state, system, identity, now)
    local ep = _episode(state, system)
    _touch(ep, now)
    local released = M.window_active(state, system, now)
    _reset_to_new_episode(ep, identity)
    ep.first_identity_resolved = true
    return released and "released" or "opened", ep.gen
end

-- A skip PROVEN to have executed on this system (before-state had a camera,
-- after-state does not - the caller keeps that #106 proof). identity is the
-- event_on_skip captured BEFORE vanilla niled it (cutscene_system.lua:105).
function M.note_skip_executed(state, system, identity, now)
    local ep = _episode(state, system)
    _touch(ep, now)
    ep.skipped = true
    if identity ~= nil then
        ep.identity = identity
    end
    ep.skip_at = now
    ep.deadline = now + M.GRACE_SECONDS
    ep.hard_deadline = now + M.MAX_WINDOW_SECONDS
    ep.first_identity_resolved = true
    return ep.gen
end

-- flow_cb_activate_cutscene_camera classification.
-- visible_identity = system.event_on_skip at call time: nil while the skipped
-- episode's stragglers replay (vanilla nils it on skip), and a DIFFERENT
-- non-nil value only when a new logic activation stored a new identity - that
-- proves a new cutscene instance, so release + pass.
function M.classify_camera(state, system, visible_identity, now)
    local ep = _episode(state, system)
    _touch(ep, now)
    if not M.window_active(state, system, now) then
        return "pass"
    end
    if visible_identity ~= nil and visible_identity ~= ep.identity then
        _reset_to_new_episode(ep, visible_identity)
        ep.first_identity_resolved = true
        return "released_pass"
    end
    _refresh(ep, now)
    return "suppress"
end

-- fx_fade classification. Precedence (the caller checks its own one-shot
-- in-skip-call flag FIRST, outside this module):
--   pending  - a deferred intro auto-skip is queued for this system: the fade
--              belongs to the cutscene that is about to be skipped.
--   window   - the skipped episode's straggler window is live.
--   watch    - pre-identity mission-intro watch (issue 257), only while the
--              caller reports auto-skip intent.
function M.classify_fade(state, system, pending, watch_enabled, now)
    local ep = _episode(state, system)
    _touch(ep, now)
    if pending then
        return "swallow_pending"
    end
    if M.window_active(state, system, now) then
        _refresh(ep, now)
        return "swallow_window"
    end
    if watch_enabled and not ep.first_identity_resolved
        and now < ep.first_contact + M.INTRO_WATCH_SECONDS then
        return "swallow_intro_watch"
    end
    return "pass"
end

return M
