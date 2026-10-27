-- _cwv_profile_graph_transaction.lua -- Pure bounded graph and raw-cell mechanics.
--
-- Owns graph identity snapshots and attempted-write/readback rollback only.
-- Family adapters retain donor, math, fallback and admission policy.
-- No engine globals, module loads, owner registry, hook or automatic retry.
--
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one entry mod:dofile and private function-reference binding.
local function capture(value, max_nodes, max_cells, include)
    local nodes, seen, cells = {}, {}, 0
    local function visit(t)
        if seen[t] then return true end
        if #nodes >= max_nodes then return false end
        seen[t] = true
        local row = { target = t, meta = getmetatable(t), fields = {}, count = 0, include = include }
        nodes[#nodes + 1] = row
        for key, child in next, t do
            if not include or include(t, key) then
            cells = cells + 1
            if cells > max_cells then return false end
            row.count = row.count + 1
            row.fields[#row.fields + 1] = { key, child }
            if type(child) == "table" and not visit(child) then return false end
            end
        end
        return true
    end
    return type(value) == "table" and visit(value) and nodes or nil
end
local function intact(nodes, bounded)
    if not nodes then return false end
    for i = 1, #nodes do
        local row, count = nodes[i], 0
        -- Opt-in retained-frame readback never runs an include callback or an
        -- unbounded added-key census. The default transaction proof is exact.
        if bounded and row.include ~= nil then return false end
        if getmetatable(row.target) ~= row.meta then return false end
        for j = 1, #row.fields do
            local cell = row.fields[j]
            if rawget(row.target, cell[1]) ~= cell[2] then return false end
        end
        for key in next, row.target do
            if not row.include or row.include(row.target, key) then count = count + 1 end
            if bounded and count > row.count then return false end
        end
        if count ~= row.count then return false end
    end
    return true
end
local function disjoint(a, b)
    if not a or not b then return false end
    local seen = {}
    for i = 1, #a do seen[a[i].target] = true end
    for i = 1, #b do if seen[b[i].target] then return false end end
    return true
end
local function rollback(changes)
    for i = #changes, 1, -1 do
        local row = changes[i]
        if row.attempted then rawset(row[1], row[2], row.before) end
    end
end
local function commit(changes, before, after, read, write)
    local ok = pcall(function()
        before()
        for i = 1, #changes do
            local row = changes[i]
            if rawget(row[1], row[2]) ~= row.before then error("preimage changed") end
            row.attempted = true
            write(row[1], row[2], row[3], row[4])
            if read(row[1], row[2], row[4]) ~= row[3] then error("publication readback rejected") end
        end
        after()
    end)
    if not ok then rollback(changes) end
    return ok
end
return { capture = capture, intact = intact, disjoint = disjoint, commit = commit }
