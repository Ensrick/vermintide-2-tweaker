-- Fixture for check_logging.ps1 -SelfTest — all sanctioned forms, zero findings.
local MOD_VERSION = "0.1.0-dev"

-- dev-banner: references MOD_VERSION -> suppressed.
if MOD_VERSION:find("-dev$") then
    mod:echo(string.format("[fx] v%s loaded", MOD_VERSION))
end

-- log-only debug helper (chat-silent channel) — fine.
local function _dbg(fmt, ...)
    mod:debug("[fx:dbg] " .. fmt, ...)
end

-- alert helper routed through pcall-guarded printf (the #240 sanctioned form).
local function _dbg_alert(fmt, ...)
    if not pcall(printf, "[fx:dbg] " .. fmt, ...) then
        pcall(printf, "[fx:dbg] (alert format error)")
    end
end

-- permanent operational marker — log only, fine.
mod:info("[fx] enabled v%s", MOD_VERSION)

-- command reply echoes — user invoked, chat is correct.
mod:command("fx_verify", "verify state", function()
    mod:echo("=== fx verify ===")
    mod:echo("  PASS: all good")
end)

-- non-per-frame guard warning on a real failure path — fine.
local function _apply()
    local ok = pcall(function() return true end)
    if not ok then
        mod:warning("[fx] apply failed")
    end
end
