-- _mod_tweaker_search.lua -- pure expansion-state transactions for Mod Tweaker search.
--
-- Search temporarily renders matching branches open without making that presentation state
-- persistent. This module owns the snapshot/restore/commit math on ordinary Lua tables so the
-- behavior is covered by the engine-free Lua 5.1 suite as well as the in-game harness.
--
-- Owned by: _mod_tweaker_view.lua. Consumed via: mod:dofile.

local Search = {}

function Search.begin(expanded, group_keys, category)
    local snapshot = {}
    for i = 1, #(group_keys or {}) do
        local key = group_keys[i]
        if expanded and expanded[key] then snapshot[key] = true end
    end
    return {
        category = category,
        group_keys = group_keys or {},
        snapshot = snapshot,
    }
end

function Search.restore(expanded, transaction)
    if type(expanded) ~= "table" or type(transaction) ~= "table" then return end
    for i = 1, #(transaction.group_keys or {}) do
        expanded[transaction.group_keys[i]] = nil
    end
    for key in pairs(transaction.snapshot or {}) do expanded[key] = true end
end

function Search.commit(expanded, transaction, ancestors, auto_collapse)
    if type(expanded) ~= "table" or type(transaction) ~= "table" then return end
    if auto_collapse then
        for i = 1, #(transaction.group_keys or {}) do
            expanded[transaction.group_keys[i]] = nil
        end
    else
        Search.restore(expanded, transaction)
    end
    for i = 1, #(ancestors or {}) do expanded[ancestors[i]] = true end
end

-- Finish a search on explicit dismissal. Prefer the last setting the user changed; when the
-- search was only inspected, retain the first direct result's branch instead.
function Search.finish(expanded, transaction, last_changed, top_result, auto_collapse)
    local target = last_changed
    if type(target) ~= "table" then target = top_result end
    Search.commit(expanded, transaction, target or {}, auto_collapse)
end

function Search.group_keys(nodes, type_of, key_of)
    local result = {}
    for i = 1, #(nodes or {}) do
        if type_of(nodes[i]) == "group" then result[#result + 1] = key_of(nodes[i]) end
    end
    return result
end

-- Return the outer-to-inner group chain containing node[index]. The result itself is excluded
-- when it is a group: its own click still gets to perform the normal expand/collapse action.
function Search.ancestors(nodes, depths, index, type_of, key_of)
    local reversed, need = {}, depths and depths[index]
    if type(need) ~= "number" then return reversed end
    for i = index - 1, 1, -1 do
        local depth = depths[i]
        if type(depth) == "number" and depth < need then
            if type_of(nodes[i]) == "group" then reversed[#reversed + 1] = key_of(nodes[i]) end
            need = depth
            if need <= 0 then break end
        end
    end
    local result = {}
    for i = #reversed, 1, -1 do result[#result + 1] = reversed[i] end
    return result
end

return Search
