return function(H, repo_root)
    local planner = dofile(repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_external_group.lua")

    local function ids(nodes)
        local out = {}
        for i = 1, #nodes do out[#out + 1] = nodes[i].setting_id or "" end
        return table.concat(out, ",")
    end

    H.test("UI Tweaks fold consumes the live VMF tree and preserves GUT controls", function()
        local stale = { setting_id = "old_mirrored_checkbox", type = "checkbox", depth = 2 }
        local widgets = {
            { type = "header", mod_name = "gut_dev", depth = 0 },
            { setting_id = "gut_hide_hud_ui_group", type = "group", depth = 0 },
            { setting_id = "hb_group", type = "group", depth = 1 },
            stale,
            { setting_id = "gut_uitweaks_integration_group", type = "group", depth = 2 },
            { setting_id = "gut_uitweaks_sync", type = "checkbox", depth = 3 },
            { setting_id = "hud_control_after_ui_tweaks", type = "checkbox", depth = 1 },
        }
        local live_slider = { setting_id = "FUTURE_SLIDER", type = "numeric", depth = 0 }
        local live = {
            { type = "header", mod_name = "HideBuffs" },
            { setting_id = "LIVE_GROUP", type = "group", depth = 0 },
            { setting_id = "LIVE_CHECKBOX", type = "checkbox", depth = 1 },
            live_slider,
            { setting_id = "FUTURE_DROPDOWN", type = "dropdown", depth = 0 },
            { setting_id = "FUTURE_KEYBIND", type = "keybind", depth = 0 },
        }
        local hb = {}
        local result = planner.replace_group_children({
            widgets = widgets,
            live_list = live,
            group_id = "hb_group",
            preserve_group_ids = { gut_uitweaks_integration_group = true },
            owners = { ckc_setting = { mod_id = "Crosshair Kill Confirmation" } },
            owner_mod_ids = { "gut_dev", "Crosshair Kill Confirmation" },
            base_owner_id = "gut_dev",
            owner_id = "HideBuffs",
            owner_obj = hb,
            exclude_owner_from_profiles = true,
        })

        H.equal(result.changed, true)
        H.equal(result.injected, 5)
        H.equal(ids(result.widgets), table.concat({
            "", "gut_hide_hud_ui_group", "hb_group", "LIVE_GROUP", "LIVE_CHECKBOX",
            "FUTURE_SLIDER", "FUTURE_DROPDOWN", "FUTURE_KEYBIND",
            "gut_uitweaks_integration_group", "gut_uitweaks_sync",
            "hud_control_after_ui_tweaks",
        }, ","))
        H.equal(result.widgets[4].depth, 2)
        H.equal(result.widgets[5].depth, 3)
        H.equal(result.widgets[6].depth, 2)
        H.equal(live_slider.depth, 0, "VMF-owned nodes must never be mutated")
        H.equal(stale.depth, 2)
        H.equal(result.owners.FUTURE_SLIDER.mod_id, "HideBuffs")
        H.equal(result.owners.FUTURE_SLIDER.mod_obj, hb)
        H.equal(result.owners.ckc_setting.mod_id, "Crosshair Kill Confirmation")
        H.equal(table.concat(result.owner_mod_ids, ","),
            "gut_dev,Crosshair Kill Confirmation,HideBuffs")
        H.equal(result.profile_excluded_owners.HideBuffs, true)
    end)

    H.test("live external lookup uses VMF synthesized mod headers", function()
        local wanted = { { mod_name = "HideBuffs" }, { setting_id = "x" } }
        local data = {
            { { mod_name = "gut_dev" }, { setting_id = "a" } },
            wanted,
        }
        H.equal(planner.find_mod_list(data, "HideBuffs"), wanted)
        H.equal(planner.find_mod_list(data, "missing"), nil)
    end)

    H.test("malformed or late VMF data preserves the authored fallback tree", function()
        local widgets = { { setting_id = "hb_group", type = "group", depth = 0 } }
        local missing = planner.replace_group_children({ widgets = widgets })
        H.equal(missing.changed, false)
        H.equal(missing.reason, "live_list_missing")
        H.equal(missing.widgets, widgets)

        local empty = planner.replace_group_children({
            widgets = widgets,
            live_list = { { mod_name = "HideBuffs", type = "header" } },
            group_id = "hb_group",
        })
        H.equal(empty.changed, false)
        H.equal(empty.reason, "live_tree_empty")
        H.equal(empty.widgets, widgets)
    end)

    H.test("late VMF tree retains known stock ownership without profile capture", function()
        local hb = {}
        local result = planner.bridge_known_fallback({
            widgets = {
                { setting_id = "known", type = "checkbox" },
                { setting_id = "future", type = "numeric" },
                { setting_id = "group", type = "group" },
            },
            setting_names = { KNOWN = "known", FUTURE = "future", GROUP = "group" },
            owner_mod_ids = { "gut_dev" },
            base_owner_id = "gut_dev",
            owner_id = "HideBuffs",
            owner_obj = hb,
            exclude_owner_from_profiles = true,
        })
        H.equal(result.changed, true)
        H.equal(result.bridged, 2)
        H.equal(result.owners.known.mod_obj, hb)
        H.equal(result.owners.future.mod_id, "HideBuffs")
        H.equal(result.owners.group, nil)
        H.equal(result.profile_excluded_owners.HideBuffs, true)
    end)

    H.test("both presentations consume the shared live-tree and profile policy", function()
        for _, name in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
            local file = assert(io.open(repo_root
                .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/" .. name, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(source:find("external_group.find_mod_list", 1, true))
            H.truthy(source:find("external_group.replace_group_children", 1, true))
            H.truthy(source:find("external_group.bridge_known_fallback", 1, true))
            H.truthy(source:find("_profile_excluded_owners", 1, true))
        end
    end)
end
