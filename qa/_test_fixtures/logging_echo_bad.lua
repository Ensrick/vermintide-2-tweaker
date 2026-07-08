-- Fixture for check_logging.ps1 -SelfTest — category (a) ECHO.
-- Expected: 2 echo findings — the hook-body echo + the on_setting_changed echo
-- (both § 3.6 "NEVER" contexts). The dev-banner echo, the command-body echo, the
-- ordinary-helper echo, and the annotated on_enabled echo are all suppressed.
local MOD_VERSION = "0.1.0-dev"

-- SUPPRESSED: dev/alpha/beta/0.x module-load banner references MOD_VERSION.
if MOD_VERSION:find("-dev$") then
    mod:echo(string.format("[fx] v%s loaded", MOD_VERSION))
end

-- SUPPRESSED: inside a mod:command(...) body — user invoked it, reply to chat.
mod:command("fx_status", "print status", function()
    mod:echo("[fx] status: ok")
end)

-- FLAG #1: echo in a hook body — routine chat spam, the § 3.6 "NEVER" class.
mod:hook_safe(CutsceneSystem, "play", function(self)
    mod:echo("[fx] cutscene started")
end)

-- FLAG #2: echo in on_setting_changed for a routine setting.
mod.on_setting_changed = function(setting_id)
    mod:echo("Setting changed: " .. tostring(setting_id))
end

-- SUPPRESSED: an on_disabled documented-limitation notice is a § 3.6 OK row —
-- annotated in a NEVER-context to exercise the escape comment.
mod.on_disabled = function()
    mod:echo("[fx] Disable does not fully unwind mutations.") -- allow-echo: § 3.6 on_disabled documented-limitation
end

-- SUPPRESSED: ordinary helper (not lifecycle / hook / top-level) — command-reply
-- helpers live here and must NOT be flagged.
local function _apply()
    mod:echo("[fx] applied")
end
