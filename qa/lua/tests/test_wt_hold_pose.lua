return function(H, repo_root)
    local prior_get_mod = _G.get_mod
    _G.get_mod = function()
        return { get = function() return nil end }
    end
    local path = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_dev_hold_pose.lua"
    local HoldPose = dofile(path)
    _G.get_mod = prior_get_mod

    local function widget_by_id(node, wanted)
        if type(node) ~= "table" then return nil end
        if node.setting_id == wanted then return node end
        for _, child in ipairs(node.sub_widgets or {}) do
            local found = widget_by_id(child, wanted)
            if found then return found end
        end
        return nil
    end

    H.test("WT #616 Hold-Pose exposes independent identity scale controls", function()
        local tree = HoldPose.build_widget_tree()
		H.equal(tree.sub_widgets[1].setting_id, "wt_dev_hp_enabled")
		H.equal(tree.sub_widgets[2].setting_id, "wt_dev_hp_target_slot")
        for _, hand in ipairs({ "rh", "lh" }) do
            for _, axis in ipairs({ "x", "y", "z" }) do
                local widget = widget_by_id(tree, "wt_dev_hp_" .. hand .. "_scale_" .. axis)
                H.truthy(widget, hand .. " scale " .. axis .. " widget missing")
                H.equal(widget.type, "numeric")
                H.equal(widget.default_value, 1)
                H.deep_equal(widget.range, { 0.01, 3.0 })
            end
        end
        for _, hand in ipairs({ "rh", "lh" }) do
            for _, component in ipairs({ "offset", "rot", "scale" }) do
                local axes = component == "rot" and { "pitch", "yaw", "roll" }
                    or { "x", "y", "z" }
                for _, axis in ipairs(axes) do
                    local widget = widget_by_id(tree,
                        "wt_dev_hp_fp_" .. hand .. "_" .. component .. "_" .. axis)
                    H.truthy(widget, "1P " .. hand .. " " .. component .. " " .. axis .. " missing")
                end
            end
        end
        H.equal(widget_by_id(tree, "wt_dev_hp_enable_3p").default_value, true)
        H.equal(widget_by_id(tree, "wt_dev_hp_enable_1p").default_value, false)
        H.equal(widget_by_id(tree, "wt_dev_hp_enabled").default_value, false)
		local loc = HoldPose.loc_keys()
		H.equal(loc.wt_dev_hp_enabled.en, "Enable Hold-Pose Tuner")
		H.equal(loc.wt_dev_hp_enabled_description.en,
			"OFF bypasses all position, rotation, and scale changes while preserving every saved value.")
    end)

    H.test("WT #168 Hold-Pose keeps right and left hand plans independent", function()
        local tree = HoldPose.build_widget_tree()
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
            local group = widget_by_id(tree, spec[1])
            H.truthy(group, spec[1] .. " missing")
            H.equal(#group.sub_widgets, 9)
            for i, suffix in ipairs(suffixes) do
                H.equal(group.sub_widgets[i].setting_id, spec[2] .. suffix)
            end
        end
        H.equal(widget_by_id(tree, "wt_dev_hp_hand"), nil,
            "legacy hand selector must not return")

        local reads = {}
        local plans = HoldPose._independent_hand_plans("third_person",
            function(channel, hand)
                reads[#reads + 1] = channel .. ":" .. hand
                if hand == "right" then
                    return 0.25, 0, 0, 0, 0, 0, 1, 1, 1
                end
                return 0, 0, 0, 0, 17, 0, 0.5, 0.75, 1.25
            end)
        H.deep_equal(reads, { "third_person:right", "third_person:left" })
        H.equal(plans.right.position, true)
        H.equal(plans.right.rotation, false)
        H.equal(plans.right.scale, false)
        H.equal(plans.right.ox, 0.25)
        H.equal(plans.left.position, false)
        H.equal(plans.left.rotation, true)
        H.equal(plans.left.scale, true)
        H.equal(plans.left.yaw, 17)
        H.equal(plans.left.sx, 0.5)

        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('_apply_pose_to(u_r, channel, "right", plans.right)', 1, true),
            "right-hand unit is not driven by the right plan")
        H.truthy(source:find('_apply_pose_to(u_l, channel, "left", plans.left)', 1, true),
            "left-hand unit is not driven by the left plan")
    end)

    H.test("WT #616 Hold-Pose scale plan is absolute and non-compounding", function()
        local contract = HoldPose._pose_contract
        H.equal(contract.scale_setter, "Unit.set_local_scale")
        H.equal(contract.scale_mode, "absolute")
        H.equal(contract.compounds, false)
        local identity = HoldPose._component_plan_values(0, 0, 0, 0, 0, 0, 1, 1, 1)
        H.equal(identity.position, false)
        H.equal(identity.rotation, false)
        H.equal(identity.scale, false)
        local scale = HoldPose._component_plan_values(0, 0, 0, 0, 0, 0, 0.5, 0.75, 1.25)
        H.equal(scale.position, false)
        H.equal(scale.rotation, false)
        H.equal(scale.scale, true)
        H.equal(scale.sx, 0.5)
        H.equal(scale.sy, 0.75)
        H.equal(scale.sz, 1.25)
    end)

    H.test("WT #616 reset and dump retain all scale axes", function()
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        for _, hand in ipairs({ "rh", "lh" }) do
            for _, axis in ipairs({ "x", "y", "z" }) do
                local key = "wt_dev_hp_" .. hand .. "_scale_" .. axis
                H.truthy(source:find('mod:set("' .. key .. '", 1)', 1, true),
                    key .. " reset missing")
            end
        end
        H.truthy(source:find("scale = { %.3f, %.3f, %.3f }", 1, true),
            "dump does not emit non-uniform scale")
    end)

    H.test("WT #616 bypass preserves values and isolates render channels", function()
        local policy_all = HoldPose._channel_policy_values(true, true, true)
        local policy_3p = HoldPose._channel_policy_values(true, false, true)
        local master_off = HoldPose._channel_policy_values(false, true, true)
        H.equal(policy_all.master, true)
        H.equal(policy_all.first_person, true)
        H.equal(policy_all.third_person, true)
        H.equal(policy_3p.first_person, false)
        H.equal(policy_3p.third_person, true)
        H.equal(policy_3p.preserves_settings, true)
        H.equal(policy_3p.restores_baseline_on_bypass, true)
        H.equal(master_off.master, false)
        H.equal(master_off.first_person, false)
        H.equal(master_off.third_person, false)

        local contract = HoldPose._pose_contract
        H.equal(contract.scope, "local_player_isolated_1p_3p")
        H.equal(contract.bypass, "restore_channel_baseline_without_erasing_settings")
        for _, surface in ipairs({ "inventory_preview", "hero_preview", "bots",
                "remote_husks", "score", "baked_transforms" }) do
            H.equal(contract.excluded_surfaces[surface], true, surface .. " leakage guard missing")
        end
    end)

    H.test("WT #616 3P tuner is a peer collapsible beside First Person", function()
        local tree = HoldPose.build_widget_tree()
        local third_person = widget_by_id(tree, "wt_dev_hp_3p_group")
        local first_person = widget_by_id(tree, "wt_dev_hp_1p_group")
        H.truthy(third_person, "Third Person group missing")
        H.truthy(first_person, "First Person group missing")
        H.equal(third_person.type, "group")
        H.equal(first_person.type, "group")
        H.truthy(widget_by_id(third_person, "wt_dev_hp_enable_3p"))
        H.truthy(widget_by_id(third_person, "wt_dev_hp_rh_group"))
        H.truthy(widget_by_id(third_person, "wt_dev_hp_lh_group"))
        H.equal(widget_by_id(first_person, "wt_dev_hp_rh_group"), nil,
            "3P controls leaked into the First Person group")

        local loc = HoldPose.loc_keys()
        H.equal(loc.wt_dev_hp_3p_group.en, "Third Person")
        H.equal(loc.wt_dev_hp_1p_group.en, "First Person")
    end)

    H.test("WT #616 numeric edits dispatch immediately to the exact render channel", function()
        local classify = HoldPose._setting_channel
        for _, hand in ipairs({ "rh", "lh" }) do
            for _, component in ipairs({ "offset_x", "rot_yaw", "scale_z" }) do
                H.equal(classify("wt_dev_hp_" .. hand .. "_" .. component), "third_person")
                H.equal(classify("wt_dev_hp_fp_" .. hand .. "_" .. component), "first_person")
            end
        end
        H.equal(classify("wt_dev_hp_target_slot"), "both")
        H.equal(classify("wt_dev_hp_enabled"), nil)
        H.equal(classify("unrelated_setting"), nil)

        local contract = HoldPose._live_delivery_contract
        H.equal(contract.setting_dispatch, "channel_exact")
        H.equal(contract.immediate_apply, true)
        H.equal(contract.bypass_preserves_values, true)
        H.equal(contract.bypass_does_not_apply, true)

        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local handler_start = assert(source:find("function M.on_setting_changed", 1, true))
        local handler_end = assert(source:find("function M.on_disabled", handler_start, true))
        local handler = source:sub(handler_start, handler_end - 1)
        H.truthy(handler:find("local applied = _apply_channel(channel)", 1, true),
            "numeric edit does not perform an immediate one-shot apply")
        H.truthy(handler:find('"saved_not_applied"', 1, true),
            "bypassed edit has no explicit diagnostic")
    end)

    H.test("WT #616 1P settings persist through bypass and reset independently", function()
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("right_hand_wielded_unit", 1, true))
        H.truthy(source:find("right_hand_wielded_unit_3p", 1, true))
        H.truthy(source:find("_pose_baselines.first_person", 1, true) == nil,
            "baselines should be indexed through a channel map, not cross-written")
        for _, hand in ipairs({ "rh", "lh" }) do
            for _, component in ipairs({ "offset_x", "offset_y", "offset_z",
                    "rot_pitch", "rot_yaw", "rot_roll", "scale_x", "scale_y", "scale_z" }) do
                local key = "wt_dev_hp_fp_" .. hand .. "_" .. component
                H.truthy(source:find('mod:get("' .. key .. '")', 1, true), key .. " persisted read missing")
                local reset_value = component:find("scale", 1, true) and "1" or "0"
                H.truthy(source:find('mod:set%("' .. key .. '",%s*' .. reset_value .. '%)'),
                    key .. " explicit reset missing")
            end
        end
        local bypass_start = assert(source:find('function M.on_setting_changed', 1, true))
        local bypass_end = assert(source:find('function M.on_disabled', bypass_start, true))
        local bypass = source:sub(bypass_start, bypass_end - 1)
        H.truthy(bypass:find('setting_id == "wt_dev_hp_enabled"', 1, true),
            "master bypass handler missing")
        H.truthy(bypass:find('_restore_cached_poses()', 1, true),
            "master bypass must restore both channel baselines")
        H.truthy(bypass:find('local applied = _apply_pose_all()', 1, true),
            "master re-enable must reapply preserved values immediately")
        H.equal(bypass:find('mod:set("wt_dev_hp_fp_', 1, true), nil,
            "bypass must not erase saved 1P values")
    end)
end
