-- Offline fixture only: actual entry/history owner/runtime/policy/transaction.
-- The catalog seam projects one real source family, not a copied WT algorithm.
local M = {}
local CP = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
local FAMILY, SETTING, STATE = "tuskgor_spear", "wt_history_tuskgor_spear", "pre_3_1_delta"
function M.bind(H, root, c)
    local mods, records = {}, {}
    c.env.get_mod = function(id) return mods[id] end
    local common_api = c.T.run(c.T.read(root .. CP .. "_cwv_history_producer_binding.lua"), c.env, "actual-Tuskgor-common-binding")
    local common = common_api.bind(c.graph, c.env.get_mod)
    local envelope_api = c.T.run(c.T.read(root .. CP .. "_cwv_tuskgor_history_envelope.lua"), c.env, "actual-Tuskgor-history-envelope")
    local envelope = envelope_api.bind(c.graph, common)
    local function install(id, selection)
        assert(id == "wt" or id == "wt_dev"); assert(records[id] == nil, "one actual owner per namespace")
        local dir = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
        local module_root, saved = "scripts/mods/" .. dir .. "/", selection or "current"
        local record = { getter_calls = 0 }
        local mod = { get = function(_, key)
            H.equal(key, SETTING); record.getter_calls = record.getter_calls + 1; return saved
        end, _wt431_profiles_allowed = function() return true end }
        mod.dofile = function(_, path)
            local actual = c.T.run(c.T.read(root .. "/" .. dir .. "/" .. path .. ".lua"), c.env, path)
            if path ~= module_root .. "_wt_history_catalog" then return actual end
            return { load = function(actual_mod)
                H.equal(actual_mod, mod)
                local catalog, problem = actual.load(mod, { module_root .. "_wt_history_3_1_catalog" })
                H.truthy(catalog, problem)
                local selected, family = {}, nil
                for key, value in next, catalog do selected[key] = value end
                for _, row in ipairs(catalog.families) do if row.id == FAMILY then
                    H.equal(family, nil); family = row
                end end
                H.truthy(family); selected.families = { family }
                return actual.merge({ selected })
            end }
        end
        mods[id] = mod
        local entry = c.T.read(root .. "/" .. dir .. "/" .. module_root .. dir .. ".lua")
        local first = "local _wt_history_owner, _wt_history_verify = mod:dofile("
        local at = assert(entry:find(first, 1, true)); assert(not entry:find(first, at + 1, true))
        local finish = assert(entry:find("\n-- Bret Sword & Shield damage buff", at, true))
        local invoke = c.T.run("return function(mod)\n" .. entry:sub(at, finish - 1)
            .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env, "actual-Tuskgor-WT-entry-owner")
        record.owner, record.verify, record.runtime = invoke(mod)
        record.mod = mod
        H.equal(mod._wt_history_runtime, record.runtime); H.equal(record.runtime.fatal_error, nil)
        H.equal(record.runtime.last_error, nil); H.equal(record.verify(), nil)
        records[id] = record
        function record.pending(value)
            saved = value
            H.equal(record.runtime:on_setting_changed(SETTING), true)
        end
        return record
    end
    return { envelope = envelope, install = install, mods = mods, records = records,
        family = FAMILY, setting = SETTING, historical = STATE }
end
return M
