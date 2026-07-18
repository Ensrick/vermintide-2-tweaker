return function(H, repo_root)
    local cim_root = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local Policy = assert(loadfile(cim_root .. "_cim_forge_widget_material_policy.lua"))()

    local function fixture()
        return {
            {
                element = { passes = {
                    { pass_type = "rotated_texture", style_id = "unsafe_arch",
                        texture_id = "arch_texture" },
                    { pass_type = "texture", style_id = "safe_slot",
                        texture_id = "slot_texture" },
                    { pass_type = "text", style_id = "title", text_id = "title" },
                    { pass_type = "hotspot", content_id = "hotspot" },
                } },
                content = {
                    arch_texture = "icon_block_arch_masked",
                    slot_texture = "icon_block",
                    title = "Block angle",
                    hotspot = {},
                },
                style = {
                    unsafe_arch = {},
                    safe_slot = { masked = true },
                    title = {},
                },
            },
            {
                element = { passes = {
                    { pass_type = "texture_uv", content_id = "nested",
                        style_id = "future", texture_id = "texture_id" },
                } },
                content = {
                    nested = {
                        texture_id = { texture_id = "future_keep_only_material" },
                    },
                },
                style = { future = {} },
            },
        }
    end

    H.test("producer wrapper preserves nil and multiple returns", function()
        local after_calls = 0
        local a, b, c = Policy.call_then(function()
            return "first", nil, "third"
        end, function()
            after_calls = after_calls + 1
        end)
        H.equal(a, "first")
        H.equal(b, nil)
        H.equal(c, "third")
        H.equal(after_calls, 1)
    end)

    H.test("dynamic forge policy suppresses only unproven texture passes", function()
        local widgets = fixture()
        local report = Policy.sanitize_widgets(widgets, function(texture, flags)
            if texture == "icon_block" then
                H.equal(flags.masked, true)
                return true
            end
            return false
        end)
        H.equal(report.widgets_scanned, 2)
        H.equal(report.texture_passes, 3)
        H.equal(report.verified, 1)
        H.equal(report.suppressed, 2)
        H.equal(widgets[1].element.passes[1].content_check_function(), false)
        H.equal(widgets[1].element.passes[2].content_check_function, nil)
        H.equal(widgets[1].element.passes[3].content_check_function, nil)
        H.equal(widgets[1].element.passes[4].content_check_function, nil)
        H.equal(widgets[2].element.passes[1].content_check_function(), false)
    end)

    H.test("clone-on-write keeps shared pass definitions instance-local", function()
        local existing_check = function() return true end
        local shared_passes = {
            { pass_type = "texture", style_id = "icon", texture_id = "icon",
                content_check_function = existing_check },
            { pass_type = "text", style_id = "text", text_id = "text" },
        }
        local unsafe = { element = { passes = shared_passes },
            content = { icon = "unsafe", text = "unsafe row" },
            style = { icon = {}, text = {} } }
        local safe = { element = { passes = shared_passes },
            content = { icon = "safe", text = "safe row" },
            style = { icon = {}, text = {} } }
        Policy.sanitize_widgets({ unsafe, safe }, function(texture)
            return texture == "safe"
        end)
        H.equal(unsafe.element.passes == shared_passes, false)
        H.equal(unsafe.element.passes[1].content_check_function(), false)
        H.equal(safe.element.passes, shared_passes)
        H.equal(safe.element.passes[1].content_check_function, existing_check)
        H.equal(shared_passes[1].content_check_function, existing_check)
        H.equal(safe.element.passes[2].content_check_function, nil)
    end)

    H.test("dynamic forge policy is idempotent for already-suppressed passes", function()
        local widgets = fixture()
        Policy.sanitize_widgets(widgets, function() return false end)
        local first_check = widgets[1].element.passes[1].content_check_function
        local report = Policy.sanitize_widgets(widgets, function() return false end)
        H.equal(report.suppressed, 0)
        H.equal(widgets[1].element.passes[1].content_check_function, first_check)
    end)

    H.test("production closes late list widgets at the producer and exact renderer", function()
        local file = assert(io.open(cim_root .. "_cim_mission_forge_safety.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('mod:hook("HeroWindowWeaveForgeWeapons", "_setup_weapon_stats"', 1, true))
        H.truthy(source:find("scrollbar.list_widgets", 1, true))
        H.truthy(source:find("window._ui_top_renderer", 1, true))
        H.truthy(source:find("_cim83_forge_widget_policy.call_then", 1, true))
        H.equal(source:find('mod:hook("HeroWindowWeaveForgeWeapons", "_draw"', 1, true), nil)
    end)
end
