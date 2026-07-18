return function(H, repo_root)
    local dev_policy_path = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_voip_disconnect_policy.lua"
    local DevPolicy = assert(loadfile(dev_policy_path))()

    local function verify_policy(Policy, stream)
        H.test("gt " .. stream .. " VOIP disconnect gate is exact", function()
            local channels = { host = 17 }

            H.equal(Policy.should_drop_server_rpc("rpc_voip_room_request", false, "host", channels), false)
            H.truthy(Policy.should_drop_server_rpc("rpc_voip_room_request", false, "gone", channels))
            H.truthy(Policy.should_drop_server_rpc("rpc_voip_room_request", false, nil, channels))
            H.equal(Policy.should_drop_server_rpc("rpc_voip_room_request", true, "gone", channels), false)
            H.equal(Policy.should_drop_server_rpc("rpc_other", false, "gone", channels), false)
            H.equal(Policy.should_drop_server_rpc("rpc_voip_room_request", false, "gone", nil), false)
        end)

        H.test("gt " .. stream .. " VOIP disconnect error match is narrow", function()
            H.truthy(Policy.is_closed_channel_error(
                "foundation/scripts/util/error.lua:26: Channel must be an integer"
            ))
            H.equal(Policy.is_closed_channel_error("rpc does not exist"), false)
            H.equal(Policy.is_closed_channel_error(nil), false)
        end)
    end

    verify_policy(DevPolicy, "dev")

    H.test("gt VOIP guard is loaded once per stream and only hooks send_rpc_server", function()
        local streams = {
            {
                main = "/general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua",
                guard = "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_network_transmit_guard.lua",
                load = 'mod:dofile("scripts/mods/general_tweaker_dev/_gt_network_transmit_guard")',
            },
        }

        for _, stream in ipairs(streams) do
            local main_file = assert(io.open(repo_root .. stream.main, "rb"))
            local main_source = main_file:read("*a")
            main_file:close()
            local guard_file = assert(io.open(repo_root .. stream.guard, "rb"))
            local guard_source = guard_file:read("*a")
            guard_file:close()

            local load_count = 0
            local search_from = 1
            while true do
                local found_at = main_source:find(stream.load, search_from, true)
                if not found_at then
                    break
                end
                load_count = load_count + 1
                search_from = found_at + #stream.load
            end
            H.equal(load_count, 1)
            H.truthy(guard_source:find('mod:hook("NetworkTransmit", "send_rpc_server"', 1, true))
            H.equal(guard_source:find('mod:hook("Voip"', 1, true), nil)
        end
    end)

    H.test("gt dev network transmit guard composes noclip without duplicate hook ownership", function()
        local noclip_file = assert(io.open(
            repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_noclip.lua",
            "rb"
        ))
        local noclip_source = noclip_file:read("*a")
        noclip_file:close()
        local guard_file = assert(io.open(
            repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_network_transmit_guard.lua",
            "rb"
        ))
        local guard_source = guard_file:read("*a")
        guard_file:close()

        H.truthy(noclip_source:find("mod._gt_noclip_server_rpc_guard = function", 1, true))
        H.equal(noclip_source:find('mod:hook("NetworkTransmit", "send_rpc_server"', 1, true), nil)
        H.truthy(guard_source:find("mod._gt_noclip_server_rpc_guard", 1, true))
    end)
end
