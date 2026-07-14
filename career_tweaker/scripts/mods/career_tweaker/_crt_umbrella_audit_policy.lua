-- Pure issue #221 catalog census. This deliberately does not implement subgroup
-- masters: the reported clusters cross independent reversible lifecycle owners.

local M = {}

M.ARMOR_IDS = {
    "armor_gromril_ignore_chip",
    "armor_specials_dont_break_gromril",
}

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

function M.snapshot(ensrick_ids, tourney_ids, get)
    get = get or function() return false end
    local ensrick_active, ensrick_total = count_matching(ensrick_ids, "", get)
    local tourney_active, tourney_total = count_matching(tourney_ids, "", get)
    local unchained_active, unchained_total = count_matching(ensrick_ids, "rework_bw_unchained_", get)
    local engineer_active, engineer_total = count_matching(ensrick_ids, "rework_dr_engineer_", get)
    local armor_active, armor_total = count_explicit(M.ARMOR_IDS, get)
    local runtime_active, runtime_total = count_explicit(M.UNCHAINED_RUNTIME_IDS, get)

    return {
        ensrick_active = ensrick_active, ensrick_total = ensrick_total,
        tourney_active = tourney_active, tourney_total = tourney_total,
        unchained_active = unchained_active, unchained_total = unchained_total,
        engineer_active = engineer_active, engineer_total = engineer_total,
        armor_active = armor_active, armor_total = armor_total,
        runtime_active = runtime_active, runtime_total = runtime_total,
    }
end

function M.format(s)
    return string.format(
        "[crt:221] whole_family=present ensrick=%d/%d tourney=%d/%d " ..
        "cluster_gates=0/4 unchained_reworks=%d/%d unchained_runtime=%d/%d " ..
        "engineer_reworks=%d/%d armor=%d/%d mutation=false",
        s.ensrick_active, s.ensrick_total, s.tourney_active, s.tourney_total,
        s.unchained_active, s.unchained_total, s.runtime_active, s.runtime_total,
        s.engineer_active, s.engineer_total, s.armor_active, s.armor_total)
end


return M
