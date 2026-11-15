-- WP-CIM-01 (#402, #1688): the shared official loadout guard keeps ids owned
-- by a mod out of the dirty_hero_data that vanilla _check_career_data returns
-- (Vermintide-2-Source-Code/scripts/managers/backend_playfab/playfab_mirror_base.lua:3409-3628),
-- while the live _career_data keeps the owned id equipped for the session.

local OWNED = "cim-owned-0001"

local function is_owned(value)
    return value == OWNED
end

local function fixture()
    local careers_data = {
        es_mercenary = {
            { slot_melee = "official-m1", slot_ranged = "official-r1" },
            { slot_melee = OWNED, slot_ranged = "official-r2" },
        },
    }
    local career_data_mirror = {
        es_mercenary = {
            { slot_melee = "official-m1", slot_ranged = "official-r1" },
            { slot_melee = "official-m2", slot_ranged = "official-r2" },
        },
    }
    return careers_data, career_data_mirror
end

-- Builds dirty_hero_data the way vanilla does: the loadout entry is a
-- reference to the live careers_data loadout table (playfab_mirror_base.lua:3523, :3541).
local function vanilla_like_func(seen)
    return function(self, careers_data, career_data_mirror)
        seen.self = self
        seen.mirror = career_data_mirror
        seen.value_during_call = careers_data.es_mercenary[2].slot_melee
        local dirty_hero_data = {
            empire_soldier = {
                careers = {
                    es_mercenary = {
                        loadouts = { ["2"] = careers_data.es_mercenary[2] },
                        deleted_loadouts = {},
                    },
                },
            },
        }
        return true, "characters-data-sentinel", dirty_hero_data
    end
end

local function contains_value(tbl, needle, visited)
    visited = visited or {}
    if visited[tbl] then return false end
    visited[tbl] = true
    for _, value in pairs(tbl) do
        if value == needle then return true end
        if type(value) == "table" and contains_value(value, needle, visited) then
            return true
        end
    end
    return false
end

return function(H, repo_root)
    local path = repo_root .. "/tools/shared_lib/_lib_official_loadout_guard.lua"

    local function load_guard()
        local chunk, err = loadfile(path)
        assert(chunk, "official loadout guard library is missing: " .. tostring(err))
        local M = chunk()
        assert(type(M) == "table", "official loadout guard must return a table")
        return M
    end

    H.test("official loadout guard: library exposes VERSION 1 and the four entry points", function()
        local M = load_guard()
        H.equal(M.VERSION, 1)
        H.equal(type(M.scrub), "function")
        H.equal(type(M.detach), "function")
        H.equal(type(M.restore), "function")
        H.equal(type(M.wrap), "function")
    end)

    H.test("official loadout guard (a): owned id is absent from dirty_hero_data and restored after wrap", function()
        local M = load_guard()
        local careers_data, career_data_mirror = fixture()
        local seen, reports = {}, {}
        local self_sentinel = {}
        local dirty, characters_data, dirty_hero_data = M.wrap(
            vanilla_like_func(seen), self_sentinel, careers_data, career_data_mirror,
            is_owned, function(subs, unsafe)
                reports[#reports + 1] = { subs, unsafe }
            end)

        H.equal(dirty, true, "first return passes through")
        H.equal(characters_data, "characters-data-sentinel", "second return passes through")
        H.truthy(rawequal(seen.self, self_sentinel), "self is forwarded")
        H.truthy(rawequal(seen.mirror, career_data_mirror), "mirror is forwarded")
        H.equal(seen.value_during_call, "official-m2", "func sees the mirror value")

        local sent = dirty_hero_data.empire_soldier.careers.es_mercenary.loadouts["2"]
        H.equal(sent.slot_melee, "official-m2", "payload carries the server value")
        H.equal(sent.slot_ranged, "official-r2", "payload keeps unrelated slots")
        H.truthy(not contains_value(dirty_hero_data, OWNED), "owned id absent from payload")
        H.equal(careers_data.es_mercenary[2].slot_melee, OWNED, "owned id equipped again after wrap")
        H.deep_equal(reports, { { 1, 0 } }, "report called once with subs and unsafe")
    end)

    H.test("official loadout guard (b): a loadout with no mirror row falls back to loadout 1", function()
        local M = load_guard()
        local careers_data, career_data_mirror = fixture()
        careers_data.es_mercenary[3] = { slot_melee = OWNED }

        local subs, unsafe = M.scrub(careers_data, career_data_mirror, is_owned)
        H.equal(unsafe, 0)
        H.equal(#subs, 2, "loadout 2 and loadout 3 substituted")
        H.equal(careers_data.es_mercenary[3].slot_melee, "official-m1", "fell back to loadout 1 mirror")
        H.equal(careers_data.es_mercenary[2].slot_melee, "official-m2")

        M.restore(careers_data, subs)
        H.equal(careers_data.es_mercenary[3].slot_melee, OWNED)
        H.equal(careers_data.es_mercenary[2].slot_melee, OWNED)
    end)

    H.test("official loadout guard (c): no mirror value at all counts unsafe and keeps the value", function()
        local M = load_guard()
        local careers_data = {
            es_mercenary = { { slot_trinket = "official-t1" }, { slot_trinket = OWNED } },
            dr_ranger = { { slot_melee = OWNED } },
        }
        local career_data_mirror = {
            es_mercenary = { { slot_melee = "official-m1" } },
        }

        local subs, unsafe = M.scrub(careers_data, career_data_mirror, is_owned)
        H.equal(#subs, 0)
        H.equal(unsafe, 2, "missing key and missing career both unsafe")
        H.equal(careers_data.es_mercenary[2].slot_trinket, OWNED)
        H.equal(careers_data.dr_ranger[1].slot_melee, OWNED)

        local reports = {}
        M.wrap(function() return false, nil, {} end, nil,
            careers_data, career_data_mirror, is_owned,
            function(n, u) reports[#reports + 1] = { n, u } end)
        H.deep_equal(reports, { { 0, 2 } }, "report fires on unsafe alone")
    end)

    H.test("official loadout guard (d): a raising func still restores and the error is re-raised", function()
        local M = load_guard()
        local careers_data, career_data_mirror = fixture()
        local value_during_call
        local ok, err = pcall(M.wrap, function(_, data)
            value_during_call = data.es_mercenary[2].slot_melee
            error("planted commit failure", 0)
        end, nil, careers_data, career_data_mirror, is_owned, function() end)

        H.equal(ok, false, "error propagates")
        H.equal(err, "planted commit failure", "error re-raised unchanged")
        H.equal(value_during_call, "official-m2")
        H.equal(careers_data.es_mercenary[2].slot_melee, OWNED, "restored after the error")
    end)

    H.test("official loadout guard (e): mutating careers_data after wrap leaves dirty_hero_data unchanged", function()
        local M = load_guard()
        local careers_data, career_data_mirror = fixture()
        local _, _, dirty_hero_data = M.wrap(vanilla_like_func({}), nil,
            careers_data, career_data_mirror, is_owned, function() end)
        local sent = dirty_hero_data.empire_soldier.careers.es_mercenary.loadouts["2"]

        H.truthy(not rawequal(sent, careers_data.es_mercenary[2]), "payload loadout is detached")
        careers_data.es_mercenary[2].slot_ranged = "changed-later"
        careers_data.es_mercenary[2].slot_melee = "changed-later"
        H.equal(sent.slot_ranged, "official-r2")
        H.equal(sent.slot_melee, "official-m2")
    end)

    H.test("official loadout guard (f): non-owned strings and non-string values are never touched", function()
        local M = load_guard()
        local nested = { inner = OWNED }
        local careers_data = {
            es_mercenary = {
                {
                    slot_melee = "official-m1",
                    count = 7,
                    flag = true,
                    nested = nested,
                    maybe = "truthy-but-not-true",
                },
            },
        }
        local career_data_mirror = {
            es_mercenary = {
                {
                    slot_melee = "mirror-m1",
                    count = 1,
                    flag = false,
                    nested = {},
                    maybe = "mirror-maybe",
                },
            },
        }
        local asked = {}
        local subs, unsafe = M.scrub(careers_data, career_data_mirror, function(value)
            asked[#asked + 1] = type(value)
            if value == "truthy-but-not-true" then return "yes" end
            return value == OWNED
        end)

        H.equal(#subs, 0)
        H.equal(unsafe, 0)
        for _, kind in ipairs(asked) do
            H.equal(kind, "string", "predicate only sees strings")
        end
        local loadout = careers_data.es_mercenary[1]
        H.equal(loadout.slot_melee, "official-m1")
        H.equal(loadout.count, 7)
        H.equal(loadout.flag, true)
        H.truthy(rawequal(loadout.nested, nested))
        H.equal(nested.inner, OWNED, "nested tables are not walked")
        H.equal(loadout.maybe, "truthy-but-not-true", "only a literal true owns a value")

        local reports = 0
        M.wrap(function() return false, nil, {} end, nil,
            careers_data, career_data_mirror, is_owned, function() reports = reports + 1 end)
        H.equal(reports, 0, "report stays silent with nothing to scrub")
    end)
end
