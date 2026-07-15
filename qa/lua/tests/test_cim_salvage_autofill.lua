return function(H, repo_root)
    local root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local core = assert(loadfile(root .. "_cim_salvage_autofill_core.lua"))()

    local function widget(scenegraph_id, texture_id)
        return {
            scenegraph_id = scenegraph_id,
            content = { texture_icon = { texture_id = texture_id } },
        }
    end

    local function definitions(rare_position, exotic_position, clear_position)
        return {
            widgets = {
                auto_fill_exotic = widget("auto_fill_exotic", "store_tag_icon_weapon_exotic"),
                auto_fill_clear = widget("auto_fill_clear", "layout_button_back"),
            },
            scenegraph_definition = {
                auto_fill_rare = { position = rare_position },
                auto_fill_exotic = { position = exotic_position },
                auto_fill_clear = { position = clear_position },
            },
        }
    end

    H.test("CIM salvage adds vertical fifth rarity button before Clear", function()
        local desktop = definitions({ 0, -140, 1 }, { 0, -210, 1 }, { 0, -280, 1 })
        local ok = core.install(desktop)
        H.truthy(ok)
        H.truthy(core.is_installed(desktop))
        H.equal(desktop.scenegraph_definition.auto_fill_modded.position[2], -280)
        H.equal(desktop.scenegraph_definition.auto_fill_clear.position[2], -350)
        H.equal(desktop.widgets.auto_fill_exotic.content.texture_icon.texture_id,
            "store_tag_icon_weapon_exotic")
        H.equal(desktop.widgets.auto_fill_modded.content.texture_icon.texture_id,
            "store_tag_icon_weapon_modded")
    end)

    H.test("CIM salvage adds horizontal fifth rarity button before Clear", function()
        local console = definitions({ 220, -125, 1 }, { 290, -125, 1 }, { 360, -125, 1 })
        local ok = core.install(console)
        H.truthy(ok)
        H.truthy(core.is_installed(console))
        H.equal(console.scenegraph_definition.auto_fill_modded.position[1], 360)
        H.equal(console.scenegraph_definition.auto_fill_clear.position[1], 430)
    end)

    H.test("CIM salvage layout transform is reload-idempotent", function()
        local console = definitions({ 220, -125, 1 }, { 290, -125, 1 }, { 360, -125, 1 })
        H.truthy(core.install(console))
        local modded_widget = console.widgets.auto_fill_modded
        local modded_node = console.scenegraph_definition.auto_fill_modded
        H.truthy(core.install(console))
        H.equal(console.widgets.auto_fill_modded, modded_widget)
        H.equal(console.scenegraph_definition.auto_fill_modded, modded_node)
    end)

    H.test("CIM production reuses vanilla bounded salvage paths", function()
        local file = assert(io.open(root .. "_cim_salvage_modded_button.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('self:_fill_by_rarity("modded")', 1, true))
        H.truthy(source:find('set_auto_fill_rarity("modded")', 1, true))
        H.truthy(source:find("CraftingSettings.NUM_SALVAGE_SLOTS ~= 9", 1, true))
    end)

    H.test("CIM salvage crossed-swords asset is fully packaged", function()
        local mod_root = repo_root .. "/crafting_in_modded_dev/"
        local paths = {
            "gui/1080p/single_textures/cim/store_tag_icon_weapon_modded.png",
            "gui/1080p/single_textures/cim/store_tag_icon_weapon_modded.texture",
            "materials/ui/store_tag_icon_weapon_modded.material",
        }
        for _, path in ipairs(paths) do
            local file = io.open(mod_root .. path, "rb")
            H.truthy(file, "missing salvage icon resource: " .. path)
            if file then file:close() end
        end

        local function read(path)
            local file = assert(io.open(mod_root .. path, "rb"))
            local source = file:read("*a")
            file:close()
            return source
        end
        H.truthy(read("resource_packages/crafting_in_modded_dev/crafting_in_modded_dev.package"):find(
            '"materials/ui/store_tag_icon_weapon_modded"', 1, true))
        H.truthy(read("resource_packages/crafting_in_modded_dev/crafting_in_modded_dev.package"):find(
            '"gui/1080p/single_textures/cim/store_tag_icon_weapon_modded"', 1, true))
        H.truthy(read("scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev_data.lua"):find(
            '"store_tag_icon_weapon_modded"', 1, true))
    end)
end
