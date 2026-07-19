return function(H, repo_root)
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local data_path = base .. "chaos_wastes_tweaker_dev_data.lua"
    local loc_path = base .. "chaos_wastes_tweaker_dev_localization.lua"
    local main_path = base .. "chaos_wastes_tweaker_dev.lua"
    local meta_path = base .. "_ct_meta_trait_boons.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function realize_catalog()
        local loc
        local adventure = {
            build_loc_entries = function() return {} end,
            build_campaign_dlc_group_widgets = function() return {} end,
            build_cw_scenarios_block = function()
                return { setting_id = "fixture_cw", type = "group", sub_widgets = {} }
            end,
            build_event_missions_block = function()
                return { setting_id = "fixture_event", type = "group", sub_widgets = {} }
            end,
        }
        local missions = {
            build_menu_group = function()
                return { setting_id = "fixture_missions", type = "group", sub_widgets = {} }
            end,
            build_loc_entries = function() return {} end,
        }
        local mod = {
            dofile = function(_, path)
                if path:find("_adventure_pool", 1, true) then return adventure end
                if path:find("_ct_dev_mission_catalog", 1, true) then return missions end
                error("unexpected dependency " .. tostring(path))
            end,
            localize = function(_, key)
                local entry = loc and loc[key]
                return entry and entry.en or "<" .. tostring(key) .. ">"
            end,
        }
        local old_get_mod = get_mod
        get_mod = function() return mod end
        loc = assert(loadfile(loc_path))()
        local data = assert(loadfile(data_path))()
        get_mod = old_get_mod
        return data, loc
    end

    H.test("CT #406 realizes Khaine's Communion once under each Modded Boons surface", function()
        local data = realize_catalog()
        local expected = {
            disable_boon_ct_kill_heal = "disable_boon_mod_boons_group",
            start_boon_ct_kill_heal = "start_boon_mod_boons_group",
        }
        local found = {}
        local function walk(node, parent)
            if type(node) ~= "table" then return end
            local id = node.setting_id
            if expected[id] then
                found[id] = found[id] or {}
                found[id][#found[id] + 1] = parent
            end
            local next_parent = node.type == "group" and id or parent
            for _, field in ipairs({ "widgets", "sub_widgets" }) do
                for _, child in ipairs(node[field] or {}) do walk(child, next_parent) end
            end
        end
        walk(data.options)
        for id, parent in pairs(expected) do
            H.equal(#(found[id] or {}), 1, id .. " must be unique")
            H.equal(found[id][1], parent, id .. " immediate parent")
        end
    end)

    H.test("CT #406 navigation labels say Modded Boons and name the heal boon", function()
        local _, loc = realize_catalog()
        H.truthy(loc.start_boon_mod_boons_group.en:find(
            "Starting Boons: Modded Boons", 1, true))
        H.truthy(loc.disable_boon_mod_boons_group.en:find(
            "Disable Boons: Modded Boons", 1, true))
        H.equal(loc.start_boon_mod_boons_group.en:find("New Scaling Boons", 1, true), nil)
        H.truthy(loc.start_boon_ct_kill_heal.en:find("Khaine's Communion", 1, true))
        H.equal(loc.start_boon_ct_kill_heal.en:find("[Issue", 1, true), nil)
    end)

    H.test("CT #406 uses one canonical power-up registration path", function()
        local source = read(main_path) .. read(meta_path)
        H.truthy(source:find('power_ups.ct_kill_heal = {', 1, true))
        H.truthy(source:find('inject_dormant_boon("ct_kill_heal", "exotic")', 1, true))
        H.truthy(source:find('local CT_KILL_HEAL_AMOUNT = 1', 1, true))
        H.truthy(source:find('DamageUtils.heal_network(unit, unit, CT_KILL_HEAL_AMOUNT, "health_regen")', 1, true))
        H.truthy(source:find('if not (Managers and Managers.player and Managers.player.is_server) then', 1, true))
        H.truthy(source:find('_ct406_log_heal("skip-client", unit, CT_KILL_HEAL_AMOUNT, nil, nil)', 1, true))
        H.truthy(source:find('[ct:406] kill_heal result=', 1, true))
        H.truthy(source:find('local CT406_HEAL_DIAG_CAP = 12', 1, true))
    end)
end
