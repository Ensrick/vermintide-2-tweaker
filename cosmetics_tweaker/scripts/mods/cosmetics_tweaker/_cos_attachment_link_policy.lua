local M = {
    VERSION = 1,
}

function M.partition(node_linking, source_has_node, target_has_node)
    if type(node_linking) ~= "table" then
        return nil, nil, "invalid_node_linking"
    end
    if type(source_has_node) ~= "function" or type(target_has_node) ~= "function" then
        return nil, nil, "invalid_probe"
    end

    local valid = {}
    local skipped = {}

    for index, link_data in ipairs(node_linking) do
        local source_node = link_data.source
        local target_node = link_data.target
        local source_exists = type(source_node) ~= "string"
            or source_has_node(source_node)
        local target_exists = type(target_node) ~= "string"
            or target_has_node(target_node)

        if source_exists and target_exists then
            valid[#valid + 1] = link_data
        else
            skipped[#skipped + 1] = {
                index = index,
                source = source_node,
                target = target_node,
                missing = not source_exists and "source" or "target",
            }
        end
    end

    return valid, skipped, "ok"
end

local function first_missing(skipped)
    local first = skipped[1]

    if not first then
        return nil, nil
    end

    local node = first.missing == "source" and first.source or first.target

    return node, first.missing
end

function M.install(mod, attachment_utils, la_bridge, unit_api)
    if type(attachment_utils) ~= "table" or type(attachment_utils.link) ~= "function" then
        return false
    end
    if type(unit_api) ~= "table" then
        return false
    end

    mod:hook(attachment_utils, "link", function(func, world, source, target, node_linking)
        local bad_node, bad_unit

        if type(source) ~= "userdata" or not unit_api.alive(source) then
            bad_node, bad_unit = "<source-unit>", "source"
        elseif type(target) ~= "userdata" or not unit_api.alive(target) then
            bad_node, bad_unit = "<target-unit>", "target"
        end

        if bad_node then
            mod:info("[cos-hat] SKIP attach no-node=%s unit=%s (dead unit)",
                tostring(bad_node), tostring(bad_unit))
            return
        end

        local valid, skipped, reason = M.partition(
            node_linking,
            function(node) return unit_api.has_node(source, node) end,
            function(node) return unit_api.has_node(target, node) end)
        local links = node_linking

        if reason == "ok" then
            if #valid == 0 and #skipped > 0 then
                local node, unit = first_missing(skipped)
                mod:info(
                    "[cos-hat] SKIP attach no shared nodes skipped=%d first_no_node=%s unit=%s",
                    #skipped, tostring(node), tostring(unit))
                return
            end

            if #skipped > 0 then
                local node, unit = first_missing(skipped)
                mod:info(
                    "[cos-hat] PARTIAL attach linked=%d skipped=%d first_no_node=%s unit=%s",
                    #valid, #skipped, tostring(node), tostring(unit))
            end

            links = valid
        end

        func(world, source, target, links)

        if not la_bridge.registered then return end
        if not unit_api.has_data(target, "unit_name") then return end
        la_bridge.maybe_queue_unit(world, target, unit_api.get_data(target, "unit_name"))
    end)

    return true
end

return M
