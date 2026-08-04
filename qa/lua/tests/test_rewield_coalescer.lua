-- Pins the #1145 per-wearer re-wield coalescer + mid-destroy guard in BOTH
-- owning mods (cosmetics_tweaker and character_weapon_variants ship the same
-- shape deliberately; there is no shared global).
--
-- The invariant under test is the crash mechanism itself: one host illusion
-- click fans out over four sync channels, and before this fix every channel
-- drove its own husk wield, stacking 8 re-wield cycles into 220 ms and
-- collapsing the husk destroy+respawn into a single frame. So the assertions
-- are (a) N same-frame requests for one wearer execute EXACTLY once, and
-- (b) a wearer whose game object no longer exists is DROPPED, never executed.
return function(Harness, repo_root)
    local MODULES = {
        cos = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_rewield_coalescer.lua",
        cwv = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_rewield_coalescer.lua",
    }

    -- Fresh module instance per test: the queue is module state.
    local function load_module(which)
        return dofile(MODULES[which])
    end

    local function alive_deps()
        return {
            silent = true,
            unit_api = { alive = function() return true end },
            script_unit = { has_extension = function()
                return { _game_object_id = 52, _game = "session" }
            end },
            game_session = { game_object_exists = function() return true end },
        }
    end

    local function destroyed_deps()
        local deps = alive_deps()
        deps.game_session = { game_object_exists = function() return false end }
        return deps
    end

    for _, which in ipairs({ "cos", "cwv" }) do
        Harness.test(which .. " 1145: four same-frame channels collapse to one re-wield", function()
            local M = load_module(which)
            local wearer, fired = {}, 0
            for i = 1, 4 do
                M.request(wearer, "channel" .. i, function() fired = fired + 1 end)
            end
            Harness.equal(M.depth(), 1, "four requests for one wearer must hold one queue slot")
            local executed, dropped = M.drain(alive_deps())
            Harness.equal(fired, 1, "exactly one re-wield may reach the engine")
            Harness.equal(executed, 1, "drain reports one execution")
            Harness.equal(dropped, 0, "a live wearer is not dropped")
            Harness.equal(M.depth(), 0, "drain empties the queue")
        end)

        Harness.test(which .. " 1145: distinct wearers are not coalesced together", function()
            local M = load_module(which)
            local a, b, na, nb = {}, {}, 0, 0
            M.request(a, "x", function() na = na + 1 end)
            M.request(b, "x", function() nb = nb + 1 end)
            M.request(a, "x", function() na = na + 1 end)
            M.drain(alive_deps())
            Harness.equal(na, 1, "wearer A re-wields once")
            Harness.equal(nb, 1, "wearer B still re-wields (not swallowed by A)")
        end)

        Harness.test(which .. " 1145: merged request keeps the newest state", function()
            local M = load_module(which)
            local wearer, seen = {}, nil
            M.request(wearer, "stale", function() seen = "stale" end)
            M.request(wearer, "fresh", function() seen = "fresh" end)
            M.drain(alive_deps())
            Harness.equal(seen, "fresh", "the newest arrival wins the merge")
        end)

        Harness.test(which .. " 1145: a re-wield that re-requests defers to the next frame", function()
            local M = load_module(which)
            local wearer, runs = {}, 0
            local function reenter()
                runs = runs + 1
                if runs < 3 then M.request(wearer, "reentrant", reenter) end
            end
            M.request(wearer, "reentrant", reenter)
            M.drain(alive_deps())
            Harness.equal(runs, 1, "re-entrant request must not run in the same frame")
            M.drain(alive_deps())
            Harness.equal(runs, 2, "it runs on the following frame")
        end)

        Harness.test(which .. " 1145: mid-destroy husk has its pulse dropped, not executed", function()
            local M = load_module(which)
            local wearer, ran = {}, false
            M.request(wearer, "on-dying-husk", function() ran = true end)
            local executed, dropped = M.drain(destroyed_deps())
            Harness.truthy(not ran, "a destroyed game object must never be re-wielded")
            Harness.equal(executed, 0, "nothing executes")
            Harness.equal(dropped, 1, "the pulse is counted as dropped")
            Harness.equal(M.depth(), 0, "a dropped pulse is NOT carried across the respawn")
        end)

        Harness.test(which .. " 1145: go_alive names the destroyed game object", function()
            local M = load_module(which)
            local _, reason = M.go_alive({}, destroyed_deps())
            Harness.equal(reason, "go-destroyed", "the guard reports why it refused")
            Harness.truthy(M.go_alive(nil) == false, "a nil wearer is never alive")
            local ok = M.go_alive({}, alive_deps())
            Harness.truthy(ok, "a live game object passes the guard")
        end)

        Harness.test(which .. " 1145: regression checks fail when the choke point is unwired", function()
            local M = load_module(which)
            local field = (which == "cos") and "_cos_rewield" or "_cwv_rewield"
            local mod = { [field] = M }
            if M.install then M.install(mod) end
            local checks = {}
            M.install_checks(mod, function(name, fn) checks[#checks + 1] = { name, fn } end)
            Harness.truthy(#checks >= 3, "three #1145 checks register")
            for _, c in ipairs(checks) do
                Harness.equal(c[2](), nil, c[1] .. " must pass while wired")
            end
            -- The #660 contract rule: disconnecting the live wiring MUST fail.
            mod[field] = { impostor = true }
            Harness.truthy(checks[1][2]() ~= nil,
                "unwiring the coalescer must FAIL the marker check, not pass silently")
        end)

        Harness.test(which .. " 1145: self-tests leave the live needle totals clean", function()
            local M = load_module(which)
            local field = (which == "cos") and "_cos_rewield" or "_cwv_rewield"
            local mod = { [field] = M }
            if M.install then M.install(mod) end
            local checks = {}
            M.install_checks(mod, function(name, fn) checks[#checks + 1] = { name, fn } end)
            for _, c in ipairs(checks) do c[2]() end
            Harness.deep_equal(
                { M.stats.queued, M.stats.merged, M.stats.executed, M.stats.dropped_dead_go },
                { 0, 0, 0, 0 },
                "the regression suite must not pollute the [" .. which .. ":1145] evidence totals")
        end)
    end

    -- cos-only: both pulse sites resolved the bounce slot with byte-identical
    -- inline blocks before this fix; they now share one resolver.
    Harness.test("cos 1145: alternate_slot bounces off the other weapon slot", function()
        local M = load_module("cos")
        local slots = { slot_melee = {}, slot_ranged = {} }
        Harness.equal(M.alternate_slot(slots, "slot_melee"), "slot_ranged", "melee bounces to ranged")
        Harness.equal(M.alternate_slot(slots, "slot_ranged"), "slot_melee", "ranged bounces to melee")
        Harness.equal(M.alternate_slot({ slot_melee = {} }, "slot_melee"), nil,
            "a wearer with no second weapon slot cannot be pulsed")
        Harness.equal(M.alternate_slot(nil, "slot_melee"), nil, "missing slots table is not fatal")
    end)

    -- cwv-only: the identity-arrival adapter must refuse every unready shape
    -- rather than enqueue work against a half-spawned husk.
    Harness.test("cwv 1145: identity-arrival adapter refuses unready wearers", function()
        local M = load_module("cwv")
        local _, r1 = M.request_peer_rewield(nil, "slot_melee")
        Harness.equal(r1, "bad-peer-slot", "no peer means no request")
        local _, r2 = M.request_peer_rewield("peer", nil)
        Harness.equal(r2, "bad-peer-slot", "no slot means no request")
        local _, r3 = M.request_peer_rewield("peer", "slot_melee", { managers = {} })
        Harness.equal(r3, "no-player-manager", "no player manager means no request")
        local deps = {
            managers = { player = { player_from_peer_id = function() return { player_unit = {} } end } },
            unit_api = { alive = function() return true end },
            script_unit = { extension = function()
                return { wield = function() end, wielded_slot = "slot_ranged" }
            end },
        }
        local _, r4 = M.request_peer_rewield("peer", "slot_melee", deps)
        Harness.equal(r4, "slot-not-wielded", "an unwielded slot is not rebuilt")
        Harness.equal(M.depth(), 0, "no refused case leaves anything queued")
    end)

    Harness.test("cwv 1145: identity-arrival adapter queues exactly one re-wield", function()
        local M = load_module("cwv")
        local wields = 0
        local inventory = {
            wielded_slot = "slot_melee",
            wield = function() wields = wields + 1 end,
        }
        local unit = {}
        local deps = {
            managers = { player = { player_from_peer_id = function()
                return { player_unit = unit }
            end } },
            unit_api = { alive = function() return true end },
            script_unit = { extension = function() return inventory end },
        }
        M.request_peer_rewield("peer", "slot_melee", deps)
        M.request_peer_rewield("peer", "slot_melee", deps)
        Harness.equal(M.depth(), 1, "two identity arrivals in one frame hold one queue slot")
        M.drain(alive_deps())
        Harness.equal(wields, 1, "the husk is re-wielded once, not once per arrival")
    end)

    Harness.test("cwv 1145: a slot change during deferral cancels the stale re-wield", function()
        local M = load_module("cwv")
        local wields = 0
        local inventory = {
            wielded_slot = "slot_melee",
            wield = function() wields = wields + 1 end,
        }
        local deps = {
            managers = { player = { player_from_peer_id = function()
                return { player_unit = {} }
            end } },
            unit_api = { alive = function() return true end },
            script_unit = { extension = function() return inventory end },
        }
        M.request_peer_rewield("peer", "slot_melee", deps)
        inventory.wielded_slot = "slot_ranged"  -- wearer swapped before the drain
        M.drain(alive_deps())
        Harness.equal(wields, 0, "a re-wield for a slot the wearer no longer holds is skipped")
    end)
end
