return function(H, repo_root)
    local prior_get_mod = _G.get_mod
    _G.get_mod = function()
        return { get = function() return nil end }
    end
    local path = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/wt_dev_hold_pose.lua"
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
        for _, hand in ipairs({ "rh", "lh" }) do
            for _, axis in ipairs({ "x", "y", "z" }) do
                local widget = widget_by_id(tree, "wt_dev_hp_" .. hand .. "_scale_" .. axis)
                H.truthy(widget, hand .. " scale " .. axis .. " widget missing")
                H.equal(widget.type, "numeric")
                H.equal(widget.default_value, 1)
                H.deep_equal(widget.range, { 0.01, 3.0 })
            end
        end
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
end
