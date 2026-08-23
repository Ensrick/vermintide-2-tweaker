return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"

local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
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
        local meta_owner = read(base .. "_ct_meta_boon_owner.lua")
        H.truthy(balance:find("sync_reckless_swings = sync_reckless_swings", 1, true))
        H.truthy(registry:find("inject_dormant_boon = inject_dormant_boon", 1, true))
        H.truthy(meta:find("sync_host_dependent_state = sync_host_dependent_state", 1, true))
        H.truthy(meta:find("balance/registry modules must load before meta boons", 1, true))
        H.truthy(meta_owner:find("return function(mod, deps)", 1, true))
    end)

    H.test("CT meta boon owner is installed once with explicit dependencies", function()
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local owner = read(base .. "_ct_meta_boon_owner.lua")
        local owner_path = "scripts/mods/chaos_wastes_tweaker_dev/_ct_meta_boon_owner"

        H.equal(occurrences(meta, owner_path), 1,
            "meta-boon owner must have one wrapper load")
        H.equal(occurrences(meta, "install_meta_boons(mod, {"), 1,
            "meta-boon owner must have one synchronous install")
        H.truthy(meta:find("context = context", 1, true))
        H.truthy(meta:find("registry = registry", 1, true))
        H.equal(meta:find("pcall(install_meta_boons", 1, true), nil,
            "owner errors must propagate through the wrapper")

        local factory = assert(loadfile(base .. "_ct_meta_boon_owner.lua"))()
        H.equal(type(factory), "function")
        local ok, err = pcall(factory, {}, nil)
        H.equal(ok, false, "missing dependencies must fail closed")
        H.truthy(tostring(err):find("missing dependency table", 1, true))

        for _, marker in ipairs({
            "local CT_META_BOONS = {",
            "local function _make_meta_proc",
            "local function _ct_clamp_current_ammo_256",
            "power_ups.ct_meta_movespeed = {",
        }) do
            H.equal(meta:find(marker, 1, true), nil,
                marker .. " must not remain in the trait wrapper")
            H.truthy(owner:find(marker, 1, true),
                marker .. " must live in the meta-boon owner")
        end
    end)

    H.test("CT meta boon extraction ratchets both modules", function()
        local meta = read(base .. "_ct_meta_trait_boons.lua")
        local owner = read(base .. "_ct_meta_boon_owner.lua")
        local _, meta_lines = meta:gsub("\n", "\n")
        local _, owner_lines = owner:gsub("\n", "\n")
        H.truthy(meta_lines + 1 <= 1750,
            "trait wrapper regrew past the extraction ceiling")
        H.truthy(owner_lines + 1 < 1500,
            "new meta-boon owner must start below the target")
    end)
end
