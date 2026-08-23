-- _gt_bot_aid_owner.lua - host-side bot aid selection and pursuit lifecycle.
--
-- Owns the existing Ironbreaker revive yield, human heal targeting, assisted-
-- respawn selection, aid-errand pinning, and bounded stalled-pursuit recovery.
-- The installer receives the exact entry-point locals it closes over, validates
-- its callable dependency before installing either hook, and returns only the
-- predicates consumed by the later teleport owner.
--
-- Owned by: _gt_bot_fixes.lua. Consumed via: one ordered mod:dofile installer.

return function(context)
    if type(context) ~= "table" then
        error("gt bot aid owner requires a context table")
    end
    if type(context.ignore_backward_gate_on) ~= "function" then
        error("gt bot aid owner requires ignore_backward_gate_on")
    end

    local mod = context.mod
    if type(mod) ~= "table" then
        error("gt bot aid owner requires mod")
    end
    if type(mod.hook) ~= "function" then
        error("gt bot aid owner requires mod.hook")
    end
    if mod._gt_bot_aid_owner_installed then
        error("gt bot aid owner is already installed")
    end

    local required_table_names = {
        "ScriptUnit",
        "POSITION_LOOKUP",
        "HEALTH_ALIVE",
        "Vector3",
        "Unit",
        "Managers",
        "ALIVE",
    }
    for _, name in ipairs(required_table_names) do
        if type(context[name]) ~= "table" then
            error("gt bot aid owner requires " .. name)
        end
    end

    local ScriptUnit = context.ScriptUnit
    local POSITION_LOOKUP = context.POSITION_LOOKUP
    local HEALTH_ALIVE = context.HEALTH_ALIVE
    local Vector3 = context.Vector3
    local Unit = context.Unit
    local Managers = context.Managers
    local ALIVE = context.ALIVE
    local _gt_ignore_backward_gate_on = context.ignore_backward_gate_on

    -- Explicit installer-scope declarations keep every callback bound to this
    -- owner under Lua 5.1 lexical rules and the strict forward-reference gate.
    local _gt_heal_allies_on
    local _gt_pick_human_heal_target
    local _gt384_aid_priority_on
    local _gt384_label
    local _gt384_arm_pin
    local _gt384_clear_pin
    local _gt384_hold_pin
    local _gt384_pin_live
-- ----------------------------------------------------------------------------
-- FIX 2: Ironbreaker bot won't revive while its ult/ability is active
-- ----------------------------------------------------------------------------
-- WHAT
--   The Ironbreaker bot ult (player_bots_settings.lua use_ability.dr_ironbreaker)
--   has a `wait_action = { input = "defend" }` and an `end_condition` tied to
--   the `bardin_ironbreaker_activated_ability` buff (lines ~118-130). So after
--   popping the ult the bot HOLDS the ability action (blocking) for the full
--   buff duration. While that ability action runs,
--   BTConditions.can_activate_ability (bt_bot_conditions.lua:607-629) returns
--   true via the `is_using_ability` short-circuit (line 628), so the bot's
--   behaviour-tree selector stays parked on the ability node and never re-enters
--   the higher-priority revive node (bt_bot.lua:14-32). Net effect: a downed
--   ally is ignored for the whole ult duration.
--
-- FIX
--   When an ally actually needs aid, make can_activate_ability return false for
--   an Ironbreaker that is mid-ult, so the ability node yields and the revive
--   node runs. The ult is a timed BUFF applied by _run_ability
--   (career_ability_dr_ironbreaker.lua) -- it KEEPS ticking for its duration; we
--   only stop the bot from standing around blocking. The ability is on cooldown
--   after use, so can_use_activated_ability() is false and the bot won't re-pop
--   it -- it just fights/revives normally with the damage-reduction buff up.
mod:hook("BTConditions", "can_activate_ability", function (func, blackboard, args)
    local result = func(blackboard, args)

    if not result then
        return result
    end

    -- v0.2.128-dev: bundled (was gt_bot_ironbreaker_revive_in_ult); #297
    -- (v0.2.182-dev): master AND its own sub-toggle again.
    if not (mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_ironbreaker_revive_in_ult")) then
        return result
    end

    local career_extension = blackboard.career_extension
    if not career_extension or career_extension:career_name() ~= "dr_ironbreaker" then
        return result
    end

    local ability_data = blackboard.activate_ability_data
    if not (ability_data and ability_data.is_using_ability) then
        return result
    end

    -- Only yield the ult-hold for a genuine aid need (revive / ledge / hook;
    -- "knocked_down" also covers awaiting-respawn relabeled by FIX 3 below).
    if blackboard.target_ally_needs_aid then
        local need_type = blackboard.target_ally_need_type
        if need_type == "knocked_down" or need_type == "ledge" or need_type == "hook" then
            mod:debug("[gt:bot-ib] yielding Ironbreaker ult-hold to aid ally (need=%s)", tostring(need_type))
            return false
        end
    end

    return result
end)

-- ----------------------------------------------------------------------------
-- FIX 13 (#523, v0.2.207-dev): Bots actively heal hurt HUMAN allies
-- ----------------------------------------------------------------------------
-- WHY (this CORRECTS the FIX 12 / #468 note below)
--   The self-heal note in FIX 12 asserts "the game has no bot heal-other action".
--   That is only half true: BTBotHealAction (bt_bot_heal_action.lua) is self-heal
--   only, but a SEPARATE vanilla node ALREADY channel-heals an ALLY --
--     bt_bot.lua:87-93 "heal_other": a BTBotInteractAction driven by
--     BotActions.default.use_heal_on_player (player_bots_settings.lua:94-97,
--     {aim_node="j_head", input="charge_shot"}), gated by
--     BTConditions.can_heal_player (bt_bot_conditions.lua:773-807).
--   The whole navigation + interaction + heal-apply chain is present and working:
--   the caller sets target_ally_needs_aid / interaction_unit / aid destination for
--   an "in_need_of_heal" need type (player_bot_base.lua:710-720, :1595-1599), then
--   the node runs the SAME interaction a human uses, so the heal amount, item
--   consumption, wound removal and networking are all vanilla-native
--   (interactions.lua:1788 DamageUtils.heal_network heal_type "bandage";
--   attack_templates.lua:403 heal_percent 0.8 = 80%% of missing health; the wound
--   is removed via StatusUtils.set_wounded_network, damage_utils.lua:2545).
--
--   The reason bots "never" heal allies is the SELECTION gate, NOT a missing
--   action. _select_ally_by_utility only labels an ally "in_need_of_heal" when its
--   PERMANENT health < WANTS_TO_HEAL_THRESHOLD (0.25) OR it is wounded, AND the bot
--   values healing them over itself (self_health_utiliy < health_utility, with
--   SELF_HEAL_STICKINESS baked into self_health_utiliy -- player_bot_base.lua:868,
--   :932, :935), AND the bot carries a can_heal_other kit. So a bot almost always
--   keeps its kit and the heal_other node stays dormant.
--
-- SHAPE (widen the dormant vanilla node -- NOT a BT graft, NOT host-side steering)
--   The tree is compiled ONCE at load from BotBehaviors.default via
--   BehaviorTree:new (ai_system.lua:1702-1703); the heal_other node is already in
--   it. So neither a runtime graft nor a hand-rolled steer/interact is needed -- we
--   just relax the SELECTION gate from inside gt's EXISTING _select_ally_by_utility
--   hook. Under a new default-OFF toggle, and only when nothing more urgent was
--   picked, relabel the neediest reachable HUMAN "in_need_of_heal"; the vanilla
--   pipeline then paths the bot in and channels the native heal. Target selection
--   per #523: wounded (grey health) first, else lowest permanent-health human,
--   within HEAL_ALLY_MAX_DIST and path-reachable. Host-side only (bot AI is
--   server-owned); no RPC / NetworkLookup, so no non-host peer can crash or desync.
--
-- COMPOSES WITH #468: a bot that RESERVES its kit
--   (gt_bot_reserve_kits_for_players, FIX 12) is exactly the carrier this feature
--   spends -- reserve stops the bot self-burning Medical Supplies, heal-allies
--   walks that kit to a hurt human. Works best with reserve ON; does not require it.
-- RISK: heal-other outranks nothing here -- it is injected LAST, only when vanilla
--   AND FIX 3/3b picked no revive/rescue/heal (need_type nil or attention-only), so
--   it can never delay a revive or rescue.
local HEAL_ALLY_MAX_DIST = 20
local HEAL_ALLY_MAX_DIST_SQ = HEAL_ALLY_MAX_DIST * HEAL_ALLY_MAX_DIST

_gt_heal_allies_on = function()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_heal_allies")
end
mod._gt_heal_allies_on = _gt_heal_allies_on

-- Pick the neediest reachable HUMAN ally for a heal-other channel, or nil.
-- Mirrors vanilla's permanent-health metric (player_bot_base.lua:926), but
-- replaces its fixed 25% / Zealot selection policy with the issue #523 controls
-- and DROPS only the self-vs-other utility bias that normally suppresses the pick.
-- BTConditions.can_heal_player remains the final native safety gate
-- (bt_bot_conditions.lua:773-807). Disabled / awaiting-respawn allies are a
-- revive/rescue case, not a heal case, and are skipped so heal-other never competes
-- with aid. Returns (unit, real_dist, permanent_health_percent, wounded).
_gt_pick_human_heal_target = function(self, unit, roster, self_pos, t)
    local blackboard = self._blackboard
    local inventory_extension = blackboard and blackboard.inventory_extension
    if not (inventory_extension and self_pos and roster) then return nil end

    local health_slot_data = inventory_extension:get_slot_data("slot_healthkit")
    local template = health_slot_data and inventory_extension:get_item_template(health_slot_data)
    if not (template and template.can_heal_other) then return nil end

    local policy = mod._gt_bot_heal_policy
    if not (policy and policy.is_eligible) then return nil end
    local options = {
        regular_percent = mod:get("gt_bot_heal_allies_pct"),
        wounded_percent = mod:get("gt_bot_heal_wounded_allies_pct"),
        exclude_zealot = mod:get("gt_bot_heal_allies_exclude_zealot"),
        heal_wounded_zealot = mod:get("gt_bot_heal_wounded_zealot"),
    }

    local player_manager = Managers.player
    local best_unit, best_dist_sq, best_health, best_wounded

    for k = 1, #roster do
        local pu = roster[k]
        if pu ~= unit and HEALTH_ALIVE[pu] then
            local owner = player_manager and player_manager:owner(pu)
            local status_ext = owner and owner:is_player_controlled()
                and ScriptUnit.has_extension(pu, "status_system")
            if status_ext and not status_ext:is_disabled()
                    and not status_ext:is_ready_for_assisted_respawn()
                    and not status_ext.near_vortex then
                local health_ext = ScriptUnit.has_extension(pu, "health_system")
                local career_ext = ScriptUnit.has_extension(pu, "career_system")
                if health_ext then
                    local wounded = status_ext:is_wounded()
                    local health_percent = health_ext:current_permanent_health_percent()
                    local is_zealot = career_ext and career_ext:career_name() == "wh_zealot"
                    if policy.is_eligible(health_percent, wounded, is_zealot, options) then
                        local cand_pos = POSITION_LOOKUP[pu]
                        local dist_sq = cand_pos and Vector3.distance_squared(self_pos, cand_pos)
                        if dist_sq and dist_sq <= HEAL_ALLY_MAX_DIST_SQ then
                            local _, allowed_aid_path = self:_ally_path_allowed(unit, pu, t)
                            if allowed_aid_path then
                                -- Rank: wounded first, then lowest permanent health,
                                -- then closest (#523 "lowest-HP human, wounded first").
                                local better = not best_unit
                                if best_unit and not better then
                                    if wounded ~= best_wounded then
                                        better = wounded
                                    elseif health_percent ~= best_health then
                                        better = health_percent < best_health
                                    else
                                        better = dist_sq < (best_dist_sq or math.huge)
                                    end
                                end
                                if better then
                                    best_unit, best_dist_sq = pu, dist_sq
                                    best_health, best_wounded = health_percent, wounded
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if best_unit then
        return best_unit, math.sqrt(best_dist_sq), best_health, best_wounded
    end
end
mod._gt_pick_human_heal_target = _gt_pick_human_heal_target

-- ----------------------------------------------------------------------------
-- FIX 3: Bots don't rescue allies awaiting (assisted) respawn
-- ----------------------------------------------------------------------------
-- WHAT
--   PlayerBotBase._select_ally_by_utility (player_bot_base.lua:843-1008) is the
--   bot's ally-aid picker. Line 903 explicitly EXCLUDES any ally for whom
--   status_ext:is_ready_for_assisted_respawn() is true from the entire aid
--   evaluation, and no aid branch handles that state. So bots never go free a
--   teammate who is waiting to be rescued at a respawn point -- including after
--   the bot itself respawns and re-evaluates targets.
--
-- FIX
--   Wrap the picker. After the vanilla call, if it found no higher-priority aid
--   and the toggle is on, scan for an ally who IS ready for assisted respawn and
--   reachable, and return it labelled "knocked_down". The bot's revive branch
--   (bt_bot.lua:14-32, condition can_revive) then drives navigation + the
--   interact action. Crucially the revive bot-action has NO forced `input`
--   (player_bots_settings.lua revive = { aim_node="j_head", use_block_interaction
--   =true }), so bt_bot_interact_action.lua:71 fires the CONTEXTUAL interaction,
--   which the engine resolves to `assisted_respawn` on an awaiting-rescue ally
--   (interactions.lua:562, gated on is_ready_for_assisted_respawn). can_revive
--   (bt_bot_conditions.lua:735-766) accepts the relabel: it keys on need_type
--   == "knocked_down" + interaction safety, and the awaiting ally's health is 0
--   so the threat-gate (health > 0.3) is skipped.
--
--   This wrapper calls the original first, so it composes with other bot mods
--   that also hook _select_ally_by_utility. It only ADDS a target when vanilla
--   found nothing more urgent.
--
-- RANGE POLICY (#300)
--   Vanilla's own follow teleport gate is 40 m (1600 squared meters) in
--   BTConditions.should_teleport (bt_bot_conditions.lua:14,451-480). Keep the
--   historical unlimited rescue behavior by default, but let the host bound
--   this injected candidate scan either to gt's active follow-leash setting or
--   to a dedicated 10-100 m override. Filtering here, before the relabel, keeps
--   the native navigation/interaction path intact and needs no additional hook.
mod._gt_rescue_awaiting_distance_cap = function(ignore_leash, custom_range_enabled, custom_range_m, follow_range_m)
    if ignore_leash then
        return nil
    end

    local custom = custom_range_enabled and true or false
    local value = tonumber(custom and custom_range_m or follow_range_m) or 40.0
    local maximum = custom and 100.0 or 40.0
    return math.max(10.0, math.min(maximum, value))
end

mod._gt_rescue_awaiting_within_cap = function(distance_m, cap_m)
    return cap_m == nil or (type(distance_m) == "number" and distance_m <= cap_m)
end
mod.GT_BOT300_RESCUE_RANGE_POLICY_MARKER_v0_2_221 = true

-- ----------------------------------------------------------------------------
-- #384 AID-ERRAND PIN (v0.2.250-dev): hold the errand across need_type flicker
-- ----------------------------------------------------------------------------
-- WHAT
--   Vanilla's picker drops a downed ally from the aid evaluation whenever
--   _ally_path_allowed is inside a failed-path cooldown -- the candidate is
--   skipped outright when the follow path is disallowed, or its in_need_type is
--   nil'd when only the aid path is disallowed (player_bot_base.lua:960-964;
--   cooldowns 1 s ahead / 5-10 s behind / 3-12 s distance-scaled,
--   player_bot_base.lua:1948-1983). _update_target_ally then clears
--   target_ally_needs_aid/target_ally_need_type (:721-724), which breaks BOTH
--   the revive errand (can_revive keys on need_type, bt_bot_conditions.lua:738)
--   AND every distance-teleport aid exception (vanilla :1226-1228 and gt's
--   tighter leash) for the cooldown window.
-- EVIDENCE (issue 384 + the 2026-07-18 log sweep of gt 0.2.248)
--   console-2026-07-06: both bots assigned to downed Rain; Markus teleported to
--   the standing human 3x starting ~2 s after the aid flag cleared, VETOED=0.
--   gt 0.2.248 session logs (FS 22.26/01.48): 410x "[gt_bot:139] TELEPORT
--   executed"; "[gt:139:chain] VETO bot=Sienna reason=tighter_leash" followed
--   0.02 s later by "TELEPORT ... veto_age=0.02s same_aid=false" -- the veto did
--   not hold; and "[gt:492] ... BAILED aid pursuit (reason=no-progress)"
--   released the veto in the same chain while the ally was still down.
-- FIX
--   Pin the errand per bot: whenever the picker hands _update_target_ally a
--   real aid pick (knocked_down / ledge / hook, incl. the FIX 3 awaiting-rescue
--   relabel and the FIX 3b force pick), remember (ally, need). On any later
--   tick where the wrapped chain produced NO aid pick while the pinned ally
--   STILL classifies (live status via policy.pin_need_type -- path cooldowns
--   cannot flicker it), re-return the pinned ally with its live need type. That
--   keeps target_ally_need_type continuously set, so vanilla's own aid
--   exception and gt's tighter leash decline the teleport at the source and the
--   #139 veto becomes the backstop instead of the sole gate.
-- RELEASE (state-based, no wall-clock -- BUG_CLASSES 34)
--   * ally no longer classifies (revived / rescued / dead with no awaiting
--     relabel) -> release;
--   * #492 bail with reason "no-path" on the pinned ally (the engine's own aid
--     pathing keeps failing -> authoritative unreachable) -> release;
--   * #492 bail with reason "no-progress" -> HOLD (per the log evidence above a
--     no-progress stall with a live errand is combat holding the bot, not
--     unreachability; genuine unreachability surfaces as failing paths).
--   The pin deliberately bypasses the FIX 3 range cap once armed: the errand
--   was legitimately acquired, and an unreachable target releases via no-path.
-- Host-side only (bot AI is server-owned); no RPC, no wire surface. All pin
-- state lives on the bot's own blackboard. Runtime deps are read through the
-- mod table (call-time) because this block precedes their definitions.
GT_BOT384_AID_ERRAND_PIN_MARKER_v0_2_250 = "gt-bot384-aid-errand-pin-holds-veto"

_gt384_aid_priority_on = function()
    local fn = mod._gt_aid_priority_on
    return fn and fn() and true or false
end

_gt384_label = function(u)
    local fn = mod._gt492_label
    if fn then return fn(u) end
    return tostring(u)
end

-- Arm/refresh the pin on every real aid pick. Clears the held-episode printf
-- latch so each later flicker episode logs exactly once.
_gt384_arm_pin = function(blackboard, ally, need_type)
    if not _gt384_aid_priority_on() then
        return
    end
    if blackboard._gt384_pin_unit ~= ally and rawget(_G, "printf") then
        printf("[gt:384:pin] ARMED bot=%s ally=%s need=%s",
            _gt384_label(blackboard.unit), _gt384_label(ally), tostring(need_type))
    end
    blackboard._gt384_pin_unit = ally
    blackboard._gt384_pin_need = need_type
    blackboard._gt384_pin_held_latch = nil
end

_gt384_clear_pin = function(blackboard)
    blackboard._gt384_pin_unit = nil
    blackboard._gt384_pin_need = nil
    blackboard._gt384_pin_held_latch = nil
end

-- Hold check: returns (unit, dist, need) to substitute as this tick's pick, or
-- nil (no pin / released / positions transiently missing). Pure decision rides
-- policy.pin_need_type + policy.pin_should_release (_gt_teleport_loop_policy).
_gt384_hold_pin = function(blackboard, self_pos, rescue_awaiting_active)
    local pin_unit = blackboard._gt384_pin_unit
    if not pin_unit then
        return nil
    end
    if not _gt384_aid_priority_on() then
        _gt384_clear_pin(blackboard)
        return nil
    end
    local policy = mod._gt_teleport_loop_policy
    if not (policy and policy.pin_need_type and policy.pin_should_release) then
        return nil   -- policy unavailable: degrade to pre-pin (shipped) behavior
    end

    local pin_need
    if ALIVE[pin_unit] then
        local st = ScriptUnit.has_extension(pin_unit, "status_system")
        -- Awaiting-rescue relabel mirrors FIX 3's pick gates exactly: feature
        -- toggle on AND the awaiting unit is health-alive.
        local allow_awaiting = rescue_awaiting_active and HEALTH_ALIVE[pin_unit] and true or false
        pin_need = st and policy.pin_need_type(st, allow_awaiting) or nil
    end

    local bail_active = blackboard._gt492_bailout and true or false
    local bail_is_pin = bail_active and blackboard._gt492_bailout_unit == pin_unit
    local release, why = policy.pin_should_release(
        pin_need, bail_active, blackboard._gt492_bailout_reason, bail_is_pin)
    if release then
        if rawget(_G, "printf") then
            printf("[gt:384:pin] RELEASED bot=%s ally=%s reason=%s",
                _gt384_label(blackboard.unit), _gt384_label(pin_unit), tostring(why))
        end
        _gt384_clear_pin(blackboard)
        return nil
    end

    blackboard._gt384_pin_need = pin_need
    local cpos = POSITION_LOOKUP[pin_unit]
    if not (self_pos and cpos) then
        return nil   -- transient (hot-join/despawn tick): keep the pin, no substitute
    end
    if rawget(_G, "printf") and not blackboard._gt384_pin_held_latch then
        blackboard._gt384_pin_held_latch = true
        printf("[gt:384:pin] HELD errand across need-flicker bot=%s ally=%s need=%s bail=%s",
            _gt384_label(blackboard.unit), _gt384_label(pin_unit), tostring(pin_need),
            tostring(bail_active and blackboard._gt492_bailout_reason or "none"))
    end
    return pin_unit, Vector3.distance(self_pos, cpos), pin_need
end

-- True while an armed pin's target still classifies -- read by the
-- should_teleport / cant_reach_ally hooks to decide whether a #492 no-progress
-- bail may release the teleport veto. Field read only (1-frame lag vs the
-- picker's release converges next tick).
_gt384_pin_live = function(blackboard)
    return blackboard._gt384_pin_unit ~= nil
end

mod:hook("PlayerBotBase", "_select_ally_by_utility", function (func, self, unit, blackboard, breed, t)
    local ally, real_dist, need_type, look_at = func(self, unit, blackboard, breed, t)
    -- Vanilla returns math.huge when no ally wins. Preserve that producer
    -- contract across every GT branch so _update_target_ally never writes nil
    -- into the numeric `blackboard.ally_distance` utility input.
    real_dist = mod._gt_bot_utility_policy.normalize_ally_distance(real_dist)

    -- Continue if the kept-separate awaiting-rescue toggle is on (FIX 3) OR the
    -- FIX 3b revive/rescue-priority feature is on (master + its
    -- gt_bot_aid_priority sub-toggle, #297 v0.2.182-dev; v0.2.128-dev had it on
    -- the bundle alone, pre-bundle it was gt_bot_revive_priority /
    -- gt_bot_rescue_priority).
    -- FIX 13 (#523): heal-allies also needs the body to run to reach its
    -- injection point (after FIX 3/3b, so it can never preempt a revive/rescue).
    local _gt_heal_allies_active = _gt_heal_allies_on()
    local _gt_rescue_awaiting_active = mod:get("gt_bot_rescue_awaiting")
    if not (_gt_rescue_awaiting_active
            or (mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aid_priority"))
            or _gt_heal_allies_active) then
        return ally, real_dist, need_type, look_at
    end

    -- Never override an already-found higher/equal-priority aid.
    if need_type == "knocked_down" or need_type == "ledge" or need_type == "hook" then
        -- #492: if the stall watchdog has armed a bailout for THIS aid target,
        -- drop the pick so _update_target_ally clears target_ally_need_type
        -- (player_bot_base.lua:721-723) and the bot re-evaluates teleport.
        if mod._gt492_should_suppress_pick and mod._gt492_should_suppress_pick(blackboard, ally) then
            if blackboard._gt492_bailout_reason ~= "no-progress" then
                -- no-path (authoritative give-up) keeps the shipped hard drop.
                return nil, math.huge, nil, nil
            end
            -- #384: a no-progress bail must not hard-drop a live errand (log
            -- evidence: veto released into a teleport loop while the ally was
            -- still down). Null the pick and fall through so the pin below can
            -- re-assert it; the pin releases the moment the bail turns no-path.
            ally, real_dist, need_type, look_at = nil, math.huge, nil, nil
        else
            _gt384_arm_pin(blackboard, ally, need_type)
            return ally, real_dist, need_type, look_at
        end
    end

    -- While #523 is enabled, its explicit thresholds and Zealot policy replace
    -- vanilla's fixed 25% heal-selection rule. Discard only vanilla's heal pick,
    -- then let the policy scan below choose the best eligible HUMAN. The native
    -- can_heal_player condition and interact action still receive the final pick.
    if _gt_heal_allies_active and need_type == "in_need_of_heal" then
        ally, real_dist, need_type, look_at = nil, math.huge, nil, nil
    end

    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then
        return ally, real_dist, need_type, look_at
    end

    -- ROOT-CAUSE FIX (v0.2.89-dev): iterate the RAW side roster, NOT
    -- side.PLAYER_AND_BOT_UNITS. SideManager._update_frame_tables rebuilds
    -- PLAYER_AND_BOT_UNITS every frame and only keeps units for which
    -- is_valid(unit) is true, where is_valid (side_manager.lua:338-339) is
    -- `unit_alive(unit) and not status:is_ready_for_assisted_respawn()`. So an
    -- awaiting-rescue ally is ALWAYS filtered out of PLAYER_AND_BOT_UNITS, which
    -- is exactly the list the old wrapper walked -- `considered` was 0 forever
    -- and no rescue ever happened (the bug the host saw with the toggle ON).
    -- side:player_units() (side.lua:222) returns the unfiltered `_player_units`
    -- roster, which DOES keep the awaiting unit (added at respawn-spawn via
    -- add_player_unit_to_side, removed only on despawn). The per-candidate gates
    -- below (ready / alive / path) still apply, so only a genuine awaiting+
    -- reachable ally is ever picked.
    local player_and_bot_units = side:player_units()
    local self_pos = POSITION_LOOKUP[unit]
    local best_unit, best_dist
    local considered, blocked_path, blocked_range, not_alive = 0, 0, 0, 0
    local rescue_distance_cap = _gt_rescue_awaiting_active and mod._gt_rescue_awaiting_distance_cap(
        mod:get("gt_bot_rescue_awaiting_ignore_leash"),
        mod:get("gt_bot_rescue_awaiting_custom_range"),
        mod:get("gt_bot_rescue_awaiting_range_m"),
        mod:get("gt_bot_follow_distance_m")
    ) or nil

    do
        -- Throttled heartbeat: proves the wrapper runs and shows the roster size,
        -- so a repro distinguishes "hook never fired" from "no awaiting ally in
        -- roster". Fires even when considered == 0 (unlike the summary below).
        local next_hb = blackboard._gt_rescue_hb_t or 0
        if t >= next_hb then
            blackboard._gt_rescue_hb_t = t + 3.0
            pcall(printf, "[gt:bot-rescue] scan roster=%d prior_need=%s", #player_and_bot_units, tostring(need_type))
        end
    end

    for k = 1, #player_and_bot_units do
        local player_unit = player_and_bot_units[k]

        if player_unit ~= unit then
            local status_ext = ScriptUnit.has_extension(player_unit, "status_system")
            local ready = status_ext and status_ext:is_ready_for_assisted_respawn()

            if ready then
                -- DIAGNOSTIC (v0.2.85-dev): log every awaiting-rescue candidate with the
                -- two gates that decide whether we can rescue it, so a repro tells us
                -- exactly why no pick happens: considered=0 => the CW respawn state
                -- never sets is_ready_for_assisted_respawn; health_alive=false => the
                -- HEALTH_ALIVE gate is wrong for this state; aid_path=false => pathing
                -- to the respawn spot is disallowed.
                considered = considered + 1
                local alive = HEALTH_ALIVE[player_unit] and true or false
                local _, allowed_aid_path = self:_ally_path_allowed(unit, player_unit, t)
                local cand_pos = POSITION_LOOKUP[player_unit]

                pcall(printf, "[gt:bot-rescue] candidate idx=%d ready=true health_alive=%s aid_path=%s has_pos=%s",
                    k, tostring(alive), tostring(allowed_aid_path and true or false), tostring(cand_pos ~= nil))

                if not alive then
                    not_alive = not_alive + 1
                elseif not allowed_aid_path then
                    blocked_path = blocked_path + 1
                elseif self_pos and cand_pos then
                    -- nil-guard both positions: a just-spawned remote awaiting unit
                    -- can momentarily lack a POSITION_LOOKUP entry (skip this frame).
                    local d = Vector3.distance(self_pos, cand_pos)
                    if not mod._gt_rescue_awaiting_within_cap(d, rescue_distance_cap) then
                        blocked_range = blocked_range + 1
                    elseif not best_dist or d < best_dist then
                        best_dist = d
                        best_unit = player_unit
                    end
                end
            end
        end
    end

    if considered > 0 then
        local next_t = blackboard._gt_rescue_log_t or 0
        if t >= next_t then
            blackboard._gt_rescue_log_t = t + 2.0
            pcall(printf, "[gt:bot-rescue] awaiting=%d picked=%s not_health_alive=%d path_blocked=%d range_blocked=%d cap_m=%s prior_need=%s",
                considered, best_unit and "yes" or "no", not_alive, blocked_path, blocked_range,
                rescue_distance_cap and string.format("%.1f", rescue_distance_cap) or "unlimited", tostring(need_type))
        end
    end

    if best_unit and _gt_rescue_awaiting_active then
        -- Relabel as knocked_down so the existing revive branch handles it; the
        -- contextual interaction resolves to assisted_respawn on this ally.
        -- (Gated on gt_bot_rescue_awaiting so the awaiting scan above can run for
        -- the priority toggles without rescuing awaiting allies when its own
        -- toggle is off.)
        pcall(printf, "[gt:bot-rescue] RESCUE picked awaiting ally dist=%.1f -> relabel knocked_down", best_dist or -1)
        _gt384_arm_pin(blackboard, best_unit, "knocked_down")
        return best_unit, best_dist, "knocked_down", false
    end

    -- ========================================================================
    -- FIX 3b (v0.2.106-dev): force revive/rescue priority over the snap-back leash
    -- ------------------------------------------------------------------------
    -- The vanilla picker already ranks aid by `dist = real_dist - utility`
    -- (player_bot_base.lua:991; utility=200 for knocked_down/ledge/hook at
    -- :909-917) with NO max-aid-distance cap -- a downed ally already wins up to
    -- ~200 m further than a follow target. But a frame where vanilla picks a
    -- follow/heal target instead can leave the bot with the team. These toggles
    -- make it EXPLICIT: re-scan for the nearest PATHABLE knocked_down (revive) /
    -- ledge|hook (rescue) ally and return it as the top-priority target with its
    -- TRUE need_type, so bt_bot's can_revive / can_rescue_* drive the right
    -- contextual interaction. Setting target_ally_need_type also auto-exempts the
    -- bot from FIX 7's leash (:561-563), so it walks the whole way. Path-gated
    -- (engine's own _ally_path_allowed) so a bot never strands itself on an
    -- unreachable ally. Host-side (bot AI is server-side).
    -- v0.2.128-dev: both revive- and rescue-priority gate on the bundle; #297
    -- (v0.2.182-dev): master AND the single gt_bot_aid_priority sub-toggle.
    -- One child deliberately drives BOTH _force_revive and _force_rescue --
    -- they are one "aid outranks everything" feature.
    local _force_revive = mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aid_priority")
    local _force_rescue = _force_revive
    if _force_revive or _force_rescue then
        local _fr_unit, _fr_eff, _fr_need
        local _prev = blackboard.target_ally_unit   -- stickiness: don't flip-flop
        for k = 1, #player_and_bot_units do
            local pu = player_and_bot_units[k]
            if pu ~= unit then
                local st = ScriptUnit.has_extension(pu, "status_system")
                local nt
                if st then
                    if _force_revive and st:is_knocked_down() then
                        nt = "knocked_down"
                    elseif _force_rescue and st:is_hanging_from_hook() then
                        nt = "hook"
                    elseif _force_rescue and st:get_is_ledge_hanging() and not st:is_pulled_up() then
                        nt = "ledge"
                    end
                end
                if nt then
                    -- Mandatory engine path-gate: only force-pick a reachable ally.
                    local _, _aid_path = self:_ally_path_allowed(unit, pu, t)
                    -- issue 142: when the backward-gate override is on, ignore the
                    -- _ally_path_allowed behind-segment cooldown for an ally who
                    -- needs aid. That helper returns false,false for up to ~10s
                    -- when a failed path's target is BEHIND the bot on the main
                    -- path (player_bot_base.lua:1962-1978, ignore_for = 10 for a
                    -- behind segment); forcing the retry lets the bot path back to
                    -- the revive immediately instead of standing off for the
                    -- cooldown. Scoped to the aid loop (nt is only set for downed /
                    -- hooked / ledge allies). Vanilla's own _select_ally_by_utility
                    -- segment skip is left untouched -- FIX 3b already bypasses it
                    -- by re-scanning the roster here.
                    if _gt_ignore_backward_gate_on() then
                        _aid_path = true
                    end
                    local cpos = POSITION_LOOKUP[pu]
                    if _aid_path and self_pos and cpos then
                        local d = Vector3.distance(self_pos, cpos)
                        -- 3 m sticky credit to the previously-chosen target so the
                        -- pick doesn't oscillate between two near-equidistant allies.
                        local eff = (pu == _prev) and (d - 3.0) or d
                        if not _fr_eff or eff < _fr_eff then
                            _fr_eff, _fr_unit, _fr_need = eff, pu, nt
                        end
                    end
                end
            end
        end
        -- #492: honour the stall bailout here too -- if this forced aid target is
        -- the one the watchdog gave up on, skip the force-pick and fall through to
        -- vanilla's (non-aid) result so target_ally_need_type clears and the bot
        -- can regroup. Vanilla's own aid pick already returned at :816-825, so the
        -- passthrough below is never an aid type.
        if _fr_unit and not (mod._gt492_should_suppress_pick and mod._gt492_should_suppress_pick(blackboard, _fr_unit)) then
            local _real = Vector3.distance(self_pos, POSITION_LOOKUP[_fr_unit])
            mod:debug("[gt:bot-priority] FORCE %s ally dist=%.1f (prior_need=%s)", _fr_need, _real, tostring(need_type))
            _gt384_arm_pin(blackboard, _fr_unit, _fr_need)
            return _fr_unit, _real, _fr_need, false
        end
    end

    -- ========================================================================
    -- #384 AID-ERRAND PIN hold (v0.2.250-dev): the wrapped chain (vanilla +
    -- FIX 3 + FIX 3b) produced NO aid pick this tick. If a pinned ally still
    -- classifies (live status -- path cooldowns cannot flicker it), re-return
    -- the errand so target_ally_need_type never drops mid-revive: vanilla's own
    -- teleport aid exception (bt_bot_conditions.lua:1226-1228), gt's tighter
    -- leash, AND can_revive (:738) all stay engaged. Runs BEFORE the FIX 13
    -- heal injection because aid outranks heal (vanilla utility 200 vs 70,
    -- player_bot_base.lua:909-937), and also overrides a heal/give/attention
    -- pick vanilla produced during a flicker frame -- exactly the pick that
    -- broke the revive lock. Rationale, evidence + release matrix at the pin
    -- helper block above; #492 no-path bail releases it there.
    -- ========================================================================
    do
        local pin_unit, pin_dist, pin_need = _gt384_hold_pin(blackboard, self_pos, _gt_rescue_awaiting_active)
        if pin_unit then
            return pin_unit, pin_dist, pin_need, false
        end
    end

    -- FIX 13 (#523): inject a heal-other target LAST -- only when nothing more
    -- urgent was picked (vanilla + FIX 3/3b left need_type nil or attention-only;
    -- a vanilla heal pick was cleared above so the configured policy owns it),
    -- so a revive/rescue/awaiting pick is never downgraded. Vanilla heal picks
    -- alone are intentionally re-evaluated against the configured policy.
    if _gt_heal_allies_active
            and (need_type == nil or need_type == "in_need_of_attention_stop"
                 or need_type == "in_need_of_attention_look") then
        local heal_unit, heal_dist, heal_hp, heal_wounded =
            _gt_pick_human_heal_target(self, unit, player_and_bot_units, self_pos, t)
        if heal_unit then
            -- [gt:523] edge-triggered per bot (acquire / retarget only, no spam).
            if heal_unit ~= blackboard._gt523_prev_target then
                blackboard._gt523_prev_target = heal_unit
                printf("[gt:523] bot heal-ally target ACQUIRED hp=%.0f%% wounded=%s dist=%.1f (relabel in_need_of_heal; drives vanilla heal_other node)",
                    (heal_hp or 0) * 100, tostring(heal_wounded), heal_dist or -1)
            end
            return heal_unit, heal_dist, "in_need_of_heal", false
        elseif blackboard._gt523_prev_target then
            blackboard._gt523_prev_target = nil
            printf("[gt:523] bot heal-ally target CLEARED (no eligible hurt human in range, or kit no longer heal-other)")
        end
    end

    return ally, real_dist, need_type, look_at
end)

-- Pure status-extension seam for the #139 regression truth table. The unit
-- wrapper below retains the engine ALIVE/POSITION_LOOKUP boundary.
local function _gt_status_needs_aid(st)
    return st:is_knocked_down()
        or st:is_hanging_from_hook()
        or (st:get_is_ledge_hanging() and not st:is_pulled_up())
end

-- #139 helper: does this ally unit currently need aid (knocked down / hanging
-- from a hook / ledge-hanging-not-yet-pulled-up)? Mirrors the inline status
-- checks in FIX 3b above. Used by FIX 7 to avoid snap-leashing a bot ONTO a
-- downed follow target (the bot should path in and revive, not teleport).
local function _gt_unit_needs_aid(u)
    if not (u and ALIVE[u]) then return false end
    local st = ScriptUnit.has_extension(u, "status_system")
    if not st then return false end
    return _gt_status_needs_aid(st)
end

-- #384 broader pure seam: aid plus pact-sworn grabs and assisted respawn.
-- Deliberately excludes corpse/brief-overpower states that are not aid errands.
local function _gt_status_needs_aid_or_rescue(st)
    return st:is_knocked_down()
        or st:is_hanging_from_hook()
        or (st:get_is_ledge_hanging() and not st:is_pulled_up())
        or st:is_pounced_down()
        or st:is_grabbed_by_pack_master()
        or st:is_grabbed_by_tentacle()
        or st:is_grabbed_by_chaos_spawn()
        or st:is_in_vortex()
        or st:is_grabbed_by_corruptor()
        or st:is_ready_for_assisted_respawn()
end

-- Unit-boundary wrapper used by the broadened teleport-veto backstop.
local function _gt_unit_needs_aid_or_rescue_full(u)
    if not (u and ALIVE[u]) then return false end
    local st = ScriptUnit.has_extension(u, "status_system")
    if not st then return false end
    return _gt_status_needs_aid_or_rescue(st)
end

-- #139 (v0.2.185-dev): the aid-priority master+sub gate, shared by FIX 3b's
-- force-revive pick and the should_teleport leash veto. When ON, a downed/
-- disabled teammate makes EVERY reachable bot drop what it is doing and path to
-- the revive, ignoring the follow leash entirely (user decision on #139: all
-- bots converge to revive). #384 (v0.2.212-dev): the veto's "teammate needs aid"
-- scan now ALSO covers awaiting-rescue + every disabler grab (see
-- _gt_any_side_teammate_needs_aid below); the #492 watchdog is the recovery valve
-- so an unreachable down/awaiting can never strand a bot.
local function _gt_aid_priority_on()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aid_priority")
end

-- #139/#384 side-wide backstop. Use the unfiltered player_units() roster so bots
-- and assisted-respawn players remain visible; #492 bounds unreachable pursuits.
local function _gt_any_side_teammate_needs_aid(self_unit)
    local sm = Managers.state and Managers.state.side
    if not sm then return nil end
    local side = sm.side_by_unit and sm.side_by_unit[self_unit]
    local punits = side and side.player_units and side:player_units()
    if not punits then return nil end
    for i = 1, #punits do
        local u = punits[i]
        if u ~= self_unit and _gt_unit_needs_aid_or_rescue_full(u) then
            return u
        end
    end
    return nil
end

-- #384 regression marker (read by gt_bot384_needs_aid_or_rescue_predicate in the
-- main file). A refactor that narrows the veto scan back to the human-only roster
-- or the knocked/hook/ledge-only predicate makes this disappear and the test fail.
GT_BOT384_AWAITING_DISABLER_VETO_MARKER = "gt-bot384-veto-covers-disablers-and-awaiting-rescue"

-- Probe helper using the same full roster/predicate as the veto backstop.
local function _gt_nearest_needing_aid(self_unit)
    local self_pos = POSITION_LOOKUP[self_unit]
    if not self_pos then return nil, nil end
    local sm = Managers.state and Managers.state.side
    local side = sm and sm.side_by_unit and sm.side_by_unit[self_unit]
    local punits = side and side.player_units and side:player_units()
    if not punits then return nil, nil end
    local best, best_d
    for i = 1, #punits do
        local u = punits[i]
        if u ~= self_unit and _gt_unit_needs_aid_or_rescue_full(u) then
            local p = POSITION_LOOKUP[u]
            if p then
                local d = Vector3.distance(self_pos, p)
                if not best_d or d < best_d then
                    best, best_d = u, d
                end
            end
        end
    end
    return best, best_d
end

-- #139 (v0.2.192-dev) testability exposures. Pure accessors -- no behavior
-- change (same pattern as mod._gt_apply_fast_reactions above). The
-- /gt_regression_test checks in general_tweaker_dev.lua drive these to guard the
-- #139 leash veto against silent regression: the status truth table
-- (_gt_status_needs_aid), the #384 broadened aid-or-rescue truth table
-- (_gt_status_needs_aid_or_rescue), and the side-scoped-not-follow scan
-- (_gt_any_side_teammate_needs_aid). Publishing a reference does not alter the
-- veto decision logic in the should_teleport hook.
mod._gt_status_needs_aid            = _gt_status_needs_aid
mod._gt_status_needs_aid_or_rescue  = _gt_status_needs_aid_or_rescue
mod._gt_unit_needs_aid             = _gt_unit_needs_aid
mod._gt_any_side_teammate_needs_aid = _gt_any_side_teammate_needs_aid
mod._gt_aid_priority_on            = _gt_aid_priority_on

-- ----------------------------------------------------------------------------
-- #492 (v0.2.198-dev): bounded recovery for the aid-priority pursuit lock
-- ----------------------------------------------------------------------------
-- WHAT
--   With aid-priority ON, the #139 decision is "all bots converge to revive": a
--   downed teammate pins blackboard.target_ally_need_type = "knocked_down" and
--   the bot drops the follow leash to path in. But nothing bounded that pursuit.
--   When the downed teammate is effectively unreachable (a long detour, a nav
--   gap, a threat the bots can't clear, or the humans having pushed 130-175 m
--   ahead of the down), the bot commits FOREVER: it never teleports to regroup.
--   Report #492 / #449: two gt bots stranded 130-175 m back for ~8 min, which
--   inflated ConflictDirector loneliness (62.6 vs threshold 25) and armed the
--   #449 cutscene-spawn class.
--
-- WHY the teleport never fires (BT structure, bt_bot.lua):
--   The teleport node ("teleport_out_of_range", condition should_teleport) sits
--   at bt_bot.lua:308-312, BELOW the revive selector (:14-32, can_revive) and the
--   priority-combat node (:305, has_priority_or_opportunity_target) in the same
--   top-level BTSelector. Two independent locks result:
--     (a) While a higher node wins (the bot fighting the horde around the down, or
--         looping the revive interaction), the selector returns before ever
--         evaluating should_teleport -- exactly the "zero should_teleport probes
--         for ~7.5 min" seen in the #449 log.
--     (b) Even when should_teleport IS reached, vanilla returns false immediately
--         while target_ally_need_type is set (bt_bot_conditions.lua:1226-1228),
--         and gt's #139 veto (the should_teleport hook below) also returns false.
--   can_revive itself keys on target_ally_need_type == "knocked_down"
--   (bt_bot_conditions.lua:738), so clearing that field breaks BOTH the revive
--   lock (a) and the teleport refusal (b) at once.
--
-- FIX (this block + the picker + the #139 veto) -- REWORKED v0.2.202-dev (#492)
--   A per-bot watchdog (mod._gt492_aid_stall_tick, dispatched from the consolidated
--   PlayerBotBase.update hook so it runs every frame). It tracks the nearest
--   downed/hooked/ledge teammate -- SAME scope as the #139 veto's
--   _gt_any_side_teammate_needs_aid -- and decides "this revive is hopeless, let the
--   bot regroup" from TWO fast signals rather than one long timer:
--     (1) NO-PATH (fast, primary): the engine's own aid pathing already records
--         whether the last path attempt to that ally FAILED. cb_ally_path_result
--         stores path_status.failed = not success into self._attempted_ally_paths
--         [ally] (player_bot_base.lua:1911-1934), fed by the aid navigation goal at
--         :1588/:1601. A sustained failure (GT492_PATH_FAIL_CONFIRM_S) IS the engine
--         telling us it cannot route there -- the nav-gap / far-ahead / past-a-
--         threshold case the report describes. Valid at any distance (a failing
--         path is itself the proof of unreachability).
--     (2) NO-PROGRESS (backstop): far from the ally (> GT492_FAR_DIST_M) with the
--         straight-line distance never closing more than GT492_PROGRESS_EPSILON_M
--         for GT492_NO_PROGRESS_TIMEOUT_S. Covers partial / repeatedly-recomputed
--         paths the engine doesn't flag as outright failures. Distance-GATED so a
--         bot merely fighting the horde right next to a reachable down (small,
--         stable distance) is NEVER pulled off the revive it is about to finish --
--         can_revive gates on threat (bt_bot_conditions.lua:748), so a close stall
--         is combat, not unreachability.
--   Either signal latches blackboard._gt492_bailout, which makes:
--     - the picker (_select_ally_by_utility above) DROP the aid pick, clearing
--       target_ally_need_type -> breaks lock (a) via can_revive and lock (b), and
--     - the #139 veto step aside -> the teleport is no longer re-blocked.
--   The bot then re-evaluates teleport and rejoins the team.
--
--   WHY the numbers (justified from the down window, not a guess): a knocked-down
--   player bleeds 10 dmg / 3 s (buff_templates.lua:4521-4531 knockdown_bleed +
--   buff_function_templates.lua:342-355), against a bleed pool equal to full max
--   health (curse debuffs cleared while down, player_unit_health_extension.lua
--   :193-196). That is a generous FLOOR of tens of seconds, but real combat down
--   windows are far shorter -- a downed teammate surrounded by enemies is dead in a
--   few seconds (field report: often < 5 s). The old 35 s bound was longer than the
--   bleed floor for low-HP careers AND many times the realistic combat window, so it
--   almost always fired AFTER the down had already resolved -- useless for its
--   purpose. The reworked bound acts within the down window: ~4 s once the engine's
--   own pathing gives up, ~8 s for the distance backstop. Vanilla itself declares a
--   follow target unreachable on the same timescale -- cant_reach_ally uses
--   t - last_success > 5 (bt_bot_conditions.lua:1203) and _ally_path_allowed a
--   3..12 s distance-scaled wait (player_bot_base.lua:1943-1946) -- so 4 s sits at
--   the fast end of the band the engine already treats as "give up".
--
--   ANTI-THRASH (the better fix for what the 35 s timer was protecting against):
--   once bailed for a given down-ally the latch HOLDS -- it does NOT clear on a mere
--   couple of metres of transient closing (the old code did, which let a bot that
--   teleported back near the team re-commit and re-stall). It un-latches ONLY when
--   the ally is no longer needing aid (target changes/clears -> #139 "all bots
--   converge" fully preserved for every reachable case) or when the bot gets
--   genuinely close again (<= GT492_REACHED_DIST_M -- it CAN reach it now, so the
--   reason we bailed is gone and it should revive). GT492_FAR_DIST_M >
--   GT492_REACHED_DIST_M gives the hysteresis that stops any oscillation.
--   UNCONDITIONAL within aid-priority (a safety valve, no menu toggle). Host-side
--   (bot AI is server-side).
local GT492_PATH_FAIL_CONFIRM_S   = 4.0    -- sustained engine aid-path failure -> unreachable (fast)
local GT492_NO_PROGRESS_TIMEOUT_S = 8.0    -- far + no net closing this long -> stuck (backstop)
local GT492_FAR_DIST_M            = 20.0   -- only the no-progress backstop fires beyond this (else revive is imminent)
local GT492_REACHED_DIST_M        = 12.0   -- once bailed, un-latch when the bot gets this close (reachable again)
local GT492_PROGRESS_EPSILON_M    = 2.0    -- min distance improvement counted as progress

-- "PlayerName" for readable logs; pcall-guarded (owner lookup can transiently
-- fail on a despawning unit). Falls back to the raw handle.
local function _gt492_label(u)
    if not u then return "nil" end
    local ok, name = pcall(function()
        local pm = Managers.player
        local owner = pm and pm.owner and pm:owner(u)
        return owner and owner.name and owner:name()
    end)
    return (ok and name) or tostring(u)
end
-- Exposed so the #384 pin helpers (declared ABOVE this definition, calling at
-- runtime via the mod table) and future diagnostics share one label format.
mod._gt492_label = _gt492_label

-- True if the unit's player is an AI bot (player_bot.lua:23 bot_player = true), so
-- the #492 census can say whether a down is a human or a bot. pcall-guarded.
local function _gt492_is_bot(u)
    if not u then return false end
    local ok, is_bot = pcall(function()
        local pm = Managers.player
        local owner = pm and pm.owner and pm:owner(u)
        return owner and owner.bot_player == true
    end)
    return (ok and is_bot) or false
end

-- item 2 observability census: at the decisive bail moment, tally the side so a
-- single field-log line settles WHICH of the user's two suspected conditions held:
--   * "the bots themselves were down (cannot aid)"      -> downed_bots high, helpers low
--   * "players in a spot bots cannot path to"           -> reason=no-path + large dist
-- Walks the full hero+bot roster (side.PLAYER_AND_BOT_UNITS): each teammate is
-- either needing aid (knocked/hook/ledge, classed bot vs human) or an alive helper
-- who could revive (alive, not awaiting assisted respawn). Cheap; called once per
-- bail (latched), never per frame.
local function _gt492_aid_census(self_unit)
    local sm = Managers.state and Managers.state.side
    local side = sm and sm.side_by_unit and sm.side_by_unit[self_unit]
    local units = side and side.PLAYER_AND_BOT_UNITS
    if not units then return 0, 0, 0 end
    local alive_helpers, down_humans, down_bots = 0, 0, 0
    for i = 1, #units do
        local u = units[i]
        if u ~= self_unit then
            local st = ScriptUnit.has_extension(u, "status_system")
            if st then
                if _gt_status_needs_aid(st) then
                    if _gt492_is_bot(u) then down_bots = down_bots + 1
                    else down_humans = down_humans + 1 end
                elseif HEALTH_ALIVE[u] and st.ready_for_assisted_respawn ~= true then
                    alive_helpers = alive_helpers + 1
                end
            end
        end
    end
    return alive_helpers, down_humans, down_bots
end

-- #492 PURE decision machine (testability seam -- NO engine reads; the tick reads
-- engine state and passes the two derived scalars in). Given the prior per-bot
-- pursuit `state` ({aid_unit, best_dist, progress_t, fail_since, bailed}), the
-- current aid target, its straight-line distance, whether the engine's last aid
-- path to it FAILED, and the time, returns (new_state, bailout). Bails on either a
-- sustained aid-path failure (fast) or a far no-progress stall (backstop), and
-- LATCHES until the target clears or the bot gets close again. The
-- /gt_regression_test drives this with a synthetic sequence to lock the recovery
-- invariant against silent regression.
local function _gt492_step(state, aid_unit, aid_dist, path_failed, t)
    if not aid_unit then
        return { aid_unit = nil }, false
    end
    if state.aid_unit ~= aid_unit then
        -- New (or first) target: start a fresh pursuit clock, un-bailed.
        return { aid_unit = aid_unit, best_dist = aid_dist, progress_t = t, fail_since = nil, bailed = false }, false
    end

    -- Already bailed: HOLD the latch (anti-thrash). Un-latch only when the bot has
    -- closed to within reach -- the ally is reachable now, so revive instead.
    if state.bailed then
        if aid_dist and aid_dist <= GT492_REACHED_DIST_M then
            return { aid_unit = aid_unit, best_dist = aid_dist, progress_t = t, fail_since = nil, bailed = false }, false
        end
        return { aid_unit = aid_unit, best_dist = state.best_dist, progress_t = state.progress_t,
                 fail_since = state.fail_since, bailed = true }, true
    end

    -- Not yet bailed: track closing progress (best distance achieved).
    local best_dist, progress_t = state.best_dist, state.progress_t
    if not best_dist or (aid_dist and aid_dist < best_dist - GT492_PROGRESS_EPSILON_M) then
        best_dist, progress_t = aid_dist, t
    end

    -- Fast signal: how long the engine has continuously failed to path to the ally.
    local fail_since = state.fail_since
    if path_failed then
        fail_since = fail_since or t
    else
        fail_since = nil
    end

    local far        = aid_dist and aid_dist > GT492_FAR_DIST_M
    local path_stuck  = fail_since ~= nil and (t - fail_since) >= GT492_PATH_FAIL_CONFIRM_S
    local no_progress = far and (t - (progress_t or t)) >= GT492_NO_PROGRESS_TIMEOUT_S
    local bailed = (path_stuck or no_progress) and true or false

    return { aid_unit = aid_unit, best_dist = best_dist, progress_t = progress_t,
             fail_since = fail_since, bailed = bailed }, bailed
end
mod._gt492_step = _gt492_step

-- Picker actuator: the #492 watchdog arms blackboard._gt492_bailout for a specific
-- unreachable aid target; the picker suppresses ONLY that target so a nearer/other
-- aid pick is untouched. Field reads only (no forward-ref); called from
-- _select_ally_by_utility above via mod._gt492_should_suppress_pick.
local function _gt492_should_suppress_pick(blackboard, ally)
    return blackboard._gt492_bailout and ally ~= nil and ally == blackboard._gt492_bailout_unit
end
mod._gt492_should_suppress_pick = _gt492_should_suppress_pick

-- True when this frame's nearest aid target differs from the one the prior state
-- tracked (or there was no prior state) -- the "pursuit just started" edge the
-- FAR-pursuit-start log fires on. Declared before the tick so the closure captures
-- it as an upvalue (a later file-scope local would resolve to a nil global here).
local function _gt492_target_changed(state, aid_unit)
    if not aid_unit then return false end
    return (not state) or state.aid_unit ~= aid_unit
end

-- The every-frame watchdog. Engine reads live here; the decision is delegated to
-- the pure _gt492_step. Dispatched from the consolidated PlayerBotBase.update
-- hook (that hook is a post-callback, so the flag it sets is read by the NEXT
-- frame's picker + should_teleport tick -- a 1-frame lag that converges).
mod._gt492_aid_stall_tick = function(self, unit, blackboard, t)
    -- Aid-priority only: this recovers the #139 "all bots converge to revive"
    -- pin, which is the only thing that keeps the bot from teleporting.
    if not _gt_aid_priority_on() then
        blackboard._gt492_bailout = nil
        blackboard._gt492_bailout_reason = nil
        blackboard._gt492_state = nil
        -- #384: drop any armed errand pin too -- the picker's early passthrough
        -- (all bot-aid toggles off) can skip the pin branch, and this tick runs
        -- every frame, so the pin state cannot go stale on a toggle flip.
        _gt384_clear_pin(blackboard)
        return
    end

    -- Nearest downed/hooked/ledge teammate + straight-line distance. Read
    -- independently of the bot's current pick so suppressing the pick cannot feed
    -- back into this accumulator (which would oscillate the bailout every frame).
    local aid_unit = _gt_any_side_teammate_needs_aid(unit)
    local self_pos = aid_unit and POSITION_LOOKUP[unit]
    local aid_pos  = aid_unit and POSITION_LOOKUP[aid_unit]
    if aid_unit and not (self_pos and aid_pos) then
        -- Position transiently missing (despawn/hot-join): hold state, don't reset
        -- the clock or the latch this frame.
        return
    end
    local aid_dist = aid_unit and Vector3.distance(self_pos, aid_pos) or nil

    -- Engine's own aid-path reachability for THIS down-ally: cb_ally_path_result
    -- stores .failed = true whenever the last aid path attempt failed
    -- (player_bot_base.lua:1911-1934). Authoritative "can't route there" signal.
    -- nil when the bot never attempted a path to it -> falls back to no-progress.
    local path_failed = false
    if aid_unit then
        local paths = self._attempted_ally_paths
        local ps = paths and paths[aid_unit]
        path_failed = (ps and ps.failed) and true or false
    end

    -- item 2 observability: log a FAR aid pursuit at its START, so a field log
    -- captures the unreachable-looking chase even if the down resolves before a
    -- bail. Fires once per new target (aid_unit change), and only when far, so the
    -- common close-down case never spams. Cheap census included.
    local new_target = _gt492_target_changed(blackboard._gt492_state, aid_unit)
    if new_target and aid_dist and aid_dist > GT492_FAR_DIST_M and rawget(_G, "printf") then
        local helpers, dh, db = _gt492_aid_census(unit)
        printf("[gt:492] %s begins FAR aid pursuit (down=%s is_bot=%s dist=%.0fm) -- roster: alive_helpers=%d downed_humans=%d downed_bots=%d",
            _gt492_label(unit), _gt492_label(aid_unit), tostring(_gt492_is_bot(aid_unit)),
            aid_dist, helpers, dh, db)
    end

    local state = blackboard._gt492_state or { aid_unit = nil }
    local prev_bailed = state.bailed
    local new_state, bailout = _gt492_step(state, aid_unit, aid_dist, path_failed, t)
    blackboard._gt492_state = new_state

    if bailout then
        -- #384 (v0.2.250-dev): name WHICH signal bailed and stamp it on the
-- blackboard. The pin + veto release discriminate on it: a no-path bail
        -- (the engine's own aid pathing keeps failing) is the authoritative
        -- give-up and releases the errand; a no-progress bail (straight-line
        -- distance not closing) must NOT release while the pinned ally still
        -- classifies -- field log gt 0.2.248 showed no-progress bails releasing
        -- the veto into a teleport loop while the ally was still down.
        local reason = (new_state.fail_since ~= nil
            and (t - new_state.fail_since) >= GT492_PATH_FAIL_CONFIRM_S) and "no-path" or "no-progress"
        if not prev_bailed and rawget(_G, "printf") then
            -- Decisive branch point: name WHICH signal fired + the roster census,
            -- so the next field log settles bots-down vs unreachable-path (item 2).
            local helpers, dh, db = _gt492_aid_census(unit)
            printf("[gt:492] %s BAILED aid pursuit (reason=%s down=%s is_bot=%s dist=%.0fm best=%.0fm) -- suspending aid pin+veto so it can regroup; roster: alive_helpers=%d downed_humans=%d downed_bots=%d",
                _gt492_label(unit), reason, _gt492_label(aid_unit), tostring(_gt492_is_bot(aid_unit)),
                aid_dist or -1, new_state.best_dist or -1, helpers, dh, db)
        end
        blackboard._gt492_bailout = true
        blackboard._gt492_bailout_reason = reason
        blackboard._gt492_bailout_unit = aid_unit
    else
        blackboard._gt492_bailout = nil
        blackboard._gt492_bailout_reason = nil
    end
end

-- #492 regression marker (read by gt_bot492_aid_stall_recovery in the parent owner). A
-- refactor that drops the stall recovery makes this disappear and the test fail.
GT_BOT492_AID_STALL_RECOVERY_MARKER_v0_2_198 = "gt-bot492-aid-pursuit-stall-recovery"

    local api = {
        pin_live = _gt384_pin_live,
        status_needs_aid = _gt_status_needs_aid,
        unit_needs_aid = _gt_unit_needs_aid,
        aid_priority_on = _gt_aid_priority_on,
        any_side_teammate_needs_aid = _gt_any_side_teammate_needs_aid,
        nearest_needing_aid = _gt_nearest_needing_aid,
        label = _gt492_label,
    }
    mod._gt_bot_aid_owner_installed = true
    return api
end
