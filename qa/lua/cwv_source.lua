local Source = {}

local MODULES_IN_INSTALL_ORDER = {
    "_cwv_illusion_provenance.lua",
    "_cwv_variant_catalog.lua",
    "_cwv_cross_access.lua",
    "_cwv_core_templates.lua",
    "_cwv_skin_registry.lua",
    "_cwv_illusion_families.lua",
    "_cwv_item_registration_owner.lua",
    "_cwv_musket_ammo_hud.lua",
    "_cwv_musket_runtime.lua",
    "_cwv_musket_equip_surface.lua",
    "_cwv_husk_residency_owner.lua",
    "_cwv_custom_mesh_runtime.lua",
    "_cwv_javelin_runtime_owner.lua",
    "_cwv_projectile_tunes.lua",
    "_cwv_rapier_runtime_owner.lua",
    "_cwv_variant_bootstrap_owner.lua",
    "_cwv_old_musket_wire.lua",
    "_cwv_old_musket_preview_pose.lua",
	"_cwv_javelin_gate.lua",
	"_cwv_thrown_wire_policy.lua",
	"_cwv_exact_wire_runtime.lua",
	"_cwv_identity_peer_pull.lua",
	"_cwv_transform_evidence.lua",
	"_cwv_crowbill_transform_runtime.lua",
    "_cwv_weapon_transform_owner.lua",
    "_cwv_husk_path.lua",
    "_cwv_item_identity_transport_owner.lua",
    "_cwv_world_equipment_owner.lua",
    "_cwv_menu_preview_owner.lua",
    "_cwv_commands_lifecycle.lua",
    "_cwv_regression_identity.lua",
	"_cwv_regression_combat_style.lua",
    "_cwv_regression_husk_ammo.lua",
    "_cwv_regression_render.lua",
}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

function Source.combined(repo_root)
    local root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local chunks = { read(root .. "character_weapon_variants.lua") }
    for _, module_name in ipairs(MODULES_IN_INSTALL_ORDER) do
        chunks[#chunks + 1] = read(root .. module_name)
    end
    return table.concat(chunks, "\n")
end

return Source
