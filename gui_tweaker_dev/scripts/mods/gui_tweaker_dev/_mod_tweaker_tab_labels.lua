-- Exact Mod Tweaker tab chrome, keyed by VMF mod id.
--
-- This is intentionally presentation-only. A mod keeps its own readable name for
-- VMF and every other surface; Mod Tweaker asks this policy whether its compact
-- native tab strip needs a shorter or domain-specific label. Keeping the map in
-- one engine-free module prevents the standalone and HeroView presentations from
-- drifting.

local EXACT = {
    cim = "CRAFTING",
    cim_dev = "CRAFTING",
    character_weapon_variants = "CWV",
    character_weapon_variants_dev = "CWV",
    mp = "PROGRESSION", -- #525: Modded Progression's Mod Tweaker tab.
}

local M = {}

function M.exact(mod_id)
    return EXACT[mod_id]
end

M.rt_checks = {
    {
        name = "issue525_progression_tab_label",
        fn = function()
            if M.exact("mp") ~= "PROGRESSION" then
                return "mp tab label is not the exact PROGRESSION chrome label"
            end
            if M.exact("unknown_mod") ~= nil then
                return "unknown mods must retain the derived-label fallback"
            end
        end,
    },
}

return M
