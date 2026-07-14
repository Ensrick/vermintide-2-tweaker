return function(H, repo_root)
    local stable_root = repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/"
    local dev_root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Ordering = assert(loadfile(dev_root .. "_mod_tweaker_ordering.lua"))()

    local function order(nodes, depths, extra)
        extra = extra or {}
        extra.get_type = extra.get_type or function(node) return node.type end
        extra.get_label = extra.get_label or function(node) return node.label end
        extra.has_explicit_order = extra.has_explicit_order or function(node)
            return node.mod_tweaker_order ~= nil or node.depends_on ~= nil
        end
        return Ordering.order_flat(nodes, depths, extra)
    end

    local function ids(nodes)
        local out = {}
        for i = 1, #nodes do out[i] = nodes[i].id end
        return out
    end

    H.test("groups precede loose settings and each partition uses display labels", function()
        local nodes = {
            { id = "setting_z", type = "checkbox", label = "Zulu" },
            { id = "group_b", type = "group", label = "Beta" },
            { id = "setting_a", type = "numeric", label = "alpha" },
            { id = "group_a", type = "group", label = "Alpha" },
        }
        local ordered, depths = order(nodes, { 0, 0, 0, 0 })
        H.deep_equal(ids(ordered), { "group_a", "group_b", "setting_a", "setting_z" })
        H.deep_equal(depths, { 0, 0, 0, 0 })
    end)

    H.test("recursive ordering preserves each complete subtree", function()
        local nodes = {
            { id = "loose", type = "checkbox", label = "Before" },
            { id = "parent", type = "group", label = "Parent" },
            { id = "child_z", type = "checkbox", label = "Zulu" },
            { id = "child_group", type = "group", label = "Alpha group" },
            { id = "grandchild", type = "checkbox", label = "Leaf" },
            { id = "child_a", type = "checkbox", label = "Alpha" },
        }
        local ordered, depths = order(nodes, { 0, 0, 1, 1, 2, 1 })
        H.deep_equal(ids(ordered), {
            "parent", "child_group", "grandchild", "child_a", "child_z", "loose",
        })
        H.deep_equal(depths, { 0, 1, 2, 1, 1, 0 })
        H.equal(ordered[3], nodes[5], "the grandchild must remain attached to its group")
    end)

    H.test("authored headers and dependency metadata preserve their sibling list", function()
        local header_nodes = {
            { id = "z", type = "checkbox", label = "Zulu" },
            { id = "header", type = "header", label = "Section" },
            { id = "a", type = "group", label = "Alpha" },
        }
        local dependency_nodes = {
            { id = "z", type = "checkbox", label = "Zulu", depends_on = "a" },
            { id = "a", type = "group", label = "Alpha" },
        }
        local header_order = order(header_nodes, { 0, 0, 0 })
        local dependency_order = order(dependency_nodes, { 0, 0 })
        H.deep_equal(ids(header_order), { "z", "header", "a" })
        H.deep_equal(ids(dependency_order), { "z", "a" })
    end)

    H.test("VMF generated tab header stays anchored without blocking row sorting", function()
        local nodes = {
            { id = "header", type = "header", label = "Mod", mod_name = "example" },
            { id = "z", type = "checkbox", label = "Zulu" },
            { id = "a", type = "group", label = "Alpha" },
        }
        local ordered = order(nodes, { 0, 0, 0 }, {
            is_generated_header = function(node) return node.mod_name ~= nil end,
        })
        H.deep_equal(ids(ordered), { "header", "a", "z" })
    end)

    H.test("Equipment opt-out preserves its deliberate synthetic sequence", function()
        local nodes = {
            { id = "crafting", type = "checkbox", label = "Crafting" },
            { id = "cosmetics", type = "group", label = "Cosmetics" },
        }
        local ordered, depths = order(nodes, { 0, 0 }, { preserve_all = true })
        H.deep_equal(ids(ordered), { "crafting", "cosmetics" })
        H.deep_equal(depths, { 0, 0 })
    end)

    H.test("stable and dev ship the same policy and wire both presentations", function()
        local function read(path)
            local file = assert(io.open(path, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        H.equal(read(stable_root .. "_mod_tweaker_ordering.lua"),
            read(dev_root .. "_mod_tweaker_ordering.lua"))
        for _, root in ipairs({ stable_root, dev_root }) do
            for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
                local source = read(root .. name)
                H.truthy(string.find(source, "_mod_tweaker_ordering", 1, true), name)
                H.truthy(string.find(source, "_order_category_nodes(category, nodes, depths)", 1, true), name)
            end
        end
    end)
end
