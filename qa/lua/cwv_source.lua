local Source = {}

local MODULES_IN_INSTALL_ORDER = {
    "_cwv_variant_catalog.lua",
    "_cwv_cross_access.lua",
    "_cwv_old_musket_wire.lua",
	"_cwv_transform_evidence.lua",
	"_cwv_crowbill_transform_runtime.lua",
    "_cwv_husk_path.lua",
    "_cwv_commands_lifecycle.lua",
    "_cwv_regression_identity.lua",
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
