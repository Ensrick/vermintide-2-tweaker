local function read(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

return function(H, repo_root)
    local mod_root = repo_root .. "/character_weapon_variants"
    local catalog_path = mod_root
        .. "/scripts/mods/character_weapon_variants/_cwv_variant_catalog.lua"
    local package_path = mod_root
        .. "/resource_packages/character_weapon_variants/character_weapon_variants.package"
    local blunderbuss =
        "units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1"

    H.test("CWV #762 Outrider uses the canonical resident blunderbuss unit", function()
        local catalog = read(catalog_path)
        local start_at = assert(catalog:find(
            'item_key        = "cwv_es_outrider_grenade_launcher"', 1, true))
        local end_at = assert(catalog:find(
            'item_type       = "cwv_es_outrider_grenade_launcher"', start_at, true))
        local block = catalog:sub(start_at, end_at)

        H.truthy(block:find('right_hand_unit = "' .. blunderbuss .. '"', 1, true))
        H.equal(block:find("launcher_family", 1, true), nil)
        H.equal(block:find("right_hand_scale", 1, true), nil)
        H.equal(block:find("right_hand_rotation", 1, true), nil)
        H.truthy(block:find("no_left_hand    = true", 1, true))
        H.truthy(block:find("no_ammo_unit    = true", 1, true))
    end)

    H.test("CWV #762 generated skins retain the definition's one visual owner", function()
        local source = require("cwv_source").combined(repo_root)
        H.truthy(source:find("right_hand_unit           = def.right_hand_unit", 1, true))
        H.truthy(source:find("[cwv:762] Outrider visual owner", 1, true))
        H.equal(source:find("_om.launcher_family", 1, true), nil)
    end)

    H.test("CWV #762 runtime regression checks definition, item, and skin parity", function()
        local regression = read(mod_root
            .. "/scripts/mods/character_weapon_variants/_cwv_regression_render.lua")
        H.truthy(regression:find(
            '_rt_register("cwv_issue762_outrider_blunderbuss_owner"', 1, true))
        H.truthy(regression:find(
            'rawget(ItemMasterList, "cwv_es_outrider_grenade_launcher")', 1, true))
        H.truthy(regression:find(
            'rawget(WeaponSkins.skins, "cwv_es_outrider_grenade_launcher_skin")',
            1, true))
    end)

    H.test("CWV #762 retired launcher resources are absent from the active package", function()
        local package_source = read(package_path)
        H.equal(package_source:find("cwv_launcher", 1, true), nil)
        H.equal(io.open(mod_root
            .. "/scripts/mods/character_weapon_variants/_cwv_launcher_family.lua", "rb"), nil)
        H.equal(io.open(mod_root
            .. "/units/cwv_launcher/launcher_01/launcher_01.unit", "rb"), nil)
        H.equal(io.open(mod_root
            .. "/textures/cwv_launcher/launcher_01/launcher_01_albedo.png", "rb"), nil)
    end)
end
