--[[
wt_dev_hold_pose — Dev: Weapon Hold Pose Tuner
==============================================

Live in-game tuning of how the currently-wielded weapon is held on the local
player's isolated 1P and 3P channels. Composes independent position/rotation deltas plus an
absolute non-uniform scale over the weapon unit's captured canonical/baked
transform each frame, then
emits a Lua-pastable `unit_attachment_node_linking`-style snippet via the
`/wt_dump_hold_pose` chat command so the lead can bake the tuned numbers back
into a weapon template / spawn-data helper.

Live-apply approach (chosen)
----------------------------
Per-frame re-apply via `mod:hook_safe("StateInGameRunning", "update", ...)`.
Rationale: a one-shot weapon-root transform write is overwritten on the very
next animation tick when the engine re-applies the canonical attachment-node
pose. Hooking a per-frame state update and re-writing the local pose every
frame keeps the slider value visible. Cost is one Matrix4x4 + Vector3 +
Quaternion stack temp per frame — cheap, and we early-out when no weapon unit
is resolvable. Per-frame writes use FRESH `Vector3` / `Quaternion` stack
temporaries each call (we never store raw Q/V across frames — engine rule).

Caveat: this is local-player development tooling only. The 1P channel resolves
only `right/left_hand_wielded_unit`; the 3P channel resolves only the matching
`*_3p` fields. Inventory/hero preview, bots, remote husks, score presentation,
and baked transforms are never targeted. The dump command emits degrees-and-
metres snippets shaped like the `unit_attachment_node_linking.first_person`
and `.third_person.<kind>` arrays in
weapon_tweaker.lua (see CROSS_CHARACTER_PORT_RECIPE.md § attachment_node_linking)
plus per-frame offset / Euler fields so the lead can bake them as either a
linking-table mutation or a one-shot pose write.

Engine rules respected
----------------------
* `Unit.has_node(unit, name)` before `Unit.node(unit, name)` — node lookups
  bypass pcall (CLAUDE.md § Lua Environment, `feedback_vt2_unit_node_not_pcall_safe.md`).
* No raw `Quaternion` / `Vector3` / `Matrix4x4` storage across frames. Every
  apply call recomputes from the scalar slider values.
* `pl.player_unit` is a FIELD (chained dot), not a method call.
* `Unit.actor` / `Unit.node` are 1-indexed where relevant; local position and
  rotation setters use node `0` for the unit root (matches engine canon at
  `projectile_physics_husk_locomotion_extension.lua:65` and
  `camera_state_helper.lua:21`).

VMF widget caveats
------------------
* `numeric` widget has no `step` field — finest step is `10^-decimals_number`.
  Offset = 3 decimals = 1mm step; rotation = 1 decimal = 0.1° step.
  See memory `reference_vmf_numeric_widget_no_step.md`.
* No checkbox-button widget in stock VMF; `Apply Now` is exposed as the
  `/wt_dev_hp_apply` chat command (a one-shot pose write that's redundant
  while live-apply is enabled, but useful when the user toggles live-apply
  off via the slot-target dropdown).
]]

local mod = get_mod("wt_dev")

local M = {}

-- Weak keys keep per-unit canonical snapshots only for the lifetime of each
-- local weapon unit. The maps are channel-separated so 1P bypass/restore can
-- never consume or mutate a 3P baseline (or vice versa). Scalars and
-- QuaternionBox are safe across frames;
-- raw Vector3/Quaternion/Matrix4x4 values are never retained.
local _pose_baselines = {
    first_person = setmetatable({}, { __mode = "k" }),
    third_person = setmetatable({}, { __mode = "k" }),
}

-- ---------------------------------------------------------------------------
-- Source-node enumeration helpers
-- ---------------------------------------------------------------------------

-- Common 3P-body bones. We probe the local player's body at install time and
-- keep only nodes that actually exist; fall back to this static list if the
-- player unit isn't available yet (install runs before any mission spawn).
local _COMMON_BONES = {
    "root",
    "j_hips",
    "j_spine", "j_spine1", "j_spine2",
    "j_neck", "j_head",
    "j_leftshoulder", "j_rightshoulder",
    "j_leftupperarm", "j_rightupperarm",
    "j_leftforearm", "j_rightforearm",
    "j_lefthand", "j_righthand",
    "j_lefthandattach", "j_righthandattach",
    "j_leftweaponattach", "j_rightweaponattach",
    "j_leftthigh", "j_rightthigh",
    "j_leftcalf", "j_rightcalf",
    "j_leftfoot", "j_rightfoot",
    "j_lefttoe", "j_righttoe",
}

local function _enumerate_source_nodes()
    -- Try to probe the local player's 3P body. If unavailable, fall back
    -- to the static list — the dropdown is regenerated only at install time
    -- (VMF dropdown options table mutation post-init doesn't refresh the
    -- open widget, see VMF_RECIPES § dropdown options mutation), so we just
    -- ship the union.
    local probed = {}
    local seen = {}
    local pm = Managers and Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    local punit = lp and lp.player_unit
    if punit and Unit.alive and Unit.alive(punit) then
        for _, name in ipairs(_COMMON_BONES) do
            if Unit.has_node(punit, name) and not seen[name] then
                probed[#probed + 1] = name
                seen[name] = true
            end
        end
    end
    -- Always add any unprobed bones from the static list (so the dropdown
    -- isn't empty when invoked from the keep before the player unit exists).
    for _, name in ipairs(_COMMON_BONES) do
        if not seen[name] then
            probed[#probed + 1] = name
            seen[name] = true
        end
    end
    local opts = {}
    for i, name in ipairs(probed) do
        opts[i] = { text = name, value = name }
    end
    return opts
end

-- ---------------------------------------------------------------------------
-- Wielded-weapon-unit resolution
-- ---------------------------------------------------------------------------

-- Returns:
--   weapon_unit, hand, slot_name, item_key
-- ...where hand is "right" or "left", slot_name is "slot_ranged"/"slot_melee"/
-- whatever the player is currently wielding, and item_key is the IML key.
-- Any failure returns nil.
local function _resolve_wielded(target_slot, target_hand, channel)
    local pm = Managers and Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    local punit = lp and lp.player_unit
    if not punit then return nil end

    local inv = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(punit, "inventory_system")
    if not inv then return nil end

    -- Determine which slot to target.
    local slot_name
    if target_slot == "auto" or target_slot == nil then
        slot_name = inv.get_wielded_slot_name and inv:get_wielded_slot_name()
    else
        slot_name = target_slot
    end
    if not slot_name then return nil end

    local equipment = inv._equipment
    if not equipment then return nil end

    -- If the requested slot IS the currently-wielded slot, prefer the
    -- ._equipment.<hand>_hand_wielded_unit_3p fields (these are the live
    -- ones the engine is currently attaching). If not currently wielded,
    -- pull from slot_data.<hand>_unit_3p instead.
    local current_wielded = equipment.wielded_slot
    local right_unit, left_unit
    if slot_name == current_wielded then
        if channel == "first_person" then
            right_unit = equipment.right_hand_wielded_unit
            left_unit  = equipment.left_hand_wielded_unit
        else
            right_unit = equipment.right_hand_wielded_unit_3p
            left_unit  = equipment.left_hand_wielded_unit_3p
        end
    else
        local slot_data = equipment.slots and equipment.slots[slot_name]
        if slot_data then
            if channel == "first_person" then
                right_unit = slot_data.right_unit_1p
                left_unit  = slot_data.left_unit_1p
            else
                right_unit = slot_data.right_unit_3p
                left_unit  = slot_data.left_unit_3p
            end
        end
    end

    local item_key
    do
        local slot_data = equipment.slots and equipment.slots[slot_name]
        item_key = slot_data and (slot_data.id
            or (slot_data.item_data and slot_data.item_data.key))
    end

    -- Pick the hand. "both" returns whichever one exists first; the apply
    -- loop iterates over hands separately to cover both when "both" is set.
    if target_hand == "left" then
        if left_unit and Unit.alive(left_unit) then
            return left_unit, "left", slot_name, item_key
        end
    elseif target_hand == "right" then
        if right_unit and Unit.alive(right_unit) then
            return right_unit, "right", slot_name, item_key
        end
    else  -- "both" — return right first (most common single-handed case)
        if right_unit and Unit.alive(right_unit) then
            return right_unit, "right", slot_name, item_key
        end
        if left_unit and Unit.alive(left_unit) then
            return left_unit, "left", slot_name, item_key
        end
    end
    return nil, nil, slot_name, item_key
end

-- Returns the local player's career key (e.g. "es_knight"), or "<unknown>".
local function _local_career()
    local pm = Managers and Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    local punit = lp and lp.player_unit
    if not punit then return "<unknown>" end
    local career_ext = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(punit, "career_system")
    if career_ext and career_ext.career_name then
        local ok, name = pcall(career_ext.career_name, career_ext)
        if ok and name then return name end
    end
    local inv = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(punit, "inventory_system")
    if inv and inv._career_name then return inv._career_name end
    return "<unknown>"
end

-- ---------------------------------------------------------------------------
-- Pose application
-- ---------------------------------------------------------------------------

-- Read one channel/hand's nine transform values. The keys are written
-- out LITERALLY per hand: the mod-lint save-restore check pairs each
-- /wt_dev_hp_reset `mod:set("KEY", ...)` with a literal `mod:get("KEY")` in
-- this file, and a concatenated `"wt_dev_hp_"..p..` key is invisible to it
-- (it reads as the truncated literal `"wt_dev_hp_"`).
local function _read_sliders(channel, hand)
    if channel == "third_person" and hand == "right" then
        return mod:get("wt_dev_hp_rh_offset_x") or 0,
               mod:get("wt_dev_hp_rh_offset_y") or 0,
               mod:get("wt_dev_hp_rh_offset_z") or 0,
               mod:get("wt_dev_hp_rh_rot_pitch") or 0,
               mod:get("wt_dev_hp_rh_rot_yaw")   or 0,
               mod:get("wt_dev_hp_rh_rot_roll")  or 0,
               mod:get("wt_dev_hp_rh_scale_x") or 1,
               mod:get("wt_dev_hp_rh_scale_y") or 1,
               mod:get("wt_dev_hp_rh_scale_z") or 1
    elseif channel == "third_person" then
        return mod:get("wt_dev_hp_lh_offset_x") or 0,
           mod:get("wt_dev_hp_lh_offset_y") or 0,
           mod:get("wt_dev_hp_lh_offset_z") or 0,
           mod:get("wt_dev_hp_lh_rot_pitch") or 0,
           mod:get("wt_dev_hp_lh_rot_yaw")   or 0,
           mod:get("wt_dev_hp_lh_rot_roll")  or 0,
           mod:get("wt_dev_hp_lh_scale_x") or 1,
           mod:get("wt_dev_hp_lh_scale_y") or 1,
               mod:get("wt_dev_hp_lh_scale_z") or 1
    elseif hand == "right" then
        return mod:get("wt_dev_hp_fp_rh_offset_x") or 0,
               mod:get("wt_dev_hp_fp_rh_offset_y") or 0,
               mod:get("wt_dev_hp_fp_rh_offset_z") or 0,
               mod:get("wt_dev_hp_fp_rh_rot_pitch") or 0,
               mod:get("wt_dev_hp_fp_rh_rot_yaw")   or 0,
               mod:get("wt_dev_hp_fp_rh_rot_roll")  or 0,
               mod:get("wt_dev_hp_fp_rh_scale_x") or 1,
               mod:get("wt_dev_hp_fp_rh_scale_y") or 1,
               mod:get("wt_dev_hp_fp_rh_scale_z") or 1
    end
    return mod:get("wt_dev_hp_fp_lh_offset_x") or 0,
           mod:get("wt_dev_hp_fp_lh_offset_y") or 0,
           mod:get("wt_dev_hp_fp_lh_offset_z") or 0,
           mod:get("wt_dev_hp_fp_lh_rot_pitch") or 0,
           mod:get("wt_dev_hp_fp_lh_rot_yaw")   or 0,
           mod:get("wt_dev_hp_fp_lh_rot_roll")  or 0,
           mod:get("wt_dev_hp_fp_lh_scale_x") or 1,
           mod:get("wt_dev_hp_fp_lh_scale_y") or 1,
           mod:get("wt_dev_hp_fp_lh_scale_z") or 1
end

-- True when every Hold-Pose slider is at identity: position/rotation zero and
-- scale one. Returning a tuned component to identity restores its captured
-- baseline once; subsequent frames are a true no-op.
local function _pose_is_default(channel, hand)
    local ox, oy, oz, pitch_deg, yaw_deg, roll_deg, sx, sy, sz = _read_sliders(channel, hand)
    return ox == 0 and oy == 0 and oz == 0
       and pitch_deg == 0 and yaw_deg == 0 and roll_deg == 0
       and sx == 1 and sy == 1 and sz == 1
end

-- Split the slider state into independent transform components. This is a
-- pure seam used by the runtime and #569 regression: an omitted/zero position
-- component must never cause a rotation write, and vice versa.
local function _component_plan_values(ox, oy, oz, pitch_deg, yaw_deg, roll_deg, sx, sy, sz)
    sx, sy, sz = sx or 1, sy or 1, sz or 1
    return {
        position = ox ~= 0 or oy ~= 0 or oz ~= 0,
        rotation = pitch_deg ~= 0 or yaw_deg ~= 0 or roll_deg ~= 0,
        scale = sx ~= 1 or sy ~= 1 or sz ~= 1,
        ox = ox, oy = oy, oz = oz,
        pitch = pitch_deg, yaw = yaw_deg, roll = roll_deg,
        sx = sx, sy = sy, sz = sz,
    }
end
local function _component_plan(channel, hand)
    return _component_plan_values(_read_sliders(channel, hand))
end
M._component_plan = _component_plan
M._component_plan_values = _component_plan_values
M._pose_contract = {
    mode = "canonical_plus_delta",
    position_setter = "Unit.set_local_position",
    rotation_setter = "Unit.set_local_rotation",
    scale_setter = "Unit.set_local_scale",
    scale_mode = "absolute",
    scope = "local_player_isolated_1p_3p",
    channels = { first_person = true, third_person = true },
    excluded_surfaces = {
        inventory_preview = true, hero_preview = true, bots = true,
        remote_husks = true, score = true, baked_transforms = true,
    },
    bypass = "restore_channel_baseline_without_erasing_settings",
    compounds = false,
}

local function _capture_baseline(weapon_unit, channel)
    local ok_pos, pos = pcall(Unit.local_position, weapon_unit, 0)
    local ok_rot, rot = pcall(Unit.local_rotation, weapon_unit, 0)
    local ok_scale, scale = pcall(Unit.local_scale, weapon_unit, 0)
    -- #569 owns an explicit canonical+half-turn rotation for tracked WP-remap
    -- units. Query that authoritative pose so capture is correct regardless of
    -- hook ordering; unrelated local units keep their live canonical rotation.
    if channel == "third_person" and mod._wt569_desired_rotation_for_unit then
        local ok_569, desired_569 = pcall(mod._wt569_desired_rotation_for_unit, weapon_unit)
        if ok_569 and desired_569 then
            rot, ok_rot = desired_569, true
        end
    end
    if not ok_pos or not pos or not ok_rot or not rot
            or not ok_scale or not scale then return nil end
    local row = {
        px = pos[1], py = pos[2], pz = pos[3],
        sx = scale[1], sy = scale[2], sz = scale[3],
        rotation = QuaternionBox(rot),
        position_dirty = false,
        rotation_dirty = false,
        scale_dirty = false,
    }
    _pose_baselines[channel][weapon_unit] = row
    return row
end

-- Apply independent values to one local 3P weapon root. Position, rotation,
-- and scale use separate setters so changing one component cannot reset either
-- of the others. Position/rotation are deltas from the captured baseline;
-- scale is the absolute authored value shown in the tuner. Every desired value
-- is rebuilt from scalars, never the previous tuner result, so repeated
-- frames/commands do not compound.
--
-- DEFER-TO-BAKED: with no cached dirty component, the identity sliders do not
-- capture or write anything. A dirty component returning to zero restores its
-- captured baseline exactly once, then becomes a no-op.
local function _apply_pose_to(weapon_unit, channel, hand)
    if not weapon_unit then return false end
    if not Unit.alive(weapon_unit) then return false end
    local plan = _component_plan(channel, hand)
    local channel_baselines = _pose_baselines[channel]
    local row = channel_baselines[weapon_unit]
    if not row and not plan.position and not plan.rotation and not plan.scale then return false end
    row = row or _capture_baseline(weapon_unit, channel)
    if not row then return false end

    local plan_key = tostring(plan.position) .. "/" .. tostring(plan.rotation)
        .. "/" .. tostring(plan.scale)
    if row.last_plan ~= plan_key then
        row.last_plan = plan_key
        pcall(printf,
            "[wt:616] hold-pose compose channel=%s hand=%s position=%s rotation=%s scale=%s base=canonical_or_baked compounds=false",
            channel, hand, tostring(plan.position), tostring(plan.rotation), tostring(plan.scale))
    end

    local wrote = false
    if plan.position then
        local desired_pos = Vector3(row.px + plan.ox, row.py + plan.oy, row.pz + plan.oz)
        local ok = pcall(Unit.set_local_position, weapon_unit, 0, desired_pos)
        row.position_dirty = ok or row.position_dirty
        wrote = ok or wrote
    elseif row.position_dirty then
        local base_pos = Vector3(row.px, row.py, row.pz)
        local ok = pcall(Unit.set_local_position, weapon_unit, 0, base_pos)
        if ok then row.position_dirty = false end
        wrote = ok or wrote
    end

    if plan.rotation then
        -- Stingray Quaternion.from_euler_angles_xyz takes DEGREES (vanilla
        -- crawl_space_extension.lua:14 passes 90). Delta is post-multiplied in
        -- the captured local frame, matching #569's canonical*correction order.
        local delta = Quaternion.from_euler_angles_xyz(plan.pitch, plan.yaw, plan.roll)
        local desired_rot = Quaternion.multiply(row.rotation:unbox(), delta)
        local ok = pcall(Unit.set_local_rotation, weapon_unit, 0, desired_rot)
        row.rotation_dirty = ok or row.rotation_dirty
        wrote = ok or wrote
    elseif row.rotation_dirty then
        local ok = pcall(Unit.set_local_rotation, weapon_unit, 0, row.rotation:unbox())
        if ok then row.rotation_dirty = false end
        wrote = ok or wrote
    end

    if plan.scale then
        local desired_scale = Vector3(plan.sx, plan.sy, plan.sz)
        local ok = pcall(Unit.set_local_scale, weapon_unit, 0, desired_scale)
        row.scale_dirty = ok or row.scale_dirty
        wrote = ok or wrote
    elseif row.scale_dirty then
        local base_scale = Vector3(row.sx, row.sy, row.sz)
        local ok = pcall(Unit.set_local_scale, weapon_unit, 0, base_scale)
        if ok then row.scale_dirty = false end
        wrote = ok or wrote
    end
    return wrote
end

local function _restore_channel(channel)
    local restored = 0
    local channel_baselines = _pose_baselines[channel]
    for unit, row in pairs(channel_baselines) do
        local ok_alive, alive = pcall(Unit.alive, unit)
        if ok_alive and alive then
            if row.position_dirty then
                local pos = Vector3(row.px, row.py, row.pz)
                if pcall(Unit.set_local_position, unit, 0, pos) then restored = restored + 1 end
            end
            if row.rotation_dirty then
                if pcall(Unit.set_local_rotation, unit, 0, row.rotation:unbox()) then restored = restored + 1 end
            end
            if row.scale_dirty then
                local scale = Vector3(row.sx, row.sy, row.sz)
                if pcall(Unit.set_local_scale, unit, 0, scale) then restored = restored + 1 end
            end
        end
        channel_baselines[unit] = nil
    end
    return restored
end

local function _restore_cached_poses()
    return _restore_channel("first_person") + _restore_channel("third_person")
end

local function _channel_enabled(channel)
    if mod:get("wt_dev_hp_enabled") ~= true then return false end
    if channel == "first_person" then
        return mod:get("wt_dev_hp_enable_1p") == true
    end
    return mod:get("wt_dev_hp_enable_3p") ~= false
end

local function _channel_policy_values(master_enabled, enable_1p, enable_3p)
    return {
        master = master_enabled == true,
        first_person = master_enabled == true and enable_1p == true,
        third_person = master_enabled == true and enable_3p ~= false,
        preserves_settings = true,
        restores_baseline_on_bypass = true,
    }
end
M._channel_policy_values = _channel_policy_values

-- Route settings to the render channel they author.  This is deliberately
-- exact: the unprefixed RH/LH sliders belong to local third person, while the
-- `fp_` sliders belong to first person.  Keeping this classifier pure gives
-- the offline suite a regression seam for the setting-to-render contract.
local function _setting_channel(setting_id)
    if type(setting_id) ~= "string" then return nil end
    if setting_id == "wt_dev_hp_target_slot" then return "both" end
    if setting_id:match("^wt_dev_hp_fp_[rl]h_") then return "first_person" end
    if setting_id:match("^wt_dev_hp_[rl]h_") then return "third_person" end
    return nil
end
M._setting_channel = _setting_channel

M._live_delivery_contract = {
    setting_dispatch = "channel_exact",
    immediate_apply = true,
    bypass_preserves_values = true,
    bypass_does_not_apply = true,
}

local _edit_diag_seen = {}
local _edit_diag_total = 0
local _EDIT_DIAG_CAP = 48

local function _edit_diag(setting_id, channel, outcome, applied)
    local token = table.concat({ tostring(setting_id), tostring(channel), tostring(outcome), tostring(applied) }, "|")
    if _edit_diag_seen[token] or _edit_diag_total >= _EDIT_DIAG_CAP then return end
    _edit_diag_seen[token] = true
    _edit_diag_total = _edit_diag_total + 1
    pcall(printf,
        "[wt:616] tuner edit %s setting=%s channel=%s applied=%s master=%s 1p=%s 3p=%s",
        tostring(outcome), tostring(setting_id), tostring(channel), tostring(applied),
        tostring(mod:get("wt_dev_hp_enabled") == true),
        tostring(mod:get("wt_dev_hp_enable_1p") == true),
        tostring(mod:get("wt_dev_hp_enable_3p") ~= false))
end

-- Apply each hand's pose from ITS OWN sliders, independently. No hand
-- dropdown, no "both" mode — RH sliders drive the right-hand unit, LH sliders
-- drive the left-hand unit, each gated by its own defer-to-baked guard.
local function _apply_channel(channel)
    if not _channel_enabled(channel) then return false end
    local target_slot = mod:get("wt_dev_hp_target_slot") or "auto"
    local applied = false
    local u_r = select(1, _resolve_wielded(target_slot, "right", channel))
    if u_r then applied = _apply_pose_to(u_r, channel, "right") or applied end
    local u_l = select(1, _resolve_wielded(target_slot, "left", channel))
    if u_l then applied = _apply_pose_to(u_l, channel, "left") or applied end
    return applied
end

local function _apply_pose_all()
    local applied_1p = _apply_channel("first_person")
    local applied_3p = _apply_channel("third_person")
    return applied_1p or applied_3p
end

-- ---------------------------------------------------------------------------
-- Dump command output
-- ---------------------------------------------------------------------------

local function _dump_snippet()
    local target_slot = mod:get("wt_dev_hp_target_slot") or "auto"
    local target_kind = mod:get("wt_dev_hp_target_kind") or "wielded"
    -- source_node stays a single dropdown: use it as the RIGHT-hand source and
    -- the canonical j_lefthand bone as the LEFT-hand source.
    local source_node = mod:get("wt_dev_hp_source_node") or "j_righthand"
    local career = _local_career()

    -- One entry per hand. Both channels are dumped even when bypassed so a
    -- disable/enable round-trip never discards authored values.
    local HANDS = {
        { hand = "right", src = source_node },
        { hand = "left",  src = "j_lefthand" },
    }
    local CHANNELS = {
        { key = "first_person", table_name = "_custom_first_person" },
        { key = "third_person", table_name = "_custom_third_person" },
    }

    mod:info("-- ==== wt Hold Pose dump ====")
    mod:info("-- character=%s  slot=%s  kind=%s", career, tostring(target_slot), tostring(target_kind))
    for _, channel in ipairs(CHANNELS) do
        mod:info("-- channel=%s enabled=%s", channel.key, tostring(_channel_enabled(channel.key)))
        mod:info("local %s = {", channel.table_name)
        for _, h in ipairs(HANDS) do
            local ox, oy, oz, pitch_deg, yaw_deg, roll_deg, sx, sy, sz =
                _read_sliders(channel.key, h.hand)
            local resolved_unit, hand, slot_name, item_key =
                _resolve_wielded(target_slot, h.hand, channel.key)
            local non_default = not _pose_is_default(channel.key, h.hand)

            if resolved_unit or non_default then
                hand      = hand      or h.hand
                slot_name = slot_name or target_slot
                item_key  = item_key  or "<unknown>"
                mod:info("    -- hand=%s  weapon=%s  slot=%s  source_node=%s",
                    tostring(hand), tostring(item_key), tostring(slot_name), tostring(h.src))
                mod:info("    -- Sliders: offset_xyz=(%.3f, %.3f, %.3f) m  rot_pyr=(%.1f, %.1f, %.1f) deg",
                    ox, oy, oz, pitch_deg, yaw_deg, roll_deg)
                mod:info("    -- Scale: scale_xyz=(%.3f, %.3f, %.3f) absolute", sx, sy, sz)
                mod:info("    {")
                mod:info("        source = %q,", h.src)
                mod:info("        target = 0,")
                mod:info("        offset = { %.3f, %.3f, %.3f },", ox, oy, oz)
                mod:info("        rotation = { pitch = %.1f, yaw = %.1f, roll = %.1f },  -- degrees, Euler XYZ",
                    pitch_deg, yaw_deg, roll_deg)
                mod:info("        scale = { %.3f, %.3f, %.3f },  -- absolute, non-compounding", sx, sy, sz)
                mod:info("    },")
            end
        end
        mod:info("}")
    end
    mod:info("-- Apply position/rotation as deltas and scale as absolute (per hand):")
    mod:info("--   Unit.set_local_position(unit, 0, base_pos + Vector3(offset_x, offset_y, offset_z))")
    mod:info("--   Unit.set_local_rotation(unit, 0, Quaternion.multiply(base_rot, Quaternion.from_euler_angles_xyz(pitch, yaw, roll)))")
    mod:info("--   Unit.set_local_scale(unit, 0, Vector3(scale_x, scale_y, scale_z))")
    mod:info("-- ==== end dump ====")
end

-- ---------------------------------------------------------------------------
-- Public: widget tree
-- ---------------------------------------------------------------------------

function M.build_widget_tree()
    local source_node_options = _enumerate_source_nodes()

    return {
        setting_id = "wt_dev_hold_pose",
        type = "group",
        sub_widgets = {
            {
                -- Master bypass is intentionally first and outside both render
                -- channel collapsibles so the tuner can be disabled at a glance.
                setting_id = "wt_dev_hp_enabled",
                type = "checkbox",
                default_value = false,
            },
            {
                setting_id = "wt_dev_hp_target_slot",
                type = "dropdown",
                default_value = "auto",
                options = {
                    { text = "Auto (currently wielded)", value = "auto" },
                    { text = "Ranged",                   value = "slot_ranged" },
                    { text = "Melee",                    value = "slot_melee" },
                },
            },
            {
                setting_id = "wt_dev_hp_target_kind",
                type = "dropdown",
                default_value = "wielded",
                options = {
                    { text = "Wielded",   value = "wielded" },
                    { text = "Display",   value = "display" },
                    { text = "Unwielded", value = "unwielded" },
                    { text = "All",       value = "all" },
                },
            },
            {
                setting_id = "wt_dev_hp_source_node",
                type = "dropdown",
                default_value = "j_righthand",
                options = source_node_options,
            },
            {
                setting_id = "wt_dev_hp_3p_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "wt_dev_hp_enable_3p",
                        type = "checkbox",
                        default_value = true,
                    },
                    -- RIGHT-hand pose sliders (drive right_unit_3p independently).
                    {
                        setting_id = "wt_dev_hp_rh_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "wt_dev_hp_rh_offset_x", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_rh_offset_y", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_rh_offset_z", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_rh_rot_pitch", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_rh_rot_yaw", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_rh_rot_roll", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_rh_scale_x", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_rh_scale_y", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_rh_scale_z", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                        },
                    },
                    -- LEFT-hand pose sliders (drive left_unit_3p independently).
                    {
                        setting_id = "wt_dev_hp_lh_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "wt_dev_hp_lh_offset_x", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_lh_offset_y", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_lh_offset_z", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_lh_rot_pitch", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_lh_rot_yaw", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_lh_rot_roll", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_lh_scale_x", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_lh_scale_y", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_lh_scale_z", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                        },
                    },
                },
            },
            {
                setting_id = "wt_dev_hp_1p_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "wt_dev_hp_enable_1p",
                        type = "checkbox",
                        default_value = false,
                    },
                    {
                        setting_id = "wt_dev_hp_fp_rh_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "wt_dev_hp_fp_rh_offset_x", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_fp_rh_offset_y", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_fp_rh_offset_z", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_fp_rh_rot_pitch", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_fp_rh_rot_yaw", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_fp_rh_rot_roll", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_fp_rh_scale_x", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_fp_rh_scale_y", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_fp_rh_scale_z", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                        },
                    },
                    {
                        setting_id = "wt_dev_hp_fp_lh_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "wt_dev_hp_fp_lh_offset_x", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_fp_lh_offset_y", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_fp_lh_offset_z", type = "numeric", default_value = 0, range = { -1.0, 1.0 }, decimals_number = 3, unit_text = " m" },
                            { setting_id = "wt_dev_hp_fp_lh_rot_pitch", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_fp_lh_rot_yaw", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_fp_lh_rot_roll", type = "numeric", default_value = 0, range = { -180.0, 180.0 }, decimals_number = 1, unit_text = " deg" },
                            { setting_id = "wt_dev_hp_fp_lh_scale_x", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_fp_lh_scale_y", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                            { setting_id = "wt_dev_hp_fp_lh_scale_z", type = "numeric", default_value = 1, range = { 0.01, 3.0 }, decimals_number = 3, unit_text = " x" },
                        },
                    },
                },
            },
            {
                -- Live re-apply gate. When false, the per-frame hook is a no-op
                -- and the user must `/wt_dev_hp_apply` for a one-shot write
                -- (or `/wt_dump_hold_pose` to print the snippet without
                -- mutating the live unit).
                -- DEFAULTS TO FALSE (primary defer-to-baked guard): with
                -- live-apply off at stock, the per-frame hook early-returns and
                -- NEVER touches the weapon unit, so baked grip offsets
                -- (weapon_tweaker.lua _weapon_grip_offsets / the durable
                -- per-frame re-apply) survive untouched. The user enables this
                -- deliberately when tuning. (Belt-and-suspenders: _apply_pose_to
                -- also no-ops when all sliders are 0, so even with this on an
                -- untouched tool won't clobber the bake.)
                setting_id = "wt_dev_hp_live_apply",
                type = "checkbox",
                default_value = false,
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- Public: localization keys
-- ---------------------------------------------------------------------------

function M.loc_keys()
    return {
        wt_dev_hold_pose      = { en = "Dev: Weapon Hold Pose Tuner" },
        wt_dev_hp_enabled     = { en = "Enable Hold-Pose Tuner" },
        wt_dev_hp_enabled_description = { en = "OFF bypasses all position, rotation, and scale changes while preserving every saved value." },
        wt_dev_hp_target_slot = { en = "Target slot" },
        wt_dev_hp_target_kind = { en = "Linking-table kind (for dump)" },
        wt_dev_hp_source_node = { en = "Source node (3P body bone)" },
        wt_dev_hp_3p_group       = { en = "Third Person" },
        wt_dev_hp_enable_3p      = { en = "Enable third-person tuner" },
        wt_dev_hp_rh_group       = { en = "Right hand" },
        wt_dev_hp_rh_offset_x    = { en = "RH Offset X (metres)" },
        wt_dev_hp_rh_offset_y    = { en = "RH Offset Y (metres)" },
        wt_dev_hp_rh_offset_z    = { en = "RH Offset Z (metres)" },
        wt_dev_hp_rh_rot_pitch   = { en = "RH Rotation pitch (deg, Euler X)" },
        wt_dev_hp_rh_rot_yaw     = { en = "RH Rotation yaw (deg, Euler Y)" },
        wt_dev_hp_rh_rot_roll    = { en = "RH Rotation roll (deg, Euler Z)" },
        wt_dev_hp_rh_scale_x     = { en = "RH Scale X (absolute)" },
        wt_dev_hp_rh_scale_y     = { en = "RH Scale Y (absolute)" },
        wt_dev_hp_rh_scale_z     = { en = "RH Scale Z (absolute)" },
        wt_dev_hp_lh_group       = { en = "Left hand" },
        wt_dev_hp_lh_offset_x    = { en = "LH Offset X (metres)" },
        wt_dev_hp_lh_offset_y    = { en = "LH Offset Y (metres)" },
        wt_dev_hp_lh_offset_z    = { en = "LH Offset Z (metres)" },
        wt_dev_hp_lh_rot_pitch   = { en = "LH Rotation pitch (deg, Euler X)" },
        wt_dev_hp_lh_rot_yaw     = { en = "LH Rotation yaw (deg, Euler Y)" },
        wt_dev_hp_lh_rot_roll    = { en = "LH Rotation roll (deg, Euler Z)" },
        wt_dev_hp_lh_scale_x     = { en = "LH Scale X (absolute)" },
        wt_dev_hp_lh_scale_y     = { en = "LH Scale Y (absolute)" },
        wt_dev_hp_lh_scale_z     = { en = "LH Scale Z (absolute)" },
        wt_dev_hp_1p_group          = { en = "First Person" },
        wt_dev_hp_enable_1p         = { en = "Enable first-person tuner" },
        wt_dev_hp_fp_rh_group       = { en = "First-person right hand" },
        wt_dev_hp_fp_rh_offset_x    = { en = "1P RH Offset X (metres)" },
        wt_dev_hp_fp_rh_offset_y    = { en = "1P RH Offset Y (metres)" },
        wt_dev_hp_fp_rh_offset_z    = { en = "1P RH Offset Z (metres)" },
        wt_dev_hp_fp_rh_rot_pitch   = { en = "1P RH Rotation pitch (deg, Euler X)" },
        wt_dev_hp_fp_rh_rot_yaw     = { en = "1P RH Rotation yaw (deg, Euler Y)" },
        wt_dev_hp_fp_rh_rot_roll    = { en = "1P RH Rotation roll (deg, Euler Z)" },
        wt_dev_hp_fp_rh_scale_x     = { en = "1P RH Scale X (absolute)" },
        wt_dev_hp_fp_rh_scale_y     = { en = "1P RH Scale Y (absolute)" },
        wt_dev_hp_fp_rh_scale_z     = { en = "1P RH Scale Z (absolute)" },
        wt_dev_hp_fp_lh_group       = { en = "First-person left hand" },
        wt_dev_hp_fp_lh_offset_x    = { en = "1P LH Offset X (metres)" },
        wt_dev_hp_fp_lh_offset_y    = { en = "1P LH Offset Y (metres)" },
        wt_dev_hp_fp_lh_offset_z    = { en = "1P LH Offset Z (metres)" },
        wt_dev_hp_fp_lh_rot_pitch   = { en = "1P LH Rotation pitch (deg, Euler X)" },
        wt_dev_hp_fp_lh_rot_yaw     = { en = "1P LH Rotation yaw (deg, Euler Y)" },
        wt_dev_hp_fp_lh_rot_roll    = { en = "1P LH Rotation roll (deg, Euler Z)" },
        wt_dev_hp_fp_lh_scale_x     = { en = "1P LH Scale X (absolute)" },
        wt_dev_hp_fp_lh_scale_y     = { en = "1P LH Scale Y (absolute)" },
        wt_dev_hp_fp_lh_scale_z     = { en = "1P LH Scale Z (absolute)" },
        wt_dev_hp_live_apply  = { en = "Live re-apply every frame" },
    }
end

-- ---------------------------------------------------------------------------
-- Public: install (hooks + chat commands)
-- ---------------------------------------------------------------------------

function M.install()
    -- Per-frame re-apply. StateInGameRunning.update is the canonical
    -- mission-time tick; it does NOT fire in the keep, so keep-side tuning
    -- relies on the `/wt_dev_hp_apply` one-shot command. (The keep-side
    -- preview is a MenuWorldPreviewer-driven scene; tuning that surface
    -- would need a separate hook target — out of scope for v1, document
    -- the limitation.)
    mod:hook_safe("StateInGameRunning", "update", function(self, dt, t)
        -- Bypass is restorative, not destructive. Polling makes the restore
        -- robust even when another settings surface bypasses on_setting_changed.
        if not _channel_enabled("first_person") then _restore_channel("first_person") end
        if not _channel_enabled("third_person") then _restore_channel("third_person") end
        if not mod:get("wt_dev_hp_live_apply") then return end
        _apply_pose_all()
    end)

    -- One-shot apply (works in keep too — useful when live-apply is off,
    -- or for re-asserting after a wield).
    mod:command("wt_dev_hp_apply",
        "Apply the current Hold-Pose slider values once to the wielded weapon.",
        function()
            local ok = _apply_pose_all()
            if ok then
                mod:echo("[wt_dev_hp] applied pose to wielded weapon")
            else
                mod:warning("[wt_dev_hp] no wielded weapon unit resolvable "
                    .. "(no local player / not in mission / hand empty)")
            end
        end)

    -- Dump command — prints a Lua-pastable snippet to the log.
    mod:command("wt_dump_hold_pose",
        "Dump the current Hold-Pose tuner values as a Lua snippet for the lead.",
        function()
            _dump_snippet()
            mod:echo("[wt_dev_hp] dumped hold-pose snippet -- see console log")
        end)

    -- Quick reset to identity (offset/rotation zero, scale one) for both
    -- channels. This is intentionally distinct from bypass: the enable
    -- toggles never call this command and therefore never erase saved values.
    mod:command("wt_dev_hp_reset",
        "Reset Hold-Pose sliders (both hands) to identity transform.",
        function()
            mod:set("wt_dev_hp_rh_offset_x", 0)
            mod:set("wt_dev_hp_rh_offset_y", 0)
            mod:set("wt_dev_hp_rh_offset_z", 0)
            mod:set("wt_dev_hp_rh_rot_pitch", 0)
            mod:set("wt_dev_hp_rh_rot_yaw",   0)
            mod:set("wt_dev_hp_rh_rot_roll",  0)
            mod:set("wt_dev_hp_rh_scale_x", 1)
            mod:set("wt_dev_hp_rh_scale_y", 1)
            mod:set("wt_dev_hp_rh_scale_z", 1)
            mod:set("wt_dev_hp_lh_offset_x", 0)
            mod:set("wt_dev_hp_lh_offset_y", 0)
            mod:set("wt_dev_hp_lh_offset_z", 0)
            mod:set("wt_dev_hp_lh_rot_pitch", 0)
            mod:set("wt_dev_hp_lh_rot_yaw",   0)
            mod:set("wt_dev_hp_lh_rot_roll",  0)
            mod:set("wt_dev_hp_lh_scale_x", 1)
            mod:set("wt_dev_hp_lh_scale_y", 1)
            mod:set("wt_dev_hp_lh_scale_z", 1)
            mod:set("wt_dev_hp_fp_rh_offset_x", 0)
            mod:set("wt_dev_hp_fp_rh_offset_y", 0)
            mod:set("wt_dev_hp_fp_rh_offset_z", 0)
            mod:set("wt_dev_hp_fp_rh_rot_pitch", 0)
            mod:set("wt_dev_hp_fp_rh_rot_yaw",   0)
            mod:set("wt_dev_hp_fp_rh_rot_roll",  0)
            mod:set("wt_dev_hp_fp_rh_scale_x", 1)
            mod:set("wt_dev_hp_fp_rh_scale_y", 1)
            mod:set("wt_dev_hp_fp_rh_scale_z", 1)
            mod:set("wt_dev_hp_fp_lh_offset_x", 0)
            mod:set("wt_dev_hp_fp_lh_offset_y", 0)
            mod:set("wt_dev_hp_fp_lh_offset_z", 0)
            mod:set("wt_dev_hp_fp_lh_rot_pitch", 0)
            mod:set("wt_dev_hp_fp_lh_rot_yaw",   0)
            mod:set("wt_dev_hp_fp_lh_rot_roll",  0)
            mod:set("wt_dev_hp_fp_lh_scale_x", 1)
            mod:set("wt_dev_hp_fp_lh_scale_y", 1)
            mod:set("wt_dev_hp_fp_lh_scale_z", 1)
            local restored = _restore_cached_poses()
            -- mod:set from non-on_setting_changed paths updates the store
            -- but the open widget doesn't refresh until view re-open (see
            -- VMF_RECIPES § checkbox cached display state). The pose itself
            -- DOES re-apply correctly because _apply_pose_all reads via
            -- mod:get on the next frame.
            mod:echo("[wt_dev_hp] sliders reset to identity; restored %d pose component(s) "
                .. "(close + reopen settings to see the UI update)", restored)
        end)

    mod:info("[wt_dev_hp] Dev: Weapon Hold Pose Tuner installed -- "
        .. "isolated 1P/3P channels with non-destructive bypass, live-apply per-frame, /wt_dev_hp_apply for one-shot, "
        .. "/wt_dump_hold_pose to dump a snippet, /wt_dev_hp_reset to identity.")
end

function M.on_setting_changed(setting_id)
    if setting_id == "wt_dev_hp_enabled" then
        if mod:get("wt_dev_hp_enabled") ~= true then
            local restored = _restore_cached_poses()
            pcall(printf, "[wt:616] tuner master bypass restored=%d values_preserved=true", restored)
        else
            local applied = _apply_pose_all()
            pcall(printf, "[wt:616] tuner master enabled values_restored=true applied=%s", tostring(applied))
        end
    elseif setting_id == "wt_dev_hp_enable_1p" then
        if not _channel_enabled("first_person") then
            local restored = _restore_channel("first_person")
            pcall(printf, "[wt:616] tuner bypass channel=first_person restored=%d values_preserved=true", restored)
        else
            local applied = _apply_channel("first_person")
            pcall(printf, "[wt:616] tuner enabled channel=first_person values_restored=true applied=%s", tostring(applied))
        end
    elseif setting_id == "wt_dev_hp_enable_3p" then
        if not _channel_enabled("third_person") then
            local restored = _restore_channel("third_person")
            pcall(printf, "[wt:616] tuner bypass channel=third_person restored=%d values_preserved=true", restored)
        else
            local applied = _apply_channel("third_person")
            pcall(printf, "[wt:616] tuner enabled channel=third_person values_restored=true applied=%s", tostring(applied))
        end
    else
        local channel = _setting_channel(setting_id)
        if channel == "both" then
            if mod:get("wt_dev_hp_enabled") == true then
                local applied = _apply_pose_all()
                _edit_diag(setting_id, channel, "delivered", applied)
            else
                _edit_diag(setting_id, channel, "saved_not_applied", false)
            end
        elseif channel then
            if _channel_enabled(channel) then
                -- Settings-screen numeric edits are explicit one-shot apply
                -- events.  This keeps tuning responsive in the keep where the
                -- StateInGameRunning per-frame hook is not guaranteed to run.
                local applied = _apply_channel(channel)
                _edit_diag(setting_id, channel, "delivered", applied)
            else
                -- Bypass is non-destructive: retain the authored value and
                -- say why it is not currently visible instead of silently
                -- pretending the unit was updated.
                _edit_diag(setting_id, channel, "saved_not_applied", false)
            end
        end
    end
end

function M.on_disabled()
    return _restore_cached_poses()
end

return M
