-- _cos_offhand_diagnostics.lua - read-only independent-offhand commands.

local OffhandDiagnostics = {}

function OffhandDiagnostics.install(mod, deps)
    deps = deps or {}
    local LA_BRIDGE = assert(deps.la_bridge, "la_bridge is required")
    local _offhand_options = assert(deps.offhand_options, "offhand_options is required")
    local _offhand_selection = assert(deps.offhand_selection, "offhand_selection is required")
    local _surfaces = assert(deps.surfaces, "surfaces is required")

    mod:command("la_offhand_dump", "Dump LA offhand variant -> intended_unit resolution", function()
        if LA_BRIDGE.dump_offhand_resolution then
            LA_BRIDGE.dump_offhand_resolution()
        else
            mod:echo("[LA bridge] dump_offhand_resolution unavailable")
        end
    end)

    mod:command("offhand_debug", "Dump offhand system state", function()
        mod:echo("[offhand] _offhand_options (item_type -> hand_field -> pool size):")
        for k, hand_pools in pairs(_offhand_options) do
            for hand, pool in pairs(hand_pools) do
                mod:echo("  %s/%s -> %d options", k, hand, #pool)
            end
        end
        mod:echo("[offhand] _offhand_selection (bid -> hand -> sel):")
        for k, per_hand in pairs(_offhand_selection) do
            if type(per_hand) == "table" then
                for hand, value in pairs(per_hand) do
                    if type(value) == "table" then
                        local label = value.la_armoury_key
                            and ("LA:" .. value.la_armoury_key)
                            or tostring(value.unit)
                        mod:echo("  %s/%s -> %s", k, hand, label)
                    end
                end
            end
        end
        mod:echo("[offhand] BackendUtils hooked: %s",
            tostring(_surfaces.BackendUtils ~= nil))
        mod:echo("[offhand] UIWidget available: %s",
            tostring(_surfaces.UIWidget ~= nil))
        mod:echo("[offhand] UIWidgets available: %s",
            tostring(_surfaces.UIWidgets ~= nil))
        mod:echo("[offhand] UIRenderer available: %s",
            tostring(_surfaces.UIRenderer ~= nil))
        mod:echo("[offhand] Colors available: %s",
            tostring(_surfaces.Colors ~= nil))
    end)

    return true
end

return OffhandDiagnostics
