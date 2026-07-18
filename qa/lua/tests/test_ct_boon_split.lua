return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(source, needle)
        local count, at = 0, 1
        while true do
            local found = source:find(needle, at, true)
            if not found then return count end
            count = count + 1
            at = found + #needle
        end
    end

    H.test("CT boon split stays below the frozen entry-file baseline", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        local _, lines = source:gsub("\n", "\n")
        -- 12040 = 2026-07-18 ratchet after the OOP W5 regression-suite extraction
        -- (_ct_regression.lua) shrank the entry. This physical-line ceiling only
        -- moves DOWN; the tighter non-empty ceiling lives in
        -- test_ct_entry_decomposition.lua.
        H.truthy(lines + 1 < 12040, "CT entry file regrew to its frozen baseline")
    end)

    H.test("CT boon split loads each explicit owner once in dependency order", function()
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
        local names = {
            "_ct_boon_balance",
            "_ct_boon_registry",
            "_ct_meta_trait_boons",
        }
        local previous = 0
        for _, name in ipairs(names) do
            local needle = 'mod:dofile(\n    "scripts/mods/chaos_wastes_tweaker_dev/' .. name .. '")'
            H.equal(occurrences(source, needle), 1, name .. " must have one entry-manifest load")
            local at = assert(source:find(needle, 1, true))
            H.truthy(at > previous, name .. " loaded out of dependency order")
            previous = at
        end
        H.equal(source:find("_ct_boon_runtime\")", 1, true), nil)
    end)

    H.test("CT boon split publishes only the bounded cross-module contracts", function()
        local balance = read(base .. "_ct_boon_balance.lua")
        local registry = read(base .. "_ct_boon_registry.lua")
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        H.truthy(balance:find("sync_reckless_swings = sync_reckless_swings", 1, true))
        H.truthy(registry:find("inject_dormant_boon = inject_dormant_boon", 1, true))
        H.truthy(meta:find("sync_host_dependent_state = sync_host_dependent_state", 1, true))
        H.truthy(meta:find("balance/registry modules must load before meta boons", 1, true))
    end)
end
