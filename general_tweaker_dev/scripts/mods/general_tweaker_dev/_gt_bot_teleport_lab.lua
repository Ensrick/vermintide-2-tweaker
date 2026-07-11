local mod = get_mod("gt_dev")

-- ============================================================================
-- Bot Teleport Lab (Diagnostics)  --  observe/probe the "bots teleport away
-- from the player" bug.  DIAGNOSTICS-FIRST: the D-probes below only read state
-- and log / draw; they never change bot behavior. The former F1..F10 behavior
-- fixes are RETIRED to dormant (see the FIXES banner) -- kept in code as
-- re-armable #139 bisection candidates, but gated off so they can't run.
-- ============================================================================
-- MERGE-DISPATCH ARCHITECTURE (why this file has almost no `mod:hook`)
-- ----------------------------------------------------------------------------
-- VMF silently DROPS a second `mod:hook`/`mod:hook_safe` on the same
-- (Class, method) pair from the same mod. gt (via _gt_bot_fixes.lua) ALREADY
-- hooks every injection point this lab needs:
--     BTConditions.should_teleport            (FIX 7)
--     BTBotTeleportToAllyAction.run           (FIX 7 confirmation, WAS hook_safe)
--     PlayerBotBase.update                    (consolidated per-frame chokepoint)
--     AIBotGroupSystem._assign_destination_points  (FIX 9 follow-mode override)
-- so this module MUST NOT re-hook any of them. Instead it defines
-- `mod._gt_btlab_*` observer functions, and _gt_bot_fixes.lua calls them from
-- INSIDE its existing hook bodies (guarded `if mod._gt_btlab_X then ... end`).
-- Because the dispatch is resolved at call time on the `mod` table, load order
-- doesn't matter: this file loads during mod init, long before any in-game
-- teleport, so the functions are present by the time a hook first fires.
--
-- NOTE re D2: the task brief said "take a FRESH hook_safe on
-- AIBotGroupSystem._assign_destination_points". That pair is ALREADY hooked by
-- FIX 9 in _gt_bot_fixes.lua, so a fresh hook would be silently dropped by VMF
-- (and flagged by tools/mod-lint). D2 is therefore MERGED into the FIX 9 body
-- like every other injection point. The D2 dispatch sits at the TOP of the FIX 9
-- hook_safe body, so it reads the follow_unit vanilla just assigned; when the
-- user runs a non-default Bot-follow-mode (Follow Host / Split), FIX 9 rewrites
-- follow_unit LATER in the same tick, so with those modes D2 logs the
-- pre-override target -- the D1/D3/D4 observers (which read at should_teleport /
-- update time) show the final post-override value.
--
-- OUTPUT: everything logs via engine `printf` (tag `[gt:btlab:dNN]`) so it's
-- visible even with VMF mod-logging OFF (the user runs logging off -- see
-- memory reference_vt2_diagnostics_use_printf_not_modinfo). Per-tick logs are
-- throttled (~1s per bot) to avoid flooding.  Every observer body is
-- pcall-guarded so a bad read degrades to vanilla behavior, never crashes.
--
-- HOST-SIDE: bot AI is server-side, so all of this only ever runs on the host.
-- Nothing here registers a network event or sends an RPC.
--
-- GATING (v0.2.175-dev): diagnostics are no longer menu toggles. Per the new
-- diagnostics doctrine, data-collecting probes are IMPLICIT and ALWAYS ON in the
-- dev stream -- they gate ONLY on IS_DEV_STREAM (below), read no settings, and
-- keep their per-bot ~1s throttles. The two VISUAL dev tools -- the bot behavior
-- HUD (supersedes the old D6 head-text) and the D7 leash lines -- moved to the
-- new "Dev Tools" settings section (gt_devtools_bot_hud / gt_devtools_leash_lines)
-- and additionally require host. The former F1..F10 fix candidates are RETIRED to
-- dormant (see the FIXES banner): their dispatch fns return false/nil regardless
-- of any saved setting, so a stale F-toggle can't resurrect a behavior change.
--
-- CHAT COMMANDS: /bot_tp_dump (teleport tally)  ,  /bot_tp_snap (snapshot buffer)
-- ============================================================================

local POSITION_LOOKUP = POSITION_LOOKUP
local ALIVE           = ALIVE
local HEALTH_ALIVE    = HEALTH_ALIVE
local ScriptUnit      = ScriptUnit
local Vector3         = Vector3
local Vector3Box      = Vector3Box
local Quaternion      = Quaternion
local Unit            = Unit
local Broadphase      = Broadphase
local Managers        = Managers

-- Retained ONLY for the dormant, re-armable F bodies below (they still read the
-- old gate + F sub-toggles when armed). The always-on diagnostics no longer use
-- it -- they gate on IS_DEV_STREAM instead.
local _MASTER = "gt_btlab_enabled"

-- Dev-only runtime gate. The dev->stable promotion port does a literal sed of
-- `gt_dev` -> `gt` across this file; `"gt" .. "_dev"` has NO contiguous "gt_dev"
-- substring, so it SURVIVES that sed. In the dev clone `mod == get_mod("gt_dev")`
-- so this is true; in the promoted stable clone `mod == get_mod("gt")` while
-- get_mod("gt".."_dev") resolves to the (absent) dev mod -> nil -> false. This is
-- the sanctioned dev-only gate for the always-on diagnostics + the Dev Tools HUD.
local IS_DEV_STREAM = (mod == get_mod("gt" .. "_dev"))

-- Retired F1..F10 behavior-fix candidates (issue #139 bisection). DORMANT: the
-- three fix dispatch fns below early-return on this flag, so a friend who saved an
-- old F-toggle ON keeps NO ghost behavior fix (the widgets are gone; the fixes are
-- gated off in code). Re-arm in code ONLY by flipping this to true; the intact fix
-- bodies (and their old gate reads) then run again.
local _BTLAB_FIXES_ARMED = false

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------

-- printf wrapper: format safely, then hand a pre-formatted string to printf so a
-- stray `%` in a name can't break the engine's own format pass.
local function _pf(fmt, ...)
    local p = rawget(_G, "printf")
    if not p then return end
    local ok, s = pcall(string.format, fmt, ...)
    if ok then p("%s", s) end
end

-- master gate + per-diagnostic sub-toggle in one read. USED ONLY by the dormant
-- re-armable F bodies now; the always-on diagnostics gate on IS_DEV_STREAM.
local function _on(sub)
    return mod:get(_MASTER) and mod:get(sub)
end

-- game clock (seconds); pcall-guarded because Managers.time may not have the
-- "game" timer outside a mission.
local function _now()
    local ok, v = pcall(function() return Managers.time and Managers.time:time("game") end)
    return (ok and v) or 0
end

-- per-bot throttle stamped on the blackboard. Returns true at most once per
-- `interval` seconds for the given key.
local function _throttle(bb, key, now, interval)
    local nxt = bb[key] or 0
    if now < nxt then return false end
    bb[key] = now + interval
    return true
end

local function _local_player_unit()
    local pm = Managers.player
    local p = pm and pm:local_player()
    return p and p.player_unit
end

local function _follow_unit(bb)
    local ge = bb and bb.ai_bot_group_extension
    return ge and ge.data and ge.data.follow_unit
end

local function _career_of_unit(unit)
    if not unit then return "?" end
    local ce = ScriptUnit.has_extension(unit, "career_system")
    if ce and ce.career_name then
        local ok, n = pcall(ce.career_name, ce)
        if ok and n then return n end
    end
    return "?"
end

-- "name(career)" for readable logs. Falls back to the raw unit handle.
local function _unit_label(unit)
    if not unit then return "none" end
    local ok, label = pcall(function()
        local pm = Managers.player
        local owner = pm and pm.owner and pm:owner(unit)
        local name = owner and owner.name and owner:name() or tostring(unit)
        return string.format("%s(%s)", name, _career_of_unit(unit))
    end)
    return (ok and label) or tostring(unit)
end

local function _dist_units(a, b)
    local pa = a and POSITION_LOOKUP[a]
    local pb = b and POSITION_LOOKUP[b]
    if pa and pb then return Vector3.distance(pa, pb) end
    return nil
end

local function _segment_of(unit)
    local cd = Managers.state and Managers.state.conflict
    if not (cd and unit) then return nil end
    local ok, seg = pcall(cd.get_player_unit_segment, cd, unit)
    return ok and seg or nil
end

local function _is_downed(unit)
    local st = unit and ScriptUnit.has_extension(unit, "status_system")
    if not st then return false end
    local ok, downed = pcall(function()
        return st:is_knocked_down() or st:is_dead() or st:is_ready_for_assisted_respawn()
    end)
    return (ok and downed) and true or false
end

-- Current running behavior-tree LEAF action for a bot, read straight off the
-- blackboard. bt_node.lua:87-113 records each active CONTAINER node's running
-- child in blackboard.running_nodes[identifier]; leaf action nodes never call
-- set_running_child, so the single active-path leaf is the running node whose OWN
-- identifier is not itself a key (bt_selector.lua:19-47 keeps exactly one running
-- child per selector). AIBrain.update drives the root :evaluate every frame
-- (ai_brain.lua:90-91, called from player_bot_base.lua:325), so running_nodes is
-- current as of our post-`update` hook_safe dispatch. Returns (identifier,
-- class_name) or nil. Per-frame table read only; no allocation.
local function _current_bot_action(blackboard)
    local rn = blackboard and blackboard.running_nodes
    if type(rn) ~= "table" then return nil end
    for _key, node in pairs(rn) do
        if type(node) == "table" then
            local nid = node._identifier
            if nid == nil or rn[nid] == nil then
                return nid, node.name
            end
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Per-mission state (reset on StateIngame enter)
-- ----------------------------------------------------------------------------
local _bots        = {}    -- [bot_unit] = { blackboard = bb, seen = t }   (D3/HUD/leash)
local _follow_last = {}    -- [bot_unit] = last follow_unit                (D2)
local _tp_counts   = {}    -- [bot_unit] = { label, total, toward, away }  (D8)
local _snaps       = {}    -- ring buffer of teleport snapshots            (D10)
local _last_tp     = {}    -- [bot_unit] = game-time of last teleport      (dormant F9 cooldown)
local _SNAP_MAX    = 10
-- Bot behavior HUD (Dev Tools): per-bot ring buffer of the last N behavior-tree
-- leaf actions the bot entered, plus the last-seen action for edge detection.
local _action_log  = {}    -- [bot_unit] = { {t=, id=}, ... } oldest first
local _action_last = {}    -- [bot_unit] = last-seen leaf action identifier
local _ACTION_LOG_MAX = 20

local function _reset_mission_state()
    _bots        = {}
    _follow_last = {}
    _tp_counts   = {}
    _snaps       = {}
    _last_tp     = {}
    _action_log  = {}
    _action_last = {}
    -- Also drop any cached draw resources so a stale world handle isn't reused.
    mod._gt_btlab_line_object  = nil
    mod._gt_btlab_line_world   = nil
    mod._gt_btlab_gui          = nil
    mod._gt_btlab_gui_world    = nil
    mod._gt_btlab_gui_deferred = nil
end

-- ============================================================================
-- #261 always-on instrumentation (radius breach + tether dump). All host-side,
-- always-on in dev (no toggles), printf so it's visible with mod logging OFF.
-- Issue #261: in split follow mode a bot pursues an objective OUTSIDE the follow
-- radius, then gets leash-yanked -- these probes capture, per event, WHAT the bot
-- was doing when it left the radius and every yank's cause. Event-driven +
-- cooldown-throttled; no new per-frame log lines.
-- ============================================================================

-- Compact one-line dump of a bot's action ring buffer, newest first, each entry
-- "id@-<age>s" (age = now - entry.t). "(none)" if empty.
local function _ring_compact(unit, now)
    local log = _action_log[unit]
    if not (log and #log > 0) then return "(none)" end
    local parts = {}
    for i = #log, 1, -1 do
        local e = log[i]
        local age = (now and e.t) and (now - e.t) or nil
        parts[#parts + 1] = age and string.format("%s@-%.1fs", e.id or "?", age)
                                 or tostring(e.id or "?")
    end
    return table.concat(parts, " ")
end

-- Per-human distance summary from a bot: "name=Xm, name=Ym", plus nearest
-- (name, dist). Uses Managers.player:human_players() (humans only). nil-guarded.
local function _human_dist_summary(unit)
    local pm = Managers.player
    local humans = pm and pm.human_players and pm:human_players()
    local bot_pos = POSITION_LOOKUP[unit]
    local parts, nearest_name, nearest_d = {}, nil, nil
    if humans and bot_pos then
        for _, player in pairs(humans) do
            local u = player and player.player_unit
            local p = u and POSITION_LOOKUP[u]
            if p then
                local d  = Vector3.distance(bot_pos, p)
                local nm = (player.name and player:name()) or "?"
                parts[#parts + 1] = string.format("%s=%.1fm", nm, d)
                if not nearest_d or d < nearest_d then nearest_d, nearest_name = d, nm end
            end
        end
    end
    return table.concat(parts, ", "), nearest_name, nearest_d
end

-- #261 RADIUS-BREACH block: printf ONE compact block (3 lines, tag
-- [gt:btlab:breach]) when a bot's distance to its CURRENT follow anchor crosses
-- ABOVE the leash radius. Answers "what was the bot trying to do when it left the
-- radius": current BT leaf action + per-human distances + the action ring buffer.
local function _report_breach(unit, blackboard, follow, dist, radius, now)
    pcall(function()
        local action = _current_bot_action(blackboard) or "?"
        _pf("[gt:btlab:breach] bot=%s LEFT follow radius: follow=%s dist=%.1fm radius=%.1fm action=%s",
            _unit_label(unit), _unit_label(follow), dist, radius, action)
        local human_line, nearest_name, nearest_d = _human_dist_summary(unit)
        _pf("[gt:btlab:breach]   humans: %s (nearest=%s @ %s)",
            (human_line ~= "" and human_line) or "none",
            nearest_name or "none",
            nearest_d and string.format("%.1fm", nearest_d) or "n/a")
        _pf("[gt:btlab:breach]   actions(newest->oldest): %s", _ring_compact(unit, now))
    end)
end

-- #261 TETHER dump: printf a [gt:btlab:tether] block (2 lines) whenever a bot is
-- leash-yanked/teleported, so every observed yank carries its cause (current
-- action + ring buffer). Per-bot ~2s cooldown (stamped on the blackboard) so an
-- oscillation doesn't flood. Dispatched from the EXISTING BTBotTeleportToAllyAction
-- .run hook body in _gt_bot_fixes.lua (no new hook).
mod._gt_btlab_report_tether = function(unit, blackboard)
    if not IS_DEV_STREAM then return end
    if not (unit and blackboard) then return end
    pcall(function()
        local now  = _now()
        local last = blackboard._gt_btlab_tether_t or -1e9
        if now - last < 2.0 then return end
        blackboard._gt_btlab_tether_t = now
        local follow = _follow_unit(blackboard)
        local action = _current_bot_action(blackboard) or "?"
        local d      = follow and _dist_units(unit, follow)
        _pf("[gt:btlab:tether] YANK bot=%s follow=%s dist=%s action=%s",
            _unit_label(unit), _unit_label(follow),
            d and string.format("%.1fm", d) or "n/a", action)
        _pf("[gt:btlab:tether]   actions(newest->oldest): %s", _ring_compact(unit, now))
    end)
end

-- Dev-gated printf passthrough for sibling files (e.g. _gt_bot_fixes.lua leash /
-- split summaries) so their mod:debug lines become visible with logging OFF.
mod._gt_btlab_pf_dev = function(fmt, ...)
    if IS_DEV_STREAM then _pf(fmt, ...) end
end

-- ============================================================================
-- D2  follow_tracker  --  merged into FIX 9's _assign_destination_points hook
-- ----------------------------------------------------------------------------
-- Log each bot's follow_unit and, when it CHANGES, old -> new with both units'
-- player identity. Stores last-seen per bot so it only logs on change.
-- ============================================================================
mod._gt_btlab_track_follow = function(bot_ai_data)
    if not IS_DEV_STREAM then return end
    if type(bot_ai_data) ~= "table" then return end
    pcall(function()
        -- #261: name the resolved follow MODE that drove the assignment
        -- (default / follow_host / split), read from FIX 9's own resolver.
        -- NOTE: this dispatch runs at the TOP of _assign_destination_points, so
        -- in follow_host/split mode it reports the PRE-override target (vanilla's
        -- pick); FIX 9 rewrites follow_unit later in the same tick. The final
        -- post-split anchor is what the breach / tether probes read (via
        -- _follow_unit(blackboard) at observe / teleport time).
        local mode = (mod._gt_resolve_follow_mode and mod._gt_resolve_follow_mode()) or "?"
        for bot_unit, data in pairs(bot_ai_data) do
            if data then
                local new_follow = data.follow_unit
                local last = _follow_last[bot_unit]
                if new_follow ~= last then
                    _follow_last[bot_unit] = new_follow
                    _pf("[gt:btlab:d2] bot=%s mode=%s follow CHANGED %s -> %s",
                        _unit_label(bot_unit), mode, _unit_label(last), _unit_label(new_follow))
                end
            end
        end
    end)
end

-- ============================================================================
-- D1 (decision side) + D4 + D5  --  merged into BTConditions.should_teleport
-- ----------------------------------------------------------------------------
-- Runs every tick per bot (throttled where noisy).
--   D1: record the measured bot->follow distance + current leash threshold onto
--       the blackboard, so the execution-side (.run) hook can classify the
--       trigger (vanilla 40m vs gt tighter leash) when a teleport actually fires.
--   D4: self vs follow_unit conflict-segment values + whether VANILLA's segment
--       gate (target_segment >= self_segment) passed or blocked. NOTE (issue 142):
--       gt's gt_bot_ignore_backward_gate can now OVERRIDE a BLOCK (the tighter
--       leash / backward fallback teleport a bot to a behind-segment follow
--       target anyway), so a BLOCK no longer guarantees "never teleports this
--       tick" -- the probe deliberately still reports VANILLA's raw comparison.
--   D5: target_ally_need_type + whether target_unit == priority_target_enemy,
--       i.e. why the aid exception did/didn't fire.
-- ============================================================================
mod._gt_btlab_observe_should_teleport = function(blackboard)
    if not IS_DEV_STREAM then return end
    pcall(function()
        local unit   = blackboard.unit
        local follow = _follow_unit(blackboard)
        local now    = _now()

        -- D1 decision recorder (cheap, unthrottled -- keeps the last-measured
        -- distance fresh for the .run trigger classification).
        if follow then
            local d = _dist_units(unit, follow)
            if d then
                local leash = mod:get("gt_bot_follow_distance_m") or 40.0
                blackboard._gt_btlab_dec = { dist = d, leash = leash }
            end
        end

        -- D4 segment probe (throttled ~1s).
        if _throttle(blackboard, "_gt_btlab_d4_t", now, 1.0) then
            local self_seg   = _segment_of(unit) or 1
            local follow_seg = follow and _segment_of(follow)
            local gate = (follow_seg and follow_seg >= self_seg) and "PASS" or "BLOCK"
            _pf("[gt:btlab:d4] bot=%s self_seg=%s follow_seg=%s gate=%s (vanilla gate; issue-142 backward override can still teleport on BLOCK)",
                _unit_label(unit), tostring(self_seg), tostring(follow_seg), gate)
        end

        -- D5 aid probe (throttled ~1s).
        if _throttle(blackboard, "_gt_btlab_d5_t", now, 1.0) then
            local need = blackboard.target_ally_need_type
            local has_prio = blackboard.target_unit and blackboard.target_unit == blackboard.priority_target_enemy
            local exception = (need ~= nil or has_prio) and true or false
            _pf("[gt:btlab:d5] bot=%s target_ally_need_type=%s has_priority_target=%s aid_exception=%s (exception=true => teleport suppressed)",
                _unit_label(unit), tostring(need), tostring(has_prio and true or false), tostring(exception))
        end
    end)
end

-- ============================================================================
-- D1 (execution side) + D8 + D9 + D10  --  merged into the CONVERTED
-- BTBotTeleportToAllyAction.run hook (see _gt_bot_fixes.lua).
-- ----------------------------------------------------------------------------
-- _gt_btlab_pre_teleport captures the bot position BEFORE the teleport executes
-- (returned boxed because it must survive the wrapped func() call).
-- _gt_btlab_observe_teleport runs AFTER the teleport, with the boxed pre-pos.
-- ============================================================================
mod._gt_btlab_pre_teleport = function(unit, blackboard) -- luacheck: ignore blackboard
    if not IS_DEV_STREAM then return nil end
    local ok, box = pcall(function()
        local p = POSITION_LOOKUP[unit]
        return p and Vector3Box(p) or nil
    end)
    return ok and box or nil
end

-- capture a snapshot of the whole team at teleport time (D10).
local function _push_snapshot(trigger_unit, trigger_info)
    local you = _local_player_unit()
    local snap = {
        t        = _now(),
        bot      = _unit_label(trigger_unit),
        trigger  = trigger_info or "?",
        you      = _unit_label(you),
        you_downed   = _is_downed(you),
        you_disabled = false,
        players  = {},
    }
    -- local player "combat state" -> disabled flag (grabbed / hooked / pounced).
    local you_st = you and ScriptUnit.has_extension(you, "status_system")
    if you_st then
        local ok, dis = pcall(function() return you_st:is_disabled() end)
        snap.you_disabled = (ok and dis) and true or false
    end

    local pm = Managers.player
    local players = pm and pm.human_and_bot_players and pm:human_and_bot_players()
    if players then
        for _, player in pairs(players) do
            local u = player.player_unit
            local entry = {
                name   = (player.name and player:name()) or "?",
                is_bot = player.bot_player and true or false,
                career = u and _career_of_unit(u) or "?",
                downed = _is_downed(u),
                seg    = u and _segment_of(u),
                follow = nil,
                pos    = nil,
            }
            local p = u and POSITION_LOOKUP[u]
            if p then entry.pos = string.format("(%.0f,%.0f,%.0f)", p.x, p.y, p.z) end
            if entry.is_bot and u then
                local rec = _bots[u]
                local bb  = rec and rec.blackboard
                local f   = bb and _follow_unit(bb)
                entry.follow = f and _unit_label(f) or "none"
            end
            snap.players[#snap.players + 1] = entry
        end
    end

    _snaps[#_snaps + 1] = snap
    while #_snaps > _SNAP_MAX do table.remove(_snaps, 1) end
end

mod._gt_btlab_observe_teleport = function(self, unit, blackboard, pre_box) -- luacheck: ignore self
    if not IS_DEV_STREAM then return end
    -- Dormant-F9 cooldown source: stamp the last-teleport time for this bot on
    -- EVERY teleport the lab sees. Kept so the retired F9 cooldown is re-armable
    -- from a live timestamp; cheap, and unread while the fixes are dormant.
    if unit then _last_tp[unit] = _now() end
    pcall(function()
        local follow  = _follow_unit(blackboard)
        local you     = _local_player_unit()
        local pre      = pre_box and pre_box:unbox()
        local post     = POSITION_LOOKUP[unit]
        local you_pos  = you and POSITION_LOOKUP[you]

        -- Trigger classification from the D1 decision recorder.
        local dec      = blackboard._gt_btlab_dec
        local measured = dec and dec.dist
        local leash    = (dec and dec.leash) or (mod:get("gt_bot_follow_distance_m") or 40.0)
        local trigger
        if measured then
            if measured >= 40.0 then
                trigger = string.format("vanilla-40m (measured %.1fm)", measured)
            elseif leash < 40.0 and measured >= leash then
                trigger = string.format("gt-tighter-leash %.0fm (measured %.1fm)", leash, measured)
            else
                trigger = string.format("unknown (measured %.1fm, leash %.0fm)", measured, leash)
            end
        else
            trigger = string.format("unknown (no fresh should_teleport measure, leash %.0fm)", leash)
        end

        -- TOWARD / AWAY-from-local-player delta.
        local before  = (pre and you_pos) and Vector3.distance(pre, you_pos) or nil
        local after   = (post and you_pos) and Vector3.distance(post, you_pos) or nil
        local dir = "?"
        if before and after then dir = (after > before) and "AWAY" or "TOWARD" end

        -- D1 full teleport line (always-on in dev).
        do
            local prex, prey, prez = (pre and pre.x) or 0, (pre and pre.y) or 0, (pre and pre.z) or 0
            local pox, poy, poz    = (post and post.x) or 0, (post and post.y) or 0, (post and post.z) or 0
            _pf("[gt:btlab:d1] TELEPORT bot=%s from=(%.1f,%.1f,%.1f) to=(%.1f,%.1f,%.1f) follow=%s dist_bot_follow=%s trigger=%s | to_local_player before=%s after=%s => %s",
                _unit_label(unit),
                prex, prey, prez, pox, poy, poz,
                _unit_label(follow),
                (measured and string.format("%.1fm", measured)) or "n/a",
                trigger,
                (before and string.format("%.1fm", before)) or "n/a",
                (after and string.format("%.1fm", after)) or "n/a",
                dir)
        end

        -- D8 per-bot per-mission counter (toward vs away; always-on in dev).
        do
            local c = _tp_counts[unit]
            if not c then
                c = { label = _unit_label(unit), total = 0, toward = 0, away = 0 }
                _tp_counts[unit] = c
            end
            c.total = c.total + 1
            if dir == "AWAY" then c.away = c.away + 1
            elseif dir == "TOWARD" then c.toward = c.toward + 1 end
        end

        -- D9 has_teleported flag SET (vanilla flips it true inside run(); always-on in dev).
        do
            _pf("[gt:btlab:d9] has_teleported SET -> %s for bot=%s (must clear in BTBotFollowAction.enter before another teleport)",
                tostring(blackboard.has_teleported), _unit_label(unit))
            -- prime the clear-detector so the update observer only reports the
            -- subsequent true->false edge.
            blackboard._gt_btlab_ht_last = blackboard.has_teleported and true or false
        end

        -- D10 snapshot into the ring buffer (always-on in dev).
        _push_snapshot(unit, trigger)
    end)
end

-- ============================================================================
-- FIXES (F1..F10)  --  RETIRED / DORMANT bisection candidates (issue #139).
-- ----------------------------------------------------------------------------
-- These were the experimental "stop bots teleporting away" toggles. Their menu
-- toggles are GONE and the three dispatch fns below early-return on the module
-- flag `_BTLAB_FIXES_ARMED` (false), so NONE of this runs -- a friend who saved
-- an old F-toggle ON gets no ghost behavior. The proven #139 fixes live in
-- _gt_bot_fixes.lua and are NOT affected. The bodies are kept intact and
-- re-armable IN CODE ONLY (flip _BTLAB_FIXES_ARMED to true); when armed they read
-- the old gate + F sub-toggles via `_on` exactly as before.
--
-- Each fix was an independent sub-toggle (default OFF, host-side, pcall-guarded),
-- gated `mod:get("gt_btlab_enabled") and mod:get("gt_btlab_fNN_...")` via `_on`.
-- The fixes route through THREE dispatch fns the _gt_bot_fixes.lua hooks call
-- (VMF drops a 2nd hook on an already-hooked pair, so nothing here re-hooks):
--   mod._gt_btlab_veto_teleport(...)        -> in BTConditions.should_teleport
--       backs the VETO fixes F2/F4/F6/F7/F8/F9/F10 (return true => BLOCK).
--   mod._gt_btlab_override_follow_unit(...)  -> in AIBotGroupSystem._assign_...
--       backs F1/F5 (return a unit to re-point data.follow_unit at, or nil).
--   mod._gt_btlab_redirect_teleport(...)     -> at the TOP of BTBotTeleport...run
--       backs F3 (teleport bot to YOUR navmesh pos, return true = handled).
-- Vetoes OR together; the FIRST that fires is logged and blocks. F1 beats F5.
-- F3 acts in .run independent of the veto layer. Tag: [gt:btlab:fNN].
-- ============================================================================

-- Navmesh-valid position of a unit (same source vanilla's teleport reads:
-- whereabouts last_position_on_navmesh, bt_bot_teleport_to_ally_action.lua:44).
-- Falls back to the raw position lookup.
local function _navmesh_pos(target_unit)
    if not target_unit then return nil end
    local wb = ScriptUnit.has_extension(target_unit, "whereabouts_system")
    local ok, p = pcall(function() return wb and wb:last_position_on_navmesh() end)
    return (ok and p) or POSITION_LOOKUP[target_unit]
end

-- F10 heading source for the LOCAL player. Primary = first-person aim (camera
-- look), flattened to horizontal + normalized. Fallback = the 3P body facing
-- (Unit.local_rotation node 0). Returns nil if neither resolves. NOTE: the aim
-- source is source-verified (first_person_system ext + current_rotation(),
-- player_unit_first_person.lua:824); the body-facing fallback is a best-effort
-- proxy. Both are pcall-guarded so a bad read just yields nil (fix no-ops).
local function _local_heading(you)
    if not you then return nil end
    local dir
    local fp = ScriptUnit.has_extension(you, "first_person_system")
    if fp and fp.current_rotation then
        local ok, rot = pcall(fp.current_rotation, fp)
        if ok and rot then
            local f = Quaternion.forward(rot)
            dir = Vector3(f.x, f.y, 0)
        end
    end
    if not dir or Vector3.length(dir) < 0.01 then
        local ok, rot = pcall(Unit.local_rotation, you, 0)
        if ok and rot then
            local f = Quaternion.forward(rot)
            dir = Vector3(f.x, f.y, 0)
        end
    end
    if dir and Vector3.length(dir) >= 0.01 then
        return Vector3.normalize(dir)
    end
    return nil
end

-- F5 helper: nearest ALIVE HUMAN player unit to `bot_unit` (excludes the bot
-- itself + any bot player). Uses Managers.player:human_players(); nil if none.
local function _nearest_alive_human(bot_unit)
    local pm = Managers.player
    local humans = pm and pm.human_players and pm:human_players()
    if not humans then return nil end
    local bot_pos = bot_unit and POSITION_LOOKUP[bot_unit]
    if not bot_pos then return nil end
    local best, best_d
    for _, player in pairs(humans) do
        local u = player and player.player_unit
        if u and u ~= bot_unit and HEALTH_ALIVE[u] then
            local p = POSITION_LOOKUP[u]
            if p then
                local d = Vector3.distance_squared(bot_pos, p)
                if not best_d or d < best_d then best_d, best = d, u end
            end
        end
    end
    return best
end

-- F8 helper: count ALIVE enemy AI within `radius` of `you_pos` via the AI
-- broadphase (mirrors the query pattern in _gt_prioritize_specials.lua:135-139).
-- side:is_enemy filters out friendly/neutral broadphase hits. pcall-guarded.
local function _enemies_near(you, you_pos, radius)
    local count = 0
    pcall(function()
        local ai = Managers.state.entity and Managers.state.entity:system("ai_system")
        local bp = ai and ai.broadphase or (ai and ai:broadphase())
        if not bp then return end
        local results = {}
        local n = Broadphase.query(bp, you_pos, radius, results)
        local side = Managers.state and Managers.state.side
        for i = 1, n do
            local e = results[i]
            if e and HEALTH_ALIVE[e] then
                local is_enemy = true
                if side and side.is_enemy and you then
                    local ok, en = pcall(side.is_enemy, side, you, e)
                    if ok then is_enemy = en and true or false end
                end
                if is_enemy then count = count + 1 end
            end
        end
    end)
    return count
end

-- F6 helper: is the bot GENUINELY stuck (justifies a teleport) vs merely far?
-- Two signals: (1) successive_failed_paths() > 0 -- the same navigation counter
-- vanilla's should_teleport_to_position reads (bt_bot_conditions.lua:1201,
-- source-verified); (2) OFF-NAVMESH -- the bot's actual position sits more than
-- ~3 m from its last-known navmesh position (heuristic proxy, NOT source-exact:
-- last_position_on_navmesh lags behind while a unit is off the mesh). Either =>
-- stuck. When neither holds, the teleport is "pure distance" and F6 vetoes it.
local _F6_OFFNAV_SQ = 9.0   -- (3 m)^2
local function _bot_is_stuck(blackboard, self_unit)
    local nav = blackboard and blackboard.navigation_extension
    if nav and nav.successive_failed_paths then
        local ok, fails = pcall(nav.successive_failed_paths, nav)
        if ok and fails and fails > 0 then return true end
    end
    local wb = self_unit and ScriptUnit.has_extension(self_unit, "whereabouts_system")
    local navpos = wb and wb:last_position_on_navmesh()
    local actual = self_unit and POSITION_LOOKUP[self_unit]
    if navpos and actual and Vector3.distance_squared(actual, navpos) > _F6_OFFNAV_SQ then
        return true
    end
    return false
end

-- ----------------------------------------------------------------------------
-- DISPATCH 1: veto layer (F2/F4/F6/F7/F8/F9/F10). Returns true to BLOCK.
-- Called from the should_teleport hook AFTER gt computes a "wants teleport"
-- decision; a true here overrides even a vanilla-40m teleport. Vetoes are
-- OR-combined in F-number order; the FIRST that fires is logged + blocks.
-- ----------------------------------------------------------------------------
mod._gt_btlab_veto_teleport = function(blackboard, self_unit, follow_unit, dist_sq) -- luacheck: ignore dist_sq
    if not _BTLAB_FIXES_ARMED then return false end   -- DORMANT: retired #139 candidate (re-arm in code only)
    local veto_id, veto_detail
    pcall(function()
        local you       = _local_player_unit()
        local you_pos   = you and POSITION_LOOKUP[you]
        local bot_pos   = self_unit and POSITION_LOOKUP[self_unit]
        local follow_pos = follow_unit and POSITION_LOOKUP[follow_unit]

        -- F2 block_away: destination (approx = follow pos) is FARTHER from you
        -- than the bot is now => the teleport pulls the bot away from you.
        if not veto_id and _on("gt_btlab_f2_block_away") and you_pos and bot_pos and follow_pos then
            local bot_to_you  = Vector3.distance(bot_pos, you_pos)
            local dest_to_you = Vector3.distance(follow_pos, you_pos)
            if dest_to_you > bot_to_you then
                veto_id = "f02"
                veto_detail = string.format("dest %.1fm from you > bot %.1fm from you (would move AWAY)", dest_to_you, bot_to_you)
            end
        end

        -- F4 proximity_veto: bot already within f4_radius m of you.
        if not veto_id and _on("gt_btlab_f4_proximity_veto") and you_pos and bot_pos then
            local r = mod:get("gt_btlab_f4_radius") or 25.0
            local d = Vector3.distance(bot_pos, you_pos)
            if d <= r then
                veto_id = "f04"
                veto_detail = string.format("bot %.1fm <= %.0fm proximity radius of you", d, r)
            end
        end

        -- F6 stuck_only: veto a pure-distance teleport; only allow when the bot
        -- is genuinely off-navmesh / has failed paths.
        if not veto_id and _on("gt_btlab_f6_stuck_only") then
            if not _bot_is_stuck(blackboard, self_unit) then
                veto_id = "f06"
                veto_detail = "not off-navmesh + no failed paths (pure-distance teleport blocked)"
            end
        end

        -- F7 threshold_raise: veto until the bot is at least f7_distance m from
        -- follow_unit (much farther leash before any teleport).
        if not veto_id and _on("gt_btlab_f7_threshold_raise") and bot_pos and follow_pos then
            local thr = mod:get("gt_btlab_f7_distance") or 80.0
            local d = Vector3.distance(bot_pos, follow_pos)
            if d < thr then
                veto_id = "f07"
                veto_detail = string.format("bot->follow %.1fm < %.0fm threshold", d, thr)
            end
        end

        -- F8 combat_hold: veto while you have enemies within f8_radius (you are
        -- in active combat, so a bot shouldn't leash off to a far follow target).
        if not veto_id and _on("gt_btlab_f8_combat_hold") and you_pos then
            local r = mod:get("gt_btlab_f8_radius") or 15.0
            local n = _enemies_near(you, you_pos, r)
            if n > 0 then
                veto_id = "f08"
                veto_detail = string.format("%d enemy(s) within %.0fm of you (combat hold)", n, r)
            end
        end

        -- F9 cooldown: veto further teleports for f9_seconds after this bot's
        -- last teleport (per-bot timestamp stamped in observe_teleport / redirect).
        if not veto_id and _on("gt_btlab_f9_cooldown") and self_unit then
            local last = _last_tp[self_unit]
            if last then
                local secs = mod:get("gt_btlab_f9_seconds") or 3.0
                local since = _now() - last
                if since < secs then
                    veto_id = "f09"
                    veto_detail = string.format("%.1fs < %.1fs since last teleport (cooldown)", since, secs)
                end
            end
        end

        -- F10 direction_aware: veto if follow_unit is BEHIND your heading
        -- (dot(look/move dir, normalize(follow - you)) < 0) -- don't yank the
        -- bot backward relative to where you're going.
        if not veto_id and _on("gt_btlab_f10_direction_aware") and you_pos and follow_pos then
            local heading = _local_heading(you)
            if heading then
                local to_follow = follow_pos - you_pos
                to_follow = Vector3(to_follow.x, to_follow.y, 0)
                if Vector3.length(to_follow) > 0.01 then
                    local dp = Vector3.dot(heading, Vector3.normalize(to_follow))
                    if dp < 0 then
                        veto_id = "f10"
                        veto_detail = string.format("follow is BEHIND your heading (dot=%.2f)", dp)
                    end
                end
            end
        end
    end)

    if veto_id then
        _pf("[gt:btlab:%s] SUPPRESSED teleport bot=%s -- %s",
            veto_id, _unit_label(self_unit), veto_detail or "?")
        return true
    end
    return false
end

-- ----------------------------------------------------------------------------
-- DISPATCH 2: follow-unit override (F1/F5). Returns a unit to re-point
-- data.follow_unit at, or nil to keep the engine's assignment. F1 (you) beats
-- F5 (nearest human) when both are on.
-- ----------------------------------------------------------------------------
mod._gt_btlab_override_follow_unit = function(bot_unit, assigned_follow_unit) -- luacheck: ignore assigned_follow_unit
    if not _BTLAB_FIXES_ARMED then return nil end   -- DORMANT: retired #139 candidate (re-arm in code only)
    local result
    pcall(function()
        -- F1 follow_you: leash the bot to the LOCAL player. Precedence over F5.
        if _on("gt_btlab_f1_follow_you") then
            local you = _local_player_unit()
            if you and you ~= bot_unit and HEALTH_ALIVE[you] then
                result = you
                return
            end
        end
        -- F5 nearest_human: leash the bot to its nearest alive human.
        if _on("gt_btlab_f5_nearest_human") then
            local nh = _nearest_alive_human(bot_unit)
            if nh then result = nh end
        end
    end)
    return result
end

-- ----------------------------------------------------------------------------
-- DISPATCH 3: teleport redirect (F3). Called at the TOP of the .run hook. When
-- on, teleport the bot to YOUR navmesh position instead of follow_unit and
-- return true so the hook SKIPS vanilla func(). Mirrors the vanilla teleport
-- primitives (bt_bot_teleport_to_ally_action.lua:84-98) + gt's FIX 5 pattern.
-- ----------------------------------------------------------------------------
mod._gt_btlab_redirect_teleport = function(unit, blackboard)
    if not _BTLAB_FIXES_ARMED then return false end   -- DORMANT: retired #139 F3 (re-arm in code only)
    local handled = false
    pcall(function()
        local you = _local_player_unit()
        if not you or you == unit then return end
        local pos = _navmesh_pos(you)
        local locomotion = blackboard.locomotion_extension
        local nav = blackboard.navigation_extension
        if not (pos and locomotion and nav) then return end

        locomotion:teleport_to(pos)
        local status_extension = blackboard.status_extension
        if status_extension then
            status_extension:set_falling_height(true, pos.z)
            status_extension:set_ignore_next_fall_damage(true)
        end
        nav:teleport(pos)
        if blackboard.ai_extension and blackboard.ai_extension.clear_failed_paths then
            blackboard.ai_extension:clear_failed_paths()
        end
        blackboard.has_teleported = true
        if blackboard.follow then
            blackboard.follow.needs_target_position_refresh = true
        end
        _last_tp[unit] = _now()   -- feed F9 cooldown from the redirect too

        _pf("[gt:btlab:f03] REDIRECTED to local player bot=%s to=(%.1f,%.1f,%.1f)",
            _unit_label(unit), pos.x, pos.y, pos.z)
        handled = true
    end)
    return handled
end

-- ============================================================================
-- D3 + D9(clear) + bot registry + action ring buffer + #261 breach probe
--   -- merged into PlayerBotBase.update
-- ----------------------------------------------------------------------------
-- Registers the bot (so the HUD / leash-line draw has a blackboard + can
-- enumerate bots), watches for the has_teleported true->false clear (D9), prints
-- the throttled distance readout (D3), polls the current BT leaf action into the
-- always-on ring buffer, and runs the #261 radius-breach edge probe.
-- ============================================================================
mod._gt_btlab_observe_update = function(self, unit, blackboard, t) -- luacheck: ignore self
    if not IS_DEV_STREAM then return end
    pcall(function()
        -- registry for the HUD / leash-line draw + D10 snapshot (blackboard by unit).
        _bots[unit] = { blackboard = blackboard, seen = t }

        -- D9 clear detection (cheap true->false edge watch; always-on in dev).
        do
            local now_ht = blackboard.has_teleported and true or false
            local was_ht = blackboard._gt_btlab_ht_last
            if was_ht == nil then
                blackboard._gt_btlab_ht_last = now_ht
            elseif was_ht and not now_ht then
                blackboard._gt_btlab_ht_last = now_ht
                _pf("[gt:btlab:d9] has_teleported CLEARED for bot=%s (follow action re-armed; bot may teleport again)",
                    _unit_label(unit))
            elseif now_ht ~= was_ht then
                blackboard._gt_btlab_ht_last = now_ht
            end
        end

        -- D3 distance readout (throttled ~1s; always-on in dev).
        if _throttle(blackboard, "_gt_btlab_d3_t", t, 1.0) then
            local follow  = _follow_unit(blackboard)
            local you     = _local_player_unit()
            local d_follow = _dist_units(unit, follow)
            local d_you    = _dist_units(unit, you)
            local leash    = mod:get("gt_bot_follow_distance_m") or 40.0
            _pf("[gt:btlab:d3] bot=%s dist_follow=%s dist_you=%s leash=%.0fm (vanilla teleports at 40m)",
                _unit_label(unit),
                d_follow and string.format("%.1fm", d_follow) or "n/a",
                d_you    and string.format("%.1fm", d_you)    or "n/a",
                leash)
        end

        -- Action ring buffer: poll the current BT leaf action and push an entry
        -- when it CHANGES. ALWAYS-ON in dev now (was HUD-toggle-gated) so the #261
        -- breach / tether printf blocks AND the HUD both draw from it. Per-frame
        -- string read + a small table only on a transition (capped _ACTION_LOG_MAX).
        -- Host is implied: bot units only exist on the host.
        local action_id = _current_bot_action(blackboard)
        if action_id and action_id ~= _action_last[unit] then
            _action_last[unit] = action_id
            local log = _action_log[unit]
            if not log then
                log = {}
                _action_log[unit] = log
            end
            log[#log + 1] = { t = t, id = action_id }
            while #log > _ACTION_LOG_MAX do
                table.remove(log, 1)
            end
        end

        -- #261 RADIUS-BREACH probe (always-on in dev): edge-triggered when the bot
        -- crosses ABOVE the leash radius from its CURRENT follow anchor. The radius
        -- is gt_bot_follow_distance_m; the leash treats >= 40 as OFF (matches
        -- _gt_tighter_leash_wants in _gt_bot_fixes.lua: `if dist_m >= 40 then return
        -- false`), so we only probe when 0 < radius < 40. Hysteresis: re-arm only
        -- after the bot drops back under 80% of the radius. Per-bot ~3s cooldown.
        -- Edge + hysteresis + cooldown state stamped on the blackboard (per-bot,
        -- per-mission; nil-armed reads as armed).
        do
            local radius = mod:get("gt_bot_follow_distance_m") or 40.0
            if radius > 0 and radius < 40.0 then
                local follow = _follow_unit(blackboard)
                local d = follow and _dist_units(unit, follow)
                if d then
                    local armed = blackboard._gt_btlab_breach_armed
                    if armed == nil then armed = true end
                    if armed and d > radius then
                        blackboard._gt_btlab_breach_armed = false
                        local last = blackboard._gt_btlab_breach_t or -1e9
                        if t - last >= 3.0 then
                            blackboard._gt_btlab_breach_t = t
                            _report_breach(unit, blackboard, follow, d, radius, t)
                        end
                    elseif (not armed) and d <= radius * 0.8 then
                        blackboard._gt_btlab_breach_armed = true
                    end
                end
            end
        end
    end)
end

-- ============================================================================
-- Bot behavior HUD (Dev Tools, gt_devtools_bot_hud) + leash lines (Dev Tools,
-- gt_devtools_leash_lines). Both run from a registered mod.update consumer (NOT a
-- class hook) and only in the dev stream, on the host, with their toggle on.
--
-- The HUD draws one fixed on-screen COLUMN per bot: header (name + career), a
-- current-behavior block (current BT leaf action, follow target, distance to the
-- follow target + to you, has_teleported, teleport tally), then the last 20 BT
-- actions the bot entered (newest first) from the _action_log ring buffer. It
-- supersedes the old per-bot head-text (former D6). Leash lines draw a 3D line
-- from each bot to its follow target and to you (former D7).
--
-- PRIMITIVES:
--   lines: World.create_line_object / LineObject.add_line / .reset / .dispatch --
--          the SAME pattern _gt_solo_qol.lua ships for its boss-sphere debug draw.
--   text : World.create_screen_gui(world, "material", "materials/fonts/arial",
--          "immediate") + Gui.text at fixed screen pixels. Screen-gui origin is
--          bottom-left, y up, so a top-down column starts at (res_h - margin) and
--          steps y DOWN (mirrors managers/debug/debug.lua:400). Gui.text arg order
--          matches graph_drawer.lua:481. Everything pcall-guarded -> a bad read
--          no-ops (never crashes / never affects gameplay).
-- ============================================================================
local FONT      = "arial"
local FONT_MTRL = "materials/fonts/arial"          -- Gui.text FONT-material arg (matches vanilla debug.lua font_mtrl)
-- create_screen_gui MATERIAL. Must be gw_fonts, NOT FONT_MTRL: EVERY vanilla debug
-- screen GUI creates with "materials/fonts/gw_fonts" (debug.lua:12, graph_drawer.lua:10,
-- state_ingame.lua:2279-2280, achievement_manager.lua:947, ...). "materials/fonts/arial"
-- is a valid Gui.text FONT material but NOT a resident create_screen_gui material, so
-- passing it here was the #293/#295 "Gui material not found" C-fatal. gw_fonts is the
-- engine's always-resident font atlas (the same self-test material the gut GUI guard uses).
local GUI_MTRL  = "materials/fonts/gw_fonts"

-- release cached draw resources + clear any lingering lines.
-- #459: LineObject.reset/dispatch may ONLY run when the cached world handle is
-- IDENTICAL to the currently-live level_world. On Leave Game, StateIngame.on_exit
-- nils Managers.player.is_server (player_manager.lua:180) five lines before
-- _teardown_world destroys the level world (state_ingame.lua:719), and VMF keeps
-- ticking mods_update between game states -- so the next _btlab_draw frame routed
-- here and dispatched into the FREED world = C-level access violation (0xc0000005)
-- that the pcall below CANNOT catch (it was on the crashing stack). has_world alone
-- is not enough: after a world change a NEW same-named world passes has_world while
-- the cached handle still points at the freed old one (the case _do_draw's
-- world-change re-key already handles). Nulling the fields is ALWAYS correct on
-- every path: a destroyed world already freed its line objects, so dropping the
-- handles IS the teardown.
local function _clear_and_null()
    local lo = mod._gt_btlab_line_object
    local w  = mod._gt_btlab_line_world
    if lo and w then
        local wm   = Managers.world
        local live = wm and wm:has_world("level_world") and wm:world("level_world")
        if live == w then
            pcall(function()
                LineObject.reset(lo)
                LineObject.dispatch(w, lo)
            end)
        else
            -- Fires at most once per teardown: the fields are nulled below, so the
            -- next frame's call sees lo/w nil and skips this whole branch.
            _pf("[gt:459] skipped LineObject cleanup - cached world is dead")
        end
    end
    mod._gt_btlab_line_object  = nil
    mod._gt_btlab_line_world   = nil
    mod._gt_btlab_gui          = nil
    mod._gt_btlab_gui_world    = nil
    mod._gt_btlab_gui_deferred = nil   -- reset the #293/#295 defer breadcrumb latch
end

-- Live position for a unit THIS frame. CRITICAL: do NOT read POSITION_LOOKUP in this
-- (mod.update) draw phase -- the LOCAL PLAYER's entry (and any followed player) is a
-- DEAD frame-pool Vector3 handle here: AI/pickup entries are refreshed every frame by
-- their own systems, but the player's is seeded once at spawn and never refreshed in
-- Lua (PositionLookupSystem.update is a no-op). Reading it fed a stale userdata to
-- Vector3.distance / LineObject.add_line; the pcall around _do_draw silently swallowed
-- the throw, so the HUD reported "created OK" but painted NOTHING (the invisible-HUD
-- symptom on the #293/#295 retest). Unit.world_position is fresh every frame. Same
-- POSITION_LOOKUP-stale class as the #337 recall crash + the _gt_debug_highlights spam.
local function _live_pos(unit)
    if not (unit and ALIVE[unit]) then return nil end
    local ok, wp = pcall(Unit.world_position, unit, 0)
    if ok then return wp end
    return nil
end

local function _do_draw(want_hud, want_lines)
    -- WorldManager.world() FASSERTS on a missing world (world_manager.lua:111-115);
    -- probe has_world first (#459) -- this runs from mods_update, which keeps
    -- ticking between game states where level_world does not exist.
    local wm    = Managers.world
    local world = wm and wm:has_world("level_world") and wm:world("level_world")
    if not world then
        _clear_and_null()
        return
    end

    -- Leash lines: line object (recreate on world change).
    local lo
    if want_lines then
        if mod._gt_btlab_line_world ~= world then
            mod._gt_btlab_line_object = nil
            mod._gt_btlab_line_world  = world
        end
        if not mod._gt_btlab_line_object then
            mod._gt_btlab_line_object = World.create_line_object(world, false)
        end
        lo = mod._gt_btlab_line_object
        if lo then LineObject.reset(lo) end
    end

    -- HUD: screen gui (recreate on world change). No camera needed -- the columns
    -- draw at fixed screen pixels, not anchored to world positions.
    local gui
    if want_hud then
        if mod._gt_btlab_gui_world ~= world then
            mod._gt_btlab_gui          = nil
            mod._gt_btlab_gui_world    = world
            mod._gt_btlab_gui_deferred = nil   -- re-log one DEFERRED breadcrumb per world
        end
        if not mod._gt_btlab_gui then
            -- #293/#295 ROOT CAUSE: this used to create with FONT_MTRL (materials/fonts/arial),
            -- which is NOT a resident create_screen_gui material -> the engine's C-level
            -- "Gui material not found" assert, which BYPASSES pcall (the pcall wrapping
            -- _do_draw at the call site did NOT catch it, so it hard-killed the process with
            -- no Lua crash block, exactly what #295 saw). Fixed to GUI_MTRL (gw_fonts), the
            -- material every vanilla debug GUI uses. Belt-and-suspenders: still PRE-FILTER with
            -- Application.can_get (vanilla's non-faulting existence check, pickup_system.lua:882)
            -- so a momentary non-residency during a mission<->keep world swap DEFERS the HUD a
            -- frame instead of crashing. Fail CLOSED (skip) on any error -- a missing dev-HUD
            -- overlay is harmless, a CTD is not.
            local app = rawget(_G, "Application")
            local ok, resident = pcall(function()
                return app and app.can_get and app.can_get("material", GUI_MTRL)
            end)
            if ok and resident == true then
                -- Breadcrumb bracket: if the C call below ever hard-crashes (#295), the log
                -- ends right after this line, pinpointing create_screen_gui as the fatal.
                _pf("[gt:btlab] create_screen_gui: material '%s' resident -- creating HUD gui", GUI_MTRL)
                mod._gt_btlab_gui = World.create_screen_gui(world, "material", GUI_MTRL, "immediate")
                _pf("[gt:btlab] create_screen_gui: HUD gui created OK")
            elseif not mod._gt_btlab_gui_deferred then
                mod._gt_btlab_gui_deferred = true   -- latch: log the defer once per world
                _pf("[gt:btlab] create_screen_gui DEFERRED: material '%s' not resident (can_get=%s) -- HUD retries next frame (prevents #293/#295 'Gui material not found' CTD)",
                    GUI_MTRL, tostring(resident))
            end
        end
        gui = mod._gt_btlab_gui
    end

    local you     = _local_player_unit()
    local you_pos = _live_pos(you)
    local up      = Vector3(0, 0, 1.0)   -- lift lines off the floor

    local color_follow = Color(255, 255, 210, 40)    -- yellow: bot -> follow_unit
    local color_you    = Color(255, 60, 200, 220)    -- cyan:   bot -> local player

    -- Leash lines: one per registered bot (prune dead/despawned bots here too).
    if lo then
        for unit, rec in pairs(_bots) do
            local bot_pos = _live_pos(unit)
            if bot_pos then
                local bb         = rec.blackboard
                local follow     = bb and _follow_unit(bb)
                local follow_pos = _live_pos(follow)
                if follow_pos then
                    LineObject.add_line(lo, color_follow, bot_pos + up, follow_pos + up)
                end
                if you_pos and you ~= unit then
                    LineObject.add_line(lo, color_you, bot_pos + up, you_pos + up)
                end
            else
                _bots[unit] = nil
            end
        end
        LineObject.dispatch(world, lo)
    end

    if not gui then return end

    -- One fixed on-screen COLUMN per bot.
    local res   = rawget(_G, "RESOLUTION_LOOKUP")
    local res_h = (res and res.res_h) or 1080
    local margin_x, col_w, line_h, layer = 24, 340, 18, 500
    local top_y = res_h - 48   -- screen-gui y is up-from-bottom; start near the top

    -- Deterministic column order so columns don't swap frame to frame.
    local order = {}
    for unit in pairs(_bots) do
        if ALIVE[unit] then
            order[#order + 1] = unit
        end
    end
    table.sort(order, function(a, b) return tostring(a) < tostring(b) end)

    local white  = Color(255, 255, 255, 255)
    local header = Color(255, 120, 220, 220)
    local yellow = Color(255, 255, 210, 40)
    local grey   = Color(255, 170, 170, 170)

    for ci = 1, #order do
        local unit = order[ci]
        local bb   = _bots[unit].blackboard
        local x    = margin_x + (ci - 1) * col_w
        local y    = top_y

        local bot_pos  = _live_pos(unit)
        local follow   = bb and _follow_unit(bb)
        local f_pos    = _live_pos(follow)
        local d_follow = (bot_pos and f_pos) and Vector3.distance(bot_pos, f_pos) or nil
        local d_you    = (bot_pos and you_pos) and Vector3.distance(bot_pos, you_pos) or nil
        local action   = _current_bot_action(bb) or "?"
        local ht       = (bb and bb.has_teleported) and true or false
        local tally    = _tp_counts[unit]

        -- Draw one line then step y down. Closure over the mutable `y` upvalue.
        local function _put(str, size, color)
            Gui.text(gui, str, FONT_MTRL, size, FONT, Vector3(x, y, layer), color)
            y = y - line_h
        end

        _put(_unit_label(unit), 20, header)
        _put(string.format("action: %s", action), 18, yellow)
        _put(string.format("follow: %s", follow and _unit_label(follow) or "none"), 16, yellow)
        _put(string.format("dFollow=%s  dYou=%s",
            d_follow and string.format("%.0f", d_follow) or "?",
            d_you    and string.format("%.0f", d_you)    or "?"), 16, yellow)
        _put(string.format("teleported=%s  tally total/toward/away=%d/%d/%d",
            tostring(ht),
            tally and tally.total  or 0,
            tally and tally.toward or 0,
            tally and tally.away   or 0), 16, grey)
        y = y - 4
        _put("last 20 actions (newest first):", 16, white)

        local log = _action_log[unit]
        if log and #log > 0 then
            for li = #log, 1, -1 do
                local e = log[li]
                _put(string.format("t=%.1f  %s", e.t or 0, e.id or "?"), 14, grey)
            end
        else
            _put("(none yet)", 14, grey)
        end
    end
end

local function _btlab_draw(dt) -- luacheck: ignore dt
    -- Zero per-frame work unless dev + host + a Dev Tools draw toggle is on.
    if not IS_DEV_STREAM then
        _clear_and_null()
        return
    end
    if not (Managers.player and Managers.player.is_server) then
        _clear_and_null()   -- bots are host-only; nothing to draw off-host
        return
    end
    local want_hud   = mod:get("gt_devtools_bot_hud")    and true or false
    local want_lines = mod:get("gt_devtools_leash_lines") and true or false
    if not (want_hud or want_lines) then
        if mod._gt_btlab_draw_on then
            mod._gt_btlab_draw_on = false
            _pf("[gt:btlab] Dev Tools draw DISABLED -- overlay torn down")
        end
        _clear_and_null()
        return
    end
    -- #295 breadcrumb: mark the exact frame the bot-testing-tools overlay turns ON. A hard
    -- crash from the draw path that flushes no Lua block ends the log right after this line
    -- (and the create_screen_gui bracket in _do_draw), localizing the fatal for the next repro.
    if not mod._gt_btlab_draw_on then
        mod._gt_btlab_draw_on = true
        _pf("[gt:btlab] Dev Tools draw ENABLED (hud=%s lines=%s) -- building overlay",
            tostring(want_hud), tostring(want_lines))
    end
    pcall(_do_draw, want_hud, want_lines)
end

if mod._gt_register_update then
    mod._gt_register_update("btlab_draw", _btlab_draw)
end

-- ============================================================================
-- Reset per-mission state on StateIngame enter (chain-wrap; never redefine the
-- central handler). D8 counters + D10 snapshots + D2 follow tracking + the bot
-- registry all reset at the mission boundary.
-- ============================================================================
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        if status == "enter" and state_name == "StateIngame" then
            _reset_mission_state()
        end
    end
end

-- ============================================================================
-- D8  chat command: /bot_tp_dump  --  per-bot teleport tally (toward vs away)
-- ============================================================================
mod:command("bot_tp_dump", "Bot Teleport Lab: dump per-bot teleport tally (toward vs away from you)", function()
    if not IS_DEV_STREAM then
        mod:echo("[btlab] teleport diagnostics run only in the dev build.")
        return
    end
    local any = false
    local gt_total, gt_toward, gt_away = 0, 0, 0
    mod:echo("[btlab] teleport tally this mission:")
    for unit, c in pairs(_tp_counts) do
        any = true
        mod:echo("  %s -- total=%d toward_you=%d away_from_you=%d",
            c.label or _unit_label(unit), c.total, c.toward, c.away)
        gt_total  = gt_total  + c.total
        gt_toward = gt_toward + c.toward
        gt_away   = gt_away   + c.away
    end
    if not any then
        mod:echo("  (no teleports recorded yet this mission -- play a bit)")
    else
        mod:echo("  ALL BOTS -- total=%d toward_you=%d away_from_you=%d", gt_total, gt_toward, gt_away)
    end
end)

-- ============================================================================
-- D10  chat command: /bot_tp_snap  --  dump the teleport snapshot ring buffer
-- ============================================================================
mod:command("bot_tp_snap", "Bot Teleport Lab: dump the last teleport snapshots (positions/downed/follow)", function()
    if not IS_DEV_STREAM then
        mod:echo("[btlab] teleport diagnostics run only in the dev build.")
        return
    end
    if #_snaps == 0 then
        mod:echo("[btlab] no teleport snapshots captured yet this mission (play a bit).")
        return
    end
    mod:echo("[btlab] %d teleport snapshot(s), oldest first -- full detail in console log:", #_snaps)
    for i, s in ipairs(_snaps) do
        mod:echo("  #%d t=%.1f bot=%s trigger=%s (you: downed=%s disabled=%s)",
            i, s.t or 0, s.bot or "?", s.trigger or "?", tostring(s.you_downed), tostring(s.you_disabled))
        _pf("[gt:btlab:d10] snapshot #%d t=%.1f bot=%s trigger=%s you=%s you_downed=%s you_disabled=%s",
            i, s.t or 0, s.bot or "?", s.trigger or "?", s.you or "?",
            tostring(s.you_downed), tostring(s.you_disabled))
        for _, e in ipairs(s.players) do
            _pf("[gt:btlab:d10]   %s%s career=%s pos=%s downed=%s seg=%s follow=%s",
                e.is_bot and "[BOT] " or "[HUMAN] ", e.name, e.career,
                e.pos or "?", tostring(e.downed), tostring(e.seg), e.follow or "-")
        end
    end
    mod:echo("[btlab] (%d snapshots dumped to console log)", #_snaps)
end)

mod:info("[gt:btlab] loaded (dev diagnostics always-on=%s; F-candidates dormant)", tostring(IS_DEV_STREAM))
