-- Canonical pure exact-wire-catalog identity builder (issue #371 / class 64).
-- Consumer copies are synchronized by tools/shared_lib/sync-shared-libs.ps1.
--
-- Presence of the same mod is not proof that process-local NetworkLookup
-- integers have the same meaning. build_identity fingerprints a mandatory
-- semantic namespace plus every owned name, its exact bidirectional numeric id,
-- and (when supplied) the exact fallback name/id used by an unconditional
-- sender floor. No engine globals or hooks are owned here.

local M = {}

M.IDENTITY_VERSION = 1

local function _positive_integer(value)
    return type(value) == "number" and value > 0 and math.floor(value) == value
end

local function _feed_hash(seed, multiplier, modulus, value)
    for i = 1, #value do
        seed = (seed * multiplier + string.byte(value, i)) % modulus
    end
    return seed
end

local function _field(value)
    value = tostring(value)
    return tostring(#value) .. ":" .. value
end

-- entries is a map:
--   owned_name -> true                 (exact owned id only), or
--   owned_name -> "vanilla_fallback"  (exact owned + fallback identities).
-- Returns identity, error, sorted_names.
function M.build_identity(namespace, entries, lookup)
    if type(namespace) ~= "string" or namespace == "" then
        return nil, "namespace-missing"
    end
    if type(entries) ~= "table" or type(lookup) ~= "table" then
        return nil, "entries-or-lookup-missing"
    end

    local names = {}
    for name, fallback in pairs(entries) do
        if type(name) ~= "string" or name == "" then
            return nil, "invalid-entry-name"
        end
        if fallback ~= true and (type(fallback) ~= "string" or fallback == "") then
            return nil, "invalid-fallback:" .. name
        end
        names[#names + 1] = name
    end
    table.sort(names)
    if #names == 0 then return nil, "entries-empty" end

    -- Length-prefixed fields make the canonical stream unambiguous even when a
    -- legal lookup name contains separators or newlines.
    local canonical = {
        "wire-catalog-v", tostring(M.IDENTITY_VERSION), "|ns=", _field(namespace), "\n",
    }
    for i = 1, #names do
        local name = names[i]
        local id = rawget(lookup, name)
        if not _positive_integer(id) or rawget(lookup, id) ~= name then
            return nil, "lookup-mismatch:" .. name
        end
        canonical[#canonical + 1] = "n="
        canonical[#canonical + 1] = _field(name)
        canonical[#canonical + 1] = "|i="
        canonical[#canonical + 1] = tostring(id)

        local fallback = entries[name]
        if fallback == true then
            canonical[#canonical + 1] = "|f=0:|fi=0\n"
        else
            local fallback_id = rawget(lookup, fallback)
            if not _positive_integer(fallback_id)
                    or rawget(lookup, fallback_id) ~= fallback then
                return nil, "fallback-lookup-mismatch:" .. fallback
            end
            canonical[#canonical + 1] = "|f="
            canonical[#canonical + 1] = _field(fallback)
            canonical[#canonical + 1] = "|fi="
            canonical[#canonical + 1] = tostring(fallback_id)
            canonical[#canonical + 1] = "\n"
        end
    end

    local input = table.concat(canonical)
    local h1 = _feed_hash(104729, 131, 2147483647, input)
    local h2 = _feed_hash(130363, 257, 2147483629, input)
    return string.format("wire-v%d:%d:%08x:%08x",
        M.IDENTITY_VERSION, #names, h1, h2), nil, names
end

return M
