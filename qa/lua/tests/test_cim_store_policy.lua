-- WP-CIM-06 (#1654, #277): pure checks for the crafted-item store
-- (crafting_in_modded_dev/.../_cim_store_policy.lua). VMF serializes every
-- mod's settings as one table; a mixed array/map table breaks that save for all
-- mods (Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/settings.lua:5-6, 19-33).

local function deep_copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deep_copy(v) end
    return copy
end

return function(H, repo_root)
    local path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_store_policy.lua"

    local function load_policy()
        local chunk, err = loadfile(path)
        assert(chunk, "cim store policy module is missing: " .. tostring(err))
        return chunk()
    end

    H.test("cim store policy: scalars, maps, arrays and empty tables are serializable", function()
        local M = load_policy()
        H.equal(M.is_serializable(1.5), true)
        H.equal(M.is_serializable("x"), true)
        H.equal(M.is_serializable(false), true)
        H.equal(M.is_serializable({}), true, "empty table")
        H.equal(M.is_serializable({ a = 1, b = { c = "d" } }), true, "nested map")
        H.equal(M.is_serializable({ { 1, 2 }, { 3, { 4, 5 } } }), true, "nested arrays")
        H.equal(M.is_serializable({ traits = { "a", "b" }, n = 2 }), true, "map holding an array")
    end)

    H.test("cim store policy: mixed, sparse and odd-key tables are not serializable", function()
        local M = load_policy()
        H.equal(M.is_serializable({ 1, 2, x = 3 }), false, "mixed keys")
        H.equal(M.is_serializable({ [1] = "a", [3] = "c" }), false, "sparse array")
        H.equal(M.is_serializable({ [0] = "zero" }), false, "zero key")
        H.equal(M.is_serializable({ [1.5] = "half" }), false, "fractional key")
        H.equal(M.is_serializable({ a = { 1, b = 2 } }), false, "nested mixed")
        H.equal(M.is_serializable(function() end), false, "function")
    end)

    H.test("cim store policy: validate_store names the backend id and the field path", function()
        local M = load_policy()
        H.equal(M.validate_store({}), true)
        H.equal(M.validate_store({
            good = { item_key = "es_2h_sword", properties = { attack_speed = 0 }, traits = { "t" } },
        }), true)
        local ok, backend_id, field = M.validate_store({
            good = { item_key = "es_2h_sword", properties = {} },
            bad = { item_key = "es_2h_sword", properties = { attack_speed = 0, [1] = 2 } },
        })
        H.equal(ok, false)
        H.equal(backend_id, "bad")
        H.equal(field, "properties")
        ok, backend_id, field = M.validate_store({
            deep = { custom_glow = { layers = { { 1, 2 }, { 3, x = 4 } } } },
        })
        H.equal(ok, false)
        H.equal(backend_id, "deep")
        H.equal(field, "custom_glow.layers.2")
    end)

    H.test("cim store policy: merge_missing adds only missing ids and mutates nothing", function()
        local M = load_policy()
        local target = { a = { item_key = "live_a" }, b = { item_key = "live_b" } }
        local source = { b = { item_key = "backup_b" }, c = { item_key = "backup_c" } }
        local target_before, source_before = deep_copy(target), deep_copy(source)
        local merged, added = M.merge_missing(target, source)
        H.equal(added, 1)
        H.equal(merged.a.item_key, "live_a")
        H.equal(merged.b.item_key, "live_b", "existing id is never overwritten")
        H.equal(merged.c.item_key, "backup_c")
        H.truthy(not rawequal(merged, target), "a new table")
        H.deep_equal(target, target_before, "target unchanged")
        H.deep_equal(source, source_before, "source unchanged")
        H.equal(M.count(merged), 3)
        H.equal(M.count(nil), 0)
        local _, none = M.merge_missing(target, nil)
        H.equal(none, 0)
    end)
end
