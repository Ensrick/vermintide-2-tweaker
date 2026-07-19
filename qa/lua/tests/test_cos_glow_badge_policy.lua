return function(H, repo_root)
    local path = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_badge_policy.lua"
    local Policy = dofile(path)

    H.test("Cosmetics rune badge uses committed RGB bytes", function()
        local color = Policy.color({ rune = { r = 300, g = 127.6, b = -5, intensity = 1 } })
        H.equal(color[1], 255)
        H.equal(color[2], 255)
        H.equal(color[3], 128)
        H.equal(color[4], 0)
    end)

    H.test("Cosmetics magic badge blend is deterministic and intensity weighted", function()
        local color = Policy.color({
            lower = { r = 255, g = 0, b = 0, intensity = 1 },
            upper = { r = 0, g = 0, b = 255, intensity = 3 },
            dots = { r = 0, g = 255, b = 0, intensity = 0 },
        })
        H.equal(color[1], 255)
        H.equal(color[2], 64)
        H.equal(color[3], 0)
        H.equal(color[4], 191)
    end)

    H.test("Cosmetics glow badge fails closed for inactive or disabled state", function()
        H.equal(Policy.color(nil), nil)
        H.equal(Policy.color({ disabled = true, rune = { intensity = 1 } }), nil)
        H.equal(Policy.color({ rune = { r = 255, intensity = 0 } }), nil)
        H.equal(Policy.color({ lower = { intensity = 0 }, upper = {}, dots = {} }), nil)
    end)

    H.test("Cosmetics glow editor button is family scoped", function()
        local closed = Policy.button("rune", false)
        H.truthy(closed.available)
        H.equal(closed.selected, false)
        local open = Policy.button("magic", true)
        H.truthy(open.available)
        H.truthy(open.selected)
        local absent = Policy.button(nil, true)
        H.equal(absent.available, false)
        H.equal(absent.selected, false)
    end)

    H.test("Cosmetics glow badge recognizes only pre-init illusion definitions", function()
        local definition = {
            scenegraph_id = "illusions_root",
            element = {
                passes = {
                    { pass_type = "hotspot", style_id = "hotspot" },
                    {
                        pass_type = "texture",
                        style_id = "icon_texture",
                        texture_id = "icon_texture",
                    },
                },
            },
            content = { button_hotspot = {} },
            style = { icon_texture = { offset = { 0, 0, 1 } } },
        }

        H.truthy(Policy.is_illusion_definition(definition))

        definition.element.pass_data = {}
        H.equal(Policy.is_illusion_definition(definition), false)
        definition.element.pass_data = nil

        definition.scenegraph_id = "inventory_root"
        H.equal(Policy.is_illusion_definition(definition), false)
        definition.scenegraph_id = "illusions_root"

        definition.content.button_hotspot = nil
        H.equal(Policy.is_illusion_definition(definition), false)
    end)
end
