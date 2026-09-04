local mod = get_mod("gut")

-- Explicit, bounded issue #389 verification entry point. Runtime contracts are
-- registered by _gut_mod_tweaker_contracts before this module is installed.
local M = {}

function M.install(checks)
    assert(type(checks) == "table", "issue 389 verifier requires the runtime check list")

    mod:command("verify_gut_slider_step", "Verify Mod Tweaker's owner-aware Base Power step", function()
        local wanted = "issue389_mod_tweaker_owner_aware_step"
        local check = nil
        for _, candidate in ipairs(checks) do
            if candidate.name == wanted then
                check = candidate.fn
                break
            end
        end
        if type(check) ~= "function" then
            mod:echo("FAIL: %s -- check is not registered", wanted)
            if type(printf) == "function" then
                pcall(printf, "[gut:issue389] verify=FAIL reason=check_not_registered")
            end
            return
        end

        local ok, err = pcall(check)
        if ok and err == nil then
            mod:echo("PASS: %s", wanted)
            if type(printf) == "function" then
                pcall(printf, "[gut:issue389] verify=PASS")
            end
            return
        end

        local reason = (not ok and tostring(err)) or tostring(err)
        mod:echo("FAIL: %s -- %s", wanted, reason)
        if type(printf) == "function" then
            pcall(printf, "[gut:issue389] verify=FAIL reason=%s", reason)
        end
    end)

    return true
end

return M
