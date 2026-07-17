-- _gt_bot_update_fixes.lua — Per-frame bot utility fixes and update dispatcher.
--
-- Owns Necromancer potion promotion, ledge pull-up, ladder recovery, and the
-- single PlayerBotBase.update hook that dispatches all GT bot update consumers.
-- Later bot-fix modules publish optional consumers on `mod`; this dispatcher
-- resolves them at event time so manifest order does not create stale captures.
--
-- Owned by: _gt_bot_fixes.lua. Consumed via: mod:dofile.

local mod = get_mod("gt_dev")
local ScriptUnit = ScriptUnit
local POSITION_LOOKUP = POSITION_LOOKUP
local HEALTH_ALIVE = HEALTH_ALIVE
local Vector3 = Vector3
local BackendUtils = BackendUtils
local Managers = Managers
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
--
--   GIVE-HALF COMPLETION (v0.2.138-dev): the promote must target the REAL potion
--   BY IDENTITY (SwapFromStorageType.Same + the potion's item_data), not storage
--   index 1 (SwapFromStorageType.First). slot_potion storage can also hold the
--   grimoire (non-giveable) and the demoted skull, so a blind First-swap promoted
--   the wrong occupant -> primary stayed non-giveable -> the give interaction
--   never resolved the real potion -> the bot looped "trying to pass but can't".
--   See the inline rationale at the swap call. Marker:
--   GT_NECRO_POTION_GIVE_HALF_MARKER_v0_2_138.
-- Find the nearest ALIVE hero/bot ally to `unit` (excludes self). Returns the
-- ally unit or nil. Source: side.PLAYER_AND_BOT_UNITS (side_manager.lua), the
-- same roster the vanilla bot aid-picker walks.
local function _gt_nearest_alive_ally(unit)
    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then
        return nil
    end
    local units = side.PLAYER_AND_BOT_UNITS
    local self_pos = POSITION_LOOKUP[unit]
    if not self_pos then
        return nil
    end
    local best, best_d
    for i = 1, #units do
        local u = units[i]
        if u ~= unit and HEALTH_ALIVE[u] then
            local p = POSITION_LOOKUP[u]
            if p then
                local d = Vector3.distance_squared(self_pos, p)
                if not best_d or d < best_d then
                    best_d = d
                    best = u
                end
            end
        end
    end
    return best
end

-- Navmesh-valid position of a unit -- the same source vanilla's teleport check
-- reads (bt_bot_conditions.lua:1232 last_position_on_navmesh). Falls back to the
-- raw position lookup if the whereabouts extension is missing.
local function _gt_navmesh_pos(target_unit)
    if not target_unit then
        return nil
    end
    local wb = ScriptUnit.has_extension(target_unit, "whereabouts_system")
    local p = wb and wb:last_position_on_navmesh()
    return p or POSITION_LOOKUP[target_unit]
end

-- FIX 1 body, extracted into a tick fn so the SINGLE PlayerBotBase.update hook
-- below can drive it alongside the other per-frame bot features. Unchanged
-- logic; see the FIX 1 header above for the full rationale + citations.
local function _gt_necro_potion_tick(self, unit, blackboard, t)
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
        return
    end

    local primary_template = inventory_extension:get_item_template(primary)
    if primary_template and primary_template.can_give_other then
        return
    end

    local stored = inventory_extension:get_additional_items("slot_potion")
    if not stored then
        return
    end

    -- GIVE-HALF FIX (v0.2.138-dev): find the EXACT giveable-potion item_data in
    -- storage and promote THAT specific one, not blindly storage index 1.
    --
    -- The old code scanned storage for *a* giveable potion but then called
    -- swap_equipment_from_storage(..., SwapFromStorageType.First, ...), which
    -- promotes stored_items[1] unconditionally (get_additional_item_swap_id
    -- returns item_id=1 for the First swap type, ignoring the compare arg --
    -- simple_inventory_extension.lua:2364-2365). slot_potion storage is NOT
    -- potion-only: the grimoire also lives in slot_potion (is_grimoire, no
    -- can_give_other -- grimoire.lua:62; bots stash it there, see
    -- bt_bot_conditions.lua:1244-1259 should_drop_grimoire), and the demoted
    -- skull lands there too. So with storage = {grimoire, real_potion} (or
    -- {skull, ...}) the First swap promotes the grimoire/skull to primary, NOT
    -- the potion. That leaves slot_potion primary STILL non-giveable, so the
    -- vanilla give chain (scoring player_bot_base.lua:882-888 -> wield
    -- slot_potion -> interactions.lua give `set_interactor_data`:1707-1711 +
    -- transfer `stop`:1640-1664 gated on can_give_other:1646) can't resolve the
    -- real potion -- the bot keeps re-offering and gets STUCK trying to pass.
    --
    -- Fix: locate the giveable potion's exact item_data reference (it lives in
    -- the live `stored` array we already iterate) and promote it by identity via
    -- SwapFromStorageType.Same, passing that item_data as the compare item.
    -- get_additional_item_swap_id(Same) returns the index where
    -- stored_items[i] == compare_item (:2374-2385), so the REAL potion lands in
    -- primary regardless of storage ordering; the grimoire/skull never get
    -- mis-promoted. Once the potion is primary, the whole vanilla give chain
    -- (and the bot drinking its own potion) just works.
    local giveable_item_data
    for i = 1, #stored do
        local item_data = stored[i]
        local template = item_data and BackendUtils.get_item_template(item_data)
        if template and template.can_give_other then
            giveable_item_data = item_data
            break
        end
    end

    if giveable_item_data then
        inventory_extension:swap_equipment_from_storage("slot_potion", SwapFromStorageType.Same, giveable_item_data)

        mod:debug("[gt:bot] promoted Necromancer bot's REAL potion (by identity) to primary so it can hand off / drink it")
    end
end

-- ----------------------------------------------------------------------------
-- FIX 4: Bots auto pull-up from ledge-hang after a few seconds
-- ----------------------------------------------------------------------------
-- WHAT
--   The ledge-hanging character state has NO self-rescue path -- it waits for
--   another unit's `pull_up` interaction or, after
--   PlayerUnitMovementSettings.ledge_hanging.time_until_fall_down = 30s, drops
--   the hanger (player_character_state_ledge_hanging.lua:91-111). A bot left
--   hanging just hangs until a human comes back.
-- FIX
--   After the configured delay of continuous ledge-hang, do the engine's own
--   pull-up: StatusUtils.set_pulled_up_network(bot, true, helper)
--   (status_utils.lua:84). The state polls is_pulled_up() every frame (line 91)
--   and transitions to leave_ledge_hanging_pull_up. set_pulled_up needs an ALIVE
--   helper unit for its dialogue branch (generic_status_extension.lua:1462), so
--   we credit the nearest alive ally; if none is alive we skip (no one to pull
--   you up). Host-side only.
local function _gt_ledge_pullup_tick(self, unit, blackboard, t)
    local status_extension = blackboard.status_extension or ScriptUnit.has_extension(unit, "status_system")
    if not status_extension or not status_extension:get_is_ledge_hanging() then
        blackboard._gt_ledge_since = nil
        return
    end
    if status_extension:is_pulled_up() then
        blackboard._gt_ledge_since = nil
        return
    end

    local since = blackboard._gt_ledge_since
    if not since then
        blackboard._gt_ledge_since = t
        return
    end

    -- #297 (v0.2.182-dev): configurable again via the slider nested under the
    -- master toggle (0 = instant pull-up); numeric fallback to the former
    -- hard-coded 3s if the setting is somehow unreadable.
    local delay = tonumber(mod:get("gt_bot_ledge_pullup_delay")) or 3
    if t - since < delay then
        return
    end

    local helper = _gt_nearest_alive_ally(unit)
    if not helper then
        return
    end

    StatusUtils.set_pulled_up_network(unit, true, helper)
    blackboard._gt_ledge_since = nil

    mod:debug("[gt:bot] pulled bot up from ledge after %.1fs", delay)
end

-- ----------------------------------------------------------------------------
-- FIX 5: Bots stuck on a ladder teleport to a teammate
-- ----------------------------------------------------------------------------
-- WHAT
--   Bot pathing can wedge on ladder smart-object transitions. The bot's
--   PlayerBotNavigation tracks the active transition as `_current_transition`
--   with `.type == "ladder"` and an entry timestamp `.t`
--   (player_bot_navigation.lua:276-339). A wedged bot keeps that ladder
--   transition active far longer than a normal climb.
-- FIX
--   When a bot has sat on a ladder transition longer than the configured delay,
--   teleport it to the followed teammate's last navmesh position using the same
--   primitives the vanilla teleport node uses (bt_bot_teleport_to_ally_action.lua
--   :82-98): locomotion:teleport_to + fall-damage suppression + navigation
--   :teleport. Host-side only.
local function _gt_ladder_unstick_tick(self, unit, blackboard, t)
    local nav = blackboard.navigation_extension
    local transition = nav and nav._current_transition
    if not (transition and transition.type == "ladder") then
        blackboard._gt_ladder_since = nil
        return
    end

    local since = blackboard._gt_ladder_since
    if not since then
        blackboard._gt_ladder_since = t
        return
    end

    -- #297 (v0.2.182-dev): configurable again via the slider nested under the
    -- master toggle (min 3s so normal climbs never trip it); numeric fallback
    -- to the former hard-coded 4s if the setting is somehow unreadable.
    local delay = tonumber(mod:get("gt_bot_ladder_unstick_delay")) or 4
    if t - since < delay then
        return
    end

    -- Prefer the unit the bot is following; fall back to nearest alive ally.
    local group_ext = blackboard.ai_bot_group_extension
    local follow_unit = group_ext and group_ext.data and group_ext.data.follow_unit
    local anchor = (follow_unit and HEALTH_ALIVE[follow_unit] and follow_unit) or _gt_nearest_alive_ally(unit)
    local pos = _gt_navmesh_pos(anchor)
    local locomotion = blackboard.locomotion_extension
    if not (pos and locomotion and nav) then
        return
    end

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
    blackboard._gt_ladder_since = nil

    mod:debug("[gt:bot] teleported bot off a stuck ladder after %.1fs", delay)
end

-- FIX 6 + potion-danger helpers moved to _gt_bot_consumables.lua.
-- ----------------------------------------------------------------------------
-- CONSOLIDATION SITE: _gt_bot_update_consolidated
-- ----------------------------------------------------------------------------
-- The SINGLE PlayerBotBase.update hook. VMF silently drops a second hook on the
-- same (Class, method), so every per-frame bot feature dispatches from here,
-- each gated on its own toggle. DO NOT add another PlayerBotBase.update hook --
-- add a gated `_gt_*_tick` fn above and a line below instead.
mod:hook_safe("PlayerBotBase", "update", function (self, unit, input, dt, context, t)
    local blackboard = self._blackboard
    if not blackboard then
        return
    end

    -- v0.2.128-dev bundled these four per-frame bot features under the single
    -- `gt_bot_behavior_improvements` toggle; #297 (v0.2.182-dev) made that a
    -- MASTER + SUB scheme: the master still gates everything, and each feature
    -- additionally reads its own sub-toggle (the pre-bundle setting ids, reused
    -- so persisted pre-bundle choices carry over). Read live every tick -- no
    -- on_setting_changed wiring.
    if mod:get("gt_bot_behavior_improvements") then
        if mod:get("gt_bot_necro_potion_handoff") then
            _gt_necro_potion_tick(self, unit, blackboard, t)
        end
        if mod:get("gt_bot_ledge_pullup") then
            _gt_ledge_pullup_tick(self, unit, blackboard, t)
        end
        if mod:get("gt_bot_ladder_unstick") then
            _gt_ladder_unstick_tick(self, unit, blackboard, t)
        end
        if mod:get("gt_bot_instant_pickup") then
            mod._gt_instant_pickup_tick(self, unit, blackboard, t)
        end
    end

    -- Replicant Bots port: drink a held potion when a boss/lord or patrol is
    -- near (separate toggle from the bundle above).
    if mod:get("gt_bot_drink_potions_in_danger") then
        mod._gt_drink_potion_tick(self, unit, blackboard, t)
    end

    -- Bot Teleport Lab (diagnostics) dispatch: registers the bot for the D6/D7
    -- draw tick, watches the has_teleported clear (D9), and prints the D3
    -- distance readout. Merged here (VMF drops a 2nd PlayerBotBase.update hook);
    -- pcall-guarded + gated on gt_btlab_enabled inside the lab fn.
    if mod._gt_btlab_observe_update then
        mod._gt_btlab_observe_update(self, unit, blackboard, t)
    end

    -- #492 aid-pursuit watchdog. Runs EVERY frame (unlike the picker, which
    -- vanilla skips on a priority-enemy frame, player_bot_base.lua:698) so the
    -- clocks are reliable. Watches the nearest downed teammate; if the revive is
    -- unreachable (the engine's aid path keeps failing, or the bot is far and not
    -- closing) it latches blackboard._gt492_bailout, which the picker (drops the
    -- aid pick) and the #139 veto (steps aside) both read. Defined after the helpers below
    -- (forward-ref), dispatched here because VMF drops a 2nd PlayerBotBase.update
    -- hook. Gated on aid-priority inside the fn.
    if mod._gt492_aid_stall_tick then
        mod._gt492_aid_stall_tick(self, unit, blackboard, t)
    end
end)

return true
