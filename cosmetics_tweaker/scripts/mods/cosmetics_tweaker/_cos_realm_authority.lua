-- Current-engine realm adapter (#1691). The native 6.12+ boolean is initialized
-- before mods/backend construction (application_parameter.lua:150-152, source
-- 93dea911). Explicit official false is final. Older games delegate to the
-- existing shared launch/legacy authority; no backend or global flag is changed.
local M = {}

function M.install(mod, globals)
    return M.new(globals, mod:dofile(
        "scripts/mods/cosmetics_tweaker/_lib_modded_realm_authority"))
end

function M.new(globals, legacy)
    assert(type(globals) == "table", "realm globals required")
    assert(type(legacy) == "table" and type(legacy.is_modded) == "function",
        "legacy realm authority required")
    local adapter = {}

    function adapter.is_modded()
        if legacy.VERSION ~= 2 then return false end
        return legacy.is_modded(rawget(globals, "script_data"), 0,
            rawget(globals, "Development"), globals) == true
    end

    -- Compatibility bracket only. Modern UI presentation must be restored at
    -- its owner; never clear MODDED_REALM or read_only_backend to enable it.
    function adapter.with_eac_off(func, self, ...)
        return legacy.with_eac_off(rawget(globals, "script_data"), nil,
            func, self, nil, ...)
    end

    function adapter.install_checks(register)
        register("issue1691_native_realm_authority", function()
            if legacy.VERSION ~= 2 then return "V2 shared realm authority missing" end
            local native = rawget(globals, "MODDED_REALM")
            if native == nil then return "skip: native MODDED_REALM unavailable on this game version" end
            if adapter.is_modded() ~= (native == true) then
                return "Cosmetics realm disagrees with native MODDED_REALM"
            end
        end, { precondition = function()
            return rawget(globals, "MODDED_REALM") ~= nil,
                "native MODDED_REALM unavailable on this game version"
        end })
        register("issue1693_shared_native_realm_authority", function()
            if legacy.VERSION ~= 2 or type(legacy.runtime_check) ~= "function" then
                return "V2 shared realm authority missing"
            end
            return legacy.runtime_check()
        end)
    end

    return adapter
end

return M
