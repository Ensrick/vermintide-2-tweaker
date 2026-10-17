-- _wt_runtime_checks_hold_pose.lua -- dev Hold-Pose regression registrations.
--
-- This owner is deliberately registration-only and engine-object neutral. The
-- parent runtime-check registrar invokes it at the historical overlay position,
-- preserving command/check order while keeping the dev-only Hold-Pose contract
-- out of the common public/dev owner.

local M = {}

function M.install(_rt_register, _wt_dev_hold_pose)
    assert(type(_rt_register) == "function",
        "WT Hold-Pose runtime checks require a register callback")

    _rt_register("issue168_hold_pose_independent_hands", function()
        local build_tree = _wt_dev_hold_pose and _wt_dev_hold_pose.build_widget_tree
        local build_plans = _wt_dev_hold_pose
            and _wt_dev_hold_pose._independent_hand_plans
        if type(build_tree) ~= "function" or type(build_plans) ~= "function" then
            return "Hold-Pose independent-hand contract missing"
        end

        local function find_setting(node, wanted)
            if type(node) ~= "table" then return nil end
            if node.setting_id == wanted then return node end
            for _, child in ipairs(node.sub_widgets or {}) do
                local found = find_setting(child, wanted)
                if found then return found end
            end
            return nil
        end

        local tree = build_tree()
        local suffixes = {
            "offset_x", "offset_y", "offset_z",
            "rot_pitch", "rot_yaw", "rot_roll",
            "scale_x", "scale_y", "scale_z",
        }
        for _, spec in ipairs({
                { "wt_dev_hp_rh_group", "wt_dev_hp_rh_" },
                { "wt_dev_hp_lh_group", "wt_dev_hp_lh_" },
                { "wt_dev_hp_fp_rh_group", "wt_dev_hp_fp_rh_" },
                { "wt_dev_hp_fp_lh_group", "wt_dev_hp_fp_lh_" },
        }) do
            local group = find_setting(tree, spec[1])
            if not group then
                return "independent hand group missing: " .. spec[1]
            end
            if type(group.sub_widgets) ~= "table" or #group.sub_widgets ~= 9 then
                return "independent hand group is not an exact nine-value owner: " .. spec[1]
            end
            for i, suffix in ipairs(suffixes) do
                if group.sub_widgets[i].setting_id ~= spec[2] .. suffix then
                    return "hand group key crossed ownership: " .. spec[1]
                end
            end
        end
        if find_setting(tree, "wt_dev_hp_hand") then
            return "legacy single-hand selector returned"
        end

        local reads = {}
        local plans = build_plans("third_person", function(channel, hand)
            reads[#reads + 1] = channel .. ":" .. hand
            if hand == "right" then
                return 0.25, 0, 0, 0, 0, 0, 1, 1, 1
            end
            return 0, 0, 0, 0, 17, 0, 0.5, 0.75, 1.25
        end)
        if reads[1] ~= "third_person:right" or reads[2] ~= "third_person:left"
                or reads[3] ~= nil then
            return "production plan owner did not read each hand exactly once"
        end
        if type(plans) ~= "table" or type(plans.right) ~= "table"
                or type(plans.left) ~= "table" then
            return "independent hand plans missing"
        end
        if not plans.right.position or plans.right.rotation or plans.right.scale
                or plans.right.ox ~= 0.25 then
            return "right-hand plan consumed left-hand values"
        end
        if plans.left.position or not plans.left.rotation or not plans.left.scale
                or plans.left.yaw ~= 17 or plans.left.sx ~= 0.5 then
            return "left-hand plan consumed right-hand values"
        end
    end)

    _rt_register("issue569_hold_pose_composition", function()
        local pose_contract = _wt_dev_hold_pose and _wt_dev_hold_pose._pose_contract
        local plan_values = _wt_dev_hold_pose and _wt_dev_hold_pose._component_plan_values
        if type(pose_contract) ~= "table" or type(plan_values) ~= "function" then
            return "Hold-Pose composition contract missing"
        end
        if pose_contract.mode ~= "canonical_plus_delta"
            or pose_contract.position_setter ~= "Unit.set_local_position"
            or pose_contract.rotation_setter ~= "Unit.set_local_rotation"
            or pose_contract.scale_setter ~= "Unit.set_local_scale"
            or pose_contract.scale_mode ~= "absolute"
            or pose_contract.scope ~= "local_player_isolated_1p_3p"
            or pose_contract.compounds ~= false then
            return "Hold-Pose must compose position/rotation/scale without compounding"
        end
        local position_only = plan_values(0, 0, 0.1, 0, 0, 0)
        if not position_only.position or position_only.rotation or position_only.scale then
            return "position-only Hold-Pose edit would overwrite canonical rotation"
        end
        local rotation_only = plan_values(0, 0, 0, 0, 0, 15)
        if rotation_only.position or not rotation_only.rotation or rotation_only.scale then
            return "rotation-only Hold-Pose edit would overwrite canonical position"
        end
        local identity = plan_values(0, 0, 0, 0, 0, 0, 1, 1, 1)
        if identity.position or identity.rotation or identity.scale then
            return "identity Hold-Pose sliders are not a no-op"
        end
    end)

    _rt_register("issue616_hold_pose_channel_bypass_restore", function()
        local contract = _wt_dev_hold_pose and _wt_dev_hold_pose._pose_contract
        local policy_values = _wt_dev_hold_pose and _wt_dev_hold_pose._channel_policy_values
        if type(contract) ~= "table" or type(policy_values) ~= "function" then
            return "Hold-Pose channel/bypass contract missing"
        end
        if contract.scope ~= "local_player_isolated_1p_3p"
                or type(contract.channels) ~= "table"
                or not contract.channels.first_person
                or not contract.channels.third_person then
            return "1P/3P channels are not explicitly isolated"
        end
        local excluded = contract.excluded_surfaces
        for _, key in ipairs({ "inventory_preview", "hero_preview", "bots",
                "remote_husks", "score", "baked_transforms" }) do
            if type(excluded) ~= "table" or excluded[key] ~= true then
                return "tuner surface leakage guard missing: " .. key
            end
        end
        local all_on = policy_values(true, true, true)
        local one_off = policy_values(true, false, true)
        local master_off = policy_values(false, true, true)
        if not all_on.master or not all_on.first_person or not all_on.third_person
                or one_off.first_person or not one_off.third_person then
            return "channel enable state is not independent"
        end
        if master_off.master or master_off.first_person or master_off.third_person then
            return "master bypass did not disable both transform channels"
        end
        if not one_off.preserves_settings or not one_off.restores_baseline_on_bypass
                or contract.bypass ~= "restore_channel_baseline_without_erasing_settings" then
            return "bypass erases values or fails to restore the canonical baseline"
        end
    end)

    _rt_register("issue616_hold_pose_live_edit_delivery", function()
        local classify = _wt_dev_hold_pose and _wt_dev_hold_pose._setting_channel
        local delivery = _wt_dev_hold_pose and _wt_dev_hold_pose._live_delivery_contract
        if type(classify) ~= "function" or type(delivery) ~= "table" then
            return "Hold-Pose live edit delivery contract missing"
        end
        if classify("wt_dev_hp_rh_offset_y") ~= "third_person"
                or classify("wt_dev_hp_lh_rot_roll") ~= "third_person"
                or classify("wt_dev_hp_rh_scale_x") ~= "third_person" then
            return "third-person position/rotation/scale edit routing drifted"
        end
        if classify("wt_dev_hp_fp_rh_offset_y") ~= "first_person"
                or classify("wt_dev_hp_fp_lh_rot_roll") ~= "first_person"
                or classify("wt_dev_hp_fp_rh_scale_x") ~= "first_person" then
            return "first-person position/rotation/scale edit routing drifted"
        end
        if classify("wt_dev_hp_target_slot") ~= "both"
                or classify("wt_dev_hp_enabled") ~= nil then
            return "Hold-Pose non-transform setting routing is not exact"
        end
        if delivery.setting_dispatch ~= "channel_exact"
                or delivery.immediate_apply ~= true
                or delivery.bypass_preserves_values ~= true
                or delivery.bypass_does_not_apply ~= true then
            return "Hold-Pose immediate/bypass delivery semantics drifted"
        end
    end)

    _rt_register("issue616_hold_pose_nonuniform_scale", function()
        local pose_contract = _wt_dev_hold_pose and _wt_dev_hold_pose._pose_contract
        local plan_values = _wt_dev_hold_pose and _wt_dev_hold_pose._component_plan_values
        if type(pose_contract) ~= "table" or type(plan_values) ~= "function" then
            return "Hold-Pose scale contract missing"
        end
        if pose_contract.scale_setter ~= "Unit.set_local_scale"
                or pose_contract.scale_mode ~= "absolute"
                or pose_contract.compounds ~= false then
            return "scale must be absolute and non-compounding"
        end
        local scale_only = plan_values(0, 0, 0, 0, 0, 0, 0.5, 0.75, 1.25)
        if scale_only.position or scale_only.rotation or not scale_only.scale
                or scale_only.sx ~= 0.5 or scale_only.sy ~= 0.75 or scale_only.sz ~= 1.25 then
            return "non-uniform scale plan clobbers another component"
        end
        local all = plan_values(0.1, -0.2, 0.3, -90, 180, -90, 0.5, 0.6, 0.7)
        if not all.position or not all.rotation or not all.scale then
            return "complete nine-value transform does not compose all components"
        end
    end)
end

return M
