local mod = get_mod("gt")

-- ============================================================================
-- Bot Options -- AI teammate behavior fixes
-- ============================================================================
-- Three independent, default-OFF, host-side fixes for long-standing bot AI
-- gaps. Bots only exist on the host (server), so every hook here is effectively
-- server-side; none registers a network event or sends an RPC, so none can
-- crash a non-modded lobby member. All gate on their own VMF toggle.
--
-- Source citations below are into the decompiled vanilla source at
-- C:\Users\danjo\source\repos\Vermintide-2-Source-Code (verified 2026-06-16).
-- ============================================================================

local ScriptUnit = ScriptUnit
local POSITION_LOOKUP = POSITION_LOOKUP
local HEALTH_ALIVE = HEALTH_ALIVE
local Vector3 = Vector3
local BackendUtils = BackendUtils

-- ----------------------------------------------------------------------------
-- FIX 1: Necromancer bot can't hand off potions (skull occupies slot_potion)
-- ----------------------------------------------------------------------------
-- WHAT
--   A Necromancer (bw_necromancer) carries a non-droppable "skull"
--   (bw_necromancer_career_utility_weapon, slot_type="potion",
--   is_not_droppable=true) that becomes the PRIMARY item in slot_potion at
--   spawn (career_settings_shovel.lua additional_inventory -> add_equipment
--   because the slot is empty, simple_inventory_extension.lua:143-154). When
--   she later picks up a real potion, the slot is occupied by the skull, so the
--   potion goes to ADDITIONAL storage (_additional_items["slot_potion"].items).
--
--   Every bot potion-handoff check reads only the PRIMARY slot item:
--     * scoring: player_bot_base.lua:881-888 reads get_slot_data("slot_potion")
--       -> skull template -> can_give_other == nil -> bot never offers a potion.
--     * give interaction: interactions.lua give_item keys off the WIELDED /
--       primary item (get_wielded_slot_item_template:1694, transfer:1640-1660,
--       gate template.can_give_other:1646/1705).
--   A human works around this by tapping the potion wield key, which promotes
--   the real potion from storage to primary (swap_equipment_from_storage). The
--   bot never does that cycle, so the skull stays primary and the handoff is
--   impossible.
--
-- FIX
--   Do the human's cycle FOR the bot: whenever a Necromancer bot has a real
--   (giveable) potion sitting in slot_potion storage while the non-giveable
--   skull is primary, promote the potion to primary
--   (swap_equipment_from_storage, simple_inventory_extension.lua:2434). Once the
--   real potion is primary, ALL the vanilla logic just works -- scoring, the
--   give interaction, and the bot drinking its own potion. The skull moves to
--   storage (harmless for a bot; bots don't use the Necromancer utility skull).
--   Throttled to ~1s; idempotent (once the potion is primary it has
--   can_give_other and the promote condition is false).
mod:hook_safe("PlayerBotBase", "update", function (self, unit, input, dt, context, t)
    if not mod:get("gt_bot_necro_potion_handoff") then
        return
    end

    local blackboard = self._blackboard
    if not blackboard then
        return
    end

    -- Throttle: this runs per-bot per-frame; once a second is plenty.
    local next_t = blackboard._gt_necro_promote_t or 0
    if t < next_t then
        return
    end
    blackboard._gt_necro_promote_t = t + 1.0

    local career_extension = blackboard.career_extension
    if not career_extension or career_extension:career_name() ~= "bw_necromancer" then
        return
    end

    local inventory_extension = blackboard.inventory_extension
    if not inventory_extension then
        return
    end

    local primary = inventory_extension:get_slot_data("slot_potion")
    if not primary then
        -- No primary potion-slot item (potion already given/used). Leave the
        -- skull where it is; nothing to promote.
        return
    end

    local primary_template = inventory_extension:get_item_template(primary)
    if primary_template and primary_template.can_give_other then
        -- A real potion is already primary -- nothing to do (idempotent exit).
        return
    end

    -- Primary is the (non-giveable) skull. Promote a stored real potion if one
    -- exists. We only swap when a genuinely giveable item is stored so we never
    -- promote a grimoire (also slot_potion, but no can_give_other).
    local stored = inventory_extension:get_additional_items("slot_potion")
    if not stored then
        return
    end

    local has_giveable_potion = false
    for i = 1, #stored do
        local item_data = stored[i]
        local template = item_data and BackendUtils.get_item_template(item_data)
        if template and template.can_give_other then
            has_giveable_potion = true
            break
        end
    end

    if has_giveable_potion then
        -- Bring the stored potion to primary, demote the skull to storage --
        -- exactly what the human's "tap potion key" does. Max additional slot
        -- count for Necro slot_potion is 1, so First == the potion.
        inventory_extension:swap_equipment_from_storage("slot_potion", SwapFromStorageType.First, primary.item_data)
        mod:debug("[gt:bot] promoted Necromancer bot potion to primary so it can hand off / drink it")
    end
end)

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

    if not mod:get("gt_bot_ironbreaker_revive_in_ult") then
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
mod:hook("PlayerBotBase", "_select_ally_by_utility", function (func, self, unit, blackboard, breed, t)
    local ally, real_dist, need_type, look_at = func(self, unit, blackboard, breed, t)

    if not mod:get("gt_bot_rescue_awaiting") then
        return ally, real_dist, need_type, look_at
    end

    -- Never override an already-found higher/equal-priority aid.
    if need_type == "knocked_down" or need_type == "ledge" or need_type == "hook" then
        return ally, real_dist, need_type, look_at
    end

    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then
        return ally, real_dist, need_type, look_at
    end

    local player_and_bot_units = side.PLAYER_AND_BOT_UNITS
    local self_pos = POSITION_LOOKUP[unit]
    local best_unit, best_dist
    local considered, blocked_path, not_alive = 0, 0, 0

    for k = 1, #player_and_bot_units do
        local player_unit = player_and_bot_units[k]

        if player_unit ~= unit then
            local status_ext = ScriptUnit.has_extension(player_unit, "status_system")
            local ready = status_ext and status_ext:is_ready_for_assisted_respawn()

            if ready then
                -- DIAGNOSTIC (v0.2.71): log every awaiting-rescue candidate with the
                -- two gates that decide whether we can rescue it, so a repro tells us
                -- exactly why no pick happens: considered=0 => the CW respawn state
                -- never sets is_ready_for_assisted_respawn; health_alive=false => the
                -- HEALTH_ALIVE gate is wrong for this state; aid_path=false => pathing
                -- to the respawn spot is disallowed.
                considered = considered + 1
                local alive = HEALTH_ALIVE[player_unit] and true or false
                local _, allowed_aid_path = self:_ally_path_allowed(unit, player_unit, t)

                mod:debug("[gt:bot-rescue] candidate idx=%d ready=true health_alive=%s aid_path=%s",
                    k, tostring(alive), tostring(allowed_aid_path and true or false))

                if not alive then
                    not_alive = not_alive + 1
                elseif not allowed_aid_path then
                    blocked_path = blocked_path + 1
                else
                    local d = Vector3.distance(self_pos, POSITION_LOOKUP[player_unit])
                    if not best_dist or d < best_dist then
                        best_dist = d
                        best_unit = player_unit
                    end
                end
            end
        end
    end

    -- Throttled per-bot summary so we see WHY a rescue did/didn't fire
    -- without spamming when no one is awaiting rescue.
    if considered > 0 then
        local next_t = blackboard._gt_rescue_log_t or 0
        if t >= next_t then
            blackboard._gt_rescue_log_t = t + 2.0
            mod:debug("[gt:bot-rescue] awaiting=%d picked=%s not_health_alive=%d path_blocked=%d prior_need=%s",
                considered, best_unit and "yes" or "no", not_alive, blocked_path, tostring(need_type))
        end
    end

    if best_unit then
        -- Relabel as knocked_down so the existing revive branch handles it; the
        -- contextual interaction resolves to assisted_respawn on this ally.
        return best_unit, best_dist, "knocked_down", false
    end

    return ally, real_dist, need_type, look_at
end)
