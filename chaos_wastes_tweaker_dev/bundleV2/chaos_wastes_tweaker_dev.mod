return {
    run = function()
        fassert(rawget(_G, "new_mod"), "Chaos Wastes Tweaker must be lower than Vermintide Mod Framework in the load order.")

        new_mod("ct_dev", {
            mod_script       = "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev",
            mod_data         = "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_data",
            mod_localization = "scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev_localization",
        })
    end,
    packages = {
        "resource_packages/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev",
    },
}
