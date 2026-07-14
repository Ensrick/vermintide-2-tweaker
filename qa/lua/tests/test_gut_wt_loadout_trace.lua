return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_wt_loadout_trace_core.lua"
    local Core = assert(loadfile(path))()

    local function fields(result)
        return {
            phase = "apply", career = "we_maidenguard", slot = "slot_melee",
            index = 1, backend_id = "ABC", item_key = "es_2h_heavy_spear",
            can_wield = false, result = result,
        }
    end

    H.test("GUT WT loadout trace deduplicates identical lifecycle outcomes", function()
        local state = Core.new(24)
        H.truthy(Core.take(state, fields("served-store-yes")))
        H.equal(Core.take(state, fields("served-store-yes")), false)
        H.truthy(Core.take(state, fields("official-fallback-resolve-no")))
        H.equal(state.count, 2)
    end)

    H.test("GUT WT loadout trace obeys its hard record cap", function()
        local state = Core.new(2)
        H.truthy(Core.take(state, fields("one")))
        H.truthy(Core.take(state, fields("two")))
        H.equal(Core.take(state, fields("three")), false)
        H.equal(state.count, 2)
    end)

    H.test("GUT issue 354 runtime trace is selected-row and WT filtered", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find('wt:get(setting_id) == true', 1, true))
        H.truthy(source:find('if idx == entry.selected_index then', 1, true))
        H.truthy(source:find('"[gut:354] phase=%s', 1, true))
    end)
end
