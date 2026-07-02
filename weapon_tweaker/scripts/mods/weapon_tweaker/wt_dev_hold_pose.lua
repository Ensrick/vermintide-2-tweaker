--[[
wt_dev_hold_pose — Dev: Weapon Hold Pose Tuner
==============================================

Live in-game tuning of how the currently-wielded weapon is held on the local
player's 3P body. Drives `Unit.set_local_pose` against the weapon unit each
frame from VMF slider values (Euler rotation degrees + offset metres), then
emits a Lua-pastable `unit_attachment_node_linking`-style snippet via the
`/wt_dump_hold_pose` chat command so the lead can bake the tuned numbers back
into a weapon template / spawn-data helper.

Live-apply approach (chosen)
----------------------------
Per-frame re-apply via `mod:hook_safe("StateInGameRunning", "update", ...)`.
Rationale: a one-shot `Unit.set_local_pose` write is overwritten on the very
next animation tick when the engine re-applies the canonical attachment-node
pose. Hooking a per-frame state update and re-writing the local pose every
frame keeps the slider value visible. Cost is one Matrix4x4 + Vector3 +
Quaternion stack temp per frame — cheap, and we early-out when no weapon unit
is resolvable. Per-frame writes use FRESH `Vector3` / `Quaternion` stack
temporaries each call (we never store raw Q/V across frames — engine rule).

Caveat: this is a 3P-body-side cosmetic tweak. 1P (first-person) hand pose is
untouched. The dump command emits a degrees-and-metres snippet shaped like
the `unit_attachment_node_linking.third_person.<kind>` arrays in
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
* `Unit.actor` / `Unit.node` are 1-indexed where relevant; `set_local_pose`
  uses node `0` for the unit root (matches engine canon at
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

local mod = get_mod("wt")

local M = {}

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
local function _resolve_wielded(target_slot, target_hand)
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
    local right_unit_3p, left_unit_3p
    if slot_name == current_wielded then
        right_unit_3p = equipment.right_hand_wielded_unit_3p
        left_unit_3p  = equipment.left_hand_wielded_unit_3p
    else
        local slot_data = equipment.slots and equipment.slots[slot_name]
        if slot_data then
            right_unit_3p = slot_data.right_unit_3p
            left_unit_3p  = slot_data.left_unit_3p
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
        if left_unit_3p and Unit.alive(left_unit_3p) then
            return left_unit_3p, "left", slot_name, item_key
        end
    elseif target_hand == "right" then
        if right_unit_3p and Unit.alive(right_unit_3p) then
            return right_unit_3p, "right", slot_name, item_key
        end
    else  -- "both" — return right first (most common single-handed case)
        if right_unit_3p and Unit.alive(right_unit_3p) then
            return right_unit_3p, "right", slot_name, item_key
        end
        if left_unit_3p and Unit.alive(left_unit_3p) then
            return left_unit_3p, "left", slot_name, item_key
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

-- True when every Hold-Pose slider is at its default (0). An all-zero pose is
-- the IDENTITY matrix at local origin, and writing it with set_local_pose is
-- ABSOLUTE — so applying it would CLOBBER any baked grip offset on node 0
-- (the scythe / Elven-axe durable re-apply in weapon_tweaker.lua, and the
-- one-shot _offset_weapon_units write). "0" must mean "no override, leave the
-- baked grip alone", NOT "force the weapon to origin". This guard makes the
-- untouched/zeroed tool a true no-op even if live-apply is on. Only an
-- explicitly non-zero slider value wins and overrides the bake.
local function _pose_is_default(p)
    return (mod:get("wt_dev_hp_"..p.."_offset_x") or 0) == 0
       and (mod:get("wt_dev_hp_"..p.."_offset_y") or 0) == 0
       and (mod:get("wt_dev_hp_"..p.."_offset_z") or 0) == 0
       and (mod:get("wt_dev_hp_"..p.."_rot_pitch") or 0) == 0
       and (mod:get("wt_dev_hp_"..p.."_rot_yaw")   or 0) == 0
       and (mod:get("wt_dev_hp_"..p.."_rot_roll")  or 0) == 0
end

-- Build a FRESH local pose matrix from scalar slider values. Returns the raw
-- Matrix4x4 (stack temporary — must be consumed before the next frame).
local function _build_pose(p)
    local ox = mod:get("wt_dev_hp_"..p.."_offset_x") or 0
    local oy = mod:get("wt_dev_hp_"..p.."_offset_y") or 0
    local oz = mod:get("wt_dev_hp_"..p.."_offset_z") or 0
    local pitch_deg = mod:get("wt_dev_hp_"..p.."_rot_pitch") or 0
    local yaw_deg   = mod:get("wt_dev_hp_"..p.."_rot_yaw")   or 0
    local roll_deg  = mod:get("wt_dev_hp_"..p.."_rot_roll")  or 0
    local pos = Vector3(ox, oy, oz)
    -- Stingray Quaternion.from_euler_angles_xyz takes DEGREES, not radians
    -- (vanilla crawl_space_extension.lua:14 passes 90 for a 90° turn). The old
    -- math.rad() wrap made every rotation ~57x too small -> imperceptible, so the
    -- rotation sliders looked like they did nothing. Pass degrees straight through.
    local rot = Quaternion.from_euler_angles_xyz(pitch_deg, yaw_deg, roll_deg)
    return Matrix4x4.from_quaternion_position(rot, pos)
end

-- Apply the slider-built pose to one weapon unit. node_index 0 is the unit
-- root (matches engine canon: projectile_physics_husk_locomotion_extension
-- .lua:65 and camera_state_helper.lua:21). Wrapped in pcall as belt-and-
-- suspenders even though set_local_pose is documented as safe — engine
-- write-side fatals occasionally bypass pcall.
--
-- DEFER-TO-BAKED: when all sliders are at default (0) we DO NOT write — an
-- absolute identity-pose write would stomp the baked grip offset on node 0
-- (precedence: 0 = "no override, keep the bake"; non-zero = "override wins").
-- This keeps the durable per-frame grip re-apply (weapon_tweaker.lua
-- _reapply_durable_grip_offsets) intact at stock defaults.
local function _apply_pose_to(weapon_unit, p)
    if not weapon_unit then return false end
    if not Unit.alive(weapon_unit) then return false end
    if _pose_is_default(p) then return false end   -- defer-to-baked guard, per hand
    local pose = _build_pose(p)
    local ok = pcall(Unit.set_local_pose, weapon_unit, 0, pose)
    return ok
end

-- Apply each hand's pose from ITS OWN sliders, independently. No hand
-- dropdown, no "both" mode — RH sliders drive the right-hand unit, LH sliders
-- drive the left-hand unit, each gated by its own defer-to-baked guard.
local function _apply_pose_all()
    local target_slot = mod:get("wt_dev_hp_target_slot") or "auto"
    local applied = false
    local u_r = select(1, _resolve_wielded(target_slot, "right"))
    if u_r then applied = _apply_pose_to(u_r, "rh") or applied end
    local u_l = select(1, _resolve_wielded(target_slot, "left"))
    if u_l then applied = _apply_pose_to(u_l, "lh") or applied end
    return applied
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

    -- One entry per hand: p = slider prefix, hand = resolve label, src = source bone.
    local HANDS = {
        { p = "rh", hand = "right", src = source_node },
        { p = "lh", hand = "left",  src = "j_lefthand" },
    }

    mod:info("-- ==== wt Hold Pose dump ====")
    mod:info("-- character=%s  slot=%s  kind=%s", career, tostring(target_slot), tostring(target_kind))
    mod:info("local _custom_third_person = {")

    for _, h in ipairs(HANDS) do
        local p = h.p
        local ox = mod:get("wt_dev_hp_"..p.."_offset_x") or 0
        local oy = mod:get("wt_dev_hp_"..p.."_offset_y") or 0
        local oz = mod:get("wt_dev_hp_"..p.."_offset_z") or 0
        local pitch_deg = mod:get("wt_dev_hp_"..p.."_rot_pitch") or 0
        local yaw_deg   = mod:get("wt_dev_hp_"..p.."_rot_yaw")   or 0
        local roll_deg  = mod:get("wt_dev_hp_"..p.."_rot_roll")  or 0

        local resolved_unit, hand, slot_name, item_key = _resolve_wielded(target_slot, h.hand)
        local non_default = not _pose_is_default(p)

        -- Emit a block when this hand has a resolved unit OR non-default sliders.
        if resolved_unit or non_default then
            hand      = hand      or h.hand
            slot_name = slot_name or target_slot
            item_key  = item_key  or "<unknown>"
            mod:info("    -- hand=%s  weapon=%s  slot=%s  source_node=%s",
                tostring(hand), tostring(item_key), tostring(slot_name), tostring(h.src))
            mod:info("    -- Sliders: offset_xyz=(%.3f, %.3f, %.3f) m  rot_pyr=(%.1f, %.1f, %.1f) deg",
                ox, oy, oz, pitch_deg, yaw_deg, roll_deg)
            mod:info("    {")
            mod:info("        source = %q,", h.src)
            mod:info("        target = 0,")
            mod:info("        offset = { %.3f, %.3f, %.3f },", ox, oy, oz)
            mod:info("        rotation = { pitch = %.1f, yaw = %.1f, roll = %.1f },  -- degrees, Euler XYZ",
                pitch_deg, yaw_deg, roll_deg)
            mod:info("    },")
        end
    end

    mod:info("}")
    mod:info("-- Apply via (per hand):")
    mod:info("--   local pos = Vector3(offset_x, offset_y, offset_z)")
    mod:info("--   local rot = Quaternion.from_euler_angles_xyz(pitch, yaw, roll)  -- DEGREES, not radians")
    mod:info("--   Unit.set_local_pose(weapon_unit, 0, Matrix4x4.from_quaternion_position(rot, pos))")
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
            -- RIGHT-hand pose sliders (drive the right_unit_3p independently).
            {
                setting_id = "wt_dev_hp_rh_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "wt_dev_hp_rh_offset_x",
                        type = "numeric",
                        default_value = 0,
                        range = { -1.0, 1.0 },
                        decimals_number = 3,  -- 1mm step (floor; numeric widget has no step field)
                        unit_text = " m",
                    },
                    {
                        setting_id = "wt_dev_hp_rh_offset_y",
                        type = "numeric",
                        default_value = 0,
                        range = { -1.0, 1.0 },
                        decimals_number = 3,
                        unit_text = " m",
                    },
                    {
                        setting_id = "wt_dev_hp_rh_offset_z",
                        type = "numeric",
                        default_value = 0,
                        range = { -1.0, 1.0 },
                        decimals_number = 3,
                        unit_text = " m",
                    },
                    {
                        setting_id = "wt_dev_hp_rh_rot_pitch",
                        type = "numeric",
                        default_value = 0,
                        range = { -180.0, 180.0 },
                        decimals_number = 1,  -- 0.1 deg step (floor)
                        unit_text = " deg",
                    },
                    {
                        setting_id = "wt_dev_hp_rh_rot_yaw",
                        type = "numeric",
                        default_value = 0,
                        range = { -180.0, 180.0 },
                        decimals_number = 1,
                        unit_text = " deg",
                    },
                    {
                        setting_id = "wt_dev_hp_rh_rot_roll",
                        type = "numeric",
                        default_value = 0,
                        range = { -180.0, 180.0 },
                        decimals_number = 1,
                        unit_text = " deg",
                    },
                },
            },
            -- LEFT-hand pose sliders (drive the left_unit_3p independently).
            {
                setting_id = "wt_dev_hp_lh_group",
                type = "group",
                sub_widgets = {
                    {
                        setting_id = "wt_dev_hp_lh_offset_x",
                        type = "numeric",
                        default_value = 0,
                        range = { -1.0, 1.0 },
                        decimals_number = 3,  -- 1mm step (floor; numeric widget has no step field)
                        unit_text = " m",
                    },
                    {
                        setting_id = "wt_dev_hp_lh_offset_y",
                        type = "numeric",
                        default_value = 0,
                        range = { -1.0, 1.0 },
                        decimals_number = 3,
                        unit_text = " m",
                    },
                    {
                        setting_id = "wt_dev_hp_lh_offset_z",
                        type = "numeric",
                        default_value = 0,
                        range = { -1.0, 1.0 },
                        decimals_number = 3,
                        unit_text = " m",
                    },
                    {
                        setting_id = "wt_dev_hp_lh_rot_pitch",
                        type = "numeric",
                        default_value = 0,
                        range = { -180.0, 180.0 },
                        decimals_number = 1,  -- 0.1 deg step (floor)
                        unit_text = " deg",
                    },
                    {
                        setting_id = "wt_dev_hp_lh_rot_yaw",
                        type = "numeric",
                        default_value = 0,
                        range = { -180.0, 180.0 },
                        decimals_number = 1,
                        unit_text = " deg",
                    },
                    {
                        setting_id = "wt_dev_hp_lh_rot_roll",
                        type = "numeric",
                        default_value = 0,
                        range = { -180.0, 180.0 },
                        decimals_number = 1,
                        unit_text = " deg",
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
        wt_dev_hp_target_slot = { en = "Target slot" },
        wt_dev_hp_target_kind = { en = "Linking-table kind (for dump)" },
        wt_dev_hp_source_node = { en = "Source node (3P body bone)" },
        wt_dev_hp_rh_group       = { en = "Right hand" },
        wt_dev_hp_rh_offset_x    = { en = "RH Offset X (metres)" },
        wt_dev_hp_rh_offset_y    = { en = "RH Offset Y (metres)" },
        wt_dev_hp_rh_offset_z    = { en = "RH Offset Z (metres)" },
        wt_dev_hp_rh_rot_pitch   = { en = "RH Rotation pitch (deg, Euler X)" },
        wt_dev_hp_rh_rot_yaw     = { en = "RH Rotation yaw (deg, Euler Y)" },
        wt_dev_hp_rh_rot_roll    = { en = "RH Rotation roll (deg, Euler Z)" },
        wt_dev_hp_lh_group       = { en = "Left hand" },
        wt_dev_hp_lh_offset_x    = { en = "LH Offset X (metres)" },
        wt_dev_hp_lh_offset_y    = { en = "LH Offset Y (metres)" },
        wt_dev_hp_lh_offset_z    = { en = "LH Offset Z (metres)" },
        wt_dev_hp_lh_rot_pitch   = { en = "LH Rotation pitch (deg, Euler X)" },
        wt_dev_hp_lh_rot_yaw     = { en = "LH Rotation yaw (deg, Euler Y)" },
        wt_dev_hp_lh_rot_roll    = { en = "LH Rotation roll (deg, Euler Z)" },
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

    -- Quick reset to zeros (faster than dragging twelve sliders back to 0).
    mod:command("wt_dev_hp_reset",
        "Reset Hold-Pose sliders (both hands) to zero offsets / zero rotation.",
        function()
            mod:set("wt_dev_hp_rh_offset_x", 0)
            mod:set("wt_dev_hp_rh_offset_y", 0)
            mod:set("wt_dev_hp_rh_offset_z", 0)
            mod:set("wt_dev_hp_rh_rot_pitch", 0)
            mod:set("wt_dev_hp_rh_rot_yaw",   0)
            mod:set("wt_dev_hp_rh_rot_roll",  0)
            mod:set("wt_dev_hp_lh_offset_x", 0)
            mod:set("wt_dev_hp_lh_offset_y", 0)
            mod:set("wt_dev_hp_lh_offset_z", 0)
            mod:set("wt_dev_hp_lh_rot_pitch", 0)
            mod:set("wt_dev_hp_lh_rot_yaw",   0)
            mod:set("wt_dev_hp_lh_rot_roll",  0)
            -- mod:set from non-on_setting_changed paths updates the store
            -- but the open widget doesn't refresh until view re-open (see
            -- VMF_RECIPES § checkbox cached display state). The pose itself
            -- DOES re-apply correctly because _apply_pose_all reads via
            -- mod:get on the next frame.
            mod:echo("[wt_dev_hp] sliders reset to zero (close + reopen the "
                .. "settings menu to see the UI update)")
        end)

    mod:info("[wt_dev_hp] Dev: Weapon Hold Pose Tuner installed -- "
        .. "live-apply per-frame, /wt_dev_hp_apply for one-shot, "
        .. "/wt_dump_hold_pose to dump a snippet, /wt_dev_hp_reset to zero.")
end

return M
