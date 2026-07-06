local mod = get_mod("gt_dev")

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
-- potions, follow mode, guard-break message, rescue-awaiting, FIX 0/7/9)
-- keeps its own independent toggle.
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

-- ----------------------------------------------------------------------------
-- FIX 6: Bots instantly grab their targeted/pinged pickup (no walking)
-- ----------------------------------------------------------------------------
-- WHAT
--   Bots normally walk to within 3.2m before looting (BTConditions.can_loot,
--   bt_bot_conditions.lua:877). Vanilla already has a failsafe: when an ordered
--   pickup has no navmesh path, player_bot_base.lua:1606-1633 sets
--   `forced_pickup_unit`, and can_loot then bypasses the distance gate because
--   `is_forced_pickup = forced_pickup_unit == interaction_unit` short-circuits
--   the `max_dist > dist` checks (bt_bot_conditions.lua:884-890).
-- FIX
--   Make that failsafe always-on for a bot's CURRENT pickup candidate: point
--   both `interaction_unit` and `forced_pickup_unit` at the live candidate
--   (mule/ordered first, then health, then ammo). is_forced_pickup then trips
--   and the bot loots from where it stands. We skip when the bot has an aid
--   target so we never stomp a revive interaction. EXPERIMENTAL -- verify
--   in-game. Host-side only.
local function _gt_instant_pickup_tick(self, unit, blackboard, t)
    if blackboard.target_ally_need_type then
        return
    end
    local pickup = blackboard.mule_pickup or blackboard.health_pickup or blackboard.ammo_pickup
    if not (pickup and Unit.alive(pickup)) then
        return
    end
    blackboard.interaction_unit = pickup
    blackboard.forced_pickup_unit = pickup
end

-- ----------------------------------------------------------------------------
-- REPLICANT BOTS PORT 2: Bots drink potions when in danger (configurable, #320)
-- ----------------------------------------------------------------------------
-- WHAT
--   Vanilla bots never drink their OWN potion -- player_bot_base.lua only ever
--   hands a potion to an ally or picks one up; there's no self-use behavior. So
--   a bot can sit on a Strength/Speed/Conc potion through a whole boss fight.
-- FIX (gt idiom; NOT a copy of Replicant's bt_bot_drink_pot_action BT node)
--   Throttled per-bot tick (mirrors the other _gt_*_tick fns). When a bot holds
--   a giveable/usable potion in slot_potion AND a configured "danger" is within
--   range, drive the drink the way BTBotHealAction does: wield slot_potion and
--   hold the use input until the potion is consumed (slot empties). One drink
--   per held potion (_gt_drinking latch cleared when the slot empties).
--
--   ADVANCED CONDITIONS (#320): the master toggle gt_bot_drink_potions_in_danger
--   now nests sub-widgets that decide WHAT counts as danger, all read LIVE each
--   scan inside _gt_danger_near (no on_setting_changed wiring):
--     * gt_bot_drink_range_m      -- scan radius in metres (was hard-coded 18)
--     * gt_bot_drink_on_boss      -- any breed.boss monster/lord in range
--     * gt_bot_drink_on_special   -- any breed.special (disabler/ranged) in range
--     * gt_bot_drink_on_patrol    -- >= gt_bot_drink_patrol_count elites in range
--     * gt_bot_drink_on_horde     -- >= gt_bot_drink_horde_count trash in range
--   Breed class is read live off each AI unit's Breed table (breed.boss /
--   breed.special / breed.elite; trash = none of those -- verified against
--   Vermintide-2-Source-Code/scripts/settings/breeds/*.lua 2026-07-04), not a
--   static name roster. Host-side only (bots are host-only). Default OFF.
local _GT_BOT_DANGER_RANGE = 18.0          -- meters; fallback danger scan radius
local _GT_BOT_PATROL_ELITE_THRESHOLD = 3   -- fallback: >= this many elites == "patrol"
local _GT_BOT_HORDE_TRASH_THRESHOLD = 8    -- fallback: >= this many trash == "horde"

-- True if any ENABLED danger condition is met within the configured range of
-- `self_pos`. Reads the live Breed table off each AI unit (breed.boss /
-- breed.special / breed.elite; trash = none of those) and the live menu
-- settings each call, so a condition change takes effect without a reload.
local function _gt_danger_near(unit, self_pos)
    if not self_pos then return false end
    local side_manager = Managers.state.side
    local side = side_manager and side_manager.side_by_unit[unit]
    if not side then return false end

    -- AI enemy units of this side (Side:enemy_units() -> the compact _enemy_units
    -- roster, swap-remove maintained so 1..#enemy_units has no holes).
    local enemy_units = side.enemy_units and side:enemy_units()
    if not enemy_units then return false end

    -- Advanced conditions (#320), live-read each scan.
    local on_boss    = mod:get("gt_bot_drink_on_boss")
    local on_special = mod:get("gt_bot_drink_on_special")
    local on_patrol  = mod:get("gt_bot_drink_on_patrol")
    local on_horde   = mod:get("gt_bot_drink_on_horde")

    -- Every trigger off -> the feature can never fire; bail before the scan.
    if not (on_boss or on_special or on_patrol or on_horde) then
        return false
    end

    local range = tonumber(mod:get("gt_bot_drink_range_m")) or _GT_BOT_DANGER_RANGE
    local range_sq = range * range
    -- Disabled cluster conditions use an unreachable threshold so their tallies
    -- never trip (math.huge is never <= a finite count).
    local patrol_threshold = on_patrol and (tonumber(mod:get("gt_bot_drink_patrol_count")) or _GT_BOT_PATROL_ELITE_THRESHOLD) or math.huge
    local horde_threshold  = on_horde  and (tonumber(mod:get("gt_bot_drink_horde_count"))  or _GT_BOT_HORDE_TRASH_THRESHOLD) or math.huge

    local elite_count, trash_count = 0, 0
    for i = 1, #enemy_units do
        local enemy = enemy_units[i]
        if ALIVE[enemy] then
            local ep = POSITION_LOOKUP[enemy]
            if ep and Vector3.distance_squared(self_pos, ep) <= range_sq then
                local breed = Unit.get_data(enemy, "breed")
                if breed then
                    -- Class priority: boss > special > elite > trash. A boss with
                    -- its trigger off simply does nothing (it is not "trash").
                    if breed.boss then
                        if on_boss then return true end       -- a monster/lord in range
                    elseif breed.special then
                        if on_special then return true end     -- a disabler/ranged special in range
                    elseif breed.elite then
                        elite_count = elite_count + 1
                        if elite_count >= patrol_threshold then
                            return true                        -- elite cluster -> patrol
                        end
                    else
                        trash_count = trash_count + 1
                        if trash_count >= horde_threshold then
                            return true                        -- trash cluster -> horde
                        end
                    end
                end
            end
        end
    end
    return false
end

local function _gt_drink_potion_tick(self, unit, blackboard, t)
    local inventory_extension = blackboard.inventory_extension
    if not inventory_extension then
        blackboard._gt_drinking = nil
        return
    end

    -- If we latched a drink, keep holding the use input until the potion slot
    -- empties (consumed), then release the latch. This survives the BT trying to
    -- re-wield a combat weapon for the few frames the drink takes.
    if blackboard._gt_drinking then
        local still_have = inventory_extension:get_slot_data("slot_potion")
        local input_ext = blackboard.input_extension
        if still_have and input_ext then
            input_ext:wield("slot_potion")
            input_ext:hold_attack()
            -- Safety timeout: never hold longer than ~1.5s.
            if t < (blackboard._gt_drinking_until or 0) then
                return
            end
        end
        blackboard._gt_drinking = nil
        blackboard._gt_drinking_until = nil
        return
    end

    -- Throttle the danger scan (once a second is plenty).
    local next_t = blackboard._gt_drink_scan_t or 0
    if t < next_t then
        return
    end
    blackboard._gt_drink_scan_t = t + 1.0

    -- Must actually hold a usable potion in slot_potion. can_give_other gates out
    -- the Necromancer skull and other non-potion slot_potion occupants.
    local potion = inventory_extension:get_slot_data("slot_potion")
    if not potion then return end
    local template = inventory_extension:get_item_template(potion)
    if not (template and template.can_give_other) then return end

    local self_pos = POSITION_LOOKUP[unit]
    if not _gt_danger_near(unit, self_pos) then return end

    -- Latch the drink for up to ~1.5s of held use input.
    blackboard._gt_drinking = true
    blackboard._gt_drinking_until = t + 1.5

    mod:debug("[gt:bot] bot drinking its potion (danger in range)")
end

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
            _gt_instant_pickup_tick(self, unit, blackboard, t)
        end
    end

    -- Replicant Bots port: drink a held potion when a boss/lord or patrol is
    -- near (separate toggle from the bundle above).
    if mod:get("gt_bot_drink_potions_in_danger") then
        _gt_drink_potion_tick(self, unit, blackboard, t)
    end

    -- Bot Teleport Lab (diagnostics) dispatch: registers the bot for the D6/D7
    -- draw tick, watches the has_teleported clear (D9), and prints the D3
    -- distance readout. Merged here (VMF drops a 2nd PlayerBotBase.update hook);
    -- pcall-guarded + gated on gt_btlab_enabled inside the lab fn.
    if mod._gt_btlab_observe_update then
        mod._gt_btlab_observe_update(self, unit, blackboard, t)
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

    -- Continue if the kept-separate awaiting-rescue toggle is on (FIX 3) OR the
    -- FIX 3b revive/rescue-priority feature is on (master + its
    -- gt_bot_aid_priority sub-toggle, #297 v0.2.182-dev; v0.2.128-dev had it on
    -- the bundle alone, pre-bundle it was gt_bot_revive_priority /
    -- gt_bot_rescue_priority).
    if not (mod:get("gt_bot_rescue_awaiting")
            or (mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aid_priority"))) then
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
    local considered, blocked_path, not_alive = 0, 0, 0

    do
        -- Throttled heartbeat: proves the wrapper runs and shows the roster size,
        -- so a repro distinguishes "hook never fired" from "no awaiting ally in
        -- roster". Fires even when considered == 0 (unlike the summary below).
        local next_hb = blackboard._gt_rescue_hb_t or 0
        if t >= next_hb then
            blackboard._gt_rescue_hb_t = t + 3.0
            mod:debug("[gt:bot-rescue] scan roster=%d prior_need=%s", #player_and_bot_units, tostring(need_type))
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

                mod:debug("[gt:bot-rescue] candidate idx=%d ready=true health_alive=%s aid_path=%s has_pos=%s",
                    k, tostring(alive), tostring(allowed_aid_path and true or false), tostring(cand_pos ~= nil))

                if not alive then
                    not_alive = not_alive + 1
                elseif not allowed_aid_path then
                    blocked_path = blocked_path + 1
                elseif self_pos and cand_pos then
                    -- nil-guard both positions: a just-spawned remote awaiting unit
                    -- can momentarily lack a POSITION_LOOKUP entry (skip this frame).
                    local d = Vector3.distance(self_pos, cand_pos)
                    if not best_dist or d < best_dist then
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
            mod:debug("[gt:bot-rescue] awaiting=%d picked=%s not_health_alive=%d path_blocked=%d prior_need=%s",
                considered, best_unit and "yes" or "no", not_alive, blocked_path, tostring(need_type))
        end
    end

    if best_unit and mod:get("gt_bot_rescue_awaiting") then
        -- Relabel as knocked_down so the existing revive branch handles it; the
        -- contextual interaction resolves to assisted_respawn on this ally.
        -- (Gated on gt_bot_rescue_awaiting so the awaiting scan above can run for
        -- the priority toggles without rescuing awaiting allies when its own
        -- toggle is off.)
        mod:debug("[gt:bot-rescue] RESCUE picked awaiting ally dist=%.1f -> relabel knocked_down", best_dist or -1)
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
        if _fr_unit then
            local _real = Vector3.distance(self_pos, POSITION_LOOKUP[_fr_unit])
            mod:debug("[gt:bot-priority] FORCE %s ally dist=%.1f (prior_need=%s)", _fr_need, _real, tostring(need_type))
            return _fr_unit, _real, _fr_need, false
        end
    end

    return ally, real_dist, need_type, look_at
end)

-- #139 pure predicate seam (v0.2.192-dev). The status-extension -> needs-aid
-- boolean split out of _gt_unit_needs_aid, testability-only and BEHAVIOR
-- IDENTICAL: the OR expression is byte-for-byte the former inline body. Exists
-- because the /gt_regression_test must exercise the exact knocked / hook /
-- ledge-not-pulled-up truth table with a STUB status extension -- and it cannot
-- stub the unit boundary, since _gt_unit_needs_aid's ALIVE[u] guard reads the
-- engine POSITION_LOOKUP map (global_utils.lua:15 `ALIVE = POSITION_LOOKUP`),
-- which rejects a fake unit key. This leaf takes the status ext directly.
-- Covered states (generic_status_extension.lua): is_knocked_down :2091,
-- is_hanging_from_hook :2322, get_is_ledge_hanging :2286, is_pulled_up :2262.
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

-- #139 (v0.2.185-dev): the aid-priority master+sub gate, shared by FIX 3b's
-- force-revive pick and the should_teleport leash veto. When ON, a downed/
-- disabled teammate makes EVERY reachable bot drop what it is doing and path to
-- the revive, ignoring the follow leash entirely (user decision on #139: all
-- bots converge to revive). Awaiting-rescue is deliberately NOT part of "needs
-- aid" here -- that stays owned by gt_bot_rescue_awaiting.
local function _gt_aid_priority_on()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_aid_priority")
end

-- v0.2.152-dev (#139 sibling): does ANY teammate on the bot's side currently
-- need aid? Returns the first downed/hooked/ledge ally found (or nil). Used by
-- FIX 7 to suppress the tighter leash when there's a reviveable teammate the
-- bot could path to -- prevents teleporting AWAY from where help is needed
-- (the user-reported case: bot leashed to LIVING far player, separate teammate
-- goes down, leash fires, bot teleports away from the downed teammate). FIX 3b
-- will assign `target_ally_need_type` within a tick or two and the bot will
-- walk in; we just need to keep the bot from teleporting away in the meantime.
local function _gt_any_side_teammate_needs_aid(self_unit)
    local sm = Managers.state and Managers.state.side
    if not sm then return nil end
    local side = sm.side_by_unit and sm.side_by_unit[self_unit]
    local punits = side and side.PLAYER_UNITS
    if not punits then return nil end
    for i = 1, #punits do
        local u = punits[i]
        if u ~= self_unit and _gt_unit_needs_aid(u) then
            return u
        end
    end
    return nil
end

-- #139 probe helper: like _gt_unit_needs_aid but also counts a teammate who is
-- fully dead and waiting to be freed at a rescue point. ready_for_assisted_respawn
-- is a plain field on GenericStatusExtension, set via set_ready_for_assisted_respawn
-- (generic_status_extension.lua:1329) when the respawn unit is available -- read it
-- directly (field access can't error).
local function _gt_unit_needs_aid_or_rescue(u)
    if _gt_unit_needs_aid(u) then return true end
    if not (u and ALIVE[u]) then return false end
    local st = ScriptUnit.has_extension(u, "status_system")
    return st ~= nil and st.ready_for_assisted_respawn == true
end

-- #139 probe helper: nearest side teammate who is downed or awaiting rescue,
-- with the metric distance from self_unit. Returns (unit, dist_m) or (nil, nil).
-- POSITION_LOOKUP can momentarily lack an entry during despawn -- nil-guarded.
local function _gt_nearest_needing_aid(self_unit)
    local self_pos = POSITION_LOOKUP[self_unit]
    if not self_pos then return nil, nil end
    local sm = Managers.state and Managers.state.side
    local side = sm and sm.side_by_unit and sm.side_by_unit[self_unit]
    local punits = side and side.PLAYER_UNITS
    if not punits then return nil, nil end
    local best, best_d
    for i = 1, #punits do
        local u = punits[i]
        if u ~= self_unit and _gt_unit_needs_aid_or_rescue(u) then
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
-- (_gt_status_needs_aid) and the side-scoped-not-follow scan
-- (_gt_any_side_teammate_needs_aid). Publishing a reference does not alter the
-- veto decision logic in the should_teleport hook.
mod._gt_status_needs_aid            = _gt_status_needs_aid
mod._gt_unit_needs_aid             = _gt_unit_needs_aid
mod._gt_any_side_teammate_needs_aid = _gt_any_side_teammate_needs_aid
mod._gt_aid_priority_on            = _gt_aid_priority_on

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

mod:hook("BTConditions", "should_teleport", function (func, blackboard)
    -- Bot Teleport Lab (diagnostics) dispatch: D1 decision-recorder + D4 segment
    -- probe + D5 aid probe. Merged here because VMF drops a 2nd hook on this
    -- (Class, method); the lab defines mod._gt_btlab_observe_should_teleport
    -- (pcall-guarded, gated on gt_btlab_enabled). See _gt_bot_teleport_lab.lua.
    if mod._gt_btlab_observe_should_teleport then
        mod._gt_btlab_observe_should_teleport(blackboard)
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
    -- and the leash yanks the bot AWAY from the downed one. Awaiting-rescue is
    -- EXCLUDED (_gt_any_side_teammate_needs_aid = knocked/hook/ledge only), so it
    -- stays owned by gt_bot_rescue_awaiting and a bot can still leash to a living
    -- follow while a teammate merely awaits rescue (the split+leash benefit).
    -- Independent of follow mode (split/host/default) -- that only changes WHO is
    -- followed, not the teleport rule. _gt139_veto_latched rate-limits the printf.
    if want and _gt_aid_priority_on() and _gt_any_side_teammate_needs_aid(blackboard.unit) then
        if rawget(_G, "printf") and not blackboard._gt139_veto_latched then
            blackboard._gt139_veto_latched = true
            printf("[gt_bot:139] teleport VETOED (was %s) -- teammate needs aid, bot paths to revive", tostring(reason))
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

    local result = func(self, unit, blackboard, t, dt)

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
        local post = POSITION_LOOKUP[unit]
        local aid_post = POSITION_LOOKUP[p139_aid_unit]
        local post_dist = (post and aid_post) and Vector3.distance(post, aid_post) or -1
        local tx, ty, tz = -1, -1, -1
        if post then
            tx, ty, tz = Vector3.x(post), Vector3.y(post), Vector3.z(post)
        end
        printf("[139:bot_tp] bot=%s dist_to_downed=%.1fm reason=%s post_dist=%.1fm target=%.1f,%.1f,%.1f t=%.2f",
            bot_career, p139_pre_dist or -1, p139_reason, post_dist, tx, ty, tz, t)
    end
    if blackboard then
        blackboard._gt139_tp_reason = nil
    end

    -- Bot Teleport Lab dispatch (post): D1 full event line + D8 counter + D9 set
    -- + D10 snapshot. pcall-guarded + gated inside the lab fn.
    if mod._gt_btlab_observe_teleport then
        mod._gt_btlab_observe_teleport(self, unit, blackboard, btlab_pre)
    end

    return result
end)

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

-- ----------------------------------------------------------------------------
-- FIX 10 (#297 item 8, v0.2.182-dev): Greedy pickup -- bots grab potions/bombs/
-- health items even while a nearby human's matching slot is empty
-- ----------------------------------------------------------------------------
-- WHAT (all citations into the decompiled vanilla source, verified 2026-07-04)
--   Mule items (potions/bombs/etc.): AIBotGroupSystem._update_mule_pickups
--   (ai_bot_group_system.lua:1891-2048) counts `num_players` = alive humans
--   whose `slot_name` slot is EMPTY with an available pickup within 20 m of
--   them (max_pickup_dist_sq = 400, :1894; count loop :1983-2010) and only
--   auto-assigns `blackboard.mule_pickup` to bots when `num_players == 0`
--   (:2012). So while ANY nearby human could still take the item, every bot
--   leaves it on the ground -- even when the humans don't want it.
--
--   Health items: AIBotGroupSystem._update_health_pickups (:2050-2361) gathers
--   the side's health pickups (:2063-2073, split into can_heal_self items and
--   auxiliary slot items) and then RESERVES one item per alive human whose
--   slot_healthkit is empty: the human's nearest item is REMOVED from the
--   assignable pool (:2104-2141; heal items :2116-2127, aux :2128-2140 -- with
--   NO distance cap on the human). Only the leftovers are permutation-assigned
--   to bots (find_permutation :2216 / :2309), which writes bb.health_pickup
--   (:2227 / :2319) and sets bb.allowed_to_take_health_pickup = true only when
--   the item is within MAX_PICKUP_RANGE = 15 of the bot's follow position
--   (:1847; range check :2236 / :2328). Every bot's allowed flag is force-reset
--   to false at the top of the bot loop (:2164). Net effect: with 4 medkits on
--   the floor and 4 empty-slot humans, the bots claim nothing.
--
-- FIX
--   hook_safe post-passes on BOTH functions. Fresh (Class, method) pairs --
--   duplicate-hook pre-flight grep of the whole mod dir (2026-07-04) found the
--   only other AIBotGroupSystem hooks are _assign_destination_points (FIX 9,
--   this file) and _update_urgent_targets (_gt_improved_bot_combat.lua). When
--   the master + gt_bot_greedy_pickup are on, re-run the vanilla assignment
--   logic WITHOUT the human-slot gates, assigning only to bots vanilla left
--   empty-handed and honoring vanilla's own distance rules, so bots claim the
--   items and (via vanilla's give-to-ally utility scoring,
--   player_bot_base.lua:881-917, plus FIX 6's instant grab) carry and hand
--   them to players instead of leaving floor loot to despawn behind the team.
--
--   KEPT INTACT (deliberately):
--   * force_use_health_pickup (:2355-2358) is never written by us -- a bot
--     still only SELF-uses its medkit when every human is healthier than the
--     lowest-HP bot, and :2145-2146 zeroes lowest_human_hp_percent while any
--     human is knocked down / wounded, which blocks bot self-healing while a
--     human is dying nearby. Greedy changes who CARRIES the item, not who gets
--     healed with it.
--   * Vanilla's per-tick retention/cleanup still applies: our mule assignment
--     survives the alive+follow-distance retention check (:1948) and is
--     re-marked assigned (:1961); health assignments are wiped and re-derived
--     by vanilla every tick (:2164, :2256-2266), so flipping the toggle off
--     reverts within one tick (a residual mule claim just gets consumed or
--     dropped by the same vanilla rules as any ordered pickup).
--   * The allowed_to_take_health_pickup follow-range gate (:2236) is mirrored,
--     so greedy bots still only fetch items near the team's path -- no
--     cross-map detours.
--   Host-side only (bots + this system are server-side); no RPC; nil-guarded.
GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182 = "gt-bot-greedy-pickup-mule-health-postpass"

local function _gt_greedy_pickup_on()
    return mod:get("gt_bot_behavior_improvements") and mod:get("gt_bot_greedy_pickup")
end

mod:hook_safe("AIBotGroupSystem", "_update_mule_pickups", function (self, dt, t)
    if not _gt_greedy_pickup_on() then
        return
    end
    local bot_ai_data = self._bot_ai_data
    local available_mule_pickups = self._available_mule_pickups
    if not (bot_ai_data and available_mule_pickups) then
        return
    end
    local max_pickup_dist_sq = 400   -- vanilla's own local (ai_bot_group_system.lua:1894)

    for side_id = 1, #bot_ai_data do
        local side_bot_data = bot_ai_data[side_id]
        local side_available = available_mule_pickups[side_id]
        if side_bot_data and side_available then
            -- Rebuild the "already claimed" set (vanilla's ASSIGNED_MULE_PICKUPS_TEMP
            -- :1889 is a file-local we cannot read): every pickup some bot's
            -- blackboard already targets plus every explicit pickup order.
            local claimed = {}
            for _, data in pairs(side_bot_data) do
                local bb = data.blackboard
                if bb and bb.mule_pickup then
                    claimed[bb.mule_pickup] = true
                end
                if data.pickup_orders then
                    for _, order in pairs(data.pickup_orders) do
                        if order and order.unit then
                            claimed[order.unit] = true
                        end
                    end
                end
            end

            -- Mimic the vanilla assignment loop (:2013-2043) minus the
            -- num_players == 0 gate (:2012). available_pickups was already
            -- pruned of dead/expired entries by the vanilla pass this tick
            -- (:1975-1981); Unit.alive is re-checked anyway (cheap, safe).
            for slot_name, available_pickups in pairs(side_available) do
                for bot_unit, data in pairs(side_bot_data) do
                    local blackboard = data.blackboard
                    local inventory_extension = blackboard and blackboard.inventory_extension
                    if inventory_extension then
                        local order = data.pickup_orders and data.pickup_orders[slot_name]
                        local has_item = inventory_extension:get_slot_data(slot_name)
                        local can_hold_more = inventory_extension:can_store_additional_item(slot_name)

                        -- Same per-bot eligibility as vanilla (:2020).
                        if not blackboard.mule_pickup and (not has_item or can_hold_more) and not order then
                            local best_pickup_dist_sq = math.huge
                            local best_pickup

                            for pickup_unit in pairs(available_pickups) do
                                if not claimed[pickup_unit] and Unit.alive(pickup_unit) then
                                    local pickup_pos = POSITION_LOOKUP[pickup_unit]
                                    local bot_pos = POSITION_LOOKUP[bot_unit]
                                    if pickup_pos and bot_pos then
                                        -- Vanilla distance rules (:2028-2031): the pickup must
                                        -- lie within 20 m of the bot's follow point (400 sq);
                                        -- nearest-to-the-bot wins.
                                        local bot_dist_sq = Vector3.distance_squared(bot_pos, pickup_pos)
                                        local follow_dist_sq = Vector3.distance_squared(data.follow_position or bot_pos, pickup_pos)
                                        if follow_dist_sq < max_pickup_dist_sq and bot_dist_sq < best_pickup_dist_sq then
                                            best_pickup = pickup_unit
                                            best_pickup_dist_sq = bot_dist_sq
                                        end
                                    end
                                end
                            end

                            if best_pickup then
                                -- Same blackboard writes as vanilla (:2038-2041).
                                blackboard.mule_pickup = best_pickup
                                blackboard.mule_pickup_dist_squared = best_pickup_dist_sq
                                claimed[best_pickup] = true

                                mod:debug("[gt:bot-greedy] bot claimed a %s mule pickup vanilla left for empty-slot humans", tostring(slot_name))
                            end
                        end
                    end
                end
            end
        end
    end
end)

mod:hook_safe("AIBotGroupSystem", "_update_health_pickups", function (self, dt, t)
    if not _gt_greedy_pickup_on() then
        return
    end
    local bot_ai_data = self._bot_ai_data
    local available_health_pickups = self._available_health_pickups
    if not (bot_ai_data and available_health_pickups) then
        return
    end
    local max_pickup_range = 15   -- vanilla's MAX_PICKUP_RANGE (ai_bot_group_system.lua:1847)

    for side_id = 1, #bot_ai_data do
        local side_bot_data = bot_ai_data[side_id]
        local available_pickups = available_health_pickups[side_id]
        if side_bot_data and available_pickups then
            -- "Already claimed" = vanilla's own assignments this tick
            -- (bb.health_pickup written at :2227 / :2252 / :2319) plus explicit
            -- slot_healthkit pickup orders (:2080-2096).
            local claimed = {}
            for _, data in pairs(side_bot_data) do
                local bb = data.blackboard
                if bb and bb.health_pickup then
                    claimed[bb.health_pickup] = true
                end
                local reservation = data.pickup_orders and data.pickup_orders.slot_healthkit
                if reservation and reservation.unit then
                    claimed[reservation.unit] = true
                end
            end

            -- Assign the leftovers -- exactly the items the human-reservation
            -- pass (:2104-2141) withheld from the bot permutation solver -- to
            -- bots vanilla left empty-handed. available_pickups was pruned of
            -- dead/expired entries by the vanilla pass this tick (:2063-2065).
            for bot_unit, data in pairs(side_bot_data) do
                local bb = data.blackboard
                local inventory_extension = bb and bb.inventory_extension
                local status_ext = data.status_extension
                -- Same bot eligibility as vanilla's valid-bot filter (:2174):
                -- alive, not parked at a respawn point, with room in
                -- slot_healthkit (empty, or stackable per can_store_additional_item).
                if inventory_extension and not bb.health_pickup
                        and HEALTH_ALIVE[bot_unit]
                        and not (status_ext and status_ext:is_ready_for_assisted_respawn()) then
                    local has_item = inventory_extension:get_slot_data("slot_healthkit")
                    local can_hold_more = inventory_extension:can_store_additional_item("slot_healthkit")
                    if not has_item or can_hold_more then
                        local bot_pos = POSITION_LOOKUP[bot_unit]
                        local best_pickup, best_dist
                        if bot_pos then
                            for pickup_unit in pairs(available_pickups) do
                                if not claimed[pickup_unit] and Unit.alive(pickup_unit) then
                                    local pickup_pos = POSITION_LOOKUP[pickup_unit]
                                    if pickup_pos then
                                        local d = Vector3.distance(bot_pos, pickup_pos)
                                        if not best_dist or d < best_dist then
                                            best_dist = d
                                            best_pickup = pickup_unit
                                        end
                                    end
                                end
                            end
                        end

                        if best_pickup then
                            -- Same blackboard writes as vanilla (:2227-2242),
                            -- INCLUDING the follow-range gate on
                            -- allowed_to_take_health_pickup (:2236): greedy bots
                            -- still only fetch items within 15 m of the team's
                            -- path, never detouring across the map.
                            bb.health_pickup = best_pickup
                            bb.health_dist = best_dist
                            bb.health_pickup_valid_until = math.huge
                            claimed[best_pickup] = true

                            local pickup_pos = POSITION_LOOKUP[best_pickup]
                            local follow_pos = data.follow_position
                            local ref_dist = (follow_pos and pickup_pos) and Vector3.distance(follow_pos, pickup_pos) or best_dist
                            bb.allowed_to_take_health_pickup = ref_dist < max_pickup_range

                            if bb.allowed_to_take_health_pickup then
                                mod:debug("[gt:bot-greedy] bot claimed a health pickup vanilla reserved for empty-slot humans (%.1fm)", best_dist)
                            end
                        end
                    end
                end
            end
        end
    end
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
    -- Bot Teleport Lab (diagnostics) D2 follow-tracker dispatch. This pair is
    -- ALREADY hooked (this FIX 9 hook_safe), so the lab CANNOT take a fresh hook
    -- (VMF would silently drop it) -- it merges here. Placed at the TOP so it
    -- fires for every follow-mode (incl. "default", which early-returns below);
    -- it reads the follow_unit vanilla just assigned. NOTE: when the user runs
    -- Follow-Host / Split mode, the block below REWRITES follow_unit later in
    -- this same tick, so D2 logs the pre-override target for those modes (the
    -- D1/D3/D4 observers show the final value). pcall-guarded + gated in the lab.
    if mod._gt_btlab_track_follow then
        mod._gt_btlab_track_follow(bot_ai_data)
    end

    local mode = _gt_resolve_follow_mode()
    local follow_host = (mode == "follow_host")
    if mode == "default" then
        -- Lab F1/F5 still get to re-point follow_unit off vanilla's assignment.
        _gt_apply_btlab_follow_override(bot_ai_data)
        return
    end
    if type(bot_ai_data) ~= "table" then return end

    local side_manager = Managers.state and Managers.state.side
    local pm = Managers.player
    if not (side_manager and pm) then return end

    local probe = next(bot_ai_data)
    if not probe then return end
    local side = side_manager.side_by_unit[probe]
    if not side then return end

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
        if not (host_unit and HEALTH_ALIVE[host_unit]) then return end   -- host dead/unit-less: leave vanilla
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
        return
    end

    local humans = _gt_split_humans_for_side(side, side_manager, host_unit)
    local num = #humans
    if num == 0 then return end

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

-- Boot-time apply: on_setting_changed doesn't fire at load, so if the user
-- already had Faster bot reactions ON, apply it now (BotConstants is a settings
-- global populated at engine boot, before mods load). Snapshots vanilla first.
if mod:get("gt_bot_fast_reactions") then
    _gt_apply_fast_reactions()
end
