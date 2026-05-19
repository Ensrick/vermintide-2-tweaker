local function en(s) return { en = s } end

return {
    mod_description = en("Defensively-patched fork of Grundlid's Material-Hijack. Same features (custom materials + animated textures + particle effects on modded cosmetic units) plus pre-validation guards that turn the `[Script Error]: Unit not found #ID[...]` C-level fatal into a logged skip. **Disable the original Material-Hijack before enabling this** — they otherwise both hook the same functions."),
}
