return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local source = CTSource.expanded(repo_root)

    H.test("CT #136 host graph snapshot applies to the live run controller on receipt", function()
        H.truthy(source:find('CT_GRAPH_SNAPSHOT_LIVE_APPLY_MARKER = "graph_snapshot_live_apply_before_mission_select_v0.7.299"', 1, true))
        H.truthy(source:find('local function apply_host_graph_snapshot_to_live_run(reason)', 1, true))
        local receiver = assert(source:find('mod:network_register("ct_graph_snapshot_chunk"', 1, true))
        local store = assert(source:find('_ct_host_graph_snapshot = { session = session, nodes = payload }', receiver, true))
        local call = assert(source:find('apply_host_graph_snapshot_to_live_run("ct_graph_snapshot_chunk")', store, true))
        H.truthy(store < call, "receiver must store snapshot before applying it to the live Deus graph")
    end)

    H.test("CT #136 live apply targets DeusRunController graph before map UI fallback", function()
        local helper = assert(source:find('local function apply_host_graph_snapshot_to_live_run(reason)', 1, true))
        local map_hook = assert(source:find('mod:hook("DeusMapScene", "on_enter"', 1, true))
        H.truthy(helper < map_hook, "live apply helper must exist before the map-open fallback hook")
        for _, needle in ipairs({
            'Managers.mechanism:game_mechanism()',
            'mechanism:get_deus_run_controller()',
            'rc:get_graph_data()',
            'apply_graph_snapshot(graph_data)',
            '[ct:136] live snapshot apply reason=%s applied=%d session=%s marker=%s',
        }) do
            H.truthy(source:find(needle, helper, true), "missing live-apply contract: " .. needle)
        end
    end)

    H.test("CT #136 preserves #97 paced graph snapshot transport", function()
        H.truthy(source:find('_CT_CHUNK_DRAIN_BUDGET = 8', 1, true))
        H.truthy(source:find('_CT_CHUNK_PACED_SEND_MARKER = "chunk_sends:enqueue_drain_paced_v0.7.163"', 1, true))
        local broadcaster = assert(source:find('local function broadcast_graph_snapshot(graph_data)', 1, true))
        local enqueue = assert(source:find('_ct_enqueue_chunk("ct_graph_snapshot_chunk", "others", CT_RPC_SCHEMA, session, seq, total, chunk_str)', broadcaster, true))
        local next_section = assert(source:find('-- Peer manifest diagnostics ->', broadcaster, true))
        H.truthy(enqueue < next_section, "graph snapshot chunks must still route through the #97 send queue")
        local burst = source:find('mod:network_send("ct_graph_snapshot_chunk"', broadcaster, true)
        H.equal(burst, nil, "graph snapshots must not reintroduce inline burst sends")
    end)
end
