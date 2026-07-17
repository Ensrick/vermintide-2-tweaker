return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_network_readiness.lua")

    H.test("GT network readiness skips title state without touching PlayerManager", function()
        local calls = 0
        local managers = {
            player = {
                local_player_safe = function()
                    calls = calls + 1
                    error("must not run")
                end,
            },
        }
        H.equal(policy.local_player(managers), nil)
        H.equal(calls, 0)
    end)

    H.test("GT network readiness contains throwing backend transitions", function()
        local managers = {
            state = {
                network = {
                    game = function() error("Network backend has not been set") end,
                },
            },
            player = {
                local_player_safe = function() error("must not run") end,
            },
        }
        H.equal(policy.local_player(managers), nil)

        managers.state.network.game = function() return {} end
        managers.player.local_player_safe = function()
            error("Network backend has not been set")
        end
        H.equal(policy.local_player(managers), nil)
    end)

    H.test("GT network readiness returns the ready local player", function()
        local expected = { player_unit = "unit" }
        local managers = {
            state = { network = { game = function() return {} end } },
            player = {
                local_player_safe = function(self)
                    H.truthy(self ~= nil)
                    return expected
                end,
                local_player = function() error("unsafe API must not be used") end,
            },
        }
        H.equal(policy.local_player(managers), expected)
    end)

    H.test("GT infinite-ammo reconciliation uses the readiness policy", function()
        local path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_hacks.lua"
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        local reconcile = assert(source:match(
            "local function _gt_reconcile_infinite_ammo%(%)%s*(.-)%s*mod%._gt_reconcile_infinite_ammo"))
        H.truthy(source:find("NETWORK_READINESS.local_player(Managers)", 1, true))
        H.equal(reconcile:find("Managers.player:local_player()", 1, true), nil)
        H.truthy(source:find("if not lp then return false end", 1, true))
        H.truthy(source:find("mod._gt_infinite_ammo_startup_safe = NETWORK_READINESS", 1, true))
    end)
end
