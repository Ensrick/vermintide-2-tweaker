return function(H, repo_root)
    local function read(path, mode)
        local file = assert(io.open(path, mode or "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    local mod_root = repo_root .. "/dynamic_cosmetic_portraits"
    local main_path = mod_root
        .. "/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua"
    local data_path = mod_root
        .. "/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits_data.lua"
    local main_source = read(main_path)
    local data_source = read(data_path)
    local atlas_lua_path = mod_root
        .. "/materials/dynamic_cosmetic_portraits/dcp_portrait_atlas.lua"
    local atlas = assert(loadfile(atlas_lua_path))()

    H.test("DCP cutout portraits use one complete private atlas (#526)", function()
        local count = 0
        for texture_name, settings in pairs(atlas) do
            count = count + 1
            local small = texture_name:find("small_portrait_", 1, true) == 1
            H.equal(settings.size[1], small and 60 or 86, texture_name .. " width")
            H.equal(settings.size[2], small and 70 or 108, texture_name .. " height")
            H.truthy(settings.uv00[1] >= 0 and settings.uv00[2] >= 0, texture_name .. " uv00")
            H.truthy(settings.uv11[1] <= 1 and settings.uv11[2] <= 1, texture_name .. " uv11")
            H.truthy(settings.uv00[1] < settings.uv11[1], texture_name .. " u ordering")
            H.truthy(settings.uv00[2] < settings.uv11[2], texture_name .. " v ordering")
        end
        H.equal(count, 24, "12 HUD + 12 small atlas sprites")

        local texture_block = assert(data_source:match(
            "local _texture_names = %b{}"))
        local standalone_count = 0
        local standalone = {}
        for texture_name in texture_block:gmatch('"([%w_]+)"') do
            standalone_count = standalone_count + 1
            standalone[texture_name] = true
            H.truthy(texture_name:find("medium_portrait_", 1, true) == 1,
                texture_name .. " must not collide with the atlas")
            H.equal(atlas[texture_name], nil,
                texture_name .. " cannot be both standalone and atlas")
        end
        H.equal(standalone_count, 12, "only medium portraits remain standalone")

        local hud_count, medium_count, small_count = 0, 0, 0
        for texture_name in main_source:gmatch('hud%s*=%s*"([%w_]+)"') do
            hud_count = hud_count + 1
            H.truthy(atlas[texture_name], texture_name .. " missing from atlas")
        end
        for texture_name in main_source:gmatch('medium%s*=%s*"([%w_]+)"') do
            medium_count = medium_count + 1
            H.truthy(standalone[texture_name], texture_name .. " missing standalone path")
        end
        for texture_name in main_source:gmatch('small%s*=%s*"([%w_]+)"') do
            small_count = small_count + 1
            H.truthy(atlas[texture_name], texture_name .. " missing from atlas")
        end
        H.equal(hud_count, 12, "map HUD count")
        H.equal(medium_count, 12, "map medium count")
        H.equal(small_count, 12, "map small count")
        H.truthy(data_source:find(
            '"materials/dynamic_cosmetic_portraits/dcp_portrait_atlas"', 1, true))
        H.truthy(data_source:find('"dcp_portrait_atlas_masked"', 1, true))
    end)

    H.test("DCP atlas resource preserves alpha and visible normal shader (#526)", function()
        local material = read(mod_root
            .. "/materials/dynamic_cosmetic_portraits/dcp_portrait_atlas.material")
        local texture = read(mod_root
            .. "/textures/dynamic_cosmetic_portraits/dcp_portrait_atlas.texture")
        local package_source = read(mod_root
            .. "/resource_packages/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.package")
        local png = read(mod_root
            .. "/textures/dynamic_cosmetic_portraits/dcp_portrait_atlas.png")

        H.truthy(material:find('dcp_portrait_atlas = {', 1, true))
        H.truthy(material:find('shader = "gui:DIFFUSE_MAP"', 1, true))
        H.truthy(texture:find('format = "A8R8G8B8"', 1, true))
        H.truthy(texture:find('enable_cut_alpha_threshold = false', 1, true))
        H.truthy(package_source:find(
            '"materials/dynamic_cosmetic_portraits/dcp_portrait_atlas"', 1, true))
        H.truthy(package_source:find(
            '"textures/dynamic_cosmetic_portraits/dcp_portrait_atlas"', 1, true))

        H.equal(png:sub(1, 8), "\137PNG\13\10\26\10", "PNG signature")
        local function u32be(offset)
            local a, b, c, d = png:byte(offset, offset + 3)
            return ((a * 256 + b) * 256 + c) * 256 + d
        end
        H.equal(u32be(17), 512, "atlas PNG width")
        H.equal(u32be(21), 512, "atlas PNG height")
    end)

    H.test("DCP generator rebuilds atlas and cannot restore cutout standalones (#526)", function()
        local source = read(mod_root .. "/tools/add_portrait.ps1")
        local rebuild = read(mod_root .. "/tools/rebuild_portrait_atlas.ps1")
        H.truthy(source:find('foreach ($prefix in @("medium_"))', 1, true))
        H.truthy(source:find('rebuild_portrait_atlas.ps1', 1, true))
        H.truthy(source:find('$shader = "gui:DIFFUSE_MAP"', 1, true))
        H.equal(source:find('$shader = if', 1, true), nil)
        H.truthy(rebuild:find('$atlasSize = 512', 1, true))
        H.truthy(rebuild:find('$atlas.SetPixel(', 1, true))
    end)

    H.test("DCP readiness fails open unless atlas and medium are resident (#526)", function()
        H.truthy(main_source:find("#_PORTRAIT_ATLAS_TEXTURES ~= 24", 1, true))
        H.truthy(main_source:find("#_PORTRAIT_STANDALONE_MATERIALS ~= 12", 1, true))
        H.truthy(main_source:find(
            "for _, texture_name in ipairs(_PORTRAIT_ATLAS_TEXTURES) do", 1, true))
        H.truthy(main_source:find(
            "for _, material_path in ipairs(_PORTRAIT_STANDALONE_MATERIALS) do", 1, true))
        H.truthy(main_source:find(
            'settings.material_name == _PORTRAIT_ATLAS_MATERIAL', 1, true))
        H.truthy(main_source:find(
            '_gui_has_material(gui, _PORTRAIT_ATLAS_MATERIAL)', 1, true))
        H.truthy(main_source:find(
            '_gui_has_material(gui, material_name)', 1, true))
        H.truthy(main_source:find(
            '_rt_register("portrait_cutouts_use_atlas_path_526"', 1, true))
    end)
end
