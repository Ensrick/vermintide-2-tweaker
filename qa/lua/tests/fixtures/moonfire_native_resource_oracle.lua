-- Source- and installed-bundle-derived oracle for issue #1125.
--
-- Native/SDK provenance:
--   Vermintide-2-Source-Code commit c5e4968b1fbb00c49884e56d640ef990a9c04dd0
--   scripts/settings/dlc_settings.lua:30-32
--   scripts/boot.lua:358-369
--   scripts/settings/dlcs/morris/morris_buff_settings.lua:5232-5237,5267
--   scripts/settings/material_effect_mappings_morris.lua:240-266
--   scripts/settings/dlcs/morris/morris_equipment_settings.lua:104-105
--
-- Installed package provenance (game files observed 2026-08-13):
--   bundle resource name hash: D44D88664CFC5FD1
--     (= fx/wpnfx_we_deus_01_impact)
--   2e2f2b4d974d1c9f (= resource_packages/dlcs/morris) contains the particle.
--     Fatshark declares this as DLCSettings.morris.package_name and boot loads
--     every such package under the persistent "boot" reference.
--   3a3e55a7e74d5d2e (= Moonfire 1P unit package) also contains the particle.
--   180b628657a5c3d3 (= Moonfire 3P unit package) does NOT contain it; package
--     ownership must not be inferred merely from the weapon unit's name.
--   resource_packages/dlcs/morris_ingame (f5b9c97431b34ca6) does not
--   contain that particle. That package owns other Chaos-Wastes particles;
--   it is not the owner of this weapon-impact effect.
--
-- The hashes were resolved with vt2_bundle_unpacker commit
-- 73ad7c295c0495ca6686397d5f3014b27c6cc885 against the installed game
-- bundle directory. Keep this fixture independent from Tweaker runtime source.

local M = {}

M.source_commit = "c5e4968b1fbb00c49884e56d640ef990a9c04dd0"
M.unpacker_commit = "73ad7c295c0495ca6686397d5f3014b27c6cc885"
M.effect = "fx/wpnfx_we_deus_01_impact"
M.effect_hash = "D44D88664CFC5FD1"
M.canonical_owner = {
    package = "resource_packages/dlcs/morris",
    bundle_hash = "2e2f2b4d974d1c9f",
    installed_sha256 = "F1D0191100019D07AF5167B6AE44B6180F9F29BDCCF933549C6A4A988033661B",
    load_reference = "boot",
}
M.additional_owner = {
    package = "units/weapons/player/wpn_we_deus_01/wpn_we_deus_01",
    bundle_hash = "3a3e55a7e74d5d2e",
    installed_sha256 = "5E0C7EC6B26F9B3E135AD686A08746A8B93606494B7C417BC3D0341E4818764C",
}
M.not_owners = {
    {
        package = "units/weapons/player/wpn_we_deus_01/wpn_we_deus_01_3p",
        bundle_hash = "180b628657a5c3d3",
        installed_sha256 = "0A76D688FFF7BD6880C998E780F352D74B63D3F433CFBA08BD7BCDE546BB1E8D",
    },
    {
        package = "resource_packages/dlcs/morris_ingame",
        bundle_hash = "f5b9c97431b34ca6",
        installed_sha256 = "FAA2D43EEC80E070E19CA5FD210C6A89ED27C9AB035F6DF63CD7A9844779089B",
    },
}

return M
