return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`Tweaker: Buffs` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

        new_mod("bt", {
            mod_script       = "scripts/mods/buff_tweaker/buff_tweaker",
            mod_data         = "scripts/mods/buff_tweaker/buff_tweaker_data",
            mod_localization = "scripts/mods/buff_tweaker/buff_tweaker_localization",
        })
    end,
    packages = {
        "resource_packages/buff_tweaker/buff_tweaker",
    },
}
