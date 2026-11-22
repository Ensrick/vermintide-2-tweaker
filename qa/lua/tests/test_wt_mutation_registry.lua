-- WP-WT-07: the ordered mutation registry (_wt_mutation_registry.lua, pure)
-- that every wt lifecycle event uses to apply and revert the weapon-table
-- owners in one fixed order.

return function(H, repo_root)
    local trees = {
        { name = "wt", path = repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_mutation_registry.lua" },
        { name = "wt_dev", path = repo_root
            .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_mutation_registry.lua" },
    }

    local function new_registry(path)
        local logged = {}
        local M = dofile(path)
        local reg = M.new(function(fmt, ...) logged[#logged + 1] = string.format(fmt, ...) end)
        return reg, logged
    end

    for _, tree in ipairs(trees) do
        H.test(tree.name .. " registry applies by order with the reason and reverts in reverse", function()
            local reg = new_registry(tree.path)
            local calls = {}
            for _, order in ipairs({ 30, 10, 20 }) do
                local id = "o" .. order
                reg.register({ id = id, order = order,
                    apply = function(reason) calls[#calls + 1] = "apply:" .. id .. ":" .. tostring(reason) end,
                    revert = function() calls[#calls + 1] = "revert:" .. id end })
            end
            H.deep_equal(reg.ids(), { "o10", "o20", "o30" })
            local ok, failed = reg.reconcile("probe")
            H.equal(ok, true)
            H.deep_equal(failed, {})
            H.deep_equal(calls, { "apply:o10:probe", "apply:o20:probe", "apply:o30:probe" })
            for i = #calls, 1, -1 do calls[i] = nil end
            local rok, restart_bound = reg.revert_all()
            H.equal(rok, true)
            H.deep_equal(restart_bound, {})
            H.deep_equal(calls, { "revert:o30", "revert:o20", "revert:o10" })
        end)

        H.test(tree.name .. " registry logs a raising apply and still runs the others", function()
            local reg, logged = new_registry(tree.path)
            local ran = {}
            reg.register({ id = "first", order = 10, apply = function() ran[#ran + 1] = "first" end, revert = function() end })
            reg.register({ id = "boom", order = 20, apply = function() error("kaput") end, revert = function() end })
            reg.register({ id = "last", order = 30, apply = function() ran[#ran + 1] = "last" end, revert = function() end })
            local ok, failed = reg.reconcile("probe")
            H.equal(ok, false)
            H.deep_equal(failed, { "boom" })
            H.deep_equal(ran, { "first", "last" })
            H.equal(#logged, 1)
            H.truthy(logged[1]:find("boom", 1, true) and logged[1]:find("kaput", 1, true), "log names id and error")
        end)

        H.test(tree.name .. " registry rejects duplicate ids", function()
            local reg = new_registry(tree.path)
            reg.register({ id = "dup", order = 10, apply = function() end, revert = function() end })
            local ok = pcall(reg.register, { id = "dup", order = 20, apply = function() end, revert = function() end })
            H.equal(ok, false, "duplicate id must be rejected")
            H.deep_equal(reg.ids(), { "dup" })
        end)

        H.test(tree.name .. " wt owner table applies in the card order and reverts in reverse", function()
            local dir = tree.path:gsub("_wt_mutation_registry%.lua$", "")
            local calls = {}
            local function rec(name) return function() calls[#calls + 1] = name end end
            local mod = {
                _wt374_seed_energy_data = rec("energy+"), _wt374_revert_energy_data = rec("energy-"),
                _wt_reconcile_history_owner_stack = function(reason)
                    calls[#calls + 1] = "history:" .. tostring(reason); return true end,
                wt_apply_priest_punch_buff = rec("priest"), wt_apply_brett_buff = rec("bret"),
                _wt431_brace_repoint = rec("brace"),
                _wt_apply_fire_sword = function(_, off) calls[#calls + 1] = off and "fire-" or "fire+" end,
            }
            local reg = dofile(repo_root .. "/qa/lua/fixtures/wt_registry_harness.lua")(dir, mod, {
                apply_weapon_unlocks = rec("avail+"), clear_weapon_unlocks = rec("avail-"),
                patch_career_actions = rec("actions+"), clear_career_actions = rec("actions-"),
                history_owner = { restore = rec("history-") },
                bolt_runtime = { apply = rec("bolt+"), revert = rec("bolt-") },
            })
            H.deep_equal(reg.ids(), { "availability", "career_actions", "energy", "history_and_axe",
                "priest_punch", "bret", "brace_repoint", "bolt_staff", "fire_sword" })
            H.equal(reg.reconcile("game_state"), true)
            H.deep_equal(calls, { "avail+", "actions+", "energy+", "history:game_state",
                "priest", "bret", "brace", "bolt+", "fire+" })
            for i = #calls, 1, -1 do calls[i] = nil end
            local ok, restart_bound = reg.revert_all()
            H.equal(ok, true); H.deep_equal(restart_bound, {})
            H.deep_equal(calls, { "fire-", "bolt-", "brace", "bret", "priest", "history-",
                "energy-", "actions-", "avail-" })
            -- A failed history reconcile is reported, and the later owners still run.
            mod._wt_reconcile_history_owner_stack = function() return nil, "2 history families refused" end
            for i = #calls, 1, -1 do calls[i] = nil end
            local rok, failed = reg.reconcile("rig")
            H.equal(rok, false); H.deep_equal(failed, { "history_and_axe" })
            H.equal(calls[#calls], "fire+")
        end)

        H.test(tree.name .. " entry wires the registry once at every lifecycle seam", function()
            local dir = tree.path:gsub("_wt_mutation_registry%.lua$", "")
            local ns = tree.name == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
            local function read(name)
                local f = assert(io.open(dir .. name, "rb")); local s = f:read("*a"); f:close(); return s
            end
            local function count(source, needle)
                local n, at = 0, 1
                while true do
                    local i = source:find(needle, at, true)
                    if not i then return n end
                    n, at = n + 1, i + #needle
                end
            end
            local entry = read(ns .. ".lua")
            H.equal(count(entry, '_wt_mutation_owners").register(_wt_reg, mod, {'), 1)
            H.equal(count(entry, '_wt_reg.reconcile("game_state")'), 1)
            H.equal(count(entry, '_wt_reg.reconcile("rework_master")'), 1)
            H.equal(count(entry, "    _wt_reg.revert_all()\n"), 1)
            H.equal(count(read("_wt431_damage_profile_parity.lua"), 'mod._wt.registry.reconcile("peer_parity")'), 1)
            H.equal(count(read("weapon_tweaker_backend.lua"), 'mod._wt.registry.reconcile("cwv_transition")'), 1)
            H.equal(count(read("_wt_settings_runtime.lua"), 'c.reconcile("settings_batch")'), 1)
        end)

        H.test(tree.name .. " registry accepts an owner without revert only when restart-bound", function()
            local reg = new_registry(tree.path)
            local ok = pcall(reg.register, { id = "no_revert", order = 10, apply = function() end })
            H.equal(ok, false, "owner without revert must declare restart_bound")
            reg.register({ id = "load_once", order = 10, apply = function() end, restart_bound = true })
            reg.register({ id = "normal", order = 20, apply = function() end, revert = function() end })
            local rok, restart_bound = reg.revert_all()
            H.equal(rok, true)
            H.deep_equal(restart_bound, { "load_once" })
        end)
    end
end
