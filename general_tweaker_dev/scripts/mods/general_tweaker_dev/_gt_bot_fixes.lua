local mod = get_mod("gt_dev")
mod._gt_bot_heal_policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_heal_policy")
mod._gt_bot_utility_policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_utility_policy")

-- ============================================================================
-- Bot Options -- AI teammate behavior fixes
-- ============================================================================
-- Default-OFF, host-side fixes for long-standing bot AI gaps. Bots only exist
-- on the host (server), so every hook here is effectively server-side; none
-- registers a network event or sends an RPC, so none can crash a non-modded
-- lobby member.
--
-- GATING SCHEME (#297, v0.2.182-dev): the FIX 1/2/3b/4/5/6/8/10 features gate
-- on the `gt_bot_behavior_improvements` MASTER toggle AND their own per-fix
-- sub-toggle (nested sub_widgets in the data file; checkbox ids reuse the
-- pre-bundle setting ids retired in v0.2.128-dev, all default ON). Sub-toggles
-- and the two delay sliders are read live inside the tick/hook bodies -- no
-- on_setting_changed wiring. Everything else here (fast reactions, drink
-- potions, follow mode, guard-break message, rescue-awaiting, FIX 0/7/9/11)
-- keeps its own independent toggle (FIX 11 default ON -- soft-lock fix).
--
-- Source citations below are into the decompiled vanilla source at
-- C:\Users\danjo\source\repos\Vermintide-2-Source-Code (verified 2026-06-16).
-- ============================================================================

local ScriptUnit = ScriptUnit
local POSITION_LOOKUP = POSITION_LOOKUP
local HEALTH_ALIVE = HEALTH_ALIVE
local Vector3 = Vector3
local BackendUtils = BackendUtils
local Unit = Unit
local Managers = Managers
local ALIVE = ALIVE
local Vector3Box = Vector3Box
local Breeds = Breeds

-- ============================================================================
-- UNGATED CRASH GUARD: malformed utility input must never reach arithmetic
-- ============================================================================
-- Vanilla Utility.get_action_utility subtracts every non-condition blackboard
-- input without a nil/type guard (utility.lua:29-41). AISystem initializes the
-- player-bot follow input `ally_distance` to math.huge (ai_system.lua:543-552),
-- and vanilla's ally picker preserves that sentinel when it finds no target
-- (player_bot_base.lua:843-1008). GT's ally-selection wrapper can legitimately
-- suppress a target, so it must preserve the same distance sentinel below.
--
-- This hook is owned here, not by Creature Spawner: it protects the host bot-AI
-- seam and is unrelated to spawning a custom breed. Valid input delegates to
-- vanilla unchanged. The exact player-bot follow input is repaired to vanilla's
-- math.huge sentinel; every other missing/non-numeric utility input returns zero
-- utility for that action instead of inventing a generic +/-infinity value.
local _gt_utility_guard_seen = {}
local _gt_player_follow_considerations = UtilityConsiderations
    and UtilityConsiderations.player_bot_default_follow

if Utility then
    mod:hook(Utility, "get_action_utility", function(func, breed_action, action_name, blackboard, ...)
        local ready, detail = mod._gt_bot_utility_policy.prepare_utility_inputs(
            breed_action,
            action_name,
            blackboard,
            _gt_player_follow_considerations
        )

        if not ready then
            local key = tostring(action_name) .. "|" .. tostring(detail)
            if not _gt_utility_guard_seen[key] then
                _gt_utility_guard_seen[key] = true
                printf("[gt:utility-guard] action=%s failed closed: %s",
                    tostring(action_name), tostring(detail))
            end
            return 0
        end

        if detail == "ally_distance" and not _gt_utility_guard_seen.ally_distance then
            _gt_utility_guard_seen.ally_distance = true
            printf("[gt:utility-guard] repaired player-bot follow ally_distance to vanilla math.huge sentinel")
        end

        return func(breed_action, action_name, blackboard, ...)
    end)

    printf("[gt:utility-guard] installed source-backed numeric-input guard")
end

if type(mod._gt_rt_register) == "function" then
    mod._gt_rt_register("gt_bot_utility_nil_guard", function()
        local follow = {
            distance_to_target = {
                blackboard_input = "ally_distance",
                max_value = 40,
                spline = { 0, 0.1, 1, 1 },
            },
        }
        local breed_action = { action_weight = 1, considerations = follow }
        local blackboard = { utility_actions = { follow = {} } }
        local ready = mod._gt_bot_utility_policy.prepare_utility_inputs(
            breed_action, "follow", blackboard, follow)

        if not ready or blackboard.ally_distance ~= math.huge then
            return "missing ally_distance was not restored to the vanilla sentinel"
        end

        local unrelated = {
            action_weight = 1,
            considerations = {
                range = {
                    blackboard_input = "unknown_range",
                    max_value = 10,
                    spline = { 0, 0, 1, 1 },
                },
            },
        }
        local unrelated_ready = mod._gt_bot_utility_policy.prepare_utility_inputs(
            unrelated, "attack", { utility_actions = { attack = {} } }, follow)
        if unrelated_ready then
            return "unknown numeric input did not fail closed"
        end
        -- Runner contract: fall off the end (nil) to PASS. `return true` scored
        -- healthy wiring as "FAIL -- true" (issue #1153).
    end)
end

-- Source-pattern marker for the FIX 1 give-half completion (v0.2.138-dev). The
-- /gt_regression_test "necro_potion_give_half_targeted_promote" check asserts
-- this constant + the SwapFromStorageType.Same promote so a refactor that
-- regresses to a blind SwapFromStorageType.First swap (which can mis-promote the
-- grimoire/skull and re-break the give) gets caught. See FIX 1 header below.
GT_NECRO_POTION_GIVE_HALF_MARKER_v0_2_138 = "gt-necro-potion-give-half-targeted-promote"

-- issue 142: the "ignore the backward/segment teleport gate" master+sub gate,
-- shared by FIX 7's tighter leash (skips its behind-segment gate), the new
-- backward-teleport fallback in the should_teleport hook, and FIX 3b's
-- force-revive path retry. Declared EARLY (before any consumer) so the
-- _select_ally_by_utility hook, the tighter leash, and the should_teleport hook
-- all capture it as an upvalue -- a later file-scope local would resolve to a nil
-- global inside those already-parsed closures. Reads live each call, no
-- on_setting_changed wiring. Default: master OFF, sub ON, so it only takes effect
-- once the user enables the Bot Options master.
local function _gt_ignore_backward_gate_on()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_ignore_backward_gate")
end
mod._gt_ignore_backward_gate_on = _gt_ignore_backward_gate_on

-- ============================================================================
-- REPLICANT BOTS PORT 1: Faster bot reactions (gt_bot_fast_reactions)
-- ----------------------------------------------------------------------------
-- Ported from "Replicant Bots - Different Bots Experimental Branch"
-- (DifferentBots.lua:273-306 + :3056-3058). Two parts, both gated on the
-- gt_bot_fast_reactions toggle:
--   1) Overwrite BotConstants.default.OPPORTUNITY_TARGET_REACTION_TIMES with a
--      flat {min=0.2,max=0.5} for EVERY difficulty so bots stop sitting on a
--      10-20s reaction delay before engaging an opportunity target.
--   2) Make AiUtils.calculate_bot_threat_time return the raw
--      bot_threat.start_time / bot_threat.duration (no random start_delay), so
--      bots dodge/react to telegraphed attacks immediately instead of rolling a
--      delayed reaction (vanilla: ai_utils.lua:723-739 returns
--      start_time+start_delay, duration-start_delay).
--
-- The source mod's on_disabled is author-flagged broken ("Disable function ...
-- is not properly written!"), so we do a REAL snapshot/restore: deep-copy the
-- vanilla table the first time we apply, and write it back verbatim on toggle
-- off. Host-side only (bot AI is server-side); no RPC. See on_setting_changed
-- dispatch in general_tweaker_dev.lua for the apply/restore call sites.
-- ============================================================================
local _gt_fast_react_value = { min = 0.2, max = 0.5 }
local _gt_fast_react_vanilla_snapshot   -- deep-copy of the vanilla reaction table (nil until first apply)
local _gt_fast_react_applied = false

local function _gt_deep_copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        out[k] = _gt_deep_copy(v)
    end
    return out
end

-- Apply the fast reaction-time table to every difficulty key the vanilla table
-- already defines (read live, not a static roster, so future difficulties are
-- covered). Snapshots the vanilla table on the first apply for restore.
local function _gt_apply_fast_reactions()
    local bc = BotConstants and BotConstants.default
    if not bc then return end
    local vanilla = bc.OPPORTUNITY_TARGET_REACTION_TIMES
    if type(vanilla) ~= "table" then return end

    if not _gt_fast_react_vanilla_snapshot then
        _gt_fast_react_vanilla_snapshot = _gt_deep_copy(vanilla)
    end

    local fast = {}
    for difficulty_key in pairs(_gt_fast_react_vanilla_snapshot) do
        fast[difficulty_key] = { min = _gt_fast_react_value.min, max = _gt_fast_react_value.max }
    end
    bc.OPPORTUNITY_TARGET_REACTION_TIMES = fast
    _gt_fast_react_applied = true

    mod:debug("[gt:bot] fast reactions applied (OPPORTUNITY_TARGET_REACTION_TIMES -> {min=0.2,max=0.5} for all difficulties)")
end

-- Restore the snapshotted vanilla reaction-time table.
local function _gt_restore_fast_reactions()
    local bc = BotConstants and BotConstants.default
    if not (bc and _gt_fast_react_vanilla_snapshot) then return end
    bc.OPPORTUNITY_TARGET_REACTION_TIMES = _gt_deep_copy(_gt_fast_react_vanilla_snapshot)
    _gt_fast_react_applied = false

    mod:debug("[gt:bot] fast reactions restored (vanilla OPPORTUNITY_TARGET_REACTION_TIMES re-applied)")
end

-- Public so general_tweaker_dev.lua's on_setting_changed can drive apply/restore.
mod._gt_apply_fast_reactions   = _gt_apply_fast_reactions
mod._gt_restore_fast_reactions = _gt_restore_fast_reactions

-- The raw-return threat-time hook. Gated; when on, return the un-delayed
-- start_time/duration so bots react to telegraphed attacks immediately.
-- (Source: DifferentBots.lua:3056-3058.) NEW (Class, method) pair -- no other
-- gt hook targets AiUtils.calculate_bot_threat_time (the only other AiUtils hook
-- in this repo is _gt_solo_qol.lua's generic_mutator_explosion).
mod:hook("AiUtils", "calculate_bot_threat_time", function (func, bot_threat)
    if mod:get("gt_bot_fast_reactions") then
        return bot_threat.start_time, bot_threat.duration
    end
    return func(bot_threat)
end)

-- ----------------------------------------------------------------------------
-- FIX 0 (CRASH): BTBotMeleeAction.enter nil slot_data hard crash
-- ----------------------------------------------------------------------------
-- WHAT
--   Vanilla BTBotMeleeAction.enter (bt_bot_melee_action.lua:70-92) does:
--       local slot_data = inventory_ext:get_slot_data(wielded_slot_name)  -- :82
--       local item_data = slot_data.item_data                            -- :83  <-- CRASH
--       ...
--       blackboard.wielded_item_template = item_template                 -- :86
--   When the bot's wielded slot is TRANSIENT/EMPTY for a frame -- e.g. the bot
--   was just given a weapon (CW bot-weapon mirror / cim / wt bot loadout / a
--   vanilla bot inventory re-equip) and the slot has no data yet -- get_slot_data
--   returns nil and :83 fatals "attempt to index local 'slot_data' (a nil value)"
--   (reported 2026-06-20, GUID 35c69dda; on the HOST, bots are host-only).
--
--   Guarding enter ALONE is not enough: enter writes blackboard.wielded_item_template
--   (nil in the empty-slot case), and the SAME frame the whole melee node derefs it
--   unguarded -- _update_melee (:418): _choose_attack (:209/:220),
--   _defend.defense_meta_data (:499), _can_stagger_target.actions (:562),
--   _time_to_next_attack / _attack .attack_meta_data/.actions/.name (:584-600).
--   So the node must NOT run a frame with a nil weapon.
--
-- FIX (two halves; the WHOLE melee node is made safe for a nil weapon)
--   1) HERE: wrap enter. Replicate vanilla's early, always-safe blackboard setup
--      (node_timer :71, the melee table :72-78, set_aiming :88-91) ourselves, then
--      only attempt the slot_data -> item_template resolution when slot_data is
--      present. If the wielded slot is empty, leave wielded_item_template = nil and
--      skip the crashing :83 deref. (We never call func, so vanilla's :83 can't run.)
--   2) In _gt_improved_bot_combat.lua, the consolidated (BTBotMeleeAction, "run")
--      hook bails the node ("done","evaluate") whenever wielded_item_template is nil,
--      so _update_melee never derefs the nil weapon. The bot leaves melee for one
--      frame and the BT re-selects next frame once the slot is populated.
--
--   UNGATED -- this is a crash fix, not the smarter-combat feature, so it must hold
--   regardless of the gt_improved_bot_combat toggle. Host-side only (bots are
--   host-only); no RPC, so it's inert/crash-safe on clients. Nil-guarded throughout.
mod:hook("BTBotMeleeAction", "enter", function (func, self, unit, blackboard, t)
    local inventory_ext = blackboard.inventory_extension
    local slot_data
    if inventory_ext then
        local wielded_slot_name = inventory_ext:get_wielded_slot_name()
        if wielded_slot_name then
            slot_data = inventory_ext:get_slot_data(wielded_slot_name)
        end
    end

    -- Slot is populated -> vanilla path is safe; let it run unchanged.
    if slot_data then
        return func(self, unit, blackboard, t)
    end

    -- Slot transient/empty -> replicate vanilla's always-safe early setup WITHOUT
    -- the :83 deref, leaving wielded_item_template = nil. The consolidated `run`
    -- hook then bails the node until the slot is populated.
    blackboard.node_timer = t
    blackboard.melee = {
        engage_change_time = 0,
        engage_position_set = false,
        engage_update_time = 0,
        engaging = false,
        engage_position = Vector3Box(0, 0, 0),
    }
    blackboard.wielded_item_template = nil

    local input_ext = blackboard.input_extension
    if input_ext then
        local soft_aiming = true
        input_ext:set_aiming(true, soft_aiming)
    end

    mod:debug("[gt:bot] BTBotMeleeAction.enter saw empty wielded slot (bot mid weapon-swap) -- deferred melee 1 frame (crash guard)")
end)

-- The three per-frame bot fixes and the singleton PlayerBotBase.update
-- dispatcher live in a dedicated module. Load order remains here because later
-- bot-fix hooks share the blackboard fields that dispatcher updates.
mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_update_fixes")

local _gt_bot_aid_install = mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_aid_owner")
local _gt_bot_aid = _gt_bot_aid_install({
    mod = mod,
    ScriptUnit = ScriptUnit,
    POSITION_LOOKUP = POSITION_LOOKUP,
    HEALTH_ALIVE = HEALTH_ALIVE,
    Vector3 = Vector3,
    Unit = Unit,
    Managers = Managers,
    ALIVE = ALIVE,
    ignore_backward_gate_on = _gt_ignore_backward_gate_on,
})
local _gt384_pin_live = _gt_bot_aid.pin_live
local _gt_status_needs_aid = _gt_bot_aid.status_needs_aid
local _gt_unit_needs_aid = _gt_bot_aid.unit_needs_aid
local _gt_aid_priority_on = _gt_bot_aid.aid_priority_on
local _gt_any_side_teammate_needs_aid = _gt_bot_aid.any_side_teammate_needs_aid
local _gt_nearest_needing_aid = _gt_bot_aid.nearest_needing_aid
local _gt492_label = _gt_bot_aid.label

-- ----------------------------------------------------------------------------
-- FIX 7: Tighter bot follow leash (configurable teleport distance)
-- ----------------------------------------------------------------------------
-- Vanilla teleports a bot to its follow target only at >= 40 m
-- (FOLLOW_TELEPORT_DISTANCE_SQ = 1600, bt_bot_conditions.lua:1206 + 1241). This
-- lets a configurable, tighter distance trigger the SAME teleport so bots stay
-- closer. We call the original first (the 40 m rule + all its gates still
-- apply); only if it declined do we re-check the identical gates with our
-- distance. The aid exception is preserved (target_ally_need_type / priority
-- target => never teleport), so a bot going for a revive still ignores the
-- leash. Faithful re-implementation of bt_bot_conditions.lua:1208-1241.
-- gt tighter-leash decision, extracted VERBATIM from the former should_teleport
-- hook body so the Bot Teleport Lab veto layer can wrap the whole decision
-- (see the hook below). Returns true if the gt tighter leash wants a teleport
-- the vanilla 40 m rule declined. All the original gates + the #139 / #139s
-- downed-teammate guards + their printf rate-limit latches are preserved exactly.
local function _gt_tighter_leash_wants(blackboard)
    -- (The "Tighter bot follow distance" enable toggle was removed 2026-06-30;
    -- the distance slider is the sole control -- 40 (its default/max) = vanilla no-op.)
    local dist_m = mod:get("gt_bot_follow_distance_m") or 40.0
    if dist_m >= 40.0 then
        -- Not tighter than vanilla's 40 m; nothing to add.
        return false
    end

    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    if not ALIVE[follow_unit] or blackboard.has_teleported then
        return false
    end

    local self_unit = blackboard.unit

    -- issue 142: the behind-segment gate (a follow target whose main-path segment
    -- is behind the bot blocks any teleport -- vanilla should_teleport
    -- bt_bot_conditions.lua:1220-1222) is opt-out by default via
    -- gt_bot_ignore_backward_gate, so the tighter leash can pull a bot BACKWARD to
    -- a straggler. The aid exception below and the #139 blanket veto in the hook
    -- still apply, so a bot never abandons a downed teammate to chase a straggler.
    if not _gt_ignore_backward_gate_on() then
        local conflict_director = Managers.state.conflict
        local self_segment = conflict_director:get_player_unit_segment(self_unit) or 1
        local target_segment = conflict_director:get_player_unit_segment(follow_unit)
        if not target_segment or target_segment < self_segment then
            return false
        end
    end

    local has_priority_target = blackboard.target_unit and blackboard.target_unit == blackboard.priority_target_enemy
    if blackboard.target_ally_need_type or has_priority_target then
        return false
    end

    local self_wb = ScriptUnit.has_extension(self_unit, "whereabouts_system")
    local follow_wb = ScriptUnit.has_extension(follow_unit, "whereabouts_system")
    local self_position = self_wb and self_wb:last_position_on_navmesh()
    local follow_position = follow_wb and follow_wb:last_position_on_navmesh()
    if not self_position or not follow_position then
        return false
    end

    local d2 = Vector3.distance_squared(self_position, follow_position)
    local fire = d2 >= dist_m * dist_m

    -- #139 (v0.2.185-dev): the "teammate needs aid" leash suppression that used
    -- to live here (the v0.2.148 snap-toward-downed guard + the v0.2.152 side-aid
    -- guard) moved UP to the BTConditions.should_teleport hook as a single
    -- BLANKET veto, so it also covers vanilla's 40 m teleport -- which this fn
    -- never sees, since it only runs when vanilla already DECLINED. This fn is
    -- now pure distance logic; the aid veto is applied once, to the final
    -- decision, in the hook.
    if fire then
        mod:debug("[gt:bot-leash] should_teleport TRUE at %.1fm (tighter leash, thresh=%.1fm)", math.sqrt(d2), dist_m)
    end
    return fire
end

-- issue 142: "does the leash want a BACKWARD teleport?" -- mirrors vanilla
-- BTConditions.should_teleport (bt_bot_conditions.lua:1208-1241) MINUS the
-- behind-segment gate (:1220-1222), so a follow target that is behind the bot on
-- the main path still triggers. Same state gates as vanilla: a live follow_unit,
-- not already teleported, and the aid exception (:1224-1228 -- a bot going for a
-- revive or with a priority enemy never leashes). Fires when the bot->follow
-- squared distance meets the SAME threshold the tighter leash uses (the
-- gt_bot_follow_distance_m slider; >= 40 == vanilla's 1600 sq). The caller
-- (should_teleport hook) only reaches this when vanilla AND the tighter leash both
-- declined and the master + gt_bot_ignore_backward_gate toggle are on; the #139
-- blanket aid veto is applied LAST, in the hook, never here.
--
-- `dist_sq` may be injected: the /gt_regression_test drives this with a stub
-- blackboard, and the ALIVE / ScriptUnit / Vector3 reads below are file-local
-- upvalues a test cannot stub (same constraint that made #139 split
-- _gt_status_needs_aid). Production passes nil and we read the same navmesh
-- whereabouts positions vanilla's should_teleport reads.
local function _gt_backward_teleport_wants(blackboard, dist_sq)
    if not blackboard then
        return false
    end
    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    if not follow_unit or blackboard.has_teleported then
        return false
    end

    -- Aid exception preserved (vanilla :1224-1228): never leash a bot that is
    -- going for a revive/rescue or holding a priority enemy target.
    local has_priority_target = blackboard.target_unit and blackboard.target_unit == blackboard.priority_target_enemy
    if blackboard.target_ally_need_type or has_priority_target then
        return false
    end

    if not dist_sq then
        if not ALIVE[follow_unit] then
            return false
        end
        local self_wb = ScriptUnit.has_extension(blackboard.unit, "whereabouts_system")
        local follow_wb = ScriptUnit.has_extension(follow_unit, "whereabouts_system")
        local self_position = self_wb and self_wb:last_position_on_navmesh()
        local follow_position = follow_wb and follow_wb:last_position_on_navmesh()
        if not self_position or not follow_position then
            return false
        end
        dist_sq = Vector3.distance_squared(self_position, follow_position)
    end

    local dist_m = mod:get("gt_bot_follow_distance_m") or 40.0
    local fire = dist_sq >= dist_m * dist_m
    if fire then
        mod:debug("[gt:bot-leash] should_teleport TRUE at %.1fm (backward gate ignored, thresh=%.1fm)", math.sqrt(dist_sq), dist_m)
    end
    return fire
end
mod._gt_backward_teleport_wants = _gt_backward_teleport_wants

-- ----------------------------------------------------------------------------
-- issue 515: teleport past no-return thresholds (composes with #142 + #492)
-- ----------------------------------------------------------------------------
-- Closes the three gaps #515 named. Everything below is gated on the SAME
-- gt_bot_ignore_backward_gate (+ Bot Behavior master) toggle as #142, so with the
-- toggle OFF every path is byte-for-byte vanilla. Host-side only: bot AI is
-- server-owned and these paths only read/write the host's own bot blackboards and
-- call the vanilla teleport action (which already syncs has_teleported over the
-- game object), so there is NO new RPC, NetworkLookup key, or wire field -- nothing
-- a non-host peer can crash or desync on.

-- GAP 1: re-arm the vanilla one-shot teleport latch. Vanilla sets
-- blackboard.has_teleported = true in the teleport action
-- (bt_bot_teleport_to_ally_action.lua:93) and clears it ONLY in
-- BTBotFollowAction.enter (bt_bot_follow_action.lua:14) -- the follow branch. A bot
-- that teleports and then goes straight into combat / an aid pursuit (never
-- re-entering the follow node) holds the latch forever, so a later genuine need (a
-- second shove past a no-return threshold) can never teleport. This PURE helper
-- (testability seam, no engine reads) says when to clear the latch: the toggle is on,
-- the latch is set, and it has been held >= GT515_REARM_COOLDOWN_S since the bot's
-- last ACTUAL teleport (nil last => never teleported through our action, so re-arm is
-- safe). The downstream distance / path-fail gates still decide whether a teleport
-- actually fires, so a close, following bot never re-teleports; the cooldown is only
-- the anti-spam backstop, sized inside the 3..12 s band vanilla itself uses to
-- declare a follow target unreachable (bt_bot_conditions.lua:1203, player_bot_base
-- .lua:1943-1946).
local GT515_REARM_COOLDOWN_S = 3.0
local function _gt515_should_rearm(has_teleported, toggle_on, now, last_tp)
    if not (has_teleported and toggle_on and now) then
        return false
    end
    return (not last_tp) or (now - last_tp) >= GT515_REARM_COOLDOWN_S
end
mod._gt515_should_rearm = _gt515_should_rearm
-- #515 GAP 1 regression marker (read by gt_bot515_teleport_latch_rearm).
GT_BOT515_LATCH_REARM_MARKER_v0_2_203 = "gt-bot515-teleport-latch-rearm"

-- GAP 2: extend the #142 backward-segment bypass to the follow/aid teleport_no_path
-- node (condition cant_reach_ally). PURE decision core (no engine reads). Vanilla
-- cant_reach_ally (bt_bot_conditions.lua:1167-1203) early-returns false for a
-- backward follow target (:1183-1187 is_backwards) BEFORE the fails/dwell test, so a
-- bot shoved past a no-return threshold (team behind it, straight-line < 40 m so the
-- should_teleport leash never fires) can never use this node. We drop only that early
-- return: is_forwards is false for a backward target, so the fails threshold is the
-- stricter non-forward 5 (never the forward 1) and the same t - last_success > 5
-- dwell and moving_toward_follow_position gate still apply -- a sustained failing path
-- IS the proof of unreachability, exactly as vanilla treats the same-segment case.
local function _gt515_cant_reach_backward_decide(is_backwards, moving_toward, fails, t, last_success)
    if not is_backwards then
        return false
    end
    local is_forwards = false   -- backward target => vanilla's non-forward branch (fails > 5)
    return (moving_toward and fails > (is_forwards and 1 or 5) and (t - last_success) > 5) and true or false
end
mod._gt515_cant_reach_backward_decide = _gt515_cant_reach_backward_decide

-- Engine-facing wrapper for GAP 2: reads the SAME state vanilla cant_reach_ally reads
-- (segments, navmesh whereabouts, successive_failed_paths, game time) and delegates
-- the verdict to the pure core. Returns true only for a genuinely-backward,
-- genuinely-unreachable follow target; the #139 / #492 aid composition is applied by
-- the caller (the cant_reach_ally hook), never here, so this stays pure geometry.
local function _gt_cant_reach_ally_backward_wants(blackboard)
    if not blackboard then return false end
    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    if not ALIVE[follow_unit] or blackboard.has_teleported then
        return false
    end
    local self_unit = blackboard.unit
    local conflict_director = Managers.state.conflict
    local self_segment = conflict_director:get_player_unit_segment(self_unit)
    local target_segment = conflict_director:get_player_unit_segment(follow_unit)
    if not self_segment or not target_segment then
        return false
    end
    local is_backwards = target_segment < self_segment
    if not is_backwards then
        -- Forward / same segment: vanilla cant_reach_ally already owns this decision
        -- (func() ran first in the hook). Never second-guess the forward path.
        return false
    end
    local self_wb = ScriptUnit.has_extension(self_unit, "whereabouts_system")
    local follow_wb = ScriptUnit.has_extension(follow_unit, "whereabouts_system")
    local self_position = self_wb and self_wb:last_position_on_navmesh()
    local follow_position = follow_wb and follow_wb:last_position_on_navmesh()
    if not self_position or not follow_position then
        return false
    end
    local navigation_extension = blackboard.navigation_extension
    if not navigation_extension then return false end
    local fails, last_success = navigation_extension:successive_failed_paths()
    if type(last_success) ~= "number" then
        return false   -- engine hasn't recorded a success yet -> stay conservative (more so than vanilla)
    end
    local t = Managers.time:time("game")
    return _gt515_cant_reach_backward_decide(is_backwards, blackboard.moving_toward_follow_position, fails, t, last_success)
end
mod._gt_cant_reach_ally_backward_wants = _gt_cant_reach_ally_backward_wants

-- #385 exact distance for the no-path branch. Vanilla cant_reach_ally and the
-- teleport action both use whereabouts:last_position_on_navmesh; matching that
-- source avoids classifying a navmesh separation with a stale raw unit pose.
mod._gt385_no_path_distance = function(blackboard)
    if not blackboard then return nil end
    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    if not ALIVE[follow_unit] then return nil end
    local self_wb = ScriptUnit.has_extension(blackboard.unit, "whereabouts_system")
    local follow_wb = ScriptUnit.has_extension(follow_unit, "whereabouts_system")
    local self_position = self_wb and self_wb:last_position_on_navmesh()
    local follow_position = follow_wb and follow_wb:last_position_on_navmesh()
    if not self_position or not follow_position then return nil end
    return math.sqrt(Vector3.distance_squared(self_position, follow_position))
end

mod._gt385_should_suppress_no_path = function(blackboard, reason)
    if not blackboard then return false end
    local distance = mod._gt385_no_path_distance(blackboard)
    local leash = mod:get("gt_bot_follow_distance_m") or 40.0
    local now = Managers.time and Managers.time.time and Managers.time:time("game")
    local policy = mod._gt_teleport_loop_policy
    if policy and policy.should_suppress_no_path(distance, leash, now,
            blackboard._gt385_last_no_path_t) then
        if rawget(_G, "printf") and not blackboard._gt385_suppress_latched then
            blackboard._gt385_suppress_latched = true
            printf("[gt:385] suppressed repeated %s teleport dist=%.1fm leash=%.1fm age=%.1fs retry=%.1fs",
                tostring(reason), distance, leash,
                now - blackboard._gt385_last_no_path_t, policy.NO_PATH_RETRY_S)
        end
        blackboard._gt139_tp_reason = nil
        return true
    end
    blackboard._gt385_suppress_latched = nil
    return false
end

mod:hook("BTConditions", "should_teleport", function (func, blackboard)
    -- Bot Teleport Lab (diagnostics) dispatch: D1 decision-recorder + D4 segment
    -- probe + D5 aid probe. Merged here because VMF drops a 2nd hook on this
    -- (Class, method); the lab defines mod._gt_btlab_observe_should_teleport
    -- (pcall-guarded, gated on gt_btlab_enabled). See _gt_bot_teleport_lab.lua.
    if mod._gt_btlab_observe_should_teleport then
        mod._gt_btlab_observe_should_teleport(blackboard)
    end

    -- issue 515 GAP 1: re-arm the vanilla one-shot has_teleported latch so a bot that
    -- already teleported once can teleport again later in the run (rationale +
    -- cooldown in _gt515_should_rearm above). Runs BEFORE func() so a cleared latch
    -- lets even vanilla's own 40 m rule re-fire. State is only touched under the
    -- toggle; the distance / path-fail gates below still gate the ACTUAL teleport, so
    -- this cannot spam (a close, following bot never re-teleports). The re-arm also
    -- un-gates the shared latch for cant_reach_ally (GAP 2), which reads the same
    -- blackboard.has_teleported.
    if blackboard.has_teleported and _gt_ignore_backward_gate_on() then
        local now = Managers.time and Managers.time.time and Managers.time:time("game")
        if _gt515_should_rearm(true, true, now, blackboard._gt515_last_tp_t) then
            -- One print per re-arm event: clearing the latch makes this branch false
            -- next tick until the bot actually teleports again (has_teleported true) and
            -- another cooldown elapses -- self-limiting, no per-frame spam.
            if rawget(_G, "printf") then
                printf("[gt:515] teleport latch re-armed for a stuck bot (held %.1fs since last teleport) -- it can teleport again",
                    blackboard._gt515_last_tp_t and (now - blackboard._gt515_last_tp_t) or -1)
            end
            blackboard.has_teleported = false
        end
    end

    -- CAPTURE the vanilla decision (do NOT early-return it) so the Bot Teleport
    -- Lab veto layer below can override even a vanilla-40 m TRUE. If vanilla
    -- declined, the gt tighter leash may still add a teleport.
    local want = func(blackboard) and true or false
    local reason = want and "vanilla_40m" or nil
    if not want then
        want = _gt_tighter_leash_wants(blackboard)
        if want then reason = "tighter_leash" end
    end
    -- issue 142: if vanilla AND the tighter leash both declined, the backward-gate
    -- override (master + gt_bot_ignore_backward_gate) lets the bot teleport to a
    -- follow target BEHIND it on the main path -- the case vanilla's segment gate
    -- (bt_bot_conditions.lua:1220-1222) always refuses. Same distance threshold as
    -- the tighter leash (>= 40 == vanilla's 1600 sq). Evaluated BEFORE the #139
    -- aid veto below, so that veto stays the FINAL word on the combined decision
    -- (a downed teammate still overrides a backward leash -- the bot paths in to
    -- revive rather than teleporting to its straggler follow target).
    if not want and _gt_ignore_backward_gate_on() then
        want = _gt_backward_teleport_wants(blackboard)
        if want then reason = "backward" end
    end
    -- #139 probe: stamp which branch wants the teleport so the .run probe can
    -- name the trigger. Stamped every call (nil when no teleport is wanted);
    -- cleared below on veto and read+cleared in BTBotTeleportToAllyAction.run.
    -- A .run that fires with reason nil means a non-should_teleport trigger
    -- (e.g. FIX 5's ladder unstick) -- the probe reports that as "other".
    blackboard._gt139_tp_reason = reason

    -- #139 FIX (v0.2.185-dev): BLANKET leash veto. With aid-priority ON, a bot
    -- must NEVER teleport while any teammate is downed/disabled -- it drops
    -- everything and paths in to revive (leash ignored; user decision on #139:
    -- all bots converge to revive). This supersedes the old
    -- in-_gt_tighter_leash_wants guards and, crucially, vetoes vanilla's 40 m
    -- teleport too (reason == "vanilla_40m"), which those guards could not reach
    -- (they only ran when vanilla had already declined). Root cause:
    -- AIBotGroupSystem._update_move_targets drops disabled players from the
    -- follow-candidate set unless EVERY player is down (ai_bot_group_system.lua
    -- :695-719), so on a split-team down follow_unit flips to a living far player
    -- and the leash yanks the bot AWAY from the downed one. #384 (v0.2.212-dev):
    -- _gt_any_side_teammate_needs_aid now scans side:player_units() (bots +
    -- awaiting-rescue) with the FULL disabler predicate, so the veto also holds
    -- for a downed BOT, a pounced/pack-mastered/tentacled/vortexed/corruptored
    -- teammate, and a fully-dead ally awaiting assisted respawn -- the exact gaps
    -- that let the bot in the #384 log leash to the standing human ~2 s after the
    -- downed ally's aid flag cleared (VETOED=0). Reading the ally's LIVE state
    -- here is what pins the errand across the target_ally_need_type flicker.
    -- Independent of follow mode (split/host/default) -- that only changes WHO is
    -- followed, not the teleport rule. _gt139_veto_latched rate-limits the printf.
    -- #492: the aid-pursuit stall watchdog (mod._gt492_aid_stall_tick) steps this
    -- veto aside for a bot it has bailed out of an UNREACHABLE revive
    -- (blackboard._gt492_bailout) so the bot can teleport back to the team; the
    -- picker has already dropped that aid pick, so this is the matching half. The
    -- gate stays contiguous (_gt_aid_priority_on() and _gt_any_side_teammate_needs_aid)
    -- for the singleton/gated regression checks.
    local aid_unit = _gt_aid_priority_on()
        and _gt_any_side_teammate_needs_aid(blackboard.unit)
        or nil
    -- #384 (v0.2.250-dev): the #492 bailout steps this veto aside ONLY when it
    -- is the authoritative no-path bail, or when no live pin holds the errand.
    -- A no-progress bail with a pinned, still-classifying ally must NOT release
    -- (log evidence: "VETO ... reason=tighter_leash" followed 0.02 s later by
    -- "TELEPORT ... same_aid=false" after a "BAILED (reason=no-progress)" in
    -- the same chain -- the release fed a teleport loop while the ally was
    -- still down). Reason nil (pre-stamp state) keeps the shipped release.
    local bail_release = blackboard._gt492_bailout
        and (blackboard._gt492_bailout_reason ~= "no-progress"
             or not _gt384_pin_live(blackboard))
    if want and not bail_release and aid_unit then
        local now = Managers.time and Managers.time.time and Managers.time:time("game")
        local group_ext = blackboard.ai_bot_group_extension
        local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
        local policy = mod._gt_teleport_loop_policy
        if policy and policy.make_aid_veto_trace then
            blackboard._gt139_last_veto = policy.make_aid_veto_trace(
                now or 0, aid_unit, follow_unit, reason)
        end
        if rawget(_G, "printf") and not blackboard._gt139_veto_latched then
            blackboard._gt139_veto_latched = true
            printf("[gt:139:chain] VETO bot=%s reason=%s follow=%s aid=%s bailout=%s need_type=%s pin=%s",
                _gt492_label(blackboard.unit), tostring(reason), _gt492_label(follow_unit),
                _gt492_label(aid_unit), tostring(blackboard._gt492_bailout and true or false),
                tostring(blackboard.target_ally_need_type),
                _gt492_label(blackboard._gt384_pin_unit))
        end
        blackboard._gt139_tp_reason = nil
        return false
    end
    blackboard._gt139_veto_latched = nil

    -- Bot Teleport Lab veto layer (F2/F4/F6/F7/F8/F9/F10). Runs AFTER the whole
    -- decision so it can suppress even a vanilla-40 m teleport. Gated +
    -- pcall-guarded inside mod._gt_btlab_veto_teleport; a true here BLOCKS.
    if want and mod._gt_btlab_veto_teleport then
        local group_ext = blackboard.ai_bot_group_extension
        local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
        if mod._gt_btlab_veto_teleport(blackboard, blackboard.unit, follow_unit, nil) then
            blackboard._gt139_tp_reason = nil
            return false
        end
    end

    return want
end)

-- #139 regression marker (read by bot_leash_veto_while_teammate_needs_aid_present
-- in the main file). If a refactor drops the blanket leash veto above, this
-- disappears and the test fails.
-- #139 (v0.2.185-dev): the v0.2.148 snap-toward-downed guard and the v0.2.152
-- side-aid guard were consolidated into a single BLANKET leash veto in the
-- should_teleport hook (covers vanilla 40 m + tighter leash). One marker now.
GT_BOT139_LEASH_VETO_AIDPRIORITY_MARKER_v0_2_185 = "gt-bot139-teleport-veto-while-teammate-needs-aid"
GT_BOT_FOLLOW_MODE_DROPDOWN_MARKER_v0_2_152 = "gt-bot-follow-mode-dropdown-consolidation"

-- issue 515 GAP 2 + GAP 3: backward bypass for the follow/aid teleport_no_path node
-- (condition cant_reach_ally, bt_bot.lua:431-435). A SEPARATE (Class, method) from
-- should_teleport, so no VMF duplicate-hook collision -- verified the only other
-- BTConditions hooks in this mod are can_activate_ability and should_teleport.
-- Vanilla's forward decision is returned untouched; ONLY the new backward path is
-- governed by the #139 / #492 aid composition, mirroring the should_teleport hook
-- exactly so a REACHABLE revive still wins, but a #492-bailed bot (unreachable down,
-- team behind it) can teleport back to regroup (GAP 3). Unlike should_teleport this
-- node has NO 40 m floor -- it fires purely on sustained path failure -- so it covers
-- the close-range no-return case (a ledge into the next room 15 m away) the leash
-- misses. Host-side (bot AI server-owned); no wire surface.
mod:hook("BTConditions", "cant_reach_ally", function (func, blackboard)
    local want = func(blackboard) and true or false
    if want then
        -- #385: this is vanilla's SECOND teleport trigger, the
        -- `teleport_no_path` node (bt_bot.lua:431-435), not the leash node.
        -- It has no distance floor: cant_reach_ally fires after sustained path
        -- failures (bt_bot_conditions.lua:1167-1203), explaining the observed
        -- 2.8-15 m `unknown` events. Keep the first legitimate unstick, but
        -- suppress repeats below the configured leash for five seconds.
        if mod._gt385_should_suppress_no_path(blackboard, "vanilla_no_path") then
            return false
        end
        blackboard._gt139_tp_reason = "vanilla_no_path"
        return true
    end
    if not blackboard or not _gt_ignore_backward_gate_on() then
        if blackboard then blackboard._gt515_creach_latched = nil end
        return false                                 -- toggle off => pure vanilla
    end
    if not _gt_cant_reach_ally_backward_wants(blackboard) then
        blackboard._gt515_creach_latched = nil
        return false
    end
    -- #139 / #492 composition (identical discipline to the should_teleport hook):
    -- while aid-priority is ON and a teammate genuinely needs aid, do NOT let this new
    -- backward teleport pull the bot off a REACHABLE revive -- UNLESS the #492
    -- watchdog already bailed this bot out of an UNREACHABLE aid pursuit
    -- (blackboard._gt492_bailout), in which case the backward teleport is exactly how
    -- it regroups (item 3). Vanilla's forward path above is never subject to this veto.
    -- #384 (v0.2.250-dev): same bail discrimination as the should_teleport veto --
    -- only a no-path bail (or a bail with no live errand pin) releases; a
    -- no-progress bail while the pinned ally still classifies holds the veto.
    local creach_bail_release = blackboard._gt492_bailout
        and (blackboard._gt492_bailout_reason ~= "no-progress"
             or not _gt384_pin_live(blackboard))
    if not creach_bail_release and _gt_aid_priority_on()
            and _gt_any_side_teammate_needs_aid(blackboard.unit) then
        if rawget(_G, "printf") and blackboard._gt515_creach_latched ~= "veto" then
            blackboard._gt515_creach_latched = "veto"
            printf("[gt:515] cant_reach_ally backward teleport VETOED -- teammate needs aid, bot paths to revive")
        end
        return false
    end
    if mod._gt385_should_suppress_no_path(blackboard, "backward_no_path") then
        return false
    end
    -- Allowed: stamp the reason so the existing BTBotTeleportToAllyAction.run probe
    -- names this trigger ("backward_no_path") instead of reporting "other".
    blackboard._gt139_tp_reason = "backward_no_path"
    if rawget(_G, "printf") and blackboard._gt515_creach_latched ~= "allow" then
        blackboard._gt515_creach_latched = "allow"
        printf("[gt:515] cant_reach_ally backward bypass -> teleport_no_path (bot regroups across a no-return threshold)")
    end
    return true
end)

-- #515 GAP 2 regression marker (read by gt_bot515_cant_reach_backward_bypass).
GT_BOT515_CANT_REACH_BACKWARD_MARKER_v0_2_203 = "gt-bot515-cant-reach-ally-backward-bypass"

-- #385 below-leash branch instrument (v0.2.250-dev, log-only, capped). The
-- #385 log's missing datum: 9 of 40 executed teleports fired BELOW the leash
-- slider (down to 2.8 m) with `trigger=unknown`. Every distance trigger
-- (vanilla 40 m, tighter leash, backward) is impossible below min(leash, 40),
-- so any such execution came from a non-distance branch -- the reason stamp
-- (vanilla_no_path / backward_no_path / other) names it. Instrument only, no
-- suppression added here (diagnose-before-mitigating); the existing bounded
-- no-path retry (mod._gt385_should_suppress_no_path) is unchanged. Distance is
-- captured PRE-teleport from the same navmesh whereabouts source the decision
-- reads (mod._gt385_no_path_distance); the session cap lives in
-- _gt_teleport_loop_policy.BELOW_LEASH_LOG_CAP.
GT_BOT385_BELOW_LEASH_INSTRUMENT_MARKER_v0_2_250 = "gt-bot385-below-leash-branch-instrument"
local _gt385_below_leash_logged = 0

-- Debug confirmation that the teleport ACTION actually executed -- a SEPARATE
-- (Class, method) pair from FIX 7's BTConditions.should_teleport, so not a
-- duplicate hook. Fires for every bot teleport (vanilla 40 m, the tighter leash,
-- and FIX 5's ladder-unstick); debug-gated, host-side. If the log shows
-- `should_teleport TRUE` but never this line, the BT selector is gating the
-- action upstream (combat/aid subtree winning), not FIX 7.
-- CONVERTED from hook_safe to a FULL mod:hook (v Bot-Teleport-Lab) so the lab's
-- D1 event log can read the bot's position BEFORE and AFTER the teleport (a
-- hook_safe post-callback only sees the AFTER position). The pre-existing FIX 7
-- debug + #139 printf body is PRESERVED verbatim below, just relocated to run
-- after func(). Still a SEPARATE (Class, method) pair from FIX 7's
-- BTConditions.should_teleport, so no duplicate-hook collision.
mod:hook("BTBotTeleportToAllyAction", "run", function (func, self, unit, blackboard, t, dt)
    -- Bot Teleport Lab F3 (teleport_to_you): redirect the teleport to YOUR
    -- navmesh position instead of follow_unit. If it fully handles the teleport
    -- (returns true), SKIP vanilla func() and report "done" like vanilla run().
    -- Gated + pcall-guarded inside mod._gt_btlab_redirect_teleport.
    if mod._gt_btlab_redirect_teleport and mod._gt_btlab_redirect_teleport(unit, blackboard) then
        return "done"
    end

    -- Bot Teleport Lab: capture the bot's position BEFORE the teleport (boxed so
    -- it survives the wrapped call). Returns nil unless the lab is enabled.
    local btlab_pre
    if mod._gt_btlab_pre_teleport then
        btlab_pre = mod._gt_btlab_pre_teleport(unit, blackboard)
    end

    -- #139 decision-point probe (default-on, printf): capture the pre-teleport
    -- distance to the nearest downed/awaiting-rescue teammate as a SCALAR (so it
    -- survives the teleport) plus the branch that wanted this teleport (stamped
    -- by the should_teleport hook above).
    local p139_aid_unit, p139_pre_dist = _gt_nearest_needing_aid(unit)
    local p139_reason = (blackboard and blackboard._gt139_tp_reason) or "other"
    -- #385: capture the follow distance BEFORE the snap (afterwards the bot is
    -- beside its follow target and the datum is destroyed).
    local p385_pre_dist = (blackboard and mod._gt385_no_path_distance)
        and mod._gt385_no_path_distance(blackboard) or nil

    local result = func(self, unit, blackboard, t, dt)

    -- issue 515 GAP 1: record when this bot last teleported so the should_teleport
    -- hook's latch re-arm measures its cooldown from the last ACTUAL teleport. Stamped
    -- for every teleport (vanilla 40 m, tighter leash, backward, no-path).
    if blackboard then
        blackboard._gt515_last_tp_t = t
        if mod._gt_teleport_loop_policy
                and mod._gt_teleport_loop_policy.is_no_path_reason(p139_reason) then
            blackboard._gt385_last_no_path_t = t
        end
    end

    -- ---- PRESERVED FIX 7 / #139 body (unchanged) ----
    mod:debug("[gt:bot-leash] TELEPORT executed (bot snapped to its follow target)")
    -- #261: every leash yank carries its cause. The lab's dispatch printfs a
    -- [gt:btlab:tether] block (current action + action ring buffer, ~2s per-bot
    -- cooldown) so the yank is visible with mod logging OFF. Dev-gated + pcall
    -- inside the lab fn; a no-op in stable. No new hook (this run hook already exists).
    if mod._gt_btlab_report_tether then
        mod._gt_btlab_report_tether(unit, blackboard)
    end
    -- #139 probe (printf -> visible with mod-logging off). If this still reports
    -- `follow downed=true` AFTER the v0.2.148-dev guard above, the snap came from
    -- vanilla's 40 m teleport (func()), not GT's tighter leash -- extend the fix
    -- to gate the vanilla path too. If it never fires for the downed case, the
    -- guard is doing its job and bots now path to revives.
    if rawget(_G, "printf") then
        local group_ext = blackboard and blackboard.ai_bot_group_extension
        local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
        printf("[gt_bot:139] TELEPORT executed (follow downed=%s)",
            tostring(follow_unit ~= nil and _gt_unit_needs_aid(follow_unit) or false))
    end

    -- #139 decision-point probe: only emit when a teammate is actually down or
    -- awaiting rescue (the scenario of interest). One line per teleport event.
    -- post_dist near 0 after the snap means the bot teleported ONTO the downed
    -- player (the reported bug); a large post_dist means it snapped to a living
    -- follow while a different teammate is still down. dist_to_downed is the
    -- PRE-teleport distance; target is where the bot ended up.
    if p139_aid_unit and rawget(_G, "printf") then
        local ce = ScriptUnit.has_extension(unit, "career_system")
        local bot_career = (ce and ce.career_name and ce:career_name()) or "?"
        local post_ok, post = pcall(Unit.world_position, unit, 0)
        if not post_ok then post = nil end
        local aid_post = POSITION_LOOKUP[p139_aid_unit]
        local post_dist = (post and aid_post) and Vector3.distance(post, aid_post) or -1
        local tx, ty, tz = -1, -1, -1
        if post then
            tx, ty, tz = Vector3.x(post), Vector3.y(post), Vector3.z(post)
        end
        printf("[139:bot_tp] bot=%s dist_to_downed=%.1fm reason=%s post_dist=%.1fm target=%.1f,%.1f,%.1f t=%.2f",
            bot_career, p139_pre_dist or -1, p139_reason, post_dist, tx, ty, tz, t)
    end
    -- #385 instrument: one capped line for every teleport that executed while
    -- the pre-snap follow distance was below BOTH the gt leash slider and
    -- vanilla's 40 m floor -- tagging WHICH branch fired (the missing datum).
    -- Fires regardless of aid state (the observed events had no teammate down).
    if rawget(_G, "printf") and blackboard and p385_pre_dist then
        local policy = mod._gt_teleport_loop_policy
        local leash_m = tonumber(mod:get("gt_bot_follow_distance_m")) or 40.0
        if policy and policy.should_log_below_leash
                and policy.should_log_below_leash(p385_pre_dist, leash_m,
                    _gt385_below_leash_logged, policy.BELOW_LEASH_LOG_CAP) then
            _gt385_below_leash_logged = _gt385_below_leash_logged + 1
            printf("[gt:385] below-leash TELEPORT %d/%d bot=%s branch=%s follow_dist=%.1fm leash=%.1fm aid_now=%s need_type=%s",
                _gt385_below_leash_logged, policy.BELOW_LEASH_LOG_CAP,
                _gt492_label(unit), tostring(p139_reason), p385_pre_dist, leash_m,
                _gt492_label(p139_aid_unit), tostring(blackboard.target_ally_need_type))
        end
    end
    -- #139/#384 correlated execution record. The earlier probe printed a veto
    -- without bot/ally identity and an execution without the veto/bailout state,
    -- so two bots in one lobby could not be joined end-to-end. One row is emitted
    -- only for an aid-adjacent teleport (live aid, a <=3 s veto record, or #492
    -- bailout), never per frame. The selector's final follow target is stamped by
    -- the consolidated _assign_destination_points diagnostics dispatch below.
    if rawget(_G, "printf") and blackboard then
        local policy = mod._gt_teleport_loop_policy
        local veto = blackboard._gt139_last_veto
        local veto_age, same_aid
        if policy and policy.correlate_aid_veto then
            veto_age, same_aid = policy.correlate_aid_veto(veto, t, p139_aid_unit)
        end
        if p139_aid_unit or veto_age ~= nil or blackboard._gt492_bailout then
            local group_ext = blackboard.ai_bot_group_extension
            local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
            printf("[gt:139:chain] TELEPORT bot=%s reason=%s selector_follow=%s action_follow=%s aid_now=%s veto_aid=%s veto_follow=%s veto_age=%s same_aid=%s bailout=%s bailout_unit=%s need_type=%s",
                _gt492_label(unit), tostring(p139_reason),
                _gt492_label(blackboard._gt139_final_follow), _gt492_label(follow_unit),
                _gt492_label(p139_aid_unit), _gt492_label(veto and veto.aid_unit),
                _gt492_label(veto and veto.follow_unit),
                veto_age and string.format("%.2fs", veto_age) or "none",
                tostring(same_aid), tostring(blackboard._gt492_bailout and true or false),
                _gt492_label(blackboard._gt492_bailout_unit),
                tostring(blackboard.target_ally_need_type))
        end
    end
    -- Bot Teleport Lab dispatch (post): D1 full event line + D8 counter + D9 set
    -- + D10 snapshot. pcall-guarded + gated inside the lab fn.
    if mod._gt_btlab_observe_teleport then
        mod._gt_btlab_observe_teleport(self, unit, blackboard, btlab_pre, p139_reason)
    end
    if blackboard then
        blackboard._gt139_tp_reason = nil
    end

    return result
end)

-- Diagnostics-only marker for the #139/#384 correlated chain. Runtime and
-- engine-free tests require the veto identity, final selector identity, #492
-- state, and actual teleport action to remain in one bounded event record.
GT_BOT139_CORRELATED_AID_TRACE_MARKER_v0_2_243 = "gt-bot139-veto-selector-action-correlation"

-- ----------------------------------------------------------------------------
-- FIX 8: Don't fail the mission while a bot is still alive
-- ----------------------------------------------------------------------------
-- GameModeAdventure.evaluate_end_conditions calls
-- GameModeHelper.side_is_dead("heroes", ignore_bots = true)
-- (game_mode_adventure.lua:92), so the run is declared lost when all HUMANS are
-- down even if a bot is alive and standing. We force ignore_bots = false for the
-- "heroes" side so a living bot counts -- the mission only ends when no teammate
-- (human OR bot) remains. Pairs with "Bots rescue allies awaiting respawn". The
-- wipe check runs server-side (GameModeManager.server_update), so this is
-- effectively host-side.
mod:hook("GameModeHelper", "side_is_dead", function (func, side_name, ignore_bots)
    -- v0.2.128-dev: bundled (was gt_bot_mission_fail_prevention); #297
    -- (v0.2.182-dev): master AND its own sub-toggle again.
    if mod:get("gt_bot_behavior_improvements")
            and mod:get("gt_bot_mission_fail_prevention")
            and side_name == "heroes" then
        return func(side_name, false)
    end
    return func(side_name, ignore_bots)
end)

-- FIX 10 greedy-pickup hooks moved to _gt_bot_pickups.lua (issue #364).
-- ----------------------------------------------------------------------------
-- FIX 12 (#468, v0.2.205-dev): Smarter bot self-healing (when to spend a heal)
-- ----------------------------------------------------------------------------
-- Opt-in #468 reimplementation of vanilla bot_should_heal (:893-921): configurable
-- HP threshold, reserve heal-other kits for humans, and suppress surplus self-use.
-- Missing state and toggle-off remain pure vanilla passthroughs; host-side only.
GT_BOT_SMART_SELF_HEAL_MARKER_v0_2_205 = "gt-bot-smart-self-heal-bot_should_heal-reimpl"

local function _gt_smart_self_heal_on()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_smart_self_heal")
end
mod._gt_smart_self_heal_on = _gt_smart_self_heal_on

-- Duplicate-hook pre-flight (2026-07-12): whole-mod grep found NO other hook on
-- (BTConditions, "bot_should_heal") -- the sibling BTConditions hooks are on
-- distinct methods (should_teleport / cant_reach_ally / can_activate_ability
-- here; the boss health-transition family in _gt_creature_spawner.lua). Fresh
-- (Class, method) pair, so this is the sole owner.
mod:hook("BTConditions", "bot_should_heal", function (func, blackboard)
    if not _gt_smart_self_heal_on() then
        return func(blackboard)
    end

    local inventory_extension = blackboard and blackboard.inventory_extension
    local health_extension = blackboard and blackboard.health_extension
    local status_extension = blackboard and blackboard.status_extension
    local self_unit = blackboard and blackboard.unit
    if not (inventory_extension and health_extension and status_extension and self_unit) then
        return func(blackboard)
    end

    local health_slot_data = inventory_extension:get_slot_data("slot_healthkit")
    local template = health_slot_data and inventory_extension:get_item_template(health_slot_data)
    local can_heal_self = template and template.can_heal_self
    if not can_heal_self then
        return false   -- vanilla :900-902
    end

    -- Vanilla :904-919, faithfully mirrored. Any of these engine reads throwing
    -- would also throw in vanilla, but keep the passthrough guard above cheap.
    local buff_extension = ScriptUnit.has_extension(self_unit, "buff_system")
    local has_no_permanent_health_from_item_buff = buff_extension
        and buff_extension:has_buff_type("trait_necklace_no_healing_health_regen")
    local wounded = status_extension:is_wounded()

    -- gt substitution 3: optionally ignore the item-surplus forced self-use.
    local raw_force_use = blackboard.force_use_health_pickup
    local force_use_health_pickup = raw_force_use
    if mod:get("gt_bot_ignore_surplus_selfuse") then
        force_use_health_pickup = nil
    end

    local current_health_percent = health_extension:current_health_percent()
    local perma_health_percent = health_extension:current_permanent_health_percent()
    local heavy_curse = health_extension:get_max_health() <= 75

    -- gt substitution 1: user HP% threshold replaces template.bot_heal_threshold.
    local gt_pct = tonumber(mod:get("gt_bot_self_heal_pct"))
    local gt_threshold = (gt_pct and gt_pct / 100) or template.bot_heal_threshold
    local hurt = current_health_percent <= gt_threshold
    local low_on_perma_health = perma_health_percent <= gt_threshold

    local target_unit = blackboard.target_unit
    local proximite_enemies = blackboard.proximite_enemies
    local is_safe = not target_unit
        or (template.fast_heal or blackboard.is_healing_self) and proximite_enemies and #proximite_enemies == 0
        or target_unit ~= blackboard.priority_target_enemy and target_unit ~= blackboard.urgent_target_enemy
            and target_unit ~= blackboard.proximity_target_enemy and target_unit ~= blackboard.slot_target_enemy

    -- Vanilla inner "want" (the parenthesised body of vanilla :921), with gt's
    -- threshold + surplus substitutions already applied.
    local want = force_use_health_pickup
        or (not has_no_permanent_health_from_item_buff and (hurt or wounded and (low_on_perma_health or heavy_curse)))
        or (has_no_permanent_health_from_item_buff and hurt and wounded)

    -- gt substitution 2: reserve a heal-OTHER kit for humans. Hold it unless the
    -- bot is wounded (grey health -- it genuinely needs the perma-heal) or the
    -- surplus force-use fired. Draughts (no can_heal_other) are never reserved.
    local reserved = false
    if mod:get("gt_bot_reserve_kits_for_players") and template.can_heal_other
            and not (wounded or force_use_health_pickup) then
        want = false
        reserved = true
    end

    local decision = (is_safe and want) and true or false

    -- [gt:468] edge-triggered trace (per bot, on decision change only, so no
    -- per-frame spam). Also compute what VANILLA would have decided from the same
    -- inputs (template threshold + un-suppressed force-use) so a "held back" edge
    -- shows exactly the waste gt prevented.
    local prev = blackboard._gt468_prev_decision
    if decision ~= prev then
        blackboard._gt468_prev_decision = decision
        local v_thr = template.bot_heal_threshold or 0
        local v_want = raw_force_use
            or (not has_no_permanent_health_from_item_buff and (current_health_percent <= v_thr
                or wounded and (perma_health_percent <= v_thr or heavy_curse)))
            or (has_no_permanent_health_from_item_buff and current_health_percent <= v_thr and wounded)
        local vanilla_decision = (is_safe and v_want) and true or false
        local item_label = template.can_heal_other and "medical_supplies" or (template.fast_heal and "draught" or "healkit")
        if decision then
            printf("[gt:468] bot SELF-HEAL greenlit item=%s hp=%.0f%% perma=%.0f%% wounded=%s force_use=%s safe=%s (gt_thr=%.0f%% vanilla_thr=%.0f%%)",
                item_label, current_health_percent * 100, perma_health_percent * 100,
                tostring(wounded), tostring(raw_force_use and true or false), tostring(is_safe),
                gt_threshold * 100, v_thr * 100)
        elseif vanilla_decision then
            printf("[gt:468] bot self-heal HELD BACK (vanilla would have healed) item=%s hp=%.0f%% perma=%.0f%% wounded=%s reserved=%s force_use=%s (gt_thr=%.0f%% vanilla_thr=%.0f%%)",
                item_label, current_health_percent * 100, perma_health_percent * 100,
                tostring(wounded), tostring(reserved), tostring(raw_force_use and true or false),
                gt_threshold * 100, v_thr * 100)
        end
    end

    return decision
end)

-- ----------------------------------------------------------------------------
-- FIX 9: Split bots among human players (one bot per human, round-robin)
-- ----------------------------------------------------------------------------
-- WHAT
--   VT2 picks ONE move-target human per side and points EVERY bot's
--   data.follow_unit at that SAME human (ai_bot_group_system.lua:1085 -> per-bot
--   write :1119-1120). The ONLY case the engine spreads bots one-per-human is
--   the 2-human + 2-bot CARRY event (:760 follow_unit_table). It also abandons a
--   player who stands still for AFK_TIME_LIMIT = 20s (the "~18s" the user
--   remembered) and swarms a moving player -- but ONLY in the 1-2-player branch
--   (_find_closest_move_target:846-848; constants :651-652). The 3+ branch
--   ignores AFK entirely.
--
-- FIX
--   Post-hook _assign_destination_points -- the single per-frame chokepoint where
--   data.follow_unit is written for every bot. We run AFTER the engine's scalar
--   write, build a deterministic mapping (humans sorted host-first, bots sorted
--   by unit) and overwrite data.follow_unit/data.follow_position so bot[i]
--   follows human[(i-1) % H + 1]: 2 humans + 2 bots -> host gets one, client the
--   other; 3 humans + 1 bot -> the lone bot follows the host. Stamping last every
--   frame also overrides the 20s stand-still re-targeting, so a bot stays on its
--   assigned human even when that human is idle.
--
-- COMPOSITION (confirmed against source)
--   follow_unit is the FOLLOW target ONLY; the aid/revive target is separate
--   (blackboard.target_ally_*, set in _select_ally_by_utility), so FIX 3/3b still
--   preempt follow in the BT -- a bot assigned to the client still breaks off to
--   revive the host, then returns. FIX 5 (ladder anchor, :243) and FIX 7 (leash,
--   :613) READ this same follow_unit, so they retarget to each bot's assigned
--   human; FIX 7's aid exception is intact. Host-side only (bot AI is
--   server-side); no RPC -- inert + crash-safe on clients.

-- Active HUMAN player units on a side, host first. Uses human_players() (NOT
-- side.PLAYER_UNITS, which also contains BOTS), filtered to this side + alive +
-- not vortex/disabled, so a bot is never assigned to follow another bot or an
-- incapacitated human.
local function _gt_split_humans_for_side(side, side_manager, host_unit)
    local active, disabled = {}, {}
    local pm = Managers.player
    local humans = pm and pm.human_players and pm:human_players()
    if not humans then return active end
    for _, player in pairs(humans) do
        local u = player and player.player_unit
        if u and Unit.alive(u) and side_manager.side_by_unit[u] == side then
            local st = ScriptUnit.has_extension(u, "status_system")
            if st and not st.near_vortex then
                if st:is_disabled() then
                    disabled[#disabled + 1] = u
                else
                    active[#active + 1] = u
                end
            end
        end
    end
    if #active == 0 then active = disabled end   -- all humans down? still cluster somewhere
    table.sort(active, function(a, b)
        if a == host_unit then return true end
        if b == host_unit then return false end
        return tostring(a) < tostring(b)   -- stable per-unit ordinal (spawned units lack a level_index)
    end)
    return active
end

-- v0.2.152-dev: resolve the new gt_bot_follow_mode dropdown. Falls back to the
-- legacy gt_bot_follow_host / gt_bot_split_among_players checkboxes on first
-- read so users with the old settings keep their behaviour (no forced reset).
-- Returns "default" | "follow_host" | "split".
local function _gt_resolve_follow_mode()
    local m = mod:get("gt_bot_follow_mode")
    if m == "follow_host" or m == "split" or m == "default" then return m end
    -- Legacy migration path (settings predate the dropdown).
    if mod:get("gt_bot_follow_host") then return "follow_host" end
    if mod:get("gt_bot_split_among_players") then return "split" end
    return "default"
end
mod._gt_resolve_follow_mode = _gt_resolve_follow_mode

-- Bot Teleport Lab F1/F5 follow-unit override pass. Runs AFTER any follow-mode
-- assignment (called at each exit of the hook below) so it is the FINAL word on
-- data.follow_unit. mod._gt_btlab_override_follow_unit is gated internally
-- (returns nil unless the lab master + F1/F5 are on), so this is a cheap no-op
-- when the lab is off. Never overrides a parked (hold_position) bot.
local function _gt_apply_btlab_follow_override(bot_ai_data)
    if not mod._gt_btlab_override_follow_unit then return end
    if type(bot_ai_data) ~= "table" then return end
    for bot_unit, data in pairs(bot_ai_data) do
        if data and not data.hold_position then
            local new_follow = mod._gt_btlab_override_follow_unit(bot_unit, data.follow_unit)
            if new_follow then
                data.follow_unit = new_follow
            end
        end
    end
end

-- Issue #139 diagnostics: call the lab only after every assignment layer has
-- composed, so its identity is the exact follow_unit the leash/action consumes.
local function _gt_trace_final_follow(bot_ai_data)
    if mod._gt_btlab_track_follow then
        mod._gt_btlab_track_follow(bot_ai_data)
    end
end

-- FIX A (issue 383) marker: the split fix now writes data.follow_position (a
-- vanilla-spacing fan point around the bot's OWN assigned human), not just
-- data.follow_unit. If a refactor drops the follow_position recompute this
-- disappears and gt_bot383_fix9_splits_follow_position fails.
GT_BOT383_FIX9_SPLIT_FOLLOW_POSITION_MARKER = "gt-bot383-fix9-split-follow-position"

-- nav_world accessor -- the same source vanilla's _update_move_targets reads
-- (ai_bot_group_system.lua:682). Guarded so a missing ai_system just yields nil
-- (the caller then leaves follow_position untouched for that bot).
local function _gt_bot_nav_world()
    local entity_mgr = Managers.state and Managers.state.entity
    local ai_system = entity_mgr and entity_mgr:system("ai_system")
    return ai_system and ai_system:nav_world()
end

-- FIX A (issue 383): compute `needed` navmesh-valid destination points fanned
-- around `unit`, EXACTLY the way vanilla fans points around its single
-- selected_unit (ai_bot_group_system.lua:780-791, and the per-human man-man
-- branch :744-755). Reused per split human so a bot reassigned off vanilla's
-- selected_unit stands NEAR its OWN human with the same spread the engine uses,
-- never ON it. pcall-wrapped: the GwNav* queries are engine calls, and the
-- contract is that ANY failure (nil position, bad navmesh) returns nil so the
-- caller leaves the bot's vanilla follow_position intact rather than stamping the
-- raw player position (which crowded the human / blocked their shots -- the
-- gt_dev too-close report). Returns the points array (always `needed` long,
-- vanilla pads short results with the origin point), or nil on failure.
local function _gt_fan_points_for_unit(system, nav_world, unit, needed)
    -- Cheap guards first (so the /gt_regression_test can exercise the nil-return
    -- fallback contract without a POSITION_LOOKUP entry for a stub unit).
    if not (system and nav_world and unit and needed and needed > 0) then
        return nil
    end
    local unit_pos = POSITION_LOOKUP[unit]
    if not unit_pos then
        return nil
    end
    local ok, points = pcall(function ()
        local disallowed_at_pos, current_mapping =
            system:_selected_unit_is_in_disallowed_nav_tag_volume(nav_world, unit_pos)
        if disallowed_at_pos then
            local origin_point = system:_find_origin(nav_world, unit)
            return system:_find_destination_points_outside_volume(nav_world, unit_pos, current_mapping, origin_point, needed)
        end
        local cluster_position, rotation = system:_find_cluster_position(nav_world, unit)
        return system:_find_destination_points(nav_world, cluster_position, rotation, needed)
    end)
    if ok and type(points) == "table" and #points > 0 then
        return points
    end
    return nil
end
mod._gt_fan_points_for_unit = _gt_fan_points_for_unit

mod:hook_safe("AIBotGroupSystem", "_assign_destination_points", function (self, bot_ai_data) -- luacheck: ignore self
    -- Bot Teleport Lab D2 is merged into this singleton pair. It dispatches at
    -- each FINAL exit below (after vanilla + orders + follow mode + lab override),
    -- never here at the pre-override top; the old placement logged the wrong copy.

    -- Issue #359 temporary bot orders share this singleton post-assignment seam.
    -- Cover/Group Up must run after vanilla writes destinations and before the
    -- persistent follow-mode options below; a true result gives the explicit,
    -- time-bounded player order precedence for this tick.
    if mod._gt359_apply_follow_override
            and mod._gt359_apply_follow_override(self, bot_ai_data) then
        _gt_trace_final_follow(bot_ai_data)
        return
    end

    local mode = _gt_resolve_follow_mode()
    local follow_host = (mode == "follow_host")
    if mode == "default" then
        -- Lab F1/F5 still get to re-point follow_unit off vanilla's assignment.
        _gt_apply_btlab_follow_override(bot_ai_data)
        _gt_trace_final_follow(bot_ai_data)
        return
    end
    if type(bot_ai_data) ~= "table" then
        _gt_trace_final_follow(bot_ai_data)
        return
    end

    local side_manager = Managers.state and Managers.state.side
    local pm = Managers.player
    if not (side_manager and pm) then
        _gt_trace_final_follow(bot_ai_data)
        return
    end

    local probe = next(bot_ai_data)
    if not probe then
        _gt_trace_final_follow(bot_ai_data)
        return
    end
    local side = side_manager.side_by_unit[probe]
    if not side then
        _gt_trace_final_follow(bot_ai_data)
        return
    end

    local host = pm.local_player and pm:local_player()
    local host_unit = host and host.player_unit

    -- "Bots always follow host" takes PRECEDENCE over "split among players" when
    -- both are on (they're opposite strategies; precedence avoids a VMF mutex whose
    -- checkbox wouldn't visually refresh -- see reference_vmf_checkbox_cached_display_state).
    -- All bots leash to the host; set ONLY follow_unit and leave vanilla's fanned-out
    -- follow_position (the spread distance) intact. When the host IS vanilla's
    -- selected_unit that fan is already correct; when it is not, follow-host carries
    -- the same residual issue-383 offset the split branch now corrects below
    -- (deliberately out of scope here -- issue 383 targets FIX 9 / split). Not
    -- stamping POSITION_LOOKUP[host] keeps bots off the host's shot line either way.
    if follow_host then
        if not (host_unit and HEALTH_ALIVE[host_unit]) then
            _gt_trace_final_follow(bot_ai_data)
            return
        end   -- host dead/unit-less: leave vanilla
        local n = 0
        for _, data in pairs(bot_ai_data) do
            if data and not data.hold_position then
                data.follow_unit = host_unit
                n = n + 1
            end
        end
        do
            local t = (Managers.time and Managers.time:time("game")) or 0
            if t >= (self._gt_followhost_log_t or 0) then
                self._gt_followhost_log_t = t + 3.0
                mod:debug("[gt:bot-follow-host] %d bots leashed to host", n)
            end
        end
        -- Lab F1/F5 override runs LAST (after the follow-host assignment).
        _gt_apply_btlab_follow_override(bot_ai_data)
        _gt_trace_final_follow(bot_ai_data)
        return
    end

    local humans = _gt_split_humans_for_side(side, side_manager, host_unit)
    local num = #humans
    if num == 0 then
        _gt_trace_final_follow(bot_ai_data)
        return
    end

    -- Deterministic bot order so bot[i] -> human[i] is stable frame-to-frame.
    local bots = {}
    for bot_unit in pairs(bot_ai_data) do bots[#bots + 1] = bot_unit end
    table.sort(bots, function(a, b) return tostring(a) < tostring(b) end)

    -- Group the bots we move OFF vanilla's single selected_unit; each such bot
    -- needs a fresh follow_position fanned around ITS human (issue 383). Bots left
    -- on vanilla's selected_unit keep vanilla's already-correct fan point.
    local fan_groups   -- human_unit -> { bot_unit, ... }, lazily created
    for i = 1, #bots do
        local data = bot_ai_data[bots[i]]
        -- Don't override a parked (hold-position) bot (vanilla already set its
        -- follow_position = hold_position:unbox() and follow_unit = nil).
        if data and not data.hold_position then
            local human = humans[(i - 1) % num + 1]
            if HEALTH_ALIVE[human] then   -- re-validate: don't strand on a just-died target
                -- FIX A (issue 383): vanilla wrote data.follow_unit = selected_unit
                -- (one human) and data.follow_position = a fan point around THAT
                -- human for every bot. Re-pointing only follow_unit left the bot
                -- standing near the wrong human. Capture vanilla's assignment; if we
                -- move the bot to a DIFFERENT human, queue it for a fan-point
                -- recompute around its new human. If it stays on vanilla's human,
                -- leave follow_position untouched (already the right fan point).
                local vanilla_follow = data.follow_unit
                data.follow_unit = human
                if human ~= vanilla_follow then
                    fan_groups = fan_groups or {}
                    local g = fan_groups[human]
                    if not g then
                        g = {}
                        fan_groups[human] = g
                    end
                    g[#g + 1] = bots[i]
                end
            end
        end
    end

    -- FIX A (issue 383): fan each reassigned human's bots around that human with
    -- the SAME spacing vanilla uses for its single selected_unit, so split bots
    -- stand NEAR their assigned human (never ON them, the old too-close report).
    -- Per-human fan sized to the group so two bots on one human still spread out.
    -- On any nav failure the bot keeps vanilla's fanned point (no player-stomp).
    if fan_groups then
        local nav_world = _gt_bot_nav_world()
        if nav_world then
            for human, group in pairs(fan_groups) do
                local points = _gt_fan_points_for_unit(self, nav_world, human, #group)
                if points then
                    for k = 1, #group do
                        local p = points[k]
                        if p then
                            bot_ai_data[group[k]].follow_position = p
                        end
                    end
                end
            end
        end
    end

    do
        local t = (Managers.time and Managers.time:time("game")) or 0
        if t >= (self._gt_split_log_t or 0) then
            self._gt_split_log_t = t + 3.0
            mod:debug("[gt:bot-split] %d bots across %d humans (host-first round-robin)", #bots, num)
            -- #261: mirror the split round-robin summary to printf in dev so it is
            -- visible with mod logging OFF (mod:debug is not). No-op in stable.
            if mod._gt_btlab_pf_dev then
                mod._gt_btlab_pf_dev("[gt:bot-split] %d bots across %d humans (host-first round-robin)", #bots, num)
            end
        end
    end

    -- Lab F1/F5 override runs LAST (after the split round-robin assignment).
    _gt_apply_btlab_follow_override(bot_ai_data)
    _gt_trace_final_follow(bot_ai_data)
end)

-- ----------------------------------------------------------------------------
-- REPLICANT BOTS PORT 3: Announce when a bot's guard breaks
-- ----------------------------------------------------------------------------
-- Ported from DifferentBots.lua:2443-2472. When a BOT teammate's block is
-- broken, post a chat line so the human knows. Scope dropdown:
--   "none"   -> disabled
--   "host"   -> local system message on the host only (add_local_system_message)
--   "global" -> broadcast to the whole lobby (send_chat_message)
-- Bots are host-only, so this hook only ever fires on the host. set_block_broken
-- early-returns in vanilla when the value is unchanged (generic_status_extension
-- .lua:994-996), so we only message on the rising edge (was not broken, now is).
-- mod:hook (full wrapper) so we can read self.block_broken BEFORE vanilla flips
-- it. New (Class, method) pair: the only other gt hook on GenericStatusExtension
-- is `update_falling` in general_tweaker_dev.lua -- a different method, no dup.
mod:hook("GenericStatusExtension", "set_block_broken", function (func, self, block_broken, t, attacker_unit)
    local scope = mod:get("gt_bot_guard_break_msg")
    -- Rising edge only: was unbroken, now breaking.
    if scope and scope ~= "none" and block_broken and not self.block_broken then
        local unit = self.unit
        local owner = unit and Managers.player and Managers.player:unit_owner(unit)
        if owner and owner.bot_player then
            local line = mod:localize("gt_bot_guard_break_chat")
            if line and line ~= "" then
                if scope == "global" and Managers.chat and Managers.chat.send_chat_message then
                    local host = Managers.player:local_player()
                    local lpid = host and host:local_player_id()
                    if lpid then
                        -- channel 1, host as sender, message already localized (localize=false).
                        Managers.chat:send_chat_message(1, lpid, line, false)
                    end
                elseif Managers.chat and Managers.chat.add_local_system_message then
                    -- "host" scope (and global fallback): local system message.
                    Managers.chat:add_local_system_message(1, line, false)
                end
            end
        end
    end

    return func(self, block_broken, t, attacker_unit)
end)

-- ----------------------------------------------------------------------------
-- FIX 11 (issue 448, SOFT-LOCK): downed bots must not grant Morr's Protection
-- ----------------------------------------------------------------------------
-- WHAT
--   The Chaos Wastes boon "Morr's Protection" (deus_knockdown_damage_immunity_aura,
--   deus_power_up_settings.lua:2371-2392; display name per the ct boon loc dump)
--   is a server-authority aura: every buff-update tick the CARRIER grants
--   deus_knockdown_damage_immunity_buff -- perk `invulnerable`, NO duration
--   (deus_power_up_settings.lua:175-190) -- to every KNOCKED-DOWN ally within
--   10m, and removes it again when the target leaves range / stands up / the
--   carrier is dead awaiting rescue (deus_knockdown_damage_immunity_aura_func,
--   morris_buff_settings.lua:872-921). The carrier's OWN knocked-down state is
--   never checked: :887 gates only on is_ready_for_assisted_respawn(), so a
--   DOWNED carrier keeps projecting the aura. Two boon-carrying bots downed
--   within 10m of each other therefore make each other PERMANENTLY invulnerable
--   (the perk also blocks the knockdown_bleed DoT, so they never bleed out,
--   enemies can never finish them, and the run soft-locks -- issue 448).
--
-- FIX
--   Wrap BuffFunctionTemplates.functions.deus_knockdown_damage_immunity_aura_func.
--   The buff extension resolves update_func from that table DYNAMICALLY on every
--   tick (buff_extension.lua:794), so the table-form hook intercepts every aura
--   tick -- same shipped pattern as this mod's apply_huntsman_activated_ability
--   hook (_gt_solo_qol.lua:497) and ct's three BuffFunctionTemplates hooks.
--   While the aura OWNER is a BOT and knocked down: skip the vanilla grant tick
--   entirely and strip any immunity buff THIS owner granted. The strip mirrors
--   vanilla's own removal path (get_non_stacking_buff + buff.server_id +
--   remove_server_controlled_buff, morris_buff_settings.lua:900-908) but is
--   additionally gated on buff.attacker_unit == owner (the grant source, stored
--   via buff_system.lua:244 -> buff_extension.lua:615), so a STANDING carrier's
--   aura on the same downed target is left alone.
--
--   SCOPE: humans (downed or not) keep exact vanilla behavior -- the wrapper
--   passes straight through unless the owner is a bot AND knocked down. Standing
--   bot carriers also pass through. Server-side only by construction: the
--   vanilla func early-outs on non-server (morris_buff_settings.lua:873) and
--   bots exist host-side only; the strip uses a vanilla API on a vanilla buff,
--   so nothing modded touches the wire. Grants resume the moment the bot is
--   revived (next aura tick passes through).
--
--   TOGGLE: gt_bot_no_downed_morrs_grant, independent + default ON. Independent
--   (not nested under the default-OFF Bot Options master) because a 0-critical
--   soft-lock fix must be live by default; a toggle at all (rather than FIX 0's
--   unconditional pattern) because this changes a boon's gameplay behavior, not
--   crash safety. Default ON because the reported behavior IS the bug (same
--   rationale as gt_bot_ignore_backward_gate).
GT_BOT_DOWNED_MORRS_MARKER_v0_2_197 = "gt-448-downed-bot-no-morrs-grant"

-- [owner_unit] = true while that bot's aura is being suppressed. Latches the
-- [gt:448] printf to once per downed episode (the aura ticks every frame);
-- cleared on any pass-through tick (bot revived / toggle off).
local _gt448_suppressed = {}

if BuffFunctionTemplates and BuffFunctionTemplates.functions
   and BuffFunctionTemplates.functions.deus_knockdown_damage_immunity_aura_func then
    -- Singleton: the only other BuffFunctionTemplates hook in gt_dev targets
    -- apply_huntsman_activated_ability (_gt_solo_qol.lua:497) -- different key.
    mod:hook(BuffFunctionTemplates.functions, "deus_knockdown_damage_immunity_aura_func", function (func, owner_unit, buff, params, world)
        local suppress = false
        if mod:get("gt_bot_no_downed_morrs_grant")
           and Managers.state and Managers.state.network and Managers.state.network.is_server
           and ALIVE[owner_unit] then
            local player = Managers.player and Managers.player:owner(owner_unit)
            if player and player.bot_player and ScriptUnit.has_extension(owner_unit, "status_system") then
                local status_ext = ScriptUnit.extension(owner_unit, "status_system")
                suppress = status_ext.is_knocked_down and status_ext:is_knocked_down() or false
            end
        end

        if not suppress then
            if _gt448_suppressed[owner_unit] then
                _gt448_suppressed[owner_unit] = nil
            end
            return func(owner_unit, buff, params, world)
        end

        -- Downed BOT carrier: grant nothing this tick; strip what THIS carrier
        -- already granted (e.g. it protected a downed ally while still standing,
        -- then went down itself). Idempotent, at most 3 other units per side.
        local stripped = 0
        local side = Managers.state.side and Managers.state.side.side_by_unit[owner_unit]
        local units = side and side.PLAYER_AND_BOT_UNITS
        local buff_system = Managers.state.entity and Managers.state.entity:system("buff_system")
        local buff_to_add = (buff.template and buff.template.buff_to_add) or "deus_knockdown_damage_immunity_buff"
        if units and buff_system then
            for i = 1, #units do
                local unit = units[i]
                if unit ~= owner_unit and ALIVE[unit] and ScriptUnit.has_extension(unit, "buff_system") then
                    local target_buff_ext = ScriptUnit.extension(unit, "buff_system")
                    local granted = target_buff_ext:get_non_stacking_buff(buff_to_add)
                    if granted and granted.attacker_unit == owner_unit and granted.server_id then
                        buff_system:remove_server_controlled_buff(unit, granted.server_id)
                        stripped = stripped + 1
                    end
                end
            end
        end

        if not _gt448_suppressed[owner_unit] then
            _gt448_suppressed[owner_unit] = true
            pcall(printf, "[gt:448] downed bot carrier: Morr's Protection aura grant suppressed (stripped %d self-granted buff(s))", stripped)
        end
        -- Deliberately NOT calling func: the vanilla tick would re-grant the
        -- invulnerable perk to every knocked-down ally within 10m (:911-918).
    end)
else
    -- Load-order surprise (merged morris settings absent): fix is NOT armed.
    pcall(printf, "[gt:448] deus_knockdown_damage_immunity_aura_func not in BuffFunctionTemplates.functions at mod load - downed-bot Morr's grant fix NOT armed")
end

-- Boot-time apply: on_setting_changed doesn't fire at load, so if the user
-- already had Faster bot reactions ON, apply it now (BotConstants is a settings
-- global populated at engine boot, before mods load). Snapshots vanilla first.
if mod:get("gt_bot_fast_reactions") then
    _gt_apply_fast_reactions()
end
