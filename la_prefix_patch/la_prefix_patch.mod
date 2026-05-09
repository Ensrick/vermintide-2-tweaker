return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`LA Prefix Patch` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

        new_mod("la_prefix_patch", {
            mod_script       = "scripts/mods/la_prefix_patch/la_prefix_patch",
            mod_data         = "scripts/mods/la_prefix_patch/la_prefix_patch_data",
            mod_localization = "scripts/mods/la_prefix_patch/la_prefix_patch_localization",
        })
    end,
    packages = {
        "resource_packages/la_prefix_patch/la_prefix_patch",
    },
}
