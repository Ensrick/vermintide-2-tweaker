return function(H, repo_root)
    local policy_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_tooltip.lua"
    local Policy = assert(loadfile(policy_path))()
    local oracle_path = repo_root
        .. "/qa/lua/tests/fixtures/ct_boon_preview_production_oracle.lua"
    local Oracle = assert(loadfile(oracle_path))()
    local runtime_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_runtime.lua"
    local Runtime = assert(loadfile(runtime_path))()

    H.test("CT #1004 vanilla, talent, and modded descriptions use only the canonical resolver", function()
        local cases = {
            attack_speed = "Gain 10% attack speed.",
            talent_2_2 = "Career-specific talent description.",
            ct_meta_movespeed = "+1% movement speed per active boon.",
        }
        for name, expected in pairs(cases) do
            local profile_seen, career_seen
            local fallback_called = false
            local description, source = Policy.resolve_description({
                instance = { name = name, rarity = "exotic" },
                profile_index = 3,
                career_index = 2,
                canonical = function(instance, profile_index, career_index)
                    H.equal(instance.name, name)
                    profile_seen, career_seen = profile_index, career_index
                    return expected
                end,
                format_description = function()
                    fallback_called = true
                    return "Plausible but wrong value."
                end,
            })
            H.equal(description, expected)
            H.equal(source, "canonical")
            H.equal(profile_seen, 3)
            H.equal(career_seen, 2)
            H.equal(fallback_called, false)
        end
    end)

    H.test("CT #1004 canonical failure never reconstructs template values", function()
        local fallback_called = false
        local description, source = Policy.resolve_description({
            instance = { name = "third_party_boon", rarity = "rare" },
            template = {
                advanced_description = "third_party_boon_desc",
                description_values = { value = 10 },
            },
            canonical = function() error("runtime registration incomplete") end,
            format_description = function()
                fallback_called = true
                return "Registered mod description with guessed 10%."
            end,
            localize = function()
                fallback_called = true
                return "Plausible localized template."
            end,
            unavailable = "Description unavailable.",
        })
        H.equal(description, "Description unavailable.")
        H.equal(source, "unavailable")
        H.equal(fallback_called, false)

        description, source = Policy.resolve_description({
            canonical = function() return "<different_missing_talent_desc>" end,
            unavailable = "[Invalid String Format]",
        })
        H.equal(description, "Description unavailable.")
        H.equal(source, "unavailable")
    end)

    H.test("CT #1004 oversized canonical text fails neutral before layout", function()
        local too_long = string.rep("x", Policy.LIMITS.max_description_bytes + 1)
        local description, source = Policy.resolve_description({
            canonical = function() return too_long end,
            unavailable = "Description unavailable.",
        })
        H.equal(description, "Description unavailable.")
        H.equal(source, "oversize")

        local calls = 0
        local layout, err = Policy.layout_description(too_long, function()
            calls = calls + 1
            return 1
        end)
        H.equal(layout, nil)
        H.equal(err, "description too long")
        H.equal(calls, 0, "oversized input must not enter renderer measurement")
    end)

    H.test("CT #1004 measured layout shrinks within 18 to 14 point bounds", function()
        local calls = {}
        local layout = assert(Policy.layout_description("A measured description.",
            function(text, width, font_size)
                calls[#calls + 1] = { text, width, font_size }
                return font_size > 14 and 700 or 500
            end))
        H.equal(layout.font_size, 14)
        H.equal(#layout.pages, 1)
        H.equal(layout.measured_description_height, 500)
        H.equal(layout.width, 620)
        H.equal(layout.body_width, 588)
        H.truthy(layout.height <= 650)
        H.equal(calls[1][2], 588)
        H.equal(calls[1][3], 18)
        H.equal(calls[#calls][3], 14)
    end)

    H.test("CT #1004 measured overflow pages preserve the complete UTF-8 description", function()
        local description = string.rep("Long localized Bögenhafen description. ", 80)
            .. "最後の段落"
        local layout = assert(Policy.layout_description(description,
            function(text, width, font_size)
                H.equal(width, 588)
                H.truthy(font_size >= 14 and font_size <= 18)
                return #text * font_size / 10
            end))
        H.equal(layout.font_size, 14)
        H.truthy(#layout.pages > 1)
        H.equal(table.concat(layout.pages), description,
            "scroll pages must retain every localized byte")
        H.equal(layout.height, 650)
        H.truthy(layout.max_page_height <= layout.body_height)
        for _, page in ipairs(layout.pages) do
            H.truthy(#page > 0)
            H.truthy(#page * layout.font_size / 10 <= layout.body_height)
        end
    end)

    H.test("CT #1004 pathological pagination obeys hard page and measurement caps", function()
        local calls = 0
        local description = string.rep("x", 1000)
        local pages, _, err = Policy.paginate(description, 588, 14, 1,
            function(text)
                calls = calls + 1
                return #text
            end)
        H.equal(pages, nil)
        H.equal(err, "page limit exceeded")
        H.truthy(calls <= Policy.LIMITS.max_measure_calls)
        H.equal(Policy.LIMITS.max_description_bytes, 16384)
        H.equal(Policy.LIMITS.max_pages, 16)
        H.equal(Policy.LIMITS.max_measure_calls, 256)

        local budget = { calls = 0, limit = 3 }
        pages, _, err = Policy.paginate(description, 588, 14, 1,
            function(text) return #text end, budget)
        H.equal(pages, nil)
        H.equal(err, "measurement limit exceeded")
        H.equal(budget.calls, 3)
    end)

    H.test("CT #1004 layout matches the committed production scenegraph oracle", function()
        local g = Policy.GEOMETRY
        local production = Policy.production_geometry()
        local banner = Oracle.geometry.banner_right
        local divider = Oracle.geometry.reward_divider
        H.equal(Oracle.provenance.commit,
            "c5e4968b1fbb00c49884e56d640ef990a9c04dd0")
        H.equal(banner.scale, "fit_height")
        H.equal(divider.parent, "banner_right")
        H.equal(divider.vertical_alignment, "top")
        H.equal(g.banner_width, banner.width)
        H.equal(g.banner_height, banner.height)
        H.equal(g.reward_divider_x, divider.x)
        H.equal(g.reward_divider_y_from_top, -divider.y)
        H.equal(g.reward_divider_width, divider.width)
        H.equal(g.reward_divider_height, divider.height)
        H.equal(g.row_pitch, 28)
        H.equal(g.row_count, 9)
        H.equal(production.divider_world_y,
            banner.height + divider.y - divider.height)
        H.equal(production.first_row_center_world_y, 330)
        H.equal(production.last_row_center_world_y, 106)
        H.equal(production.tooltip_world_left, 24)
        H.equal(production.tooltip_world_right, 644)
        H.equal(production.tooltip_world_bottom, 398)
        H.equal(production.tooltip_world_top, 1048)
        H.truthy(production.tooltip_world_left >= 0)
        H.truthy(production.tooltip_world_right <= g.banner_width)
        H.truthy(production.tooltip_world_bottom > production.first_row_center_world_y)
        H.truthy(production.tooltip_world_top <= g.banner_height)
    end)

    H.test("CT #1004 faithful production metric adapter executes renderer semantics", function()
        local calls = {}
        local deps = {
            UIFontByResolution = function(style)
                calls[#calls + 1] = "resolution"
                H.equal(style.font_type, "hell_shark")
                return { "font_resource" }, 21
            end,
            UIGetFontHeight = function(gui, font_type, scaled_size)
                calls[#calls + 1] = "height"
                H.equal(gui, "gui")
                H.equal(font_type, "hell_shark")
                H.equal(scaled_size, 21)
                return 99, -4, 11
            end,
            word_wrap = function(renderer, text, font, size, width)
                calls[#calls + 1] = "wrap"
                H.equal(renderer.gui, "gui")
                H.equal(text, "measured production text")
                H.equal(font, "font_resource")
                H.equal(size, 21)
                H.equal(width, 588)
                return { "one", "two", "three" }
            end,
            Localize = function(text) return text end,
            TextToUpper = function(text) return text:upper() end,
            inv_scale = 0.5,
        }
        local height, lines = Oracle.get_text_height(deps, { gui = "gui" },
            { 588, 0 }, {
                font_size = 18,
                font_type = "hell_shark",
                word_wrap = true,
            }, "measured production text")
        H.equal(height, 22.5)
        H.equal(lines, 3)
        H.equal(table.concat(calls, ","), "resolution,height,wrap")
    end)

    H.test("CT #1004 controller paging uses source-proven actions and debounce", function()
        for _, platform in ipairs({ "xb1", "ps4", "ps_pad" }) do
            local bindings = Oracle.page_actions[platform]
            H.equal(bindings.right_press[3], "pressed")
            H.equal(bindings.right_hold[3], "held")
        end
        H.equal(Oracle.page_actions.xb1.right_press[2], "right_shoulder")
        H.equal(Oracle.page_actions.ps4.right_press[2], "r1")
        H.equal(Policy.page_hint_key(false), "ct_boon_preview_page_hint_mouse")
        H.equal(Policy.page_hint_key(true), "ct_boon_preview_page_hint_controller")

        local delta, latched, controller = Policy.navigation_step(nil, true, true, false)
        H.equal(delta, 1)
        H.equal(latched, true)
        H.equal(controller, true)
        delta, latched = Policy.navigation_step(nil, true, true, latched)
        H.equal(delta, 0, "held/repeated controller edge must not page twice")
        delta, latched = Policy.navigation_step(nil, false, false, latched)
        H.equal(delta, 0)
        H.equal(latched, false)
        delta = Policy.navigation_step(-1, false, false, latched)
        H.equal(delta, 1)

        local fake_mod = {
            _ct_boon_preview_tooltip = Policy,
            localize = function(_, key)
                if key == "ct_boon_preview_page_hint_mouse" then
                    return "Mouse wheel: pages"
                end
                return "Right shoulder: next page"
            end,
        }
        Runtime.install(fake_mod)
        local widget = {
            _ct_pages = { "page one", "page two" },
            _ct_page_index = 2,
            content = { description = "page two", page_indicator = "" },
        }
        fake_mod._ct_update_boon_tooltip_hint(widget, false)
        H.equal(widget.content.page_indicator, "2/2  Mouse wheel: pages")
        fake_mod._ct_scroll_boon_tooltip(widget, 1, true)
        H.equal(widget._ct_page_index, 1, "controller next must wrap after last page")
        H.equal(widget.content.description, "page one")
        fake_mod._ct_update_boon_tooltip_hint(widget, true)
        H.equal(widget.content.page_indicator, "1/2  Right shoulder: next page")
    end)

    H.test("CT #1004 production wiring is lazy and composes the singleton native-cursor draw hook", function()
        local main_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
        local f = assert(io.open(main_path, "rb"))
        local source = f:read("*a"); f:close()
        f = assert(io.open(runtime_path, "rb"))
        local runtime = f:read("*a"); f:close()
        local _, draw_hooks = source:gsub(
            'mod:hook_safe%("IngamePlayerListUI", "_draw"', "")
        H.equal(draw_hooks, 1, "#461/#533/#571/#1004 must share one draw hook")
        H.truthy(source:find('CT_BOON_TOOLTIP_1004_MARKER', 1, true))
        H.truthy(source:find('pass_type = "hotspot"', 1, true))
        H.truthy(source:find('self._cursor_active and hotspot and hotspot.is_hover', 1, true))
        H.truthy(runtime:find('ui_utils.get_text_height(ui_renderer, { width, 0 }', 1, true),
            "production tooltip must use live renderer font metrics")
        H.truthy(source:find('input_service:get("scroll_axis")', 1, true),
            "measured overflow must remain reachable")
        H.truthy(source:find('input_service:get("right_press")', 1, true),
            "controller paging must consume the source-proven pressed action")
        H.truthy(source:find('input_service:get("right_hold")', 1, true),
            "controller paging must explicitly debounce the held action")
        H.truthy(source:find('widget._ct_boon_tooltip_data, r', 1, true),
            "tooltip measurement and construction must be lazy on first hover")
        H.truthy(source:find('icon_widget._ct_boon_tooltip_attempted = false', 1, true))
        H.truthy(source:find('pcall(UIRenderer.draw_widget, r, tooltip)', 1, true))

        local start = assert(source:find('CT_BOON_TOOLTIP_1004_MARKER', 1, true))
        local finish = assert(source:find('-- Textual preview + /verify surface for #461', start, true))
        local block = source:sub(start, finish - 1)
        H.equal(block:find('format_localized_description', 1, true), nil,
            "#1004 must not reconstruct canonical description values")
        local description_start = assert(block:find(
            'function mod._ct_start_boon_description', 1, true))
        local description_finish = assert(block:find(
            'function mod._ct_collect_start_boons', description_start, true))
        local description_block = block:sub(description_start, description_finish - 1)
        H.equal(description_block:find('DeusPowerUpTemplates', 1, true), nil,
            "description path must not read templates outside the native resolver")
        H.equal(block:find('mod:hook_safe("IngamePlayerListUI", "update"', 1, true), nil,
            "#1004 must use the native cursor activation/release path")
        H.equal(block:find('mod:hook("IngamePlayerListUI", "update"', 1, true), nil,
            "#1004 must not own the native input lifecycle")
        H.equal(block:find('_set_active(', 1, true), nil,
            "#1004 must not change native Tab/cursor release behavior")
    end)
end
