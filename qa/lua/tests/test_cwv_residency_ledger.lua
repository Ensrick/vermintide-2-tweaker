-- resource-safety: cwv1159-husk-residency-force-load
--
-- Offline lock for #401: the husk override-unit residency ledger must record
-- SUCCESS (not attempts), and failed loads must be re-attempted on a bounded
-- retry path. The pass lives in _cwv_husk_residency_owner (moved verbatim out
-- of the CWV entry chunk by the #1159 slice), so these are source-pattern
-- locks on the exact ordering and retry markers in that module, plus an
-- entry-side assertion that no shadowing copy of the pass was left behind.

local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(H, repo_root)
    local mod_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local entry_path = mod_root .. "_cwv_husk_residency_owner.lua"
    local main_entry_path = mod_root .. "character_weapon_variants.lua"

    local function find_all(source, needle)
        local positions = {}
        local from = 1
        while true do
            local at = source:find(needle, from, true)
            if not at then break end
            positions[#positions + 1] = at
            from = at + 1
        end
        return positions
    end

    H.test("CWV husk residency force-loads keep their resource-safety marker", function()
        -- check_native_resource_safety is a diff gate: both Managers.package:load
        -- boundaries in this module are covered by one file-level marker, and the
        -- token must resolve to qa/ evidence. This test IS that evidence, so the
        -- marker and the two boundaries it covers are pinned together here.
        local source = read(entry_path)
        H.truthy(source:find("resource-safety: cwv1159-husk-residency-force-load", 1, true),
            "husk-residency owner lost its resource-safety marker")
        -- Match the executable call form, not the bare prefix: a doc comment
        -- above the first pass quotes the idiom as
        -- `Managers.package:load(unit_path, ref, nil, sync=true, ...)`, so a
        -- prefix count would read 3 and drift the moment that prose is edited.
        H.equal(#find_all(source, "Managers.package:load(path, ref, nil, true, true)"), 2,
            "exactly two package-load boundaries are covered by that one marker")
        H.equal(#find_all(read(main_entry_path), "resource-safety: cwv1159-husk-residency-force-load"), 0,
            "the marker must not be duplicated back into the entry")
    end)

    H.test("CWV #401 residency ledger records success only AFTER the load call", function()
        local source = read(entry_path)
        local ledger_writes = find_all(source, "_loaded[path] = true")
        H.equal(#ledger_writes, 1,
            "exactly one ledger write expected in the residency pass")
        local load_call = source:find(
            "Managers.package:load(path, ref, nil, true, true)", 1, true)
        H.truthy(load_call, "residency force-load call missing")
        H.truthy(load_call < ledger_writes[1],
            "#401: the ledger must be written AFTER the pcall load, "
            .. "inside the success branch -- not before the attempt")
        -- The write must sit inside `if ok then`, i.e. between the pcall result
        -- check and the failure branch.
        local ok_branch = source:find("if ok then", load_call, true)
        H.truthy(ok_branch and ok_branch < ledger_writes[1],
            "#401: ledger write is not guarded by the load-call success branch")
    end)

    H.test("CWV #401 failed residency loads are re-attempted on a bounded retry", function()
        local source = read(entry_path)
        H.truthy(source:find("_attempts[path] = (_attempts[path] or 0) + 1", 1, true),
            "per-path attempt counter missing")
        H.truthy(source:find("(_attempts[path] or 0) < _MAX_LOAD_ATTEMPTS", 1, true),
            "attempt cap missing -- the retry must be bounded")
        H.truthy(source:find("_MAX_LOAD_ATTEMPTS = {}, 3", 1, true)
                or source:find("local _MAX_LOAD_ATTEMPTS = 3", 1, true),
            "bounded retry cap constant missing")
        local calls = find_all(source, "_force_load_husk_override_units()")
        H.truthy(#calls >= 2,
            "the residency pass must run again on the retry edge "
            .. "(boot pass + on_all_mods_loaded), found " .. #calls .. " call(s)")
        H.truthy(source:find("previous_on_all_mods_loaded", 1, true),
            "the retry edge must preserve the earlier mod.on_all_mods_loaded handler")
    end)

    H.test("CWV #1159 the entry keeps no shadowing copy of the residency pass", function()
        -- The pass moved to _cwv_husk_residency_owner. A leftover copy in the
        -- entry would double every force-load and re-chain on_all_mods_loaded
        -- twice, so the entry must be clear of every producer marker.
        local entry = read(main_entry_path)
        for _, marker in ipairs({
            "local function _force_load_husk_override_units()",
            "local function _force_load_axe_shield_husk_units()",
            "_loaded[path] = true",
            "_attempts[path] = (_attempts[path] or 0) + 1",
            "_om._husk_override_unit_needs_residency = function(def, field)",
        }) do
            H.equal(#find_all(entry, marker), 0,
                "entry must not retain residency-pass marker: " .. marker)
        end
        -- ...and it must load the owner exactly once, at one site.
        H.equal(#find_all(entry, "_cwv_husk_residency_owner"), 1,
            "entry must dofile the residency owner from exactly one site")
    end)
end
