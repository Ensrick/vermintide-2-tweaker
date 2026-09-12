-- Pure issue #221 catalog census. The census itself never writes a setting; it
-- reports which of the four proposed subgroup clusters now has a registered
-- cluster master in the rework-master policy (M.FAMILIES entries with `ids`).

local M = {}

-- Proposed subgroup clusters: Unchained reworks, Outcast Engineer reworks,
-- armor controls, per-career controls. A gate counts only once the policy
-- registers a cluster family whose master owns the complete leaf list.
M.CLUSTER_TOTAL = 4

M.UNCHAINED_RUNTIME_IDS = {
    "unchained_no_overcharge_from_disablers",
    "unchained_no_overcharge_from_ff",
    "unchained_no_overcharge_from_self_dot",
}

local function count_matching(ids, prefix, get)
    local active, total = 0, 0
    for i = 1, #(ids or {}) do
        if string.sub(ids[i], 1, #prefix) == prefix then
            total = total + 1
            if get(ids[i]) then active = active + 1 end
        end
    end
    return active, total
end

local function count_explicit(ids, get)
    local active = 0
    for i = 1, #ids do
        if get(ids[i]) then active = active + 1 end
    end
    return active, #ids
end

local function is_cluster(metadata)
    return type(metadata) == "table"
        and type(metadata.ids) == "table"
        and type(metadata.master_id) == "string"
end

-- Number of registered cluster families in the rework-master metadata.
function M.gated_clusters(families)
    local count = 0
    for _, metadata in pairs(families or {}) do
        if is_cluster(metadata) then count = count + 1 end
    end
    return count
end

-- Leaf list a registered cluster owns, or an empty list while it is deferred.
function M.cluster_ids(families, family)
    local metadata = families and families[family]
    if is_cluster(metadata) then return metadata.ids end
    return {}
end

function M.snapshot(ensrick_ids, tourney_ids, get, families)
    get = get or function() return false end
    local ensrick_active, ensrick_total = count_matching(ensrick_ids, "", get)
    local tourney_active, tourney_total = count_matching(tourney_ids, "", get)
    local unchained_active, unchained_total = count_matching(ensrick_ids, "rework_bw_unchained_", get)
    local engineer_active, engineer_total = count_matching(ensrick_ids, "rework_dr_engineer_", get)
    local armor_active, armor_total = count_explicit(M.cluster_ids(families, "armor"), get)
    local runtime_active, runtime_total = count_explicit(M.UNCHAINED_RUNTIME_IDS, get)

    return {
        ensrick_active = ensrick_active, ensrick_total = ensrick_total,
        tourney_active = tourney_active, tourney_total = tourney_total,
        cluster_gates = M.gated_clusters(families), cluster_total = M.CLUSTER_TOTAL,
        unchained_active = unchained_active, unchained_total = unchained_total,
        engineer_active = engineer_active, engineer_total = engineer_total,
        armor_active = armor_active, armor_total = armor_total,
        runtime_active = runtime_active, runtime_total = runtime_total,
    }
end

function M.format(s)
    return string.format(
        "[crt:221] whole_family=present ensrick=%d/%d tourney=%d/%d " ..
        "cluster_gates=%d/%d unchained_reworks=%d/%d unchained_runtime=%d/%d " ..
        "engineer_reworks=%d/%d armor=%d/%d mutation=false",
        s.ensrick_active, s.ensrick_total, s.tourney_active, s.tourney_total,
        s.cluster_gates or 0, s.cluster_total or M.CLUSTER_TOTAL,
        s.unchained_active, s.unchained_total, s.runtime_active, s.runtime_total,
        s.engineer_active, s.engineer_total, s.armor_active, s.armor_total)
end


return M
