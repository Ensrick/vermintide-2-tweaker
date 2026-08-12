-- _cos_glow_diagnostics_runtime.lua - bounded glow evidence and commands.
--
-- Installs in two phases so the bounded log function remains available at its
-- original declaration point while command registration retains its original
-- position relative to every hook and command in the entry.

local GlowDiagnosticsRuntime = {}

function GlowDiagnosticsRuntime.install(mod, deps)
    deps = deps or {}
    local _printf = deps.printf
    local commands_installed = false

    local function log(fmt, ...)
        mod._cos574_diag_count = mod._cos574_diag_count or 0
        if mod._cos574_diag_count >= 48 then return end
        mod._cos574_diag_count = mod._cos574_diag_count + 1
        if _printf then
            local ok, message = pcall(string.format, fmt, ...)
            pcall(_printf, "[cos:574] %s evidence=%d/48 chat=false",
                ok and message or tostring(fmt), mod._cos574_diag_count)
        end
    end

    local function install_commands(glow_picker)
        assert(not commands_installed, "glow diagnostic commands installed twice")
        commands_installed = true

        mod:command("glow_status",
            "Report glow hook health and per-hook call counts since session start",
            function()
                local trace = mod:get("glow_trace")
                mod:echo(string.format("[glow_status] trace=%s picker_open=%s",
                    tostring(trace),
                    tostring(glow_picker and glow_picker.is_open
                        and glow_picker.is_open())))
                for _, label in ipairs({ "gear", "flow", "cosmetic" }) do
                    mod:echo(string.format(
                        "[glow_status] hook[%s] installed=%s calls_this_session=%d",
                        label,
                        tostring(mod._glow_hooks_installed[label]),
                        mod._glow_call_counts[label] or 0))
                end
            end)

        mod:command("glow_trace",
            "Toggle per-call glow trace logging (on/off). No arg toggles; pass 1/0 to set.",
            function(arg)
                local current = mod:get("glow_trace") and true or false
                local new_value
                if arg == nil or arg == "" then
                    new_value = not current
                else
                    new_value = (arg == "1" or arg == "on" or arg == "true")
                end
                mod:set("glow_trace", new_value)
                mod:echo(string.format("[glow_trace] now %s",
                    new_value and "ON" or "OFF"))
            end)
    end

    return {
        log = log,
        install_commands = install_commands,
    }
end

return GlowDiagnosticsRuntime
