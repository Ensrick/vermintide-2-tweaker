return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Policy = assert(loadfile(root .. "_cim_keep_forge_interaction.lua"))()

    H.test("CIM restores only untrusted Keep forge interaction", function()
        H.equal(Policy.resolve(false, true, true), true)
        H.equal(Policy.resolve(false, true, false), false)
        H.equal(Policy.resolve(false, false, true), false)
        H.equal(Policy.resolve(true, false, false), true)
    end)

    H.test("CIM forge install preserves native stop prompt and original predicate", function()
        local calls = 0
        local original = function()
            calls = calls + 1
            return false
        end
        local defs = {
            forge_access = {
                client = {
                    can_interact = original,
                    stop = function() return "native-transition" end,
                    hud_description = function() return "native-prompt" end,
                },
            },
        }
        local mod = {
            _cim_is_in_keep = function() return false end,
            _cim_is_modded_realm = function() return true end,
        }
        local old_script_data = script_data
        script_data = { ["eac-untrusted"] = true }
        local ok = Policy.install(mod, defs)
        H.truthy(ok)
        H.equal(defs.forge_access.client.can_interact(), false)
        H.equal(calls, 1)
        H.equal(defs.forge_access.client.stop(), "native-transition")
        H.equal(defs.forge_access.client.hud_description(), "native-prompt")
        script_data = old_script_data
    end)

    H.test("CIM Keep forge uses shared authority inside MP's EAC-off window", function()
        local original = function() return false end
        local defs = { forge_access = { client = { can_interact = original } } }
        local mod = {
            _cim_is_in_keep = function() return true end,
            _cim_is_modded_realm = function() return true end,
        }
        local old_script_data, old_printf = script_data, printf
        script_data = { ["eac-untrusted"] = nil }
        printf = function() end
        H.truthy(Policy.install(mod, defs))
        H.equal(defs.forge_access.client.can_interact(), true)
        script_data, printf = old_script_data, old_printf
    end)

    H.test("CIM forge install is reload-idempotent", function()
        local original = function() return false end
        local defs = { forge_access = { client = { can_interact = original } } }
        local mod = {
            _cim_is_in_keep = function() return false end,
            _cim_is_modded_realm = function() return false end,
        }
        H.truthy(Policy.install(mod, defs))
        local installed = defs.forge_access.client.can_interact
        H.truthy(Policy.install(mod, defs))
        H.equal(mod._cim_keep_forge_interaction_state.original_can_interact, original)
        H.equal(defs.forge_access.client.can_interact, installed)
    end)
end
