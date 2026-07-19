return function(H, repo_root)
    local policy_path = repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_shadow_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("Event Tweaker Shadow policy preserves native Weaves", function()
        H.equal(Policy.plan(true, true, false, false), "native_weave")
    end)

    H.test("Event Tweaker Shadow adapter requires code and capability parity", function()
        H.equal(Policy.plan(true, false, true, true), "adventure_adapter")
        H.equal(Policy.plan(true, false, false, true), "drop_peer_capability")
        H.equal(Policy.plan(true, false, true, false), "drop_adapter_unavailable")
        H.equal(Policy.plan(false, false, false, false), "passthrough")
        H.equal(Policy.ADVENTURE_RADIUS, 6)
    end)

    H.test("Event Tweaker Shadow adapter never spawns weave-only assets", function()
        local runtime = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua")
        H.equal(runtime:find('World%.spawn_unit%('), nil)
        H.equal(runtime:find('Unit%.light%('), nil)
        H.truthy(runtime:find('mutator_shadow_damage_reduction', 1, true))
        H.truthy(runtime:find('set_min_fade', 1, true))
        H.truthy(runtime:find('remove_ping_from_unit', 1, true))
        H.truthy(runtime:find('et_shadow_adventure_v1', 1, true))
    end)

    H.test("Event Tweaker Shadow selection gates before stock RPC activation", function()
        local entry = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker.lua")
        local selection = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_selection.lua")
        local guard = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua")

        local adapter_at = assert(entry:find('_evt_shadow_adventure', 1, true))
        local selection_at = assert(entry:find('_evt_selection', adapter_at, true))
        H.truthy(adapter_at < selection_at)
        H.truthy(selection:find('decision == "adventure_adapter"', 1, true))
        H.truthy(selection:find('set_shadow_requested(true)', 1, true))
        H.truthy(guard:find('_shadow_requested or _shadow_active', 1, true))
        H.truthy(guard:find('ET.peer_feature_wire_safe', 1, true))
    end)
end
