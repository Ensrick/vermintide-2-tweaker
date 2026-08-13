return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Probe = assert(loadfile(root .. "_gut_dx12_fence630.lua"))()

    H.test("#630 records a balanced borrowed-renderer lifecycle", function()
        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone", renderer = "renderer-a", tab = "gut_dev" })
        probe:before_draw({ focus = true, tab = "gut_dev", rows = 12, visible = 8 })
        probe:after_draw()
        probe:before_draw({ focus = true, tab = "wt_dev", rows = 40, visible = 11 })
        probe:after_draw()
        probe:leave("on_exit")

        local state = probe:snapshot()
        H.equal(state.draw_begins, 2)
        H.equal(state.draw_ends, 2)
        H.equal(state.imbalance_count, 0)
        H.equal(state.active, false)
        H.truthy(string.find(table.concat(lines, "\n"), "tab=wt_dev", 1, true))
        H.truthy(string.find(table.concat(lines, "\n"), "balance=0", 1, true))
    end)

    H.test("#630 exposes an unmatched or re-entered draw pass", function()
        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone" })
        probe:before_draw({ focus = true, tab = "wt_dev" })
        probe:before_draw({ focus = true, tab = "wt_dev" })
        probe:leave("probe")

        local state = probe:snapshot()
        H.equal(state.draw_begins, 2)
        H.equal(state.draw_ends, 0)
        H.truthy(state.imbalance_count >= 2)
        H.truthy(string.find(table.concat(lines, "\n"), "anomaly=draw_reentry", 1, true))
        H.truthy(string.find(table.concat(lines, "\n"), "balance=2", 1, true))
    end)

    H.test("#630 focus and tab evidence is edge-triggered and hard-capped", function()
        H.equal(Probe.DEFAULT_LINE_CAP, 48)
        local lines = {}
        local probe = Probe.new({
            line_cap = 7,
            emit = function(line) lines[#lines + 1] = line end,
        })
        probe:enter({ presentation = "standalone" })
        for i = 1, 20 do
            probe:before_draw({ focus = i < 10, tab = i < 15 and "wt_dev" or "gut_dev" })
            probe:after_draw()
        end
        probe:leave("on_exit")

        local state = probe:snapshot()
        H.equal(#lines, 7)
        H.equal(state.lines, 7)
        H.equal(state.capped, true)
        H.equal(state.draw_begins, 20)
        H.equal(state.draw_ends, 20)
    end)

    H.test("#630 distinguishes Equipment tab subsections", function()
        local owner = {
            _expanded = { ["gut_equipment:__equip_weapons"] = true },
            _rows = {
                { _wtype = "group", _setting_id = "__equip_cosmetics",
                    _group_key = "gut_equipment:__equip_cosmetics", _middle_visible = true },
                { _wtype = "group", _setting_id = "__equip_crafting",
                    _group_key = "gut_equipment:__equip_crafting", _middle_visible = false },
                { _wtype = "group", _setting_id = "__equip_weapons",
                    _group_key = "gut_equipment:__equip_weapons", _middle_visible = true },
                { _wtype = "group", _setting_id = "nested_weapon_group",
                    _group_key = "gut_equipment:nested_weapon_group", _middle_visible = true },
            },
        }
        local state, expanded = Probe.equipment_state(owner)
        H.equal(state, "cosmetics:collapsed-stored:visible=true;crafting:collapsed-stored:visible=false;weapons:expanded-stored:visible=true")
        H.equal(expanded, "cosmetics:collapsed-stored;crafting:collapsed-stored;weapons:expanded-stored")

        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone" })
        probe:before_draw({
            focus = true,
            tab = "gut_equipment",
            rows = 4,
            visible = 2,
            equipment_state = state,
            equipment_expanded = expanded,
        })
        probe:after_draw()

        owner._expanded["gut_equipment:__equip_weapons"] = nil
        owner._rows[3]._display_expanded = true
        local forced_state, forced_expanded = Probe.equipment_state(owner)
        probe:before_draw({
            focus = true,
            tab = "gut_equipment",
            rows = 4,
            visible = 2,
            equipment_state = forced_state,
            equipment_expanded = forced_expanded,
        })
        probe:after_draw()

        -- Scrolling changes prior-frame viewport visibility, not the active
        -- subsection. It must not consume another bounded diagnostic record.
        owner._rows[3]._middle_visible = false
        local scrolled_state, scrolled_expanded = Probe.equipment_state(owner)
        probe:before_draw({
            focus = true,
            tab = "gut_equipment",
            rows = 4,
            visible = 1,
            equipment_state = scrolled_state,
            equipment_expanded = scrolled_expanded,
        })
        probe:after_draw()
        probe:leave("on_exit")

        local text = table.concat(lines, "\n")
        H.truthy(string.find(text, "weapons:expanded-stored:visible=true", 1, true))
        H.truthy(string.find(text, "weapons:expanded-forced:visible=true", 1, true))
        H.equal(string.find(text, "nested_weapon_group", 1, true), nil)
        local equipment_edges = 0
        for _ in text:gmatch("equipment_state=") do equipment_edges = equipment_edges + 1 end
        H.equal(equipment_edges, 2)
    end)

    H.test("#630 records the post-pass visible resource set only on useful edges", function()
        local owner = {
            _rows = {
                {
                    _setting_id = "weapon_toggle_a", _wtype = "checkbox",
                    _middle_visible = true,
                    content = { icon = "icon_weapon_a" },
                    style = { label = { font_type = "hell_shark" } },
                    element = { passes = {
                        { pass_type = "texture", texture_id = "icon" },
                        { pass_type = "text", style_id = "label", text_id = "label" },
                    } },
                },
                {
                    _setting_id = "hidden_weapon_toggle", _wtype = "checkbox",
                    _middle_visible = false,
                    content = { texture_id = "must_not_appear" },
                    style = {}, element = { passes = { { pass_type = "texture" } } },
                },
                {
                    _setting_id = "weapon_slider_b", _wtype = "numeric",
                    _middle_visible = true,
                    content = { nested = { tex = "icon_weapon_b" } },
                    style = {}, element = { passes = {
                        { pass_type = "texture_uv", content_id = "nested", texture_id = "tex" },
                    } },
                },
            },
        }
        local rows, resources = Probe.visible_draw_signature(owner)
        H.equal(rows, "weapon_toggle_a:checkbox,weapon_slider_b:numeric")
        H.equal(resources, "font:hell_shark,texture:icon_weapon_a,texture:icon_weapon_b")

        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone" })
        probe:before_draw({ owner = owner, focus = true, tab = "gut_equipment" })
        probe:after_draw()
        local after_first = #lines
        probe:before_draw({ owner = owner, focus = true, tab = "gut_equipment" })
        probe:after_draw()
        H.equal(#lines, after_first, "steady frames must not emit resource evidence")
        probe:before_draw({ owner = owner, focus = false, tab = "gut_equipment" })
        probe:after_draw()

        local text = table.concat(lines, "\n")
        local evidence = 0
        for _ in text:gmatch("frame_evidence") do evidence = evidence + 1 end
        H.equal(evidence, 2, "first draw and focus edge each need one post-pass breadcrumb")
        H.truthy(text:find("visible_rows=weapon_toggle_a:checkbox,weapon_slider_b:numeric", 1, true))
        H.truthy(text:find("resource_candidates=font:hell_shark,texture:icon_weapon_a,texture:icon_weapon_b", 1, true))
        H.equal(text:find("must_not_appear", 1, true), nil)
    end)

    H.test("#630 is wired around both Mod Tweaker presentation passes", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(root .. name, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(string.find(source, "dx12_diag:enter", 1, true), name .. " missing enter")
            H.truthy(string.find(source, "dx12_diag:before_draw", 1, true), name .. " missing begin edge")
            H.truthy(string.find(source, "dx12_diag:after_draw", 1, true), name .. " missing end edge")
            H.truthy(string.find(source, "dx12_diag:leave", 1, true), name .. " missing exit")
        end
    end)
end
