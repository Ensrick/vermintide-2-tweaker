return function(Harness, repo_root)
    local script_path = repo_root
        .. "/dynamic_cosmetic_portraits/scripts/mods/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.lua"
    local file = assert(io.open(script_path, "rb"))
    local source = file:read("*a")
    file:close()

    Harness.test("DCP HUD and small portraits compile with alpha masking (#526)", function()
        local checked = 0
        for material_path in source:gmatch('"materials/ui/([^\"]+)"') do
            if not material_path:find("<", 1, true) and not material_path:match("^medium_") then
                local path = repo_root .. "/dynamic_cosmetic_portraits/materials/ui/"
                    .. material_path .. ".material"
                local material = assert(io.open(path, "rb"))
                local material_source = material:read("*a")
                material:close()
                Harness.truthy(material_source:find(
                    'shader = "gui_gradient:DIFFUSE_MAP:MASKED"', 1, true),
                    material_path .. " can render as an opaque rectangle")
                checked = checked + 1
            end
        end
        Harness.equal(checked, 24, "expected every current HUD/small portrait material")
    end)

    Harness.test("DCP generator preserves size-specific shader policy (#526)", function()
        local path = repo_root .. "/dynamic_cosmetic_portraits/tools/add_portrait.ps1"
        local tool = assert(io.open(path, "rb"))
        local source = tool:read("*a")
        tool:close()
        Harness.truthy(source:find('$prefix %-eq "medium_"'))
        Harness.truthy(source:find('gui_gradient:DIFFUSE_MAP:MASKED', 1, true))
        Harness.truthy(source:find('shader = "$shader"', 1, true))
    end)
end
