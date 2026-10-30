-- _cwv_family_bootstrap.lua -- Private entry family-context composition.
--
-- Preserves the published Sword/Mace installation and its exceptions verbatim.
-- Only the unrelated dormant Tuskgor setup has a failure boundary; it cannot
-- prevent the already-created Sword result from returning to the entry.
-- Owned by: character_weapon_variants.lua. Consumed once at its family handoff.
local M = {}
function M.install(mod, ctx)
    local sword = ctx.sword_install(mod, ctx)
    local ok, tuskgor = pcall(function() return ctx.prepare_tuskgor(ctx) end)
    if not ok or type(tuskgor) ~= "table" then
        local printable, reason = pcall(tostring, tuskgor)
        tuskgor = { setup_error = "#645 Tuskgor setup unavailable: "
            .. (printable and reason or "<unprintable setup failure>") }
    end
    return sword, tuskgor
end
return M
