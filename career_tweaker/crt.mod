return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Career Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("crt", {
            mod_script       = "scripts/mods/career_tweaker/career_tweaker",
            mod_data         = "scripts/mods/career_tweaker/career_tweaker_data",
            mod_localization = "scripts/mods/career_tweaker/career_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/career_tweaker",
    },
}
