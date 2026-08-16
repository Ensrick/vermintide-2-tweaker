-- Pure authored-pose catalog policy for issue #485. Engine-free for QA.
local Policy = {}

function Policy.build_catalog(item_master_list)
    local by_parent = {}
    if type(item_master_list) ~= "table" then return by_parent end

    for item_name, data in pairs(item_master_list) do
        if type(data) == "table"
            and data.item_type == "weapon_pose"
            and type(data.parent) == "string"
            and type(data.pose_index) == "number"
            and type(data.data) == "table"
            and type(data.data.anim_event) == "string" then
            local rows = by_parent[data.parent]
            if not rows then
                rows = {}
                by_parent[data.parent] = rows
            end
            rows[#rows + 1] = {
                ItemId = item_name,
                backend_id = "cos_pose:" .. item_name,
                data = data,
                rarity = data.rarity or "default",
            }
        end
    end

    for _, rows in pairs(by_parent) do
        table.sort(rows, function(a, b)
            if a.data.pose_index == b.data.pose_index then
                return a.ItemId < b.ItemId
            end
            return a.data.pose_index < b.data.pose_index
        end)
    end

    return by_parent
end

function Policy.for_parent(catalog, parent_item)
    if type(catalog) ~= "table" or type(parent_item) ~= "string" then return nil end
    local rows = catalog[parent_item]
    if type(rows) ~= "table" or #rows == 0 then return nil end
    return rows
end

-- #485: the gather decision truth table. Realm, setting, and catalog support
-- are three orthogonal axes with three DISTINCT vanilla outcomes plus the one
-- authored outcome; the official realm always wins over the setting so the
-- decision can never leak authored rows into trusted play.
function Policy.decide(setting_on, untrusted_realm, rows)
    if untrusted_realm ~= true then return "vanilla-official-realm" end
    if setting_on ~= true then return "vanilla-setting-off" end
    if type(rows) ~= "table" or #rows == 0 then
        return "vanilla-unsupported-parent"
    end
    return "authored"
end

-- #485: exactly one armed wheel rebuild per option flip. Arms (returns true)
-- only when the live enable state CHANGED since the holder last saw it; a
-- steady state defers to vanilla's own dirty logic.
function Policy.rebuild_armed(holder, key, live)
    if type(holder) ~= "table" then return false end
    if holder[key] == live then return false end
    holder[key] = live
    return true
end

-- #485: execute a built catalog against its source master list and report the
-- first contract violation (nil = clean). Written as an independent walk, not
-- a call back into build_catalog, so a builder drift cannot self-certify:
--   * exact-parent completeness - every animation-backed authored weapon_pose
--     row appears under exactly its own parent, and nothing else appears;
--   * deterministic order - pose_index then ItemId, stable across rebuilds;
--   * animation-backed rows only - each row keeps a string anim_event;
--   * no ownership-table writes - rows alias the master data untouched and
--     the synthetic backend identity never leaks onto the master row.
function Policy.validate_catalog(catalog, item_master_list)
    if type(catalog) ~= "table" or type(item_master_list) ~= "table" then
        return "catalog and master list are required"
    end
    local expected = {}
    for item_name, data in pairs(item_master_list) do
        if type(data) == "table"
            and data.item_type == "weapon_pose"
            and type(data.parent) == "string"
            and type(data.pose_index) == "number"
            and type(data.data) == "table"
            and type(data.data.anim_event) == "string" then
            expected[data.parent] = (expected[data.parent] or 0) + 1
        end
    end
    for parent, rows in pairs(catalog) do
        if not expected[parent] then
            return "catalog invented parent " .. tostring(parent)
        end
        if type(rows) ~= "table" or #rows ~= expected[parent] then
            return string.format("parent %s carries %d row(s), authored %d",
                tostring(parent), type(rows) == "table" and #rows or -1,
                expected[parent])
        end
        local prev
        for _, row in ipairs(rows) do
            local source = item_master_list[row.ItemId]
            if type(source) ~= "table" or row.data ~= source then
                return "row is not the master-list table: " .. tostring(row.ItemId)
            end
            if source.parent ~= parent then
                return "cross-parent row " .. tostring(row.ItemId)
                    .. " under " .. tostring(parent)
            end
            if type(source.data) ~= "table"
                or type(source.data.anim_event) ~= "string" then
                return "row without animation backing: " .. tostring(row.ItemId)
            end
            if row.backend_id ~= "cos_pose:" .. row.ItemId then
                return "row backend identity drifted: " .. tostring(row.ItemId)
            end
            if source.backend_id ~= nil then
                return "ownership write: backend id stamped onto master row "
                    .. tostring(row.ItemId)
            end
            if prev and (prev.data.pose_index > source.pose_index
                    or (prev.data.pose_index == source.pose_index
                        and prev.ItemId >= row.ItemId)) then
                return "unsorted rows under " .. tostring(parent)
            end
            prev = row
        end
    end
    for parent in pairs(expected) do
        if catalog[parent] == nil then
            return "authored parent missing from catalog: " .. tostring(parent)
        end
    end
    return nil
end

return Policy
