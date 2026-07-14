-- Pure tree-preserving ordering policy for Mod Tweaker setting rows.
--
-- VMF supplies a flat preorder list plus a depth per node.  Sorting that flat
-- list directly can separate a collapsible group from its descendants, so this
-- module first rebuilds the sibling tree, sorts each sibling list, then emits a
-- new preorder list while retaining the original depths and node identities.

local M = {}

local function _copy(values)
    local out = {}
    for i = 1, #values do out[i] = values[i] end
    return out
end

local function _safe(callback, value, fallback)
    if type(callback) ~= "function" then return fallback end
    local ok, result = pcall(callback, value)
    if ok and result ~= nil then return result end
    return fallback
end

local function _sort_siblings(siblings, options)
    for i = 1, #siblings do
        _sort_siblings(siblings[i].children, options)
    end

    -- Authored headers and dependency/order metadata denote organization.  A
    -- sibling list containing either is left intact rather than guessed at.
    -- VMF's generated per-mod header is different: it is a non-rendered anchor,
    -- so keep it in place while allowing the actual rows around it to sort.
    local sortable = {}
    for i = 1, #siblings do
        local node = siblings[i].node
        local is_header = _safe(options.get_type, node, nil) == "header"
        if (is_header and not _safe(options.is_generated_header, node, false))
                or _safe(options.has_explicit_order, node, false) then
            return
        end
        if not is_header then sortable[#sortable + 1] = siblings[i] end
    end

    table.sort(sortable, function(a, b)
        local ag = _safe(options.get_type, a.node, nil) == "group"
        local bg = _safe(options.get_type, b.node, nil) == "group"
        if ag ~= bg then return ag end

        local al = string.lower(tostring(_safe(options.get_label, a.node, "")))
        local bl = string.lower(tostring(_safe(options.get_label, b.node, "")))
        if al ~= bl then return al < bl end
        return a.index < b.index
    end)
    local next_sorted = 1
    for i = 1, #siblings do
        if _safe(options.get_type, siblings[i].node, nil) ~= "header" then
            siblings[i] = sortable[next_sorted]
            next_sorted = next_sorted + 1
        end
    end
end

local function _emit(records, nodes, depths)
    for i = 1, #records do
        local record = records[i]
        nodes[#nodes + 1] = record.node
        depths[#depths + 1] = record.depth
        _emit(record.children, nodes, depths)
    end
end

function M.order_flat(nodes, depths, options)
    options = options or {}
    if type(nodes) ~= "table" or type(depths) ~= "table" or #nodes ~= #depths
            or options.preserve_all then
        return _copy(nodes or {}), _copy(depths or {})
    end

    local roots, stack = {}, {}
    for i = 1, #nodes do
        local depth = tonumber(depths[i]) or 0
        local record = {
            node = nodes[i],
            depth = depth,
            index = i,
            children = {},
        }

        while #stack > 0 and stack[#stack].depth >= depth do
            stack[#stack] = nil
        end
        local parent = stack[#stack]
        local destination = parent and parent.children or roots
        destination[#destination + 1] = record
        stack[#stack + 1] = record
    end

    _sort_siblings(roots, options)
    local ordered_nodes, ordered_depths = {}, {}
    _emit(roots, ordered_nodes, ordered_depths)
    return ordered_nodes, ordered_depths
end

return M
