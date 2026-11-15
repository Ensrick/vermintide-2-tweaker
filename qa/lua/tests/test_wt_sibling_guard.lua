-- WP-WT-03: when public wt and friends-only wt_dev are both enabled, public wt
-- yields through VMF from its update tick; wt_dev never yields.

return function(H, repo_root)
    local trees = {
        { name = "wt", path = repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_sibling_guard.lua" },
        { name = "wt_dev", path = repo_root
            .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_sibling_guard.lua" },
    }

    local function enabled_stub(value)
        return { is_enabled = function() return value end }
    end

    local function harness(self_id, sibling)
        local log = { printed = {}, echoed = {}, state_changes = {} }
        local mod = {
            get_name = function() return self_id end,
            is_enabled = function() return true end,
            echo = function(_, text) log.echoed[#log.echoed + 1] = text end,
        }
        local vmf = {
            mod_state_changed = function(name, value)
                log.state_changes[#log.state_changes + 1] = { name, value }
            end,
        }
        local function get_mod_fn(name)
            if name == "VMF" then return vmf end
            if name == (self_id == "wt" and "wt_dev" or "wt") then return sibling end
            return nil
        end
        local function print_fn(line) log.printed[#log.printed + 1] = line end
        return mod, get_mod_fn, print_fn, log
    end

    for _, tree in ipairs(trees) do
        H.test(tree.name .. " sibling guard: ids and the yield rule", function()
            local M = dofile(tree.path)
            H.equal(M.sibling_id("wt"), "wt_dev")
            H.equal(M.sibling_id("wt_dev"), "wt")
            H.equal(M.public_must_yield("wt", true, enabled_stub(true)), true)
            H.equal(M.public_must_yield("wt", true, nil), false, "nil sibling")
            H.equal(M.public_must_yield("wt", true, enabled_stub(false)), false, "disabled sibling")
            H.equal(M.public_must_yield("wt", true,
                { is_enabled = function() error("boom") end }), false, "raising sibling")
            H.equal(M.public_must_yield("wt", false, enabled_stub(true)), false, "self disabled")
            H.equal(M.public_must_yield("wt_dev", true, enabled_stub(true)), false, "dev never yields")
            H.equal(M.public_must_yield("wt_dev", false, enabled_stub(true)), false)
        end)

        H.test(tree.name .. " sibling guard: public wt yields once at 1.0 s", function()
            local M = dofile(tree.path)
            local mod, get_mod_fn, print_fn, log = harness("wt", enabled_stub(true))
            H.equal(M.tick(mod, 0.25, get_mod_fn, print_fn), false)
            H.equal(M.tick(mod, 0.25, get_mod_fn, print_fn), false)
            H.equal(#log.printed + #log.echoed + #log.state_changes, 0, "0.5 s must do nothing")
            H.equal(M.tick(mod, 0.25, get_mod_fn, print_fn), false)
            H.equal(M.tick(mod, 0.25, get_mod_fn, print_fn), true, "1.0 s must yield")
            H.deep_equal(log.printed, { "[wt:SIBLING] wt and wt_dev are both enabled; disabling public wt" })
            H.deep_equal(log.echoed, {
                "Weapon Tweaker (dev) is enabled. The public Weapon Tweaker was turned off to avoid conflicts.",
            })
            H.deep_equal(log.state_changes, { { "wt", false } })
        end)

        H.test(tree.name .. " sibling guard: wt_dev never disables anything", function()
            local M = dofile(tree.path)
            local mod, get_mod_fn, print_fn, log = harness("wt_dev", enabled_stub(true))
            for _ = 1, 8 do
                H.equal(M.tick(mod, 0.5, get_mod_fn, print_fn), false)
            end
            H.equal(#log.state_changes, 0)
            H.equal(#log.printed + #log.echoed, 0)
        end)
    end
end
