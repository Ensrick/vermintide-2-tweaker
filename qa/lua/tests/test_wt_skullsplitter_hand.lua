return function(H, repo_root)
    local streams = {
        {
            name = "beta",
            root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            entry = "weapon_tweaker.lua",
        },
        {
            name = "dev",
            root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            entry = "weapon_tweaker_dev.lua",
        },
    }

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    for _, stream in ipairs(streams) do
        local policy = dofile(stream.root .. "_wt_skullsplitter_hand.lua")

        H.test("WT #181 " .. stream.name .. " policy scopes both hands to Kruber", function()
            H.equal(policy.runtime_action("wh_hammer_book", "es_mercenary", "left"),
                "relink_hammer_right")
            H.equal(policy.runtime_action("wh_hammer_book", "es_knight", "right"),
                "hide_book")
            H.equal(policy.runtime_action("wh_hammer_book", "wh_priest", "left"), nil)
            H.equal(policy.runtime_action("es_1h_mace", "es_mercenary", "left"), nil)
            H.equal(policy.runtime_action("wh_hammer_book", "es_mercenary", "unknown"), nil)
        end)

        H.test("WT #181 " .. stream.name .. " resolves and validates right-hand linking", function()
            local linking = { { source = "j_rightweaponattach", target = 0 } }
            local third_person = { wielded = linking, unwielded = linking }
            local weapons = {
                one_handed_hammer_template_1 = {
                    right_hand_attachment_node_linking = {
                        third_person = third_person,
                    },
                },
            }
            local resolved = policy.resolve_right_hand_linking(weapons)
            H.equal(resolved, linking)
            H.equal(policy.resolve_right_hand_third_person(weapons), third_person)
            local ok = policy.validate_linking(resolved,
                function(name) return name == "j_rightweaponattach" end,
                function() return false end)
            H.equal(ok, true)
            local bad, reason = policy.validate_linking(
                { { source = "missing", target = 0 } },
                function() return false end,
                function() return true end)
            H.equal(bad, false)
            H.truthy(reason:find("source node missing", 1, true))
        end)

        H.test("WT #181 " .. stream.name .. " preview rewrite is atomic and non-mutating", function()
            local old_linking = { { source = "j_leftweaponattach", target = 0 } }
            local right_linking = { { source = "j_rightweaponattach", target = 0 } }
            local right_third_person = {
                wielded = right_linking,
                unwielded = { { source = "j_hips", target = 0 } },
            }
            local hammer = {
                left_hand = true,
                unit_name = "illusion_hammer_3p",
                unit_attachment_node_linking = old_linking,
                material_settings_name = "blue_glow",
            }
            local book = { right_hand = true, unit_name = "book_3p" }
            local auxiliary = { unit_name = "auxiliary" }
            local original = { hammer, book, auxiliary }
            local rewritten, hid_book, moved_hammer =
                policy.rewrite_preview_spawn_data(original, right_third_person)

            H.equal(hid_book, true)
            H.equal(moved_hammer, true)
            H.equal(#rewritten, 2)
            H.equal(rewritten[1].right_hand, true)
            H.equal(rewritten[1].left_hand, nil)
            H.equal(rewritten[1].unit_name, "illusion_hammer_3p")
            H.equal(rewritten[1].material_settings_name, "blue_glow")
            H.equal(rewritten[1].unit_attachment_node_linking, right_third_person)
            H.equal(rewritten[1].despawn_both_hands_units, true)
            H.equal(rewritten[2], auxiliary)
            H.equal(hammer.left_hand, true)
            H.equal(hammer.right_hand, nil)
            H.equal(hammer.unit_attachment_node_linking, old_linking)

            -- HeroPreviewer._spawn_item_unit selects `.wielded` / `.unwielded`
            -- after this rewrite. Supplying only the wielded list would therefore
            -- produce a nil link at runtime; reject that incomplete shape.
            local wrong_shape, wrong_hidden, wrong_moved =
                policy.rewrite_preview_spawn_data(original, right_linking)
            H.equal(wrong_shape, original)
            H.equal(wrong_hidden, false)
            H.equal(wrong_moved, false)

            local incomplete = { hammer }
            local unchanged, hidden, moved =
                policy.rewrite_preview_spawn_data(incomplete, right_third_person)
            H.equal(unchanged, incomplete)
            H.equal(hidden, false)
            H.equal(moved, false)
        end)

        H.test("WT #181 " .. stream.name .. " runtime controller relinks only the 3P hammer", function()
            local right = { { source = "j_rightweaponattach", target = 0 } }
            local calls = {}
            local unit_api = {
                alive = function(unit) return unit == "owner" or unit == "hammer" or unit == "book" end,
                has_node = function(unit, node)
                    return (unit == "owner" and node == "j_rightweaponattach")
                        or (unit == "hammer" and node == "root")
                end,
                has_visibility_group = function() return true end,
                set_visibility = function(unit, group, visible)
                    calls[#calls + 1] = { "hide", unit, group, visible }
                end,
                set_unit_visibility = function() error("unexpected visibility fallback") end,
            }
            local args = {
                item_name = "wh_hammer_book",
                career_name = "es_mercenary",
                hand = "left",
                perspective = "owner_or_bot",
                weapon_unit_3p = "hammer",
                owner_unit_3p = "owner",
                world = "world",
                unit_api = unit_api,
                world_api = {
                    unlink_unit = function(world, unit)
                        calls[#calls + 1] = { "unlink", world, unit }
                    end,
                },
                gear_utils = {
                    link = function(world, linking, scene, owner, unit)
                        calls[#calls + 1] = { "link", world, linking, scene, owner, unit }
                    end,
                },
                weapons = {
                    one_handed_hammer_template_1 = {
                        right_hand_attachment_node_linking = {
                            third_person = { wielded = right },
                        },
                    },
                },
            }
            local applied, result = policy.apply_runtime(args)
            H.equal(applied, true)
            H.equal(result, "relinked")
            H.equal(calls[1][1], "unlink")
            H.equal(calls[2][1], "link")
            H.equal(calls[2][3], right)

            args.hand = "right"
            args.weapon_unit_3p = "book"
            local hidden, hide_result = policy.apply_runtime(args)
            H.equal(hidden, true)
            H.equal(hide_result, "hidden")
            H.equal(calls[3][1], "hide")
            H.equal(calls[3][2], "book")
        end)

        H.test("WT #181 " .. stream.name .. " preview controller owns the parallel transaction", function()
            local third_person = {
                wielded = { { source = "j_rightweaponattach", target = 0 } },
                unwielded = { { source = "j_hips", target = 0 } },
            }
            local previewer = {
                _current_career_name = "es_knight",
                _item_info_by_slot = {
                    melee = {
                        spawn_data = {
                            { left_hand = true, unit_name = "illusion_hammer_3p" },
                            { right_hand = true, unit_name = "book_3p" },
                        },
                    },
                },
            }
            local applied, result = policy.apply_preview(previewer, "wh_hammer_book",
                { type = "melee" }, {
                    one_handed_hammer_template_1 = {
                        right_hand_attachment_node_linking = {
                            third_person = third_person,
                        },
                    },
                })
            H.equal(applied, true)
            H.equal(result, "rewritten")
            local spawn_data = previewer._item_info_by_slot.melee.spawn_data
            H.equal(#spawn_data, 1)
            H.equal(spawn_data[1].right_hand, true)
            H.equal(spawn_data[1].unit_name, "illusion_hammer_3p")
            H.equal(spawn_data[1].unit_attachment_node_linking, third_person)
        end)

        H.test("WT #181 " .. stream.name .. " integrates guarded 3P relink without 1P replacement", function()
            -- The #1159 wave-14 slice moved both call sites out of the entry:
            -- apply_runtime into the in-game 3P swap owner, apply_preview into
            -- the menu preview owner. The invariants below are about the whole
            -- wt surface, so assert against entry + both owners.
            local source = read(stream.root .. stream.entry)
                .. read(stream.root .. "_wt_ingame_3p_swap_owner.lua")
                .. read(stream.root .. "_wt_menu_preview_owner.lua")
            local module = read(stream.root .. "_wt_skullsplitter_hand.lua")
            H.truthy(source:find("_wt_skullsplitter_hand_policy.apply_runtime({", 1, true))
            H.truthy(source:find("_wt_skullsplitter_hand_policy.apply_preview(", 1, true))
            H.truthy(module:find("args.world_api.unlink_unit", 1, true))
            H.truthy(module:find("M.validate_linking", 1, true))
            H.truthy(module:find("M.rewrite_preview_spawn_data", 1, true))
            H.truthy(module:find("[wt:181] surface=runtime", 1, true))
            H.truthy(source:find("return v_w3p, v_a3p, v_w1p, v_a1p", 1, true))
            H.equal(module:find("v_w1p", 1, true), nil)
            H.equal(source:find("mark_for_deletion(v_w1p", 1, true), nil)
            H.equal(source:find("World.unlink_unit(world, v_w1p)", 1, true), nil)
        end)
    end
end
