return function(H, repo_root)
    local cos_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
    local persist_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua"
    local cwv_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local cos = read(cos_path)
    local persist = read(persist_path)
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
        H.truthy(cos:find("LA_PERSIST.clear_offhand(entry.backend_id, entry.hand_field)", 1, true))
    end)

    H.test("dual offhand render and peer replay reuse bounded existing surfaces", function()
        H.truthy(cos:find("mod._send_offhand_mesh", 1, true))
        H.truthy(cos:find("mod._store_offhand_mesh_recv", 1, true))
        H.truthy(cos:find("mod._offhand_mesh_by_peer", 1, true))
        H.truthy(cos:find("HUSK-VANILLA-SWAP", 1, true))
        H.truthy(cos:find("_override_package_ready(unit_path)", 1, true))
        H.truthy(cos:find("_la_self_rebroadcast_pending = true", 1, true))
        H.truthy(cos:find('mod:network_send("cos_la_apply"', 1, true))
        H.equal(cos:find('mod:network_register("cos_dual_offhand', 1, true), nil)
    end)
end
