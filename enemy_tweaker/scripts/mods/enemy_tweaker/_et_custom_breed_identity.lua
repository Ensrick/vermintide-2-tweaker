-- Engine-free exact identity and spawn-floor policy for Enemy Tweaker's two
-- custom breeds (#451B). Numeric lookup ids are process-local, so same-mod
-- presence is insufficient: all three encoded/statistics axes and the
-- registrar semantic fingerprints must agree exactly.

local M = {}

M.IDENTITY_VERSION = 1
M.SPECS = {
    {
        name = "et_chosen_greataxe",
        owner = "enemy_tweaker.chosen_greataxe",
        fingerprint = "et-custom-breed:v4:chosen-greataxe:boss-parity",
        donor = "chaos_warrior",
    },
    {
        name = "et_skaven_warlord",
        owner = "enemy_tweaker.skaven_warlord",
        fingerprint = "et-custom-breed:v3:skaven-warlord:champion-pristine",
        donor = "skaven_storm_vermin_champion",
    },
}

local AXES = {
    { name = "breeds", marker_field = "breed_index" },
    { name = "damage_sources", marker_field = "damage_source_index" },
    { name = "statistics_path_names", marker_field = "statistics_path_index" },
}

local SPEC_BY_NAME = {}
for i = 1, #M.SPECS do
    SPEC_BY_NAME[M.SPECS[i].name] = M.SPECS[i]
end

local function _positive_integer(value)
    return type(value) == "number" and value > 0
        and value == math.floor(value) and value < math.huge
end

local function _field(value)
    value = tostring(value)
    return tostring(#value) .. ":" .. value
end

local function _hash(value)
    local h1, h2 = 104729, 130363
    for i = 1, #value do
        local byte = string.byte(value, i)
        h1 = (h1 * 131 + byte) % 2147483647
        h2 = (h2 * 257 + byte) % 2147483629
    end
    return string.format("etcb-v%d:%d:%08x:%08x",
        M.IDENTITY_VERSION, #M.SPECS, h1, h2)
end

function M.spec_for(name)
    return SPEC_BY_NAME[name]
end

function M.fingerprint_for(name)
    local spec = SPEC_BY_NAME[name]
    return spec and spec.fingerprint or nil
end

-- Capture both semantic and process-local identity. The marker ids are a
-- fourth authority over the three bidirectional NetworkLookup pairs: a table
-- that was shifted or partially rewritten after registrar commit is rejected.
function M.capture(context)
    context = type(context) == "table" and context or {}
    local breeds = context.breeds
    local network_lookup = context.network_lookup
    local marker_key = context.marker_key
    local registrar_schema = context.registrar_schema
    if type(breeds) ~= "table" or type(network_lookup) ~= "table" then
        return nil, "breed-or-network-lookup-missing"
    end
    if type(marker_key) ~= "string" or marker_key == "" then
        return nil, "registrar-marker-key-missing"
    end
    if not _positive_integer(registrar_schema) then
        return nil, "registrar-schema-invalid"
    end

    local snapshot = {
        breeds = breeds,
        network_lookup = network_lookup,
        marker_key = marker_key,
        registrar_schema = registrar_schema,
        axes = {},
        rows = {},
    }
    local canonical = {
        "et-custom-breeds-v", tostring(M.IDENTITY_VERSION),
        "|registrar=", tostring(registrar_schema), "\n",
    }

    for i = 1, #AXES do
        local axis = AXES[i]
        local lookup = rawget(network_lookup, axis.name)
        if type(lookup) ~= "table" then
            return nil, "lookup-axis-missing:" .. axis.name
        end
        snapshot.axes[i] = { name = axis.name, lookup = lookup }
    end

    -- SPECS is deliberately sorted by name. Assert that invariant so a future
    -- edit cannot silently make identity construction order-dependent.
    for i = 2, #M.SPECS do
        if M.SPECS[i - 1].name >= M.SPECS[i].name then
            return nil, "spec-order-invalid"
        end
    end

    for i = 1, #M.SPECS do
        local spec = M.SPECS[i]
        local breed = rawget(breeds, spec.name)
        local marker = type(breed) == "table" and rawget(breed, marker_key)
        if type(breed) ~= "table" or rawget(breed, "name") ~= spec.name then
            return nil, "breed-mismatch:" .. spec.name
        end
        if type(marker) ~= "table"
                or rawget(marker, "schema") ~= registrar_schema
                or rawget(marker, "owner") ~= spec.owner
                or rawget(marker, "fingerprint") ~= spec.fingerprint then
            return nil, "registrar-fingerprint-mismatch:" .. spec.name
        end

        local row = { spec = spec, breed = breed, marker = marker, ids = {} }
        canonical[#canonical + 1] = "name=" .. _field(spec.name)
            .. "|owner=" .. _field(spec.owner)
            .. "|fp=" .. _field(spec.fingerprint)
        for a = 1, #AXES do
            local axis = AXES[a]
            local lookup = snapshot.axes[a].lookup
            local id = rawget(lookup, spec.name)
            if not _positive_integer(id) or rawget(lookup, id) ~= spec.name then
                return nil, "lookup-asymmetric:" .. axis.name .. ":" .. spec.name
            end
            if rawget(marker, axis.marker_field) ~= id then
                return nil, "registrar-id-mismatch:" .. axis.name .. ":" .. spec.name
            end
            row.ids[a] = id
            canonical[#canonical + 1] = "|" .. axis.name .. "=" .. tostring(id)
        end
        canonical[#canonical + 1] = "\n"
        snapshot.rows[i] = row
    end

    snapshot.identity = _hash(table.concat(canonical))
    return snapshot
end

-- Re-prove the load-time snapshot at every custom-breed emission. This is
-- intentionally reference-exact as well as value-exact: replacing a breed,
-- marker, NetworkLookup root, or axis table retires the proof for the session.
function M.intact(snapshot, current)
    if type(snapshot) ~= "table" or type(snapshot.rows) ~= "table"
            or type(snapshot.axes) ~= "table" then
        return false, "snapshot-invalid"
    end
    if type(current) ~= "table"
            or current.breeds ~= snapshot.breeds
            or current.network_lookup ~= snapshot.network_lookup then
        return false, "global-root-replaced"
    end
    if type(snapshot.network_lookup) ~= "table"
            or type(snapshot.breeds) ~= "table" then
        return false, "snapshot-roots-invalid"
    end
    for a = 1, #AXES do
        local axis = snapshot.axes[a]
        if type(axis) ~= "table" or axis.name ~= AXES[a].name
                or rawget(snapshot.network_lookup, axis.name) ~= axis.lookup then
            return false, "lookup-axis-replaced:" .. AXES[a].name
        end
    end
    for i = 1, #M.SPECS do
        local expected = M.SPECS[i]
        local row = snapshot.rows[i]
        if type(row) ~= "table" or row.spec ~= expected
                or rawget(snapshot.breeds, expected.name) ~= row.breed
                or rawget(row.breed, snapshot.marker_key) ~= row.marker then
            return false, "breed-or-marker-replaced:" .. expected.name
        end
        if rawget(row.breed, "name") ~= expected.name
                or rawget(row.marker, "schema") ~= snapshot.registrar_schema
                or rawget(row.marker, "owner") ~= expected.owner
                or rawget(row.marker, "fingerprint") ~= expected.fingerprint then
            return false, "registrar-fingerprint-drift:" .. expected.name
        end
        for a = 1, #AXES do
            local axis = AXES[a]
            local id = row.ids[a]
            local lookup = snapshot.axes[a].lookup
            if rawget(lookup, expected.name) ~= id
                    or rawget(lookup, id) ~= expected.name
                    or rawget(row.marker, axis.marker_field) ~= id then
                return false, "lookup-drift:" .. axis.name .. ":" .. expected.name
            end
        end
    end
    return true
end

local function _validated_donor(spec, breeds, network_lookup)
    local donor = type(breeds) == "table" and rawget(breeds, spec.donor)
    local lookup = type(network_lookup) == "table"
        and rawget(network_lookup, "breeds") or nil
    local id = type(lookup) == "table" and rawget(lookup, spec.donor) or nil
    if type(donor) ~= "table" or rawget(donor, "name") ~= spec.donor
            or not _positive_integer(id) or rawget(lookup, id) ~= spec.donor then
        return nil, "donor-invalid:" .. spec.donor
    end
    return donor
end

-- The final sender floor. It recognizes custom intent by NAME, so another mod
-- (including General Tweaker's enumerated creature spawner) cannot bypass it by
-- holding a stale/fabricated table. Exact-safe custom sends must additionally
-- use the canonical Breeds[name] object; every other case receives the vanilla
-- donor or fails without emitting a custom id.
function M.resolve_spawn_breed(requested, exact_safe, breeds, network_lookup)
    if type(requested) ~= "table" then return requested, "not-a-breed" end
    local name = rawget(requested, "name")
    local spec = SPEC_BY_NAME[name]
    if not spec then return requested, "vanilla" end
    if exact_safe == true and type(breeds) == "table"
            and rawget(breeds, name) == requested then
        return requested, "exact-custom"
    end
    local donor, reason = _validated_donor(spec, breeds, network_lookup)
    if not donor then return nil, reason end
    return donor, "vanilla-donor"
end

-- Call the runtime floor without permitting the generic protective hook's
-- vanilla fallback to re-emit a custom breed after a floor error. Ordinary
-- vanilla breeds never need parity work and stay untouched even if the floor
-- is absent or throwing. Custom intent is recognized by name, including a
-- fabricated/stale table supplied by another mod.
function M.guard_spawn_surface(requested, surface, floor)
    if type(requested) ~= "table" then return requested, "not-a-breed" end
    local spec = SPEC_BY_NAME[rawget(requested, "name")]
    if not spec then return requested, "vanilla" end
    if type(floor) ~= "function" then return nil, "floor-unavailable" end
    local ok, resolved, decision = pcall(floor, requested, surface)
    if not ok then return nil, "floor-threw" end
    if resolved == nil then return nil, decision or "floor-rejected" end
    return resolved, decision
end

return M
