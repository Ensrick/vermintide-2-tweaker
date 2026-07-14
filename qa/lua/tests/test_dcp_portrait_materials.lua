return function(Harness, repo_root)
    local script_path = repo_root
        .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua"
    local file = assert(io.open(script_path, "rb"))
    local source = file:read("*a")
    file:close()

    Harness.test("DCP portraits retain the proven visible Gui shader (#526)", function()
        local checked = 0
        for material_path in source:gmatch('"materials/ui/([^\"]+)"') do
            if not material_path:find("<", 1, true) then
                local path = repo_root .. "/dynamic_cosmetic_portraits/materials/ui/"
                    .. material_path .. ".material"
                local material = assert(io.open(path, "rb"))
                local material_source = material:read("*a")
                material:close()
                Harness.truthy(material_source:find(
                    'shader = "gui:DIFFUSE_MAP"', 1, true),
                    material_path .. " can compile invisible in the Gui")
                checked = checked + 1
            end
        end
        Harness.equal(checked, 36, "expected every current portrait material")
    end)

    Harness.test("DCP generator rejects the invisible masked-gradient regression (#526)", function()
        local path = repo_root .. "/dynamic_cosmetic_portraits/tools/add_portrait.ps1"
        local tool = assert(io.open(path, "rb"))
        local source = tool:read("*a")
        tool:close()
        Harness.truthy(source:find('$shader = "gui:DIFFUSE_MAP"', 1, true))
        Harness.equal(source:find('$shader = if', 1, true), nil)
        Harness.truthy(source:find('shader = "$shader"', 1, true))
    end)
end
