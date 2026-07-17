return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)

    H.test("CWV cross-access remap owns the pre-RPC 3P animation seam", function()
        H.truthy(source:find('mod:hook("WeaponUnitExtension", "_play_3p_anim"', 1, true))
        H.truthy(source:find("_cwv_networked_3p_remap_installed = true", 1, true))
        H.equal(source:find('mod:hook("Unit", "animation_event"', 1, true), nil)
    end)

    H.test("CWV delegates substituted animation and audio to vanilla", function()
        local hook_start = assert(source:find(
            'mod:hook("WeaponUnitExtension", "_play_3p_anim"', 1, true
        ))
        local hook_end = assert(source:find(
            "_cwv_networked_3p_remap_installed = true", hook_start, true
        ))
        local hook = source:sub(hook_start, hook_end)
        H.truthy(hook:find("func(self, target, event, owner_unit, looping_event, anim_time_scale)", 1, true))
        H.equal(hook:find("WwiseWorld.trigger_event", 1, true), nil)
        H.equal(hook:find("rpc_play_sound_event", 1, true), nil)
    end)
end
