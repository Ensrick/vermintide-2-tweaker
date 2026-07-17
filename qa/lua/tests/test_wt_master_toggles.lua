return function(H, repo_root)
    local path = repo_root
        .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_master_toggles.lua"
    local Masters = assert(loadfile(path))()

    local function checkbox(id, label, default)
        return {
            setting_id = id,
            type = "checkbox",
            default_value = default == true,
            _label = label,
        }
    end

    local function fixture()
        local rows = {
            checkbox("unlock_es_mercenary_bw_mace", "Sienna: Mace", false),
            checkbox("unlock_es_mercenary_we_glaive", "Kerillian: Glaive", false),
            checkbox("unlock_es_mercenary_dr_axe", "Bardin: Axe", false),
            checkbox("unlock_es_mercenary_es_sword", "Kruber: Sword", true),
            checkbox("unlock_es_mercenary_wh_flail", "Saltzpyre: Flail", false),
        }
        local huntsman = {
            checkbox("unlock_es_huntsman_we_glaive", "[working] Kerillian: Glaive", false),
            checkbox("unlock_es_huntsman_es_sword", "Kruber: Sword", true),
        }
        local ranged = {
            checkbox("unlock_es_mercenary_we_longbow", "Kerillian: Longbow", false),
            checkbox("unlock_es_mercenary_es_handgun", "Kruber: Handgun", true),
        }
        local mercenary_leaf = {
            setting_id = "melee_es_mercenary", type = "group", sub_widgets = rows,
        }
        local huntsman_leaf = {
            setting_id = "melee_es_huntsman", type = "group", sub_widgets = huntsman,
        }
        local ranged_leaf = {
            setting_id = "ranged_es_mercenary", type = "group", sub_widgets = ranged,
        }
        local data = { options = { widgets = { {
            setting_id = "weapon_availability", type = "group", sub_widgets = {
                { setting_id = "char_kruber", type = "group", sub_widgets = {
                    { setting_id = "kruber_melee_group", type = "group",
                        sub_widgets = { mercenary_leaf, huntsman_leaf } },
                    { setting_id = "kruber_ranged_group", type = "group",
                        sub_widgets = { ranged_leaf } },
                } },
            },
        } } } }

        local values, writes, loc = {}, {}, {}
        for _, node in ipairs(rows) do loc[node.setting_id] = { en = node._label } end
        for _, node in ipairs(huntsman) do loc[node.setting_id] = { en = node._label } end
        for _, node in ipairs(ranged) do loc[node.setting_id] = { en = node._label } end
        local mod = {
            _wt_loc_raw = loc,
            get = function(_, id) return values[id] end,
            set = function(_, id, value, notify)
                values[id] = value
                writes[#writes + 1] = { id = id, value = value, notify = notify }
            end,
        }
        return mod, data, values, writes, mercenary_leaf, huntsman_leaf, ranged_leaf
    end

    H.test("WT #611 masters are gear parents inside exact career leaves in requested source order", function()
        local mod, data, _, _, mercenary, huntsman, ranged = fixture()
        H.equal(Masters.build_widgets(mod, data), 9)
        local expected = {
            "wtmaster_es_mercenary_melee_kruber",
            "wtmaster_es_mercenary_melee_bardin",
            "wtmaster_es_mercenary_melee_kerillian",
            "wtmaster_es_mercenary_melee_saltzpyre",
            "wtmaster_es_mercenary_melee_sienna",
        }
        for index, id in ipairs(expected) do
            H.equal(mercenary.sub_widgets[index].setting_id, id)
            H.truthy(type(mercenary.sub_widgets[index].sub_widgets) == "table",
                "every master must expose an advanced-options child list")
        end
        H.equal(#mercenary.sub_widgets, 5,
            "flat weapon rows must move under their source master, not remain duplicated")
        H.equal(huntsman.sub_widgets[1].setting_id,
            "wtmaster_es_huntsman_melee_kruber")
        H.equal(huntsman.sub_widgets[2].setting_id,
            "wtmaster_es_huntsman_melee_kerillian")
        H.equal(ranged.sub_widgets[1].setting_id,
            "wtmaster_es_mercenary_ranged_kruber")
        H.equal(ranged.sub_widgets[2].setting_id,
            "wtmaster_es_mercenary_ranged_kerillian")
        H.deep_equal(mod._wt_master_children.wtmaster_es_mercenary_melee_kerillian,
            { "unlock_es_mercenary_we_glaive" })
        H.deep_equal(mod._wt_master_children.wtmaster_es_huntsman_melee_kerillian,
            { "unlock_es_huntsman_we_glaive" })
        H.equal(mercenary.sub_widgets[3].sub_widgets[1].setting_id,
            "unlock_es_mercenary_we_glaive")
        H.equal(mod._wt_master_widget_children.wtmaster_es_mercenary_melee_kerillian[1],
            mercenary.sub_widgets[3].sub_widgets[1],
            "runtime diagnostics must reference the exact nested widget node")
    end)

    H.test("WT #611 gear view allows partial selection while derived master stays off", function()
        local mod, data, values, writes, mercenary = fixture()
        Masters.build_widgets(mod, data)
        local master = mercenary.sub_widgets[3]
        H.equal(master.setting_id, "wtmaster_es_mercenary_melee_kerillian")
        H.equal(master.sub_widgets[1].setting_id, "unlock_es_mercenary_we_glaive")

        values.unlock_es_mercenary_we_glaive = true
        values.wtmaster_es_mercenary_melee_kerillian = false
        -- A one-child fixture becomes fully selected; prove the general partial
        -- behavior with a second child in the same source bucket.
        master.sub_widgets[2] = checkbox(
            "unlock_es_mercenary_we_spear", "Kerillian: Spear", false)
        mod._wt_master_children[master.setting_id][2] =
            "unlock_es_mercenary_we_spear"
        mod._wt_child_to_master.unlock_es_mercenary_we_spear = master.setting_id
        values.unlock_es_mercenary_we_spear = false
        Masters.on_child_changed(mod, "unlock_es_mercenary_we_glaive")
        H.equal(values.unlock_es_mercenary_we_glaive, true,
            "manual child selection must not be cleared by an off master")
        H.equal(values.wtmaster_es_mercenary_melee_kerillian, false,
            "a partial advanced-options selection must leave the master off")
        H.equal(#writes, 0, "already-correct derived master must not churn writes")
    end)

    H.test("WT #611 preserves unknown future rows after gear masters", function()
        local mod, data, _, _, mercenary = fixture()
        local future = { setting_id = "future_weapon_note", type = "text" }
        mercenary.sub_widgets[#mercenary.sub_widgets + 1] = future
        Masters.build_widgets(mod, data)
        H.equal(mercenary.sub_widgets[#mercenary.sub_widgets], future)
    end)

    H.test("WT #611 master cascade cannot cross a receiving career", function()
        local mod, data, values, writes = fixture()
        Masters.build_widgets(mod, data)
        values.wtmaster_es_mercenary_melee_kerillian = true
        Masters.on_master_changed(mod, "wtmaster_es_mercenary_melee_kerillian")
        H.equal(#writes, 1)
        H.equal(writes[1].id, "unlock_es_mercenary_we_glaive")
        H.equal(writes[1].value, true)
        H.equal(values.unlock_es_huntsman_we_glaive, nil,
            "Mercenary master must not write Huntsman's weapon")
    end)

    H.test("WT #611 child change recomputes only its corresponding master", function()
        local mod, data, values, writes = fixture()
        Masters.build_widgets(mod, data)
        values.unlock_es_mercenary_we_glaive = false
        values.wtmaster_es_mercenary_melee_kerillian = true
        values.wtmaster_es_huntsman_melee_kerillian = true
        Masters.on_child_changed(mod, "unlock_es_mercenary_we_glaive")
        H.equal(#writes, 1)
        H.equal(writes[1].id, "wtmaster_es_mercenary_melee_kerillian")
        H.equal(writes[1].value, false)
        H.equal(values.wtmaster_es_huntsman_melee_kerillian, true)
    end)

    H.test("WT #611 seed derives each career master independently", function()
        local mod, data, values, writes = fixture()
        Masters.build_widgets(mod, data)
        values.unlock_es_mercenary_es_sword = true
        values.unlock_es_huntsman_es_sword = false
        Masters.seed(mod)
        H.equal(values.wtmaster_es_mercenary_melee_kruber, true)
        H.equal(values.wtmaster_es_huntsman_melee_kruber and true or false, false)
        H.truthy(#writes > 0)
    end)

    H.test("WT #611 master style uses GUI Tweaker font_button_normal", function()
        local previous = _G.Colors
        _G.Colors = {
            get_color_table_with_alpha = function(name, alpha)
                H.equal(name, "font_button_normal")
                H.equal(alpha, 255)
                return { 255, 160, 146, 101 }
            end,
        }
        local master_widget = { style = { text = { text_color = { 255, 255, 255, 255 } } } }
        local weapon_widget = { style = { text = { text_color = { 255, 255, 255, 255 } } } }
        H.equal(Masters.style_master_widget(master_widget,
            "wtmaster_es_mercenary_melee_kruber"), true)
        H.deep_equal(master_widget.style.text.text_color, { 255, 160, 146, 101 })
        H.equal(Masters.style_master_widget(weapon_widget,
            "unlock_es_mercenary_es_sword"), false)
        H.deep_equal(weapon_widget.style.text.text_color, { 255, 255, 255, 255 })
        _G.Colors = previous
    end)

    H.test("WT #611 advanced gear parents receive GUI Tweaker accent in both streams", function()
        local paths = {
            "/gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_view.lua",
            "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua",
        }
        for _, relative in ipairs(paths) do
            local file = assert(io.open(repo_root .. relative, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(source:find("row._advanced_parent_accent = true", 1, true),
                relative .. " must mark and style gear-parent rows")
            H.truthy(source:find(
                "accent[1], accent[2], accent[3], accent[4] = 255, 160, 146, 101",
                1, true), relative .. " must use the warm-tan menu accent")
        end
    end)
end
