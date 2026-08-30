return function(H, repo_root)
    local streams = {
        {
            name = "stable",
            root = repo_root .. "/gui_tweaker/scripts/mods/gui_tweaker/",
            recognizes_own_dev = false,
        },
        {
            name = "dev",
            root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/",
            recognizes_own_dev = true,
        },
    }

    local function register_policy_tests(stream)
        local Policy = assert(loadfile(stream.root .. "_mod_tweaker_disabled_sections.lua"))()
        local prefix = stream.name .. " Mod Tweaker "

        H.test(prefix .. "recognizes both Tweaker Weapons streams", function()
            H.equal(true, Policy.is_author_mod("gut"))
            H.equal(stream.recognizes_own_dev, Policy.is_author_mod("gut_dev"))
            H.equal(true, Policy.is_author_mod("wt"))
            H.equal(true, Policy.is_author_mod("wt_dev"))
            H.equal(false, Policy.is_author_mod("HideBuffs"))
            H.equal(false, Policy.is_author_mod("Crosshair Kill Confirmation"))
        end)

        H.test(prefix .. "equipment layout counts disabled installed members", function()
            local roles = { wt = "weapons", character_weapon_variants = "cwv" }
            local members, count = Policy.select_members({
                { mod_id = "wt", enabled = true },
                { mod_id = "character_weapon_variants", enabled = false },
            }, roles)
            H.equal(2, count)
            H.equal(false, members.cwv.enabled)
        end)

        H.test(prefix .. "alias selection prefers the enabled crafting stream", function()
            local roles = { cim = "crafting", cim_dev = "crafting" }
            local members, count = Policy.select_members({
                { mod_id = "cim", enabled = false },
                { mod_id = "cim_dev", enabled = true },
            }, roles)
            H.equal(1, count)
            H.equal("cim_dev", members.crafting.mod_id)
        end)

        H.test(prefix .. "Weapons collapsible selects wt_dev and preserves its rows", function()
            local dev_widgets = {
                { mod_name = "wt_dev", readable_mod_name = "Tweaker: Weapons Dev" },
                { setting_id = "weapon_availability", type = "group", depth = 1 },
                { setting_id = "enable_dev_anim_picker", type = "checkbox", depth = 1 },
                { setting_id = "wt_dev_hold_pose", type = "group", depth = 1 },
            }
            local members, count = Policy.select_equipment_members({
                { mod_id = "wt", enabled = false, widgets = {
                    { mod_name = "wt" }, { setting_id = "weapon_availability" },
                } },
                { mod_id = "wt_dev", enabled = true, widgets = dev_widgets },
                { mod_id = "character_weapon_variants", enabled = true, widgets = {
                    { mod_name = "character_weapon_variants" },
                    { setting_id = "cwv_weapon_availability" },
                } },
            })

            H.equal(2, count)
            H.equal("wt_dev", members.weapons.mod_id)
            H.equal(dev_widgets, members.weapons.widgets,
                "policy must preserve the selected VMF widget list")
            H.equal("weapon_availability", members.weapons.widgets[2].setting_id)
            H.equal("enable_dev_anim_picker", members.weapons.widgets[3].setting_id)
            H.equal("wt_dev_hold_pose", members.weapons.widgets[4].setting_id)
        end)

        H.test(prefix .. "twins synthesize the Weapons collapsible", function()
            for _, filename in ipairs({ "_mod_tweaker_state.lua", "_mod_tweaker_view.lua" }) do
                local file = assert(io.open(stream.root .. filename, "rb"))
                local source = file:read("*a")
                file:close()

                H.truthy(source:find("disabled_sections.is_author_mod(mod_name)", 1, true),
                    stream.name .. " " .. filename .. " must use shared authored-mod discovery")
                H.truthy(source:find("disabled_sections.select_equipment_members(cats)", 1, true),
                    stream.name .. " " .. filename .. " must use shared Equipment aliases")
                H.truthy(source:find('"__equip_weapons"', 1, true),
                    stream.name .. " " .. filename .. " must create the Weapons collapsible")
                H.truthy(source:find("_add_member(members.weapons, 1)", 1, true),
                    stream.name .. " " .. filename .. " must copy Tweaker: Weapons rows")
                H.equal(nil, source:find("local _MY_MODS", 1, true),
                    stream.name .. " " .. filename .. " must not duplicate authored-mod aliases")
                H.equal(nil, source:find("local _EQUIP_ROLE", 1, true),
                    stream.name .. " " .. filename .. " must not duplicate Equipment aliases")
            end
        end)

        H.test(prefix .. "disabled integration keeps only its explained header", function()
            local widgets = {
                { setting_id = "before", depth = 0 },
                { setting_id = "ui_tweaks", type = "group", depth = 1 },
                { setting_id = "child_a", depth = 2 },
                { setting_id = "child_group", type = "group", depth = 2 },
                { setting_id = "grandchild", depth = 3 },
                { setting_id = "after", depth = 1 },
            }
            local filtered, found = Policy.disable_group_subtree(widgets, "ui_tweaks")
            H.truthy(found)
            H.equal(3, #filtered)
            H.equal("ui_tweaks", filtered[2].setting_id)
            H.equal(true, filtered[2].disabled)
            H.equal("Disabled in VMF", filtered[2].tooltip)
            H.equal("after", filtered[3].setting_id)
            H.equal(nil, widgets[2].disabled, "VMF source widgets must not be mutated")
        end)
    end

    for _, stream in ipairs(streams) do
        register_policy_tests(stream)
    end

    local runtime_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_runtime_gates.lua"

    H.test("Mod Tweaker runtime gates compose and fail closed", function()
        local Gates = assert(loadfile(runtime_path))()
        local alerts = {}
        Gates.init_dbg(nil, function(fmt, ...)
            alerts[#alerts + 1] = string.format(fmt, ...)
        end)

        local parity_ready = true
        H.truthy(Gates.register("peer-presence", {
            mod_id = "character_weapon_variants",
            setting_ids = { "throwing_spear", "throwing_axe" },
            evaluate = function()
                return parity_ready, "Disabled while Rain lacks Career Weapon Variants."
            end,
        }))
        H.truthy(Gates.register("catalog-proof", {
            mod_id = "character_weapon_variants",
            setting_ids = { "throwing_spear" },
            evaluate = function() return true end,
        }))

        H.equal(false, Gates.status("character_weapon_variants", "throwing_spear"))
        parity_ready = false
        local blocked, reason, gate_id = Gates.status(
            "character_weapon_variants", "throwing_spear")
        H.equal(true, blocked)
        H.equal("Disabled while Rain lacks Career Weapon Variants.", reason)
        H.equal("peer-presence", gate_id)

        H.truthy(Gates.register("catalog-proof", {
            mod_id = "character_weapon_variants",
            setting_ids = { "throwing_spear" },
            evaluate = function() error("catalog unavailable") end,
        }))
        parity_ready = true
        blocked, reason, gate_id = Gates.status(
            "character_weapon_variants", "throwing_spear")
        H.equal(true, blocked)
        H.equal("Unavailable because multiplayer safety could not be confirmed.", reason)
        H.equal("catalog-proof", gate_id)
        H.equal(1, #alerts)
        Gates.status("character_weapon_variants", "throwing_spear")
        H.equal(1, #alerts, "repeated predicate failures must not spam logs per frame")
    end)

    H.test("Mod Tweaker drops edits gated after staging", function()
        local Gates = assert(loadfile(runtime_path))()
        Gates.register("late-join", {
            mod_id = "character_weapon_variants",
            setting_ids = { "throwing_spear" },
            evaluate = function() return false, "A peer lacks CWV." end,
        })
        local pending = { character_weapon_variants = {
            throwing_spear = true, local_visual = true,
        } }
        local blocked_count = Gates.prune_pending(
            pending, { "character_weapon_variants" })
        H.equal(1, blocked_count)
        H.equal(nil, pending.character_weapon_variants.throwing_spear)
        H.equal(true, pending.character_weapon_variants.local_visual)
    end)

    H.test("Mod Tweaker runtime-gated rows restore native state live", function()
        local Gates = assert(loadfile(runtime_path))()
        local available = false
        Gates.register("live-peer-state", {
            mod_id = "character_weapon_variants",
            setting_ids = { "throwing_spear" },
            evaluate = function()
                return available, "Disabled while Rain lacks Career Weapon Variants."
            end,
        })
        local row = {
            _readonly = false,
            _tip_desc = "Enable the throwing spear.",
            style = { label = { text_color = { 255, 160, 146, 101 } } },
        }

        H.equal(true, Gates.apply_row(row,
            "character_weapon_variants", "throwing_spear"))
        H.equal(true, row._readonly)
        H.equal(true, row._runtime_gate_disabled)
        H.equal("Disabled while Rain lacks Career Weapon Variants.", row._tip_desc)
        H.equal(128, row.style.label.text_color[1])

        available = true
        H.equal(false, Gates.apply_row(row,
            "character_weapon_variants", "throwing_spear"))
        H.equal(false, row._readonly)
        H.equal(nil, row._runtime_gate_disabled)
        H.equal("Enable the throwing spear.", row._tip_desc)
        H.equal(255, row.style.label.text_color[1])
        H.equal(160, row.style.label.text_color[2])
        H.equal(146, row.style.label.text_color[3])
        H.equal(101, row.style.label.text_color[4])
    end)

    H.test("both Mod Tweaker paths refresh runtime gates before row input", function()
        local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
        for _, filename in ipairs({
            "_mod_tweaker_view.lua",
            "_mod_tweaker_state.lua",
            "_mod_tweaker_view_interaction.lua",
            "_mod_tweaker_state_interaction.lua",
        }) do
            local file = assert(io.open(root .. filename, "rb"))
            local source = file:read("*a")
            file:close()
            H.truthy(source:find("apply_runtime_gate", 1, true),
                filename .. " must consume the shared runtime-gate API")
        end
    end)

    H.test("GUT runtime suite pins the issue 371 public API", function()
        local contract_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts.lua"
        local file = assert(io.open(contract_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('"issue371_runtime_gate_api"', 1, true))
        for _, method in ipairs({
            "register_runtime_gate",
            "unregister_runtime_gate",
            "runtime_gate_status",
            "apply_runtime_gate",
            "prune_runtime_gated_pending",
        }) do
            H.truthy(source:find('"' .. method .. '"', 1, true),
                "runtime suite must require " .. method)
        end
    end)
end
