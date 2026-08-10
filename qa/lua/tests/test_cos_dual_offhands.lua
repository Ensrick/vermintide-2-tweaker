return function(H, repo_root)
    local cos_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
    local lifecycle_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle.lua"
    local persist_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua"
    local commit_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_commit_policy.lua"
    local diagnostics_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_diagnostics.lua"
    local cwv_family_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_cwv_family_contract.lua"
    local cwv_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
    local cim_path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/illusion_swap.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local entry_only = read(cos_path)
    local view_lifecycle = read(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua")
    -- #1159: the exit-time OFFHAND_COMMIT.drain moved out of the entry into the
    -- view lifecycle owner, so it joins the offhand-family source this test reads.
    -- #1159: the husk vanilla-offhand mesh swap and the live-body selection
    -- override moved out of the entry with the BackendUtils.get_item_units seam,
    -- so the equipment-assembly owner joins the offhand-family source too.
    local equipment_assembly = read(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua")
    local cos = entry_only
        .. read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_catalog.lua")
        .. read(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_picker.lua")
        .. view_lifecycle
        .. equipment_assembly
    local lifecycle = read(lifecycle_path)
    local persist = read(persist_path)
    local commit = read(commit_path)
    local diagnostics = read(diagnostics_path)
    local cwv_family = assert(dofile(cwv_family_path))
    local cim = read(cim_path)
    local cwv = require("cwv_source").combined(repo_root)

    H.test("native Dual Skullsplitters use row one plus one independent offhand", function()
        H.truthy(cos:find("wh_dual_hammer = {", 1, true))
        H.truthy(cos:find('skin_table = "wh_dual_hammer_skins"', 1, true))
        H.truthy(cos:find("if is_multi_mount and not is_independent_dual", 1, true))
        H.truthy(cos:find('name = "Follow Main Illusion"', 1, true))
        H.truthy(cos:find('follow_main = true', 1, true))
    end)

    H.test("every current CWV dual family has a lazy exact-hand contract", function()
        local families = {
            "cwv_es_dual_swords",
            "cwv_es_sword_and_mace",
            "cwv_es_dual_axes",
            "cwv_wh_dual_axes",
            "cwv_es_dual_maces",
            "cwv_wh_dual_maces",
            "cwv_es_dual_warpriest_hammers",
        }
        for _, item_type in ipairs(families) do
            H.truthy(cwv:find('item_key        = "' .. item_type .. '"', 1, true)
                or cwv:find('item_key = "' .. item_type .. '"', 1, true),
                "CWV source family missing: " .. item_type)
            H.truthy(cos:find(item_type .. " = {", 1, true),
                "Cosmetics hand contract missing: " .. item_type)
        end
        H.truthy(cos:find("mod._discover_cwv_dual_offhand_pools", 1, true))
        H.truthy(cos:find("mod._ensure_independent_dual_pool", 1, true))
    end)

    H.test("dual offhands persist by exact item and hand and fail closed", function()
        H.truthy(persist:find("_state.offhands[backend_id][hand_field]", 1, true))
        H.truthy(persist:find("unit_path = unit_path", 1, true))
        H.truthy(cos:find("candidate.unit == rec.unit_path", 1, true))
        H.truthy(cos:find("mod._dual_offhand_unit_allowed", 1, true))
        H.truthy(cos:find('if hand_field ~= "left_hand_unit" then return false end', 1, true))
        H.truthy(persist:find("M.commit_offhand_entry = function(entry)", 1, true))
        H.truthy(commit:find("persistence.commit_offhand_entry(entry)", 1, true))
        H.truthy(view_lifecycle:find("OFFHAND_COMMIT.drain", 1, true))
        H.equal(entry_only:find("OFFHAND_COMMIT.drain", 1, true), nil)
        H.truthy(cos:find("mod._la_offhand_restore_done = deferred == 0", 1, true))
    end)

    H.test("dual primary and offhand persistence share exact instance identity", function()
        H.truthy(cim:find("mod._cim563_commit_explicit_skin_choice = function(backend_id", 1, true))
        H.truthy(cim:find("mod._cim_get_craft(backend_id)", 1, true))
        H.truthy(cim:find("next_saved[backend_id] = skin_key", 1, true))
        H.truthy(persist:find("_state.offhands[backend_id][hand_field]", 1, true))
        H.truthy(commit:find("persistence.commit_offhand_entry(entry)", 1, true))
    end)

    H.test("dual offhand render and peer replay reuse bounded existing surfaces", function()
        H.truthy(cos:find("mod._send_offhand_mesh", 1, true))
        H.truthy(cos:find("mod._store_offhand_mesh_recv", 1, true))
        H.truthy(cos:find("mod._offhand_mesh_by_peer", 1, true))
        H.truthy(cos:find("HUSK-VANILLA-SWAP", 1, true))
        H.truthy(cos:find("_override_package_ready(unit_path)", 1, true))
        H.truthy(lifecycle:find("_la_self_rebroadcast_pending = true", 1, true))
        H.truthy(cos:find('mod:network_send("cos_la_apply"', 1, true))
        H.equal(cos:find('mod:network_register("cos_dual_offhand', 1, true), nil)
    end)

    H.test("issue 704 picker census is exact bounded and shares setup hook", function()
        H.truthy(diagnostics:find('local _ISSUE704_ITEM_TYPE = "cwv_es_sword_and_mace"', 1, true))
        H.truthy(diagnostics:find("mod._cwv_dual_offhand_contract", 1, true))
        H.truthy(diagnostics:find("COS.classify_issue704_picker_family", 1, true))
        H.truthy(diagnostics:find("_ISSUE704_ENTRY_CAP = 56", 1, true))
        H.truthy(diagnostics:find("_ISSUE704_CAPTURE_CAP = 4", 1, true))
        H.truthy(diagnostics:find("_ISSUE704_SIGNATURE_PART_CAP = 64", 1, true))
        H.truthy(diagnostics:find("_ISSUE704_VALUE_BYTE_CAP = 128", 1, true))
        H.truthy(diagnostics:find('"[cos:704] summary', 1, true))
        H.truthy(diagnostics:find('rawget(_G, "printf")', 1, true))
        H.equal(diagnostics:find('mod:echo("[cos:704]', 1, true), nil)
        H.equal((function()
            local count, at = 0, 1
            while true do
                local found = cos:find('mod:hook("HeroWindowItemCustomization", "_setup_illusions"', at, true)
                if not found then return count end
                count = count + 1
                at = found + 1
            end
        end)(), 1)
        local hook_at = assert(cos:find('mod:hook("HeroWindowItemCustomization", "_setup_illusions"', 1, true))
        local original_at = assert(cos:find("func(self, item)", hook_at, true))
        local pool_at = assert(cos:find("local hand_pools = _get_offhand_options(weapon_key)", original_at, true))
        local capture_at = assert(cos:find("capture_issue704_setup", pool_at, true))
        H.truthy(original_at < pool_at and pool_at < capture_at)
    end)

    H.test("issue 704 production classifier flags a foreign component family", function()
        local old_get_mod, old_printf = _G.get_mod, _G.printf
        local lines = {}
        local fake_mod = {
            _cos = { flush_log = function() end },
            _cwv_dual_offhand_contract = {
                cwv_es_sword_and_mace = {
                    right_hand_unit = { matching_item_key = "es_1h_sword" },
                    left_hand_unit = { matching_item_key = "es_1h_mace" },
                },
            },
            command = function() end,
        }
        _G.get_mod = function() return fake_mod end
        _G.printf = function(format, ...)
            lines[#lines + 1] = string.format(format, ...)
        end
        local ok, err = pcall(dofile, diagnostics_path)
        _G.get_mod, _G.printf = old_get_mod, old_printf
        H.truthy(ok, err)

        local classify = fake_mod._cos.classify_issue704_picker_family
        local provider = fake_mod._cwv_dual_offhand_contract
        H.equal(classify("vanilla", "es_dual_wield_hammer_sword", provider,
            "cwv_es_sword_and_mace"), true)
        H.equal(classify("right_hand_unit", "es_1h_sword", provider), true)
        H.equal(classify("left_hand_unit", "es_1h_mace", provider), true)
        H.equal(classify("left_hand_unit", "es_1h_mace", provider,
            "cwv_dr_dawi_mace"), false)
        H.equal(classify("left_hand_unit", "dr_1h_hammer", provider), false)
        H.equal(classify("left_hand_unit", "es_1h_mace", {}), false)

        _G.printf = function(format, ...)
            lines[#lines + 1] = string.format(format, ...)
        end
        local captured, suspects = fake_mod._cos.capture_issue704_picker({
            weapon_key = "cwv_es_sword_and_mace",
            backend_id = "test-704",
            current_skin = "pair_skin",
            illusion_widgets = {
                { content = { skin_key = "pair_skin" } },
            },
            hand_pools = {
                right_hand_unit = {
                    { source_skin_key = "sword_skin", unit = "sword_unit" },
                },
                left_hand_unit = {
                    { follow_main = true, unit = "" },
                    { source_skin_key = "mace_skin", unit = "mace_unit" },
                    { source_skin_key = "hammer_skin", unit = "hammer_unit" },
                },
            },
            provider_contract = provider,
            item_master_list = {
                pair_skin = {
                    matching_item_key = "es_dual_wield_hammer_sword",
                    cwv_owner_item_type = "cwv_es_sword_and_mace",
                },
                sword_skin = { matching_item_key = "es_1h_sword" },
                mace_skin = { matching_item_key = "es_1h_mace" },
                hammer_skin = {
                    matching_item_key = "es_1h_mace",
                    cwv_owner_item_type = "cwv_dr_dawi_mace",
                },
            },
            weapon_skins = {},
        })
        _G.printf = old_printf
        H.equal(captured, true)
        H.equal(suspects, 1)
        H.truthy(table.concat(lines, "\n"):find("suspects=1", 1, true))

        lines = {}
        local oversized = {}
        for index = 1, 200 do
            oversized[index] = {
                source_skin_key = "hammer_skin_" .. tostring(index)
                    .. string.rep("x", 256),
                unit = string.rep("u", 256),
                name = string.rep("n", 256),
            }
        end
        _G.printf = function(format, ...)
            lines[#lines + 1] = string.format(format, ...)
        end
        local bounded = fake_mod._cos.capture_issue704_picker({
            weapon_key = "cwv_es_sword_and_mace",
            backend_id = "test-704-bounded",
            current_skin = "pair_skin",
            illusion_widgets = {},
            hand_pools = {
                right_hand_unit = {},
                left_hand_unit = oversized,
            },
            provider_contract = provider,
            item_master_list = {},
            weapon_skins = {},
        })
        _G.printf = old_printf
        H.equal(bounded, true)
        H.equal(#lines, 56)
        local bounded_log = table.concat(lines, "\n")
        H.truthy(bounded_log:find("truncated=true", 1, true))
        H.truthy(bounded_log:find("signature_truncated=true", 1, true))
    end)

    H.test("issue 704 borrowed family distinguishes owner from compatibility key", function()
        local vanilla = {
            matching_item_key = "es_1h_mace",
            right_hand_unit = "empire_mace",
        }
        local dawi = {
            matching_item_key = "es_1h_mace",
            cwv_owner_item_type = "cwv_dr_dawi_mace",
            right_hand_unit = "dawi_mace",
        }
        H.equal(cwv_family.SKIN_OWNER_FIELD, "cwv_owner_item_type")
        H.equal(cwv_family.skin_source_allowed(vanilla), true)
        H.equal(cwv_family.skin_source_allowed(dawi), false)
        H.equal(cwv_family.skin_source_allowed(dawi, {
            cwv_dr_dawi_mace = true,
        }), true)
        H.truthy(cos:find("CWV_FAMILY_CONTRACT.skin_source_allowed(", 1, true))
        H.truthy(cos:find("issue704_picker_family = function(surface, family, _, owner_item_type)", 1, true))
        H.truthy(cos:find("mod._cwv_dual_offhand_contract, owner_item_type)", 1, true))
        H.truthy(cwv:find("cwv_owner_item_type = def.item_key", 1, true))
        H.truthy(cwv:find("and not entry.cwv_owner_item_type", 1, true))
    end)
end
