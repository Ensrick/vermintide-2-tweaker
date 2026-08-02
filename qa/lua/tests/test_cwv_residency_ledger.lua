-- Offline lock for #401: the husk override-unit residency ledger must record
-- SUCCESS (not attempts), and failed loads must be re-attempted on a bounded
-- retry path. The pass is inline in the CWV entry chunk, so these are
-- source-pattern locks on the exact ordering and retry markers.

local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(H, repo_root)
    local entry_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"

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
end
