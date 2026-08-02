-- Issue #915: the CWV Maul rendered a 1H sword because
-- _register_macesword_mace_maul_illusions harvested illusion sources by
-- scanning ItemMasterList for matching_item_key == "es_dual_wield_hammer_sword"
-- WITHOUT provenance. CWV's own Sword and Mace base skin borrows that vanilla
-- matching key for template resolution (DEVELOPMENT.md apply-crash rule) while
-- authoring a SWORD in right_hand_unit (inverse hand layout), so the scan
-- copied a sword mesh into the Maul picker as
-- cwv_es_maul_cwv_es_sword_and_mace_skin.
--
-- Vanilla family provenance (decompiled source):
--   scripts/settings/equipment/item_master_list_paperweight.lua:89-103
--     es_dual_wield_hammer_sword: right = wpn_emp_mace_04_t2 (MACE right hand)
--   scripts/settings/equipment/weapon_skins_paperweight.lua:171-212, 263-274
--     family skins skin_01/skin_02/skin_02_runed_01 all carry MACE right hands.
--
-- These tests pin the #704 ownership filter (`not entry.cwv_owner_item_type`)
-- on EVERY vanilla-family illusion-source scan, exercise the shipped scan
-- predicates against polluted fixture registries, and exercise the shipped
-- stale-generation scrub that cleans a previously polluted Maul picker pool.

return function(H, repo_root)
    local cwv = require("cwv_source").combined(repo_root)

    local function extract_scan(source, function_name)
        local fn_at = assert(source:find("local function " .. function_name .. "()", 1, true),
            function_name .. " not found")
        local scan_at = assert(source:find("for skin_key, entry in pairs(ItemMasterList) do", fn_at, true),
            function_name .. " has no ItemMasterList scan")
        local if_at = assert(source:find("if ", scan_at, true))
        local then_at = assert(source:find(" then", if_at, true))
        return source:sub(if_at + 3, then_at - 1), scan_at
    end

    local function compile_predicate(condition_text)
        local chunk = assert(loadstring(
            "return function(entry) return (" .. condition_text .. ") and true or false end",
            "scan_predicate"))
        return chunk()
    end

    H.test("every CWV illusion-source ItemMasterList scan filters CWV-owned rows", function()
        local scans = 0
        local search_from = 1
        while true do
            local scan_at = cwv:find("for skin_key, entry in pairs(ItemMasterList) do", search_from, true)
            if not scan_at then break end
            local window = cwv:sub(scan_at, scan_at + 1400)
            local append_at = window:find("source_keys[#source_keys + 1]", 1, true)
                or window:find("pool[#pool + 1]", 1, true)
            if window:find("entry.matching_item_key ==", 1, true) and append_at then
                scans = scans + 1
                local condition = window:sub(1, append_at)
                H.truthy(condition:find("not entry.cwv_owner_item_type", 1, true),
                    "unfiltered family scan at combined-source offset " .. scan_at)
            end
            search_from = scan_at + 1
        end
        -- dual swords (es_1h_sword), dual maces (es_1h_mace), maul
        -- (es_dual_wield_hammer_sword), rapier (wh_fencing_sword), and the
        -- sword-and-mace pair pools (#704). A lower count means the sweep
        -- went blind, not that the scans are clean.
        H.truthy(scans >= 5, "expected at least 5 family scans, saw " .. scans)
    end)

    H.test("shipped Maul scan predicate admits only vanilla mace-and-sword skins", function()
        local condition = extract_scan(cwv, "_register_macesword_mace_maul_illusions")
        H.truthy(condition:find('entry.matching_item_key == "es_dual_wield_hammer_sword"', 1, true))
        local admits = compile_predicate(condition)

        -- item_master_list_weapon_skins.lua:754-765 (skin_01, mace right hand)
        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "es_dual_wield_hammer_sword",
            right_hand_unit = "units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2",
        }), true)
        -- item_master_list_paperweight.lua:163-175 (default base skin row)
        H.equal(admits({
            base_skin_item = true,
            item_type = "weapon_skin",
            matching_item_key = "es_dual_wield_hammer_sword",
        }), true)
        -- The #915 polluter: CWV's inverse-layout base skin (sword right hand).
        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "es_dual_wield_hammer_sword",
            cwv_owner_item_type = "cwv_es_sword_and_mace",
            right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
        }), false)
        -- Foreign family and non-table rows never pass.
        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "es_1h_sword",
        }), false)
        H.equal(admits("not_a_table"), false)
    end)

    H.test("shipped dual-mace scan predicate rejects Cudgel and Dawi Mace base skins", function()
        local condition = extract_scan(cwv, "_register_es_1h_mace_dual_illusions")
        H.truthy(condition:find('entry.matching_item_key == "es_1h_mace"', 1, true))
        local admits = compile_predicate(condition)

        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "es_1h_mace",
            right_hand_unit = "units/weapons/player/wpn_emp_mace_02_t1/wpn_emp_mace_02_t1",
        }), true)
        -- cwv_es_cudgel_skin borrows es_1h_mace with a mace+sword-family mesh.
        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "es_1h_mace",
            cwv_owner_item_type = "cwv_es_cudgel",
            right_hand_unit = "units/weapons/player/wpn_emp_mace_04_t2/wpn_emp_mace_04_t2",
        }), false)
        -- cwv_dr_dawi_mace_skin borrows es_1h_mace with a DWARF placeholder mesh.
        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "es_1h_mace",
            cwv_owner_item_type = "cwv_dr_dawi_mace",
            right_hand_unit = "units/weapons/player/wpn_dw_hammer_01_t1/wpn_dw_hammer_01_t1",
        }), false)
    end)

    H.test("shipped rapier scan predicate rejects the CWV rapier base skin", function()
        local condition = extract_scan(cwv, "_register_rapier_illusions")
        H.truthy(condition:find('entry.matching_item_key == "wh_fencing_sword"', 1, true))
        local admits = compile_predicate(condition)

        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "wh_fencing_sword",
            right_hand_unit = "units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1",
        }), true)
        -- cwv_es_rapier_skin borrows wh_fencing_sword; re-admitting it would
        -- duplicate the default mesh inside the Rapier picker.
        H.equal(admits({
            item_type = "weapon_skin",
            matching_item_key = "wh_fencing_sword",
            cwv_owner_item_type = "cwv_es_rapier",
            right_hand_unit = "units/weapons/player/wpn_fencingsword_01_t1/wpn_fencingsword_01_t1",
        }), false)
    end)

    H.test("shipped stale-generation scrub prunes CWV-sourced Maul picker entries", function()
        local scrub_at = assert(cwv:find("-- #915 stale-generation scrub", 1, true))
        local scrub_end = assert(cwv:find("local single_hand_display", scrub_at, true))
        local scrub_source = cwv:sub(scrub_at, scrub_end - 1)
        H.truthy(scrub_source:find("table.remove(tier, i)", 1, true))

        local env = {
            ItemMasterList = {
                es_dual_wield_hammer_sword_skin_01 = {
                    item_type = "weapon_skin",
                    matching_item_key = "es_dual_wield_hammer_sword",
                },
                cwv_es_sword_and_mace_skin = {
                    item_type = "weapon_skin",
                    matching_item_key = "es_dual_wield_hammer_sword",
                    cwv_owner_item_type = "cwv_es_sword_and_mace",
                },
            },
            WeaponSkins = {
                skin_combinations = {
                    cwv_es_maul_skins = {
                        exotic = {
                            "cwv_es_maul_skin",
                            "cwv_es_maul_cwv_es_sword_and_mace_skin",
                            "cwv_es_maul_es_dual_wield_hammer_sword_skin_01",
                        },
                    },
                },
            },
            rawget = rawget,
            table = table,
            type = type,
            pairs = pairs,
        }
        local chunk = assert(loadstring(scrub_source, "stale_scrub"))
        setfenv(chunk, env)
        chunk()

        local tier = env.WeaponSkins.skin_combinations.cwv_es_maul_skins.exotic
        H.deep_equal(tier, {
            "cwv_es_maul_skin",
            "cwv_es_maul_es_dual_wield_hammer_sword_skin_01",
        })
    end)

    H.test("runtime census pins Maul illusion provenance (#915)", function()
        local render_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_regression_render.lua"
        local file = assert(io.open(render_path, "rb"))
        local render = file:read("*a")
        file:close()
        H.truthy(render:find("issue915_maul_illusion_vanilla_provenance", 1, true))
        H.truthy(render:find("Maul pool admitted CWV-owned source: ", 1, true))
        H.truthy(render:find("Maul illusion carries non-vanilla right hand: ", 1, true))
    end)
end
